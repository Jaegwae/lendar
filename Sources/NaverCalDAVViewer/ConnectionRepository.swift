import Foundation

/// Minimal password storage surface needed by `ConnectionRepository`.
///
/// The production adapter writes to Keychain in release and debug defaults in DEBUG.
/// Tests use an in-memory implementation so migration/upsert/delete behavior can be
/// verified without touching global Keychain state.
protocol ConnectionPasswordStoring: AnyObject {
    func save(_ password: String, account: String)
    func load(account: String) -> String?
    func delete(account: String)
    func clearDebugPasswords()
}

/// Production password-store adapter backed by `ConnectionPasswordStore`.
final class LiveConnectionPasswordStore: ConnectionPasswordStoring {
    func save(_ password: String, account: String) {
        ConnectionPasswordStore.save(password, account: account)
    }

    func load(account: String) -> String? {
        ConnectionPasswordStore.load(account: account)
    }

    func delete(account: String) {
        ConnectionPasswordStore.delete(account: account)
    }

    func clearDebugPasswords() {
        ConnectionPasswordStore.clearDebugPasswords()
    }
}

/// Minimal shared-data storage surface for app/widget payloads.
///
/// Production uses Data Protection Keychain; tests can provide a memory store.
protocol SharedDataStoring: AnyObject {
    func save(_ data: Data, account: String)
    func load(account: String) -> Data?
    func delete(account: String)
}

/// Production shared-data adapter backed by `SharedKeychainStore`.
final class LiveSharedDataStore: SharedDataStoring {
    func save(_ data: Data, account: String) {
        SharedKeychainStore.save(data, account: account)
    }

    func load(account: String) -> Data? {
        SharedKeychainStore.load(account: account)
    }

    func delete(account: String) {
        SharedKeychainStore.delete(account: account)
    }
}

/// Repository for connection metadata, secrets, legacy migration, and widget
/// shared payloads.
///
/// `ConnectionStore` remains as the app-wide static facade. This repository holds
/// the implementation so tests can inject isolated UserDefaults/password/shared
/// stores and verify persistence behavior without side effects.
final class ConnectionRepository {
    private static let accountKey = "naver_connection_account"
    private static let monthsKey = "naver_connection_months"
    private static let sharedConnectionAccount = "naver_connection_shared"
    private static let sharedColorsAccount = "naver_calendar_colors_shared"
    private static let sharedWidgetSnapshotsAccount = "naver_calendar_widget_snapshots_shared"
    private static let connectionsKey = "calendar.connections.v2"

    private let defaults: UserDefaults
    private let passwordStore: ConnectionPasswordStoring
    private let sharedStore: SharedDataStoring

    init(
        defaults: UserDefaults = .standard,
        passwordStore: ConnectionPasswordStoring = LiveConnectionPasswordStore(),
        sharedStore: SharedDataStoring = LiveSharedDataStore()
    ) {
        self.defaults = defaults
        self.passwordStore = passwordStore
        self.sharedStore = sharedStore
    }

    func saveConnections(_ connections: [CalendarConnection]) {
        // Connection metadata lives in UserDefaults, while the secret value lives in
        // Keychain (release) or per-account debug defaults (debug). Do not put
        // passwords/refresh tokens into StoredConnection.
        let stored = connections.map {
            StoredConnection(
                id: $0.id,
                provider: ConnectionNormalizer.provider(for: $0.serverURL, explicit: $0.provider),
                email: ConnectionNormalizer.username($0.email),
                serverURL: ConnectionNormalizer.serverURL($0.serverURL)
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.connectionsKey)
        }

        for connection in connections {
            passwordStore.save(connection.password, account: connectionPasswordAccount(connection.id))
        }

        if let first = connections.first {
            save(username: first.email, password: first.password, monthsAhead: "all")
        } else {
            clear()
        }
    }

    func loadConnections() -> [CalendarConnection] {
        // v2 is the first multi-account format. Missing v2 data means the user is
        // coming from the old single-account Naver-only build, so migrate once.
        if let data = defaults.data(forKey: Self.connectionsKey),
           let stored = try? JSONDecoder().decode([StoredConnection].self, from: data)
        {
            var needsRewrite = false
            let connections = stored.compactMap { item -> CalendarConnection? in
                guard let password = passwordStore.load(account: connectionPasswordAccount(item.id)) else {
                    return nil
                }
                let normalizedServerURL = ConnectionNormalizer.serverURL(item.serverURL)
                let normalizedProvider = ConnectionNormalizer.provider(
                    for: normalizedServerURL,
                    explicit: item.provider ?? "caldav"
                )
                let normalizedEmail = ConnectionNormalizer.username(item.email)
                if item.provider != normalizedProvider ||
                    item.serverURL != normalizedServerURL ||
                    item.email != normalizedEmail
                {
                    needsRewrite = true
                }
                return CalendarConnection(
                    id: item.id,
                    provider: normalizedProvider,
                    email: normalizedEmail,
                    password: password,
                    serverURL: normalizedServerURL
                )
            }
            if needsRewrite {
                saveConnections(connections)
            }
            return connections
        }

        guard let legacy = load() else {
            return []
        }

        let migrated = CalendarConnection(
            id: UUID().uuidString,
            provider: "caldav",
            email: ConnectionNormalizer.username(legacy.username),
            password: legacy.password,
            serverURL: "https://caldav.calendar.naver.com"
        )
        saveConnections([migrated])
        return [migrated]
    }

    func upsertConnection(_ connection: CalendarConnection) {
        var connections = loadConnections()
        let normalized = CalendarConnection(
            id: connection.id.isEmpty ? UUID().uuidString : connection.id,
            provider: ConnectionNormalizer.provider(for: connection.serverURL, explicit: connection.provider),
            email: ConnectionNormalizer.username(connection.email),
            password: connection.password,
            serverURL: ConnectionNormalizer.serverURL(connection.serverURL)
        )

        // Treat email as unique for now. This lets a failed manual Google CalDAV entry
        // be replaced cleanly by the correct OAuth-backed Google connection.
        if let index = connections.firstIndex(where: { $0.id == normalized.id || $0.email == normalized.email }) {
            connections[index] = normalized
        } else {
            connections.append(normalized)
        }
        saveConnections(connections)
    }

    func deleteConnection(id: String) {
        let next = loadConnections().filter { $0.id != id }
        passwordStore.delete(account: connectionPasswordAccount(id))
        saveConnections(next)
    }

    func save(username: String, password: String, monthsAhead: String) {
        let normalized = ConnectionNormalizer.username(username)
        defaults.set(normalized, forKey: Self.accountKey)
        defaults.set(monthsAhead, forKey: Self.monthsKey)
        passwordStore.save(password, account: normalized)
        saveSharedConnection(username: normalized, password: password, monthsAhead: monthsAhead)
    }

    func load() -> (username: String, password: String, monthsAhead: String)? {
        guard let storedUsername = defaults.string(forKey: Self.accountKey) else {
            return loadSharedConnection()
        }

        let normalized = ConnectionNormalizer.username(storedUsername)
        let password = passwordStore.load(account: normalized) ??
            passwordStore.load(account: storedUsername)
        guard let password else { return nil }

        if normalized != storedUsername {
            save(username: normalized, password: password, monthsAhead: defaults.string(forKey: Self.monthsKey) ?? "6")
            passwordStore.delete(account: storedUsername)
        }

        let monthsAhead = defaults.string(forKey: Self.monthsKey) ?? "6"
        return (normalized, password, monthsAhead)
    }

    func clear() {
        guard let username = defaults.string(forKey: Self.accountKey) else {
            defaults.removeObject(forKey: Self.monthsKey)
            passwordStore.clearDebugPasswords()
            return
        }

        passwordStore.clearDebugPasswords()
        clearSharedConnection()
        passwordStore.delete(account: ConnectionNormalizer.username(username))
        passwordStore.delete(account: username)
        defaults.removeObject(forKey: Self.accountKey)
        defaults.removeObject(forKey: Self.monthsKey)
    }

    func loadSharedConnection() -> (username: String, password: String, monthsAhead: String)? {
        guard let data = sharedStore.load(account: Self.sharedConnectionAccount),
              let decoded = try? JSONDecoder().decode(SharedConnection.self, from: data)
        else {
            return nil
        }
        return (decoded.username, decoded.password, decoded.monthsAhead)
    }

    func saveCustomCalendarColorCodes(_ colorCodes: [String: String]) {
        guard let data = try? JSONEncoder().encode(colorCodes) else {
            return
        }
        sharedStore.save(data, account: Self.sharedColorsAccount)
    }

    func loadCustomCalendarColorCodes() -> [String: String] {
        guard let data = sharedStore.load(account: Self.sharedColorsAccount),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    func saveWidgetEventSnapshots(_ snapshots: [WidgetEventSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }
        sharedStore.save(data, account: Self.sharedWidgetSnapshotsAccount)
    }

    func loadWidgetEventSnapshots() -> [WidgetEventSnapshot] {
        guard let data = sharedStore.load(account: Self.sharedWidgetSnapshotsAccount),
              let decoded = try? JSONDecoder().decode([WidgetEventSnapshot].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func connectionPasswordAccount(_ id: String) -> String {
        "calendar_connection_password_\(id)"
    }

    private func saveSharedConnection(username: String, password: String, monthsAhead: String) {
        let connection = SharedConnection(username: username, password: password, monthsAhead: monthsAhead)
        guard let data = try? JSONEncoder().encode(connection) else {
            return
        }
        sharedStore.save(data, account: Self.sharedConnectionAccount)
    }

    private func clearSharedConnection() {
        sharedStore.delete(account: Self.sharedConnectionAccount)
    }
}

private struct SharedConnection: Codable {
    let username: String
    let password: String
    let monthsAhead: String
}

private struct StoredConnection: Codable {
    let id: String
    let provider: String?
    let email: String
    let serverURL: String
}
