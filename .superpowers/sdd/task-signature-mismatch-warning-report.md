# Task report: signature mismatch warning with reason and actions

Branch: `feat/signature-mismatch-warning` (from `main`)

## Goal

When a signature is invalid or mismatched (tampered message, wrong key,
revoked key), the security banner explains *why* verification failed and
offers concrete actions: view the signer key, fetch an unknown signer key,
and report the issue.

## Key finding from probing

A scratch probe (deleted afterwards) ran three scenarios through
`engine.decode` with librnp v0.18.1:

- **Tampered content** → status `.invalid`, signer fingerprint reported.
- **Revoked signing key** (revoked after signing) → status `.invalid`,
  fingerprint reported. The revoked-key reason is reachable end-to-end.
- **Expired signing key** (1-second expiry, verified after expiry) → status
  `.valid`: librnp still verifies signatures made before the key expired.
  An expired key therefore never produces `.invalid` in practice; the
  `keyExpired` reason is a defensive mapping covered by unit tests only.

Also: librnp reports `.signerUnknown` (not `.invalid`) when the key is not
in the keyring, so an `.invalid` signature without a fingerprint is the
"key unknown / revoked elsewhere" catch-all rather than the common case.

## What was implemented

### 1. Reason classification (`MailSecurityEngine`)

- New `Sources/MailSecurityEngine/InvalidSignatureWarning.swift`:
  `InvalidSignatureReason` (`content-mismatch`, `key-unknown`, `key-revoked`,
  `key-expired`), a string-raw-value enum mirroring how
  `RnpSignatureStatus` is carried in `SignerContext`.
- `MessageSecurityCore.decodedMessage(forMessageData:)` classifies every
  `.invalid` signer via the new private `invalidSignatureReason(for:)`:
  - no fingerprint from the detailed verification result
    (`Rnp.verifyDetailed` / `verifyDetachedDetailed` via the engine's
    `signerInfos`) → `.keyUnknown`;
  - signing key found in the keyring and `isRevoked` → `.keyRevoked`;
  - key expired (`Self.expirationDate(of:)`, shared with the expired-key
    feature) → `.keyExpired`;
  - otherwise → `.contentMismatch`.
- `SignerContext` gained an optional `invalidReason: String?` field (the
  wire-format doc requires new fields to stay optional; a legacy-payload
  decode test covers this).

### 2. Richer invalid detail (`mapSignerTrust`)

- `mapSignerTrust(status:trust:keyExpiration:)` gained a defaulted fourth
  parameter `invalidReason: InvalidSignatureReason? = nil`
  (source-compatible).
- The `.invalid` detail text now names the cause:
  - `.contentMismatch`: "The signature does not match the message content;
    the message may have been modified after signing."
  - `.keyUnknown`: "The signature was made by an unknown or revoked key, so
    it could not be verified."
  - `.keyRevoked`: "The signature was made by a key that has been revoked.
    Do not trust this message."
  - `.keyExpired`: "The signature was made by an expired key." plus
    "The key expired on \<date\>." when the date is known.
  - no reason (legacy contexts): the original "The signature does not
    verify; the message may have been modified." — byte-identical.
- `.invalid` now returns `reviewDeepLink: true` except when the reason is
  `.keyUnknown` (no key to show); the banner still gates the button on a
  known fingerprint, so this implements the "View signer key" action.

### 3. Banner actions (`MailSecurityUI`)

- **View signer key**: the existing "View Key in RNP" deep link
  (`rnpmail://review/<fpr>`) now appears for invalid signatures with a
  known key (driven by the `reviewDeepLink` change above).
- **Fetch signer key**: previously only `.signerUnknown`; now also offered
  for `.invalid` signatures whose context carries no fingerprint (unknown
  key), using the existing email-fallback identifier and fetch flow.
- **Report Issue**: new button shown for every `.invalid` signer; opens a
  pre-filled GitHub issue
  (`https://github.com/rnpgp/rnp-mailapp-extension/issues/new?title=…&body=…`)
  whose body carries the signer label, signature status, failure reason,
  and fingerprint (or "unknown"). The URL is built by the internal static
  `MailSecurityBannerView.reportIssueURL(for:)` so it is unit-testable
  without `NSWorkspace`.

No `MailSecurityEngine` API was changed (additions are defaulted/optional),
and no MailKit-side changes were needed: the banner's new actions need no
host wiring beyond what `MessageSecurityViewController` already passes.

## Files changed

- `Sources/MailSecurityEngine/InvalidSignatureWarning.swift` (new)
- `Sources/MailSecurityEngine/SignerContext.swift`
- `Sources/MailSecurityEngine/SignerTrustViewModel.swift`
- `Sources/MailSecurityEngine/MessageSecurityCore.swift`
- `Sources/MailSecurityUI/MailSecurityBannerView.swift`
- `Tests/MailSecurityEngineTests/MailSecurityEngineTests.swift` (exhaustive
  mapping test: the three `.invalid` rows now expect
  `reviewDeepLink == true`, the deliberate behavior change above)
- `Tests/MailSecurityEngineTests/InvalidSignatureWarningTests.swift`
  (new, 12 tests)
- `Tests/MailSecurityUITests/MailSecurityBannerInvalidTests.swift`
  (new, 13 tests)

## Tests added

- Mapping: per-reason detail text across trust states, date appended for
  `.keyExpired`, original text kept without a reason, review-link rules
  (offered for all reasons except `.keyUnknown`).
- Plumbing: `SignerContext` round-trips `invalidReason`; legacy payloads
  without the field still decode.
- Decode-time classification (end-to-end through
  `MessageSecurityCore.decodedMessage`): tampered message →
  `content-mismatch`; revoked signer key → `key-revoked`; valid signature →
  no reason attached.
- Banner: reason text rendered for each reason; original detail without a
  reason; "View Key in RNP" present for invalid+known key and absent for
  `key-unknown`; "Fetch signer key" present (and tappable, invoking the
  wired action) for invalid+unknown key, absent with a known key; "Report
  Issue" present for invalid, absent for valid; report URL pre-fills
  status/reason/fingerprint and degrades to "unknown" without them.

## Verification

1. `PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib`
   — **passed**: 244 tests, 0 failures (includes the 25 new tests; 219
   before). Snapshot PNG warnings are non-fatal and machine-specific (they
   fire for untouched snapshots too), as documented in
   `MailSecurityBannerSnapshotTests.swift`.
2. `PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme RNP build CODE_SIGNING_ALLOWED=NO`
   — **BUILD SUCCEEDED**.
3. `PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO`
   — **BUILD SUCCEEDED**.

## Notes / follow-ups

- The snapshot PNG references for the `single-invalid-*` rows still depict
  the pre-change banner (no "Report Issue" button, no "View Key in RNP");
  they warn but do not fail. Re-recording is machine-specific, so they were
  left alone, matching the expired-key task's precedent.
- `keyExpired` is unreachable with librnp v0.18.1 (expired-key signatures
  verify as `.valid`); the case exists so a future librnp that reports
  `.invalid` for them gets a sensible message, and the text is unit-tested
  at the mapping level.
- The reason is classified once at decode time against the live keyring;
  a key revoked *after* the message was decoded will not retroactively
  change a banner Mail has already rendered (same limitation as the
  existing trust state).
