// KeychainHelper.swift
// Tiny Keychain wrapper used to store the active session token + the
// per-human profile cache. Mirrors the desktop's KeychainHelper so the
// shape ("service" + "account") matches across platforms.
//
// Why Keychain: the iOS app holds a Bearer token that grants full access
// to the user's Nexus. UserDefaults is plaintext on-device backup; Keychain
// is hardware-backed and never leaves the device. This is the only piece
// the phone holds that an attacker would actually want.

import Foundation
import Security

enum KeychainHelper {
    static let service = "io.talkcircles.nexus.ios"

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str  = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
