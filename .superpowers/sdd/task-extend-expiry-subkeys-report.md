# Task Report: Extend expiry updates subkeys, not just the primary

**Branch:** `fix/extend-expiry-subkeys` (from `main`)
**Commit:** `7b38d44` — KeyLifecycle: extend expiry on subkeys as well as the primary

## Problem

Feature-audit gap P2-1: `KeyLifecycle.extendExpiry` re-signed only the primary
key's self-signature. Subkeys kept their old expiry, so extending expiry did
not rescue a key whose encryption subkey had expired — even though
`KeyManager.generateKey` sets the expiration on the primary *and* all
subkeys, and the UI ("extendExpiry.title") implies the whole key is extended.

## Change

### `Sources/KeyLifecycle/KeyLifecycle.swift`

`extendExpiry(for:newDate:)` now iterates the key's subkeys after updating the
primary and sets the same absolute expiration date on each one. Because
OpenPGP stores expiration as seconds from each key's own creation time (and
subkeys can have different creation times, e.g. after a rotation), the
seconds value is computed per subkey from its own `creationDate`:

```swift
for subkey in try key.subkeys {
    let subkeyCreation = try subkey.creationDate
    let subkeyExpirySeconds = UInt32(max(0, newDate.timeIntervalSince1970 - subkeyCreation.timeIntervalSince1970))
    try subkey.setExpirationSeconds(subkeyExpirySeconds)
}
```

The public API is unchanged; the doc comment was updated to describe the new
behavior.

### `Tests/KeyLifecycleTests/KeyLifecycleTests.swift`

New test `testExtendExpiryRescuesExpiredEncryptionSubkey`:

1. Generates an RSA key with `expirationSeconds: 1` (primary and encryption
   subkey both expire ~1s after creation).
2. Waits until the subkey's `expirationDate` is actually in the past
   (~1.5s sleep, computed from the reported expiry).
3. Asserts the encryption subkey is expired.
4. Calls `extendExpiry` with a date ~2 years out.
5. Asserts the subkey's expiration now matches the new date (±10s) and is in
   the future, i.e. the subkey is no longer expired.

## UI impact

None required. The extend-expiry sheet
(`Swift-Rnp/MailExtensionsContainer/Model/KeysManager.swift:190`) calls
`lifecycle.extendExpiry(for:newDate:)`; the signature is unchanged, and both
Xcode schemes build. The sheet's displayed expiration comes from re-listed
key info, which now reflects the subkey re-signatures as well.

## Verification

1. `PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib`
   → **167 tests, 0 failures** (exit 0). New test also run in isolation:
   passed in 1.577s.
2. `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO` (with `Vendor/pkgconfig`)
   → **BUILD SUCCEEDED**.
3. `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme "Ribose container" build CODE_SIGNING_ALLOWED=NO` (with `Vendor/pkgconfig`)
   → **BUILD SUCCEEDED**.

## Notes / concerns

- The new test sleeps ~1.5s to let a real 1-second expiry lapse; this keeps
  the test honest (it verifies an actually-expired subkey) at a small runtime
  cost.
- Subkeys whose creation time is after `newDate` are clamped to 0 seconds
  (never expires) by the existing `max(0, …)` pattern; unreachable in practice
  since `newDate` must be in the future.
