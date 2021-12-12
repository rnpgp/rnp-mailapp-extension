//
//  ContentViewModel.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation
import Combine

class ContentViewModel: ObservableObject {
    @Published var hasKeys: Bool = false
    
    var listModel: KeysListViewModel {
        KeysListViewModel(manager: self.manager)
    }
    
    private var manager: KeysManager
    private var cancellables = Set<AnyCancellable>()
    
    init(manager: KeysManager) {
        self.manager = manager
        setupObservables()
    }
    
    private func setupObservables() {
        manager
            .$items
            .map{ !$0.isEmpty }
            .assign(to: \.hasKeys, on: self)
            .store(in: &cancellables)
    }
    
    func addKeys() {
        manager.addKeys()
    }
}
