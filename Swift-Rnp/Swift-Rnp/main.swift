//
//  main.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 21.11.2021.
//

import Foundation

var object = RnpObject.init(pubFormat: RnpKeyStoreFormat.gpg.rawValue, secFormat: RnpKeyStoreFormat.gpg.rawValue)
// FIXME: Think about keychain
let password = "userPass"
if !object.hasKeys {
    object.createKeys("userId@key", password: password) { success in
        print("Keys are \(success ? "generated" : "not generated")")
    }
}

if object.hasKeys, let message = object.decrypt(usingKeys: true, password: password) {
    print(message)
}
