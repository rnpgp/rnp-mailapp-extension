//
//  RnpFacade.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 09.03.2022.
//

import Foundation

class RnpFacade: ObservableObject {
    
    var hasKeys: Bool
    let password: String
    
    private var foreighKeysList: [String]
    
    private let object: RnpObject
    
    init(pubFormat: RnpKeyStoreFormat, secFormat: RnpKeyStoreFormat) {
        object = RnpObject(pubFormat: RnpConstants.rnpKeyStoreFormat_(toString: pubFormat),
                           secFormat: RnpConstants.rnpKeyStoreFormat_(toString: secFormat))
        
        hasKeys = object.hasOwnKeys
        
        if UserDefaults.password.isEmpty {
            // Create password for future use for all keys inside
            UserDefaults.password = String.randomString(length: 10)
        }
        password = UserDefaults.password
        
        foreighKeysList = UserDefaults.keysList
        
        // TODO: Implement managment for keys: valide by using | last using | filename. Also need to implement file deletion for unsuccessfully loaded ones.
        foreighKeysList = object.loadKeyFiles(foreighKeysList).compactMap{ $0.value.boolValue ? $0.key : nil }
    }
    
    func createKeys(userId: String, password: String) -> Result<Void, Error> {
        guard !object.hasOwnKeys else {
            hasKeys = true
            return .success()
        }
        
        do {
            try object.createKeys(userId, password: password)
            hasKeys = true
            return .success()
        } catch {
            return .failure(error)
        }
    }
    
    func checkKeyPresenceFor(_ email: String) -> Bool {
        object.isKeyExist(forUserId: email)
    }
    
    func signMessageData(_ messageData: Data, userId: String) -> Result<Data, Error> {
        do {
            let string = try object.sign(messageData, userId: userId, password: password)
            guard let data = string.data(using: .utf8) else {
                return .failure(RnpFacadeError.signedMessageIsEmpty)
            }
            return .success(data)
        } catch {
            return .failure(error)
        }
    }
    
    // TODO: return any signers info (into result) to deliver/check on upper level
    func verifyMessageString(_ signedMessage: String, detachedSign: String) -> Result<Void, Error> {
        do {
            try object.verifyRawString(signedMessage, detachedSign: detachedSign)
            return .success()
        } catch {
            return .failure(error)
        }
    }
    
    func encryptMessageData(_ messageData: Data, userId: String, password: String?) -> Result<Data, Error> {
        do {
            let string = try object.encryptData(messageData, userId: userId, password: password)
            guard let data = string.data(using: .utf8) else {
                return .failure(RnpFacadeError.encryptedMessageIsEmpty)
            }
            return .success(data)
        } catch {
            return .failure(error)
        }
    }
    
    func decryptMessage(message: String) -> String? {
        guard let decrypted = try? object.decryptString(message, password: password) else { return nil }
        return decrypted
    }
    
    @discardableResult
    func importKeyString(_ string: String, filename: String?) -> String? {
        // TODO: deliver import error to UI
        // TODO: Use filename if it present, in most cases it prevents copies for key files
        guard let filename = try? object.importKey(from: string) else { return nil }
            
        addFilename(filename)
        return filename
    }
    
        // MARK: - Private
    
    private func addFilename(_ name: String) {
        foreighKeysList.append(name)
        UserDefaults.keysList = foreighKeysList
    }
}

extension RnpFacade {
    static var mock: RnpFacade {
        RnpFacade(pubFormat: .gpg, secFormat: .gpg)
    }
}

extension RnpFacade {
    static func errorCodeCase(error: NSError) -> RnpErrorCode {
        RnpConstants.rnpErrorCode(Int32((error as NSError).code))
    }
}
