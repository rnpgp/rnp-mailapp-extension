//
//  main.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 21.11.2021.
//

import Foundation

// TODO: next flags check isn't work as well #if ARCHITECTURE_INTEL, because it happen in bridhging header
// FIXME: For the moment only Intel lib is ready

var object = RnpObject.init(pubFormat: "GPG"/*RnpKeyStoreFormat.gpg.rawValue*/, secFormat: "GPG"/*RnpKeyStoreFormat.gpg.rawValue*/)
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
