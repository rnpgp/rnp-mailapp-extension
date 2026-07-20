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
/// fields without a migration.
public struct SignerContext: Codable, Equatable, Sendable {
    /// OpenPGP fingerprint of the signing key, when known.
    public let fingerprint: String?
    /// `RnpSignatureStatus` raw value for the signature verification result.
    public let status: String

    public init(fingerprint: String?, status: String) {
        self.fingerprint = fingerprint
        self.status = status
    }
}
