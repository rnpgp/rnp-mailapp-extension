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
//  Delegates to the existing `KeyringScanner` (already read-only).
//

import Foundation
import MailSecurityEngine

public final class GnuPGImportSource: KeyImportSource {

    public let identifier = "gnupg"
    public let displayName = "GnuPG keyring (~/.gnupg)"
    public var availability: BackendAvailability {
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

    /// Returns keys currently visible at ~/.gnupg. Pure read — does
    /// NOT modify GnuPG. Delegates to KeyringScanner.discoverAll()
    /// and filters to the .gnupg source.
    public func listAvailable() async throws -> [KeyringKeyRecord] {
        guard availability == .available else { return [] }
        let discovered = KeyringScanner.discoverAll()
        // discoverAll returns ALL sources; we only want GnuPG.
        let gnupgKeys = discovered
            .first { $0.source == .gnupg }?
            .keys ?? []
        return gnupgKeys.map { key in
            KeyringKeyRecord(
                id: key.fingerprint,
                primaryUserID: key.primaryUserID,
                allUserIDs: key.userIDs,
                keyBytes: Data(),  // bytes fetched on-demand via `gpg --export --armor <fpr>` at import time
                hasSecret: key.hasSecret,
                keyCreationDate: Date(),  // KeyringScanner doesn't expose creation; left as discovery time
                keyExpirationDate: nil,
                modifiedAt: Date(),
                modifiedBy: "gnupg"
            )
        }
    }

    /// Exports a single key's bytes from GnuPG via `gpg --export --armor`.
    /// Used at import time to actually get the armored key bytes (which
    /// listAvailable leaves empty by design — the bytes aren't needed
    /// for display, only for import).
    /// Pure read — does NOT modify GnuPG.
    public func exportKey(fingerprint: String) -> Data? {
        guard let gpg = Self.gpgExecutable else { return nil }
        let proc = Process()
        proc.executableURL = gpg
        proc.arguments = ["--batch", "--yes", "--export", "--armor", fingerprint]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()  // discard
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    // MARK: Internals

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
}
