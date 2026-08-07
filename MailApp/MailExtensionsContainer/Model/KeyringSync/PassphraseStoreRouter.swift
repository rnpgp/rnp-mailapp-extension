//
//  PassphraseStoreRouter.swift
//  RNP
//
//  Dispatches per-fingerprint passphrase operations to the right
//  backend based on `SyncConfiguration.passphraseStoreID`:
//
//    - "keychain"        → KeychainPassphraseStore only (local to this Mac)
//    - "icloud-keychain" → write to BOTH KeychainPassphraseStore and
//                          SynchronizablePassphraseStore; read falls
//                          back from local to synced
//    - "prompt"          → no storage; methods behave as no-ops /
//                          nil (caller prompts every time)
//
//  Why both stores when sync is on:
//  The Mail extension reads passphrases via KeychainPassphraseStore
//  and has no awareness of iCloud Keychain. Mirroring to the local
//  Keychain on write means the extension keeps working unchanged.
//  SynchronizablePassphraseStore then handles cross-device sync.
//
//  Per docs/sync-architecture.md: the keyring passphrase (shared)
//  is NEVER routed through this layer — it's a different concern
//  and stays on KeychainPassphraseStore with Touch ID protection.
//

import Foundation
import MailSecurityEngine

public enum PassphraseStoreRouter {

    private static var preferredStoreID: String {
        // Reading SyncConfiguration on every call is cheap (it's
        // all UserDefaults). Cannot hold a long-lived reference
        // because the user can flip the radio button mid-session.
        SyncConfiguration().passphraseStoreID
    }

    /// True when the user has selected iCloud Keychain as the
    /// passphrase store. Exposed for tests + diagnostic UI.
    public static var syncEnabled: Bool {
        preferredStoreID == "icloud-keychain"
    }

    // MARK: Read

    /// Returns the per-fingerprint passphrase from the preferred
    /// store, falling back to the other store on miss. Order:
    ///   sync on  → local first, then iCloud Keychain
    ///   sync off → local only
    public static func passphrase(forKeyFingerprint fingerprint: String) -> String? {
        if syncEnabled {
            // Try local first (fast path; the extension reads this).
            if let local = KeychainPassphraseStore.passphrase(forKeyFingerprint: fingerprint) {
                return local
            }
            // Fall back to the synced item (e.g. set by another device
            // since the last local mirror).
            if let synced = SynchronizablePassphraseStore.read(fingerprint: fingerprint) {
                // Mirror into local so the extension sees it next time.
                _ = KeychainPassphraseStore.setPassphrase(synced, forKeyFingerprint: fingerprint)
                return synced
            }
            return nil
        }
        return KeychainPassphraseStore.passphrase(forKeyFingerprint: fingerprint)
    }

    // MARK: Write

    /// Stores the per-fingerprint passphrase. When sync is enabled,
    /// writes to BOTH local and synced stores. Returns nil on
    /// success or a warning describing the failure.
    @discardableResult
    public static func setPassphrase(
        _ passphrase: String,
        forKeyFingerprint fingerprint: String
    ) -> KeychainWarning? {
        let local = KeychainPassphraseStore.setPassphrase(passphrase, forKeyFingerprint: fingerprint)
        guard syncEnabled else { return local }
        do {
            try SynchronizablePassphraseStore.write(fingerprint: fingerprint, passphrase: passphrase)
        } catch {
            // Surface as a warning; the local write still succeeded.
            return .storageFailed(error.localizedDescription)
        }
        return local
    }

    // MARK: Delete

    /// Removes the per-fingerprint passphrase from both stores when
    /// sync is on, or just local when sync is off. Idempotent.
    public static func removePassphrase(forKeyFingerprint fingerprint: String) {
        KeychainPassphraseStore.removePassphrase(forKeyFingerprint: fingerprint)
        if syncEnabled {
            _ = try? SynchronizablePassphraseStore.delete(fingerprint: fingerprint)
        }
    }
}
