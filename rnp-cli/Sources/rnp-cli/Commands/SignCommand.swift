//
//  SignCommand.swift
//  rnp-cli
//

import ArgumentParser
import Foundation
import MailSecurityEngine
import Librnp

struct SignCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sign",
        abstract: "Sign a file (or stdin) with your secret key."
    )

    @Argument(help: "Input file. Use '-' or omit for stdin.")
    var inputFile: String? = nil

    @Option(name: .shortAndLong, help: "Signing key fingerprint or user ID.")
    var signer: String

    @Flag(name: .shortAndLong, help: "Produce a detached .sig instead of an inline signature.")
    var detached = false

    @Flag(name: .shortAndLong, help: "Cleartext-signed output (RFC 4880 §7). Text stays readable.")
    var cleartext = false

    func run() throws {
        let payload = try EncryptCommand.readInput(inputFile)
        let dir = CLIKeyring.directory()
        let manager = try KeyManager(directory: dir, keyedPassphraseProvider: { _, _ in nil })
        let signed: Data
        try manager.withRnp { rnp in
            let key = try rnp.requireKey(signer)
            if detached {
                signed = try rnp.signDetached(payload, with: key)
            } else if cleartext {
                signed = try rnp.signCleartext(payload, with: key)
            } else {
                signed = try rnp.sign(payload, with: key, armored: true)
            }
        }
        try EncryptCommand.writeOutput(signed, to: nil)  // always stdout
    }
}
