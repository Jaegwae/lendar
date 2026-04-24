import Foundation

/// Static production facade for calendar connection persistence.
///
/// Most app code should depend on `CalendarConnectionManaging` when testability is
/// useful. This facade preserves the original call sites that need global
/// production storage, including the widget extension snapshot loader.
enum ConnectionStore {
    private static func repository() -> ConnectionRepository {
        ConnectionRepository()
    }

    static func saveConnections(_ connections: [CalendarConnection]) {
        repository().saveConnections(connections)
    }

    static func loadConnections() -> [CalendarConnection] {
        repository().loadConnections()
    }

    static func upsertConnection(_ connection: CalendarConnection) {
        repository().upsertConnection(connection)
    }

    static func deleteConnection(id: String) {
        repository().deleteConnection(id: id)
    }

    static func save(username: String, password: String, monthsAhead: String) {
        repository().save(username: username, password: password, monthsAhead: monthsAhead)
    }

    static func load() -> (username: String, password: String, monthsAhead: String)? {
        repository().load()
    }

    static func clear() {
        repository().clear()
    }

    static func loadSharedConnection() -> (username: String, password: String, monthsAhead: String)? {
        repository().loadSharedConnection()
    }

    static func saveCustomCalendarColorCodes(_ colorCodes: [String: String]) {
        repository().saveCustomCalendarColorCodes(colorCodes)
    }

    static func loadCustomCalendarColorCodes() -> [String: String] {
        repository().loadCustomCalendarColorCodes()
    }

    static func saveWidgetEventSnapshots(_ snapshots: [WidgetEventSnapshot]) {
        repository().saveWidgetEventSnapshots(snapshots)
    }

    static func loadWidgetEventSnapshots() -> [WidgetEventSnapshot] {
        repository().loadWidgetEventSnapshots()
    }
}
