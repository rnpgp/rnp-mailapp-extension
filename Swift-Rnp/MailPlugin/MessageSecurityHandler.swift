//
//  MessageSecurityHandler.swift
//  MailPlugin
//
//  Thin MailKit adapter: all OpenPGP and MIME work lives in the
//  MailSecurityEngine Swift package; this class only translates between
//  MailKit types and engine types.
//

import Foundation
import MailKit
import MailSecurityEngine
import Rnp

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {

    /// Context attached to each `MEMessageSigner` so the extension view
    /// controller can look up trust state without re-running verification.
    struct SignerContext: Codable {
        let fingerprint: String?
        let status: String
    }

    static let shared = MessageSecurityHandler()

    private let engine: MailSecurityEngine

    override init() {
        engine = MessageSecurityHandler.makeEngine()
        super.init()
    }

    /// Engine on the shared keyring directory, with passphrases from the
    /// Keychain. Falls back to a temporary directory when the keyring is
    /// unavailable, so the extension can never fail to launch.
    private static func makeEngine() -> MailSecurityEngine {
        let provider: (String) -> String? = { _ in KeychainPassphraseStore.sharedPassphrase() }
        if let engine = try? MailSecurityEngine(
            directory: AppGroup.keyringDirectory(),
            passphraseProvider: provider
        ) {
            return engine
        }
        // The keyring directory could not be read; degrade to an empty
        // in-memory keyring rather than crashing the extension.
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-mail-extension-fallback")
        return (try? MailSecurityEngine(
            directory: fallback,
            passphraseProvider: provider
        ))!
    }

    // MARK: - Encoding Messages

    func getEncodingStatus(for message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void) {
        let status = (try? engine.encodingStatus(
            sender: message.fromAddress.rawString,
            recipients: message.allRecipientAddresses.map(\.rawString)
        )) ?? EncodingStatus(canSign: false, canEncrypt: false, missingRecipientKeys: [])
        completionHandler(MEOutgoingMessageEncodingStatus(
            canSign: status.canSign,
            canEncrypt: status.canEncrypt,
            securityError: nil,
            addressesFailingEncryption: status.missingRecipientKeys.map { MEEmailAddress(rawString: $0) }
        ))
    }

    func encode(_ message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEMessageEncodingResult) -> Void) {
        let noEncoding = MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)

        // Only act on messages being sent that the user asked to protect.
        guard message.state == .sending,
              composeContext.shouldSign || composeContext.shouldEncrypt,
              let rawData = message.rawData
        else {
            completionHandler(noEncoding)
            return
        }

        let request = EncodingRequest(
            message: rawData,
            sender: message.fromAddress.rawString,
            recipients: message.allRecipientAddresses.map(\.rawString),
            sign: composeContext.shouldSign,
            encrypt: composeContext.shouldEncrypt
        )
        do {
            let encoded = try engine.encode(request)
            let outgoing = MEEncodedOutgoingMessage(
                rawData: encoded.rawData,
                isSigned: encoded.isSigned,
                isEncrypted: encoded.isEncrypted
            )
            completionHandler(MEMessageEncodingResult(
                encodedMessage: outgoing,
                signingError: nil,
                encryptionError: nil
            ))
        } catch {
            // Attribute the failure to the side Mail should blame: key
            // resolution errors map to their natural side, crypto failures
            // to the requested operation.
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
            completionHandler(MEMessageEncodingResult(
                encodedMessage: nil,
                signingError: signingError,
                encryptionError: encryptionError
            ))
        }
    }

    // MARK: - Decoding Messages

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        guard let decoded = try? engine.decode(data) else {
            // No OpenPGP content: Mail displays the message untouched.
            return nil
        }
        let signers = decoded.security.signers.map { signer in
            let context = SignerContext(
                fingerprint: signer.fingerprint,
                status: signer.status.rawValue
            )
            let contextData = (try? JSONEncoder().encode(context)) ?? Data()
            return MEMessageSigner(
                emailAddresses: signer.userID.map { [MEEmailAddress(rawString: $0)] } ?? [],
                signatureLabel: signer.userID ?? signer.fingerprint ?? "Unknown signer",
                context: contextData
            )
        }
        let information = MEMessageSecurityInformation(
            signers: signers,
            isEncrypted: decoded.security.isEncrypted,
            signingError: decoded.security.signingError,
            encryptionError: decoded.security.encryptionError
        )
        return MEDecodedMessage(
            data: decoded.data,
            securityInformation: information,
            context: nil
        )
    }

    // MARK: - Displaying Security Information

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? {
        let contexts: [SignerContext?] = messageSigners.map { signer in
            guard !signer.context.isEmpty else { return nil }
            return try? JSONDecoder().decode(SignerContext.self, from: signer.context)
        }
        return MessageSecurityViewController(
            signers: messageSigners,
            contexts: contexts,
            trustStore: engine.keyManager.trustStore
        )
    }

    // MARK: - Displaying Additional Context

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? {
        nil
    }

    func primaryActionClicked(forMessageContext context: Data, completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        completionHandler(nil)
    }
}
