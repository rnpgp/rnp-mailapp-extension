//
//  MailExtensionsContainerApp.swift
//  MailExtensionsContainer
//
//  Container app for the RNP Mail extension: manages the shared OpenPGP
//  keyring (generate, import, export, delete).
//

import SwiftUI
import Rnp

@main
struct MailExtensionsContainerApp: App {
    @StateObject private var keysManager = KeysManager()

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Self.runSelfTest()
            NSApplication.shared.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: ContentViewModel(manager: keysManager))
        }
    }

    private static func runSelfTest() {
        print("RnpMail self-test starting...")
        print("librnp \(Rnp.versionStringFull)")
        do {
            let rnp = try Rnp(password: "self-test-password")
            let userID = "Self Test <self-test@example.com>"
            try rnp.generateKey(json: Rnp.rsaKeyGenJSON(userid: userID))
            let key = try rnp.requireKey(userID)
            print("self-test generated key: \(try key.fingerprint)")
            let message = Data("self-test roundtrip".utf8)
            let encrypted = try rnp.encrypt(message, for: [key])
            let decrypted = try rnp.decrypt(encrypted)
            guard decrypted == message else {
                fputs("self-test roundtrip mismatch\n", stderr)
                exit(1)
            }
            print("self-test encrypt/decrypt roundtrip OK")
        } catch {
            fputs("self-test error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        print("RnpMail self-test passed")
    }
}
