//
//  FileSecurityEngine.swift
//  RNP
//
//  The deep module for OpenPGP file operations: encrypt, decrypt, sign,
//  sign-detached, verify (inline + detached). Replaces the ad-hoc
//  encrypt/decrypt/verify methods that used to live on KeysManager.
//
//  Design principles (see TODO.complete/05-sign-verify-files.md):
//    - MECE: every file operation lives here, exactly once.
//    - OCP: adding a new operation = adding a new Strategy + one case
//      to the router switch in `perform(_:)`. Existing strategies don't
//      change.
//    - Model-driven: types named after the domain (SignRequest,
//      SignatureVerification), not after the implementation.
//

import Foundation
import MailSecurityEngine
import Rnp

// MARK: - Operations

/// Every file security operation the engine can perform. Adding a new
/// verb = adding a case here + a Strategy below.
public enum FileSecurityOperation {
    case encrypt(EncryptRequest)
    case encryptWithPassword(EncryptWithPasswordRequest)
    case decrypt(DecryptRequest)
    case sign(SignRequest)
    case signDetached(SignRequest)
    case signCleartext(SignRequest)
    case verify(VerifyRequest)
    case verifyDetached(VerifyDetachedRequest)
}

public struct EncryptRequest {
    public let plaintext: Data
    public let recipientFingerprints: [String]
    public let armored: Bool
    /// AEAD-OCB instead of legacy CFB+MDC. Off by default for GnuPG interop.
    public let aead: Bool

    public init(plaintext: Data, recipientFingerprints: [String], armored: Bool = true, aead: Bool = false) {
        self.plaintext = plaintext
        self.recipientFingerprints = recipientFingerprints
        self.armored = armored
        self.aead = aead
    }
}

public struct DecryptRequest {
    public let ciphertext: Data
    public init(ciphertext: Data) { self.ciphertext = ciphertext }
}

/// Symmetric (passphrase-only) encryption request. No recipients;
/// anyone with the passphrase can decrypt.
public struct EncryptWithPasswordRequest {
    public let plaintext: Data
    public let passphrase: String
    public let armored: Bool
    /// AEAD-OCB instead of legacy CFB+MDC. Off by default for GnuPG interop.
    public let aead: Bool

    public init(plaintext: Data, passphrase: String, armored: Bool = true, aead: Bool = false) {
        self.plaintext = plaintext
        self.passphrase = passphrase
        self.armored = armored
        self.aead = aead
    }
}

public struct SignRequest {
    public let payload: Data
    public let signingKeyFingerprint: String
    public let armored: Bool

    public init(payload: Data, signingKeyFingerprint: String, armored: Bool = true) {
        self.payload = payload
        self.signingKeyFingerprint = signingKeyFingerprint
        self.armored = armored
    }
}

public struct VerifyRequest {
    public let signedPayload: Data
    public init(signedPayload: Data) { self.signedPayload = signedPayload }
}

public struct VerifyDetachedRequest {
    public let payload: Data
    public let detachedSignature: Data
    public init(payload: Data, detachedSignature: Data) {
        self.payload = payload
        self.detachedSignature = detachedSignature
    }
}

// MARK: - Result

public struct FileSecurityResult {
    public enum Kind {
        case ciphertext(Data)
        case plaintext(Data, signatureValidity: Bool?)
        case signedPayload(Data)
        case detachedSignature(Data)
        case verification(SignatureVerification, payload: Data?)
    }

    public let kind: Kind

    public static func ciphertext(_ data: Data) -> FileSecurityResult {
        FileSecurityResult(kind: .ciphertext(data))
    }
    public static func plaintext(_ data: Data, signatureValidity: Bool?) -> FileSecurityResult {
        FileSecurityResult(kind: .plaintext(data, signatureValidity: signatureValidity))
    }
    public static func signedPayload(_ data: Data) -> FileSecurityResult {
        FileSecurityResult(kind: .signedPayload(data))
    }
    public static func detachedSignature(_ data: Data) -> FileSecurityResult {
        FileSecurityResult(kind: .detachedSignature(data))
    }
    public static func verification(_ verification: SignatureVerification, payload: Data?) -> FileSecurityResult {
        FileSecurityResult(kind: .verification(verification, payload: payload))
    }
}

/// Outcome of a signature check. `isValid` is the bottom line; the rest
/// is presentation metadata.
public struct SignatureVerification {
    public let isValid: Bool
    public let signerFingerprint: String?
    public let signerUserID: String?
    public let signedAt: Date?

    public init(isValid: Bool, signerFingerprint: String?, signerUserID: String?, signedAt: Date?) {
        self.isValid = isValid
        self.signerFingerprint = signerFingerprint
        self.signerUserID = signerUserID
        self.signedAt = signedAt
    }
}

// MARK: - Errors

public enum FileSecurityError: Error, LocalizedError {
    case keyringUnavailable
    case recipientNotFound(fingerprint: String)
    case noRecipients
    case signingKeyNotFound(fingerprint: String)
    case noSigningKeyConfigured
    case verificationFailed
    case engine(Error)

    public var errorDescription: String? {
        switch self {
        case .keyringUnavailable:    return "error.fileSecurity.keyringUnavailable".localized
        case .recipientNotFound(let fpr): return String(format: "error.fileSecurity.recipientNotFound".localized, String(fpr.prefix(16)))
        case .noRecipients:          return "error.fileSecurity.noRecipients".localized
        case .signingKeyNotFound(let fpr): return String(format: "error.fileSecurity.signingKeyNotFound".localized, String(fpr.prefix(16)))
        case .noSigningKeyConfigured:return "error.fileSecurity.noSigningKeyConfigured".localized
        case .verificationFailed:    return "error.fileSecurity.verificationFailed".localized
        case .engine(let err):       return err.localizedDescription
        }
    }
}

// MARK: - Engine

/// Single entry point for all OpenPGP file operations. Construct one
/// per `KeysManager` and call `perform(_:)` with the operation you want.
public final class FileSecurityEngine {
    private let keyringStore: KeyringStore?

    public init(keyringStore: KeyringStore?) {
        self.keyringStore = keyringStore
    }

    /// Routes an operation to its strategy. This is the only switch in
    /// the file — adding a new operation means adding one case here plus
    /// a Strategy implementation below.
    public func perform(_ operation: FileSecurityOperation) throws -> FileSecurityResult {
        guard let keyringStore else { throw FileSecurityError.keyringUnavailable }
        switch operation {
        case .encrypt(let req):      return try EncryptStrategy.perform(req, keyringStore: keyringStore)
        case .encryptWithPassword(let req): return try EncryptWithPasswordStrategy.perform(req, keyringStore: keyringStore)
        case .decrypt(let req):      return try DecryptStrategy.perform(req, keyringStore: keyringStore)
        case .sign(let req):         return try SignStrategy.perform(req, detached: false, keyringStore: keyringStore)
        case .signDetached(let req): return try SignStrategy.perform(req, detached: true, keyringStore: keyringStore)
        case .signCleartext(let req):        return try SignCleartextStrategy.perform(req, keyringStore: keyringStore)
        case .verify(let req):       return try VerifyStrategy.performInline(req, keyringStore: keyringStore)
        case .verifyDetached(let req): return try VerifyStrategy.performDetached(req, keyringStore: keyringStore)
        }
    }
}

// MARK: - Strategies (one per operation; OCP — add new operations here)

enum EncryptStrategy {
    static func perform(_ req: EncryptRequest, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            var recipients: [RnpKey] = []
            for fpr in req.recipientFingerprints {
                guard let key = try? rnp.requireKey(fpr, type: .fingerprint) else {
                    throw FileSecurityError.recipientNotFound(fingerprint: fpr)
                }
                recipients.append(key)
            }
            guard !recipients.isEmpty else { throw FileSecurityError.noRecipients }
            let ciphertext: Data
            if req.aead {
                ciphertext = try rnp.encrypt(req.plaintext, for: recipients, aead: .ocb, pkeskVersion: .v3, armored: req.armored)
            } else {
                ciphertext = try rnp.encrypt(req.plaintext, for: recipients, armored: req.armored)
            }
            return .ciphertext(ciphertext)
        }
    }
}

enum DecryptStrategy {
    static func perform(_ req: DecryptRequest, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            // Try decrypt first; fall back to verify for cleartext-signed payloads.
            if let decrypted = try? rnp.decrypt(req.ciphertext) {
                return .plaintext(decrypted, signatureValidity: nil)
            }
            let verified = try rnp.verifyDetailed(req.ciphertext)
            return .plaintext(verified.payload ?? req.ciphertext, signatureValidity: verified.hasValidSignature)
        }
    }
}

enum EncryptWithPasswordStrategy {
    static func perform(_ req: EncryptWithPasswordRequest, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            let aead: Rnp.EncryptAEAD = req.aead ? .ocb : .none
            let ciphertext = try rnp.encryptWithPassword(
                req.plaintext,
                password: req.passphrase,
                aead: aead,
                armored: req.armored
            )
            return .ciphertext(ciphertext)
        }
    }
}

enum SignCleartextStrategy {
    static func perform(_ req: SignRequest, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            let key = try rnp.requireKey(req.signingKeyFingerprint, type: .fingerprint)
            let cleartext = try rnp.signCleartext(req.payload, with: key)
            return .signedPayload(cleartext)
        }
    }
}

enum SignStrategy {
    /// `detached == false` produces an inline signed payload (the
    /// original bytes plus the signature). `detached == true` produces
    /// a standalone `.sig` the user keeps alongside the original.
    static func perform(_ req: SignRequest, detached: Bool, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            let key = try rnp.requireKey(req.signingKeyFingerprint, type: .fingerprint)
            if detached {
                let sig = try rnp.signDetached(req.payload, with: key, armored: req.armored)
                return .detachedSignature(sig)
            } else {
                let signed = try rnp.sign(req.payload, with: key, armored: req.armored)
                return .signedPayload(signed)
            }
        }
    }
}

enum VerifyStrategy {
    static func performInline(_ req: VerifyRequest, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            let v = try rnp.verifyDetailed(req.signedPayload)
            return makeVerificationResult(from: v, fallbackPayload: req.signedPayload)
        }
    }

    static func performDetached(_ req: VerifyDetachedRequest, keyringStore: KeyringStore) throws -> FileSecurityResult {
        try keyringStore.withRnp { rnp in
            let v = try rnp.verifyDetachedDetailed(signature: req.detachedSignature, data: req.payload)
            return makeVerificationResult(from: v, fallbackPayload: req.payload)
        }
    }

    /// Pure translation from `RnpVerification` to our domain type. No
    /// key lookups — those belong in the view layer, which has the
    /// user-facing key list.
    private static func makeVerificationResult(
        from v: RnpVerification,
        fallbackPayload: Data
    ) -> FileSecurityResult {
        let primary = v.signatures.first(where: { $0.status == .valid }) ?? v.signatures.first
        let verification = SignatureVerification(
            isValid: v.hasValidSignature,
            signerFingerprint: primary?.fingerprint,
            signerUserID: nil,
            signedAt: primary?.creationDate
        )
        return .verification(verification, payload: v.payload ?? fallbackPayload)
    }
}
