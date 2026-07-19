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

    private let keyManager: KeyManager

    /// Opens the shared keyring (app group container), creating it on first
    /// use. Falls back to a temporary directory if the keyring cannot be
    /// read, so the app always launches.
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
            keyManager = (try? KeyManager(
                directory: fallback,
                passphraseProvider: provider
            ))!
        }
        reload()
    }

    func reload() {
        do {
            keys = try keyManager.listKeys()
        } catch {
            keys = []
            lastError = error.localizedDescription
        }
    }

    func generate(userID: String, algorithm: KeyAlgorithm) {
        perform {
            try keyManager.generateKey(userID: userID, algorithm: algorithm)
        }
    }

    /// Imports armored or binary key data; reports the number of primary
    /// keys imported.
    func importKeys(_ data: Data) {
        perform {
            try keyManager.importKeys(data)
        }
    }

    /// Armored public key export for the given fingerprint.
    func exportKey(fingerprint: String) -> Data? {
        try? keyManager.exportKey(fingerprint: fingerprint)
    }

    func delete(_ key: KeyInfo) {
        perform {
            try keyManager.deleteKey(fingerprint: key.fingerprint)
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
