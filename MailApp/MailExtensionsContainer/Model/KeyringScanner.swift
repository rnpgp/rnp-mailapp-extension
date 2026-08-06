//
//  KeyringScanner.swift
//  RNP for Mail
//
//  Detects the user's existing OpenPGP keyrings on disk (~/.gnupg,
//  ~/.rnp) and lists their keys read-only. Nothing this scanner does
//  ever writes to the source keyring — it only reads.
//
//  Per the absolute rule [[never-wipe-user-keys]]: this scanner is a
//  read-only operation against any source keyring. Import is a
//  separate, user-driven step that copies keys into the app's own
//  keyring, never back the other way.
//

import Foundation
import MailSecurityEngine
import Rnp

enum KeyringSource: String, CaseIterable, Hashable {
    case gnupg
    case rnp

    var displayName: String {
        switch self {
        case .gnupg: return "GnuPG"
        case .rnp:   return "RNP"
        }
    }

    var homePath: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .gnupg: return home.appendingPathComponent(".gnupg")
        case .rnp:   return home.appendingPathComponent(".rnp")
        }
    }

    /// True if the keyring directory exists and looks like it has at
    /// least one keyring file inside.
    var isInstalled: Bool {
        guard let path = homePath,
              FileManager.default.fileExists(atPath: path.path) else {
            return false
        }
        switch self {
        case .gnupg:
            // Modern GnuPG uses pubring.kbx; legacy used pubring.gpg.
            return FileManager.default.fileExists(atPath: path.appendingPathComponent("pubring.kbx").path)
                || FileManager.default.fileExists(atPath: path.appendingPathComponent("pubring.gpg").path)
        case .rnp:
            return FileManager.default.fileExists(atPath: path.appendingPathComponent("pubring.gpg").path)
        }
    }
}

struct DiscoveredKey: Identifiable, Hashable {
    let id = UUID()
    let fingerprint: String
    let userIDs: [String]
    let hasSecret: Bool
    let source: KeyringSource

    var primaryUserID: String { userIDs.first ?? fingerprint }
}

struct DiscoveredKeyring: Identifiable, Hashable {
    let id = UUID()
    let source: KeyringSource
    let path: URL
    let keys: [DiscoveredKey]
}

enum KeyringScanner {
    /// Walk every known source location, return those present on disk
    /// with their keys. Read-only — never writes to source keyrings.
    static func discoverAll() -> [DiscoveredKeyring] {
        KeyringSource.allCases
            .filter(\.isInstalled)
            .compactMap { source in
                guard let path = source.homePath else { return nil }
                let keys: [DiscoveredKey]
                switch source {
                case .gnupg: keys = scanGnuPG(at: path) ?? []
                case .rnp:   keys = scanRNP(at: path) ?? []
                }
                return DiscoveredKeyring(source: source, path: path, keys: keys)
            }
    }

    /// Export the given key as ASCII-armored data, ready for the
    /// existing `KeysManager.importKeys(Data)` path. Returns nil on
    /// any failure (user can retry or use the file-picker fallback).
    static func exportArmored(_ key: DiscoveredKey) -> Data? {
        switch key.source {
        case .gnupg:
            return exportGnuPG(fingerprint: key.fingerprint)
        case .rnp:
            return exportRNP(fingerprint: key.fingerprint, secret: key.hasSecret)
        }
    }

    // MARK: - GnuPG

    private static func scanGnuPG(at home: URL) -> [DiscoveredKey]? {
        guard let gpg = locate("gpg") else { return nil }
        // --list-secret-keys surfaces the user's own keys (the ones worth
        // importing into a Mail extension). --with-colons is the stable
        // machine-readable format; --no-tty prevents pinentry popups.
        let output = runProcess(exec: gpg, args: [
            "--homedir", home.path,
            "--list-secret-keys",
            "--with-fingerprint",
            "--with-colons",
            "--no-tty",
            "--fingerprint"
        ])
        return parseGnuPGColon(output)
    }

    private static func exportGnuPG(fingerprint: String) -> Data? {
        guard let gpg = locate("gpg"),
              let home = KeyringSource.gnupg.homePath else { return nil }
        // Export both public and secret halves. --export-secret-keys
        // prompts via gpg-agent (typically macOS keychain or pinentry);
        // a cancelled prompt yields an empty blob and we return nil so
        // the UI can show the user that one key didn't come through.
        let pub = runProcess(exec: gpg, args: [
            "--homedir", home.path, "--no-tty", "--armor",
            "--export", fingerprint
        ])
        let sec = runProcess(exec: gpg, args: [
            "--homedir", home.path, "--no-tty", "--armor",
            "--export-secret-keys", fingerprint
        ])
        // Prefer the secret-inclusive blob if we got it; fall back to pub.
        let armored = sec.isEmpty ? pub : sec
        return armored.isEmpty ? nil : Data(armored.utf8)
    }

    /// Parse `gpg --with-colons` output into DiscoveredKey records.
    /// See https://github.com/MLZ-chanYileskyo/gnupg-doc/blob/master/doc/DETAILS
    private static func parseGnuPGColon(_ output: String) -> [DiscoveredKey] {
        var keys: [DiscoveredKey] = []
        var currentFpr: String?
        var currentUserIDs: [String] = []

        let flush: (String?) -> Void = { fpr in
            guard let fpr else { return }
            keys.append(DiscoveredKey(
                fingerprint: fpr,
                userIDs: currentUserIDs,
                hasSecret: true,
                source: .gnupg
            ))
            currentUserIDs = []
        }

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let kind = fields.first else { continue }
            switch kind {
            case "sec", "pub":
                flush(currentFpr)
                currentFpr = nil
            case "fpr":
                // First fpr after pub/sec is the primary fingerprint.
                // Subsequent fprs (before the next pub/sec) are subkeys.
                if currentFpr == nil, fields.count > 9 {
                    currentFpr = fields[9]
                }
            case "uid":
                // UID field layout: uid:status:validity:...:userID-text:...
                // The text is at index 9.
                if fields.count > 9, !fields[9].isEmpty {
                    currentUserIDs.append(fields[9])
                }
            default:
                break
            }
        }
        flush(currentFpr)
        return keys
    }

    // MARK: - RNP (librnp)

    private static func scanRNP(at home: URL) -> [DiscoveredKey]? {
        // Open the keyring directory with a no-op passphrase provider —
        // listing public keys does not require a passphrase.
        let provider: Rnp.KeyedPassphraseProvider = { _, _ in nil }
        guard let manager = try? KeyringStore(directory: home, keyedPassphraseProvider: provider) else {
            return nil
        }
        guard let publicKeys = try? manager.listKeys() else { return [] }
        return publicKeys.map { info in
            DiscoveredKey(
                fingerprint: info.fingerprint,
                userIDs: info.userIDs,
                hasSecret: info.hasSecret,
                source: .rnp
            )
        }
    }

    private static func exportRNP(fingerprint: String, secret: Bool) -> Data? {
        guard let home = KeyringSource.rnp.homePath else { return nil }
        let provider: Rnp.KeyedPassphraseProvider = { _, _ in nil }
        guard let manager = try? KeyringStore(directory: home, keyedPassphraseProvider: provider) else {
            return nil
        }
        // Public export never needs a passphrase. Secret export would
        // need one; for now we surface only the public half and the
        // user keeps the secret in their original RNP keyring.
        return try? manager.exportKey(fingerprint: fingerprint, secret: false)
    }

    // MARK: - Process helpers

    private static func locate(_ binary: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(binary)",
            "/usr/local/bin/\(binary)",
            "/usr/bin/\(binary)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runProcess(exec: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exec)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()  // silence
        do {
            try proc.run()
        } catch {
            return ""
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
