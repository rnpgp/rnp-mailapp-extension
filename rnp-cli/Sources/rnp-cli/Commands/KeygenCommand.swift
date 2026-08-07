//
//  KeygenCommand.swift
//  rnp-cli
//
//  `rnp keygen` — generate a new OpenPGP key.
//

import ArgumentParser
import Foundation
import MailSecurityEngine
import Librnp

struct KeygenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keygen",
        abstract: "Generate a new OpenPGP key."
    )

    @Option(name: .shortAndLong, help: "User ID, e.g. \"Alice <alice@example.com>\"")
    var name: String

    @Option(name: .shortAndLong, help: "Algorithm: ed25519 | rsa | ecdsa")
    var algorithm: String = "ed25519"

    @Option(help: "Passphrase for the new secret key. Leave empty to be prompted.")
    var passphrase: String?

    func run() throws {
        let dir = CLIKeyring.directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manager = try KeyManager(directory: dir, keyedPassphraseProvider: { _, _ in nil })
        let alg: KeyAlgorithm
        switch algorithm.lowercased() {
        case "ed25519", "eddsa": alg = .ed25519
        case "rsa":               alg = .rsa
        case "ecdsa":             alg = .ecdsa
        default:
            throw CleanError.message("Unknown algorithm: \(algorithm)")
        }
        let pw = passphrase ?? Self.promptPassphrase()
        let json: String
        switch alg {
        case .ed25519: json = Rnp.ed25519KeyGenJSON(userid: name, expirationSeconds: 0)
        case .rsa:     json = Rnp.rsaKeyGenJSON(userid: name, expirationSeconds: 0)
        case .ecdsa:   json = Rnp.ecdsaP256KeyGenJSON(userid: name, expirationSeconds: 0)
        default:
            throw CleanError.message("Algorithm \(alg) not supported by keygen yet")
        }
        try manager.withRnp { rnp in
            try rnp.generateKey(json: json, password: pw)
        }
        print("Generated \(alg.rawValue) key for \(name)")
        print("Keyring: \(dir.path)")
    }

    private static func promptPassphrase() -> String {
        print("Passphrase: ", terminator: "")
        return Self.readSecure()
    }

    /// Reads a passphrase from /dev/tty with echo disabled. Avoids
    /// Foundation's `SecureField` (UI only).
    private static func readSecure() -> String {
        let tty = FileHandle(forUpdatingAtPath: "/dev/tty") ?? .standardInput
        // Disable echo via stty -echo
        ProcRunner.run("/usr/bin/stty", ["-echo"])
        defer { ProcRunner.run("/usr/bin/stty", ["echo"]) }
        let data = tty.availableData
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum ProcRunner {
    static func run(_ executable: String, _ args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        try? proc.run()
        proc.waitUntilExit()
    }
}
