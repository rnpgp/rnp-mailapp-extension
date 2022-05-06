//
//  MessageSecurityError.swift
//  MailPlugin
//
//  Created by Sergey Vinogradov on 08.04.2022.
//

import Foundation
import MailKit

enum MessageSecurityError: Error {
    case missedPublicKeysEmails(emailAdresses: [MEEmailAddress])
    case noEncodableData
    case parserFails
    
    var errorReason: String {
        switch self {
        case .missedPublicKeysEmails(let emailAdresses):
            return "Missed keys for emails.\n\(emailAdresses.map { $0.rawString })"
        case .noEncodableData:
            return "No encodable data found."
        case .parserFails:
            return "Message can't being parsed"
        }
    }
}
