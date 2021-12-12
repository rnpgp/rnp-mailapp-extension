//
//  ContentViewModel.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation

class ContentViewModel {
    
    var listModel: KeysListViewModel {
        KeysListViewModel(manager: self.manager)
    }
    
    private var manager: KeysManager
    
    init(manager: KeysManager) {
        self.manager = manager
    }
}
