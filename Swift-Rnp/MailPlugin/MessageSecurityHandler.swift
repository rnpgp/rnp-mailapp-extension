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
    /// Keychain. The keyed provider answers per-key passphrase requests for
    /// imported keys protected by a foreign passphrase before falling back
    /// to the keyring passphrase. Returns `nil` when the keyring is
    /// unavailable so the extension can still launch and degrade gracefully.
    ///
    /// Touch ID: when the user enabled Touch ID during onboarding, the
    /// keyring passphrase is stored with a biometric access control, so the
    /// first passphrase read in this process shows a system Touch ID prompt
    /// over Mail. If the user cancels, the provider returns `nil` and the
    /// sign/decrypt operation fails gracefully (the error is recorded for
    /// the banner); a short backoff avoids re-prompting on every message.
    /// A successful unlock is cached for the process lifetime. Manual
    /// passphrase entry lives in the container app — unlock there and the
    /// next message access here succeeds.
    ///
    /// When "require Touch ID for each operation" is enabled in the
    /// container app's security settings, the provider instead prompts once
    /// per session-timeout window (default 30 seconds) before handing out a
    /// passphrase, so every sign/encrypt/decrypt operation is freshly
    /// authorized.
    private static func makeCore() -> MessageSecurityCore? {
        let provider: Rnp.KeyedPassphraseProvider = KeychainPassphraseStore.resolvingProvider()
        let stateRecorder = SecurityStateRecorder(directory: AppGroup.extensionStateDirectory())
        if let engine = try? makeEngine(directory: AppGroup.keyringDirectory(), provider: provider) {
            return MessageSecurityCore(engine: engine, stateRecorder: stateRecorder)
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-mail-extension-fallback")
        guard let engine = try? makeEngine(directory: fallback, provider: provider) else {
            return nil
        }
        return MessageSecurityCore(engine: engine, stateRecorder: stateRecorder)
    }

    private static func makeEngine(
        directory: URL,
        provider: @escaping Rnp.KeyedPassphraseProvider
    ) throws -> MailSecurityEngine {
        MailSecurityEngine(keyManager: try KeyManager(directory: directory, keyedPassphraseProvider: provider))
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
        // Snapshot the message before the async hop: with auto-fetch enabled
        // the status may complete after a keyserver round-trip, and MailKit
        // message objects are not meant to be read off the callback queue.
        let snapshot = SnapshotMailMessage(
            fromAddress: message.fromAddress.rawString,
            recipientAddresses: message.allRecipientAddresses.map(\.rawString)
        )
        let context = SnapshotComposeContext(
            shouldSign: composeContext.shouldSign,
            shouldEncrypt: composeContext.shouldEncrypt
        )
        Task {
            let status = await core.getEncodingStatusWithAutoFetch(
                for: snapshot,
                composeContext: context
            )
            completionHandler(MEOutgoingMessageEncodingStatus(
                canSign: status.canSign,
                canEncrypt: status.canEncrypt,
                securityError: status.securityError,
                addressesFailingEncryption: status.addressesFailingEncryption.map { MEEmailAddress(rawString: $0) }
            ))
        }
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

    /// BCC-aware encode path. Catches `BccRequiresSpecialHandlingError`
    /// and surfaces it as a structured `encryptionError` so the
    /// container app can present `BCCRefusalSheet`. When the user
    /// picks a resolution, the container app calls
    /// `applyBccResolution(_:message:composeContext:sign:encrypt:)`.
    func encodeWithBccHandling(
        _ message: MEMessage,
        composeContext: MEComposeContext,
        completionHandler: @escaping (MEMessageEncodingResult) -> Void
    ) {
        guard let core = core else {
            completionHandler(MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil))
            return
        }
        do {
            let result = try core.encodeWithBccPolicy(
                MailKitMessage(message),
                composeContext: MailKitComposeContext(composeContext),
                bccPolicy: .refuse
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
        } catch let error as BccRequiresSpecialHandlingError {
            completionHandler(MEMessageEncodingResult(
                encodedMessage: nil,
                signingError: nil,
                encryptionError: error
            ))
        } catch {
            completionHandler(MEMessageEncodingResult(
                encodedMessage: nil,
                signingError: nil,
                encryptionError: error
            ))
        }
    }

    /// Applies a user-chosen BCC resolution and returns the encoded
    /// result. Called by the container app after presenting
    /// `BCCRefusalSheet`.
    func applyResolution(
        _ resolution: BccResolution,
        for message: MEMessage,
        composeContext: MEComposeContext
    ) -> MEMessageEncodingResult {
        guard let core = core else {
            return MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
        }
        let outcome = core.applyBccResolution(
            resolution,
            message: MailKitMessage(message),
            composeContext: MailKitComposeContext(composeContext),
            sign: composeContext.shouldSign,
            encrypt: composeContext.shouldEncrypt
        )
        switch outcome {
        case .cancelled:
            return MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
        case let .singleMessage(result):
            let outgoing = result.encodedMessage.map {
                MEEncodedOutgoingMessage(rawData: $0.rawData, isSigned: $0.isSigned, isEncrypted: $0.isEncrypted)
            }
            return MEMessageEncodingResult(
                encodedMessage: outgoing,
                signingError: result.signingError,
                encryptionError: result.encryptionError
            )
        case .separateMessages:
            // The container app should call the engine's
            // encodeSendSeparately directly; this returns nil for now.
            return MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
        }
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
    /// Raw data of the most recently decoded message, kept so the banner's
    /// "Fetch signer key" action can re-decode the message after importing
    /// the key. Same decode-before-indicator guarantee as above.
    private var lastDecodedRawData: Data?
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
        lastDecodedRawData = data
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
        lastDecodedEncryptionLock.lock()
        let rawData = lastDecodedRawData
        lastDecodedEncryptionLock.unlock()
        return MessageSecurityViewController(
            signers: messageSigners,
            contexts: contexts,
            trustStore: core.trustStore,
            encryption: encryptionInfo(for: contexts),
            fetchSignerKey: makeSignerKeyFetch(core: core, rawData: rawData)
        )
    }

    /// Builds the banner's "Fetch signer key" operation: fetch and import
    /// the signer's key, then re-decode the message so the banner shows the
    /// refreshed signature status. Returns `nil` when no decoded message is
    /// available to re-verify (the banner then hides the action).
    private func makeSignerKeyFetch(
        core: MessageSecurityCore,
        rawData: Data?
    ) -> MessageSecurityViewController.SignerKeyFetch? {
        guard let rawData else { return nil }
        return { context in
            switch await core.fetchSignerKey(fingerprint: context.fingerprint, email: context.email) {
            case let .failure(error):
                return .failure(error)
            case .success:
                guard let decoded = core.decodedMessage(forMessageData: rawData) else {
                    return .failure(.invalidResponse)
                }
                let signers = decoded.securityInformation.signers.map { info in
                    MailSecurityBannerView.Signer(
                        label: info.signatureLabel,
                        context: core.signerContext(for: info)
                    )
                }
                let encryption = MailSecurityBannerView.EncryptionInfo(
                    isEncrypted: decoded.securityInformation.isEncrypted,
                    errorDescription: decoded.securityInformation.encryptionError?.localizedDescription
                )
                return .success(MessageSecurityViewController.RefreshedBannerContent(
                    signers: signers,
                    encryption: encryption
                ))
            }
        }
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
    var toAddresses: [String] { message.toRecipients.map(\.rawString) }
    var ccAddresses: [String] { message.ccRecipients.map(\.rawString) }
    var bccAddresses: [String] { message.bccRecipients.map(\.rawString) }
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

/// Value-type `MailMessage` snapshot for the encoding-status path, which may
/// complete asynchronously after a keyserver fetch. Only the fields
/// `getEncodingStatus` reads are captured.
private struct SnapshotMailMessage: MailMessage {
    let fromAddress: String
    let recipientAddresses: [String]

    var rawData: Data? { nil }
    var isSending: Bool { true }
}

/// Value-type `MailComposeContext` snapshot for the same reason.
private struct SnapshotComposeContext: MailComposeContext {
    let shouldSign: Bool
    let shouldEncrypt: Bool
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
