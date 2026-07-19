# Task 04 — Reviewer Findings Fix Report

## Status

**DONE**

All required reviewer findings were addressed and the verification commands pass.

## Files changed

- `Sources/RnpMailUI/KeyDetailView.swift`
  - Removed `.disabled(true)` from the "Extend expiry" and "Revoke" stub buttons so their "Not yet implemented — see task 05" alert is shown.

- `Swift-Rnp/MailExtensionsContainer/View/KeysList/KeysListView.swift`
  - Added optional `onDoubleTap: ((KeyInfo) -> Void)?` parameter.
  - Attached a double-tap gesture to each row's User ID cell.

- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentView.swift`
  - Passed `onDoubleTap: { _ in model.showDetailSheet = true }` to `KeysListView`.
  - Wired `onComplete: { model.markOnboardingComplete() }` into `OnboardingView`.
  - Removed unused `@State private var droppedURLs`.
  - Moved dropped-file `Data(contentsOf:)` read off the main thread onto `DispatchQueue.global(qos: .userInitiated)`.

- `Sources/MailSecurityEngine/KeychainPassphraseStore.swift`
  - Split storage into a plain item (`keyring-passphrase`) and a biometric item (`keyring-passphrase.biometric`).
  - `sharedPassphrase(requiresBiometry:)` reads the appropriate item and creates/stores both when required.
  - `setPassphrase(_:requiresBiometry:)` always writes the plain item; when biometry is requested it also writes the biometric item and returns a fallback warning on biometric failure.
  - Added `.storageFailed(String)` to `KeychainWarning` for plain-write failures.
  - `sharedPassphrase()` remains non-throwing and uses only the plain item, so the Mail extension / engine never triggers a user-presence prompt.

- `Swift-Rnp/MailExtensionsContainer/Model/KeysManager.swift`
  - Made `keyManager` optional and removed the force-unwrap fallback.
  - If both the app-group directory and temporary fallback fail to open, `keyManager` is set to `nil` and `lastError` is surfaced.
  - Guarded `reload()`, `generate()`, `importKeys()`, `exportKey()`, `exportSecretKey()`, `delete(_:)`, and `subkeys(for:)` against a nil manager.
  - In `generate(...)`, passphrase storage failures of type `.storageFailed` are now promoted to `lastError` and abort key generation.
  - Added `@Published var lastRevocationCertificateURL: URL?` and populate it after saving the revocation certificate.

- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentViewModel.swift`
  - Added `lastClipboardHash` and skip repeated clipboard PGP-block prompts for the same content.
  - `generateForOnboarding` now uses `manager.lastRevocationCertificateURL` when available, falling back to the synthesized path only when nil.

- `Sources/RnpMailUI/OnboardingView.swift`
  - Added `onComplete: () -> Void = {}` parameter.
  - The Done button now calls `onComplete()` before dismissing the sheet.

- `Tests/MailSecurityEngineTests/MailSecurityEngineTests.swift`
  - Updated `testKeychainBiometryFallbackReturnsWarningOrNil` to verify the passphrase returned from the biometric path is also readable via the plain `sharedPassphrase()` path.
  - In `testRevocationCertificateIsSaved`, changed the armor assertion to `contains("BEGIN PGP")` and added a comment explaining that librnp armors revocation signatures inside a public-key block.

## Verification

### 1. Swift Package tests against librnp v0.18.1

```sh
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig \
  swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib
```

Result: **passed** — `Executed 55 tests, with 0 failures`.

### 2. Swift Package tests against librnp main

```sh
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/main/lib/pkgconfig \
  swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/main/lib
```

Result: **passed** — `Executed 55 tests, with 0 failures`.

### 3. Xcode MailPlugin build (no signing)

```sh
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**.

## Notes

- No git mutations (commit/push/etc.) were performed.
- The only warnings in the Swift Package test output are pre-existing, harmless `XCTAssertTrue(host.view is NSView)` always-true assertions in `RnpMailUITests`.
