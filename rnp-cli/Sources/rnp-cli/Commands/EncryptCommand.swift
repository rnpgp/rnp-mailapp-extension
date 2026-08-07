//
//  EncryptCommand.swift
//  rnp-cli
//
//  `rnp encrypt` — encrypt stdin (or a file) to recipients. Writes
//  ASCII-armored ciphertext to stdout.
//

import ArgumentParser
import Foundation
import MailSecurityEngine
import Librnp

struct EncryptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encrypt",
        abstract: "Encrypt a file (or stdin) to OpenPGP recipients."
    )

    @Argument(help: "Input file. Use '-' or omit for stdin.")
    var inputFile: String? = nil

    @Option(name: .shortAndLong, help: "Recipient fingerprint or user ID. Repeatable.")
    var recipient: [String]

    @Option(name: .shortAndLong, help: "Output file. Default: stdout.")
    var output: String? = nil

    func run() throws {
        let plaintext = try Self.readInput(inputFile)
        let dir = CLIKeyring.directory()
        let manager = try KeyManager(directory: dir, keyedPassphraseProvider: { _, _ in nil })
        let ciphertext: Data
        try manager.withRnp { rnp in
            var recipientKeys: [RnpKey] = []
            for r in recipient {
                guard let key = try? rnp.locateKey(r) else {
                    throw CleanError.message("Recipient not found: \(r)")
                }
                recipientKeys.append(key)
            }
            guard !recipientKeys.isEmpty else {
                throw CleanError.message("No recipients. Pass -r <fingerprint or user ID>.")
            }
            ciphertext = try rnp.encrypt(plaintext, for: recipientKeys, armored: true)
        }
        try Self.writeOutput(ciphertext, to: output)
    }

    static func readInput(_ path: String?) throws -> Data {
        guard let path, path != "-" else { return FileHandle.standardInput.readDataToEndOfFile() }
        let url = URL(fileURLWithPath: path)
        return try Data(contentsOf: url)
    }

    static func writeOutput(_ data: Data, to path: String?) throws {
        guard let path else {
            FileHandle.standardOutput.write(data)
            return
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
