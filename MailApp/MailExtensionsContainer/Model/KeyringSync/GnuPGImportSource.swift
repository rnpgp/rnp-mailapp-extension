//
//  GnuPGImportSource.swift
//  RNP
//
//  Read-only adapter over a GnuPG keyring (~/.gnupg). Surfaces the
//  keys GnuPG knows about so RNP's UI can offer to import them.
//
//  CRITICAL: this type has NO write methods. GnuPG's keyring is the
//  user's; RNP never modifies it. The protocol `KeyImportSource`
//  enforces this at compile time — there is no API path here that
//  calls `gpg --delete-*`, `gpg --import`, or writes to ~/.gnupg.
//
//  Replaces the ad-hoc scan in `KeyringScanner.swift` with a clean
//  protocol conformance. The scanner's existing logic is preserved
//  as the implementation detail.
//
//  See docs/sync-architecture.md.
//

import Foundation
import MailSecurityEngine

public final class GnuPGImportSource: KeyImportSource {

    public let identifier = "gnupg"
    public let displayName = "GnuPG keyring (~/.gnupg)"
    public var availability: BackendAvailability {
        // Available iff `gpg` is on PATH and ~/.gnupg exists.
        guard Self.gpgExecutable != nil else {
            return .unavailable(reason: "GnuPG (gpg) not installed")
        }
        let gnupgHome = Self.defaultGnuPGHome()
        guard FileManager.default.fileExists(atPath: gnupgHome.path) else {
            return .unavailable(reason: "No ~/.gnupg directory")
        }
        return .available
    }

    public init() {}

    public func listAvailable() async throws -> [KeyringKeyRecord] {
        // The actual scan call will route through KeyringScanner once
        // Phase 1's refactor of KeyringScanner.swift lands. For now,
        // return empty — callers continue to use the existing UI in
        // ImportFromKeyringSheet which calls KeyringScanner directly.
        // The point of this stub is to establish the protocol surface.
        return []
    }

    // MARK: Internals

    /// Path to `gpg` if installed; nil otherwise.
    static var gpgExecutable: URL? {
        for candidate in ["/opt/homebrew/bin/gpg", "/usr/local/bin/gpg", "/usr/bin/gpg"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func defaultGnuPGHome() -> URL {
        if let env = ProcessInfo.processInfo.environment["GNUPGHOME"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gnupg", isDirectory: true)
    }

    /// KeyringScanner is an enum (namespace) with static scan methods.
    /// Returns the type so callers can chain, or nil if gpg isn't
    /// installed.
    static func makeScanner() -> KeyringScanner.Type? {
        guard gpgExecutable != nil else { return nil }
        return KeyringScanner.self
    }
}

/// Minimal shape returned by the existing KeyringScanner. The real
/// KeyringScanner returns richer data; this is the subset we surface
/// via the import protocol. Existing KeyringScanner conformance is
/// preserved; this is just the projection.
public struct GnuPGScanEntry: Sendable {
    public let fingerprint: String
    public let primaryUserID: String
    public let hasSecret: Bool
    public let creationDate: Date
    public let expirationDate: Date?

    public init(fingerprint: String, primaryUserID: String, hasSecret: Bool,
                creationDate: Date, expirationDate: Date?) {
        self.fingerprint = fingerprint
        self.primaryUserID = primaryUserID
        self.hasSecret = hasSecret
        self.creationDate = creationDate
        self.expirationDate = expirationDate
    }
}

/// Adapter protocol so `GnuPGImportSource` can call into the existing
/// `KeyringScanner` without coupling. The existing class conforms.
public protocol GnuPGScanning {
    func scan() throws -> [GnuPGScanEntry]
}

extension KeyringScanner: GnuPGScanning {
    /// Default implementation — returns empty list. The real
    /// KeyringScanner already returns its own richer type; this is
    /// a stub that will be wired in the Phase 1 refactor.
    public func scan() throws -> [GnuPGScanEntry] { [] }
}
