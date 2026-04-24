import Foundation
@testable import NaverCalDAVViewer
import XCTest

final class ConnectionRepositoryTests: XCTestCase {
    func testSaveAndLoadConnectionsKeepSecretsOutOfMetadata() {
        let passwordStore = MemoryPasswordStore()
        let sharedStore = MemorySharedStore()
        let defaults = isolatedDefaults()
        let repository = ConnectionRepository(
            defaults: defaults,
            passwordStore: passwordStore,
            sharedStore: sharedStore
        )
        let connection = CalendarConnection(
            id: "account-1",
            provider: "caldav",
            email: "demo",
            password: "secret",
            serverURL: "caldav.calendar.naver.com/"
        )

        repository.saveConnections([connection])
        let loaded = repository.loadConnections()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].email, "demo@naver.com")
        XCTAssertEqual(loaded[0].password, "secret")
        XCTAssertEqual(loaded[0].serverURL, "https://caldav.calendar.naver.com")
        XCTAssertEqual(passwordStore.saved["calendar_connection_password_account-1"], "secret")
        let metadata = defaults.data(forKey: "calendar.connections.v2") ?? Data()
        XCTAssertFalse(String(data: metadata, encoding: .utf8)?.contains("secret") == true)
    }

    func testUpsertReplacesConnectionWithSameEmail() {
        let repository = ConnectionRepository(
            defaults: isolatedDefaults(),
            passwordStore: MemoryPasswordStore(),
            sharedStore: MemorySharedStore()
        )

        repository.upsertConnection(
            CalendarConnection(
                id: "old",
                provider: "caldav",
                email: "demo@naver.com",
                password: "old-secret",
                serverURL: "https://caldav.example.com"
            )
        )
        repository.upsertConnection(
            CalendarConnection(
                id: "new",
                provider: "google",
                email: "demo@naver.com",
                password: "refresh-token",
                serverURL: "https://www.googleapis.com/calendar/v3"
            )
        )

        let loaded = repository.loadConnections()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "new")
        XCTAssertEqual(loaded[0].provider, "google")
        XCTAssertEqual(loaded[0].password, "refresh-token")
    }

    func testLegacySingleConnectionMigratesToV2Connections() {
        let passwordStore = MemoryPasswordStore()
        let defaults = isolatedDefaults()
        let repository = ConnectionRepository(
            defaults: defaults,
            passwordStore: passwordStore,
            sharedStore: MemorySharedStore()
        )
        repository.save(username: "demo", password: "legacy-secret", monthsAhead: "6")

        let loaded = repository.loadConnections()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].provider, "caldav")
        XCTAssertEqual(loaded[0].email, "demo@naver.com")
        XCTAssertEqual(loaded[0].password, "legacy-secret")
        XCTAssertNotNil(defaults.data(forKey: "calendar.connections.v2"))
        XCTAssertEqual(passwordStore.saved["calendar_connection_password_\(loaded[0].id)"], "legacy-secret")
    }

    func testLoadConnectionsReclassifiesLegacyGoogleCalDAVMetadata() throws {
        let passwordStore = MemoryPasswordStore()
        let defaults = isolatedDefaults()
        let repository = ConnectionRepository(
            defaults: defaults,
            passwordStore: passwordStore,
            sharedStore: MemorySharedStore()
        )
        let legacyGoogle = LegacyStoredConnection(
            id: "google-legacy",
            provider: "caldav",
            email: "User@Gmail.COM",
            serverURL: "calendar.google.com"
        )
        try defaults.set(JSONEncoder().encode([legacyGoogle]), forKey: "calendar.connections.v2")
        passwordStore.save("refresh-token", account: "calendar_connection_password_google-legacy")

        let loaded = repository.loadConnections()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].provider, "google")
        XCTAssertEqual(loaded[0].email, "user@gmail.com")
        XCTAssertEqual(loaded[0].serverURL, "https://calendar.google.com")
        XCTAssertEqual(loaded[0].password, "refresh-token")
    }

    func testDeleteConnectionDeletesOnlySelectedSecretAndResavesRemaining() {
        let passwordStore = MemoryPasswordStore()
        let repository = ConnectionRepository(
            defaults: isolatedDefaults(),
            passwordStore: passwordStore,
            sharedStore: MemorySharedStore()
        )
        repository.saveConnections([
            CalendarConnection(
                id: "one",
                email: "one@example.com",
                password: "one-secret",
                serverURL: "https://caldav.example.com"
            ),
            CalendarConnection(
                id: "two",
                email: "two@example.com",
                password: "two-secret",
                serverURL: "https://caldav.example.com"
            ),
        ])

        repository.deleteConnection(id: "one")
        let loaded = repository.loadConnections()

        XCTAssertEqual(passwordStore.deleted, ["calendar_connection_password_one"])
        XCTAssertEqual(loaded.map(\.id), ["two"])
        XCTAssertEqual(loaded[0].password, "two-secret")
    }

    func testSharedColorAndWidgetSnapshotsRoundTripThroughSharedStore() {
        let repository = ConnectionRepository(
            defaults: isolatedDefaults(),
            passwordStore: MemoryPasswordStore(),
            sharedStore: MemorySharedStore()
        )
        let snapshot = WidgetEventSnapshot(
            id: "widget-1",
            title: "Widget",
            calendarName: "Work",
            startTimestamp: 1,
            endTimestamp: 2,
            isAllDay: false,
            location: "",
            note: "",
            status: "CONFIRMED",
            colorCode: "0"
        )

        repository.saveCustomCalendarColorCodes(["Work": "custom:FF0000"])
        repository.saveWidgetEventSnapshots([snapshot])

        XCTAssertEqual(repository.loadCustomCalendarColorCodes(), ["Work": "custom:FF0000"])
        XCTAssertEqual(repository.loadWidgetEventSnapshots().map(\.title), ["Widget"])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ConnectionRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct LegacyStoredConnection: Codable {
    let id: String
    let provider: String
    let email: String
    let serverURL: String
}

private final class MemoryPasswordStore: ConnectionPasswordStoring {
    var saved: [String: String] = [:]
    var deleted: [String] = []
    var didClearDebugPasswords = false

    func save(_ password: String, account: String) {
        saved[account] = password
    }

    func load(account: String) -> String? {
        saved[account]
    }

    func delete(account: String) {
        deleted.append(account)
        saved.removeValue(forKey: account)
    }

    func clearDebugPasswords() {
        didClearDebugPasswords = true
    }
}

private final class MemorySharedStore: SharedDataStoring {
    var saved: [String: Data] = [:]
    var deleted: [String] = []

    func save(_ data: Data, account: String) {
        saved[account] = data
    }

    func load(account: String) -> Data? {
        saved[account]
    }

    func delete(account: String) {
        deleted.append(account)
        saved.removeValue(forKey: account)
    }
}
