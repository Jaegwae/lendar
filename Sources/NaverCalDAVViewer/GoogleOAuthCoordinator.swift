import AppKit
import Foundation
import Network

struct GoogleOAuthResult {
    let email: String
    let refreshToken: String
}

enum GoogleOAuthCoordinator {
    static func authorize() async throws -> GoogleOAuthResult {
        guard !GoogleOAuthConfig.clientID.isEmpty, !GoogleOAuthConfig.clientSecret.isEmpty else {
            let searchedPaths = GoogleOAuthConfig.configSearchPaths
                .map(\.path)
                .joined(separator: "\n")
            throw CalDAVError.auth("Google OAuth 설정을 찾지 못했습니다. sandbox 앱에서는 다음 위치에 google-oauth.json이 필요합니다:\n\(searchedPaths)")
        }

        // Desktop OAuth uses a short-lived loopback HTTP server. The browser returns
        // to 127.0.0.1:<port>/oauth2redirect with a one-time authorization code, which
        // is then exchanged for access/refresh tokens.
        let loopback = try await OAuthLoopbackServer.start()
        let state = UUID().uuidString
        let scope = [
            GoogleOAuthConfig.calendarReadOnlyScope,
            "https://www.googleapis.com/auth/userinfo.email",
            "openid",
        ].joined(separator: " ")

        var components = URLComponents(string: GoogleOAuthConfig.authURI)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: loopback.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            throw CalDAVError.auth("Google OAuth URL 생성 실패")
        }

        await MainActor.run {
            _ = NSWorkspace.shared.open(authURL)
        }

        let callback = try await loopback.waitForCallback()
        guard callback.state == state else {
            throw CalDAVError.auth("Google OAuth state mismatch")
        }

        let transport = URLSessionGoogleAPITransport()
        let token = try await GoogleHTTP.exchangeAuthorizationCode(
            callback.code,
            redirectURI: loopback.redirectURI,
            transport: transport
        )
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty,
              let accessToken = token.accessToken, !accessToken.isEmpty
        else {
            throw CalDAVError.auth("Google refresh token을 받지 못했습니다. 다시 연결해 주세요.")
        }

        let email = try await fetchEmail(accessToken: accessToken, transport: transport)
        return GoogleOAuthResult(email: email, refreshToken: refreshToken)
    }

    private static func fetchEmail(accessToken: String, transport: any GoogleAPITransport) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await transport.data(for: request)
        return try JSONDecoder().decode(GoogleUserInfo.self, from: data).email
    }
}

private struct GoogleUserInfo: Decodable {
    let email: String
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    struct Callback {
        let code: String
        let state: String
    }

    let redirectURI: String
    private let listener: NWListener
    private var continuation: CheckedContinuation<Callback, Error>?

    private init(listener: NWListener, redirectURI: String) {
        self.listener = listener
        self.redirectURI = redirectURI
    }

    static func start() async throws -> OAuthLoopbackServer {
        // Do not use port 0 in redirect_uri. Google will happily accept the URL but the
        // browser cannot callback to a real app listener. Reserve a deterministic local
        // range and pass the actual bound port to the OAuth URL.
        let (listener, port) = try makeListener()
        let server = OAuthLoopbackServer(listener: listener, redirectURI: "http://127.0.0.1:\(port)/oauth2redirect")
        listener.newConnectionHandler = { [weak server] connection in
            server?.handle(connection)
        }
        listener.start(queue: .main)
        return server
    }

    private static func makeListener() throws -> (NWListener, UInt16) {
        for rawPort in 53682 ... 53692 {
            if let port = NWEndpoint.Port(rawValue: UInt16(rawPort)),
               let listener = try? NWListener(using: .tcp, on: port)
            {
                return (listener, UInt16(rawPort))
            }
        }
        let listener = try NWListener(using: .tcp, on: .any)
        return (listener, listener.port?.rawValue ?? 53682)
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                self?.finish(connection: connection, result: .failure(CalDAVError.auth("OAuth callback 수신 실패")))
                return
            }

            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let target = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            guard let url = URL(string: "http://127.0.0.1\(target)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                finish(connection: connection, result: .failure(CalDAVError.auth("OAuth callback URL 파싱 실패")))
                return
            }

            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = query["error"], !error.isEmpty {
                finish(connection: connection, result: .failure(CalDAVError.auth(error)))
                return
            }

            guard let code = query["code"], let state = query["state"] else {
                finish(connection: connection, result: .failure(CalDAVError.auth("OAuth code 누락")))
                return
            }

            finish(connection: connection, result: .success(Callback(code: code, state: state)))
        }
    }

    private func finish(connection: NWConnection, result: Result<Callback, Error>) {
        let html = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html><body><h3>lendar Google 연결이 완료되었습니다.</h3><p>이 창은 닫아도 됩니다.</p></body></html>
        """
        connection.send(content: Data(html.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
        listener.cancel()

        switch result {
        case let .success(callback):
            continuation?.resume(returning: callback)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
