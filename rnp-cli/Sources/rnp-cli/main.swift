//
//  main.swift
//  rnp-cli
//
//  Entry point. Delegates to RnpCLI.parseAsRoot() — ArgumentParser
//  handles argv + dispatch to the right @Command struct.
//
//  Adding a new subcommand: declare a `struct FooCommand: Parsable.Command`
//  in its own file under `Commands/`, then add `.command(FooCommand())` to
//  `RnpCLI.commands` below.
//

import ArgumentParser

@main
struct RnpCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rnp",
        abstract: "OpenPGP for macOS — keys, files, and Mail. Powered by librnp.",
        version: "0.1.0",
        subcommands: [
            KeygenCommand.self,
            ListCommand.self,
            EncryptCommand.self,
            DecryptCommand.self,
            SignCommand.self,
            VerifyCommand.self,
        ]
    )
}

// Pull in the command implementations. Each file in Commands/ adds one.
