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
import RnpMailUI
import TrustStore

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
    ///
    /// UI tests can pass `--uitest-keyring-dir <path>` as a launch argument
    /// to use an isolated keyring (and trust store) instead of the shared
    /// app-group container.
    init() {
        let provider: (String) -> String? = { _ in KeychainPassphraseStore.sharedPassphrase() }
        if let manager = try? KeyManager(
            directory: Self.launchKeyringDirectory(),
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
                lastError = "error.keyringOpenFailed".localized
            }
        }
        reload()
    }

    /// Keyring directory for this launch: the `--uitest-keyring-dir` launch
    /// argument when present, otherwise the shared app-group location.
    private static func launchKeyringDirectory() -> URL {
        let arguments = CommandLine.arguments
        if let flagIndex = arguments.firstIndex(of: "--uitest-keyring-dir"),
           arguments.indices.contains(flagIndex + 1) {
            return URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
        }
        return AppGroup.keyringDirectory()
    }

    func reload() {
        guard let keyManager else {
            keys = []
            lastError = "error.keyringOpenFailed".localized
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
            lastError = "error.keyringOpenFailed".localized
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
            lastError = "error.keyringOpenFailed".localized
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
            lastError = "error.keyringOpenFailed".localized
            return nil
        }
        return try? keyManager.exportKey(fingerprint: fingerprint)
    }

    /// Armored secret key export for the given fingerprint.
    func exportSecretKey(fingerprint: String) -> Data? {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
            return nil
        }
        return try? keyManager.exportKey(fingerprint: fingerprint, secret: true)
    }

    func delete(_ key: KeyInfo) {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
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
            lastError = "error.keyringOpenFailed".localized
            return
        }
        perform {
            _ = try lifecycle.rotateEncryptionSubkey(for: key.fingerprint)
        }
    }

    /// Rotates the signing subkey for the selected key.
    func rotateSigningSubkey(for key: KeyInfo) {
        guard let lifecycle else {
            lastError = "error.keyringOpenFailed".localized
            return
        }
        perform {
            _ = try lifecycle.rotateSigningSubkey(for: key.fingerprint)
        }
    }

    /// Extends the primary key's expiry to the given date.
    func extendExpiry(for key: KeyInfo, to newDate: Date) {
        guard let lifecycle else {
            lastError = "error.keyringOpenFailed".localized
            return
        }
        perform {
            try lifecycle.extendExpiry(for: key.fingerprint, newDate: newDate)
        }
    }

    /// Revokes the key and stores the revocation certificate URL.
    func revoke(_ key: KeyInfo, code: RevocationCode, reason: String) {
        guard let lifecycle else {
            lastError = "error.keyringOpenFailed".localized
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

    // MARK: - Keyserver

    /// Publishes the armored public key of the given key to the default keyserver.
    func publish(key: KeyInfo) async -> Result<UploadReceipt, KeyServerError> {
        guard let keyManager else {
            return .failure(.network(underlying: "error.keyringOpenFailed".localized))
        }
        guard let armored = try? keyManager.exportKey(fingerprint: key.fingerprint) else {
            return .failure(.malformedKey)
        }
        let service = KeyServerService()
        do {
            let receipt = try await service.upload(armoredKey: String(decoding: armored, as: UTF8.self))
            return .success(receipt)
        } catch {
            return .failure(error as? KeyServerError ?? .network(underlying: error.localizedDescription))
        }
    }

    /// Discovers a key by email or fingerprint.
    func discoverByEmail(_ email: String) async -> Result<FetchedKey, KeyServerError> {
        await KeyServerService().discoverByEmail(email)
    }

    func discoverByFingerprint(_ fingerprint: String) async -> Result<FetchedKey, KeyServerError> {
        await KeyServerService().discoverByFingerprint(fingerprint)
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

    /// Trust state for the given fingerprint.
    func trustState(forFpr fingerprint: String) -> TrustState {
        guard let keyManager else {
            return .unverified
        }
        return keyManager.trustStore.state(forFpr: fingerprint)
    }

    /// All unresolved key-change conflicts.
    func trustConflicts() -> [TrustConflict] {
        guard let keyManager else {
            return []
        }
        return keyManager.trustStore.conflicts()
    }

    /// Marks the fingerprint as verified and resolves any related conflict.
    func markVerified(fingerprint: String) {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
            return
        }
        do {
            try keyManager.trustStore.markVerified(fingerprint: fingerprint)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
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
