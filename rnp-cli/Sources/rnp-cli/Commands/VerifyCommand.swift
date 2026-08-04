//
//  VerifyCommand.swift
//  rnp-cli
//

import ArgumentParser
import Foundation
import MailSecurityEngine
import Rnp

struct VerifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify an OpenPGP signature."
    )

    @Argument(help: "Signed file (.pgp, .asc) or detached signature (.sig).")
    var signedFile: String

    @Option(name: .shortAndLong, help: "Original payload, for detached signatures only.")
    var payload: String?

    @Option(name: .shortAndLong, help: "Output format: human|json|porcelain")
    var output: OutputFormat = .human

    func run() throws {
        let signed = try Data(contentsOf: URL(fileURLWithPath: signedFile))
        let dir = CLIKeyring.directory()
        let manager = try KeyManager(directory: dir, keyedPassphraseProvider: { _, _ in nil })

        let isValid: Bool
        let signerFingerprint: String?
        try manager.withRnp { rnp in
            if let payloadPath = payload {
                let original = try Data(contentsOf: URL(fileURLWithPath: payloadPath))
                let v = try rnp.verifyDetachedDetailed(signature: signed, data: original)
                isValid = v.hasValidSignature
                signerFingerprint = v.signatures.first?.fingerprint
            } else {
                let v = try rnp.verifyDetailed(signed)
                isValid = v.hasValidSignature
                signerFingerprint = v.signatures.first?.fingerprint
            }
        }
        switch output {
        case .human:
            print(isValid ? "OK" : "FAIL")
            if let signerFingerprint { print("Signer: \(signerFingerprint)") }
        case .json:
            print(CLIJSON.encode([
                ("valid", isValid ? "true" : "false"),
                ("signerFingerprint", signerFingerprint ?? "")
            ]))
        case .porcelain:
            print("\(isValid ? "OK" : "FAIL"):\(signerFingerprint ?? "")")
        }
        if !isValid { throw ExitCode.failure }
    }
}
