//
//  MailExtensionsContainerApp.swift
//  RNP for Mail
//
//  Container app for the RNP for Mail extension: manages the shared OpenPGP
//  keyring (generate, import, export, delete).
//

import SwiftUI
import Rnp
import RnpMailUI

@main
struct MailExtensionsContainerApp: App {
    @StateObject private var model = ContentViewModel(manager: KeysManager())

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Self.runSelfTest()
            NSApplication.shared.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup("RNP for Mail") {
            ContentView(model: model)
                .onAppear {
                    model.checkOnboarding()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("menu.newKey") {
                    model.beginGenerate(algorithm: .ed25519)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("menu.importKey") {
                    model.importFromFile()
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("menu.exportPublic") {
                    model.exportSelectedPublicToPasteboard()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.selectedKey == nil)

                Button("menu.deleteKey") {
                    model.showDeleteConfirmation = true
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedKey == nil)

                Divider()

                Button("menu.refreshKeys") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Button("menu.showOnboarding") {
                    model.reopenOnboarding()
                }
                Button("menu.keyservers") {
                    NotificationCenter.default.post(
                        name: .showKeyServerSettings,
                        object: nil
                    )
                }
                Button("menu.security") {
                    NotificationCenter.default.post(
                        name: .showSecuritySettings,
                        object: nil
                    )
                }
                Button("menu.licenses") {
                    NotificationCenter.default.post(
                        name: .showLicenses,
                        object: nil
                    )
                }
            }
        }
    }

    private static func runSelfTest() {
        print("RNP for Mail self-test starting...")
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
        print("RNP for Mail self-test passed")
    }
}
