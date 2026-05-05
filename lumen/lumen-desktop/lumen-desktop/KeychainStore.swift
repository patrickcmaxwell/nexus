import Foundation
import Security

/// Tiny wrapper around macOS Keychain (Security framework, generic password
/// class). Used by `LumenAuthRegistry` to persist `nx_session` cookies per
/// human across app launches without leaving them lying in UserDefaults.
///
/// Why Keychain over @AppStorage:
///   - Encrypted at rest by the OS
///   - Survives "delete app, reinstall" cycles when the user wants
///   - Standard mac security primitive — what every native app uses for creds
///
/// Service identifier groups every Lumen secret under one logical bucket so
/// they show up together in Keychain Access.app and can be cleared in bulk
/// if the Director ever wants to nuke all sessions.
enum KeychainStore {
    private static let service = "nexus.lumen.auth"

    /// Write `value` under `account`. Replaces any existing entry.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Replace if already present
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(newItem as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Read the string under `account`, or nil if absent.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete the entry under `account`. No-op if absent.
    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    /// List every account under our service. Used to discover known users
    /// on app launch.
    static func allAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let arr = items as? [[String: Any]] else { return [] }
        return arr.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
