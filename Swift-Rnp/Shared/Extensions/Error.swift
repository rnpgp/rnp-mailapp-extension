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
    case signIsRequired
}

extension RnpFacadeError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .signedMessageIsEmpty:
            return "Signed message is empty"
        case .encryptedMessageIsEmpty:
            return "Encrypted message is empty"
        case .signIsRequired:
            return "[WIP] Encryption without signing not supported"
        }
    }
}
