# Task 04 — Key management UX (container app)

## Status

**DONE**

All requested features were implemented and the required verification commands pass.

## Summary of changes

1. **Moved shared non-UI utilities into `MailSecurityEngine`**
   - `KeychainPassphraseStore.swift` and `AppGroup.swift` now live in `Sources/MailSecurityEngine` so they are covered by `swift test` and available to both the Mail extension and the container app.
   - Updated the Xcode project to stop compiling these files directly and rely on the Swift package instead.

2. **Added Ed25519 key generation**
   - `Rnp.ed25519KeyGenJSON(userid:expirationSeconds:)` generates an EDDSA primary key and an ECDH/Curve25519 encryption subkey.
   - `KeyAlgorithm.ed25519` is now the default in the UI.
   - `KeyManager.generateKey` accepts an optional `expirationSeconds` parameter.

3. **Added key detail metadata**
   - `RnpKey.keyID` and `RnpKey.capabilities`.
   - `SubkeyInfo` in `MailSecurityEngine` and `KeyManager.subkeys(for:)`.
   - `KeyManager.saveRevocationCertificate(fingerprint:)` writes an armored revocation certificate to the keyring directory.

4. **Touch ID Keychain ACL**
   - `KeychainPassphraseStore.setPassphrase(_:requiresBiometry:)` stores the passphrase with `SecAccessControlCreateWithFlags(.biometryCurrentSet, .userPresence)` when requested.
   - If biometric storage fails, it falls back to non-biometric storage and returns a non-fatal `KeychainWarning` that the UI can surface.
   - `sharedPassphrase()` remains non-throwing for the engine.

5. **Onboarding flow**
   - New `RnpMailUI` Swift package target with `OnboardingView`, `OnboardingViewModel`, `GenerateKeyForm`, `ImportKeyForm`, `PassphraseStrengthMeter`.
   - 3-page flow: welcome → create/import → done.
   - Ed25519 default, RSA-3072 option, 1y/2y/no-expiry, passphrase strength meter, Touch ID toggle default ON.
   - Done screen notes the saved revocation certificate and stubs task-06 publish/fetch actions.
   - Shown automatically when the keyring is empty and onboarding has not been completed; can be reopened from Help → Show Onboarding.

6. **Key detail sheet**
   - `KeyDetailView` in `RnpMailUI` shows primary user ID, full grouped fingerprint with copy, all user IDs, and a subkeys table.
   - Actions: export public key, export secret key (with confirmation), delete.
   - Stubs for extend expiry and revoke show an alert pointing to task 05.

7. **Drag-drop + clipboard import and recipient tabs**
   - `ContentView` uses a segmented picker for **My Keys** / **Recipients**.
   - `.onDrop` on the key list accepts files and pasted armored text.
   - `NSApplication.didBecomeActiveNotification` triggers optional clipboard PGP-block detection (toggleable via `autoDetectClipboardImport` user default).

8. **Tests**
   - `MailSecurityEngineTests` now round-trips RSA and Ed25519 `KeyInfo` metadata, checks subkey metadata, and verifies revocation certificate creation.
   - Added Keychain store/read and biometry-fallback tests.
   - `RnpMailUITests` verifies that `OnboardingView` and `GenerateKeyForm` render and that the onboarding view model advances through the flow.

9. **Xcode build fixes**
   - Added a fallback copy of the vendored `rnp` headers under `Sources/CRnp/rnp` and updated `shim.h` to use them when pkg-config is unavailable, so `xcodebuild` can build the Mail extension and container app without extra environment variables.

## Verification commands and output

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

Additional verification (not required by the brief):

```sh
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme "Ribose container" build CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**.

## Concerns

- **Vendored header fallback.** `Sources/CRnp/rnp` is a copy of the vendored framework headers with one local change (`#include "rnp_export.h"`). This lets Xcode build without pkg-config, but the copy must be kept in sync if `RNPFramework.xcframework` is rebuilt.
- **Touch ID user-presence prompts.** The ACL includes `.userPresence`, so reading the passphrase will prompt for authentication. The Mail extension may trigger this during background operations. `sharedPassphrase()` remains non-throwing; if authentication is cancelled it falls back to generating a new passphrase (pre-existing behavior). The UI only receives a warning when storage itself falls back.
- **Onboarding render test is shallow.** It instantiates the view in `NSHostingController` and checks the view is created; it does not inspect rendered text because the tests run without a host app.
- **Ed25519 JSON quirk.** librnp 0.18.1 rejects an explicit `"curve"` for the EDDSA primary key in `rnp_generate_key_json`, so the Ed25519 generator omits it and relies on the implicit Ed25519 curve.

## Files modified or created

### Modified

- `Package.swift`
- `Sources/CRnp/shim.h`
- `Sources/MailSecurityEngine/KeyManager.swift`
- `Sources/Rnp/Rnp.swift`
- `Sources/Rnp/RnpKey.swift`
- `Swift-Rnp/MailExtensionsContainer/MailExtensionsContainerApp.swift`
- `Swift-Rnp/MailExtensionsContainer/Model/KeysManager.swift`
- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentView.swift`
- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentViewModel.swift`
- `Swift-Rnp/Swift-Rnp.xcodeproj/project.pbxproj`
- `Tests/MailSecurityEngineTests/MailSecurityEngineTests.swift`

### Created

- `Sources/MailSecurityEngine/AppGroup.swift` (moved from `Swift-Rnp/Shared`)
- `Sources/MailSecurityEngine/KeychainPassphraseStore.swift` (moved from `Swift-Rnp/Shared`)
- `Sources/RnpMailUI/OnboardingView.swift`
- `Sources/RnpMailUI/OnboardingViewModel.swift`
- `Sources/RnpMailUI/GenerateKeyForm.swift`
- `Sources/RnpMailUI/ImportKeyForm.swift`
- `Sources/RnpMailUI/PassphraseStrength.swift`
- `Sources/RnpMailUI/PassphraseStrengthMeter.swift`
- `Sources/RnpMailUI/KeyDetailView.swift`
- `Tests/RnpMailUITests/OnboardingViewTests.swift`
- `Sources/CRnp/rnp/rnp.h`
- `Sources/CRnp/rnp/rnp_err.h`
- `Sources/CRnp/rnp/rnp_export.h`
- `Sources/CRnp/rnp/rnp_ver.h`

### Deleted

- `Swift-Rnp/Shared/AppGroup.swift`
- `Swift-Rnp/Shared/KeychainPassphraseStore.swift`
- `Swift-Rnp/Shared` (now empty)
