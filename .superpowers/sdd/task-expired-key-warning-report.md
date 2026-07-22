# Task report: recipient key expired warning + fetch/update action

Branch: `feat/expired-key-warning` (from `main`)

## Goal

When a recipient's key is expired, show a clear warning in Mail compose and
in the security banner, and offer to fetch a new key from the keyserver or
update (extend) the existing key.

## Key finding from probing

Encrypting to an expired key **does not fail**: librnp resolves expired keys
(`encodingStatus` reports them as present) and `encode` succeeds. Verified
with a scratch probe test (key with `expirationSeconds: 1`, slept past
expiry, `engine.encode` still returned `isEncrypted=true`). Therefore the
expired-key state is surfaced as a **warning only** — recipients are *not*
added to `addressesFailingEncryption` and `canEncrypt` is unchanged.

## What was implemented

### 1. Compose-time expired key warning (`MessageSecurityCore.getEncodingStatus`)

- New `Sources/MailSecurityEngine/ExpiredKeyWarning.swift`:
  - `ExpiredRecipientKey` — recipient + expiration date.
  - `ExpiredRecipientKeysWarning` — `Error`/`LocalizedError` surfaced through
    `HandlerEncodingStatus.securityError` (and on to MailKit's
    `MEOutgoingMessageEncodingStatus.securityError`, which
    `Swift-Rnp/MailPlugin/MessageSecurityHandler.swift` already forwards
    unchanged, so no MailKit-side changes were needed). The text lists the
    recipients with their expiration dates and offers both remedies (fetch
    from keyserver in the RNP app, or extend the key's expiry if it is the
    user's own key).
  - `RecipientKeyUpdateError` — errors for the update action.
  - `formatKeyExpirationDate(_:)` — shared locale-aware date formatting.
- `MessageSecurityCore.getEncodingStatus` now detects expired recipient
  keys via the new private `expiredKeyExpiration(for:)`:
  - A key counts as expired when the **primary** is expired, or when **every
    encryption-capable subkey** is expired (`expiredForEncryption(_:now:)`);
    an expired primary with a valid subkey and a valid primary with an
    expired encryption subkey both warn.
  - Per-recipient precedence: conflict → problem → **expired** → unverified.
    The expiry warning takes precedence over the unverified TOFU note because
    it carries the actionable remedies; blocking states (conflict/problem)
    still win because `encode` fails for them.
  - The sender is skipped (encrypt-to-self, implicitly trusted), exactly as
    for trust issues.
  - `ComposeSecurityWarning` gained an `expiredKeyWarning` field (defaulted
    `nil` init parameter, source-compatible). When exactly one warning kind
    is present it is still surfaced directly (`RecipientTrustWarning`,
    `MissingRecipientKeysHint`, `ExpiredRecipientKeysWarning`), preserving
    the existing type-based test expectations; several kinds combine into
    `ComposeSecurityWarning`.
  - Only surfaced when `composeContext.shouldEncrypt` is set, same as the
    existing warnings.

### 2. Banner expired key warning with expiration date

- `SignerContext` gained an optional `keyExpiration: Date?` field (the
  wire-format doc requires new fields to stay optional; a legacy-payload
  decode test covers this).
- `MessageSecurityCore.decodedMessage(forMessageData:)` fills it from the
  signing key's expiration date (best-effort keyring lookup by the signer
  fingerprint librnp reports).
- `mapSignerTrust(status:trust:keyExpiration:)` gained a defaulted third
  parameter (source-compatible); the three `.expired` cases append
  "The key expired on \<date\>." to the existing detail text when the date
  is known. Without a date the detail text is byte-identical to before.
- `MailSecurityBannerView` passes `signer.context?.keyExpiration` through.

### 3. Fetch/update actions (`MessageSecurityCore`)

- **Fetch new key**: the existing `fetchRecipientKey(for:)` already
  implements the flow (WKD → VKS lookup by email, import, substitution
  guard). Importing a refreshed copy of an already-known key merges the new
  self-signatures, clearing the expired state — covered by a new end-to-end
  test (stale expired key in the client keyring, owner extends expiry on the
  "server", client fetches and the warning clears, fingerprint unchanged).
- **Update key**: new `extendRecipientKeyExpiry(for:to:)` extends the
  primary key's and all subkeys' expiry when the keyring holds the secret
  key. Throws `RecipientKeyUpdateError.keyNotOwned` for public-only keys
  (only the owner can re-sign), `.keyNotFound` for unknown recipients, and
  `.invalidExpiryDate` for past dates. It intentionally mirrors
  `KeyLifecycle.extendExpiry`, which this module cannot import (KeyLifecycle
  depends on MailSecurityEngine, not vice versa — importing it would be a
  circular dependency). No `MailSecurityEngine` API was changed.

## Files changed

- `Sources/MailSecurityEngine/ExpiredKeyWarning.swift` (new)
- `Sources/MailSecurityEngine/MessageSecurityCore.swift`
- `Sources/MailSecurityEngine/RecipientKeyFetch.swift`
- `Sources/MailSecurityEngine/SignerContext.swift`
- `Sources/MailSecurityEngine/SignerTrustViewModel.swift`
- `Sources/MailSecurityUI/MailSecurityBannerView.swift`
- `Tests/MailSecurityEngineTests/ExpiredKeyWarningTests.swift` (new, 18 tests)
- `Tests/MailSecurityUITests/MailSecurityBannerExpiredTests.swift` (new, 2 tests)

## Tests added

- Compose warning: expired key warns (with date, fetch/update guidance),
  suppressed when not encrypting, not flagged for non-expired keys, sender
  never flagged, expiry warning wins over unverified, combined
  expired+missing case, expired encryption-subkey-only case.
- Update action: owned key extended (primary + subkey, warning clears),
  unowned/unknown/past-date rejections.
- Fetch action: refreshed key clears the warning (`fetchRecipientKey`
  round-trip through the mock keyserver).
- Banner: `mapSignerTrust` expired detail includes the date (all trust
  states) and is unchanged without one; `SignerContext` round-trip and
  legacy-payload decode; `decodedMessage` attaches the signer key's
  expiration; banner view renders the date and falls back to the original
  detail without one.

## Verification

1. `PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib`
   — **passed**: 219 tests, 0 failures (includes the 20 new tests).
   Snapshot PNG warnings are non-fatal and machine-specific, as documented
   in `MailSecurityBannerSnapshotTests.swift`.
2. `PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme RNP build CODE_SIGNING_ALLOWED=NO`
   — **BUILD SUCCEEDED** (on this branch, with the change).
3. `PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO`
   — **BUILD SUCCEEDED**.

### Note on the first RNP build attempts

The first `xcodebuild -scheme RNP` run failed in the untouched
`Sources/RnpMailUI/ImportKeyForm.swift` with
`<unknown>:0: error: cannot load module 'RNP' as 'Rnp'` — the RNP app
target's module colliding with the package's `Rnp` module from stale
products in `Swift-Rnp/Build` (case-insensitive filesystem). Resolved with
`xcodebuild ... clean` followed by a rebuild; unrelated to this change (no
module names or project files were touched).

Two subsequent attempts died in the Xcode toolchain itself
(`swift-frontend` / `ld` signal 11) while compiling generated asset symbols
and linking the app; `main` built fine in between, and a plain retry on
this branch then succeeded — intermittent toolchain crashes on this
machine, not caused by the change.

## Notes / follow-ups

- The compose warning text points to the RNP app's Recipients tab for the
  fetch, mirroring the existing `MissingRecipientKeysHint` wording; the
  container app already exposes fetch-from-keyserver and expiry-extension
  UI (`KeysManager.extendExpiry`, `discoverByEmail`).
- Auto-fetch (`getEncodingStatusWithAutoFetch`) deliberately still only
  fetches *missing* keys; extending it to refresh expired keys would be a
  small follow-up if desired.
- `extendRecipientKeyExpiry` duplicates ~15 lines of
  `KeyLifecycle.extendExpiry` because of the module dependency direction;
  if more lifecycle operations are ever needed compose-side, consider
  moving the shared primitives into MailSecurityEngine.
