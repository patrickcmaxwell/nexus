import Foundation
import Security

// KeychainHelper
//
// Tiny wrapper over Security.framework for reading/writing app secrets.
// Used to keep API keys out of source — the alternative was leaving
// `anthropicApiKey = "PASTE_YOUR_KEY_HERE"` in `LumenAPIManager.swift`,
// one accidental edit away from a public-repo leak.
//
// Lookup precedence at call sites: env var (fast iteration in Xcode) →
// keychain (production builds) → empty string (caller decides what to do).

enum KeychainHelper {
    /// Read a value from the macOS keychain. Returns nil when missing.
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecMatchLimit as String:      kSecMatchLimitOne,
            kSecReturnData as String:      true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Insert or replace a keychain entry. Returns true on success.
    @discardableResult
    static func write(service: String, account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Build base query — these fields uniquely identify the entry.
        let baseQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Try update first; if no row exists, insert.
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            // Block iCloud sync — these are device-local app secrets, not
            // user-portable creds.
            addQuery[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    /// Remove a keychain entry. Returns true even when the entry was missing
    /// — callers are deleting state, not asserting it existed.
    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
