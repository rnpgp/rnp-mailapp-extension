# Task report: Touch ID runtime effect

Branch: `feat/touchid-runtime` (from `main`)
Commit: `5a176e4` — Require Touch ID to unlock the keyring when enabled in onboarding

## Root cause of "zero runtime effect"

Two independent defects made the onboarding Touch ID option inert:

1. **Invalid access-control flags.** `storeWithBiometry` called
   `SecAccessControlCreateWithFlags` with `[.biometryCurrentSet, .userPresence]`.
   macOS rejects that combination with `errSecParam` (-50): "userPresence can be
   combined only with applicationPassword and privateKeyUsage" (verified
   empirically). Creation therefore always failed, the code always returned a
   `.biometryFailed` warning, and the biometric item was never created.
2. **Two-item design.** Even when biometric storage had worked, the passphrase
   was also kept in a plain, unprotected item — and every read path
   (`sharedPassphrase()`, `resolvingProvider()`) used only the plain item, so
   nothing ever required Touch ID.

Also verified empirically on this machine: `SecItemAdd` with
`kSecAttrAccessControl` fails with `errSecMissingEntitlement` (-34018) in
unsigned processes, so biometric storage can only work in signed builds with
the keychain entitlements; unsigned dev/test builds must fall back.

## What changed

### `Sources/MailSecurityEngine/KeychainPassphraseStore.swift` (reworked)

- **Single source of truth.** `setPassphrase(_:requiresBiometry: true)` stores
  the passphrase ONLY in the biometric item (`.userPresence` access control,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) and deletes the plain item.
  `.userPresence` was chosen (the task allowed either): it is the only valid
  single constraint for this use, prompts for Touch ID, keeps the macOS login
  password as a system-level fallback, and survives fingerprint re-enrollment
  (unlike `.biometryCurrentSet`). `requiresBiometry: false` stores the plain
  item (`kSecAttrAccessibleWhenUnlocked`, unchanged) and deletes any biometric
  item.
- **Preflight + fallbacks.** `storeWithBiometry` first checks
  `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`;
  without usable biometry it returns `.biometryUnavailable` and the passphrase
  falls back to the plain item with a warning (nothing is lost). A stale
  biometric item is deleted in the fallback so it cannot shadow the new
  passphrase. `errSecMissingEntitlement` is mapped to a clear message for
  unsigned builds.
- **Tri-state read.** New `readSharedPassphrase(allowingAuthenticationUI:)`
  returns `.success / .notFound / .authenticationFailed(OSStatus)`, routing to
  the biometric item whenever it exists. Crucially, a cancelled/failed
  authentication is NOT treated as "missing": no new passphrase is created and
  the stored item is never overwritten (the old code would have silently
  replaced it with a fresh random one, bricking the keyring).
  `allowingAuthenticationUI: false` sets `kSecUseAuthenticationUISkip` and
  bypasses the cache, giving tests and the launch probe a prompt-free live view
  (a protected item answers `errSecInteractionNotAllowed`). The prompting read
  carries an `LAContext` with `localizedReason` "Unlock your RNP keyring".
- **Session cache + backoff.** A successful unlock is cached per process
  (keychain ACL authorization is per-process), so one Touch ID prompt unlocks
  the keyring for the app's lifetime. After a cancellation, `sharedPassphrase()`
  returns `""` without prompting for a 30 s backoff so a burst of librnp
  requests cannot spam prompts. `resolvingProvider()` now maps the locked state
  to `nil`, which librnp treats as "abort the operation" — the graceful path.
- **Manual-entry support.** `cacheVerifiedPassphrase(_:)` lets the container
  app unlock a process with a passphrase it verified itself, without touching
  (downgrading) the protected item. New `isBiometricProtectionEnabled`
  (never prompts) and `PassphraseReadResult` / `KeychainWarning.authenticationRequired`.
  Public API stays source-compatible: `sharedPassphrase()`,
  `sharedPassphrase(requiresBiometry:)` (now also migrates a plain passphrase
  behind Touch ID), `setPassphrase`, per-key APIs, `reset()`, and
  `resolvingProvider()` keep their signatures; `MailSecurityEngine`/`KeyManager`
  are untouched. `reset()` also clears the session state.

### Container app

- `KeysManager` (`Swift-Rnp/MailExtensionsContainer/Model/KeysManager.swift`):
  new `@Published keyringLocked`, probed at launch WITHOUT showing a prompt
  (the app never surprises the user with a Touch ID dialog on startup);
  `unlockKeyring()` (Touch ID prompt from a background queue, result applied
  on main); `unlockKeyringManually(passphrase:)` which first verifies the
  typed passphrase against the secret keys (`KeyManager.unlockSecretKey`, a
  non-persisting check) and then only fills the session cache — a typo can
  never overwrite the Keychain item, and protection is never downgraded.
  `detectForeignPassphraseKeys` and `reprotectForeignKey` now bail out with a
  clear locked state instead of misbehaving on the empty (locked) passphrase.
- `ContentViewModel`: `keyringLocked`, `unlockKeyringWithTouchID()`,
  `unlockKeyringManually(_:)`, `showKeyringUnlockSheet`.
- `ContentView`: a "keyring locked" banner opens the new `KeyringUnlockSheet`
  (Touch ID button + manual passphrase field with wrong-passphrase feedback;
  auto-dismisses on unlock). 8 new localization keys × 11 languages added to
  `Localizable.xcstrings` (en translated, others marked needs_review, matching
  the catalog's convention).

### Mail extension

No code change was needed beyond the store/provider behavior; the adapter's
documentation now states the contract
(`Swift-Rnp/MailPlugin/MessageSecurityHandler.swift`): the first passphrase
read in the extension process shows the system Touch ID prompt over Mail;
cancelling fails that sign/decrypt gracefully (provider returns nil, the error
is recorded for the banner), the backoff prevents prompt spam, and unlocking
in the container app does not unlock the extension's process.

### Docs

- `docs/SECURITY-MODEL.md`: keychain bullet rewritten for the single-item
  biometric design; boundary note now covers the Mail extension prompt, the
  graceful cancel path, and the verified manual fallback.
- `docs/usage.md`: "Passphrases and the Keychain" explains the runtime
  behavior (locked keyring on launch, manual fallback, extension prompts,
  unsigned-build degradation).

## Tests

New `Tests/MailSecurityEngineTests/KeychainPassphraseStoreTests.swift` (7
tests, all passing): plain round-trip without biometry; biometric storage
either enforces authentication (no plain copy; no-UI read refused) or falls
back with a warning; a refused read leaves storage untouched (no creation, no
overwrite); disabling biometry restores plain storage; the manual-unlock cache
does not downgrade protection; `reset()` clears session state; migration of an
existing plain passphrase behind Touch ID. The existing
`testKeychainBiometryFallbackReturnsWarningOrNil` was updated to the
single-item semantics. Because ACL items cannot be created in unsigned
processes and this Mac reports Touch ID unavailable (closed clamshell), the
tests assert the invariants of whichever branch the runner can actually
exercise — the biometric-enforcement branch will execute on signed,
Touch ID-capable runners. Tests never trigger a real prompt: enforcement is
verified with UI-skipped reads.

## Verification

Final re-run on this branch (2026-07-22):

1. `swift test` (with the task's PKG_CONFIG_PATH/rpath): **308 tests, 0
   failures** — all 7 new keychain tests and all pre-existing tests pass.
   Note: `KeyLifecycleTests.testOldEncryptionSubkeyGetsGraceExpiry` is
   timing-sensitive and unrelated to this change — the implementation
   timestamps the grace expiry BEFORE generating the new RSA subkey while the
   test measures after, so the 10 s tolerance can be exceeded whenever RSA
   keygen is slow. It failed intermittently in earlier runs (on `main` too,
   verified via a `main` worktree: passed once, failed once by 0.07 s on this
   branch, failed twice under load); it passed in the final run.
2. `xcodebuild -scheme RNP build CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
3. `xcodebuild -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.

## Notes / follow-ups

- Real-device behavior (actual Touch ID prompt in the signed app and in Mail)
  could not be exercised here: this Mac has no usable Touch ID (closed
  clamshell) and unsigned processes cannot create ACL items. Worth a manual
  smoke test on a Touch ID Mac with a signed build.
- Enabling Touch ID on a Mac where biometry later becomes unavailable (e.g.
  clamshell) is handled: reads then fall to the system login-password prompt
  via `.userPresence`, and the app's manual fallback remains.
- There is intentionally no settings toggle to enable Touch ID after
  onboarding (out of scope); `sharedPassphrase(requiresBiometry: true)` already
  implements the migration such a toggle would need.
