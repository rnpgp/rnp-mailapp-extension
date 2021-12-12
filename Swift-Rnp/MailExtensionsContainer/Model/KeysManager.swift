//
//  KeysManager.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation

class KeysManager: ObservableObject {
    @Published var items: [KeyFile] = []
    
    init() {
        guard RnpFacade.hasKeys() else { return }
            
        // TODO: remove mock
        self.items = KeyFile.mock
    }
    
    func addKeys() {
        RnpFacade.createKeys()
        
        // TODO: remove mock
        self.items = KeyFile.mock
    }
}

extension KeysManager {
    static var mock: KeysManager {
        let manager = KeysManager()
        manager.items = KeyFile.mock
        return manager
    }
}
