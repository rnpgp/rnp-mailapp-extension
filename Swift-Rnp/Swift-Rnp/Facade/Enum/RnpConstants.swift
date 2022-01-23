//
//  RnpConstants.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 20.01.2022.
//

import Foundation

@objc
enum RnpConstants: Int {
    case pubFileName
    case secFileName
}

extension RnpConstants: RawRepresentable {
    public typealias RawValue = String
    
    public var rawValue: RawValue {
        switch self {
        case .pubFileName:
            return "pubring.pgp"
        case .secFileName:
            return "secring.pgp"
        }
    }
    
    public init?(rawValue: RawValue) {
        switch rawValue {
        case "pubring.pgp":
            self = .pubFileName
        case "secring.pgp":
            self = .secFileName
        default:
            return nil
        }
    }
}
