//
//  Error.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 13.04.2022.
//

import Foundation

enum RnpFacadeError: Error {
    case signedMessageIsEmpty
    case encryptedMessageIsEmpty
}
