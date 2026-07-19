//
//  KeychainPassphraseStore.swift
//  swift-rnp
//
//  Keyring passphrase storage in the macOS Keychain.
//
//  A single random passphrase protects all keys in the shared keyring. It is
//  created on first use and stored as a generic password; with both targets
//  listing the same keychain access group in their entitlements, the item is
//  shared between the container app and the Mail extension. (Keychain
//  sharing requires proper code signing — see README.md; unsigned local
//  builds still work because macOS Keychain does not isolate unsigned
//  clients the way iOS does.)
//

import Foundation
import Security

/// Stores and retrieves the keyring passphrase in the login Keychain.
enum KeychainPassphraseStore {
    private static let service = "RNP Mail Extension keyring"
    private static let account = "keyring-passphrase"

    /// Keychain access group shared by the container app and the Mail
    /// extension. Driven by the `RNPMAILKeychainAccessGroup` Info.plist key;
    /// `nil` for unsigned local builds where no access group is provisioned.
    private static let accessGroup: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RNPMAILKeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.hasPrefix("$(")
        else {
            return nil
        }
        return value
    }()

    /// The shared passphrase, creating and storing a random one on first
    /// use.
    static func sharedPassphrase() -> String {
        if let existing = read() {
            return existing
        }
        let created = randomPassphrase()
        try? store(created)
        return created
    }

    /// Deletes the stored passphrase (e.g. when wiping the keyring).
    static func reset() {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    private static func read() -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func store(_ passphrase: String) throws {
        let data = Data(passphrase.utf8)
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            // Accessible only while the device is unlocked; not synced.
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    private static func randomPassphrase() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}

/// Keychain operation failures.
enum KeychainError: Error {
    case unhandled(status: OSStatus)
}
