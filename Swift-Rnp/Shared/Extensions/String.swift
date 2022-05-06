//
//  String.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 10.04.2022.
//

import Foundation

extension String {
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    var qpDecoded: String {
        enum CharType {
            case text, equal, special(firstChar: UInt8)
        }
        
        func alignedChar(char: UInt8) -> UInt8 {
            if char < 58 {
                return char - 48
            } else if char < 71 {
                return char - 55
            } else {
                return char - 87
            }
        }
        
        var result = ""
        var type: CharType = .text
        var uScal: Unicode.Scalar = Unicode.Scalar(182)!
        for item in self.compactMap({ $0.asciiValue }) {
            switch type {
            case .text:
                switch item {
                case 61:
                    type = .equal
                    continue
                    
                default:
                    type = .text
                    uScal = UnicodeScalar(item)
                }
            case .equal:
                switch item {
                case 10:
                    type = .text
                    continue
                case 13:
                    type = .equal // one more time
                    continue
                case 48...57, //0...9
                    97...102, //a...f
                    65...70:  //A...F
                    type = .special(firstChar: item)
                    continue
                default:
                    type = .text
                    uScal = UnicodeScalar(item)
                }
            case .special(let first):
                type = .text
                uScal = UnicodeScalar(alignedChar(char: first) << 4 + alignedChar(char: item))
            }
            
            result.unicodeScalars.append(uScal)
        }
        
        return result
    }
}
