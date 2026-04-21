import Foundation
import SwiftUI

@MainActor
final class CalendarStore: ObservableObject {
    @Published var naverID = ""
    @Published var appPassword = ""
    @Published var monthsAhead = "6"
    @Published var loading = false
    @Published var errorText = ""
    @Published var diagnostics: [String] = []
    @Published var items: [CalendarItem] = []
    @Published var selectedItemID: CalendarItem.ID?
    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published var displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @Published var visibleCalendars: Set<String> = []
    @Published var customCalendarColorCodes: [String: String] = [:]
    @Published var showingDetailSheet = false
    @Published var showingSettingsSheet = false
    @Published var showingDaySheet = false
    @Published var showingDiagnostics = false
    @Published var hasSavedConnection = false
    @Published var requestedVisibleMonth: Date?
    @Published var layoutRevision = 0
    @Published var connections: [CalendarConnection] = []
    @Published var connectionErrors: [String: String] = [:]
    @Published var connectionCalendarCounts: [String: Int] = [:]

    private var didAttemptInitialLoad = false
    private let customCalendarColorKey = "calendar.customColorCodes"

    var selectedItem: CalendarItem? {
        items.first(where: { $0.id == selectedItemID }).map(applyCustomColor)
    }

    init() {
        restoreConnections()
        restoreCustomCalendarColors()
        scheduleInitialLoadIfPossible()
    }

    var calendarNames: [String] {
        Array(Set(items.map(\.sourceCalendar))).sorted()
    }

    var calendarSourceGroups: [(source: String, calendars: [String])] {
        let grouped = Dictionary(grouping: calendarNames) { CalendarText.calendarSourceName($0) }
        return grouped
            .map { source, calendars in
                (
                    source: source,
                    calendars: calendars.sorted {
                        CalendarText.calendarDisplayName($0) < CalendarText.calendarDisplayName($1)
                    }
                )
            }
            .sorted { $0.source < $1.source }
    }

    var filteredItems: [CalendarItem] {
        items
            .filter { visibleCalendars.contains($0.sourceCalendar) }
            .map(applyCustomColor)
    }

    var orderedFilteredItems: [CalendarItem] {
        filteredItems.sorted(by: compareItems)
    }

    var upcomingItems: [CalendarItem] {
        let now = Date()
        return filteredItems
            .filter { ($0.startDate ?? .distantPast) >= Calendar.current.startOfDay(for: now) }
            .sorted { lhs, rhs in
                (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
            }
    }

    func load(shouldCloseSettings: Bool = true) {
        errorText = ""
        diagnostics = []
        loading = true
        // Calendar API and CalDAV do not share a common "fetch everything" contract.
        // Keep the UI free of a month-range setting, but still send a broad bounded
        // window so Google Calendar API and CalDAV servers can answer predictably.
        let rangeStart = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
        let rangeEnd = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
        connectionErrors = [:]
        connectionCalendarCounts = [:]

        // Legacy compatibility: older builds stored one Naver account in naverID/appPassword.
        // If no v2 connection exists, promote that state into the multi-account model.
        if connections.isEmpty, !naverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !appPassword.isEmpty {
            upsertConnection(
                CalendarConnection(
                    id: UUID().uuidString,
                    email: naverID,
                    password: appPassword,
                    serverURL: "https://caldav.calendar.naver.com"
                ),
                shouldReload: false
            )
        }

        let activeConnections = connections
        hasSavedConnection = !activeConnections.isEmpty

        Task {
            var mergedItems: [CalendarItem] = []
            var mergedDiagnostics: [String] = []

            // Each account is isolated: one bad Google/CalDAV account must not wipe
            // successful items from other accounts. Store per-account errors for the
            // settings UI and keep merging whatever succeeds.
            for connection in activeConnections {
                do {
                    let result: FetchResult
                    if connection.provider == "google" {
                        result = try await GoogleCalendarClient(
                            email: connection.email,
                            refreshToken: connection.password
                        )
                        .fetchCalendarItems(rangeStart: rangeStart, rangeEnd: rangeEnd)
                    } else {
                        result = try await CalDAVClient(
                            username: connection.email,
                            appPassword: connection.password,
                            serverURL: connection.serverURL
                        )
                        .fetchCalendarItems(rangeStart: rangeStart, rangeEnd: rangeEnd)
                    }
                    mergedDiagnostics.append("[\(connection.displayEmail)]")
                    mergedDiagnostics.append(contentsOf: result.diagnostics)
                    await MainActor.run {
                        connectionCalendarCounts[connection.id] = result.items.count
                        connectionErrors[connection.id] = nil
                    }
                    let source = connection.displayServer
                    mergedItems.append(contentsOf: result.items.map { item in
                        item.withSourceCalendar(
                            CalendarText.calendarKey(
                                source: source,
                                calendar: item.sourceCalendar
                            )
                        )
                    })
                } catch {
                    mergedDiagnostics.append("[\(connection.displayEmail)]")
                    mergedDiagnostics.append("동기화 실패: \(error.localizedDescription)")
                    await MainActor.run {
                        connectionCalendarCounts[connection.id] = 0
                        connectionErrors[connection.id] = error.localizedDescription
                    }
                    if let diagnosticError = error as? CalDAVError,
                       case .diagnostic(_, let entries) = diagnosticError {
                        mergedDiagnostics.append(contentsOf: entries)
                    }
                }
            }

            await MainActor.run {
                items = mergedItems.sorted(by: compareItems)
                diagnostics = mergedDiagnostics
                visibleCalendars = Set(mergedItems.map(\.sourceCalendar))
                selectedItemID = mergedItems.first?.id
                showingSettingsSheet = !shouldCloseSettings
                let today = Calendar.current.startOfDay(for: Date())
                let todayMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
                selectedDate = today
                displayedMonth = todayMonth
                requestedVisibleMonth = todayMonth
                layoutRevision += 1
                loading = false
                errorText = mergedItems.isEmpty && !activeConnections.isEmpty ? "연결된 계정에서 가져온 일정이 없습니다." : ""
                saveWidgetSnapshot()
            }
        }
    }

    func restoreConnections() {
        connections = ConnectionStore.loadConnections()
        hasSavedConnection = !connections.isEmpty
        if let first = connections.first {
            naverID = first.email
            appPassword = first.password
            monthsAhead = "all"
        }
    }

    func upsertConnection(_ connection: CalendarConnection, shouldReload: Bool = true) {
        ConnectionStore.upsertConnection(connection)
        restoreConnections()
        if shouldReload {
            load(shouldCloseSettings: false)
        }
    }

    func deleteConnection(id: String) {
        ConnectionStore.deleteConnection(id: id)
        restoreConnections()
        if connections.isEmpty {
            items = []
            diagnostics = []
            errorText = ""
            visibleCalendars = []
            selectedItemID = nil
            hasSavedConnection = false
            try? WidgetSnapshotStore.save([])
            WidgetSnapshotStore.refreshWidgets()
        } else {
            load(shouldCloseSettings: false)
        }
        layoutRevision += 1
    }

    func disconnect() {
        ConnectionStore.clear()
        naverID = ""
        appPassword = ""
        monthsAhead = "6"
        items = []
        diagnostics = []
        errorText = ""
        visibleCalendars = []
        hasSavedConnection = false
        connections = []
        layoutRevision += 1

        try? WidgetSnapshotStore.save([])
        ConnectionStore.saveWidgetEventSnapshots([])
        WidgetSnapshotStore.refreshWidgets()
    }

    func colorCode(for item: CalendarItem) -> String {
        customCalendarColorCodes[item.sourceCalendar] ?? item.sourceColorCode
    }

    func colorCode(for calendarName: String) -> String {
        customCalendarColorCodes[calendarName] ?? items.first(where: { $0.sourceCalendar == calendarName })?.sourceColorCode ?? "0"
    }

    func setCalendarColor(_ color: Color, for calendarName: String) {
        customCalendarColorCodes[calendarName] = CalendarPalette.customCode(for: color)
        persistCustomCalendarColors()
        saveWidgetSnapshot()
        layoutRevision += 1
    }

    func toggleCalendar(_ name: String) {
        if visibleCalendars.contains(name) {
            visibleCalendars.remove(name)
        } else {
            visibleCalendars.insert(name)
        }
        layoutRevision += 1
    }

    func items(for day: Date) -> [CalendarItem] {
        filteredItems.filter { item in
            item.occurs(on: day)
        }
        .sorted { compareDayItems($0, $1, on: day) }
    }

    func moveMonth(by offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = next
        }
    }

    func jumpToMonth(_ month: Date) {
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month)) ?? month
        displayedMonth = monthStart
        requestedVisibleMonth = monthStart
    }

    func jumpToToday() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDate = today
        let month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        displayedMonth = month
        requestedVisibleMonth = month
    }

    func selectItem(_ item: CalendarItem) {
        selectedItemID = item.id
    }

    func focusItem(_ item: CalendarItem) {
        selectItem(item)
        if let startDate = item.startDate {
            selectedDate = Calendar.current.startOfDay(for: startDate)
        }
    }

    func openDay(_ day: Date) {
        selectedDate = Calendar.current.startOfDay(for: day)
        selectedItemID = items(for: day).first?.id
        showingDaySheet = true
    }

    func autoLoadIfPossible() {
        scheduleInitialLoadIfPossible()
    }

    private func scheduleInitialLoadIfPossible() {
        guard hasSavedConnection, !didAttemptInitialLoad else { return }
        didAttemptInitialLoad = true

        Task { @MainActor in
            load()
        }
    }

    private func compareItems(_ lhs: CalendarItem, _ rhs: CalendarItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return rhs.isCompleted
        }

        let left = lhs.startDate ?? .distantFuture
        let right = rhs.startDate ?? .distantFuture
        if left == right {
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay
            }
            return lhs.summary < rhs.summary
        }
        return left < right
    }

    private func compareDayItems(_ lhs: CalendarItem, _ rhs: CalendarItem, on day: Date) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }

        let leftEnd = daySortEndDate(lhs, on: day)
        let rightEnd = daySortEndDate(rhs, on: day)
        if leftEnd != rightEnd {
            return leftEnd < rightEnd
        }

        let leftStart = lhs.startDate ?? .distantFuture
        let rightStart = rhs.startDate ?? .distantFuture
        if leftStart != rightStart {
            return leftStart < rightStart
        }

        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay
        }

        return lhs.summary < rhs.summary
    }

    private func daySortEndDate(_ item: CalendarItem, on day: Date) -> Date {
        if let endDate = item.endDate {
            return endDate
        }
        if let displayEndDay = item.displayEndDay {
            return displayEndDay
        }
        if let startDate = item.startDate {
            return startDate
        }
        return Calendar.current.startOfDay(for: day)
    }

    private func applyCustomColor(_ item: CalendarItem) -> CalendarItem {
        guard let customCode = customCalendarColorCodes[item.sourceCalendar] else {
            return item
        }
        return item.withSourceColorCode(customCode)
    }

    private func restoreCustomCalendarColors() {
        let shared = ConnectionStore.loadCustomCalendarColorCodes()
        if let data = UserDefaults.standard.data(forKey: customCalendarColorKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            customCalendarColorCodes = shared.merging(decoded) { _, local in local }
        } else {
            customCalendarColorCodes = shared
        }
        ConnectionStore.saveCustomCalendarColorCodes(customCalendarColorCodes)
    }

    private func persistCustomCalendarColors() {
        guard let data = try? JSONEncoder().encode(customCalendarColorCodes) else {
            return
        }
        UserDefaults.standard.set(data, forKey: customCalendarColorKey)
        ConnectionStore.saveCustomCalendarColorCodes(customCalendarColorCodes)
    }

    private func saveWidgetSnapshot() {
        // Widgets cannot safely run the same network/auth flow as the app. The app is
        // the source of truth: after every sync/color change it writes a flattened,
        // already-colored event snapshot that the WidgetKit extension reads.
        let snapshots = items.map { item in
            WidgetEventSnapshot(
                id: item.uid,
                title: item.summary,
                calendarName: item.sourceCalendar,
                startTimestamp: item.startDate?.timeIntervalSince1970 ?? 0,
                endTimestamp: item.endDate?.timeIntervalSince1970,
                isAllDay: item.isAllDay,
                location: item.location,
                note: item.note,
                status: item.derivedStatus,
                colorCode: colorCode(for: item)
            )
        }
        try? WidgetSnapshotStore.save(snapshots)
        ConnectionStore.saveWidgetEventSnapshots(snapshots)
        WidgetSnapshotStore.refreshWidgets()
    }
}

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

    private static var localConfig: LocalGoogleOAuthConfig? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lendar/google-oauth.json")
        ]

        for url in candidates {
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

    func fetchCalendarItems(rangeStart: Date, rangeEnd: Date) async throws -> FetchResult {
        // Google Calendar uses OAuth + JSON REST APIs, not the Basic Auth CalDAV flow
        // used by Naver. The stored password field is a refresh token for this provider.
        let accessToken = try await refreshAccessToken()
        var diagnostics = ["Google Calendar API account: \(email)"]
        let calendars = try await fetchCalendars(accessToken: accessToken)
        diagnostics.append("Google calendars: \(calendars.count)")

        var items: [CalendarItem] = []
        for calendar in calendars {
            let events = try await fetchEvents(calendar: calendar, accessToken: accessToken, rangeStart: rangeStart, rangeEnd: rangeEnd)
            diagnostics.append("Calendar: \(calendar.summary) events=\(events.count)")
            items.append(contentsOf: events)
        }

        return FetchResult(items: items.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }, diagnostics: diagnostics)
    }

    private func refreshAccessToken() async throws -> String {
        var request = URLRequest(url: URL(string: GoogleOAuthConfig.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        guard let accessToken = token.accessToken, !accessToken.isEmpty else {
            throw CalDAVError.auth("Google access token not returned")
        }
        return accessToken
    }

    private func fetchCalendars(accessToken: String) async throws -> [GoogleCalendar] {
        var components = URLComponents(string: "\(GoogleOAuthConfig.calendarAPIBase)/users/me/calendarList")!
        components.queryItems = [
            URLQueryItem(name: "showHidden", value: "true"),
            URLQueryItem(name: "minAccessRole", value: "reader")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data).items ?? []
    }

    private func fetchEvents(calendar: GoogleCalendar, accessToken: String, rangeStart: Date, rangeEnd: Date) async throws -> [CalendarItem] {
        var results: [CalendarItem] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "\(GoogleOAuthConfig.calendarAPIBase)/calendars/\(Self.urlPath(calendar.id))/events")!
            components.queryItems = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500"),
                URLQueryItem(name: "timeMin", value: Self.rfc3339(rangeStart)),
                URLQueryItem(name: "timeMax", value: Self.rfc3339(rangeEnd))
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            var request = authorizedRequest(url: components.url!, accessToken: accessToken)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTP(response: response, data: data)
            let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
            results.append(contentsOf: (decoded.items ?? []).compactMap { event in
                item(from: event, calendar: calendar)
            })
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return results
    }

    private func item(from event: GoogleEvent, calendar: GoogleCalendar) -> CalendarItem? {
        guard let start = parseGoogleDate(event.start), let end = parseGoogleDate(event.end) else {
            return nil
        }
        let isAllDay = event.start?.date != nil
        let colorCode = calendar.backgroundColor.map { CalendarPalette.customColorPrefix + $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) } ?? "0"
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

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CalDAVError.network("invalid HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalDAVError.http(http.statusCode, body)
        }
    }

    private func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(Self.urlForm(key))=\(Self.urlForm(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func urlForm(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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
