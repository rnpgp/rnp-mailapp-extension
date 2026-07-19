//
//  KeysManager.swift
//  Ribose container
//
//  Observable keyring model for the container app, backed by the real
//  MailSecurityEngine KeyManager on the shared app-group keyring.
//

import Foundation
import KeyLifecycle
import MailSecurityEngine
import Rnp

/// Observable wrapper around the engine's `KeyManager`.
///
/// Passphrases live in the Keychain (`KeychainPassphraseStore`), never in
/// UserDefaults.
final class KeysManager: ObservableObject {
    @Published private(set) var keys: [KeyInfo] = []
    @Published var lastError: String?
    @Published var lastWarning: KeychainWarning?
    @Published var lastRevocationCertificateURL: URL?

    private let keyManager: KeyManager?
    private var lifecycle: KeyLifecycle? {
        keyManager.map { KeyLifecycle(keyManager: $0) }
    }

    /// Opens the shared keyring (app group container), creating it on first
    /// use. Falls back to a temporary directory if the keyring cannot be
    /// read. If both locations fail, the manager is left in a failed state
    /// and operations surface an error instead of crashing.
    init() {
        let provider: (String) -> String? = { _ in KeychainPassphraseStore.sharedPassphrase() }
        if let manager = try? KeyManager(
            directory: AppGroup.keyringDirectory(),
            passphraseProvider: provider
        ) {
            keyManager = manager
        } else {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("rnp-mail-extension-fallback")
            if let manager = try? KeyManager(
                directory: fallback,
                passphraseProvider: provider
            ) {
                keyManager = manager
            } else {
                keyManager = nil
                lastError = "Could not open the keyring."
            }
        }
        reload()
    }

    func reload() {
        guard let keyManager else {
            keys = []
            lastError = "Could not open the keyring."
            return
        }
        do {
            keys = try keyManager.listKeys()
        } catch {
            keys = []
            lastError = error.localizedDescription
        }
    }

    func generate(
        userID: String,
        algorithm: KeyAlgorithm,
        passphrase: String? = nil,
        expirationSeconds: UInt32 = 0,
        useTouchID: Bool = false
    ) {
        guard let keyManager else {
            lastError = "Could not open the keyring."
            return
        }

        lastWarning = nil

        if let passphrase {
            let warning = KeychainPassphraseStore.setPassphrase(passphrase, requiresBiometry: useTouchID)
            if let warning {
                if case .storageFailed = warning {
                    lastError = warning.message
                    return
                }
                lastWarning = warning
            }
        }

        perform {
            let info = try keyManager.generateKey(
                userID: userID,
                algorithm: algorithm,
                expirationSeconds: expirationSeconds
            )
            lastRevocationCertificateURL = try keyManager.saveRevocationCertificate(fingerprint: info.fingerprint)
        }
    }

    /// Imports armored or binary key data; reports the number of primary
    /// keys imported.
    @discardableResult
    func importKeys(_ data: Data) -> [KeyInfo] {
        guard let keyManager else {
            lastError = "Could not open the keyring."
            return []
        }
        var imported: [KeyInfo] = []
        perform {
            imported = try keyManager.importKeys(data)
        }
        return imported
    }

    /// Armored public key export for the given fingerprint.
    func exportKey(fingerprint: String) -> Data? {
        guard let keyManager else {
            lastError = "Could not open the keyring."
            return nil
        }
        return try? keyManager.exportKey(fingerprint: fingerprint)
    }

    /// Armored secret key export for the given fingerprint.
    func exportSecretKey(fingerprint: String) -> Data? {
        guard let keyManager else {
            lastError = "Could not open the keyring."
            return nil
        }
        return try? keyManager.exportKey(fingerprint: fingerprint, secret: true)
    }

    func delete(_ key: KeyInfo) {
        guard let keyManager else {
            lastError = "Could not open the keyring."
            return
        }
        perform {
            try keyManager.deleteKey(fingerprint: key.fingerprint)
        }
    }

    // MARK: - Lifecycle

    /// Rotates the encryption subkey for the selected key.
    func rotateEncryptionSubkey(for key: KeyInfo) {
        guard let lifecycle else {
            lastError = "Could not open the keyring."
            return
        }
        perform {
            _ = try lifecycle.rotateEncryptionSubkey(for: key.fingerprint)
        }
    }

    /// Rotates the signing subkey for the selected key.
    func rotateSigningSubkey(for key: KeyInfo) {
        guard let lifecycle else {
            lastError = "Could not open the keyring."
            return
        }
        perform {
            _ = try lifecycle.rotateSigningSubkey(for: key.fingerprint)
        }
    }

    /// Extends the primary key's expiry to the given date.
    func extendExpiry(for key: KeyInfo, to newDate: Date) {
        guard let lifecycle else {
            lastError = "Could not open the keyring."
            return
        }
        perform {
            try lifecycle.extendExpiry(for: key.fingerprint, newDate: newDate)
        }
    }

    /// Revokes the key and stores the revocation certificate URL.
    func revoke(_ key: KeyInfo, code: RevocationCode, reason: String) {
        guard let lifecycle else {
            lastError = "Could not open the keyring."
            return
        }
        perform {
            let certificate = try lifecycle.revoke(for: key.fingerprint, code: code, reason: reason)
            let url = AppGroup.keyringDirectory()
                .appendingPathComponent("\(key.fingerprint)-revocation")
                .appendingPathExtension("asc")
            try certificate.write(to: url, options: .atomic)
            lastRevocationCertificateURL = url
        }
    }

    /// Returns keys and subkeys that are expired or expiring soon.
    func expiryReport() -> [KeyExpiryItem] {
        guard let lifecycle else {
            return []
        }
        do {
            return try lifecycle.expiryReport()
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Subkey metadata for the given fingerprint.
    func subkeys(for key: KeyInfo) -> [SubkeyInfo] {
        guard let keyManager else {
            return []
        }
        return (try? keyManager.subkeys(for: key.fingerprint)) ?? []
    }

    private func perform(_ operation: () throws -> Void) {
        lastError = nil
        do {
            try operation()
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
