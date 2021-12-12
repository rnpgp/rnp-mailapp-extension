//
//  KeyFile.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import Foundation

struct KeyFile: Identifiable {
    let id = UUID()
    let filename: String
    let isPublic: Bool
}

extension KeyFile {
    static var mock: [KeyFile] {
        [
            KeyFile(filename: "pubring.gpg", isPublic: true),
            KeyFile(filename: "secring.gpg", isPublic: false)
        ]
    }
}
