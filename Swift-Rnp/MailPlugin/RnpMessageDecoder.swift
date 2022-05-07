//
//  RnpMessageDecoder.swift
//  MailPlugin
//
//  Created by Sergey Vinogradov on 28.03.2022.
//

import Foundation
import MailKit
import MimeParser

final class RnpMessageDecoder {
    
    enum PGPBlocks: String, CaseIterable {
        case pubKeyBegin = "BEGIN PGP PUBLIC KEY BLOCK"
        case pubKeyEnd = "END PGP PUBLIC KEY BLOCK"
        case signBegin = "BEGIN PGP SIGNATURE"
        case signEnd = "END PGP SIGNATURE"
        case encBegin = "BEGIN PGP MESSAGE"
        case encEnd = "END PGP MESSAGE"
    }
    /* https://datatracker.ietf.org/doc/html/rfc4880#section-6.2
    BEGIN PGP PRIVATE KEY BLOCK // Used for armoring private keys.
    
    BEGIN PGP MESSAGE, PART X/Y // Used for multi-part messages, where the armor is split amongst Y
    parts, and this is the Xth part out of Y.
    
    BEGIN PGP MESSAGE, PART X //Used for multi-part messages, where this is the Xth part of an
    unspecified number of parts.  Requires the MESSAGE-ID Armor
    Header to be used.
    */
    
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
        guard let contentType = parsed.header.contentType?.subtype,
              contentType == MimeSubtypes.signed.rawValue ||
                contentType == MimeSubtypes.encrypted.rawValue else { return nil }
        
        // Need to check if we already have keys
        let filters = ["From", "from", "X-Google-Original-From"]
        let senderList = parsed.header.other
            .filter({ filters.contains($0.name) && !$0.body.isEmpty })
            .map { MEEmailAddress(rawString: $0.body) }
        
        // TODO: Think about requirement of any notification with MEDecodedMessageBanner about it
        guard !senderList.isEmpty else { return nil }

        /**
         * In case we don't have the key we should check if it attached to the image.
         * But if after it we still can't find one then it can be related to try checking by wrong key
         */
        // TODO: Inplement validation by "being used" after implement the same functionality in SPM
        var aSender: MEEmailAddress? = RnpMessageDecoder.checkKeyPresentFor(senderList, rnp: rnp)
        if aSender == nil {
            RnpMessageDecoder.checkMimeForKeys(parsed, rnp: rnp)
            
            aSender = RnpMessageDecoder.checkKeyPresentFor(senderList, rnp: rnp)
        }
        
        // TODO: We don't need just bool answer here - we need decrypted message. Checked for signed and encrypted statuses
        guard RnpMessageDecoder.checkMimeForEncodedParts(parsed),
              let sender = aSender else { return nil }
        
        var encoded: String? = message
        var signers: [MEMessageSigner] = [MEMessageSigner(emailAddresses: [sender],
                                                          signatureLabel: sender.rawString,
                                                          context: "Some useful data".data(using: .utf8))]
        var signingError: Error?
        var encryptionError: Error?
        performDecodeMime(parsed, boundary: parsed.header.boundaryParameter, message: &encoded, signers: &signers, signingError: &signingError, encryptionError: &encryptionError)
        
        guard let decodedMessage = encoded,
              !signers.isEmpty else { return nil }
        
        let info = MEMessageSecurityInformation(signers: signers,
                                                isEncrypted: false,
                                                signingError: signingError,
                                                encryptionError: encryptionError)
        
        let decoded =  MEDecodedMessage(data: decodedMessage.data(using: .utf8),
                                        securityInformation: info,
                                        context: "MEDecodedMessage's context. Should be received in custom VC".data(using: .utf8))
        
        return decoded
    }
    
    /// Perform needed operation on message and set message to nil in not-sucessful cases
    ///
    /// - parameter mime: parsed message Mime to analyze & decoding/sign checking
    /// - parameter message: optional **inout** origin message. Will set to nil if we can't decode.
    private func performDecodeMime(_ mime: Mime, boundary: String?, message: inout String?, signers: inout [MEMessageSigner], signingError: inout Error?, encryptionError: inout Error?) {
        switch mime.content {
        case .mixed(let mimesList):
            for item in mimesList {
                self.performDecodeMime(item, boundary: boundary, message: &message, signers: &signers, signingError: &signingError, encryptionError: &encryptionError)
            }
        case .body(let mimeBody):
            print(mimeBody)
            if mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.encBegin.rawValue) != .none,
               mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.encEnd.rawValue) != .none {
                // "This is an OpenPGP/MIME encrypted message (RFC 4880 and 3156)"
                switch rnp.decryptMessage(message: mimeBody.raw) {
                case .success(let decrypted):
                    message = message?.replacingOccurrences(of: mimeBody.raw, with: decrypted)
                case .failure(let error):
                    signers.removeAll()
                    encryptionError = error
                }
            } else if mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.signBegin.rawValue) != .none,
                      mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.signEnd.rawValue) != .none,
                      var signed = RnpMessageDecoder.extractInboundariedString(boundary, string: message) {
                
                signed = signed
                    .replacingOccurrences(of: "\n", with: "\r\n")// LF -> CRLF
                switch rnp.verifyMessageString(signed,
                                               detachedSign: mimeBody.raw) {
                case .success(): break
                    // TODO: As soon as we just check if plain text signed with the right person, then no need eny decode. But anyway possible to clear any signed-related content
                    /*
                    guard let parsed = try? MimeParser().parse(signed) else { return }
                    message = RnpMessageDecoder.plainTextFrom(parsed)
                     */
                case .failure(let error):
                    signers.removeAll()
                    signingError = error
                }
            }
        case .alternative(let mimeList):
            print("curious")
        }
    }
}

/// Static private methods
extension RnpMessageDecoder {
    
    static private func checkMimeForKeys(_ mime: Mime, rnp: RnpFacade) {
        switch mime.content {
        case .mixed(let mimesList):
            for item in mimesList {
                self.checkMimeForKeys(item, rnp: rnp)
            }
        case .body(let mimeBody):
            // Assume mimeBody.encoding == MimeParser.ContentTransferEncoding.quotedPrintable
            guard mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.pubKeyBegin.rawValue) != .none,
                  mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.pubKeyEnd.rawValue) != .none else { return }
            let filename = RnpMessageDecoder.checkMimeForFilename(mime)
            var keyString = mimeBody.raw
            switch mime.header.contentTransferEncoding {
            case .quotedPrintable:
                keyString = QuotedPrintable.decode(string: keyString)
            default: break
            }
            rnp.importKeyString(keyString, filename: filename)
        case .alternative(let mimeList):
            print("curious")
        }
    }
    
    /// Return yes if mime has encoded parts
    @discardableResult
    static private func checkMimeForEncodedParts(_ mime: Mime) -> Bool {
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
               (mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.encBegin.rawValue) != .none &&
                mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.encEnd.rawValue) != .none ||
                mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.signBegin.rawValue) != .none &&
                mimeBody.raw.range(of: RnpMessageDecoder.PGPBlocks.signEnd.rawValue) != .none) {
                result = true
            }
        case .alternative(let mimeList):
            print("curious")
        }
        return result
    }
    
    /// Usually, the pgp client add exactly raw string as user id
    static private func checkKeyPresentFor(_ mailAddreses: [MEEmailAddress], rnp: RnpFacade) -> MEEmailAddress? {
        var result: MEEmailAddress?
        for item in mailAddreses {
            if rnp.checkKeyPresenceFor(item.rawString) {
                result = item
                break
            } else if let email = item.addressString,
                      rnp.checkKeyPresenceFor(email) {
                result = item
                break
            }
        }
        return result
    }
    
    /// Check header for filename
    static private func checkMimeForFilename(_ mime: Mime) -> String? {
        guard let disp = mime.header.contentDisposition,
              let filename = disp.filename else { return nil }
        return filename
    }
    
    static private func extractInboundariedString(_ boudary: String?, string: String?) -> String? {
        guard let theBoundary = boudary,
              let body = string,
              let begin = body.range(of: "--" + theBoundary) else { return nil }
        var result = body.suffix(from: begin.upperBound)
        if result.hasPrefix("\n") {
            result = result.suffix(result.count - 1)
        }

        guard let end = result.range(of: "--" + theBoundary) else { return nil }
        result = result.prefix(upTo: end.lowerBound)
        if result.hasSuffix("\n") {
            result = result.prefix(result.count - 1)
        }
        
        return String(result)
    }
    
    static private func plainTextFrom(_ mime: Mime) -> String? {
        var result: String?
        switch mime.content {
        case .mixed(let mimesList):
            for item in mimesList {
                result = RnpMessageDecoder.plainTextFrom(item)
                if result != nil { break }
            }
        case .body(let mimeBody):
            guard mime.header.contentType?.type ==  "text",
                  mime.header.contentType?.subtype == "plain" else { return nil }
            
            let body = mimeBody.raw
            switch mimeBody.encoding {
            case .base64:
                guard let decodedData = Data(base64Encoded: body),
                      let decodedString = String(data: decodedData, encoding: .utf8) else { return nil }
                    
                return decodedString
            default:
                break
            }
        case .alternative(let mimeList):
            print("curious")
        }
        
        return result
    }
}

extension MimeHeader {
    var boundaryParameter: String? {
        guard let contentType = self.contentType else { return nil }
        
        var result: String?
        for (key, value) in contentType.parameters {
            guard key == "boundary" else { continue }
            result = value
            break
        }
        
        return result
    }
}
