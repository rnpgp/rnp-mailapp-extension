//
//  KeysManager.swift
//  Ribose container
//
//  Observable keyring model for the container app, backed by the real
//  MailSecurityEngine KeyManager on the shared app-group keyring.
//

import Foundation
import MailSecurityEngine

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
