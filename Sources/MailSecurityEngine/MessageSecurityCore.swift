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
    /// Records decode outcomes for the end-to-end test harness, when set.
    private let stateRecorder: SecurityStateRecorder?

    public init(engine: MailSecurityEngine, stateRecorder: SecurityStateRecorder? = nil) {
        self.engine = engine
        self.stateRecorder = stateRecorder
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

        // Per-recipient key trust, for recipients that resolve to a key.
        // Problem keys and unresolved conflicts block encryption exactly the
        // way `encode` does; unverified keys only produce a warning, matching
        // the engine's TOFU behavior. The sender is skipped: their own key is
        // implicitly trusted (encrypt-to-self), so they must never be flagged
        // as a failing recipient.
        var issues: [RecipientTrustIssue] = []
        for recipient in message.recipientAddresses where !status.missingRecipientKeys.contains(recipient) {
            if KeyManager.addressesMatch(recipient, message.fromAddress) {
                continue
            }
            if trustStore.hasConflict(forEmail: recipient) {
                issues.append(RecipientTrustIssue(recipient: recipient, kind: .conflict))
                continue
            }
            switch trustStore.state(forEmail: recipient) {
            case .problem:
                issues.append(RecipientTrustIssue(recipient: recipient, kind: .problem))
            case .unverified:
                issues.append(RecipientTrustIssue(recipient: recipient, kind: .unverified))
            case .verified:
                break
            }
        }

        let warning = issues.isEmpty ? nil : RecipientTrustWarning(issues: issues)
        let blocked = warning?.blockedRecipients ?? []

        return HandlerEncodingStatus(
            canSign: status.canSign,
            canEncrypt: status.canEncrypt && blocked.isEmpty,
            // Only warn when the user actually asked for encryption; there is
            // no point nagging about recipient keys for a plaintext send.
            securityError: composeContext.shouldEncrypt ? warning : nil,
            addressesFailingEncryption: status.missingRecipientKeys + blocked
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
            recipients: encryptionRecipients(for: message, composeContext: composeContext),
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

    /// Recipient list for an encode request.
    ///
    /// When encryption is requested and a secret key exists for the sender,
    /// the sender is added to the recipients (encrypt-to-self) so they can
    /// decrypt their own sent messages. A sender without a key is left out:
    /// encrypt-to-self is best-effort and must never break a send that would
    /// otherwise succeed. The sender's own key is implicitly trusted; the
    /// engine skips its trust check for the sender.
    private func encryptionRecipients(
        for message: MailMessage,
        composeContext: MailComposeContext
    ) -> [String] {
        let recipients = message.recipientAddresses
        guard composeContext.shouldEncrypt,
              senderKeyAvailable(message.fromAddress),
              !recipients.contains(where: { KeyManager.addressesMatch($0, message.fromAddress) })
        else {
            return recipients
        }
        return recipients + [message.fromAddress]
    }

    /// Whether a secret key for `userID` exists in the keyring. Keyring
    /// failures are treated as "no key".
    private func senderKeyAvailable(_ userID: String) -> Bool {
        let key = try? engine.keyManager.withRnp { rnp in
            try engine.keyManager.secretKeyUnlocked(forUserID: userID, rnp: rnp)
        }
        return key != nil
    }

    // MARK: - Decoding

    public func decodedMessage(forMessageData data: Data) -> HandlerDecodedMessage? {
        guard let decoded = try? engine.decode(data) else {
            return nil
        }
        let signers = decoded.security.signers.map { signer in
            let context = SignerContext(
                fingerprint: signer.fingerprint,
                status: signer.status.rawValue,
                isEncrypted: decoded.security.isEncrypted,
                encryptionError: decoded.security.encryptionError?.localizedDescription
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
        recordState(rawMessage: data, decoded: decoded)
        return HandlerDecodedMessage(data: decoded.data, securityInformation: information)
    }

    // MARK: - State recording

    /// Writes the decode outcome to the state recorder, when configured.
    /// Header fields are read from the raw message so the harness can
    /// correlate the record with the message it injected.
    private func recordState(rawMessage data: Data, decoded: DecodedMessage) {
        guard let stateRecorder else { return }
        let parsed = MimeMessage.parse(data)
        func header(_ name: String) -> String? {
            parsed.headers.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })?.value
        }
        let signers = decoded.security.signers.map { signer in
            RecordedSigner(
                label: signer.userID ?? signer.fingerprint ?? "Unknown signer",
                fingerprint: signer.fingerprint,
                status: signer.status.rawValue,
                trust: signer.fingerprint.map { trustStore.state(forFpr: $0).rawValue }
            )
        }
        stateRecorder.record(RecordedMessageSecurity(
            messageID: header("Message-ID"),
            subject: header("Subject"),
            from: header("From"),
            isEncrypted: decoded.security.isEncrypted,
            signers: signers,
            signingError: decoded.security.signingError?.localizedDescription,
            encryptionError: decoded.security.encryptionError?.localizedDescription
        ))
    }

    // MARK: - Signer context

    /// Decodes the `SignerContext` attached to a signer, if present.
    public func signerContext(for signer: MailMessageSigner) -> SignerContext? {
        guard !signer.context.isEmpty else { return nil }
        return try? JSONDecoder().decode(SignerContext.self, from: signer.context)
    }
}
