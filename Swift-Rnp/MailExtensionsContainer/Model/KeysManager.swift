//
//  KeysManager.swift
//  RNP
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
    /// Whether the keyring passphrase is Touch ID-protected and has not been
    /// unlocked in this process yet. Secret-key operations fail while locked;
    /// the UI offers Touch ID and manual-passphrase unlock.
    @Published private(set) var keyringLocked = false

    private let keyManager: KeyManager?
    private var lifecycle: KeyLifecycle? {
        keyManager.map { KeyLifecycle(keyManager: $0) }
    }

    /// Archived (decrypt-only) keys for the Archived section.
    var archivedKeys: [KeyInfo] {
        (try? keyManager?.archivedKeys()) ?? []
    }

    /// Whether the engine keyManager is available.
    var engineAvailable: Bool { keyManager != nil }

    /// Opens the shared keyring (app group container), creating it on first
    /// use. Falls back to a temporary directory if the keyring cannot be
    /// read. If both locations fail, the manager is left in a failed state
    /// and operations surface an error instead of crashing.
    ///
    /// UI tests can pass `--uitest-keyring-dir <path>` as a launch argument
    /// to use an isolated keyring (and trust store) instead of the shared
    /// app-group container.
    init() {
        let provider: Rnp.KeyedPassphraseProvider = KeychainPassphraseStore.resolvingProvider()
        if let manager = try? KeyManager(
            directory: Self.launchKeyringDirectory(),
            keyedPassphraseProvider: provider
        ) {
            keyManager = manager
        } else {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("rnp-mail-extension-fallback")
            if let manager = try? KeyManager(
                directory: fallback,
                keyedPassphraseProvider: provider
            ) {
                keyManager = manager
            } else {
                keyManager = nil
                lastError = "error.keyringOpenFailed".localized
            }
        }
        reload()
        keyringLocked = Self.computeKeyringLocked()
    }

    /// Whether the keyring needs unlocking: the passphrase is stored with
    /// Touch ID protection and is not cached in this process. Probed without
    /// showing authentication UI, so launching the app never prompts on its
    /// own — the user unlocks explicitly from the locked-keyring banner.
    private static func computeKeyringLocked() -> Bool {
        guard KeychainPassphraseStore.isBiometricProtectionEnabled else {
            return false
        }
        if case .authenticationFailed = KeychainPassphraseStore.readSharedPassphrase(
            allowingAuthenticationUI: false
        ) {
            return true
        }
        return false
    }

    // MARK: - Keyring unlock (Touch ID)

    /// Attempts to unlock the keyring with Touch ID. The system prompt is
    /// shown from a background queue so the UI stays responsive; the result
    /// is applied on the main queue. On success the passphrase is cached for
    /// the rest of the process lifetime and keyring operations stop
    /// prompting.
    func unlockKeyring() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = KeychainPassphraseStore.readSharedPassphrase()
            DispatchQueue.main.async {
                switch result {
                case .success, .notFound:
                    self.keyringLocked = false
                case .authenticationFailed:
                    self.keyringLocked = true
                }
            }
        }
    }

    /// Manual fallback for when Touch ID fails or is cancelled: verifies
    /// `passphrase` against the secret keys, then unlocks this process.
    ///
    /// Verification happens before anything is stored, so a typo cannot
    /// overwrite the Keychain item. When the item is Touch ID-protected it
    /// stays protected — only this process's session cache is populated.
    ///
    /// - Returns: `true` when the passphrase was accepted.
    @discardableResult
    func unlockKeyringManually(passphrase: String) -> Bool {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
            return false
        }
        guard !passphrase.isEmpty, verifyKeyringPassphrase(passphrase, keyManager: keyManager) else {
            return false
        }
        if KeychainPassphraseStore.isBiometricProtectionEnabled {
            KeychainPassphraseStore.cacheVerifiedPassphrase(passphrase)
        } else if let warning = KeychainPassphraseStore.setPassphrase(passphrase, requiresBiometry: false) {
            lastError = warning.message
            return false
        }
        keyringLocked = false
        return true
    }

    /// Checks a candidate keyring passphrase by trying to unlock the secret
    /// keys with it. Passing requires at least one secret key to unlock (a
    /// keyring without secret keys has nothing to verify against, so the
    /// passphrase is accepted).
    private func verifyKeyringPassphrase(_ passphrase: String, keyManager: KeyManager) -> Bool {
        let secretFingerprints = keys.filter(\.hasSecret).map(\.fingerprint)
        guard !secretFingerprints.isEmpty else {
            return true
        }
        for fingerprint in secretFingerprints {
            if let unlocked = try? keyManager.unlockSecretKey(fingerprint: fingerprint, passphrase: passphrase),
               unlocked
            {
                return true
            }
        }
        return false
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
    /// keys imported. Imported secret keys whose passphrase differs from the
    /// keyring passphrase are queued into `foreignPassphraseRequests` so the
    /// UI can ask the user to unlock them.
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
        if !imported.isEmpty {
            detectForeignPassphraseKeys(among: imported, keyManager: keyManager)
        }
        return imported
    }

    // MARK: - Foreign passphrases

    /// Imported secret keys still protected by a foreign passphrase, waiting
    /// for the user to unlock them. Presented one at a time by the prompt
    /// sheet; resolution removes entries.
    @Published var foreignPassphraseRequests: [LockedSecretKeyInfo] = []

    /// Queues unlock prompts for imported secret keys the keyring passphrase
    /// cannot unlock. Keys that already have a stored per-key passphrase or
    /// a pending request are skipped.
    private func detectForeignPassphraseKeys(among imported: [KeyInfo], keyManager: KeyManager) {
        let fingerprints = imported.filter(\.hasSecret).map(\.fingerprint)
        guard !fingerprints.isEmpty else {
            return
        }
        let keyringPassphrase = KeychainPassphraseStore.sharedPassphrase()
        // An empty passphrase means the keyring is locked behind Touch ID;
        // detection would flag every key as foreign, so skip it until the
        // keyring is unlocked.
        guard !keyringPassphrase.isEmpty else {
            return
        }
        let locked = (try? keyManager.lockedSecretKeys(
            keyringPassphrase: keyringPassphrase,
            among: fingerprints
        )) ?? []
        for info in locked where KeychainPassphraseStore.passphrase(forKeyFingerprint: info.fingerprint) == nil {
            if !foreignPassphraseRequests.contains(info) {
                foreignPassphraseRequests.append(info)
            }
        }
    }

    /// Verifies `passphrase` against the requested key and stores it in the
    /// Keychain as the key's per-key passphrase.
    ///
    /// - Returns: `true` when the passphrase unlocked the key and was stored.
    func storeForeignPassphrase(_ passphrase: String, for request: LockedSecretKeyInfo) -> Bool {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
            return false
        }
        do {
            guard try keyManager.unlockSecretKey(fingerprint: request.fingerprint, passphrase: passphrase) else {
                return false
            }
            if let warning = KeychainPassphraseStore.setPassphrase(passphrase, forKeyFingerprint: request.fingerprint) {
                lastError = warning.message
                return false
            }
            foreignPassphraseRequests.removeAll { $0 == request }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Verifies `passphrase` and re-protects the key with the keyring
    /// passphrase, so no separate per-key passphrase is needed afterwards.
    ///
    /// - Returns: `true` when the passphrase unlocked the key and the key
    ///   was re-protected.
    func reprotectForeignKey(_ passphrase: String, for request: LockedSecretKeyInfo) -> Bool {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
            return false
        }
        let keyringPassphrase = KeychainPassphraseStore.sharedPassphrase()
        guard !keyringPassphrase.isEmpty else {
            // The keyring is locked behind Touch ID; unlock it first.
            keyringLocked = true
            lastError = KeychainWarning.authenticationRequired.message
            return false
        }
        do {
            try keyManager.reprotectSecretKey(
                fingerprint: request.fingerprint,
                currentPassphrase: passphrase,
                newPassphrase: keyringPassphrase
            )
            // Re-protected with the keyring passphrase: a stale per-key entry
            // for this fingerprint must not shadow it.
            KeychainPassphraseStore.removePassphrase(forKeyFingerprint: request.fingerprint)
            foreignPassphraseRequests.removeAll { $0 == request }
            reload()
            return true
        } catch KeyManagerError.wrongPassphrase(_) {
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Dismisses the unlock prompt for the key without storing a passphrase.
    /// The key stays locked; signing and decryption with it will fail until
    /// it is unlocked another way.
    func skipForeignPassphrase(for request: LockedSecretKeyInfo) {
        foreignPassphraseRequests.removeAll { $0 == request }
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
            KeychainPassphraseStore.removePassphrase(forKeyFingerprint: key.fingerprint)
        }
    }

    /// Restores an archived key to active state.
    func restoreArchivedKey(fingerprint: String) throws {
        guard let keyManager else { return }
        try keyManager.setUsageState(.active, forFingerprint: fingerprint, reason: "user restored from archive")
    }

    /// Deletes a key from the keyring permanently (after the user has
    /// confirmed via `DeleteForeverConfirmation`). Also clears the
    /// usage-state record and any per-key passphrase.
    func deleteKeyForever(fingerprint: String) {
        guard let keyManager else { return }
        perform {
            try keyManager.deleteKey(fingerprint: fingerprint)
            try? keyManager.removeUsageRecord(forFingerprint: fingerprint)
            KeychainPassphraseStore.removePassphrase(forKeyFingerprint: fingerprint)
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

    /// Rejects the newly seen key of a key-change conflict, keeping the old
    /// binding for the address.
    func rejectConflict(email: String, newFingerprint: String) {
        guard let keyManager else {
            lastError = "error.keyringOpenFailed".localized
            return
        }
        do {
            try keyManager.trustStore.rejectConflict(email: email, newFpr: newFingerprint)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The unresolved conflict whose new key has the given fingerprint.
    func trustConflict(forNewFingerprint fingerprint: String) -> TrustConflict? {
        guard let keyManager else {
            return nil
        }
        return keyManager.trustStore.conflicts().first {
            $0.newFingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame
        }
    }

    /// Trust history recorded for an address, most recent first.
    func trustHistory(forEmail email: String) -> [TrustRecord] {
        guard let keyManager else {
            return []
        }
        return keyManager.trustStore.history(forEmail: email)
    }

    /// First email address found in the key's user IDs.
    func primaryEmail(for key: KeyInfo) -> String? {
        for userID in key.userIDs {
            if let email = Self.emailAddress(from: userID) {
                return email
            }
        }
        return nil
    }

    /// Extracts the email address from a user ID of the form
    /// "Name <email@example.com>", or returns the input itself when it looks
    /// like a bare email address. Mirrors the engine's internal
    /// `KeyManager.emailAddress(from:)`.
    private static func emailAddress(from userID: String) -> String? {
        if let open = userID.lastIndex(of: "<"),
           let close = userID.lastIndex(of: ">"), open < close
        {
            return String(userID[userID.index(after: open) ..< close])
        }
        return userID.contains("@") ? userID : nil
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
