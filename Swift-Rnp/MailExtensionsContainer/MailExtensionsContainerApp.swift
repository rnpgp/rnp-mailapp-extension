//
//  MailExtensionsContainerApp.swift
//  MailExtensionsContainer
//
//  Created by Sergey Vinogradov on 30.11.2021.
//

import SwiftUI

@main
struct MailExtensionsContainerApp: App {
    let keysManager = KeysManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(model: ContentViewModel(manager: keysManager))
        }
    }
}
