//
//  MessageSecurityHandler.swift
//  MailPlugin
//
//  Thin MailKit adapter: all OpenPGP and MIME work lives in the
//  MailSecurityEngine Swift package; this class only translates between
//  MailKit types and the package's protocol abstractions.
//

import Foundation
import MailKit
import MailSecurityEngine
import MailSecurityUI
import Rnp

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {

    static let shared = MessageSecurityHandler()

    private let core: MessageSecurityCore?

    override init() {
        core = MessageSecurityHandler.makeCore()
        super.init()
    }

    /// Engine on the shared keyring directory, with passphrases from the
    /// Keychain. Returns `nil` when the keyring is unavailable so the
    /// extension can still launch and degrade gracefully.
    private static func makeCore() -> MessageSecurityCore? {
        let provider: (String) -> String? = { _ in KeychainPassphraseStore.sharedPassphrase() }
        let stateRecorder = SecurityStateRecorder(directory: AppGroup.extensionStateDirectory())
        if let engine = try? MailSecurityEngine(
            directory: AppGroup.keyringDirectory(),
            passphraseProvider: provider
        ) {
            return MessageSecurityCore(engine: engine, stateRecorder: stateRecorder)
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-mail-extension-fallback")
        guard let engine = try? MailSecurityEngine(
            directory: fallback,
            passphraseProvider: provider
        ) else {
            return nil
        }
        return MessageSecurityCore(engine: engine, stateRecorder: stateRecorder)
    }

    // MARK: - Encoding Messages

    func getEncodingStatus(for message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void) {
        guard let core = core else {
            completionHandler(MEOutgoingMessageEncodingStatus(
                canSign: false,
                canEncrypt: false,
                securityError: nil,
                addressesFailingEncryption: []
            ))
            return
        }
        let status = core.getEncodingStatus(
            for: MailKitMessage(message),
            composeContext: MailKitComposeContext(composeContext)
        )
        completionHandler(MEOutgoingMessageEncodingStatus(
            canSign: status.canSign,
            canEncrypt: status.canEncrypt,
            securityError: status.securityError,
            addressesFailingEncryption: status.addressesFailingEncryption.map { MEEmailAddress(rawString: $0) }
        ))
    }

    func encode(_ message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEMessageEncodingResult) -> Void) {
        guard let core = core else {
            completionHandler(MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil))
            return
        }
        let result = core.encode(
            MailKitMessage(message),
            composeContext: MailKitComposeContext(composeContext)
        )
        let outgoing = result.encodedMessage.map {
            MEEncodedOutgoingMessage(
                rawData: $0.rawData,
                isSigned: $0.isSigned,
                isEncrypted: $0.isEncrypted
            )
        }
        completionHandler(MEMessageEncodingResult(
            encodedMessage: outgoing,
            signingError: result.signingError,
            encryptionError: result.encryptionError
        ))
    }

    // MARK: - Decoding Messages

    /// Encryption status of the most recently decoded OpenPGP message.
    ///
    /// MailKit's `extensionViewController(signers:)` receives no encryption
    /// state, and signer contexts only exist for signed messages. For
    /// encrypted-but-unsigned messages the banner falls back to the status
    /// recorded here at decode time (Mail always decodes a message before it
    /// can show its security indicator).
    private var lastDecodedEncryption: (isEncrypted: Bool, errorDescription: String?)?
    private let lastDecodedEncryptionLock = NSLock()

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        guard let core = core, let decoded = core.decodedMessage(forMessageData: data) else {
            return nil
        }
        lastDecodedEncryptionLock.lock()
        lastDecodedEncryption = (
            decoded.securityInformation.isEncrypted,
            decoded.securityInformation.encryptionError?.localizedDescription
        )
        lastDecodedEncryptionLock.unlock()
        let signers = decoded.securityInformation.signers.map { info in
            MEMessageSigner(
                emailAddresses: info.emailAddresses.map { MEEmailAddress(rawString: $0) },
                signatureLabel: info.signatureLabel,
                context: info.context
            )
        }
        let information = MEMessageSecurityInformation(
            signers: signers,
            isEncrypted: decoded.securityInformation.isEncrypted,
            signingError: decoded.securityInformation.signingError,
            encryptionError: decoded.securityInformation.encryptionError
        )
        return MEDecodedMessage(
            data: decoded.data,
            securityInformation: information,
            context: nil
        )
    }

    // MARK: - Displaying Security Information

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? {
        guard let core = core else {
            return nil
        }
        let contexts: [SignerContext?] = messageSigners.map { signer in
            core.signerContext(for: MailKitSigner(signer))
        }
        return MessageSecurityViewController(
            signers: messageSigners,
            contexts: contexts,
            trustStore: core.trustStore,
            encryption: encryptionInfo(for: contexts)
        )
    }

    /// Encryption status for the banner: prefer the per-message value carried
    /// in the signer contexts; fall back to the most recent decode for
    /// encrypted messages without signers.
    private func encryptionInfo(for contexts: [SignerContext?]) -> MailSecurityBannerView.EncryptionInfo? {
        if let context = contexts.lazy.compactMap({ $0 }).first, let isEncrypted = context.isEncrypted {
            return MailSecurityBannerView.EncryptionInfo(
                isEncrypted: isEncrypted,
                errorDescription: context.encryptionError
            )
        }
        lastDecodedEncryptionLock.lock()
        defer { lastDecodedEncryptionLock.unlock() }
        return lastDecodedEncryption.map {
            MailSecurityBannerView.EncryptionInfo(
                isEncrypted: $0.isEncrypted,
                errorDescription: $0.errorDescription
            )
        }
    }

    // MARK: - Displaying Additional Context

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? {
        nil
    }

    func primaryActionClicked(forMessageContext context: Data, completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - MailKit wrappers

/// Wraps `MEMessage` so the core can treat it as a `MailMessage` without
/// requiring the MailKit class to conform to the protocol directly.
private struct MailKitMessage: MailMessage {
    private let message: MEMessage

    init(_ message: MEMessage) {
        self.message = message
    }

    var rawData: Data? { message.rawData }
    var fromAddress: String { message.fromAddress.rawString }
    var recipientAddresses: [String] { message.allRecipientAddresses.map(\.rawString) }
    var isSending: Bool { message.state == .sending }
}

/// Wraps `MEComposeContext`.
private struct MailKitComposeContext: MailComposeContext {
    private let context: MEComposeContext

    init(_ context: MEComposeContext) {
        self.context = context
    }

    var shouldSign: Bool { context.shouldSign }
    var shouldEncrypt: Bool { context.shouldEncrypt }
}

/// Wraps `MEMessageSigner`.
private struct MailKitSigner: MailMessageSigner {
    private let signer: MEMessageSigner

    init(_ signer: MEMessageSigner) {
        self.signer = signer
    }

    var signerEmailAddresses: [String] { signer.emailAddresses.map(\.rawString) }
    var signerLabel: String { signer.label }
    var context: Data { signer.context }
}
