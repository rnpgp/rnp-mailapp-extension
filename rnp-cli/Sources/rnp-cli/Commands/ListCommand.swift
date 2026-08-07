//
//  ListCommand.swift
//  rnp-cli
//
//  `rnp list` — list keys in the shared keyring.
//

import ArgumentParser
import Foundation
import MailSecurityEngine
import Librnp

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List keys in the keyring."
    )

    @Option(name: .shortAndLong, help: "Output format: human|json|porcelain")
    var output: OutputFormat = .human

    @Flag(name: .shortAndLong, help: "Show secret keys only")
    var secret = false

    func run() throws {
        let dir = CLIKeyring.directory()
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw CleanError.message("No keyring found at \(dir.path). Run `rnp keygen` first.")
        }
        let manager = try KeyManager(directory: dir, keyedPassphraseProvider: { _, _ in nil })
        try manager.withRnp { rnp in
            let publicKeys = (try? rnp.allUserIDs()) ?? []
            // The KeyManager.listKeys() API returns KeyInfo records
            // matching the GUI app's shape. We just dump them.
            let keys = (try? manager.listKeys()) ?? []
            let filtered = secret ? keys.filter { $0.hasSecret } : keys
            switch output {
            case .human:
                for key in filtered {
                    print("\(key.fingerprint)  \(key.primaryUserID)\(key.hasSecret ? "  [secret]" : "")")
                }
                if filtered.isEmpty { print("(no keys)") }
            case .json:
                let arr = filtered.map { CLIJSON.encode([
                    ("fingerprint", $0.fingerprint),
                    ("userID", $0.primaryUserID),
                    ("hasSecret", $0.hasSecret ? "true" : "false")
                ]) }.joined(separator: ",")
                print("[\(arr)]")
            case .porcelain:
                for key in filtered {
                    print("\(key.fingerprint):\(key.primaryUserID):\(key.hasSecret ? "S" : "P")")
                }
            }
            _ = publicKeys  // unused; keep reference for future expansion
        }
    }
}

enum CleanError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}
