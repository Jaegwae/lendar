import Foundation

/// Basic Auth CalDAV client for manual email-server accounts, especially Naver.
/// Google Calendar intentionally uses GoogleCalendarClient instead of this path.
struct CalDAVClient {
    let username: String
    let appPassword: String
    let baseURL: URL
    private let transport: any CalDAVTransport

    init(
        username: String,
        appPassword: String,
        serverURL: String = "https://caldav.calendar.naver.com",
        transport: any CalDAVTransport = URLSessionCalDAVTransport()
    ) {
        self.username = username
        self.appPassword = appPassword
        self.transport = transport
        baseURL = CalDAVPath.normalizedBaseURL(serverURL)
    }

    private var normalizedUsername: String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var authUsername: String {
        normalizedUsername
    }

    func fetchCalendarItems(rangeStart: Date? = nil, rangeEnd: Date? = nil) async throws -> FetchResult {
        let totalTimer = SyncTimer()
        var diagnostics: [String] = []
        diagnostics.append("Auth username: \(authUsername)")
        diagnostics.append("Server: \(baseURL.absoluteString)")
        diagnostics.append("Manual principal path: \(CalDAVPath.fallbackPrincipalPath(username: normalizedUsername))")
        diagnostics.append("Manual calendar home path: \(CalDAVPath.fallbackCalendarHomePath(username: normalizedUsername))")

        if let directCalendarPath {
            diagnostics.append("Trying direct calendar path: \(directCalendarPath)")
            do {
                let items = try await fetchDirectCalendarItems(
                    calendarPath: directCalendarPath,
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    diagnostics: &diagnostics
                )
                if !items.isEmpty {
                    diagnostics.append("Parsed direct calendar items: \(items.count)")
                    return FetchResult(items: items, diagnostics: diagnostics)
                }
                diagnostics.append("Direct calendar returned no items, falling back to discovery")
            } catch {
                diagnostics.append("Direct calendar failed: \(error.localizedDescription)")
            }
        }

        let homePath: String
        do {
            let manualPrincipal = CalDAVPath.fallbackPrincipalPath(username: normalizedUsername)
            diagnostics.append("Trying manual principal path first")
            homePath = try await discoverCalendarHomePath(principalPath: manualPrincipal, diagnostics: &diagnostics)
        } catch {
            diagnostics.append("Manual principal path failed: \(error.localizedDescription)")

            let principalPath: String
            do {
                principalPath = try await discoverPrincipalPath(diagnostics: &diagnostics)
                diagnostics.append("Discovered principal path: \(principalPath)")
            } catch {
                diagnostics.append("Principal discovery failed: \(error.localizedDescription)")
                throw CalDAVError.diagnostic("Unable to resolve principal path", diagnostics)
            }

            do {
                homePath = try await discoverCalendarHomePath(principalPath: principalPath, diagnostics: &diagnostics)
            } catch {
                diagnostics.append("Home discovery failed: \(error.localizedDescription)")
                throw CalDAVError.diagnostic("Unable to resolve calendar home", diagnostics)
            }
        }

        diagnostics.append("Using calendar home path: \(homePath)")
        let discoveryTimer = SyncTimer()
        let calendars = try await discoverCalendarCollections(homePath: homePath, diagnostics: &diagnostics)
        diagnostics.append("Discovered calendar collections: \(calendars.count)")
        diagnostics.append(discoveryTimer.line("CalDAV calendar discovery"))

        let calendarResults = try await fetchCalendarCollectionsInParallel(
            calendars: calendars,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            useTimeRange: rangeStart != nil && rangeEnd != nil
        )
        diagnostics.append(contentsOf: calendarResults.flatMap(\.diagnostics))
        var merged = calendarResults.flatMap(\.items)

        if merged.isEmpty {
            diagnostics.append("No items with time-range filter, retrying without time-range")
            let fallbackResults = try await fetchCalendarCollectionsInParallel(
                calendars: calendars,
                rangeStart: nil,
                rangeEnd: nil,
                useTimeRange: false
            )
            diagnostics.append(contentsOf: fallbackResults.flatMap(\.diagnostics))
            merged = fallbackResults.flatMap(\.items)
        }

        let items = merged.sorted { lhs, rhs in
            let left = lhs.startOrDue
            let right = rhs.startOrDue
            if left == right { return lhs.summary < rhs.summary }
            return left < right
        }

        diagnostics.append("Parsed items: \(items.count)")
        diagnostics.append(totalTimer.line("CalDAV total"))
        return FetchResult(items: items, diagnostics: diagnostics)
    }

    private func fetchCalendarCollectionsInParallel(
        calendars: [CalendarCollection],
        rangeStart: Date?,
        rangeEnd: Date?,
        useTimeRange: Bool
    ) async throws -> [CalDAVCalendarFetchResult] {
        try await withThrowingTaskGroup(of: CalDAVCalendarFetchResult.self) { group in
            for (index, calendar) in calendars.enumerated() {
                group.addTask {
                    try await fetchCalendarCollection(
                        calendar: calendar,
                        index: index,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        useTimeRange: useTimeRange
                    )
                }
            }

            var results: [CalDAVCalendarFetchResult] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }
        }
    }

    private func fetchCalendarCollection(
        calendar: CalendarCollection,
        index: Int,
        rangeStart: Date?,
        rangeEnd: Date?,
        useTimeRange: Bool
    ) async throws -> CalDAVCalendarFetchResult {
        let timer = SyncTimer()
        var diagnostics: [String] = []
        var merged: [CalendarItem] = []
        let queryRange: (start: Date, end: Date)? = if useTimeRange, let rangeStart, let rangeEnd {
            (rangeStart, rangeEnd)
        } else {
            nil
        }
        let components = calendar.supportedComponents.sorted().joined(separator: ",")
        diagnostics.append("Calendar: \(calendar.displayName) components=\(components) path=\(calendar.href)")

        if calendar.supportedComponents.contains("VEVENT") {
            let icsList = try await queryCalendarDataForComponent(
                calendarPath: calendar.href,
                component: "VEVENT",
                range: queryRange,
                diagnostics: &diagnostics
            )
            merged.append(contentsOf: icsList.flatMap { ics in
                ICSParser.parseItems(
                    from: ics,
                    calendarName: calendar.displayName,
                    rangeStart: queryRange?.start,
                    rangeEnd: queryRange?.end
                )
            })
        }

        if calendar.supportedComponents.contains("VTODO") {
            let icsList = try await queryCalendarDataForComponent(
                calendarPath: calendar.href,
                component: "VTODO",
                range: queryRange,
                diagnostics: &diagnostics
            )
            merged.append(contentsOf: icsList.flatMap { ics in
                ICSParser.parseItems(
                    from: ics,
                    calendarName: calendar.displayName,
                    rangeStart: queryRange?.start,
                    rangeEnd: queryRange?.end
                )
            })
        }

        diagnostics.append(timer.line("CalDAV calendar \(calendar.displayName)"))
        return CalDAVCalendarFetchResult(index: index, items: merged, diagnostics: diagnostics)
    }

    private func queryCalendarDataForComponent(
        calendarPath: String,
        component: String,
        range: (start: Date, end: Date)?,
        diagnostics: inout [String]
    ) async throws -> [String] {
        if let range {
            return try await queryCalendarData(
                calendarPath: calendarPath,
                component: component,
                rangeStart: range.start,
                rangeEnd: range.end,
                diagnostics: &diagnostics
            )
        }

        return try await queryCalendarDataWithoutTimeRange(
            calendarPath: calendarPath,
            component: component,
            diagnostics: &diagnostics
        )
    }

    private var directCalendarPath: String? {
        let path = CalDAVPath.normalize(baseURL.path)
        if path.lowercased().hasSuffix("/events") || path.lowercased().hasSuffix("/events/") {
            return path
        }

        if baseURL.host?.lowercased().contains("googleusercontent.com") == true {
            let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let prefix = basePath.isEmpty ? "caldav/v2" : basePath
            return "/\(prefix)/\(CalDAVPath.encodedPathSegment(authUsername))/events/"
        }

        return nil
    }

    private func fetchDirectCalendarItems(
        calendarPath: String,
        rangeStart: Date?,
        rangeEnd: Date?,
        diagnostics: inout [String]
    ) async throws -> [CalendarItem] {
        let eventData: [String] = if let rangeStart, let rangeEnd {
            try await queryCalendarData(
                calendarPath: calendarPath,
                component: "VEVENT",
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                diagnostics: &diagnostics
            )
        } else {
            try await queryCalendarDataWithoutTimeRange(
                calendarPath: calendarPath,
                component: "VEVENT",
                diagnostics: &diagnostics
            )
        }

        return eventData.flatMap { ics in
            ICSParser.parseItems(from: ics, calendarName: authUsername, rangeStart: rangeStart, rangeEnd: rangeEnd)
        }
    }

    private func discoverPrincipalPath(diagnostics: inout [String]) async throws -> String {
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:current-user-principal />
          </d:prop>
        </d:propfind>
        """

        let data = try await send(path: "/", method: "PROPFIND", depth: "0", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""

        guard let href = CalDAVXML.firstCurrentUserPrincipalHref(from: xml) else {
            throw CalDAVError.parse("current-user-principal href not found")
        }

        return CalDAVPath.normalize(href)
    }

    private func discoverCalendarHomePath(principalPath: String, diagnostics: inout [String]) async throws -> String {
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <c:calendar-home-set />
          </d:prop>
        </d:propfind>
        """

        let data = try await send(path: principalPath, method: "PROPFIND", depth: "0", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""

        guard let href = CalDAVXML.firstCalendarHomeSetHref(from: xml) else {
            throw CalDAVError.parse("calendar-home-set href not found")
        }

        return CalDAVPath.normalize(href)
    }

    private func discoverCalendarCollections(homePath: String, diagnostics: inout [String]) async throws -> [CalendarCollection] {
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:displayname />
            <d:resourcetype />
            <c:supported-calendar-component-set />
          </d:prop>
        </d:propfind>
        """

        let data = try await send(path: homePath, method: "PROPFIND", depth: "1", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""

        var results: [CalendarCollection] = []

        for response in CalDAVXML.responses(from: xml) {
            guard let hrefRaw = response.hrefs.first else {
                continue
            }

            let href = CalDAVPath.normalize(hrefRaw)
            if href == CalDAVPath.normalize(homePath) {
                continue
            }

            if !response.isCalendar {
                continue
            }

            let displayName = response.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? href
            let components = response.componentNames.isEmpty ? Set(["VEVENT", "VTODO"]) : response.componentNames
            results.append(
                CalendarCollection(
                    href: href,
                    displayName: displayName,
                    supportedComponents: components
                )
            )
        }

        if results.isEmpty {
            throw CalDAVError.parse("no calendar collection discovered")
        }
        return results
    }

    private func queryCalendarData(
        calendarPath: String,
        component: String,
        rangeStart: Date,
        rangeEnd: Date,
        diagnostics: inout [String]
    ) async throws -> [String] {
        let start = CalDAVDateFormatting.utcStamp(rangeStart)
        let end = CalDAVDateFormatting.utcStamp(rangeEnd)

        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag />
            <c:calendar-data />
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="\(component)">
                <c:time-range start="\(start)" end="\(end)" />
              </c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """

        let data = try await send(path: calendarPath, method: "REPORT", depth: "1", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""
        let extracted = CalDAVXML.extractCalendarData(from: xml)
        diagnostics.append("calendar-query \(component) calendar-data count: \(extracted.count)")
        if !extracted.isEmpty {
            return extracted
        }

        diagnostics.append("calendar-query \(component) returned no calendar-data, trying multiget fallback")
        return try await fetchCalendarDataViaMultiget(
            calendarPath: calendarPath,
            diagnostics: &diagnostics
        )
    }

    private func queryCalendarDataWithoutTimeRange(
        calendarPath: String,
        component: String,
        diagnostics: inout [String]
    ) async throws -> [String] {
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag />
            <c:calendar-data />
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="\(component)" />
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """

        let data = try await send(path: calendarPath, method: "REPORT", depth: "1", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""
        let extracted = CalDAVXML.extractCalendarData(from: xml)
        diagnostics.append("calendar-query(no-range) \(component) calendar-data count: \(extracted.count)")
        if !extracted.isEmpty {
            return extracted
        }

        diagnostics.append("calendar-query(no-range) \(component) returned no calendar-data, trying multiget fallback")
        return try await fetchCalendarDataViaMultiget(
            calendarPath: calendarPath,
            diagnostics: &diagnostics
        )
    }

    private func fetchCalendarDataViaMultiget(
        calendarPath: String,
        diagnostics: inout [String]
    ) async throws -> [String] {
        let objectPaths = try await listCalendarObjectPaths(
            calendarPath: calendarPath,
            diagnostics: &diagnostics
        )
        diagnostics.append("multiget object count: \(objectPaths.count)")
        if objectPaths.isEmpty {
            return []
        }

        let chunks = stride(from: 0, to: objectPaths.count, by: 50).map {
            Array(objectPaths[$0 ..< min($0 + 50, objectPaths.count)])
        }

        var merged: [String] = []
        for chunk in chunks {
            try await merged.append(contentsOf: multigetCalendarObjects(paths: chunk, diagnostics: &diagnostics))
        }
        return merged
    }

    private func listCalendarObjectPaths(
        calendarPath: String,
        diagnostics: inout [String]
    ) async throws -> [String] {
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:getcontenttype />
            <d:resourcetype />
          </d:prop>
        </d:propfind>
        """

        let data = try await send(path: calendarPath, method: "PROPFIND", depth: "1", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""
        var paths: [String] = []

        for response in CalDAVXML.responses(from: xml) {
            guard let hrefRaw = response.hrefs.first else {
                continue
            }

            let href = CalDAVPath.normalize(hrefRaw)
            if href == CalDAVPath.normalize(calendarPath) {
                continue
            }

            let contentType = response.contentType?.lowercased() ?? ""
            if response.isCollection {
                continue
            }

            if contentType.contains("text/calendar") || href.hasSuffix(".ics") || href.contains("/event/") || href.contains("/todo/") {
                paths.append(href)
            }
        }

        return Array(Set(paths)).sorted()
    }

    private func multigetCalendarObjects(
        paths: [String],
        diagnostics: inout [String]
    ) async throws -> [String] {
        let hrefs = paths.map { "<d:href>\($0)</d:href>" }.joined()
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag />
            <c:calendar-data />
          </d:prop>
          \(hrefs)
        </c:calendar-multiget>
        """

        let basePath = paths.first.flatMap(CalDAVPath.parentPath) ?? "/"
        let data = try await send(path: basePath, method: "REPORT", depth: "1", body: body, diagnostics: &diagnostics)
        let xml = String(bytes: data, encoding: .utf8) ?? ""
        let extracted = CalDAVXML.extractCalendarData(from: xml)
        diagnostics.append("calendar-multiget returned calendar-data count: \(extracted.count)")
        return extracted
    }

    private func send(path: String, method: String, depth: String, body: String, diagnostics: inout [String]) async throws -> Data {
        let url = CalDAVPath.url(from: path, baseURL: baseURL)
        diagnostics.append("\(method) \(url.absoluteString) depth=\(depth)")
        let request = CalDAVRequest(
            url: url,
            method: method,
            depth: depth,
            body: body,
            username: authUsername,
            password: appPassword
        )
        let response = try await transport.send(request)
        diagnostics.append("-> HTTP \(response.statusCode)")

        guard (200 ... 299).contains(response.statusCode) else {
            let bodyText = String(data: response.data, encoding: .utf8) ?? ""
            diagnostics.append("-> Body \(bodyText.prefix(200))")
            throw CalDAVError.http(response.statusCode, bodyText)
        }

        return response.data
    }
}

private struct CalDAVCalendarFetchResult {
    let index: Int
    let items: [CalendarItem]
    let diagnostics: [String]
}
