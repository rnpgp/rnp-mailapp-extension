//
//  KeyDescriptionGenerator.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 24.12.2021.
//

import Foundation

@objc public
enum KeyExpiration: Int {
    case halfYear = 15768000
    case year = 31536000
}

private enum KeyUsage: String {
    case sign
    case encrypt
}

extension KeyExpiration: RawRepresentable {
    public typealias RawValue = Int
}

private struct KeyDescription: Encodable {
    let primary, sub: KeyDescriptionPart
}

private struct KeyDescriptionPart: Encodable {
    let type: String
    let length: Int?
    let userid: String?
    let curve: String?
    let expiration: Int
    let usage: [String]
    let protection: Protection
}

private struct Protection: Encodable {
    let cipher, hash: String
}

@objc public
class KeyDescriptionGenerator: NSObject {
    @objc public
    static func rsaKey(userId: String, expiration: KeyExpiration) -> String? {
        let protection = Protection(cipher: RnpAlgorythm.aes256.rawValue,
                                    hash: RnpAlgorythm.sha256.rawValue)
        
        let rsaLength = 2048
        let primary = KeyDescriptionPart(type: RnpAlgorythm.rsa.rawValue,
                                         length: rsaLength,
                                         userid: userId,
                                         curve: nil,
                                         expiration: expiration.rawValue,
                                         usage: [KeyUsage.sign.rawValue],
                                         protection: protection)
        
        let secondary = KeyDescriptionPart(type: RnpAlgorythm.rsa.rawValue,
                                           length: rsaLength,
                                           userid: nil,
                                           curve: nil,
                                           expiration: expiration.rawValue,
                                           usage: [KeyUsage.encrypt.rawValue],
                                           protection: protection)
        

        let keyDesc = KeyDescription(primary: primary,
                                     sub: secondary)
        guard let jsonData = try? JSONEncoder().encode(keyDesc),
              let result = String(data: jsonData, encoding: .utf8) else { return nil }
        
        return result
    }
    
    @objc public
    static func curve25519Key(userId: String, expiration: KeyExpiration) -> String? {
        let protection = Protection(cipher: RnpAlgorythm.aes256.rawValue,
                                    hash: RnpAlgorythm.sha256.rawValue)
        
        let primary = KeyDescriptionPart(type: RnpAlgorythm.eddsa.rawValue,
                                         length: nil,
                                         userid: userId,
                                         curve: nil,
                                         expiration: 0,
                                         usage: [KeyUsage.sign.rawValue],
                                         protection: protection)
        
        let secondary = KeyDescriptionPart(type: RnpAlgorythm.ecdh.rawValue,
                                           length: nil,
                                           userid: nil,
                                           curve: "Curve25519",
                                           expiration: expiration.rawValue,
                                           usage: [KeyUsage.encrypt.rawValue],
                                           protection: protection)
        
        
        let keyDesc = KeyDescription(primary: primary,
                                     sub: secondary)
        guard let jsonData = try? JSONEncoder().encode(keyDesc),
              var result = String(data: jsonData, encoding: .utf8) else { return nil }
        
        result = result.replacingOccurrences(of: "\"", with: "'")
        return result
    }
}
