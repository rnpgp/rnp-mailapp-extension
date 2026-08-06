//
//  KeyringBackupService.swift
//  RNP
//
//  Zips and unzips the App Group keyring directory. Backups include
//  pubring + secring + per-key .asc files + a manifest. Restore merges
//  — never overwrites — so users can recover from a backup without
//  losing keys added since.
//
//  Passphrases live in the Keychain, NOT in the backup. After restore,
//  users re-enter passphrases for restored secret keys.
//
//  See TODO.complete/19-keyring-backup-restore.md.
//

import Foundation
import Compression

public struct KeyringBackupManifest: Codable {
    public let formatVersion: Int     // currently 1
    public let appVersion: String
    public let createdAt: Date
    public let keyCount: Int
    public let includesSecretKeys: Bool
}

public struct KeyringRestoreReport: Equatable {
    public let importedKeys: Int
    public let skippedKeys: Int
    public let failedFiles: [String]
}

public enum KeyringBackupError: Error, LocalizedError {
    case sourceMissing(URL)
    case archiveUnreadable(URL)
    case manifestMissing
    case unsupportedFormat(found: Int, expected: Int)
    case writeFailed(URL, underlying: String?)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let url): return String(format: "error.backup.sourceMissing".localized, url.path)
        case .archiveUnreadable(let url): return String(format: "error.backup.archiveUnreadable".localized, url.path)
        case .manifestMissing: return "error.backup.manifestMissing".localized
        case .unsupportedFormat(let f, let e):
            return String(format: "error.backup.unsupportedFormat".localized, f, e)
        case .writeFailed(let url, let reason):
            return String(format: "error.backup.writeFailed".localized, url.path, reason ?? "")
        }
    }
}

/// Pure functions on the keyring directory + backup archives. No
/// dependency on KeyManager or MailSecurityEngine — testable in
/// isolation with a temp directory.
public enum KeyringBackupService {

    // MARK: Backup

    /// Builds a backup archive at `destinationURL` containing every
    /// file under `keyringDirectory`. The destination must end in
    /// `.rnp-keys.zip`; we don't append automatically because the
    /// caller picks the filename via NSSavePanel.
    public static func backup(
        from keyringDirectory: URL,
        to destinationURL: URL,
        appVersion: String,
        includesSecretKeys: Bool
    ) throws -> KeyringBackupManifest {
        let fm = FileManager.default
        guard fm.fileExists(atPath: keyringDirectory.path) else {
            throw KeyringBackupError.sourceMissing(keyringDirectory)
        }

        // Snapshot the keyring to a temp directory so the manifest can
        // be added without modifying the live keyring.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }

        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let manifest = KeyringBackupManifest(
            formatVersion: 1,
            appVersion: appVersion,
            createdAt: Date(),
            keyCount: try countKeys(in: keyringDirectory),
            includesSecretKeys: includesSecretKeys
        )

        // Copy keyring contents (preserve structure).
        if let entries = try? fm.contentsOfDirectory(at: keyringDirectory, includingPropertiesForKeys: nil) {
            for entry in entries {
                let dest = temp.appendingPathComponent(entry.lastPathComponent)
                try? fm.copyItem(at: entry, to: dest)
            }
        }

        // Write manifest.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: temp.appendingPathComponent("manifest.json"))

        // Zip temp → destination. NSFileCoordinator not needed; we own temp.
        try zip(directory: temp, to: destinationURL)
        RnpLogger.backup.info("wrote backup to \(destinationURL.path, privacy: .public): \(manifest.keyCount) keys")
        return manifest
    }

    // MARK: Restore

    /// Extracts `archiveURL` into a temp directory, reads its manifest,
    /// then merges the keyring files into `keyringDirectory`. Existing
    /// files are skipped (not overwritten).
    public static func restore(
        from archiveURL: URL,
        into keyringDirectory: URL
    ) throws -> KeyringRestoreReport {
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveURL.path) else {
            throw KeyringBackupError.archiveUnreadable(archiveURL)
        }

        let temp = fm.temporaryDirectory
            .appendingPathComponent("rnp-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)

        try unzip(archive: archiveURL, to: temp)

        // Read + validate manifest.
        let manifestURL = temp.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw KeyringBackupError.manifestMissing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(KeyringBackupManifest.self, from: manifestData)
        guard manifest.formatVersion == 1 else {
            throw KeyringBackupError.unsupportedFormat(found: manifest.formatVersion, expected: 1)
        }

        try fm.createDirectory(at: keyringDirectory, withIntermediateDirectories: true)
        return try merge(from: temp, into: keyringDirectory, skipping: ["manifest.json"])
    }

    // MARK: Internals

    /// Counts files matching `*.gpg` / `*.pgp` / `*.asc` in the
    /// keyring directory. Used for the manifest; not authoritative.
    private static func countKeys(in directory: URL) throws -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return entries.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["gpg", "pgp", "asc"].contains(ext)
        }.count
    }

    /// Copies every file in `source` into `destination` (recursing into
    /// subdirectories). Existing files are skipped — restore is a merge
    /// operation, never an overwrite. Files in `skip` (basenames) are
    /// ignored entirely.
    private static func merge(
        from source: URL,
        into destination: URL,
        skipping skip: [String]
    ) throws -> KeyringRestoreReport {
        let fm = FileManager.default
        var imported = 0
        var skipped = 0
        var failed: [String] = []

        let entries = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            if skip.contains(entry.lastPathComponent) { continue }
            let dest = destination.appendingPathComponent(entry.lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) {
                    skipped += 1
                    RnpLogger.backup.info("restore skipped existing \(dest.lastPathComponent, privacy: .public)")
                } else {
                    try fm.copyItem(at: entry, to: dest)
                    imported += 1
                    RnpLogger.backup.info("restore imported \(dest.lastPathComponent, privacy: .public)")
                }
            } catch {
                failed.append(entry.lastPathComponent)
                RnpLogger.backup.error("restore failed on \(entry.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return KeyringRestoreReport(importedKeys: imported, skippedKeys: skipped, failedFiles: failed)
    }

    /// Zip a directory using the system `ditto` shell command (handles
    /// resource forks correctly; same as Finder's "Compress"). For a
    /// pure-Swift implementation we'd need libcompression streaming,
    /// but ditto is on every Mac and reliable.
    private static func zip(directory: URL, to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", directory.path, archiveURL.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = try stderr.fileHandleForReading.readToEnd() ?? Data()
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw KeyringBackupError.writeFailed(archiveURL, underlying: message)
        }
    }

    private static func unzip(archive: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = try stderr.fileHandleForReading.readToEnd() ?? Data()
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            RnpLogger.backup.error("unzip failed for \(archive.path, privacy: .public): \(message ?? "unknown", privacy: .public)")
            throw KeyringBackupError.archiveUnreadable(archive)
        }
    }
}
