//
//  RnpFacade.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 09.03.2022.
//

import Foundation
import Combine

enum RnpFacadeError: Error {
    case importKeyFail
}

class RnpFacade: ObservableObject {
    
    @Published var hasKeys: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var keysFilesList: [String]
    
    let object: RnpObject
    
    init(pubFormat: RnpKeyStoreFormat, secFormat: RnpKeyStoreFormat) {
        object = RnpObject(pubFormat: RnpConstants.rnpKeyStoreFormat_(toString: pubFormat),
                           secFormat: RnpConstants.rnpKeyStoreFormat_(toString: secFormat))
        
        keysFilesList = UserDefaults.keysList
        
        // TODO: Implement physically removing files
        // Remove all not-succesfully loaded files
        keysFilesList = object.loadKeyFiles(keysFilesList).compactMap{ $0.value.boolValue ? $0.key : nil }
        setupObservables()
    }
    
    private func setupObservables() {
        object
            .publisher(for: \.hasOwnKeys) // KVO
            .assign(to: \.hasKeys, on: self)
            .store(in: &cancellables)
    }
    
    func createKeys(userId: String, password: String) {
        guard !object.hasOwnKeys else { return }
        
        object.createKeys(userId, password: password, completion: {_ in });
    }
    
    func checkKeyPresenceFor(_ email: String) -> Bool {
        object.isKeyExist(forUserId: email)
    }
    
    func decryptMessage(message: String) -> String? {
        guard let decrypted = object.decryptString(message, usingKeys: true, password: nil) else { return nil }
        return decrypted
    }
    
    @discardableResult
    func importKeyString(_ string: String) -> String? {
        guard let filename = object.importKey(from: string) else { return nil }
            
        addFilename(filename)
        return filename
    }
    
        // MARK: - Private
    
    private func addFilename(_ name: String) {
        keysFilesList.append(name)
        UserDefaults.keysList = keysFilesList
    }
}

extension RnpFacade {
    static var mock: RnpFacade {
        RnpFacade(pubFormat: .gpg, secFormat: .gpg)
    }
}
