import Foundation
import Security

/// Stores small app-to-widget payloads in the Data Protection Keychain.
///
/// This is separate from account secrets because widget refreshes need stable
/// access to snapshots and color overrides without triggering login-keychain
/// prompts or running network/auth flows inside WidgetKit.
enum SharedKeychainStore {
    private static let service = "calendar.naver.viewer"

    static func save(_ data: Data, account: String) {
        // Shared data is read by the widget extension. Data Protection Keychain avoids
        // the repeated "lendar Widget wants to use confidential information" prompts
        // that occur when a freshly signed debug widget reads login-keychain items.
        deleteVariants(account: account)
        var query = sharedQuery(account: account)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
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

    static func delete(account: String) {
        SecItemDelete(sharedQuery(account: account) as CFDictionary)
    }

    static func deleteVariants(account: String) {
        delete(account: account)
        SecItemDelete(legacySharedQuery(account: account, includeAccessGroup: false) as CFDictionary)
        SecItemDelete(legacySharedQuery(account: account, includeAccessGroup: true) as CFDictionary)
    }

    private static func sharedQuery(account: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
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
            kSecAttrAccount: account,
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
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil)
        else {
            return nil
        }
        return value as? String
    }
}
