//
//  main.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 21.11.2021.
//

import Foundation

var object = RnpObject.init(pubFormat: RnpKeyStoreFormat.gpg.rawValue, secFormat: RnpKeyStoreFormat.gpg.rawValue)
if !object.hasKeys {
    object.createKeys("userID@key", password: "userPass") { success in
        print("Keys are \(success ? "generated" : "not generated")")
    }
}
