//
//  RnpMessageEncoder.swift
//  MailPlugin
//
//  Created by Sergey Vinogradov on 08.04.2022.
//

import Foundation
import MailKit

final class RnpMessageEncoder {
    private var rnp: RnpFacade
    
    init(rnp: RnpFacade) {
        self.rnp = rnp
    }
    
    func encodingStatus(for message: MEMessage, composeContext: MEComposeContext) -> MEOutgoingMessageEncodingStatus {
        /// In case if `MEOutgoingMessageEncodingStatus` contains non-nil `securityError` then Mail will show SFCertificateView without any details.
        // TODO: fix empty presentation of SFCertificateTrustPanel. Possibly work aroud built-in MacOS keyring
        
        var canSign = rnp.hasKeys
        if !canSign {
            // Here we create the key to sign with static password
            let userId = message.fromAddress.rawString
            switch rnp.createKeys(userId: userId, password: rnp.password) {
            case .success():
                canSign = rnp.hasKeys
            case .failure(_):
                // error eliminated bacause of top described issue
                return MEOutgoingMessageEncodingStatus(canSign: false,
                                                       canEncrypt: false,
                                                       securityError: nil,
                                                       addressesFailingEncryption: [])
            }
        }
        
        // FIXME: return filtering, possible we should try encode right after import and in success case we can receive key's userId on performing encode_op
        /*
        let invalidRecipients = message.allRecipientAddresses.filter({ address in
            guard let email = address.addressString else { return true }
            return !rnp.checkKeyPresenceFor(email)
        })
        
        guard invalidRecipients.isEmpty else {
            // error eliminated bacause of top described issue
            /*let error = MessageSecurityError.missedPublicKeysEmails(emailAdresses: invalidRecipients)*/
            return MEOutgoingMessageEncodingStatus(canSign: false,
                                                   canEncrypt: false,
                                                   securityError: nil,
                                                   addressesFailingEncryption: [])
        }
        */
        return MEOutgoingMessageEncodingStatus(canSign: canSign,
                                               canEncrypt: true,
                                               securityError: nil,
                                               addressesFailingEncryption: [])
    }
    
    func encode(_ message: MEMessage, composeContext: MEComposeContext) -> MEMessageEncodingResult {
        let defaultResult = MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
        
        /// Let encrypt only messages which ready to send but not encrypted yet
        guard message.state == .sending,
              message.encryptionState != .encrypted else { return defaultResult }
        
        // If message don't require sign or/and encrypt then we shouldn't perform any operation
        guard composeContext.shouldSign || composeContext.shouldEncrypt else { return defaultResult }
        
        var signedEncryptedData: Data?
        let userId = message.fromAddress.rawString
        
        // If we encrypt then sign - anyone can verify the sign but only recipient can decode.
        // Opposite sign then encrypt - only recipient can decrypt and after can validate the sign.
        var isSigned = false
        var signingError: Error?
        if composeContext.shouldSign,
           let data = message.rawData {
            switch rnp.signMessageData(data, userId: userId) {
            case .success(let signed):
                signedEncryptedData = signed
                isSigned = true
            case .failure(let error):
                signingError = error
#if DEBUG
                let errorCase = RnpFacade.errorCodeCase(error: error as NSError)
                print(errorCase)
#endif
            }
        }
        
// FIXME: Here we should check key's presence (as we did it on decoder)
        
        var isEncrypted = false
        var encryptionError: Error?
        if composeContext.shouldEncrypt,
           let data = composeContext.shouldSign ? signedEncryptedData : message.rawData {
            switch rnp.encryptMessageData(data, userId: userId, password: nil) {
            case .success(let encrypted):
                signedEncryptedData = encrypted
                isEncrypted = true
            case .failure(let error):
                encryptionError = error
#if DEBUG
                let errorCase = RnpFacade.errorCodeCase(error: error as NSError)
                print(errorCase)
#endif
            }
        }
        
        var encodedMessage: MEEncodedOutgoingMessage?
        if let rawData = signedEncryptedData {
            encodedMessage = MEEncodedOutgoingMessage(rawData: rawData,
                                                          isSigned: isSigned,
                                                          isEncrypted: isEncrypted)
        }
        
        let result = MEMessageEncodingResult(encodedMessage: encodedMessage,
                                             signingError: signingError,
                                             encryptionError: encryptionError)
        
        return result
    }
}
