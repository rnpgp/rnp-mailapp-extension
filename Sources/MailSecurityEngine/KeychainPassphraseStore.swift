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
import Rnp
import Security

/// A non-fatal warning surfaced when Touch ID storage cannot be used or when
/// plain Keychain storage fails.
public enum KeychainWarning: Equatable {
    /// The device or keychain does not support the requested biometric ACL.
    case biometryUnavailable
    /// Biometric storage failed with the given explanation.
    case biometryFailed(String)
    /// Plain Keychain storage failed with the given explanation.
    case storageFailed(String)

    /// Human-friendly sentence describing the warning.
    public var message: String {
        switch self {
        case .biometryUnavailable:
            return "Touch ID is not available on this Mac. The passphrase was saved without it."
        case .biometryFailed(let reason):
            return "Could not save the passphrase with Touch ID: \(reason). It was saved without biometric protection."
        case .storageFailed(let reason):
            return "The passphrase could not be saved to the Keychain. \(reason)"
        }
    }
}

/// Keychain operation failures.
public enum KeychainError: Error {
    case unhandled(status: OSStatus)
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            return "Keychain error (\(status)): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }
}

/// Stores and retrieves the keyring passphrase in the login Keychain.
public enum KeychainPassphraseStore {
    private static let service = "RNP Mail Extension keyring"
    private static let plainAccount = "keyring-passphrase"
    private static let biometricAccount = "keyring-passphrase.biometric"

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
    ///
    /// This variant is non-throwing and returns only the passphrase, so it
    /// can be used directly by the Mail security engine's passphrase
    /// provider. It always uses the plain Keychain item and never prompts for
    /// biometry.
    public static func sharedPassphrase() -> String {
        sharedPassphrase(requiresBiometry: false).passphrase
    }

    /// The shared passphrase, optionally reading from or creating the
    /// biometric Keychain item.
    ///
    /// - Parameter requiresBiometry: when `true`, the passphrase is read from
    ///   the biometric item, creating it protected by Touch ID if it does not
    ///   already exist. When `false`, the plain item is used.
    /// - Returns: the passphrase and an optional warning for the UI.
    public static func sharedPassphrase(requiresBiometry: Bool) -> (passphrase: String, warning: KeychainWarning?) {
        let account = requiresBiometry ? biometricAccount : plainAccount
        if let existing = read(account: account) {
            return (existing, nil)
        }
        // If the requested biometric item is missing but the plain item exists,
        // reuse the existing passphrase instead of generating a new one. This
        // keeps the engine's passphrase stable even when the biometric item is
        // created later.
        if account == biometricAccount, let plain = read(account: plainAccount) {
            let warning = setPassphrase(plain, requiresBiometry: true)
            return (plain, warning)
        }
        let created = randomPassphrase()
        let warning = setPassphrase(created, requiresBiometry: requiresBiometry)
        return (created, warning)
    }

    /// Stores a specific passphrase.
    ///
    /// The passphrase is always written to the plain Keychain item. When
    /// `requiresBiometry` is `true`, it is also written to the biometric item.
    /// If biometric storage fails, the plain item still holds the passphrase
    /// and a fallback warning is returned. If plain storage fails, a
    /// `.storageFailed` warning is returned.
    ///
    /// - Parameters:
    ///   - passphrase: the passphrase to store.
    ///   - requiresBiometry: when `true`, the passphrase is also stored with
    ///     biometric access control.
    /// - Returns: `nil` on full success, or a warning describing the failure.
    @discardableResult
    public static func setPassphrase(_ passphrase: String, requiresBiometry: Bool) -> KeychainWarning? {
        do {
            try store(passphrase, account: plainAccount, accessControl: nil)
        } catch {
            return .storageFailed(error.localizedDescription)
        }

        if requiresBiometry {
            if let warning = storeWithBiometry(passphrase) {
                return warning
            }
        }
        return nil
    }

    /// Deletes the stored passphrase (e.g. when wiping the keyring).
    ///
    /// Per-key passphrases stored under key fingerprints are removed as
    /// well: with the keyring gone they no longer protect anything.
    public static func reset() {
        delete(account: plainAccount)
        delete(account: biometricAccount)
        deleteAllKeyPassphrases()
    }

    // MARK: - Per-key passphrases

    /// Keychain account holding the passphrase of one specific key.
    ///
    /// Distinct per-key items share the service with the keyring passphrase;
    /// the account prefix keeps them apart.
    private static func keyAccount(forFingerprint fingerprint: String) -> String {
        "key-passphrase." + fingerprint.uppercased()
    }

    /// The passphrase stored for the key with the given fingerprint, or
    /// `nil` when the key has no per-key passphrase.
    public static func passphrase(forKeyFingerprint fingerprint: String) -> String? {
        read(account: keyAccount(forFingerprint: fingerprint))
    }

    /// Stores a per-key passphrase for the key with the given fingerprint,
    /// replacing any existing entry.
    ///
    /// Per-key passphrases are always stored in a plain Keychain item: they
    /// must be readable by the Mail extension without user interaction, like
    /// the keyring passphrase itself.
    ///
    /// - Returns: `nil` on success, or a warning describing the failure.
    @discardableResult
    public static func setPassphrase(_ passphrase: String, forKeyFingerprint fingerprint: String) -> KeychainWarning? {
        do {
            try store(passphrase, account: keyAccount(forFingerprint: fingerprint), accessControl: nil)
            return nil
        } catch {
            return .storageFailed(error.localizedDescription)
        }
    }

    /// Deletes the per-key passphrase stored for the given fingerprint
    /// (e.g. after the key has been re-protected or removed).
    public static func removePassphrase(forKeyFingerprint fingerprint: String) {
        delete(account: keyAccount(forFingerprint: fingerprint))
    }

    /// Removes every per-key passphrase item (all accounts with the
    /// per-key prefix under this service).
    private static func deleteAllKeyPassphrases() {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let items = item as? [[CFString: Any]]
        else {
            return
        }
        for attributes in items {
            guard let account = attributes[kSecAttrAccount] as? String,
                  account.hasPrefix("key-passphrase.")
            else {
                continue
            }
            delete(account: account)
        }
    }

    /// Passphrase provider resolving per-key passphrases before the keyring
    /// passphrase.
    ///
    /// When librnp asks for the passphrase of a key that has a per-key
    /// passphrase stored under its fingerprint, that passphrase is returned;
    /// every other request (including requests without a key) is answered
    /// with the shared keyring passphrase.
    public static func resolvingProvider() -> Rnp.KeyedPassphraseProvider {
        { _, fingerprint in
            if let fingerprint,
               let perKey = passphrase(forKeyFingerprint: fingerprint)
            {
                return perKey
            }
            return sharedPassphrase()
        }
    }

    // MARK: - Private

    private static func read(account: String) -> String? {
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

    /// Stores the passphrase for the given account, replacing any existing item.
    ///
    /// - Parameters:
    ///   - passphrase: the passphrase to store.
    ///   - account: the Keychain account identifier.
    ///   - accessControl: an optional access control object. When `nil` the
    ///     item is protected by the standard device-unlocked policy.
    private static func store(_ passphrase: String, account: String, accessControl: SecAccessControl?) throws {
        let data = Data(passphrase.utf8)

        // Remove any existing item so the ACL/accessibility can be changed.
        var deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup {
            deleteQuery[kSecAttrAccessGroup] = accessGroup
        }
        SecItemDelete(deleteQuery as CFDictionary)

        var item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
        ]
        if let accessGroup {
            item[kSecAttrAccessGroup] = accessGroup
        }

        if let accessControl {
            item[kSecAttrAccessControl] = accessControl
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        } else {
            // Accessible only while the device is unlocked; not synced.
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        }

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    /// Attempts to store the passphrase with Touch ID protection.
    ///
    /// - Returns: `nil` on success, or a warning describing why biometric
    ///   storage could not be used.
    private static func storeWithBiometry(_ passphrase: String) -> KeychainWarning? {
        var error: Unmanaged<CFError>?
        let flags: SecAccessControlCreateFlags = [.biometryCurrentSet, .userPresence]
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &error
        ) else {
            let reason = error?.takeRetainedValue().localizedDescription
                ?? "the keychain refused the biometric access control"
            return reason.contains("not available") || reason.contains("unavailable")
                ? .biometryUnavailable
                : .biometryFailed(reason)
        }

        do {
            try store(passphrase, account: biometricAccount, accessControl: accessControl)
            return nil
        } catch {
            let reason = (error as? KeychainError)?.errorDescription ?? error.localizedDescription
            return reason.contains("not available") || reason.contains("unavailable")
                ? .biometryUnavailable
                : .biometryFailed(reason)
        }
    }

    private static func delete(account: String) {
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

    private static func randomPassphrase() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
