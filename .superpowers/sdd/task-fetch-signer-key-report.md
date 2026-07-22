# Task Report: Fetch signer key for unknown signers in the Mail banner

## Status

DONE

## Summary

When a signed message arrives whose signing key is not in the local keyring
("Unknown signer"), the Mail security banner now offers a **Fetch signer
key** action. Tapping it looks the key up on public keyservers — by
fingerprint first, falling back to the signer's email — imports it, and
re-decodes the message so the banner shows the refreshed signature status.
The `MailSecurityEngine` API is unchanged; the fetch primitive lives in
`MessageSecurityCore` (mirroring `fetchRecipientKey`), and the action is
wired through `MailSecurityUI` and `MessageSecurityViewController`, per the
task constraint.

- **Signer identification**: librnp reports *no* fingerprint for an unknown
  signer (RNP 0.18.1; asserted by the existing
  `testUnknownSignerReported`), so the fingerprint path alone would never
  fire in practice. `SignerContext` therefore gained an optional `email`
  field (the wire format stays backward compatible — optional fields decode
  from old payloads). `MessageSecurityCore.decodedMessage` fills it with the
  signing key's user-ID address when known, otherwise with the message's
  `From:` address — the signer is almost always the sender, so this is the
  practical lookup key for unknown signers.
- **Keyserver fetch by fingerprint**: `KeyServerService.discoverByFingerprint`
  now falls back from VKS (keys.openpgp.org, which only serves keys with
  verified user IDs) to the HKP keyservers in `HKPSServer.allCases`. The new
  `KeyServerService.discover(fingerprint:email:)` tries the fingerprint path
  first (it identifies the exact key) and then email discovery (WKD
  advanced → direct → VKS). Side effect: the container app's fetch sheet,
  which shares `discoverByFingerprint`, gains the HKPS fallback too.
- **Fetch + import**: `MessageSecurityCore.fetchSignerKey(fingerprint:email:)`
  discovers, imports via the existing `KeyManager.importKeys` path (TOFU /
  unverified trust, same as a manual import), and then applies a
  substitution guard: the keyring must afterwards hold the exact fingerprint
  asked for, or a key resolving to the queried address — a hostile or broken
  server cannot substitute somebody else's key (`.invalidResponse`).
- **Banner action**: `MailSecurityBannerView` shows "Fetch signer key" on
  `.signerUnknown` rows when the host supplied an action and an identifier
  (fingerprint or email) exists. While fetching, the button is disabled and
  reads "Fetching…"; on failure the banner rebuilds with the error inline
  and the button re-enabled for retry; on success the host replaces the
  banner with the re-verified content.
- **Re-decode**: `MessageSecurityHandler` stashes the raw data of the most
  recently decoded message (same decode-before-indicator guarantee the
  encryption-status fallback already relies on) and hands the view
  controller a fetch operation: fetch + import via the core, then re-decode
  and map the fresh signer labels/contexts. The view controller swaps its
  view for a rebuilt banner on success. Lookups are user-initiated (button
  click), so the privacy consent is explicit — no automatic network access
  was added.

## Commits

- `feat: signer key fetch flow in MessageSecurityCore and KeyServerService`
- `feat(mailplugin): Fetch signer key banner action with re-decode refresh`
- `test: signer key fetch flow and banner action tests`
- (this report) `docs: report for fetch signer key task`

## Files changed

- `Sources/MailSecurityEngine/KeyServerService.swift`: HKPS fallback in
  `discoverByFingerprint`; new `discover(fingerprint:email:)`.
- `Sources/MailSecurityEngine/SignerContext.swift`: new optional `email`
  field (doc comment records the fallback semantics).
- `Sources/MailSecurityEngine/SignerKeyFetch.swift` (new):
  `SignerKeyFetchResult`.
- `Sources/MailSecurityEngine/MessageSecurityCore.swift`: new
  `fetchSignerKey(fingerprint:email:)` with substitution guard; signer
  contexts now carry the signer email (user-ID address, else From: header).
- `Sources/MailSecurityUI/MailSecurityBannerView.swift`: "Fetch signer key"
  button for unknown signers, in-progress state, inline failure label,
  `SignerKeyFetchAction` / `SignerKeyFetchOutcome` types; new optional
  `onFetchSignerKey` initializer parameter (defaulted — existing call sites
  and tests unchanged).
- `Swift-Rnp/MailPlugin/MessageSecurityViewController.swift`: builds the
  banner action from a `SignerKeyFetch` operation; rebuilds the banner from
  `RefreshedBannerContent` on success.
- `Swift-Rnp/MailPlugin/MessageSecurityHandler.swift`: stashes
  `lastDecodedRawData` at decode time; `makeSignerKeyFetch` builds the
  fetch + re-decode operation.
- `Tests/MailSecurityEngineTests/SignerKeyFetchTests.swift` (new): 11 tests.
- `Tests/MailSecurityUITests/MailSecurityBannerFetchTests.swift` (new): 8
  tests.
- `Tests/MailSecurityUITests/MailSecurityBannerSnapshotTests.swift`: one
  structural + snapshot test for the fetch-button row; new reference
  `Tests/Fixtures/snapshots/single-signerUnknown-fetch.png`.

## Verification

### Swift Package Manager tests

```sh
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig \
  swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib
```

Result: **199 tests, 0 failures** (179 pre-existing + 20 new). The snapshot
PNG comparisons warn on this machine (font rendering is machine-specific;
pre-existing behavior, warnings only — `SNAPSHOT_STRICT=1` not set).

New tests:

- `SignerKeyFetchTests`: VKS by-fingerprint import; HKPS fallback; email
  fallback (fingerprint tried first, call order asserted on the mock);
  email-only resolution; wrong-fingerprint and wrong-address rejection
  (`.invalidResponse`); not-found; no identifiers → no network; end-to-end
  sign → decode (unknown signer, context carries From: email) → fetch →
  re-decode → `valid`; `SignerContext` email round-trip and decoding of
  legacy payloads without the field.
- `MailSecurityBannerFetchTests`: button visibility (fingerprint /
  email-only / no action / known signer / no identifier); action invoked
  with the signer + progress state; failure shows the error inline and
  restores the button; success does not surface an error.

### Xcode builds

```sh
PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig \
  xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme RNP build CODE_SIGNING_ALLOWED=NO
PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig \
  xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO
```

Both: **BUILD SUCCEEDED**, no warnings in changed files.

## Notes / follow-ups

- librnp gives no fingerprint for unknown signers in this version, so the
  email fallback (From: header) is the path that fires in practice; the
  fingerprint path is future-proofing for RNP versions that do report one.
  The From:-header heuristic assumes signer == sender, which holds for
  ordinary signed mail; mailing-list or third-party signatures could fetch
  the sender's key instead of the actual signer's. The substitution guard
  only checks address resolution on that path, so a wrong-but-matching key
  would be imported as unverified and the re-verify would still fail — a
  harmless dead end, but worth knowing.
- The banner's rebuilt view relies on Mail re-laying-out the extension view
  controller's view after `view` is swapped; this could not be exercised
  without Mail.app. If the banner does not resize after a successful fetch,
  setting `preferredContentSize` on the view controller is the fix.
- Fetches are user-initiated only; no throttling/caching was added (unlike
  compose auto-fetch). Repeated taps simply re-query.
- The fetch failure message is shown in English from
  `KeyServerError.localizedDescription`; the MailPlugin banner strings are
  not part of the container app's `Localizable.xcstrings` catalog, matching
  the existing banner buttons ("Copy Fingerprint", etc.).
