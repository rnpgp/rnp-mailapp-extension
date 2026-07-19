//
//  MailExtensionsContainerApp.swift
//  MailExtensionsContainer
//
//  Container app for the RNP Mail extension: manages the shared OpenPGP
//  keyring (generate, import, export, delete).
//

import SwiftUI

@main
struct MailExtensionsContainerApp: App {
    @StateObject private var keysManager = KeysManager()

    var body: some Scene {
        WindowGroup {
            ContentView(model: ContentViewModel(manager: keysManager))
        }
    }
}
