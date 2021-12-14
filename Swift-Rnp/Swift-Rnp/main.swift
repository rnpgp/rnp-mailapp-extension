//
//  main.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 21.11.2021.
//

import Foundation

print("Check keys")
if RnpFacade.hasKeys() {
    print("Already has keys")
    RnpFacade.decrypt(true)
} else {
    print("Create keys")
    RnpFacade.createKeys()
}
