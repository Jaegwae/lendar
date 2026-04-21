import Foundation
import Security

struct CalendarConnection: Identifiable, Codable, Equatable {
    var id: String
    var provider: String = "caldav"
    var email: String
    var password: String
    var serverURL: String

    var displayEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "CalDAV 계정"
        }
        return trimmed
    }

    var displayServer: String {
        if provider == "google" {
            return "calendar.google.com"
        }
        return serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum ConnectionStore {
    private static let service = "calendar.naver.viewer"
    private static let accountKey = "naver_connection_account"
    private static let monthsKey = "naver_connection_months"
    private static let debugPasswordKey = "naver_connection_password_debug"
    private static let sharedConnectionAccount = "naver_connection_shared"
    private static let sharedColorsAccount = "naver_calendar_colors_shared"
    private static let sharedWidgetSnapshotsAccount = "naver_calendar_widget_snapshots_shared"
    private static let connectionsKey = "calendar.connections.v2"

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

    static func saveConnections(_ connections: [CalendarConnection]) {
        // Connection metadata lives in UserDefaults, while the secret value lives in
        // Keychain (release) or per-account debug defaults (debug). Do not put
        // passwords/refresh tokens into StoredConnection.
        let stored = connections.map {
            StoredConnection(
                id: $0.id,
                provider: provider(for: $0.serverURL, explicit: $0.provider),
                email: normalizedUsername($0.email),
                serverURL: normalizedServerURL($0.serverURL)
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: connectionsKey)
        }

        for connection in connections {
            savePassword(connection.password, account: connectionPasswordAccount(connection.id))
        }

        if let first = connections.first {
            save(username: first.email, password: first.password, monthsAhead: "all")
        } else {
            clear()
        }
    }

    static func loadConnections() -> [CalendarConnection] {
        // v2 is the first multi-account format. Missing v2 data means the user is
        // coming from the old single-account Naver-only build, so migrate once.
        if let data = UserDefaults.standard.data(forKey: connectionsKey),
           let stored = try? JSONDecoder().decode([StoredConnection].self, from: data) {
            return stored.compactMap { item in
                guard let password = loadPassword(account: connectionPasswordAccount(item.id)) else {
                    return nil
                }
                return CalendarConnection(
                    id: item.id,
                    provider: item.provider ?? provider(for: item.serverURL),
                    email: item.email,
                    password: password,
                    serverURL: normalizedServerURL(item.serverURL)
                )
            }
        }

        guard let legacy = load() else {
            return []
        }

        let migrated = CalendarConnection(
            id: UUID().uuidString,
            provider: "caldav",
            email: normalizedUsername(legacy.username),
            password: legacy.password,
            serverURL: "https://caldav.calendar.naver.com"
        )
        saveConnections([migrated])
        return [migrated]
    }

    static func upsertConnection(_ connection: CalendarConnection) {
        var connections = loadConnections()
        let normalized = CalendarConnection(
            id: connection.id.isEmpty ? UUID().uuidString : connection.id,
            provider: provider(for: connection.serverURL, explicit: connection.provider),
            email: normalizedUsername(connection.email),
            password: connection.password,
            serverURL: normalizedServerURL(connection.serverURL)
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

    static func deleteConnection(id: String) {
        let next = loadConnections().filter { $0.id != id }
        deletePassword(account: connectionPasswordAccount(id))
        saveConnections(next)
    }

    static func save(username: String, password: String, monthsAhead: String) {
        let normalized = normalizedUsername(username)
        UserDefaults.standard.set(normalized, forKey: accountKey)
        UserDefaults.standard.set(monthsAhead, forKey: monthsKey)
        savePassword(password, account: normalized)
        saveSharedConnection(username: normalized, password: password, monthsAhead: monthsAhead)
    }

    static func load() -> (username: String, password: String, monthsAhead: String)? {
        guard let storedUsername = UserDefaults.standard.string(forKey: accountKey) else {
            return loadSharedConnection()
        }

        let normalized = normalizedUsername(storedUsername)
        let password = loadPassword(account: normalized) ?? loadPassword(account: storedUsername)
        guard let password else { return nil }

        if normalized != storedUsername {
            save(username: normalized, password: password, monthsAhead: UserDefaults.standard.string(forKey: monthsKey) ?? "6")
            deletePassword(account: storedUsername)
        }

        let monthsAhead = UserDefaults.standard.string(forKey: monthsKey) ?? "6"
        return (normalized, password, monthsAhead)
    }

    static func clear() {
        guard let username = UserDefaults.standard.string(forKey: accountKey) else {
            UserDefaults.standard.removeObject(forKey: monthsKey)
            clearDebugPasswords()
            return
        }

        clearDebugPasswords()
        clearSharedConnection()
        deletePassword(account: normalizedUsername(username))
        deletePassword(account: username)
        UserDefaults.standard.removeObject(forKey: accountKey)
        UserDefaults.standard.removeObject(forKey: monthsKey)
    }

    static func loadSharedConnection() -> (username: String, password: String, monthsAhead: String)? {
        guard let data = loadSharedData(account: sharedConnectionAccount),
              let decoded = try? JSONDecoder().decode(SharedConnection.self, from: data) else {
            return nil
        }
        return (decoded.username, decoded.password, decoded.monthsAhead)
    }

    static func saveCustomCalendarColorCodes(_ colorCodes: [String: String]) {
        guard let data = try? JSONEncoder().encode(colorCodes) else {
            return
        }
        saveSharedData(data, account: sharedColorsAccount)
    }

    static func loadCustomCalendarColorCodes() -> [String: String] {
        guard let data = loadSharedData(account: sharedColorsAccount),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func saveWidgetEventSnapshots(_ snapshots: [WidgetEventSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }
        saveSharedData(data, account: sharedWidgetSnapshotsAccount)
    }

    static func loadWidgetEventSnapshots() -> [WidgetEventSnapshot] {
        guard let data = loadSharedData(account: sharedWidgetSnapshotsAccount),
              let decoded = try? JSONDecoder().decode([WidgetEventSnapshot].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func normalizedUsername(_ username: String) -> String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed.contains("@") {
            return trimmed
        }
        return "\(trimmed)@naver.com"
    }

    private static func normalizedServerURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "https://caldav.calendar.naver.com"
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased() else {
            return normalized
        }

        if host == "www.google.com", url.path.lowercased().hasPrefix("/calendar/dav") {
            return "https://apidata.googleusercontent.com/caldav/v2"
        }

        if host == "calendar.google.com", url.path.lowercased().contains("calendar/dav") {
            return "https://apidata.googleusercontent.com/caldav/v2"
        }

        return normalized
    }

    private static func connectionPasswordAccount(_ id: String) -> String {
        "calendar_connection_password_\(id)"
    }

    private static func provider(for serverURL: String, explicit: String = "caldav") -> String {
        // The settings UI supports both manual CalDAV and Google OAuth. Provider must
        // survive persistence because Google's secret is a refresh token, not a CalDAV
        // password, and CalendarStore dispatches to different network clients.
        if explicit == "google" {
            return "google"
        }

        let lowercased = serverURL.lowercased()
        if lowercased.contains("googleusercontent.com") ||
            lowercased.contains("calendar.google.com") ||
            lowercased.contains("googleapis.com") ||
            lowercased.contains("www.google.com/calendar/dav") {
            return "google"
        }

        return "caldav"
    }

    private static func savePassword(_ password: String, account: String) {
        #if DEBUG
        // Debug builds do not use real Keychain to keep local iteration fast, but each
        // connection still needs its own secret key. A single debug key caused Google
        // refresh tokens and Naver app passwords to overwrite each other.
        UserDefaults.standard.set(password, forKey: debugPasswordKey(for: account))
        #else
        let data = Data(password.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
        #endif
    }

    private static func saveSharedConnection(username: String, password: String, monthsAhead: String) {
        let connection = SharedConnection(username: username, password: password, monthsAhead: monthsAhead)
        guard let data = try? JSONEncoder().encode(connection) else {
            return
        }
        saveSharedData(data, account: sharedConnectionAccount)
    }

    private static func clearSharedConnection() {
        deleteSharedData(account: sharedConnectionAccount)
    }

    private static func loadPassword(account: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: debugPasswordKey(for: account)) ??
            UserDefaults.standard.string(forKey: debugPasswordKey)
        #else
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
        #endif
    }

    private static func deletePassword(account: String) {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: debugPasswordKey(for: account))
        #endif
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func debugPasswordKey(for account: String) -> String {
        "\(debugPasswordKey).\(account)"
    }

    private static func clearDebugPasswords() {
        UserDefaults.standard.removeObject(forKey: debugPasswordKey)
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("\(debugPasswordKey).") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func saveSharedData(_ data: Data, account: String) {
        // Shared data is read by the widget extension. Data Protection Keychain avoids
        // the repeated "lendar Widget wants to use confidential information" prompts
        // that occur when a freshly signed debug widget reads login-keychain items.
        deleteSharedDataVariants(account: account)
        var query = sharedQuery(account: account)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadSharedData(account: String) -> Data? {
        var query = sharedQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func deleteSharedData(account: String) {
        SecItemDelete(sharedQuery(account: account) as CFDictionary)
    }

    private static func deleteSharedDataVariants(account: String) {
        deleteSharedData(account: account)
        SecItemDelete(legacySharedQuery(account: account, includeAccessGroup: false) as CFDictionary)
        SecItemDelete(legacySharedQuery(account: account, includeAccessGroup: true) as CFDictionary)
    }

    private static func sharedQuery(account: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true
        ]

        if let accessGroup = sharedAccessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }

        return query
    }

    private static func legacySharedQuery(account: String, includeAccessGroup: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        if includeAccessGroup, let accessGroup = sharedAccessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }

        return query
    }

    private static var sharedAccessGroup: String? {
        guard let teamIdentifier else {
            return nil
        }
        return "\(teamIdentifier).calendar.naver.viewer.shared"
    }

    private static var teamIdentifier: String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) else {
            return nil
        }
        return value as? String
    }
}
