import Foundation
import Security

/// Stores per-account secrets for calendar connections.
///
/// Release builds use Keychain. Debug builds intentionally use per-account
/// `UserDefaults` keys to avoid repeated local Keychain prompts while developing
/// the app and widget extension.
enum ConnectionPasswordStore {
    private static let service = "calendar.naver.viewer"
    private static let debugPasswordKey = "naver_connection_password_debug"

    static func save(_ password: String, account: String) {
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
                kSecAttrAccount: account,
            ]

            let attributes: [CFString: Any] = [
                kSecValueData: data,
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var addQuery = query
                addQuery[kSecValueData] = data
                SecItemAdd(addQuery as CFDictionary, nil)
            }
        #endif
    }

    static func load(account: String) -> String? {
        #if DEBUG
            return UserDefaults.standard.string(forKey: debugPasswordKey(for: account)) ??
                UserDefaults.standard.string(forKey: debugPasswordKey)
        #else
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let password = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return password
        #endif
    }

    static func delete(account: String) {
        #if DEBUG
            UserDefaults.standard.removeObject(forKey: debugPasswordKey(for: account))
        #endif
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearDebugPasswords() {
        UserDefaults.standard.removeObject(forKey: debugPasswordKey)
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("\(debugPasswordKey).") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func debugPasswordKey(for account: String) -> String {
        "\(debugPasswordKey).\(account)"
    }
}
