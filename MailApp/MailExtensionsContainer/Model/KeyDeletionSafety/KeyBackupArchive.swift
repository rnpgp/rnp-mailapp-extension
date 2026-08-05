//
//  KeyBackupArchive.swift
//  RNP
//
//  Before any key is deleted from RNP's canonical store, this module
//  produces an OpenPGP-encrypted archive of the key bytes. The
//  archive is itself a standard PGP message — recoverable via
//  `rnp decrypt backup.pgp`, `gpg -d backup.pgp`, or any OpenPGP
//  tool. The user picks the passphrase at delete time.
//
//  Why PGP (not zip -e or age):
//  - Native to RNP. We're an OpenPGP app; backups should be OpenPGP.
//  - No external dep — uses the same librnp engine.
//  - Recoverable on any platform with any OpenPGP tool.
//
//  Why symmetric (passphrase-only) and not encrypted-to-self:
//  - The user is deleting the key. Encrypting the backup to the key
//    being deleted would be circular — if they could decrypt the
//    backup, they wouldn't need it.
//  - Symmetric encryption with a fresh passphrase the user types at
//    delete time is the right model. They have to remember (or write
//    down) the passphrase to recover.
//
//  See docs/sync-architecture.md (delete safety section).
//

import Foundation
import MailSecurityEngine
import Rnp

public enum KeyBackupArchiveError: Error, LocalizedError {
    case keyManagerUnavailable
    case encryptionFailed(String)
    case writeFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .keyManagerUnavailable:
            return "error.deleteBackup.keyringUnavailable".localized
        case .encryptionFailed(let reason):
            return String(format: "error.deleteBackup.encryptionFailed".localized, reason)
        case .writeFailed(let url, let reason):
            return String(format: "error.deleteBackup.writeFailed".localized, url.lastPathComponent, reason)
        }
    }
}

/// Builds an OpenPGP-encrypted archive of one or more keys before
/// deletion. The output is a `.pgp` file containing all the keys'
/// bytes, encrypted symmetrically with a user-provided passphrase.
public enum KeyBackupArchive {

    /// Default location for backup archives. User can override via
    /// NSSavePanel at delete time.
    public static var defaultBackupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return docs.appendingPathComponent("RNP Backups", isDirectory: true)
    }

    /// Suggested filename: `rnp-keys-deleted-YYYY-MM-DD-HHMMSS.pgp`.
    public static func suggestedFilename(at date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return "rnp-keys-deleted-\(f.string(from: date)).pgp"
    }

    /// Produces the encrypted archive. The archive is a single
    /// OpenPGP message containing the concatenated armored keys,
    /// symmetrically encrypted with `passphrase`.
    ///
    /// - Parameters:
    ///   - fingerprints: Keys to include. Looked up in `manager`.
    ///   - passphrase: User-provided. Required for recovery.
    ///   - destination: Where to write the .pgp file.
    ///   - manager: Source of key bytes.
    static func write(
        fingerprints: [String],
        passphrase: String,
        to destination: URL,
        using manager: KeysManager
    ) throws -> BackupSummary {
        // Concatenate the armored key bytes for all fingerprints.
        // Uses KeysManager's public export API — doesn't reach into
        // the private KeyManager.
        var combined = Data()
        for fpr in fingerprints {
            // Prefer the secret key; fall back to public-only.
            if let armored = manager.exportSecretKey(fingerprint: fpr) {
                combined.append(armored)
            } else if let armored = manager.exportKey(fingerprint: fpr) {
                combined.append(armored)
            }
        }
        guard !combined.isEmpty else {
            throw KeyBackupArchiveError.encryptionFailed("No keys found to back up")
        }

        // Encrypt symmetrically via KeysManager's helper.
        guard let encrypted = manager.encryptWithPassword(combined, passphrase: passphrase) else {
            throw KeyBackupArchiveError.encryptionFailed("Symmetric encryption failed")
        }

        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encrypted.write(to: destination, options: .atomic)
        } catch {
            throw KeyBackupArchiveError.writeFailed(destination, error.localizedDescription)
        }

        return BackupSummary(
            url: destination,
            fingerprintCount: fingerprints.count,
            fingerprints: fingerprints,
            byteCount: encrypted.count,
            createdAt: Date()
        )
    }
}

public struct BackupSummary: Equatable, Sendable {
    public let url: URL
    public let fingerprintCount: Int
    public let fingerprints: [String]
    public let byteCount: Int
    public let createdAt: Date
}
