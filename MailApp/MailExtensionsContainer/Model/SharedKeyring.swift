//
//  SharedKeyring.swift
//  RNP for Mail
//
//  Single source of truth for constructing a KeyManager on the shared
//  app-group keyring. Both the container app (KeysManager) and the Mail
//  extension (MessageSecurityHandler) go through this factory so the
//  fallback recipe stays in sync — divergence here is a security bug
//  class (host and extension disagree on which keyring to read).
//
//  Compiled into both targets so each sees its own module-qualified
//  SharedKeyring; no cross-target import needed.
//

import Foundation
import MailSecurityEngine

enum SharedKeyring {
    /// Build a KeyManager on `directory` using the shared Keychain
    /// passphrase provider. If `directory` cannot be opened, retry on a
    /// temporary fallback location so the app keeps running in degraded
    /// mode. Returns nil only if both locations fail.
    ///
    /// Callers decide how to handle nil:
    /// - Container app (KeysManager): surfaces `error.keyringOpenFailed`.
    /// - Mail extension (MessageSecurityHandler): returns nil core so
    ///   Mail launches and degrades to plaintext.
    static func makeKeyManager(directory: URL) -> KeyManager? {
        let provider: Rnp.KeyedPassphraseProvider = KeychainPassphraseStore.resolvingProvider()
        if let manager = try? KeyManager(directory: directory, keyedPassphraseProvider: provider) {
            return manager
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-mail-extension-fallback")
        return try? KeyManager(directory: fallback, keyedPassphraseProvider: provider)
    }
}
