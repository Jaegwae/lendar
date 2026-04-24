import Foundation
@testable import NaverCalDAVViewer
import SwiftUI
import XCTest

@MainActor
final class CalendarStoreTests: XCTestCase {
    func testLoadAppliesSyncResultAndWritesWidgetSnapshot() async {
        let event = item(uid: "load-1", summary: "Loaded", sourceCalendar: "Work")
        let sync = CapturingCalendarSyncing(
            result: CalendarSyncResult(
                items: [event],
                diagnostics: ["sync ok"],
                connectionErrors: ["account-1": nil].compactMapValues { $0 },
                connectionCalendarCounts: ["account-1": 1]
            )
        )
        let connections = FakeConnectionManager(
            connections: [
                CalendarConnection(
                    id: "account-1",
                    provider: "caldav",
                    email: "demo@naver.com",
                    password: "secret",
                    serverURL: "https://caldav.calendar.naver.com"
                ),
            ]
        )
        let widget = FakeWidgetSnapshotWriter()
        let store = CalendarStore(
            syncService: sync,
            connectionManager: connections,
            widgetSnapshotWriter: widget,
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )

        await store.load(shouldCloseSettings: false).value

        XCTAssertFalse(store.loading)
        XCTAssertEqual(store.items.map(\.summary), ["Loaded"])
        XCTAssertEqual(store.diagnostics, ["sync ok"])
        XCTAssertEqual(store.connectionCalendarCounts, ["account-1": 1])
        XCTAssertEqual(store.visibleCalendars, ["Work"])
        XCTAssertEqual(store.selectedItemID, event.id)
        XCTAssertTrue(store.showingSettingsSheet)
        XCTAssertEqual(widget.savedSnapshots.map { $0.map(\.title) }, [["Loaded"]])
        XCTAssertEqual(connections.savedWidgetSnapshots.map { $0.map(\.title) }, [["Loaded"]])

        let range = await sync.lastRange()
        XCTAssertNotNil(range)
        if let range {
            let monthSpan = Calendar.current.dateComponents([.month], from: range.start, to: range.end).month
            XCTAssertEqual(monthSpan, 37)
        }
    }

    func testDeleteLastConnectionClearsStateAndSnapshots() {
        let connections = FakeConnectionManager(connections: [])
        let widget = FakeWidgetSnapshotWriter()
        let store = CalendarStore(
            syncService: FakeCalendarSyncing(result: .empty),
            connectionManager: connections,
            widgetSnapshotWriter: widget,
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )
        store.items = [item(uid: "stale", summary: "Stale", sourceCalendar: "Work")]
        store.visibleCalendars = ["Work"]
        store.selectedItemID = store.items[0].id
        store.hasSavedConnection = true

        let reloadTask = store.deleteConnection(id: "account-1")

        XCTAssertNil(reloadTask)
        XCTAssertEqual(connections.deletedIDs, ["account-1"])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.visibleCalendars.isEmpty)
        XCTAssertNil(store.selectedItemID)
        XCTAssertFalse(store.hasSavedConnection)
        XCTAssertEqual(widget.savedSnapshots.map(\.count), [0])
        XCTAssertEqual(widget.refreshCount, 1)
    }

    func testJumpingOutsideLoadedRangeFetchesAndMergesAdditionalWindow() async throws {
        let initial = item(uid: "initial", summary: "Initial", sourceCalendar: "Work")
        let far = try item(uid: "far", summary: "Far", sourceCalendar: "Work", start: XCTUnwrap(Calendar.current.date(byAdding: .year, value: 5, to: Date())))
        let sync = SequenceCalendarSyncing(results: [
            CalendarSyncResult(items: [initial], diagnostics: ["initial"], connectionErrors: [:], connectionCalendarCounts: ["account-1": 1]),
            CalendarSyncResult(items: [far], diagnostics: ["far"], connectionErrors: [:], connectionCalendarCounts: ["account-1": 1]),
        ])
        let store = CalendarStore(
            syncService: sync,
            connectionManager: FakeConnectionManager(connections: [connection()]),
            widgetSnapshotWriter: FakeWidgetSnapshotWriter(),
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )

        await store.load(shouldCloseSettings: false).value
        let loadTask = store.jumpToMonth(far.startDate ?? Date())
        await loadTask?.value

        XCTAssertEqual(Set(store.items.map(\.summary)), Set(["Initial", "Far"]))
        XCTAssertEqual(store.diagnostics, ["initial", "far"])
        let callCount = await sync.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testJumpingInsideLoadedRangeDoesNotFetchAgain() async {
        let sync = SequenceCalendarSyncing(results: [
            CalendarSyncResult(
                items: [item(uid: "initial", summary: "Initial", sourceCalendar: "Work")],
                diagnostics: ["initial"],
                connectionErrors: [:],
                connectionCalendarCounts: ["account-1": 1]
            ),
        ])
        let store = CalendarStore(
            syncService: sync,
            connectionManager: FakeConnectionManager(connections: [connection()]),
            widgetSnapshotWriter: FakeWidgetSnapshotWriter(),
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )

        await store.load(shouldCloseSettings: false).value
        let loadTask = store.jumpToMonth(Date())
        await loadTask?.value

        XCTAssertNil(loadTask)
        let callCount = await sync.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testDeleteRemainingConnectionTriggersReload() async {
        let event = item(uid: "remaining", summary: "Remaining", sourceCalendar: "Work")
        let connections = FakeConnectionManager(
            connections: [
                CalendarConnection(
                    id: "remaining-account",
                    provider: "caldav",
                    email: "demo@naver.com",
                    password: "secret",
                    serverURL: "https://caldav.calendar.naver.com"
                ),
            ]
        )
        let store = CalendarStore(
            syncService: FakeCalendarSyncing(
                result: CalendarSyncResult(
                    items: [event],
                    diagnostics: ["reloaded"],
                    connectionErrors: [:],
                    connectionCalendarCounts: ["remaining-account": 1]
                )
            ),
            connectionManager: connections,
            widgetSnapshotWriter: FakeWidgetSnapshotWriter(),
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )

        let reloadTask = store.deleteConnection(id: "old-account")
        await reloadTask?.value

        XCTAssertEqual(connections.deletedIDs, ["old-account"])
        XCTAssertEqual(store.items.map(\.summary), ["Remaining"])
        XCTAssertEqual(store.diagnostics, ["reloaded"])
    }

    func testDisconnectClearsConnectionsAndWidgetSnapshots() {
        let connections = FakeConnectionManager(connections: [])
        let widget = FakeWidgetSnapshotWriter()
        let store = CalendarStore(
            syncService: FakeCalendarSyncing(result: .empty),
            connectionManager: connections,
            widgetSnapshotWriter: widget,
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )
        store.items = [item(uid: "loaded", summary: "Loaded", sourceCalendar: "Work")]
        store.visibleCalendars = ["Work"]
        store.hasSavedConnection = true

        store.disconnect()

        XCTAssertTrue(connections.didClear)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertFalse(store.hasSavedConnection)
        XCTAssertEqual(widget.savedSnapshots.map(\.count), [0])
        XCTAssertEqual(connections.savedWidgetSnapshots.map(\.count), [0])
    }

    func testSetCalendarColorPersistsAndSnapshotsUseOverride() {
        let connections = FakeConnectionManager(connections: [])
        let widget = FakeWidgetSnapshotWriter()
        let store = CalendarStore(
            syncService: FakeCalendarSyncing(result: .empty),
            connectionManager: connections,
            widgetSnapshotWriter: widget,
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )
        store.items = [item(uid: "color", summary: "Color", sourceCalendar: "Work", sourceColorCode: "0")]

        store.setCalendarColor(Color(red: 1, green: 0, blue: 0), for: "Work")

        XCTAssertEqual(connections.savedColorCodes.count, 2)
        XCTAssertEqual(store.colorCode(for: "Work"), "custom:FF0000")
        XCTAssertEqual(widget.savedSnapshots.last?.first?.colorCode, "custom:FF0000")
        XCTAssertEqual(connections.savedWidgetSnapshots.last?.first?.colorCode, "custom:FF0000")
    }

    func testFocusAndOpenDayUpdateSelectionState() {
        let selected = item(uid: "selected", summary: "Selected", sourceCalendar: "Work", start: date(2026, 4, 22))
        let store = CalendarStore(
            syncService: FakeCalendarSyncing(result: .empty),
            connectionManager: FakeConnectionManager(connections: []),
            widgetSnapshotWriter: FakeWidgetSnapshotWriter(),
            userDefaults: isolatedDefaults(),
            autoLoad: false
        )
        store.items = [selected]
        store.visibleCalendars = ["Work"]

        store.focusItem(selected)

        XCTAssertEqual(store.selectedItemID, selected.id)
        XCTAssertTrue(Calendar.current.isDate(store.selectedDate, inSameDayAs: date(2026, 4, 22)))

        store.openDay(date(2026, 4, 22))

        XCTAssertTrue(store.showingDaySheet)
        XCTAssertEqual(store.selectedItemID, selected.id)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CalendarStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func connection(id: String = "account-1") -> CalendarConnection {
        CalendarConnection(
            id: id,
            provider: "caldav",
            email: "demo@naver.com",
            password: "secret",
            serverURL: "https://caldav.calendar.naver.com"
        )
    }

    private func item(
        uid: String,
        summary: String,
        sourceCalendar: String,
        sourceColorCode: String = "0",
        start: Date = Date(timeIntervalSince1970: 0)
    ) -> CalendarItem {
        CalendarItem(
            type: .event,
            uid: uid,
            summary: summary,
            startOrDue: "",
            endOrCompleted: "",
            location: "",
            note: "",
            status: "",
            sourceCalendar: sourceCalendar,
            sourceColorCode: sourceColorCode,
            rawFields: [:],
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false
        )
    }
}

private struct FakeCalendarSyncing: CalendarSyncing {
    let result: CalendarSyncResult

    func fetchItems(
        connections _: [CalendarConnection],
        rangeStart _: Date,
        rangeEnd _: Date
    ) async -> CalendarSyncResult {
        result
    }
}

private actor CapturingCalendarSyncing: CalendarSyncing {
    let result: CalendarSyncResult
    private var capturedRange: (start: Date, end: Date)?

    init(result: CalendarSyncResult) {
        self.result = result
    }

    func fetchItems(
        connections _: [CalendarConnection],
        rangeStart: Date,
        rangeEnd: Date
    ) async -> CalendarSyncResult {
        capturedRange = (rangeStart, rangeEnd)
        return result
    }

    func lastRange() -> (start: Date, end: Date)? {
        capturedRange
    }
}

private actor SequenceCalendarSyncing: CalendarSyncing {
    private var results: [CalendarSyncResult]
    private var index = 0

    init(results: [CalendarSyncResult]) {
        self.results = results
    }

    func fetchItems(
        connections _: [CalendarConnection],
        rangeStart _: Date,
        rangeEnd _: Date
    ) async -> CalendarSyncResult {
        defer { index += 1 }
        return results[min(index, results.count - 1)]
    }

    func callCount() -> Int {
        index
    }
}

private final class FakeConnectionManager: CalendarConnectionManaging {
    var connections: [CalendarConnection]
    var deletedIDs: [String] = []
    var didClear = false
    var savedColorCodes: [[String: String]] = []
    var savedWidgetSnapshots: [[WidgetEventSnapshot]] = []

    init(connections: [CalendarConnection]) {
        self.connections = connections
    }

    func loadConnections() -> [CalendarConnection] {
        connections
    }

    func upsertConnection(_ connection: CalendarConnection) {
        connections = [connection]
    }

    func deleteConnection(id: String) {
        deletedIDs.append(id)
    }

    func clear() {
        didClear = true
        connections = []
    }

    func loadCustomCalendarColorCodes() -> [String: String] {
        [:]
    }

    func saveCustomCalendarColorCodes(_ colorCodes: [String: String]) {
        savedColorCodes.append(colorCodes)
    }

    func saveWidgetEventSnapshots(_ snapshots: [WidgetEventSnapshot]) {
        savedWidgetSnapshots.append(snapshots)
    }
}

private final class FakeWidgetSnapshotWriter: WidgetSnapshotWriting {
    var savedSnapshots: [[WidgetEventSnapshot]] = []
    var refreshCount = 0

    func save(_ snapshots: [WidgetEventSnapshot]) throws {
        savedSnapshots.append(snapshots)
    }

    func refreshWidgets() {
        refreshCount += 1
    }
}

private extension CalendarSyncResult {
    static let empty = CalendarSyncResult(
        items: [],
        diagnostics: [],
        connectionErrors: [:],
        connectionCalendarCounts: [:]
    )
}
