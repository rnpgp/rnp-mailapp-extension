//
//  MailExtensionsContainerApp.swift
//  MailExtensionsContainer
//
//  Created by Sergey Vinogradov on 30.11.2021.
//

import SwiftUI

@main
struct MailExtensionsContainerApp: App {
    var keysManager: KeysManager {
        KeysManager(rnp: RnpFacade(pubFormat: .gpg, secFormat: .gpg))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(model: ContentViewModel(manager: self.keysManager))
        }
    }
}
