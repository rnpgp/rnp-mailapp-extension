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

let userId = "userId@key"
let password = "userPass"
if !object.hasOwnKeys {
    do {
        try object.createKeys(userId, password: password)
        print("Keys are generated")
    } catch {
        print("Keys aren't generated \(error.localizedDescription)")
    }
}

let text: String = "What a day!"
if object.hasOwnKeys,
   let message = try? object.encryptString(text, userId: userId, password: password),
   let data: Data = message.data(using: .utf8),
   let decrypted = try? object.decryptData(data, password: password) {
    print("encoded and decoded - \(decrypted)")
}
