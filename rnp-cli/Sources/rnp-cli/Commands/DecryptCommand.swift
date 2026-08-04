//
//  DecryptCommand.swift
//  rnp-cli
//

import ArgumentParser
import Foundation
import MailSecurityEngine

struct DecryptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decrypt",
        abstract: "Decrypt an OpenPGP message (file or stdin)."
    )

    @Argument(help: "Input file. Use '-' or omit for stdin.")
    var inputFile: String? = nil

    @Option(name: .shortAndLong, help: "Passphrase for the keyring.")
    var passphrase: String?

    @Option(name: .shortAndLong, help: "Output file. Default: stdout.")
    var output: String? = nil

    func run() throws {
        let ciphertext = try EncryptCommand.readInput(inputFile)
        let dir = CLIKeyring.directory()
        let pw = passphrase ?? ""
        let manager = try KeyManager(directory: dir, keyedPassphraseProvider: { _, _ in pw.isEmpty ? nil : pw })
        let plaintext: Data
        try manager.withRnp { rnp in
            plaintext = try rnp.decrypt(ciphertext)
        }
        try EncryptCommand.writeOutput(plaintext, to: output)
    }
}
