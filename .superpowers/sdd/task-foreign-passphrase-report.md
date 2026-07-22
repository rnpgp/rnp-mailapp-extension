# Task report: Foreign passphrase support for imported secret keys

Branch: `feat/foreign-passphrase` (from `main`)
Date: 2026-07-22

## Goal

Imported secret keys protected by a *foreign* passphrase (different from the
keyring passphrase) become usable: the container app prompts for the key's
passphrase, verifies it against the key, and either stores it in the Keychain
under the key's fingerprint or re-protects the key with the keyring
passphrase. The Mail extension resolves stored per-key passphrases at crypto
time, so signing/decryption with such keys works unattended afterwards.

## Design

librnp calls the FFI passphrase callback with the handle of the key being
unlocked. The pipeline built on that:

1. **`Rnp.KeyedPassphraseProvider`** (new, additive): `(context, keyFingerprint?) -> String?`.
   The C callback (`rnpPasswordCallback`) now resolves the handle to a
   fingerprint — subkeys resolve to their *primary* key's fingerprint via
   `rnp_key_get_primary_fprint` (it fails on primary keys, in which case the
   key's own fingerprint is used) — so per-key passphrases can be stored
   against the primary key fingerprint. The legacy `PassphraseProvider` init
   is kept as a convenience wrapper; no existing caller changed behavior.
2. **`RnpKey` wrappers**: `isProtected`, `unlock(password:) -> Bool`
   (`rnp_key_unlock`; `false` on bad password), `protect(password:)`
   (`rnp_key_protect` with librnp defaults).
3. **`KeychainPassphraseStore`**: per-key items in the same service with
   account `key-passphrase.<FINGERPRINT>` — `passphrase(forKeyFingerprint:)`,
   `setPassphrase(_:forKeyFingerprint:)`, `removePassphrase(forKeyFingerprint:)`;
   `reset()` now also wipes per-key items; `resolvingProvider()` returns a
   keyed provider that prefers a per-key entry and falls back to the shared
   keyring passphrase.
4. **`KeyManager`** (engine API unchanged; additive only):
   - new designated init taking `Rnp.KeyedPassphraseProvider` (old init
     delegates);
   - `LockedSecretKeyInfo` (fingerprint + primary user ID);
   - `lockedSecretKeys(keyringPassphrase:among:)` — reports protected secret
     keys the keyring passphrase cannot unlock (probe covers primary +
     subkeys; public-only and unprotected keys are skipped);
   - `unlockSecretKey(fingerprint:passphrase:)` — verifies a passphrase
     against every protected secret part;
   - `reprotectSecretKey(fingerprint:currentPassphrase:newPassphrase:)` —
     unlocks all parts, re-protects with the new passphrase, persists the
     keyrings; throws `KeyManagerError.wrongPassphrase` on a bad passphrase.
5. **Container app**: `KeysManager.importKeys` detects foreign-passphrase
   keys among the imported ones and queues `foreignPassphraseRequests`;
   `ContentView` presents a sheet (`ForeignPassphraseSheet`/`Form`) showing
   the key's user ID and fingerprint, with a passphrase field, a
   "re-protect with the keyring passphrase" checkbox (the optional
   re-protect feature), Unlock/Skip buttons, and an inline wrong-passphrase
   error. Queued requests re-render in place. Key deletion drops the stored
   per-key passphrase.
6. **MailPlugin**: `MessageSecurityHandler` now builds its engine from
   `KeychainPassphraseStore.resolvingProvider()` via the keyed `KeyManager`
   init (the `MailSecurityEngine` crypto API was not touched).

## Files changed

- `Sources/Rnp/Rnp.swift` — `KeyedPassphraseProvider`, keyed init (designated),
  legacy init now convenience; passphrase callback resolves key fingerprint
  (primary for subkeys); `generateSubkey` uses the keyed provider.
- `Sources/Rnp/RnpKey.swift` — `isProtected`, `unlock(password:)`,
  `protect(password:)`.
- `Sources/MailSecurityEngine/KeychainPassphraseStore.swift` — per-key
  storage/retrieval/deletion, `resolvingProvider()`, `reset()` wipes per-key
  items.
- `Sources/MailSecurityEngine/KeyManager.swift` — keyed-provider init,
  `LockedSecretKeyInfo`, `lockedSecretKeys`, `unlockSecretKey`,
  `reprotectSecretKey`, `KeyManagerError.wrongPassphrase`.
- `Swift-Rnp/MailExtensionsContainer/Model/KeysManager.swift` — keyed
  provider wiring, foreign-passphrase request queue,
  `storeForeignPassphrase` / `reprotectForeignKey` / `skipForeignPassphrase`,
  per-key passphrase cleanup on delete.
- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentViewModel.swift` —
  `foreignPassphraseRequest`, `resolveForeignPassphrase`, `skipForeignPassphrase`.
- `Swift-Rnp/MailExtensionsContainer/View/ContentView/ContentView.swift` —
  prompt sheet presentation + `ForeignPassphraseSheet`/`ForeignPassphraseForm`.
- `Swift-Rnp/MailExtensionsContainer/Resources/Localizable.xcstrings` —
  7 new keys (`button.skip`, `foreignPassphrase.*`) with all 11 locales
  (non-English marked `needs_review`, matching existing entries).
- `Swift-Rnp/MailPlugin/MessageSecurityHandler.swift` — keyed resolving
  provider for the extension engine.
- `Tests/RnpTests/RnpTests.swift` — keyed-provider fingerprint delivery test;
  key protection (unlock/protect) round-trip test.
- `Tests/MailSecurityEngineTests/ForeignPassphraseTests.swift` — new suite
  (7 tests): detection after import, public-only/own-key exclusion,
  passphrase verification, re-protect flow (incl. wrong-passphrase rejection
  and persistence across manager instances), runtime sign+decrypt of a
  foreign key via the keyed provider (asserts the primary fingerprint is
  delivered), Keychain per-key storage/overwrite/delete/reset, resolving
  provider precedence.
- `docs/usage.md`, `docs/faq.md`, `docs/SECURITY-MODEL.md` — replaced stale
  "no per-key passphrase prompt" caveats with the new behavior; added the
  per-key passphrase Keychain item to the assets table.

## Verification

1. `PKG_CONFIG_PATH=... swift test -Xlinker -rpath -Xlinker .../lib`:
   **301 tests, 0 failures** (executed twice with full logs; the very first
   run reported 1 transient failure whose detail was lost to the `tail -40`
   pipe — a third run was launched to confirm flakiness vs. regression; see
   Concerns).
   - `RnpTests`: 14/14 pass (incl. 2 new).
   - `ForeignPassphraseTests`: 7/7 pass.
2. `xcodebuild -scheme RNP build CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
3. `xcodebuild -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.

## Notes / follow-ups

- The prompt appears only in the container app; Mail itself never prompts
  (documented in `docs/usage.md` known limitations). A key whose prompt was
  skipped stays locked until re-import triggers the prompt again.
- Onboarding imports queue the same requests; the prompt sheet appears after
  the onboarding sheet closes (SwiftUI single-sheet limitation).
- Snapshot tests emit machine-specific font-rendering warnings on this
  machine, as before; they are warnings, not failures.
