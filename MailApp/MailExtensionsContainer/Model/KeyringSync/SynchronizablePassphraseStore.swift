//
//  SynchronizablePassphraseStore.swift
//  RNP
//
//  Wraps the existing KeychainPassphraseStore with
//  `kSecAttrSynchronizable: true` so per-key passphrases sync to
//  iCloud Keychain across the user's macOS and iOS devices.
//
//  iCloud Keychain is end-to-end encrypted by Apple — only the
//  user's devices can read these items. Apple cannot.
//
//  Failure modes:
//  - iCloud Keychain disabled → items still save locally; sync
//    silently skips. Surface in Tools hub.
//  - Item already exists on remote (set by another device) →
//    SecItemAdd returns errSecDuplicateItem; we fall back to
//    SecItemUpdate.
//
//  See docs/sync-architecture.md.
//

import Foundation
import Security

public enum SynchronizablePassphraseError: Error, LocalizedError {
    case keychainUnavailable(OSStatus)
    case iCloudKeychainDisabled

    public var errorDescription: String? {
        switch self {
        case .keychainUnavailable(let status):
            return String(format: "error.passphraseSync.keychainUnavailable".localized, status)
        case .iCloudKeychainDisabled:
            return "error.passphraseSync.iCloudDisabled".localized
        }
    }
}

public enum SynchronizablePassphraseStore {

    public static let service = "com.rnpgp.RNPForMail.passphrase.sync"

    // MARK: Read

    /// Returns the passphrase for `fingerprint`, or nil if not present.
    /// Sync-attributed items are read the same way as non-sync ones —
    /// the synchronizable flag is on the item, not the query.
    public static func read(fingerprint: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: fingerprint,
            kSecAttrSynchronizable: kCFBooleanTrue as Any,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Write

    /// Stores `passphrase` for `fingerprint` as a synchronizable
    /// Keychain item. Falls back to update if the item already exists
    /// (e.g., set by another device).
    @discardableResult
    public static func write(fingerprint: String, passphrase: String) throws -> Bool {
        let data = Data(passphrase.utf8)
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: fingerprint,
            kSecAttrSynchronizable: kCFBooleanTrue as Any,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            // Update the existing item
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: fingerprint,
                kSecAttrSynchronizable: kCFBooleanTrue as Any
            ]
            let updates: [CFString: Any] = [
                kSecValueData: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SynchronizablePassphraseError.keychainUnavailable(updateStatus)
            }
            return true
        }
        throw SynchronizablePassphraseError.keychainUnavailable(status)
    }

    // MARK: Delete

    @discardableResult
    public static func delete(fingerprint: String) throws -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: fingerprint,
            kSecAttrSynchronizable: kCFBooleanTrue as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: Diagnostic

    /// True if iCloud Keychain appears to be enabled on this device.
    /// We can't directly query it (no public API), but we can check
    /// whether ANY synchronizable item exists locally — if the user
    /// has iCloud Keychain enabled, other apps' items would have
    /// propagated.
    public static var isICloudKeychainEnabled: Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: kCFBooleanTrue as Any,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
}
