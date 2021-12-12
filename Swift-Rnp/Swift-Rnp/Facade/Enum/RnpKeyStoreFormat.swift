//
//  RnpKeyStoreFormat.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 02.12.2021.
//

enum RnpKeyStoreFormat: String {
    case gpg, kbx, g10, g21
    
    var rawValue: String {
        switch self {
        case .gpg:
            return RNP_KEYSTORE_GPG
        case .kbx:
            return RNP_KEYSTORE_KBX
        case .g10:
            return RNP_KEYSTORE_G10
        case .g21:
            return RNP_KEYSTORE_GPG21
        }
    }
}
