//
//  MessageSecurityCore.swift
//  swift-rnp
//
//  MailKit-independent core of the message-security handler. All OpenPGP and
//  MIME work is delegated to MailSecurityEngine; this type only translates
//  between the handler's protocol abstractions and engine types.
//

import Foundation
import TrustStore

/// MailKit-independent message-security handler.
public final class MessageSecurityCore {
    private let engine: MailSecurityEngine

    public init(engine: MailSecurityEngine) {
        self.engine = engine
    }

    /// Trust store used by the view layer to look up per-signer trust.
    public var trustStore: TrustStore {
        engine.keyManager.trustStore
    }

    // MARK: - Encoding

    public func getEncodingStatus(
        for message: MailMessage,
        composeContext: MailComposeContext
    ) -> HandlerEncodingStatus {
        let status = (try? engine.encodingStatus(
            sender: message.fromAddress,
            recipients: message.recipientAddresses
        )) ?? EncodingStatus(canSign: false, canEncrypt: false, missingRecipientKeys: [])

        return HandlerEncodingStatus(
            canSign: status.canSign,
            canEncrypt: status.canEncrypt,
            securityError: nil,
            addressesFailingEncryption: status.missingRecipientKeys
        )
    }

    public func encode(
        _ message: MailMessage,
        composeContext: MailComposeContext
    ) -> HandlerEncodingResult {
        let noEncoding = HandlerEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)

        guard message.isSending,
              composeContext.shouldSign || composeContext.shouldEncrypt,
              let rawData = message.rawData
        else {
            return noEncoding
        }

        let request = EncodingRequest(
            message: rawData,
            sender: message.fromAddress,
            recipients: message.recipientAddresses,
            sign: composeContext.shouldSign,
            encrypt: composeContext.shouldEncrypt
        )
        do {
            let encoded = try engine.encode(request)
            let outgoing = HandlerEncodedMessage(
                rawData: encoded.rawData,
                isSigned: encoded.isSigned,
                isEncrypted: encoded.isEncrypted
            )
            return HandlerEncodingResult(encodedMessage: outgoing, signingError: nil, encryptionError: nil)
        } catch {
            var signingError: Error?
            var encryptionError: Error?
            switch error {
            case MailSecurityError.noSecretKeyForSender:
                signingError = error
            case MailSecurityError.missingRecipientKeys:
                encryptionError = error
            default:
                if composeContext.shouldEncrypt {
                    encryptionError = error
                } else {
                    signingError = error
                }
            }
            return HandlerEncodingResult(encodedMessage: nil, signingError: signingError, encryptionError: encryptionError)
        }
    }

    // MARK: - Decoding

    public func decodedMessage(forMessageData data: Data) -> HandlerDecodedMessage? {
        guard let decoded = try? engine.decode(data) else {
            return nil
        }
        let signers = decoded.security.signers.map { signer in
            let context = SignerContext(
                fingerprint: signer.fingerprint,
                status: signer.status.rawValue
            )
            let contextData = (try? JSONEncoder().encode(context)) ?? Data()
            return HandlerSignerInfo(
                emailAddresses: signer.userID.map { [$0] } ?? [],
                signatureLabel: signer.userID ?? signer.fingerprint ?? "Unknown signer",
                context: contextData
            )
        }
        let information = HandlerSecurityInformation(
            signers: signers,
            isEncrypted: decoded.security.isEncrypted,
            signingError: decoded.security.signingError,
            encryptionError: decoded.security.encryptionError
        )
        return HandlerDecodedMessage(data: decoded.data, securityInformation: information)
    }

    // MARK: - Signer context

    /// Decodes the `SignerContext` attached to a signer, if present.
    public func signerContext(for signer: MailMessageSigner) -> SignerContext? {
        guard !signer.context.isEmpty else { return nil }
        return try? JSONDecoder().decode(SignerContext.self, from: signer.context)
    }
}
