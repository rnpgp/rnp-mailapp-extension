//
//  RnpAlgorythm.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 25.12.2021.
//

import Foundation

enum RnpAlgorythm: String {
    case plaintext
    case rsa
    case elgamal
    case dsa
    case ecdh
    case ecdsa
    case eddsa
    case idea
    case tripledes
    case cast5
    case blowfish
    case twofish
    case aes128
    case aes192
    case aes256
    case camellia128
    case camellia192
    case camellia256
    case sm2
    case sm3
    case sm4
    case md5
    case sha1
    case sha256
    case sha384
    case sha512
    case sha224
    case sha3256
    case sha3512
    case ripemd160
    case crc24
    
    var rawValue: String {
        switch self {
        case .plaintext:
            return RNP_ALGNAME_PLAINTEXT
        case .rsa:
            return RNP_ALGNAME_RSA
        case .elgamal:
            return RNP_ALGNAME_ELGAMAL
        case .dsa:
            return RNP_ALGNAME_DSA
        case .ecdh:
            return RNP_ALGNAME_ECDH
        case .ecdsa:
            return RNP_ALGNAME_ECDSA
        case .eddsa:
            return RNP_ALGNAME_EDDSA
        case .idea:
            return RNP_ALGNAME_IDEA
        case .tripledes:
            return RNP_ALGNAME_TRIPLEDES
        case .cast5:
            return RNP_ALGNAME_CAST5
        case .blowfish:
            return RNP_ALGNAME_BLOWFISH
        case .twofish:
            return RNP_ALGNAME_TWOFISH
        case .aes128:
            return RNP_ALGNAME_AES_128
        case .aes192:
            return RNP_ALGNAME_AES_192
        case .aes256:
            return RNP_ALGNAME_AES_256
        case .camellia128:
            return RNP_ALGNAME_CAMELLIA_128
        case .camellia192:
            return RNP_ALGNAME_CAMELLIA_192
        case .camellia256:
            return RNP_ALGNAME_CAMELLIA_256
        case .sm2:
            return RNP_ALGNAME_SM2
        case .sm3:
            return RNP_ALGNAME_SM3
        case .sm4:
            return RNP_ALGNAME_SM4
        case .md5:
            return RNP_ALGNAME_MD5
        case .sha1:
            return RNP_ALGNAME_SHA1
        case .sha256:
            return RNP_ALGNAME_SHA256
        case .sha384:
            return RNP_ALGNAME_SHA384
        case .sha512:
            return RNP_ALGNAME_SHA512
        case .sha224:
            return RNP_ALGNAME_SHA224
        case .sha3256:
            return RNP_ALGNAME_SHA3_256
        case .sha3512:
            return RNP_ALGNAME_SHA3_512
        case .ripemd160:
            return RNP_ALGNAME_RIPEMD160
        case .crc24:
            return RNP_ALGNAME_CRC24
        }
    }
}
