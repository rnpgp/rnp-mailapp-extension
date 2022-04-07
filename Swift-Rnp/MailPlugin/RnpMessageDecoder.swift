//
//  RnpMessageDecoder.swift
//  MailPlugin
//
//  Created by Sergey Vinogradov on 28.03.2022.
//

import Foundation
import MailKit
import MimeParser

enum MessageSecurityError: Error {
    case unverifiedEmails(emailAdresses: [MEEmailAddress])
    case noEncodableData
    case parserFails
    
    var errorReason: String {
        switch self {
        case .unverifiedEmails(let emailAdresses):
            return "Invalid email addresses detected.\n\(emailAdresses.map { $0.rawString })"
        case .noEncodableData:
            return "No encodable data found."
        case .parserFails:
            return "Message can't being parsed"
        }
    }
}

final class RnpMessageDecoder {
    
    enum PGPBlocks: String, CaseIterable {
        case pubKeyBegin = "BEGIN PGP PUBLIC KEY BLOCK"
        case pubKeyEnd = "END PGP PUBLIC KEY BLOCK"
        case signBegin = "BEGIN PGP SIGNATURE"
        case signEnd = "END PGP SIGNATURE"
        case encBegin = "BEGIN PGP MESSAGE"
        case encEnd = "END PGP MESSAGE"
    }
    
    enum MimeSubtypes: String {
        case signed = "signed"
        case encrypted = "encrypted"
        case keys = "pgp-keys"
    }
    
    private var rnp: RnpFacade
    
    init(rnp: RnpFacade) {
        self.rnp = rnp
    }
    
    func decodedMessage(from data: Data) -> MEDecodedMessage? {
        let message = String(decoding: data, as: UTF8.self)
        
        /// Here we give one more chance to parse raw RFC 822/2045/2046
        guard let parsed = try? MimeParser().parse(message) else {
            // For case when we want to block second check for parse
            /*
             let error = MessageSecurityError.parserFails
             let info = MEMessageSecurityInformation(signers: [], isEncrypted: false, signingError: nil, encryptionError: error)
             let banner = MEDecodedMessageBanner(title: error.errorReason, primaryActionTitle: "Ok", dismissable: false)
             return MEDecodedMessage(data: nil, securityInformation: info, context: nil, banner: banner)
             */
            return nil
        }
        
        // Check if message is signed or encrypted
        // FIXME: Add check for public keys here and return nil as fast as we can
        guard let contentType = parsed.header.contentType,
              contentType.subtype == MimeSubtypes.signed.rawValue ||
                contentType.subtype == MimeSubtypes.encrypted.rawValue else {
                  
                  return nil
}
        
        // Need to check if we already have keys
        let senderList = parsed.header.other.filter({ $0.name == "From" || $0.name == "from" })
        
        // TODO: Think about requirement of any notification with MEDecodedMessageBanner about it
        guard !senderList.isEmpty,
              !senderList[0].body.isEmpty else { return nil }
        let sender = MEEmailAddress(rawString: senderList[0].body)
        
        // Usually, the pgp client add exactly raw string as user id
        func checkKeyPresentFor(_ mailAddress: MEEmailAddress) -> Bool {
            var result = rnp.checkKeyPresenceFor(mailAddress.rawString)
            if !result, let email = mailAddress.addressString {
                result = rnp.checkKeyPresenceFor(email)
            }
            return result
        }

        // In case we don't have the key we should check if it attached to the image
        var haveKeys = checkKeyPresentFor(sender)
        if !haveKeys {
            checkMimeForKeys(parsed)
            
            haveKeys = checkKeyPresentFor(sender)
        }
        
        // We can't decode it
        guard haveKeys else {
            let encrypted = contentType.subtype == "encrypted"
            let error = MessageSecurityError.unverifiedEmails(emailAdresses: [sender])
            // FIXME: In case if message signed then we should show signers without key stored locally
            let info = MEMessageSecurityInformation(signers: [], isEncrypted: encrypted, signingError: nil, encryptionError: error)
                // it show banner only if data is nil
            let banner = MEDecodedMessageBanner(title: error.errorReason, primaryActionTitle: "Ok", dismissable: false)
            return MEDecodedMessage(data: encrypted ? nil : data, securityInformation: info, context: nil, banner: banner)
        }
        
        // TODO: We don't need just bool answer here - we need decrypted message. Checked for signed and encrypted statuses
        guard checkMimeForEncodedParts(parsed) else { return nil }
        
        let signed = false
        var signers = [MEMessageSigner]()
        if signed {
                // TODO: possible to have more than one signer
            let signer = MEMessageSigner(emailAddresses: [sender],
                                         signatureLabel: sender.rawString,
                                         context: nil)
            signers.append(signer)
        }
        
        let info = MEMessageSecurityInformation( signers: signers,
                                                 isEncrypted: false,
                                                 signingError: nil,
                                                 encryptionError: nil)
        
        let decoded =  MEDecodedMessage(data: data,
                                        securityInformation: info,
                                        context: nil)
        
        return decoded
    }
    
    private func checkMimeForKeys(_ mime: Mime) {
        switch mime.content {
        case .mixed(let mimesList):
            for item in mimesList {
                self.checkMimeForKeys(item)
            }
        case .body(let mimeBody):
            // Assume mimeBody.encoding == MimeParser.ContentTransferEncoding.quotedPrintable
            guard mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.pubKeyBegin.rawValue) != .none,
                  mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.pubKeyEnd.rawValue) != .none else { return }
            rnp.importKeyString(mimeBody.raw)
        case .alternative(let mimeList):
            print("curious")
        }
    }
    
    /// Return yes if mime has encoded parts
    @discardableResult
    private func checkMimeForEncodedParts(_ mime: Mime) -> Bool {
        var result = false
        switch mime.content {
        case .mixed(let mimesList):
            for item in mimesList {
                result = self.checkMimeForEncodedParts(item)
                if result {
                    break
                }
            }
        case .body(let mimeBody):
            if !result,
               mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.encBegin.rawValue) != .none,
               mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.encEnd.rawValue) != .none {
                result = true
            }
        case .alternative(let mimeList):
            print("curious")
        }
        return result
    }
}
