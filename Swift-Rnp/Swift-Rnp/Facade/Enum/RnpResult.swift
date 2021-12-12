//
//  RnpResult.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 02.12.2021.
//

import Foundation

enum RnpResult: Int, CaseIterable {
    case success
    
    /* Common error codes */
    case errorGeneric
    case errorBadFormat
    case errorBadParameters
    case errorNotImplemented
    case errorNotSupported
    case errorOutOfMemory
    case errorShortBuffer
    case errorNullPointer
    
    /* Storage */
    case errorStorageAccess
    case errorStorageRead
    case errorStorageWrite
    
    /* Crypto */
    case errorCryptoBadState
    case errorCryptoMacInvalid
    case errorCryptoSignatureInvalid
    case errorCryptoKeyGeneration
    case errorCryptoBadPassword
    case errorCryptoKeyNotFound
    case errorCryptoNoSuitableKey
    case errorCryptoDecryptFailed
    case errorCryptoRng
    case errorCryptoSigningFailed
    case errorCryptoNoSignaturesFound
    
    case errorCryptoSignatureExpired
    case errorCryptoVerificationFailed
    
    /* Parsing */
    case errorParsingNotEnoughData
    case errorParsingUnknownTag
    case errorParsingPacketNotConsumed
    case errorParsingNoUsedId
    case errorParsingEof
    
    var rawValue: Int {
        switch self {
        case .success:
            return RNP_SUCCESS
            
            /* Common error codes */
        case .errorGeneric:
            return RNP_ERROR_GENERIC
        case .errorBadFormat:
            return RNP_ERROR_BAD_FORMAT
        case .errorBadParameters:
            return RNP_ERROR_BAD_PARAMETERS
        case .errorNotImplemented:
            return RNP_ERROR_NOT_IMPLEMENTED
        case .errorNotSupported:
            return RNP_ERROR_NOT_SUPPORTED
        case .errorOutOfMemory:
            return RNP_ERROR_OUT_OF_MEMORY
        case .errorShortBuffer:
            return RNP_ERROR_SHORT_BUFFER
        case .errorNullPointer:
            return RNP_ERROR_NULL_POINTER
            
            /* Storage */
        case .errorStorageAccess:
            return RNP_ERROR_ACCESS
        case .errorStorageRead:
            return RNP_ERROR_READ
        case .errorStorageWrite:
            return RNP_ERROR_WRITE
            
            /* Crypto */
        case .errorCryptoBadState:
            return RNP_ERROR_BAD_STATE
        case .errorCryptoMacInvalid:
            return RNP_ERROR_MAC_INVALID
        case .errorCryptoSignatureInvalid:
            return RNP_ERROR_SIGNATURE_INVALID
        case .errorCryptoKeyGeneration:
            return RNP_ERROR_KEY_GENERATION
        case .errorCryptoBadPassword:
            return RNP_ERROR_BAD_PASSWORD
        case .errorCryptoKeyNotFound:
            return RNP_ERROR_KEY_NOT_FOUND
        case .errorCryptoNoSuitableKey:
            return RNP_ERROR_NO_SUITABLE_KEY
        case .errorCryptoDecryptFailed:
            return RNP_ERROR_DECRYPT_FAILED
        case .errorCryptoRng:
            return RNP_ERROR_RNG
        case .errorCryptoSigningFailed:
            return RNP_ERROR_SIGNING_FAILED
        case .errorCryptoNoSignaturesFound:
            return RNP_ERROR_NO_SIGNATURES_FOUND
            
        case .errorCryptoSignatureExpired:
            return RNP_ERROR_SIGNATURE_EXPIRED
        case .errorCryptoVerificationFailed:
            return RNP_ERROR_VERIFICATION_FAILED
            
            /* Parsing */
        case .errorParsingNotEnoughData:
            return RNP_ERROR_NOT_ENOUGH_DATA
        case .errorParsingUnknownTag:
            return RNP_ERROR_UNKNOWN_TAG
        case .errorParsingPacketNotConsumed:
            return RNP_ERROR_PACKET_NOT_CONSUMED
        case .errorParsingNoUsedId:
            return RNP_ERROR_NO_USERID
        case .errorParsingEof:
            return RNP_ERROR_EOF
        }
    }
}
