import Foundation

struct CalDAVClient {
    let username: String
    let appPassword: String
    let baseURL: URL

    init(username: String, appPassword: String, serverURL: String = "https://caldav.calendar.naver.com") {
        self.username = username
        self.appPassword = appPassword
        self.baseURL = Self.normalizedBaseURL(serverURL)
    }

    private var normalizedUsername: String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var authUsername: String {
        let trimmed = normalizedUsername
        return trimmed
    }

    func fetchCalendarItems(rangeStart: Date? = nil, rangeEnd: Date? = nil) async throws -> FetchResult {
        var diagnostics: [String] = []
        diagnostics.append("Auth username: \(authUsername)")
        diagnostics.append("Server: \(baseURL.absoluteString)")
        diagnostics.append("Manual principal path: \(fallbackPrincipalPath())")
        diagnostics.append("Manual calendar home path: \(fallbackCalendarHomePath())")

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
            let manualPrincipal = fallbackPrincipalPath()
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
        let calendars = try await discoverCalendarCollections(homePath: homePath, diagnostics: &diagnostics)
        diagnostics.append("Discovered calendar collections: \(calendars.count)")

        var merged: [CalendarItem] = []
        for calendar in calendars {
            let components = calendar.supportedComponents.sorted().joined(separator: ",")
            diagnostics.append("Calendar: \(calendar.displayName) components=\(components) path=\(calendar.href)")
            if calendar.supportedComponents.contains("VEVENT") {
                let icsList: [String]
                if let rangeStart, let rangeEnd {
                    icsList = try await queryCalendarData(
                        calendarPath: calendar.href,
                        component: "VEVENT",
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        diagnostics: &diagnostics
                    )
                } else {
                    icsList = try await queryCalendarDataWithoutTimeRange(
                        calendarPath: calendar.href,
                        component: "VEVENT",
                        diagnostics: &diagnostics
                    )
                }
                merged.append(contentsOf: icsList.flatMap { ICSParser.parseItems(from: $0, calendarName: calendar.displayName) })
            }

            if calendar.supportedComponents.contains("VTODO") {
                let icsList: [String]
                if let rangeStart, let rangeEnd {
                    icsList = try await queryCalendarData(
                        calendarPath: calendar.href,
                        component: "VTODO",
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        diagnostics: &diagnostics
                    )
                } else {
                    icsList = try await queryCalendarDataWithoutTimeRange(
                        calendarPath: calendar.href,
                        component: "VTODO",
                        diagnostics: &diagnostics
                    )
                }
                merged.append(contentsOf: icsList.flatMap { ICSParser.parseItems(from: $0, calendarName: calendar.displayName) })
            }
        }

        if merged.isEmpty {
            diagnostics.append("No items with time-range filter, retrying without time-range")
            for calendar in calendars {
                if calendar.supportedComponents.contains("VEVENT") {
                    let icsList = try await queryCalendarDataWithoutTimeRange(
                        calendarPath: calendar.href,
                        component: "VEVENT",
                        diagnostics: &diagnostics
                    )
                    merged.append(contentsOf: icsList.flatMap { ICSParser.parseItems(from: $0, calendarName: calendar.displayName) })
                }

                if calendar.supportedComponents.contains("VTODO") {
                    let icsList = try await queryCalendarDataWithoutTimeRange(
                        calendarPath: calendar.href,
                        component: "VTODO",
                        diagnostics: &diagnostics
                    )
                    merged.append(contentsOf: icsList.flatMap { ICSParser.parseItems(from: $0, calendarName: calendar.displayName) })
                }
            }
        }

        let items = merged.sorted { lhs, rhs in
            let left = lhs.startOrDue
            let right = rhs.startOrDue
            if left == right { return lhs.summary < rhs.summary }
            return left < right
        }

        diagnostics.append("Parsed items: \(items.count)")
        return FetchResult(items: items, diagnostics: diagnostics)
    }

    private var directCalendarPath: String? {
        let path = normalizePath(baseURL.path)
        if path.lowercased().hasSuffix("/events") || path.lowercased().hasSuffix("/events/") {
            return path
        }

        if baseURL.host?.lowercased().contains("googleusercontent.com") == true {
            let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let prefix = basePath.isEmpty ? "caldav/v2" : basePath
            return "/\(prefix)/\(encodedPathSegment(authUsername))/events/"
        }

        return nil
    }

    private func fetchDirectCalendarItems(
        calendarPath: String,
        rangeStart: Date?,
        rangeEnd: Date?,
        diagnostics: inout [String]
    ) async throws -> [CalendarItem] {
        let eventData: [String]
        if let rangeStart, let rangeEnd {
            eventData = try await queryCalendarData(
                calendarPath: calendarPath,
                component: "VEVENT",
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                diagnostics: &diagnostics
            )
        } else {
            eventData = try await queryCalendarDataWithoutTimeRange(
                calendarPath: calendarPath,
                component: "VEVENT",
                diagnostics: &diagnostics
            )
        }

        return eventData.flatMap {
            ICSParser.parseItems(from: $0, calendarName: authUsername)
        }
    }

    private static func normalizedBaseURL(_ value: String) -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: normalized),
           let host = url.host?.lowercased(),
           (host == "www.google.com" && url.path.lowercased().hasPrefix("/calendar/dav") ||
            host == "calendar.google.com" && url.path.lowercased().contains("calendar/dav")) {
            return URL(string: "https://apidata.googleusercontent.com/caldav/v2")!
        }

        return URL(string: normalized) ??
            URL(string: "https://caldav.calendar.naver.com")!
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
        let xml = String(decoding: data, as: UTF8.self)

        guard let principalBlock = firstMatch(in: xml, pattern: #"<[^>]*current-user-principal[^>]*>([\s\S]*?)</[^>]*current-user-principal>"#),
              let href = firstMatch(in: principalBlock, pattern: #"<[^>]*href[^>]*>([\s\S]*?)</[^>]*href>"#) else {
            throw CalDAVError.parse("current-user-principal href not found")
        }

        return normalizePath(decodeXMLText(href))
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
        let xml = String(decoding: data, as: UTF8.self)

        guard let homeBlock = firstMatch(in: xml, pattern: #"<[^>]*calendar-home-set[^>]*>([\s\S]*?)</[^>]*calendar-home-set>"#),
              let href = firstMatch(in: homeBlock, pattern: #"<[^>]*href[^>]*>([\s\S]*?)</[^>]*href>"#) else {
            throw CalDAVError.parse("calendar-home-set href not found")
        }

        return normalizePath(decodeXMLText(href))
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
        let xml = String(decoding: data, as: UTF8.self)

        let responseBlocks = allMatches(in: xml, pattern: #"<[^>]*response[^>]*>([\s\S]*?)</[^>]*response>"#)
        var results: [CalendarCollection] = []

        for block in responseBlocks {
            guard let hrefRaw = firstMatch(in: block, pattern: #"<[^>]*href[^>]*>([\s\S]*?)</[^>]*href>"#) else {
                continue
            }

            let href = normalizePath(decodeXMLText(hrefRaw))
            if href == normalizePath(homePath) {
                continue
            }

            let hasCalendarTag =
                block.range(of: #"<[^>]*calendar\s*/>"#, options: .regularExpression) != nil ||
                block.range(of: #"<[^>]*calendar[^>]*>[\s\S]*?</[^>]*calendar>"#, options: .regularExpression) != nil
            if !hasCalendarTag {
                continue
            }

            let displayRaw = firstMatch(in: block, pattern: #"<[^>]*displayname[^>]*>([\s\S]*?)</[^>]*displayname>"#) ?? href
            let displayName = decodeXMLText(displayRaw).trimmingCharacters(in: .whitespacesAndNewlines)

            let compNames = Set(
                allMatches(in: block, pattern: #"<[^>]*comp[^>]*name=\"([^\"]+)\"[^>]*/?>"#)
                    .map { $0.uppercased() }
            )

            let components = compNames.isEmpty ? Set(["VEVENT", "VTODO"]) : compNames
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
        let start = Self.utcStamp(rangeStart)
        let end = Self.utcStamp(rangeEnd)

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
        let xml = String(decoding: data, as: UTF8.self)
        let extracted = extractCalendarData(from: xml)
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
        let xml = String(decoding: data, as: UTF8.self)
        let extracted = extractCalendarData(from: xml)
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
            Array(objectPaths[$0..<min($0 + 50, objectPaths.count)])
        }

        var merged: [String] = []
        for chunk in chunks {
            merged.append(contentsOf: try await multigetCalendarObjects(paths: chunk, diagnostics: &diagnostics))
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
        let xml = String(decoding: data, as: UTF8.self)
        let responseBlocks = allMatches(in: xml, pattern: #"<[^>]*response[^>]*>([\s\S]*?)</[^>]*response>"#)
        var paths: [String] = []

        for block in responseBlocks {
            guard let hrefRaw = firstMatch(in: block, pattern: #"<[^>]*href[^>]*>([\s\S]*?)</[^>]*href>"#) else {
                continue
            }

            let href = normalizePath(decodeXMLText(hrefRaw))
            if href == normalizePath(calendarPath) {
                continue
            }

            let contentType = firstMatch(in: block, pattern: #"<[^>]*getcontenttype[^>]*>([\s\S]*?)</[^>]*getcontenttype>"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let isCollection =
                block.range(of: #"<[^>]*collection\s*/>"#, options: .regularExpression) != nil ||
                block.range(of: #"<[^>]*collection[^>]*>[\s\S]*?</[^>]*collection>"#, options: .regularExpression) != nil

            if isCollection {
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

        let basePath = paths.first.flatMap(parentPath) ?? "/"
        let data = try await send(path: basePath, method: "REPORT", depth: "1", body: body, diagnostics: &diagnostics)
        let xml = String(decoding: data, as: UTF8.self)
        let extracted = extractCalendarData(from: xml)
        diagnostics.append("calendar-multiget returned calendar-data count: \(extracted.count)")
        return extracted
    }

    private func send(path: String, method: String, depth: String, body: String, diagnostics: inout [String]) async throws -> Data {
        let url = urlFrom(path: path)
        diagnostics.append("\(method) \(url.absoluteString) depth=\(depth)")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let login = "\(authUsername):\(appPassword)"
        guard let loginData = login.data(using: .utf8) else {
            throw CalDAVError.auth("failed to encode credentials")
        }
        let token = loginData.base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CalDAVError.network("invalid HTTP response")
        }
        diagnostics.append("-> HTTP \(http.statusCode)")

        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            diagnostics.append("-> Body \(bodyText.prefix(200))")
            throw CalDAVError.http(http.statusCode, bodyText)
        }

        return data
    }

    private func urlFrom(path: String) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let normalized = normalizePath(path)
        return baseURL.appendingPathComponent(String(normalized.dropFirst()))
    }

    private func normalizePath(_ input: String) -> String {
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            if let url = URL(string: input), let path = url.path.removingPercentEncoding {
                return path.hasPrefix("/") ? path : "/\(path)"
            }
        }

        let plain = input.removingPercentEncoding ?? input
        if plain.hasPrefix("/") {
            return plain
        }
        return "/\(plain)"
    }

    private func fallbackPrincipalPath() -> String {
        let user = normalizedUsername
        let idOnly = user.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? user
        return "/principals/users/\(encodedPathSegment(idOnly))"
    }

    private func fallbackCalendarHomePath() -> String {
        let user = normalizedUsername
        let idOnly = user.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? user
        return "/calendars/users/\(encodedPathSegment(idOnly))/"
    }

    private func encodedPathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func parentPath(of path: String) -> String? {
        let normalized = normalizePath(path)
        guard let slashIndex = normalized.lastIndex(of: "/"), slashIndex > normalized.startIndex else {
            return nil
        }
        return String(normalized[..<slashIndex]) + "/"
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    private func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[valueRange])
        }
    }

    private func decodeXMLText(_ value: String) -> String {
        var decoded = value
        decoded = decoded.replacingOccurrences(of: "&lt;", with: "<")
        decoded = decoded.replacingOccurrences(of: "&gt;", with: ">")
        decoded = decoded.replacingOccurrences(of: "&quot;", with: "\"")
        decoded = decoded.replacingOccurrences(of: "&apos;", with: "'")
        decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
        return decoded
    }

    private func extractCalendarData(from xml: String) -> [String] {
        allMatches(in: xml, pattern: #"<[^>]*calendar-data[^>]*>([\s\S]*?)</[^>]*calendar-data>"#)
            .map { decodeXMLText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

enum CalDAVError: LocalizedError {
    case auth(String)
    case network(String)
    case parse(String)
    case http(Int, String)
    case diagnostic(String, [String])

    var errorDescription: String? {
        switch self {
        case .auth(let message):
            return "Auth error: \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .parse(let message):
            return "Parse error: \(message)"
        case .http(let status, let body):
            if body.isEmpty {
                return "HTTP error: status=\(status)"
            }
            return "HTTP error: status=\(status), body=\(body.prefix(300))"
        case .diagnostic(let message, let diagnostics):
            return ([message] + diagnostics).joined(separator: "\n")
        }
    }
}
