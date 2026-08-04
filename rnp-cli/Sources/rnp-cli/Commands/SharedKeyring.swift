//
//  SharedKeyring.swift
//  rnp-cli
//
//  Resolves the keyring location. Mirrors the GUI app's logic: App
//  Group container when available, ~/.rnp/ fallback otherwise.
//  Reading from the GUI app's keyring lets the CLI see keys imported
//  via the GUI and vice versa.
//

import Foundation
import MailSecurityEngine

enum CLIKeyring {
    /// Resolves the keyring directory. Prefers the GUI app's App
    /// Group location; falls back to `~/.rnp` (user-owned, no GUI
    /// install needed). The CLI never writes outside this directory.
    static func directory() -> URL {
        // Honor $RNP_KEYRING_DIR for tests / power users.
        if let override = ProcessInfo.processInfo.environment["RNP_KEYRING_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // App Group container — same path the GUI app uses.
        return AppGroup.keyringDirectory()
    }
}
