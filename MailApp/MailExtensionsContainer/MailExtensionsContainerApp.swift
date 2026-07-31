//
//  MailExtensionsContainerApp.swift
//  RNP for Mail
//
//  Container app for the RNP for Mail product: manages the shared OpenPGP
//  keyring, hosts the Mail extension, and provides File Tools for
//  encrypting/decrypting files outside of Mail.
//
//  Branding: the product is "RNP for Mail". Every user-visible window
//  title, menu label, and DMG name uses that name. Bundle IDs stay
//  com.rnpgp.RNPForMail (implementation detail). The RNP technology
//  brand is reserved for librnp / the OpenPGP engine.
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
        // Primary window: key manager.
        WindowGroup("RNP for Mail") {
            ContentView(model: model)
                .onAppear {
                    model.checkOnboarding()
                }
                .background(WindowOpener())
        }
        // File Tools: standalone workspace. Same product brand, distinct
        // window title so the two don't collide in the Window menu.
        WindowGroup("fileTools.windowTitle".localized, id: "file-tools") {
            FileToolsView(model: model)
        }
        .defaultSize(width: 640, height: 520)
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

                Divider()

                Button("menu.fileTools") {
                    NotificationCenter.default.post(name: .openFileTools, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Button("menu.showOnboarding") {
                    model.reopenOnboarding()
                }
                Button("menu.keyservers") {
                    model.currentSheet = .keyServerSettings
                }
                Button("menu.security") {
                    model.currentSheet = .securitySettings
                }
                Button("menu.licenses") {
                    model.currentSheet = .licenses
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

extension Notification.Name {
    /// Posted to open (or focus) the File Tools window.
    static let openFileTools = Notification.Name("com.rnpgp.RNPForMail.openFileTools")
}

/// Invisible helper that holds the openWindow environment action so
/// menu items (which live outside the View hierarchy) can open the
/// File Tools WindowGroup by posting `.openFileTools`.
private struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openFileTools)) { _ in
                openWindow(id: "file-tools")
            }
    }
}
