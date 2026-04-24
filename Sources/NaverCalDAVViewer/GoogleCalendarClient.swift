import Foundation

enum GoogleOAuthConfig {
    static var clientID: String {
        localConfig?.clientID ?? ProcessInfo.processInfo.environment["LENDAR_GOOGLE_CLIENT_ID"] ?? ""
    }

    static var clientSecret: String {
        localConfig?.clientSecret ?? ProcessInfo.processInfo.environment["LENDAR_GOOGLE_CLIENT_SECRET"] ?? ""
    }

    static let authURI = "https://accounts.google.com/o/oauth2/auth"
    static let tokenURI = "https://oauth2.googleapis.com/token"
    static let calendarAPIBase = "https://www.googleapis.com/calendar/v3"
    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"

    static var configSearchPaths: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lendar/google-oauth.json"),
        ]
    }

    private static var localConfig: LocalGoogleOAuthConfig? {
        for url in configSearchPaths {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let direct = try? JSONDecoder().decode(LocalGoogleOAuthConfig.self, from: data) {
                return direct
            }
            if let wrapped = try? JSONDecoder().decode(LocalGoogleOAuthInstalledConfig.self, from: data) {
                return wrapped.installed
            }
        }
        return nil
    }
}

private struct LocalGoogleOAuthInstalledConfig: Decodable {
    let installed: LocalGoogleOAuthConfig
}

private struct LocalGoogleOAuthConfig: Decodable {
    let clientID: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

struct GoogleCalendarClient {
    let email: String
    let refreshToken: String
    private let transport: any GoogleAPITransport

    init(
        email: String,
        refreshToken: String,
        transport: any GoogleAPITransport = URLSessionGoogleAPITransport()
    ) {
        self.email = email
        self.refreshToken = refreshToken
        self.transport = transport
    }

    func fetchCalendarItems(rangeStart: Date, rangeEnd: Date) async throws -> FetchResult {
        // Google Calendar uses OAuth + JSON REST APIs, not the Basic Auth CalDAV flow
        // used by Naver. The stored password field is a refresh token for this provider.
        let totalTimer = SyncTimer()
        let tokenTimer = SyncTimer()
        let accessToken = try await refreshAccessToken()
        let tokenTiming = tokenTimer.line("Google token refresh")
        var diagnostics = ["Google Calendar API account: \(email)"]
        diagnostics.append(tokenTiming)

        let calendarTimer = SyncTimer()
        let calendars = try await fetchCalendars(accessToken: accessToken)
        diagnostics.append("Google calendars: \(calendars.count)")
        diagnostics.append(calendarTimer.line("Google calendar list"))

        let calendarResults = try await fetchCalendarsInParallel(
            calendars: calendars,
            accessToken: accessToken,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        diagnostics.append(contentsOf: calendarResults.flatMap(\.diagnostics))
        diagnostics.append(totalTimer.line("Google total"))

        let items = calendarResults.flatMap(\.items)
        return FetchResult(items: items.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }, diagnostics: diagnostics)
    }

    private func fetchCalendarsInParallel(
        calendars: [GoogleCalendar],
        accessToken: String,
        rangeStart: Date,
        rangeEnd: Date
    ) async throws -> [GoogleCalendarFetchResult] {
        try await withThrowingTaskGroup(of: GoogleCalendarFetchResult.self) { group in
            for (index, calendar) in calendars.enumerated() {
                group.addTask {
                    let timer = SyncTimer()
                    let events = try await fetchEvents(
                        calendar: calendar,
                        accessToken: accessToken,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd
                    )
                    return GoogleCalendarFetchResult(
                        index: index,
                        items: events,
                        diagnostics: [
                            "Calendar: \(calendar.summary) events=\(events.count)",
                            timer.line("Google events \(calendar.summary)"),
                        ]
                    )
                }
            }

            var results: [GoogleCalendarFetchResult] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }
        }
    }

    private func refreshAccessToken() async throws -> String {
        let token = try await GoogleHTTP.refreshAccessToken(refreshToken, transport: transport)
        guard let accessToken = token.accessToken, !accessToken.isEmpty else {
            throw CalDAVError.auth("Google access token not returned")
        }
        return accessToken
    }

    private func fetchCalendars(accessToken: String) async throws -> [GoogleCalendar] {
        var components = URLComponents(string: "\(GoogleOAuthConfig.calendarAPIBase)/users/me/calendarList")!
        components.queryItems = [
            URLQueryItem(name: "showHidden", value: "true"),
            URLQueryItem(name: "minAccessRole", value: "reader"),
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        let data = try await transport.data(for: request)
        return try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data).items ?? []
    }

    private func fetchEvents(calendar: GoogleCalendar, accessToken: String, rangeStart: Date, rangeEnd: Date) async throws -> [CalendarItem] {
        var results: [CalendarItem] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "\(GoogleOAuthConfig.calendarAPIBase)/calendars/\(Self.urlPath(calendar.id))/events")!
            components.queryItems = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500"),
                URLQueryItem(name: "timeMin", value: Self.rfc3339(rangeStart)),
                URLQueryItem(name: "timeMax", value: Self.rfc3339(rangeEnd)),
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            var request = authorizedRequest(url: components.url!, accessToken: accessToken)
            request.httpMethod = "GET"
            let data = try await transport.data(for: request)
            let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
            results.append(contentsOf: (decoded.items ?? []).compactMap { event in
                item(from: event, calendar: calendar)
            })
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return results
    }

    private func item(from event: GoogleEvent, calendar: GoogleCalendar) -> CalendarItem? {
        guard event.status?.uppercased() != "CANCELLED" else {
            return nil
        }
        guard let start = parseGoogleDate(event.start), let end = parseGoogleDate(event.end) else {
            return nil
        }
        let isAllDay = event.start?.date != nil
        let colorCode = calendar.backgroundColor.map {
            CalendarColorCatalog.customColorPrefix + $0.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        } ?? "0"
        return CalendarItem(
            type: .event,
            uid: event.id,
            summary: event.summary ?? "(제목 없음)",
            startOrDue: "",
            endOrCompleted: "",
            location: event.location ?? "",
            note: event.description ?? "",
            status: event.status ?? "",
            sourceCalendar: calendar.summary,
            sourceColorCode: colorCode,
            rawFields: [:],
            startDate: start.date,
            endDate: end.date,
            isAllDay: isAllDay
        )
    }

    private func parseGoogleDate(_ value: GoogleEventDate?) -> (date: Date, allDay: Bool)? {
        guard let value else { return nil }
        if let dateTime = value.dateTime, let date = Self.isoFormatter().date(from: dateTime) ?? Self.isoFormatterWithFraction().date(from: dateTime) {
            return (date, false)
        }
        if let rawDate = value.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: rawDate) {
                return (date, true)
            }
        }
        return nil
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func urlPath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func rfc3339(_ date: Date) -> String {
        isoFormatter().string(from: date)
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func isoFormatterWithFraction() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

enum GoogleHTTP {
    static func exchangeAuthorizationCode(
        _ code: String,
        redirectURI: String,
        transport: any GoogleAPITransport = URLSessionGoogleAPITransport()
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: GoogleOAuthConfig.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "code": code,
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ])

        let data = try await transport.data(for: request)
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    static func refreshAccessToken(
        _ refreshToken: String,
        transport: any GoogleAPITransport = URLSessionGoogleAPITransport()
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: GoogleOAuthConfig.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])

        let data = try await transport.data(for: request)
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CalDAVError.network("invalid HTTP response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalDAVError.http(http.statusCode, body)
        }
    }

    static func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(urlForm(key))=\(urlForm(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    static func urlForm(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

struct GoogleTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendar]?
}

private struct GoogleCalendar: Decodable {
    let id: String
    let summary: String
    let backgroundColor: String?
}

private struct GoogleCalendarFetchResult {
    let index: Int
    let items: [CalendarItem]
    let diagnostics: [String]
}

private struct GoogleEventsResponse: Decodable {
    let items: [GoogleEvent]?
    let nextPageToken: String?
}

private struct GoogleEvent: Decodable {
    let id: String
    let status: String?
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleEventDate?
    let end: GoogleEventDate?
}

private struct GoogleEventDate: Decodable {
    let date: String?
    let dateTime: String?
}
