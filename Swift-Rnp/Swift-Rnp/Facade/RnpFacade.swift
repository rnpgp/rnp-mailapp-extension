//
//  RnpFacade.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 02.12.2021.
//

import Foundation

protocol RnpFacadeProtocol {
    // TODO: Cover whole functionality by protocol
    // init(withFormats pub: String, sec: String)
    var hasKeys: Bool { get }
}

class RnpFacade: RnpFacadeProtocol {
    var hasKeys: Bool {
        RnpFacade.hasKeys()
    }
    
    /// By default you can use GPG
    private static let defaultKeysFormat = RnpKeyStoreFormat.gpg.rawValue
    
    /**
     Check if keys files are presented
     - returns:`true` in case of files are on the place
     - warning: It return `false` in any error cace
     */
    @discardableResult
    static func hasKeys() -> Bool {
        wHasKeys(RnpFacade.defaultKeysFormat, RnpFacade.defaultKeysFormat) == 1
    }
    
    /**
     Try to create keys files
     - returns:`true` in case of keys was created and files are saved succesfully
     - warning: Keys will be created on ~/Library/Containers/**BuildID**/Data/, so for container app and the plugin **BuildID** should be the same
     */
    @discardableResult
    static func createKeys() -> Bool {
        wCreateKeys(RnpFacade.defaultKeysFormat, RnpFacade.defaultKeysFormat) == 1
    }
    
    
    @discardableResult
    static func decrypt(_ useKeys: Bool) -> Bool {
        wDecrypt(RnpFacade.defaultKeysFormat, RnpFacade.defaultKeysFormat, useKeys ? 1 : 0) == 1
    }
}
