import Foundation
import SwiftUI

/// Main state and sync orchestrator. Merges CalDAV and Google Calendar API accounts,
/// stores per-account errors, applies color overrides, and writes widget snapshots.
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
    private let syncService: any CalendarSyncing
    private let connectionManager: any CalendarConnectionManaging
    private let widgetSnapshotWriter: any WidgetSnapshotWriting
    private let userDefaults: UserDefaults
    private let syncWindow = CalendarSyncWindow()
    /// Tracks the server-backed range currently represented in `items`. Month
    /// navigation can then fetch only missing far-past/far-future windows.
    private var loadedRange: (start: Date, end: Date)?
    /// Prevents repeated far-month navigation from launching duplicate sync tasks
    /// while an additional range request is already in flight.
    private var additionalLoadTask: Task<Void, Never>?

    var selectedItem: CalendarItem? {
        items.first(where: { $0.id == selectedItemID }).map(applyCustomColor)
    }

    init(
        syncService: any CalendarSyncing = LiveCalendarSyncing(),
        connectionManager: any CalendarConnectionManaging = LiveCalendarConnectionManager(),
        widgetSnapshotWriter: any WidgetSnapshotWriting = LiveWidgetSnapshotWriter(),
        userDefaults: UserDefaults = .standard,
        autoLoad: Bool = true
    ) {
        self.syncService = syncService
        self.connectionManager = connectionManager
        self.widgetSnapshotWriter = widgetSnapshotWriter
        self.userDefaults = userDefaults
        restoreConnections()
        restoreCustomCalendarColors()
        if autoLoad {
            scheduleInitialLoadIfPossible()
        }
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
        filteredItems.sorted(by: CalendarItemOrdering.compareItems)
    }

    var upcomingItems: [CalendarItem] {
        let now = Date()
        return filteredItems
            .filter { ($0.startDate ?? .distantPast) >= Calendar.current.startOfDay(for: now) }
            .sorted { lhs, rhs in
                (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
            }
    }

    @discardableResult
    func load(shouldCloseSettings: Bool = true) -> Task<Void, Never> {
        errorText = ""
        diagnostics = []
        loading = true
        let syncRange = syncWindow.range(around: Date())
        let rangeStart = syncRange.start
        let rangeEnd = syncRange.end
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

        return Task {
            let syncResult = await syncService.fetchItems(
                connections: activeConnections,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )

            await MainActor.run {
                logSyncDiagnostics(syncResult.diagnostics)
                items = syncResult.items
                loadedRange = syncRange
                diagnostics = syncResult.diagnostics
                connectionCalendarCounts = syncResult.connectionCalendarCounts
                connectionErrors = syncResult.connectionErrors
                visibleCalendars = Set(syncResult.items.map(\.sourceCalendar))
                selectedItemID = syncResult.items.first?.id
                showingSettingsSheet = !shouldCloseSettings
                let today = Calendar.current.startOfDay(for: Date())
                let todayMonth = monthStart(for: today)
                selectedDate = today
                displayedMonth = todayMonth
                requestedVisibleMonth = todayMonth
                layoutRevision += 1
                loading = false
                errorText = syncResult.items.isEmpty && !activeConnections.isEmpty ? "연결된 계정에서 가져온 일정이 없습니다." : ""
                saveWidgetSnapshot()
            }
        }
    }

    func restoreConnections() {
        connections = connectionManager.loadConnections()
        hasSavedConnection = !connections.isEmpty
        if let first = connections.first {
            naverID = first.email
            appPassword = first.password
            monthsAhead = "all"
        }
    }

    @discardableResult
    func upsertConnection(_ connection: CalendarConnection, shouldReload: Bool = true) -> Task<Void, Never>? {
        connectionManager.upsertConnection(connection)
        restoreConnections()
        if shouldReload {
            return load(shouldCloseSettings: false)
        }
        return nil
    }

    @discardableResult
    func deleteConnection(id: String) -> Task<Void, Never>? {
        connectionManager.deleteConnection(id: id)
        restoreConnections()
        if connections.isEmpty {
            items = []
            diagnostics = []
            errorText = ""
            visibleCalendars = []
            selectedItemID = nil
            hasSavedConnection = false
            try? widgetSnapshotWriter.save([])
            widgetSnapshotWriter.refreshWidgets()
        } else {
            let task = load(shouldCloseSettings: false)
            layoutRevision += 1
            return task
        }
        layoutRevision += 1
        return nil
    }

    func disconnect() {
        connectionManager.clear()
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

        try? widgetSnapshotWriter.save([])
        connectionManager.saveWidgetEventSnapshots([])
        widgetSnapshotWriter.refreshWidgets()
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
        .sorted { CalendarItemOrdering.compareDayItems($0, $1, on: day) }
    }

    @discardableResult
    func moveMonth(by offset: Int) -> Task<Void, Never>? {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            let monthStart = monthStart(for: next)
            displayedMonth = monthStart
            requestedVisibleMonth = monthStart
            return ensureLoaded(around: monthStart)
        }
        return nil
    }

    @discardableResult
    func jumpToMonth(_ month: Date) -> Task<Void, Never>? {
        let monthStart = monthStart(for: month)
        displayedMonth = monthStart
        requestedVisibleMonth = monthStart
        return ensureLoaded(around: monthStart)
    }

    @discardableResult
    func jumpToToday() -> Task<Void, Never>? {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDate = today
        let month = monthStart(for: today)
        displayedMonth = month
        requestedVisibleMonth = month
        return ensureLoaded(around: month)
    }

    @discardableResult
    func updateDisplayedMonthFromScroll(_ month: Date) -> Task<Void, Never>? {
        displayedMonth = month
        return ensureLoaded(around: month)
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

    @discardableResult
    private func ensureLoaded(around month: Date) -> Task<Void, Never>? {
        let monthStart = monthStart(for: month)
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        guard hasSavedConnection, !connections.isEmpty else {
            return nil
        }
        guard !loading else {
            return nil
        }
        guard let loadedRange else {
            return load(shouldCloseSettings: false)
        }
        guard monthStart < loadedRange.start || nextMonth > loadedRange.end else {
            return nil
        }
        if let additionalLoadTask {
            return additionalLoadTask
        }

        let syncRange = syncWindow.range(around: monthStart)
        let activeConnections = connections
        loading = true

        let task = Task {
            let syncResult = await syncService.fetchItems(
                connections: activeConnections,
                rangeStart: syncRange.start,
                rangeEnd: syncRange.end
            )

            await MainActor.run {
                logSyncDiagnostics(syncResult.diagnostics)
                mergeAdditionalSyncResult(syncResult, loadedRange: syncRange)
                loading = false
                additionalLoadTask = nil
            }
        }
        additionalLoadTask = task
        return task
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func mergeAdditionalSyncResult(
        _ syncResult: CalendarSyncResult,
        loadedRange newRange: (start: Date, end: Date)
    ) {
        let knownCalendars = Set(items.map(\.sourceCalendar))
        items = mergedItems(existing: items, incoming: syncResult.items)
            .sorted(by: CalendarItemOrdering.compareItems)
        diagnostics.append(contentsOf: syncResult.diagnostics)
        connectionErrors.merge(syncResult.connectionErrors) { _, new in new }
        visibleCalendars.formUnion(Set(syncResult.items.map(\.sourceCalendar)).subtracting(knownCalendars))
        loadedRange = unionLoadedRange(loadedRange, newRange)
        layoutRevision += 1
        saveWidgetSnapshot()
    }

    /// DEBUG-only file logging is intentionally local to the sandbox tmp folder.
    /// It lets us diagnose real CalDAV/Google bottlenecks without exposing tokens
    /// or storing persistent personal data in the repository.
    private func logSyncDiagnostics(_ entries: [String]) {
        #if DEBUG
            let lines = entries.map { "[lendar-sync] \($0)" }
            for entry in entries {
                print("[lendar-sync] \(entry)")
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("lendar-sync.log")
            let payload = (["--- \(Date()) ---"] + lines).joined(separator: "\n") + "\n"
            if let data = payload.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path),
                   let handle = try? FileHandle(forWritingTo: url)
                {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    try? data.write(to: url, options: .atomic)
                }
            }
        #endif
    }

    private func mergedItems(existing: [CalendarItem], incoming: [CalendarItem]) -> [CalendarItem] {
        var merged: [String: CalendarItem] = [:]
        for item in existing + incoming {
            merged[item.syncIdentityKey] = item
        }
        return Array(merged.values)
    }

    private func unionLoadedRange(
        _ current: (start: Date, end: Date)?,
        _ next: (start: Date, end: Date)
    ) -> (start: Date, end: Date) {
        guard let current else {
            return next
        }
        return (min(current.start, next.start), max(current.end, next.end))
    }

    private func applyCustomColor(_ item: CalendarItem) -> CalendarItem {
        guard let customCode = customCalendarColorCodes[item.sourceCalendar] else {
            return item
        }
        return item.withSourceColorCode(customCode)
    }

    private func restoreCustomCalendarColors() {
        let shared = connectionManager.loadCustomCalendarColorCodes()
        if let data = userDefaults.data(forKey: customCalendarColorKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
            customCalendarColorCodes = shared.merging(decoded) { _, local in local }
        } else {
            customCalendarColorCodes = shared
        }
        connectionManager.saveCustomCalendarColorCodes(customCalendarColorCodes)
    }

    private func persistCustomCalendarColors() {
        guard let data = try? JSONEncoder().encode(customCalendarColorCodes) else {
            return
        }
        userDefaults.set(data, forKey: customCalendarColorKey)
        connectionManager.saveCustomCalendarColorCodes(customCalendarColorCodes)
    }

    private func saveWidgetSnapshot() {
        // Widgets cannot safely run the same network/auth flow as the app. The app is
        // the source of truth: after every sync/color change it writes a flattened,
        // already-colored event snapshot that the WidgetKit extension reads.
        let snapshots = WidgetSnapshotMapper.snapshots(from: items, colorCode: colorCode(for:))
        try? widgetSnapshotWriter.save(snapshots)
        connectionManager.saveWidgetEventSnapshots(snapshots)
        widgetSnapshotWriter.refreshWidgets()
    }
}

private extension CalendarItem {
    /// Stable enough to merge repeated range fetches without keeping duplicate rows
    /// when sync windows overlap.
    var syncIdentityKey: String {
        [
            type.rawValue,
            sourceCalendar,
            uid,
            startDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
            endDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
        ].joined(separator: "|")
    }
}
