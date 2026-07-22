# Task: Touch ID verification per sign/encrypt/decrypt operation

Status: implemented (opt-in, default off).

## Investigation findings

### How other secure apps handle this

- **gpg-agent / GnuPG (and GPG Suite, pinentry-touchid):** the classic model
  is *session-based*. `gpg-agent` caches the unlocked key passphrase for
  `default-cache-ttl` (default 600 s, renewed on use) up to `max-cache-ttl`
  (default 2 h); every uncached use goes through pinentry. The
  `pinentry-touchid` project stores the passphrase in the macOS Keychain
  behind a Touch ID ACL, so an uncached use prompts Touch ID — i.e. Touch ID
  per operation, bounded by a cache TTL. That is exactly the model chosen
  here.
- **1Password (macOS):** session-based. Touch ID unlocks the vault; the
  vault re-locks on an auto-lock timer ("lock after N minutes of
  inactivity", "lock when the Mac sleeps"). It never prompts per item use.
  (On iOS, AutoFill prompts Face ID per fill because the item sits behind a
  `.userPresence` Keychain ACL — a platform constraint, not a product
  choice.)
- **Apple Mail with S/MIME:** no per-operation biometrics at all. The
  private key lives in the keychain; the first use per process triggers the
  "… wants to use your confidential information …" allow/always-allow
  dialog, then it is silent for the session.
- **Keybase:** device keys plus optional biometric unlock of the local
  storage on mobile — again session-based, not per operation.
- **Apple Pay / banking apps:** the opposite extreme — *every* transaction
  is biometrically authorized, because a transaction is an explicit,
  high-value user action.

Conclusion: mainstream tools converge on **biometric unlock + session
timeout**, not strict per-operation prompts. Strict per-operation prompts
appear only where each operation is itself an explicit user action
(payments). This task implements exactly that mainstream model: a prompt
per operation, coalesced by a configurable session timeout (default 30 s).

### Per-operation vs. session-based — trade-offs

- **Security value of per-operation prompts is real but bounded.** The
  unlocked keyring passphrase is cached in process memory either way; an
  attacker with code execution in the extension process can read it
  regardless of how often we prompt. The genuine win is against
  *unattended use*: someone (or something, via Mail's UI) triggering a
  sign/decrypt while the user is away from an unlocked Mac. A fresh Touch
  ID prompt proves presence at use time, not just at unlock time.
- **Sign/encrypt vs. decrypt are different UX.** Signing/encrypting happens
  on an explicit user action (Send), so a prompt there matches user intent
  ("I am sending this"). Decryption happens passively — Mail decodes every
  message you merely select — so prompting per decrypt without a timeout
  would be unusable (one prompt per message browsed). The session timeout
  is what makes the feature acceptable: one prompt covers an operation's
  internal burst of passphrase requests *and* the user's natural
  reading/sending cadence.
- **Backoff after cancel.** A cancelled prompt starts the existing 30 s
  backoff so a burst of librnp requests (or Mail auto-retrying a decode)
  does not spam prompts. Trade-off: a deliberate retry within 30 s of a
  cancel fails silently without a new prompt — consistent with the shipped
  keyring-unlock behavior.

### Passkeys (WebAuthn) as an alternative?

Not pursued, and not recommended here:

- WebAuthn on macOS (`ASAuthorizationPlatformPublicKeyCredentialProvider`)
  is designed for *web sign-in ceremonies* (RP ID, challenge/response),
  not for gating arbitrary local operations.
- A platform passkey assertion and an `LAContext` evaluation are both
  "user presence" proofs rooted in the same Secure Enclave biometric — the
  passkey adds ceremony complexity with **zero** additional security for a
  purely local gate. (The WebAuthn PRF extension, which could actually
  wrap a secret, is not exposed by the native macOS API.)
- Touch ID via LocalAuthentication / Keychain ACL is the correct
  primitive, is already in use here, and carries the system-level
  login-password fallback for free.

## Implementation

All logic lives in the Swift package (`Sources/MailSecurityEngine/`), so
`MailSecurityEngine`'s API is unchanged; the container app only exposes the
setting.

- **`OperationVerification.swift` (new):** the shared setting, stored in
  the app-group `UserDefaults` (same pattern as `RecipientKeyAutoFetch`),
  so the container app writes and the Mail extension reads the same value
  live. `requireTouchIDPerOperation` (default off) and
  `operationVerificationTimeoutSeconds` (default 30).
- **`KeychainPassphraseStore.swift`:** a `verifyOperationAccess()` gate.
  When the setting is off it returns `true` immediately (zero behavior
  change). When on, a stale verification prompts once — via a fresh
  ACL-protected Keychain read when the keyring is Touch ID-protected, or a
  direct `LAContext.deviceOwnerAuthentication` evaluation (Touch ID with
  login-password fallback) for plain storage — and records the timestamp.
  The gate is applied in `sharedPassphrase()` and at the top of
  `resolvingProvider()`, so per-key passphrases (foreign-passphrase keys)
  are gated too. Success re-arms the timeout window; failure starts the
  existing 30 s backoff and returns `""`/`nil`, failing the operation
  gracefully. A successful biometric Keychain read and
  `cacheVerifiedPassphrase` (the container app's manual passphrase
  fallback) both count as verification.
- **Container app UI:** Help → "Security…" opens a sheet with the toggle
  and a timeout picker (15 s / 30 s / 1 min / 5 min). Strings added to the
  String Catalog in all 11 languages (non-English marked `needs_review`,
  matching the project's convention).
- **Docs:** `docs/SECURITY-MODEL.md` and the `MessageSecurityHandler` doc
  comment updated.

### Tests

`Tests/MailSecurityEngineTests/OperationVerificationTests.swift` (8 tests):
setting round-trip/defaults, no prompt when disabled, one prompt per
timeout window, re-prompt when stale, deny+backoff on failure, retry after
backoff, manual unlock counting as verification, and per-key passphrases
being gated. Tests stub `KeychainPassphraseStore.operationVerifier`, so no
real Touch ID prompt is ever triggered (same convention as the existing
Keychain tests).

## Verification

- `PKG_CONFIG_PATH=…/v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker …/v0.18.1/lib`:
  **326 tests, 0 failures** (84 s), including the 8 new
  `OperationVerificationTests` (also run standalone: 8/8 passed in 0.5 s).
  The only warnings are the pre-existing machine-specific snapshot
  font-rendering warnings in `MailSecurityUITests`.
- `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme RNP build CODE_SIGNING_ALLOWED=NO`:
  **BUILD SUCCEEDED**.
- `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO`:
  **BUILD SUCCEEDED**.

## Known limitations / follow-ups

- The prompt reason string inside the package
  ("Authorize signing and decryption with your OpenPGP keys") is English
  only, matching the existing "Unlock your RNP keyring" string; system
  prompt text localization would need package-side localization support.
- After a cancelled prompt, deliberate retries within the 30 s backoff fail
  silently (no new prompt) — inherited from the keyring-unlock behavior.
- The biometric path re-prompts via the Keychain ACL read; on macOS a very
  recent Touch ID authentication may satisfy the ACL without a visible
  prompt, which is semantically still a fresh user-presence check.
