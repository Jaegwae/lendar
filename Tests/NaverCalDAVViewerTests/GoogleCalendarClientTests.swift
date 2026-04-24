import Foundation
@testable import NaverCalDAVViewer
import XCTest

final class GoogleCalendarClientTests: XCTestCase {
    func testFetchCalendarItemsRefreshesTokenAndFetchesPagedEvents() async throws {
        let transport = FakeGoogleTransport(responses: [
            googleJSON("""
            {"access_token":"access-token","expires_in":3600}
            """),
            googleJSON("""
            {"items":[{"id":"primary","summary":"Primary","backgroundColor":"#336699"}]}
            """),
            googleJSON("""
            {
              "items": [
                {
                  "id": "event-1",
                  "status": "confirmed",
                  "summary": "Timed",
                  "description": "Notes",
                  "location": "Room",
                  "start": {"dateTime": "2026-04-22T10:00:00Z"},
                  "end": {"dateTime": "2026-04-22T11:00:00Z"}
                },
                {
                  "id": "event-cancelled",
                  "status": "cancelled",
                  "summary": "Cancelled",
                  "start": {"dateTime": "2026-04-22T12:00:00Z"},
                  "end": {"dateTime": "2026-04-22T13:00:00Z"}
                }
              ],
              "nextPageToken": "next"
            }
            """),
            googleJSON("""
            {
              "items": [
                {
                  "id": "event-2",
                  "status": "confirmed",
                  "summary": "All day",
                  "start": {"date": "2026-04-23"},
                  "end": {"date": "2026-04-24"}
                }
              ]
            }
            """),
        ])
        let client = GoogleCalendarClient(
            email: "demo@example.com",
            refreshToken: "refresh-token",
            transport: transport
        )

        let result = try await client.fetchCalendarItems(
            rangeStart: Date(timeIntervalSince1970: 0),
            rangeEnd: Date(timeIntervalSince1970: 86400)
        )
        let requests = await transport.capturedRequests()

        XCTAssertEqual(result.items.map(\.summary), ["Timed", "All day"])
        XCTAssertEqual(result.items[0].sourceColorCode, "custom:336699")
        XCTAssertFalse(result.items[0].isAllDay)
        XCTAssertTrue(result.items[1].isAllDay)
        XCTAssertTrue(result.diagnostics.contains("Google Calendar API account: demo@example.com"))
        XCTAssertTrue(result.diagnostics.contains("Google calendars: 1"))
        XCTAssertTrue(result.diagnostics.contains("Calendar: Primary events=2"))
        XCTAssertTrue(result.diagnostics.contains { $0.hasPrefix("Google token refresh: ") })
        XCTAssertTrue(result.diagnostics.contains { $0.hasPrefix("Google events Primary: ") })
        XCTAssertTrue(result.diagnostics.contains { $0.hasPrefix("Google total: ") })

        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].url?.absoluteString, GoogleOAuthConfig.tokenURI)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertTrue(requests[0].bodyText.contains("client_id="))
        XCTAssertTrue(requests[0].bodyText.contains("client_secret="))
        XCTAssertTrue(requests[0].bodyText.contains("grant_type=refresh_token"))
        XCTAssertTrue(requests[0].bodyText.contains("refresh_token=refresh-token"))
        XCTAssertEqual(requests[1].url?.path, "/calendar/v3/users/me/calendarList")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(requests[2].url?.path, "/calendar/v3/calendars/primary/events")
        XCTAssertTrue(requests[2].url?.query?.contains("singleEvents=true") == true)
        XCTAssertTrue(requests[2].url?.query?.contains("showDeleted=false") == true)
        XCTAssertTrue(requests[3].url?.query?.contains("pageToken=next") == true)
    }

    func testGoogleHTTPThrowsHTTPErrorFromTransportValidation() async {
        let transport = FakeGoogleTransport(responses: [
            FakeGoogleResponse(statusCode: 401, data: Data("bad token".utf8)),
        ])

        do {
            _ = try await GoogleHTTP.refreshAccessToken("refresh-token", transport: transport)
            XCTFail("Expected refresh token failure")
        } catch let error as CalDAVError {
            XCTAssertEqual(error.localizedDescription, "HTTP error: status=401, body=bad token")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor FakeGoogleTransport: GoogleAPITransport {
    private let responses: [FakeGoogleResponse]
    private var index = 0
    private(set) var requests: [URLRequest] = []

    init(responses: [FakeGoogleResponse]) {
        self.responses = responses
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }

    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        guard index < responses.count else {
            XCTFail("Unexpected Google request: \(request.url?.absoluteString ?? "<nil>")")
            return Data()
        }

        let response = responses[index]
        index += 1
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        try GoogleHTTP.validate(response: http, data: response.data)
        return response.data
    }
}

private struct FakeGoogleResponse {
    let statusCode: Int
    let data: Data

    init(statusCode: Int = 200, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

private func googleJSON(_ value: String) -> FakeGoogleResponse {
    FakeGoogleResponse(data: Data(value.utf8))
}

private extension URLRequest {
    var bodyText: String {
        httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
