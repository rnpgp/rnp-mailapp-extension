//
//  main.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 21.11.2021.
//

import Foundation

// TODO: next flags check isn't work as well #if ARCHITECTURE_INTEL, because it happen in bridhging header
// FIXME: For the moment only Intel lib is ready
let format = RnpConstants.rnpKeyStoreFormat_(toString: .gpg)
let object = RnpObject(pubFormat: format, secFormat: format)
    // FIXME: Think about keychain
let userId = "userId@key"
let password = "userPass"
if !object.hasOwnKeys {
    object.createKeys(userId, password: password) { success in
        print("Keys are \(success ? "generated" : "not generated")")
    }
}

let text: String = "What a day!"
if object.hasOwnKeys,
   let message = object.encryptString(text, userId: userId, password: password),
   let data: Data = message.data(using: .utf8),
   let message = object.decryptData(data, usingKeys: false, password: password) {
    print("encoded and decoded - \(message)")
}
