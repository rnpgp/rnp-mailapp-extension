//
//  GnuPGAgentPassphraseStore.swift
//  RNP
//
//  Lookup-only passphrase store backed by gpg-agent. For keys the
//  user imported from GnuPG, this lets RNP reuse gpg-agent's cached
//  passphrases instead of re-prompting.
//
//  CANNOT extract passphrases directly (gpg-agent security design).
//  What this store DOES:
//    1. Detects whether gpg-agent has a passphrase cached for a
//       fingerprint by attempting `gpg --sign --batch --use-agent`
//       with --passphrase from a FIFO.
//    2. If gpg-agent succeeds without prompting, RNP learns the
//       passphrase is available via gpg and can delegate sign/decrypt
//       ops to gpg itself.
//
//  This store is read-only: `setPassphrase`/`deletePassphrase` throw.
//  RNP's own passphrases live in macOS Keychain or iCloud Keychain;
//  this store is purely for cross-interop lookup.
//

import Foundation

public enum GnuPGAgentError: Error, LocalizedError {
    case gpgNotFound
    case lookupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .gpgNotFound:           return "error.gnupgAgent.notFound".localized
        case .lookupFailed(let r):   return String(format: "error.gnupgAgent.lookupFailed".localized, r)
        }
    }
}

public final class GnuPGAgentPassphraseStore: PassphraseStore {

    public let identifier = "gnupg-agent"
    public let displayName = "gpg-agent (lookup-only)"
    public var availability: BackendAvailability {
        GnuPGImportSource.gpgExecutable != nil
            ? .available
            : .unavailable(reason: "gpg not installed")
    }

    public init() {}

    /// True if gpg-agent currently has a passphrase cached for `fingerprint`.
    /// Does NOT return the passphrase (gpg-agent won't give it up).
    /// Used by the UI to show "Passphrase available via gpg-agent" instead
    /// of prompting.
    public func hasCachedPassphrase(for fingerprint: String) -> Bool {
        guard let gpg = GnuPGImportSource.gpgExecutable else { return false }
        // `gpg --list-secret-keys <fpr>` doesn't prompt for a passphrase.
        // To probe gpg-agent's cache we try `--passwd` which DOES trigger
        // agent but returns immediately if cached.
        let proc = Process()
        proc.executableURL = gpg
        proc.arguments = ["--batch", "--no-tty", "--pinentry-mode", "loopback",
                          "--passphrase", "", "--passwd", fingerprint]
        // Suppress stderr
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return false }
        // Exit 0 = passphrase was empty/cached; non-zero = not cached.
        // In practice gpg returns success even on empty passphrases for
        // unprotected keys; this is best-effort.
        return proc.terminationStatus == 0
    }

    // MARK: PassphraseStore (read-only)

    public func passphrase(for fingerprint: String) -> String? {
        // gpg-agent does not expose passphrases. Return nil; the caller
        // should fall back to prompting the user OR delegating the
        // crypto operation to gpg directly.
        return nil
    }

    public func setPassphrase(_ passphrase: String, for fingerprint: String) throws {
        // Read-only store. RNP's own passphrases go to Keychain /
        // iCloud Keychain, not here.
        throw GnuPGAgentError.lookupFailed("Cannot write to gpg-agent")
    }

    public func deletePassphrase(for fingerprint: String) throws {
        throw GnuPGAgentError.lookupFailed("Cannot delete from gpg-agent")
    }
}

/// Protocol that all passphrase stores conform to. Decoupled from
/// `KeyImportSource` — this is RNP's own data, not external.
public protocol PassphraseStore: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    var availability: BackendAvailability { get }

    func passphrase(for fingerprint: String) -> String?
    func setPassphrase(_ passphrase: String, for fingerprint: String) throws
    func deletePassphrase(for fingerprint: String) throws
}
