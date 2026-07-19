//
//  SignerTrustViewModel.swift
//  swift-rnp
//
//  Pure mapping from signature verification status + key trust to a
//  Mail-extension banner view model. Kept free of MailKit types so it is
//  unit-testable with plain XCTest.
//

import Foundation
import Rnp
import TrustStore

/// Visual intent for a signer trust line.
public enum SignerTrustIntent: Equatable, Sendable {
    /// Verified signature + verified key.
    case positive
    /// Verified signature but key not verified, or neutral state.
    case neutral
    /// Signature or trust problem that deserves attention.
    case caution
    /// Hard failure: invalid signature or key marked problem.
    case critical
}

/// View model describing how to present one signer's trust in Mail's security
/// banner.
public struct SignerTrustViewModel: Equatable, Sendable {
    /// Short headline, e.g. "Verified key" or "Key not verified".
    public let label: String
    /// Longer explanation shown below the headline.
    public let detail: String
    /// Visual intent driving the banner color.
    public let intent: SignerTrustIntent
    /// Whether the banner should offer a deep link to review the key.
    public let reviewDeepLink: Bool

    public init(
        label: String,
        detail: String,
        intent: SignerTrustIntent,
        reviewDeepLink: Bool
    ) {
        self.label = label
        self.detail = detail
        self.intent = intent
        self.reviewDeepLink = reviewDeepLink
    }
}

/// Maps a signature verification status and the signer's trust state to a
/// presentation model for the Mail extension banner.
///
/// The mapping is deliberately simple and does not include web-of-trust or
/// ownertrust semantics.
public func mapSignerTrust(
    status: RnpSignatureStatus,
    trust: TrustState
) -> SignerTrustViewModel {
    switch (status, trust) {
    case (.valid, .verified):
        return SignerTrustViewModel(
            label: "Verified key",
            detail: "This signature was made by a key whose fingerprint you verified.",
            intent: .positive,
            reviewDeepLink: false
        )
    case (.valid, .problem):
        return SignerTrustViewModel(
            label: "Key problem",
            detail: "This key is marked as having a problem (expired, revoked, or changed). Do not trust this signature without checking the fingerprint.",
            intent: .critical,
            reviewDeepLink: true
        )
    case (.valid, .unverified):
        return SignerTrustViewModel(
            label: "Key not verified",
            detail: "The signature is valid, but you have not verified this key's fingerprint. Verify it before trusting the signature.",
            intent: .neutral,
            reviewDeepLink: true
        )
    case (.expired, .verified):
        return SignerTrustViewModel(
            label: "Verified key, expired signature",
            detail: "The key is verified, but the signature has expired.",
            intent: .caution,
            reviewDeepLink: false
        )
    case (.expired, .problem):
        return SignerTrustViewModel(
            label: "Key problem, expired signature",
            detail: "The key is marked as having a problem and the signature has expired.",
            intent: .critical,
            reviewDeepLink: true
        )
    case (.expired, .unverified):
        return SignerTrustViewModel(
            label: "Key not verified, expired signature",
            detail: "The signature has expired and the key has not been verified.",
            intent: .caution,
            reviewDeepLink: true
        )
    case (.signerUnknown, _):
        return SignerTrustViewModel(
            label: "Unknown signer",
            detail: "The signer's public key is not in your keyring.",
            intent: .critical,
            reviewDeepLink: false
        )
    case (.invalid, _):
        return SignerTrustViewModel(
            label: "Invalid signature",
            detail: "The signature does not verify; the message may have been modified.",
            intent: .critical,
            reviewDeepLink: false
        )
    case (.unknown, .verified):
        return SignerTrustViewModel(
            label: "Verified key, unknown signature status",
            detail: "The key is verified, but the signature status is unknown.",
            intent: .caution,
            reviewDeepLink: false
        )
    case (.unknown, .problem):
        return SignerTrustViewModel(
            label: "Key problem, unknown signature status",
            detail: "The key is marked as having a problem and the signature status is unknown.",
            intent: .critical,
            reviewDeepLink: true
        )
    case (.unknown, .unverified):
        return SignerTrustViewModel(
            label: "Key not verified, unknown signature status",
            detail: "The signature status is unknown and the key has not been verified.",
            intent: .caution,
            reviewDeepLink: true
        )
    }
}
