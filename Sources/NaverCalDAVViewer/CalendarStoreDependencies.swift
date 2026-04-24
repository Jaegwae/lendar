import Foundation

/// Injectable sync boundary used by `CalendarStore`.
///
/// Production uses `LiveCalendarSyncing`, while tests inject fixed results to
/// exercise UI state transitions without CalDAV/Google network calls.
protocol CalendarSyncing: Sendable {
    func fetchItems(
        connections: [CalendarConnection],
        rangeStart: Date,
        rangeEnd: Date
    ) async -> CalendarSyncResult
}

/// Production sync adapter that delegates to `CalendarSyncService`.
struct LiveCalendarSyncing: CalendarSyncing {
    func fetchItems(
        connections: [CalendarConnection],
        rangeStart: Date,
        rangeEnd: Date
    ) async -> CalendarSyncResult {
        await CalendarSyncService.fetchItems(
            connections: connections,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
    }
}

/// Injectable persistence boundary for calendar connection metadata, colors,
/// and widget-shared snapshots.
///
/// The implementation is synchronous because the underlying storage is currently
/// UserDefaults/Keychain. A protocol keeps `CalendarStore` tests isolated from
/// global process storage.
protocol CalendarConnectionManaging: AnyObject {
    func loadConnections() -> [CalendarConnection]
    func upsertConnection(_ connection: CalendarConnection)
    func deleteConnection(id: String)
    func clear()
    func loadCustomCalendarColorCodes() -> [String: String]
    func saveCustomCalendarColorCodes(_ colorCodes: [String: String])
    func saveWidgetEventSnapshots(_ snapshots: [WidgetEventSnapshot])
}

/// Production connection persistence adapter backed by `ConnectionStore`.
final class LiveCalendarConnectionManager: CalendarConnectionManaging {
    func loadConnections() -> [CalendarConnection] {
        ConnectionStore.loadConnections()
    }

    func upsertConnection(_ connection: CalendarConnection) {
        ConnectionStore.upsertConnection(connection)
    }

    func deleteConnection(id: String) {
        ConnectionStore.deleteConnection(id: id)
    }

    func clear() {
        ConnectionStore.clear()
    }

    func loadCustomCalendarColorCodes() -> [String: String] {
        ConnectionStore.loadCustomCalendarColorCodes()
    }

    func saveCustomCalendarColorCodes(_ colorCodes: [String: String]) {
        ConnectionStore.saveCustomCalendarColorCodes(colorCodes)
    }

    func saveWidgetEventSnapshots(_ snapshots: [WidgetEventSnapshot]) {
        ConnectionStore.saveWidgetEventSnapshots(snapshots)
    }
}

/// Injectable local widget snapshot writer.
///
/// This handles the app-group JSON file and WidgetKit refresh trigger separately
/// from the Keychain-backed shared snapshot stored by `CalendarConnectionManaging`.
protocol WidgetSnapshotWriting: AnyObject {
    func save(_ snapshots: [WidgetEventSnapshot]) throws
    func refreshWidgets()
}

/// Production widget snapshot writer backed by `WidgetSnapshotStore`.
final class LiveWidgetSnapshotWriter: WidgetSnapshotWriting {
    func save(_ snapshots: [WidgetEventSnapshot]) throws {
        try WidgetSnapshotStore.save(snapshots)
    }

    func refreshWidgets() {
        WidgetSnapshotStore.refreshWidgets()
    }
}
