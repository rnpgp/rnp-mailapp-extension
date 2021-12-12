//
//  KeysListViewModel.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation
import Combine

class KeysListViewModel: ObservableObject {
    @Published var keyFiles: [KeyFile] = []
    
    private let manager: KeysManager
    private var cancellables = Set<AnyCancellable>()
    
    init(manager: KeysManager) {
        self.manager = manager
        
        setupObservables()
    }
    
    private func setupObservables() {
        manager
            .$items
            .assign(to: \.keyFiles, on: self)
            .store(in: &cancellables)
    }
}
