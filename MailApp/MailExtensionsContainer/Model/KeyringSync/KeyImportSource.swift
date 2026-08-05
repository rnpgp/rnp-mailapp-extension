//
//  KeyImportSource.swift
//  RNP
//
//  Read-only source of keys that RNP can IMPORT from. Distinct from
//  `KeyringBackend` (which is read/write for RNP's own canonical
//  store). Import sources have NO write/delete methods — compile-time
//  guarantee that RNP can never accidentally modify them.
//
//  Implementations:
//  - GnuPGImportSource  (reads ~/.gnupg)
//  - PasteImportSource  (reads clipboard)
//  - FileImportSource   (reads drag-dropped files)
//  - WKDImportSource    (fetches via Web Key Directory)
//  - KeysOpenpgpOrgImportSource (fetches from keys.openpgp.org)
//
//  The flow is always:
//    source.listAvailable()  -> [KeyringKeyRecord]
//    user picks which to import
//    backend.upsert(record)  -> writes to RNP's canonical store
//    source is UNTOUCHED
//
//  See docs/sync-architecture.md.
//

import Foundation

public enum BackendAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

/// Read-only key source. RNP NEVER writes to conforming types.
public protocol KeyImportSource: AnyObject {
    /// Stable identifier for persistence (e.g. "gnupg", "wkd", "paste").
    var identifier: String { get }
    /// User-facing name + description for the Import UI.
    var displayName: String { get }
    /// Whether this source is currently usable on this device. Sources
    /// return `.unavailable` with a clear reason when the underlying
    /// dependency is missing (e.g. gpg not installed, no clipboard
    /// contents, no network).
    var availability: BackendAvailability { get }

    /// Returns keys currently visible at this source. Pure read — does
    /// NOT modify the source. The caller (UI) decides which records to
    /// import via `KeyringBackend.upsert(_:)`.
    ///
    /// Network-backed sources (WKD, keyservers) suspend until the
    /// fetch completes or fails.
    func listAvailable() async throws -> [KeyringKeyRecord]
}
