# Task 04 — Key management UX (container app)

Status: in progress · Milestone: M2 · Depends on: 01

## Goal

Make the container app a complete, delightful OpenPGP key manager: generate,
import, inspect, export, delete — with onboarding and Touch ID.

## Context / existing base

- `MailSecurityEngine.KeyManager` already does: generate (RSA/ECDSA JSON),
  import, export, list, delete, recipient resolution, lock-serialized keyring
  dir. The container app (PR #13) has basic generate/import/export/delete
  wiring. `Rnp` wrapper has `RnpKey.fingerprint/userIDs/primaryUserID/hasSecret`,
  `Rnp.allUserIDs()`, `Rnp.remove(key:)`.
- The following wrapper/metadata work is ALREADY DONE in this session and must
  be preserved/used:
  - `RnpKey.algorithm`, `bits`, `curve`, `creationDate`, `expirationSeconds`,
    `validTill`, `isRevoked`, `revocationReason`, `subkeys`, `revoke()`,
    `exportRevocation()`, `RevocationCode`.
  - `KeyInfo` extended with `algorithm`, `bits`, `creationDate`, `expirationDate`,
    `isRevoked`, `subkeyCount`, `algorithmLabel`, `isExpired`, `daysUntilExpiry`.
  - `KeyManager.listKeys()` populates the metadata above.
  - `KeysListView` already shows algorithm label and expiry/revocation badges.

## What remains to implement

1. **Key detail sheet/view**
   - Reachable by double-clicking or selecting a key in the list and a toolbar
     "Info" button.
   - Shows: primary user ID, full fingerprint (grouped, copy button), all user
     IDs, subkeys table (algo, bits/curve, created, expiry, capabilities).
   - Actions: export public key, export secret key (encrypted, with
     confirmation), delete. Include placeholders/stubs for "Extend expiry" and
     "Revoke" that show an alert "Not yet implemented — see task 05".
   - Use the existing `KeyInfo` for the primary key; add a `SubkeyInfo` type in
     `MailSecurityEngine` if needed and expose it via `KeyManager`.

2. **Onboarding flow** (first launch only)
   - 3 screens: welcome → create or import → done.
   - "Create new key" screen: name+email, Ed25519 default with RSA-3072
     "maximum compatibility" option, expiry 2y default, passphrase with strength
     meter, "Save to Keychain with Touch ID" toggle default ON.
   - "Import existing" screen: file/paste (task 06 fetch-by-email is a stub
     placeholder).
   - "Done" screen: note that a revocation certificate was saved, and offer
     "Publish public key" (stub deep-link for task 06).
   - Detect first launch; show onboarding as a sheet over `ContentView` when the
     keyring is empty on launch. Provide a way to re-open it from the Help menu.

3. **Touch ID Keychain ACL**
   - Extend `KeychainPassphraseStore` (in `Swift-Rnp/Shared`) so that when the
     "Touch ID" toggle is on it stores the passphrase with
     `SecAccessControlCreateWithFlags(.biometryCurrentSet, .userPresence)`.
   - Provide a fallback path: if Touch ID storage is unavailable or fails,
     store without biometry (current behavior) and surface a non-fatal warning
     in the UI once.
   - Keep `sharedPassphrase()` non-throwing; the engine depends on it.

4. **Drag-drop + clipboard import**
   - Add drag-drop file import onto the key list / window (NSViewRepresentable
     or SwiftUI `.onDrop` for macOS 13+).
   - Auto-detect clipboard containing `-----BEGIN PGP PUBLIC KEY BLOCK-----` on
     app activation and offer an import sheet (can be disabled via user
     default).

5. **Recipients tab separation**
   - Split `ContentView` into a tabbed interface: "My Keys" (keys with
     `hasSecret`) and "Recipients" (public-only keys).
   - Both tabs share the key detail view, but the Recipients detail hides
     secret-key actions and shows a stub "Unverified" trust badge (task 07).

6. **Tests**
   - Add `MailSecurityEngineTests` that round-trip `KeyInfo` metadata from a
     generated key.
   - Add a UI test (or at least a testable `OnboardingView` preview/unit test)
     that asserts the onboarding view renders and the generate-key sheet can be
     created.
   - Ensure `swift test` passes against both local librnp installs.

## Build / test commands

```sh
# Package tests against a local librnp (both installs must pass)
PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig \
  swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib

PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/main/lib/pkgconfig \
  swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/main/lib

# Xcode mail extension build (no signing)
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO
```

## Acceptance criteria

- New user: launch → key created → public key exported, in <5 minutes,
  without reading docs.
- All key metadata displayed matches `rnp --list-keys`/GnuPG for the same
  keyring (spot-check one RSA and one Ed25519 key).
- Passphrase never touches UserDefaults/disk; Keychain entry has Touch ID ACL.
- `swift test` green on both librnp installs; CI green.

## Constraints

- All logic that can live outside MailKit MUST live in SwiftPM targets and be
  covered by `swift test`.
- No force-unwraps in library code.
- Errors shown in UI as human sentences + recovery action (never raw rnp codes).
- Secret-key export must stay armored+passphrase-protected; never offer
  "export unprotected".
