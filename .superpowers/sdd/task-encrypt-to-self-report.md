# Task report: encrypt-to-self

**Branch:** `fix/encrypt-to-self` (from `main`)
**Date:** 2026-07-22

## Goal

Close the highest-impact gap from `.superpowers/sdd/feature-audit-report.md`
(P1-1): the sender could not decrypt their own sent messages because the
sender's key was never added as an encryption recipient — only To/Cc/Bcc
addresses were encrypted to.

## What changed

### 1. `Sources/MailSecurityEngine/MessageSecurityCore.swift`

- `encode` now builds its recipient list via a new private
  `encryptionRecipients(for:composeContext:)`: when encryption is requested
  and `keyManager.secretKeyUnlocked(forUserID:)` resolves a key for the
  sender (`MailMessage.fromAddress`), the sender's address is appended to the
  `EncodingRequest.recipients` (deduplicated with a case-insensitive
  address comparison, so a sender already present in To/Cc/Bcc is not added
  twice). A sender without a key is simply not added — encrypt-to-self is
  best-effort and never breaks a send that would previously succeed
  (encrypt-only send from an account with no key still works).
- `getEncodingStatus` now skips the sender in the per-recipient trust-issue
  loop: the sender's own key is implicitly trusted (mirroring the encode
  path), so the sender is never flagged in `addressesFailingEncryption` or
  in the `RecipientTrustWarning`, even when the sender is an explicit
  recipient with a key-change conflict on their own address.

### 2. `Sources/MailSecurityEngine/MailSecurityEngine.swift`

- The per-recipient trust check inside `encode` (which throws
  `MailSecurityError.trustConflict` for `.problem` keys or unresolved
  conflicts) now exempts the recipient that matches `request.sender`.
  Rationale: the check executes inside `engine.encode`, so it cannot be
  bypassed from `MessageSecurityCore` — no recipient string routed through
  the public API can avoid the fingerprint-based `.problem` check. The
  public `MailSecurityEngine` API is unchanged (no signature or type
  changes); this is an internal behavior exemption, as suggested by the
  audit ("in `MessageSecurityCore.encode` (or `MailSecurityEngine.encode`)").
  Without it, a conflict recorded for the user's own address (e.g. after
  importing a second key for oneself) would newly break *all* encrypted
  sending once encrypt-to-self adds the sender to the recipient set.

### 3. `Sources/MailSecurityEngine/KeyManager.swift`

- New internal `static func addressesMatch(_:_:)`: case-insensitive address
  equality comparing the emails extracted from user-ID form when present
  (reuses the existing `emailAddress(from:)`). Used by both the core and the
  engine for sender/recipient comparison.

`MessageSecurityHandler` (MailKit adapter) needed no changes.

## Tests added

`Tests/MailSecurityEngineTests/MessageSecurityCoreTests.swift`:

- `testEncodeEncryptToSelfSenderCanDecrypt` — the required test: Alice
  encrypts to Bob; both Bob *and Alice* decrypt the encoded message
  successfully (pre-fix, Alice's decode carried an encryption error and no
  data).
- `testEncodeEncryptWithoutSenderKeyStillSucceeds` — regression guard:
  encrypt-only send with no sender key does not fail with
  `missingRecipientKeys`.
- `testEncodeEncryptToSelfIgnoresSenderTrustConflict` — a key-change
  conflict on the sender's own address does not block encrypt-to-self.
- `testEncodeEncryptToSelfIgnoresSenderProblemState` — the sender's own key
  marked `.problem` does not block encrypt-to-self.
- `testGetEncodingStatusDoesNotFlagSenderWithConflict` — compose-time status
  does not flag the sender as a failing recipient, even when the sender is
  an explicit recipient with a conflict on their own address.

`Tests/MailSecurityEngineTests/MailSecurityEngineTests.swift`:

- `testTrustConflictOnSenderDoesNotBlockEncryption` — engine-level pin of
  the sender exemption.

## Verification

1. `PKG_CONFIG_PATH=.../v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker .../v0.18.1/lib`
   — **166 tests, 0 failures.**
   (One intermediate failure during development: the Bob-side assertion in
   the new round-trip test hit a pre-existing decode behavior —
   `Rnp.verifyDetailed` returns `payload: nil` when the signer's key is not
   in the keyring. Fixed by importing Alice's public key into Bob's keyring,
   mirroring the existing `testMultiRecipientEncryption` pattern. Not caused
   by, and not changed by, this task.)
2. `xcodebuild -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO` — **BUILD SUCCEEDED**.
3. `xcodebuild -scheme "Ribose container" build CODE_SIGNING_ALLOWED=NO` — **BUILD SUCCEEDED**.

## Notes / follow-ups

- Pre-existing decode gap observed (out of scope): when the *recipient* lacks
  the signer's public key, `decodePGPMimeEncrypted` yields empty decoded
  data (`verifyDetailed` drops the payload on non-success verify status).
  Worth its own task.
