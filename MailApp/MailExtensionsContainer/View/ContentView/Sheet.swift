//
//  Sheet.swift
//  RNP for Mail
//
//  The single source of truth for "which sheet is currently presented in
//  the main window". Replaces 12 `@Published var showXxx` booleans on
//  ContentViewModel and 3 NotificationCenter posts from menu items.
//

import Foundation
import MailSecurityEngine

enum Sheet: Hashable, Identifiable {
    /// New-key generation sheet. Algorithm is read from
    /// `ContentViewModel.generateAlgorithm` at presentation time.
    case generate
    /// Key detail sheet. Selected key is read from
    /// `ContentViewModel.selectedKey`.
    case detail
    /// Clipboard-import confirmation sheet (PGP block detected on the
    /// pasteboard). Pending text is `ContentViewModel.clipboardText`.
    case clipboardImport
    /// Extend-key-expiry sheet. Form state is
    /// `ContentViewModel.extendExpiryDate`.
    case extendExpiry
    /// Revoke-key sheet. Form state is
    /// `ContentViewModel.revokeFingerprintInput` / `revokeReason`.
    case revoke
    /// Subkey-rotation sheet. `kind` selects which subkey to rotate.
    case rotate(kind: RotateKind)
    /// Publish-to-keyserver sheet. State is
    /// `ContentViewModel.isPublishing` / `publishMessage`.
    case publish
    /// Fetch-from-keyserver sheet. Form state is
    /// `ContentViewModel.fetchQuery` / `fetchedKey`.
    case fetch
    /// Foreign-passphrase unlock prompt for an imported secret key. The
    /// pending request is `ContentViewModel.foreignPassphraseRequest`.
    case foreignPassphrase
    /// Trust history for an address. Data is
    /// `ContentViewModel.trustHistoryEmail` / `trustHistoryRecords`.
    case trustHistory
    /// Touch-ID / manual-passphrase keyring-unlock sheet.
    case keyringUnlock
    /// About → Licenses attribution sheet.
    case licenses
    /// Keyserver settings sheet.
    case keyServerSettings
    /// Security settings sheet (require Touch ID per operation, timeout).
    case securitySettings
    /// Auto-detect existing keyrings (~/.gnupg, ~/.rnp) and let the
    /// user pick keys to import. Read-only against the source.
    case importFromKeyring

    var id: Self { self }
}

enum RotateKind: Hashable {
    case encryption
    case signing
}
