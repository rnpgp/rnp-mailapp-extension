//
//  SignerContext.swift
//  swift-rnp
//
//  Context attached to each `MEMessageSigner` so the banner UI can look up
//  trust state without re-running verification. Shared between the Mail
//  extension (which encodes it into `MEMessageSigner.context`) and the
//  `MailSecurityUI` banner view (which consumes it).
//

import Foundation

/// Per-signer context carried from the decode path to the security banner.
///
/// Serialized as JSON into `MEMessageSigner.context` by the Mail extension
/// and decoded back for display. The wire format is stable; do not rename
/// fields without a migration. New fields must stay optional so payloads
/// written by older extension versions still decode.
public struct SignerContext: Codable, Equatable, Sendable {
    /// OpenPGP fingerprint of the signing key, when known.
    public let fingerprint: String?
    /// `RnpSignatureStatus` raw value for the signature verification result.
    public let status: String
    /// Whether the message this signer belongs to was encrypted. Carried in
    /// every signer's context because MailKit's
    /// `extensionViewController(signers:)` does not pass encryption state.
    public let isEncrypted: Bool?
    /// Decryption problem reported at decode time, when any.
    public let encryptionError: String?
    /// Email address associated with the signer, when known: the address
    /// from the signing key's user ID, or — for unknown signers, whose key is
    /// not in the keyring — the message's `From:` address as a best-effort
    /// fallback. Used by the banner's "Fetch signer key" action when the
    /// fingerprint is unavailable.
    public let email: String?

    public init(
        fingerprint: String?,
        status: String,
        isEncrypted: Bool? = nil,
        encryptionError: String? = nil,
        email: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.status = status
        self.isEncrypted = isEncrypted
        self.encryptionError = encryptionError
        self.email = email
    }
}
