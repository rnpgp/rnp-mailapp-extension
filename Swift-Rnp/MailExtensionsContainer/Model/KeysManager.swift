//
//  KeysManager.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation

class KeysManager: ObservableObject {
    @Published var items: [KeyFile] = []
    
    private let rnp: RnpFacade
    init(rnp: RnpFacade) {
        self.rnp = rnp
        guard rnp.hasKeys else { return }
            
        // TODO: remove mock
        self.items = KeyFile.mock
    }
    
    func addKeys() {
        rnp.createKeys()
        
        // TODO: remove mock
        self.items = KeyFile.mock
    }
}

extension KeysManager {
    static var mock: KeysManager {
        let manager = KeysManager(rnp: RnpFacade.mock)
        manager.items = KeyFile.mock
        return manager
    }
}
