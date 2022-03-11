//
//  RnpFacade.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 09.03.2022.
//

import Foundation
import Combine

class RnpFacade: ObservableObject {
    
    @Published var hasKeys: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    let object: RnpObject
    
    init(pubFormat: RnpKeyStoreFormat, secFormat: RnpKeyStoreFormat) {
        object = RnpObject(pubFormat: RnpConstants.rnpKeyStoreFormat_(toString: pubFormat),
                           secFormat: RnpConstants.rnpKeyStoreFormat_(toString: secFormat))
        
        setupObservables()
    }
    
    private func setupObservables() {
        object
            .publisher(for: \.hasKeys) // KVO
            .assign(to: \.hasKeys, on: self)
            .store(in: &cancellables)
    }
    
    func createKeys() {
        
    }
}

extension RnpFacade {
    static var mock: RnpFacade {
        RnpFacade(pubFormat: .gpg, secFormat: .gpg)
    }
}
