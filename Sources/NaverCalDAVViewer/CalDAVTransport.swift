import Foundation

/// A fully materialized CalDAV HTTP request.
///
/// `CalDAVClient` builds this value after resolving relative CalDAV paths against
/// the configured server URL. Keeping request construction explicit lets tests
/// inspect method, path, headers, and body without opening a real network socket.
struct CalDAVRequest {
    let url: URL
    let method: String
    let depth: String
    let body: String
    let username: String
    let password: String
}

/// Transport boundary for CalDAV network I/O.
///
/// Production code uses `URLSessionCalDAVTransport`; tests inject a fake transport
/// to validate discovery, REPORT, PROPFIND, and multiget fallback behavior without
/// depending on Naver or Google servers.
protocol CalDAVTransport: Sendable {
    func send(_ request: CalDAVRequest) async throws -> (statusCode: Int, data: Data)
}

/// Default CalDAV transport backed by `URLSession`.
///
/// This type owns HTTP header construction and Basic Auth encoding. `CalDAVClient`
/// still owns CalDAV-level diagnostics and status-code handling so fake transports
/// can return raw status/data pairs and exercise the same error path.
struct URLSessionCalDAVTransport: CalDAVTransport {
    func send(_ request: CalDAVRequest) async throws -> (statusCode: Int, data: Data) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue(request.depth, forHTTPHeaderField: "Depth")
        urlRequest.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let login = "\(request.username):\(request.password)"
        guard let loginData = login.data(using: .utf8) else {
            throw CalDAVError.auth("failed to encode credentials")
        }
        let token = loginData.base64EncodedString()
        urlRequest.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = request.body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CalDAVError.network("invalid HTTP response")
        }

        return (http.statusCode, data)
    }
}
