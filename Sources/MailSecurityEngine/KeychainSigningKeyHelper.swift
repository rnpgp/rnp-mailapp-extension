//
//  KeychainSigningKeyHelper.swift
//  MailSecurityEngine
//
//  DRY extraction: TrustStore, KeyStateStore, and SecurityStateRecordStore
//  each have their own load-or-create-signing-key code. This helper
//  centralizes the Keychain operations so all three stores use the same
//  load/create/update pattern with the same error handling.
//
//  Each store still has its own Keychain service + account string (so
//  compromising one store's key does not grant write access to another).
//

import CryptoKit
import Foundation
import Security

/// Centralized helper for creating, loading, and updating Ed25519
/// signing keys stored in the macOS Keychain. Used by TrustStore,
/// KeyStateStore, and SecurityStateRecordStore.
public enum KeychainSigningKeyHelper {
    /// Loads an existing signing key from the Keychain, or creates a
    /// new one if none exists. The service + account pair uniquely
    /// identifies the key per-store.
    public static func loadOrCreate(
        service: String,
        account: String,
        keychainAccessGroup: String?
    ) throws -> Curve25519.Signing.PrivateKey {
        if let existing = try? read(service: service, account: account, keychainAccessGroup: keychainAccessGroup) {
            return existing
        }
        let key = Curve25519.Signing.PrivateKey()
        try store(key, service: service, account: account, keychainAccessGroup: keychainAccessGroup)
        return key
    }

    /// Reads a signing key from the Keychain. Returns `nil` when the
    /// key does not exist or cannot be decoded.
    public static func read(
        service: String,
        account: String,
        keychainAccessGroup: String?
    ) throws -> Curve25519.Signing.PrivateKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status: status)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    /// Stores a signing key in the Keychain. Updates in place if the
    /// key already exists.
    public static func store(
        _ key: Curve25519.Signing.PrivateKey,
        service: String,
        account: String,
        keychainAccessGroup: String?
    ) throws {
        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.rawRepresentation,
        ]
        if let group = keychainAccessGroup, !group.isEmpty {
            addQuery[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: key.rawRepresentation,
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }
}
