import Foundation

/// Transport boundary for Google OAuth and Calendar REST requests.
///
/// This mirrors the CalDAV transport split: production calls use `URLSession`,
/// while tests inject fake responses for token refresh, calendar-list lookup,
/// event pagination, and HTTP error handling.
protocol GoogleAPITransport: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

/// Default Google API transport backed by `URLSession`.
///
/// It validates HTTP status centrally via `GoogleHTTP.validate`, so callers only
/// receive response data after 2xx status checks have passed.
struct URLSessionGoogleAPITransport: GoogleAPITransport {
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try GoogleHTTP.validate(response: response, data: data)
        return data
    }
}
