import Foundation
@testable import NaverCalDAVViewer
import XCTest

final class CalDAVClientTransportTests: XCTestCase {
    func testDirectCalendarPathUsesReportAndParsesItems() async throws {
        let transport = FakeCalDAVTransport(responses: [
            FakeCalDAVResponse(
                method: "REPORT",
                path: "/caldav/v2/demo/events",
                data: calendarDataResponse(summary: "Direct event")
            ),
        ])
        let client = CalDAVClient(
            username: "demo",
            appPassword: "secret",
            serverURL: "https://example.com/caldav/v2/demo/events",
            transport: transport
        )

        let result = try await client.fetchCalendarItems()
        let requests = await transport.capturedRequests()

        XCTAssertEqual(result.items.map(\.summary), ["Direct event"])
        XCTAssertEqual(requests.map(\.method), ["REPORT"])
        XCTAssertTrue(requests[0].body.contains(#"<c:comp-filter name="VEVENT" />"#))
        XCTAssertEqual(requests[0].depth, "1")
        XCTAssertEqual(requests[0].username, "demo")
    }

    func testDiscoveryFallsBackToCurrentUserPrincipalWhenManualHomeFails() async throws {
        let transport = FakeCalDAVTransport(responses: [
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/principals/users/demo",
                statusCode: 404,
                data: Data("missing".utf8)
            ),
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/",
                data: currentUserPrincipalResponse("/principals/discovered/")
            ),
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/principals/discovered",
                data: calendarHomeResponse("/calendars/discovered/")
            ),
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/calendars/discovered",
                data: calendarCollectionResponse(href: "/calendars/discovered/work/", displayName: "Work")
            ),
            FakeCalDAVResponse(
                method: "REPORT",
                path: "/calendars/discovered/work",
                data: calendarDataResponse(summary: "Discovered event")
            ),
        ])
        let client = CalDAVClient(
            username: "demo",
            appPassword: "secret",
            transport: transport
        )

        let result = try await client.fetchCalendarItems()
        let requests = await transport.capturedRequests()

        XCTAssertEqual(result.items.map(\.summary), ["Discovered event"])
        XCTAssertEqual(
            requests.map { "\($0.method) \($0.url.path)" },
            [
                "PROPFIND /principals/users/demo",
                "PROPFIND /",
                "PROPFIND /principals/discovered",
                "PROPFIND /calendars/discovered",
                "REPORT /calendars/discovered/work",
            ]
        )
        XCTAssertTrue(result.diagnostics.contains("Manual principal path failed: HTTP error: status=404, body=missing"))
        XCTAssertTrue(result.diagnostics.contains("Discovered principal path: /principals/discovered/"))
    }

    func testCalendarQueryFallsBackToMultigetWhenServerOmitsCalendarData() async throws {
        let transport = FakeCalDAVTransport(responses: [
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/principals/users/demo",
                data: calendarHomeResponse("/calendars/users/demo/")
            ),
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/calendars/users/demo",
                data: calendarCollectionResponse(href: "/calendars/users/demo/work/", displayName: "Work")
            ),
            FakeCalDAVResponse(
                method: "REPORT",
                path: "/calendars/users/demo/work",
                data: Data("<d:multistatus xmlns:d=\"DAV:\" />".utf8)
            ),
            FakeCalDAVResponse(
                method: "PROPFIND",
                path: "/calendars/users/demo/work",
                data: objectListResponse(path: "/calendars/users/demo/work/item.ics")
            ),
            FakeCalDAVResponse(
                method: "REPORT",
                path: "/calendars/users/demo/work",
                data: calendarDataResponse(summary: "Multiget event")
            ),
        ])
        let client = CalDAVClient(
            username: "demo",
            appPassword: "secret",
            transport: transport
        )

        let result = try await client.fetchCalendarItems(
            rangeStart: date(2026, 4, 1),
            rangeEnd: date(2026, 5, 1)
        )
        let requests = await transport.capturedRequests()

        XCTAssertEqual(result.items.map(\.summary), ["Multiget event"])
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "PROPFIND", "REPORT", "PROPFIND", "REPORT"])
        XCTAssertTrue(requests[2].body.contains("<c:time-range"))
        XCTAssertTrue(requests[4].body.contains("<c:calendar-multiget"))
    }
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
}

private actor FakeCalDAVTransport: CalDAVTransport {
    private let responses: [FakeCalDAVResponse]
    private var index = 0
    private(set) var requests: [CalDAVRequest] = []

    init(responses: [FakeCalDAVResponse]) {
        self.responses = responses
    }

    func capturedRequests() -> [CalDAVRequest] {
        requests
    }

    func send(_ request: CalDAVRequest) async throws -> (statusCode: Int, data: Data) {
        requests.append(request)
        guard index < responses.count else {
            XCTFail("Unexpected CalDAV request: \(request.method) \(request.url.path)")
            return (500, Data())
        }

        let response = responses[index]
        index += 1
        XCTAssertEqual(request.method, response.method)
        XCTAssertEqual(request.url.path, response.path)
        return (response.statusCode, response.data)
    }
}

private struct FakeCalDAVResponse {
    let method: String
    let path: String
    let statusCode: Int
    let data: Data

    init(method: String, path: String, statusCode: Int = 200, data: Data) {
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.data = data
    }
}

private func currentUserPrincipalResponse(_ href: String) -> Data {
    Data("""
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:propstat>
          <d:prop>
            <d:current-user-principal><d:href>\(href)</d:href></d:current-user-principal>
          </d:prop>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """.utf8)
}

private func calendarHomeResponse(_ href: String) -> Data {
    Data("""
    <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:propstat>
          <d:prop>
            <c:calendar-home-set><d:href>\(href)</d:href></c:calendar-home-set>
          </d:prop>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """.utf8)
}

private func calendarCollectionResponse(href: String, displayName: String) -> Data {
    Data("""
    <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:href>/calendars/home/</d:href>
      </d:response>
      <d:response>
        <d:href>\(href)</d:href>
        <d:propstat>
          <d:prop>
            <d:displayname>\(displayName)</d:displayname>
            <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
            <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
          </d:prop>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """.utf8)
}

private func calendarDataResponse(summary: String) -> Data {
    Data("""
    <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:propstat>
          <d:prop>
            <c:calendar-data>BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:\(summary.replacingOccurrences(of: " ", with: "-"))
    SUMMARY:\(summary)
    DTSTART:20260422T100000
    DTEND:20260422T110000
    END:VEVENT
    END:VCALENDAR</c:calendar-data>
          </d:prop>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """.utf8)
}

private func objectListResponse(path: String) -> Data {
    Data("""
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>\(path)</d:href>
        <d:propstat>
          <d:prop>
            <d:getcontenttype>text/calendar</d:getcontenttype>
          </d:prop>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """.utf8)
}
