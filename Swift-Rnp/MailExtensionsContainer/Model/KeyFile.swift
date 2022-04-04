//
//  KeyFile.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation

struct KeyFile: Identifiable {
    let id = UUID()
    let userId: String
    let filename: String
    let isPublic: Bool
}

extension KeyFile {
    static var mock: [KeyFile] {
        [
            KeyFile(userId: "john@doe.com", filename: "pubring.gpg", isPublic: true),
            KeyFile(userId: "ben@appleseed.com", filename: "secring.gpg", isPublic: false)
        ]
    }
}
