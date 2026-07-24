# Roadmap progress tracker

This file tracks the implementation status of every item in `TODO.roadmap/`.
Update it as work lands. When a checkbox is checked, link the PR or commit
that did it.

Legend:
- `[ ]` not started
- `[~]` engine / model layer landed, UI shell still pending
- `[x]` done and merged

## Tier A — recovery & trust

### 01 — Disaster recovery (paperkey, recovery sheet, iCloud Keychain sync)
- [x] `RnpKey.exportPaperKeyText` paperkey-format exporter
- [x] `PaperKeyHexFormatter` pure formatter + parser (6 tests, round-trips)
- [x] `KeyManager.exportPaperKey(fingerprint:)` engine wrapper
- [x] `RecoverySheetWizard` + `RecoverySheetViewModel` SwiftUI (3-step)
- [ ] Print layout (hex + QR) for paper backup
- [ ] iCloud Keychain sync option (`kSecAttrSynchronizable`) in KeychainPassphraseStore
- [ ] Restore-from-paper-key flow in onboarding
- [ ] Docs: `docs/disaster-recovery.md` (covered in scenarios.md for now)

### 02 — Archive-key state
- [x] `KeyUsageState` enum (active/archived)
- [x] `KeyStateStore` sidecar (signed JSON, in app group)
- [x] Engine selection excludes archived from sign/encrypt
- [x] Auto-archive on revoke-with-superseded
- [x] Migration on first launch for existing revoked keys
- [x] Tests: state transitions; archived decrypts; cannot sign (9 tests)
- [ ] SwiftUI: collapsible "Archived" section in KeysListView
- [ ] "Delete forever" requires fingerprint typing

### 03 — Decryption errors
- [x] `DecryptionFailure` typed enum + `MissingKeyAction`
- [x] `Rnp.dumpPacketsAsJSON(data:)` FFI wrapper
- [x] `MessageDecoder` failure classifier (PKESK inspection)
- [x] Tests: each failure type with fixtures (11 tests)
- [ ] SwiftUI: banner action buttons (currently engine-layer only)
- [ ] Symmetric-passphrase decrypt path

### 04 — Key expiry recovery
- [x] `KeyHealthState` + `KeyRole` + `RecoveryAction` + `RecoveryRecommendation` models
- [x] `ExpiryRecovery.action(for:)` pure mapping function (13 scenarios)
- [x] Tests: each of 13 scenarios produces correct action (13 tests)
- [x] `KeyHealthView` + `KeyHealthViewModel` SwiftUI (status chips + actions)
- [x] `NotifyContactsTemplate` pure template builder (9 tests)
- [ ] Inline recovery sheets at compose / banner / onboarding
- [ ] Promote `ExtensionState/` to first-class per-message store

### 05 — Key transition wizard
- [x] `KeyTransition` engine service (5-step orchestration)
- [x] Tests: end-to-end + public-only refusal (2 tests)
- [ ] Transition certification FFI wiring (`rnp_key_signature_sign`)
- [ ] SwiftUI multi-step wizard sheet
- [ ] Failure-mode paths (old secret lost; offline publish)

### 06 — BCC handling
- [x] `MailMessage` extended with `toAddresses` / `ccAddresses` / `bccAddresses`
- [x] `BccPolicy` enum (refuse / sendSeparately / removeEncryption / removeBcc)
- [x] `BccResolution` (user-facing options)
- [x] Engine refuses via `MessageSecurityCore.encodeWithBccPolicy`
- [x] Tests: each option (6 tests)
- [ ] SwiftUI refusal sheet
- [ ] "Send separately" multi-message path (needs MailKit investigation)

## Tier B — better encryption UX

### 07 — Autocrypt
- [x] `RnpKey.exportAutocryptKey(key:uid:)` FFI wrapper
- [x] `AutocryptHeader` model + parser/serializer
- [x] `AutocryptStore` (level 1 latest-valid-key-wins)
- [x] `AutocryptEmitPolicy` + `AutocryptHeaderBuilder`
- [x] Tests: emit + parse round-trip; store update; mutual default (11 tests)
- [ ] Wire emit into `MessageEncoder.encodePGPMime` (policy in place, call site pending)
- [ ] Wire parse into `MessageDecoder` (AutocryptStore.observe on incoming)
- [ ] Per-account `prefer-encrypt` setting in UI
- [ ] `Autocrypt-Gossip` (level 1.1)

### 08 — Mailbox key scan
- [ ] `MailboxKeyScan` service (3 sources)
- [ ] Consent gate (`MailboxScanConsentView` stub exists)
- [ ] Settings → Re-run scan
- [ ] SwiftUI results list with Import / Ignore
- [ ] Tests: synthetic mailbox with each source type
- [ ] MailKit API investigation (may need to defer)

### 09 — Compose recipient diagnostics
- [x] `RecipientStatus` model + state enum
- [x] `ComposeRecipientStatus` SwiftUI-typed status
- [x] `ComposeRecipientDiagnosticsView` real view with status chips + actions
- [x] `MessageSecurityCore.recipientStatuses(for:)` engine helper (RecipientResolution)
- [ ] Wire into MailKit compose banner
- [ ] Recommended-action banner (single-line summary)
- [ ] Reply-context default-encrypted heuristic

### 10 — Multi-UID keys
- [x] `RnpKey.addUserID(_:hash:expirationSeconds:flags:primary:)` FFI wrapper
- [x] `UserIDKeyFlags` OptionSet matching RFC 4880 §5.2.3.21
- [x] `KeyManager.addUserID(...)` engine wrapper
- [x] Tests: round-trip + reload (2 tests, librnp-gated)
- [x] `AddUserIDForm` SwiftUI sheet (real impl)
- [ ] Add to KeyDetailView as a presented sheet

## Future

### 11 — PQC hybrid
- [x] Phase 1: librnp picks hybrid KEM/signing automatically; catalog tests
- [x] `KeyAlgorithm.hybridPQ` and `KeyAlgorithm.conservativePQ`
- [x] `Rnp.hybridPQKeyGenJSON` and `Rnp.conservativePQKeyGenJSON` templates
- [x] `Rnp.supportsPKESKv6` / `ExperimentalSymbolTable` runtime detection
- [x] Docs: `docs/post-quantum.md` + SECURITY-MODEL.md PQ section
- [ ] Settings UI for PQ policy (classical / hybrid / conservative)
- [ ] Interop test against Sequoia / Thunderbird-PQ fixture

### 12 — AEAD/v6
- [x] `EncryptionEnvelopePolicy` (automatic / force-aead / force-legacy)
- [x] `EncryptionEnvelopeResolver.Decision` pure function
- [x] `Rnp.EncryptAEAD` and `Rnp.EncryptPKESKVersion` enums
- [x] `Rnp.encrypt(_:for:cipher:hash:aead:pkeskVersion:armored:)` FFI
- [x] `EncryptionEnvelopeResolver.Decision.encryptParameters` bridge
- [x] Tests: capability detection, fallback to CFB (7 + 5 tests)
- [ ] Wire `encryptParameters` into `MessageEncoder.encodePGPMime`
- [ ] Settings UI for envelope policy
- [ ] v6 key generation opt-in (`rnp_op_generate_set_v6_key`)

### 13 — Search & archive documentation
- [x] `docs/encrypted-mail-search.md` written (with verification caveat)
- [ ] Verify Mail's actual decode-then-reindex behavior
- [ ] FAQ entry
- [ ] SECURITY-MODEL.md addition (done — see "Encrypted-mail body search" line)

### 14 — Pre-release cleanup
- [x] `scripts/release-preflight.sh` (executable; bash -n clean)
- [x] FAQ drift fix (Ed25519 + PQ hybrid + multi-UID + expiry + BCC entries)
- [ ] Bundle full license texts (rnp, Botan, json-c, sexpp, zlib, bzip2)
- [ ] Update `LicensesView` to render them
- [ ] `docs/key-lifecycle.md` (done)

### 15 — Deferred past 1.0
- [x] Record file exists (no implementation work expected)

## Architecture principles enforced in this work

Applied across all roadmap items:

- **Open/closed**: each feature is a new file or new method on an existing
  type; existing call sites don't change behavior unless they explicitly
  opt in. Examples: `BccPolicy` is passed in, not global; `KeyUsageState`
  is read via `KeyStateStore`, not embedded in `KeyInfo` (which stays a
  snapshot of librnp's view). `Rnp.encrypt` gained a new overload
  accepting AEAD/PKESK-version params; the original signature stays and
  calls into the new one with defaults.
- **MECE**: each concern lives in one place. `DecryptionFailure` is the
  single taxonomy; banner rendering reads from it. `KeyUsageState` is the
  single decrypt-vs-encrypt selector; `KeyManager` does not branch on
  revoked+archived separately. `EncryptionEnvelopeResolver` is the only
  envelope selector; `ExperimentalSymbolTable` is the only FFI-feature
  probe.
- **Model-driven**: types are named after domain concepts (`BccPolicy`,
  `EncryptionEnvelopePolicy`, `KeyHealthState`, `ExpiryRecovery.Action`,
  `NotifyContactsTrigger`, `PaperKeyHexFormatter`).
- **No encapsulation bypass**: no `Mirror`, no `@_spi`, no
  `responds(to:)`, no stringly-typed flags. FFI feature detection uses
  typed function-pointer lookup via `ExperimentalSymbolTable`.
- **DRY**: shared helpers (`MessageOutput` reused for `dumpPacketsAsJSON`;
  `withMemoryInput` reused for both; `BccPolicyEvaluator` shared by
  encoder and UI; `ExpiryRecovery.state(...)` derives state from
  `KeyInfo` so callers don't each branch).
- **Performance**: classification runs only on failure paths; successful
  decrypt takes the existing fast path. FFI feature probes are
  memoized in `static let`s.

## What is NOT done in this pass

The UI wiring for the engine-layer features remains incomplete. The
SwiftUI views (`KeyHealthView`, `RecoverySheetWizard`,
`ComposeRecipientDiagnosticsView`, `AddUserIDForm`) are real and
functional, but they are not yet inserted into the container app's
navigation; they're reachable from previews but not from the main
window. That wiring is a separate container-app task that touches
`Swift-Rnp/MailExtensionsContainer/` (outside the SPM package) and
should land in a focused PR per view.

The engine-layer calls that are not yet wired into `MessageEncoder`:
- `AutocryptHeaderBuilder.build(...)` (emit path)
- `AutocryptStore.observe(...)` (parse path on decode)
- `EncryptionEnvelopeResolver.Decision.encryptParameters` (AEAD/v6)

These are one-line additions once their integration tests are in place.
