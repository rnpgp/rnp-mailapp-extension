//
//  KeyTransition.swift
//  KeyLifecycle
//
//  Orchestrates the multi-step key transition flow described in
//  TODO.roadmap/05-key-transition-wizard.md. Each step is a discrete
//  method so it can be tested in isolation; the full orchestration is
//  a thin sequence over the steps.
//
//  The engine layer focuses on the cryptographic actions:
//    1. Generate new key (delegated to `KeyManager`).
//    2. Copy old UID(s) onto new key.
//    3. Sign new key's UID(s) with old key (transition certification).
//    4. Revoke old key with reason `superseded` pointing at new key.
//    5. Archive old key (decrypt-only).
//
//  Publish and notify-contacts are caller responsibilities (they touch
//  the network and the user's address book, not the crypto).
//

import Foundation
import MailSecurityEngine
import Rnp

/// Snapshot of a completed transition. Returned by `KeyTransition.run`
/// for the caller to use in publish / notify UX flows.
public struct KeyTransitionResult: Equatable {
    public let oldFingerprint: String
    public let newFingerprint: String
    public let transitionCertificationAdded: Bool
    public let oldKeyArchived: Bool
}

/// Errors thrown by `KeyTransition`.
public enum KeyTransitionError: Error, Equatable {
    case oldKeyNotSecret
    case newKeyAlreadyExists(fingerprint: String)
    case certificationFailed(String)
    case revocationFailed(String)
}

/// Engine-layer orchestrator for key transitions.
public final class KeyTransition {
    private let keyManager: KeyManager

    public init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    /// Runs the full transition flow:
    /// 1. Generate a new key for each old UID.
    /// 2. Add the old UIDs to the new key.
    /// 3. Certify each new UID with the old key.
    /// 4. Revoke the old key with reason `superseded`, naming the new
    ///    fingerprint in the revocation reason text.
    /// 5. Archive the old key (decrypt-only).
    ///
    /// - Parameters:
    ///   - oldFingerprint: the existing key to be replaced.
    ///   - algorithm: algorithm for the new key.
    ///   - userIDsOverride: optional explicit UID list for the new key.
    ///     Defaults to copying the old key's UIDs.
    ///   - hash: hash for the certification signature. Defaults to SHA256.
    /// - Returns: a snapshot of the transition result.
    @discardableResult
    public func run(
        replacing oldFingerprint: String,
        newKeyAlgorithm algorithm: KeyAlgorithm,
        userIDsOverride: [String]? = nil,
        hash: String = "SHA256"
    ) throws -> KeyTransitionResult {
        let userIDs: [String] = try keyManager.withRnp { rnp in
            let old = try rnp.requireKey(oldFingerprint, type: .fingerprint)
            guard (try? old.hasSecret) == true else {
                throw KeyTransitionError.oldKeyNotSecret
            }
            return userIDsOverride ?? ((try? old.userIDs) ?? [])
        }

        // Step 1: generate the new key with a unique placeholder UID. We
        // cannot use the old key's UID directly because `KeyManager.generateKey`
        // looks the new key up by userID, and the old key still has that
        // UID — it would return the old key's fingerprint. The real UIDs
        // are added in step 2.
        let placeholderUID = "RNP transition key \(UUID().uuidString.prefix(8))"
        let newInfo = try keyManager.generateKey(
            userID: placeholderUID,
            algorithm: algorithm,
            expirationSeconds: 0
        )

        // Step 2: add each old UID onto the new key. The placeholder is
        // left in place — it does not affect anything and removing it
        // would require additional FFI wiring (per-UID revocation).
        for uid in userIDs {
            _ = try? keyManager.addUserID(uid, toKeyWithFingerprint: newInfo.fingerprint)
        }

        // Step 3: certify each new UID with the old key.
        //
        // The transition certification is a Generic Certification (0x10)
        // signature made by the OLD primary on the NEW UID+primary. The
        // actual FFI call is `rnp_key_signature_sign`, which is non-
        // trivial to wire correctly; the first version of this flow
        // stubs the call out. Publish and notify still execute, and the
        // user is told via the caller's UI that out-of-band fingerprint
        // verification is required.
        // TODO: wire `rnp_key_signature_sign` once its surface is verified.
        let certificationAdded = false

        // Step 4: revoke the old key with reason `superseded`.
        do {
            try keyManager.withRnp { rnp in
                let old = try rnp.requireKey(oldFingerprint, type: .fingerprint)
                try old.revoke(
                    code: .superseded,
                    reason: "Superseded by \(newInfo.fingerprint)",
                    hash: hash
                )
            }
            try keyManager.save()
        } catch {
            throw KeyTransitionError.revocationFailed(error.localizedDescription)
        }

        // Step 5: archive the old key (decrypt-only) and clean up.
        try keyManager.setUsageState(
            .archived,
            forFingerprint: oldFingerprint,
            reason: "auto-archived by key transition (superseded by \(newInfo.fingerprint))"
        )

        return KeyTransitionResult(
            oldFingerprint: oldFingerprint,
            newFingerprint: newInfo.fingerprint,
            transitionCertificationAdded: certificationAdded,
            oldKeyArchived: true
        )
    }
}
