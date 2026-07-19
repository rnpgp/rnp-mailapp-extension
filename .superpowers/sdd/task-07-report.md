# Task 07 Report: Trust & key verification

## Status

DONE

## Summary

Implemented the trust and key-verification infrastructure for the swift-rnp mail extension. The work closes all acceptance criteria from the task brief:

- New `TrustStore` SPM target with TOFU first-seen, manual verify, key-change conflict detection, and Ed25519-signed JSON persistence with tamper detection.
- `KeyManager` notes seen keys on import; `MailSecurityEngine.encode` throws `.trustConflict(recipient)` when a recipient has an unresolved key change.
- Container app shows per-key trust badges, a "Mark as verified" action, a trust-conflicts banner, and handles `rnpmail://review/<fpr>` deep links.
- Mail extension view controller maps `(RnpSignatureStatus, TrustState)` to a view model and shows per-signer trust next to MailKit's banner.
- README "Trust model" section explains TOFU, manual fingerprint verification, key-change warnings, and the deliberate no-web-of-trust scope cut.
- `TrustStoreTests` is wired into `Package.swift` and runs with `swift test`.

## Commits

- `cde0005` feat: add TrustStore SPM target with signed JSON persistence
- `e5ae9b2` feat: wire TrustStore into KeyManager, block encryption on unresolved conflicts, add signer-trust mapping
- `cdb85fb` feat: container app trust badge, verify action, conflict banner, and rnpmail://review deep link
- `a4abfdf` feat: surface per-signer trust in Mail extension security banner
- `a352686` docs+test: README trust model and tests for TrustStore, conflicts, and signer-trust mapping

## Files changed

- `Package.swift`
- `README.md`
- `Sources/Rnp/Verification.swift`
- `Sources/TrustStore/TrustState.swift` (new)
- `Sources/TrustStore/TrustRecord.swift` (new)
- `Sources/TrustStore/TrustConflict.swift` (new)
- `Sources/TrustStore/TrustStore.swift` (new)
- `Sources/MailSecurityEngine/KeyManager.swift`
- `Sources/MailSecurityEngine/MailSecurityEngine.swift`
- `Sources/MailSecurityEngine/SignerTrustViewModel.swift` (new)
- `Sources/RnpMailUI/KeyDetailView.swift`
- `Swift-Rnp/MailExtensionsContainer/Info.plist`
- `Swift-Rnp/MailExtensionsContainer/Model/KeysManager.swift`
- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentView.swift`
- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentViewModel.swift`
- `Swift-Rnp/MailPlugin/MessageSecurityHandler.swift`
- `Swift-Rnp/MailPlugin/MessageSecurityViewController.swift`
- `Tests/TrustStoreTests/TrustStoreTests.swift` (new)
- `Tests/MailSecurityEngineTests/MailSecurityEngineTests.swift`

## Verification

### Swift Package Manager tests

```sh
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig \
  swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib
```

Result: **93 tests, 0 failures**.

New tests added:
- `TrustStoreTests` (13 tests): state transitions, conflict detection, persistence, tamper detection, schema version.
- `MailSecurityEngineTests.testTrustConflictBlocksEncryption`
- `MailSecurityEngineTests.testMarkVerifiedAllowsEncryptionAfterConflict`
- `MailSecurityEngineTests.testSignerTrustMappingExhaustive`

### Xcode builds

```sh
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig \
  xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**.

```sh
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig \
  xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme "Ribose container" build CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**.

## Notes and concerns

- The task brief referenced at `.superpowers/sdd/task-07-brief.md` did not exist in this worktree; I used the task description in the prompt and `TODO.impl/07-trust-verification.md` as the source of truth.
- The core trust infrastructure described as "already in place" was not present in the repository, so I implemented it from scratch as part of this task.
- `RnpSignatureStatus` was made `RawRepresentable` with `String` so it can be serialized into `MEMessageSigner.context` for the Mail extension view controller. This is a backward-compatible change.
- `KeyManager.deleteKey` was fixed to pass `secret: false` when the key has no secret material; this resolved a librnp "Bad parameters" failure in `testMarkVerifiedAllowsEncryptionAfterConflict` when retiring a public-only imported key.
- The Mail extension view controller uses `MessageSecurityHandler.SignerContext` (internal to the MailPlugin target) to carry fingerprint and status from the decode path to the banner UI.
- The deep-link URL scheme `rnpmail` is registered in `Swift-Rnp/MailExtensionsContainer/Info.plist` and handled via `.onOpenURL` in `ContentView`.
