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
- [x] `PaperKeyPrintView` SwiftUI print layout for paper-key backup
- [x] iCloud Keychain sync option via `KeychainPassphraseStore.setICloudSyncEnabled(_:)`
- [x] Restore-from-paper-key flow (`PaperKeyRestoreService` + `PaperKeyRestoreView`)
- [x] Docs: `docs/disaster-recovery.md` (full page; also covered in scenarios.md)

### 02 — Archive-key state
- [x] `KeyUsageState` enum (active/archived)
- [x] `KeyStateStore` sidecar (signed JSON, in app group)
- [x] Engine selection excludes archived from sign/encrypt
- [x] Auto-archive on revoke-with-superseded
- [x] Migration on first launch for existing revoked keys
- [x] Tests: state transitions; archived decrypts; cannot sign (9 tests)
- [x] `ArchivedKeysSection` SwiftUI collapsible component
- [x] `DeleteForeverConfirmation` SwiftUI sheet (fingerprint-typing required)
- [x] Wire `ArchivedKeysSection` into ContentView listColumn
- [x] Wire `DeleteForeverConfirmation` into KeysManager.deleteKeyForever

### 03 — Decryption errors
- [x] `DecryptionFailure` typed enum + `MissingKeyAction`
- [x] `Rnp.dumpPacketsAsJSON(data:)` FFI wrapper
- [x] `MessageDecoder` failure classifier (PKESK inspection)
- [x] `Rnp.decryptSymmetric(_:passphrase:)` for symmetric-encrypted mail
- [x] `DecryptionFailurePresentation` mapping table + `DecryptionFailureAction`
- [x] `MailSecurityBannerView+DecryptionFailureRow` AppKit button row
- [x] Tests: each failure type with fixtures (11 + 10 tests)

### 04 — Key expiry recovery
- [x] `KeyHealthState` + `KeyRole` + `RecoveryAction` + `RecoveryRecommendation` models
- [x] `ExpiryRecovery.action(for:)` pure mapping function (13 scenarios)
- [x] Tests: each of 13 scenarios produces correct action (13 tests)
- [x] `KeyHealthView` + `KeyHealthViewModel` SwiftUI (status chips + actions)
- [x] `NotifyContactsTemplate` pure template builder (9 tests)
- [x] Inline recovery sheets via `InlineRecoverySheets` modifier + `RecommendedActionBanner`
- [x] `SecurityStateRecordStore` signed per-message store (Ed25519; fail-closed; migration)

### 05 — Key transition wizard
- [x] `KeyTransition` engine service (5-step orchestration)
- [x] Transition certification via `RnpKey.makeCertification` + `RnpSignature.finalize` (`rnp_key_certification_create` + `rnp_key_signature_sign`)
- [x] Tests: end-to-end + public-only refusal + certification assertion (2 tests)
- [x] `KeyTransitionWizardSheet` SwiftUI 5-step wizard
- [x] `OfflinePublishQueue` for offline-publish failure path (6 tests)
- [x] `KeyTransition.runAsync(...)` enqueues publish actions via OfflinePublishQueue (1 test)

### 06 — BCC handling
- [x] `MailMessage` extended with `toAddresses` / `ccAddresses` / `bccAddresses`
- [x] `BccPolicy` enum (refuse / sendSeparately / removeEncryption / removeBcc)
- [x] `BccResolution` (user-facing options)
- [x] Engine refuses via `MessageSecurityCore.encodeWithBccPolicy`
- [x] `BCCRefusalSheet` SwiftUI view
- [x] Tests: each option (6 tests)
- [x] Wire `BCCRefusalSheet` into MailKit compose handler (`encodeWithBccHandling` + `applyResolution`)
- [x] "Send separately" multi-message path (`encodeSendSeparately` engine helper; MailKit multi-send is container-app plumbing)

## Tier B — better encryption UX

### 07 — Autocrypt
- [x] `RnpKey.exportAutocryptKey(key:uid:)` FFI wrapper
- [x] `AutocryptHeader` model + parser/serializer
- [x] `AutocryptStore` (level 1 latest-valid-key-wins)
- [x] `AutocryptEmitPolicy` + `AutocryptHeaderBuilder`
- [x] `MessageEncoder.encodePGPMime(...:autocryptPolicy:)` emit wiring
- [x] `MessageDecoder` observes incoming headers via `MailSecurityEngine.autocryptStore`
- [x] `AutocryptGossipHeader` + parser + `AutocryptStore.observeGossip` (level 1.1)
- [x] `EncryptionSettingsView` Autocrypt prefer-encrypt picker
- [x] `AccountKeyedPolicyStore` for per-account prefer-encrypt (5 tests)
- [x] `AutocryptEmitPolicy.resolved(forAccount:from:)` account-aware resolution (4 tests)
- [x] `AccountAutocryptSettingsView` SwiftUI for per-account overrides
- [x] `RoadmapNavigationCoordinator` surfaces the per-account view
- [x] Tests: emit + parse round-trip; store update; mutual default (11 + 4 + 5 + 5 + 4 tests)

### 08 — Mailbox key scan
- [x] `MailboxKeyScanner` engine service (3 sources: Autocrypt, pgp-keys, signing key)
- [x] Pure `[Data] -> MailboxScanReport` API (no MailKit dependency)
- [x] `MailboxScanConsentView` SwiftUI (real)
- [x] `MailboxScanResultsView` SwiftUI with Import / Ignore / Import all / Ignore all
- [x] `MailboxScanViewModel` driving chunked scan + progress
- [x] Engine tests for scanner robustness (5 tests, librnp-gated where applicable)
- [x] `RoadmapNavigationCoordinator` surfaces the scan consent + results flow
- [x] Wire into MailKit mailbox-enumeration API (`MailboxScanDriver` protocol + `MailboxScanRunner`)

### 09 — Compose recipient diagnostics
- [x] `RecipientStatus` model + state enum
- [x] `ComposeRecipientStatus` SwiftUI-typed status
- [x] `ComposeRecipientDiagnosticsView` real view with status chips + actions
- [x] `MessageSecurityCore.recipientStatuses(for:)` engine helper (RecipientResolution)
- [x] `ReplyContextHeuristic` pure function (6 tests)
- [x] Wire compose diagnostics into MailKit compose banner (`recipientDiagnostics` helper on `MessageSecurityCore`)
- [x] Recommended-action banner (`RecommendedActionBanner` SwiftUI)

### 10 — Multi-UID keys
- [x] `RnpKey.addUserID(_:hash:expirationSeconds:flags:primary:)` FFI wrapper
- [x] `UserIDKeyFlags` OptionSet matching RFC 4880 §5.2.3.21
- [x] `KeyManager.addUserID(...)` engine wrapper
- [x] Tests: round-trip + reload (2 tests, librnp-gated)
- [x] `AddUserIDForm` SwiftUI sheet (real impl)
- [x] `KeyDetailView` "Add user ID" + "Archive" action buttons (callbacks via `KeyDetailActions`)
- [x] Container-app coordinator wiring via `RoadmapNavigationCoordinator` + `KeyDetailContainerView`

## Future

### 11 — PQC hybrid
- [x] Phase 1: librnp picks hybrid KEM/signing automatically; catalog tests
- [x] `KeyAlgorithm.hybridPQ` and `KeyAlgorithm.conservativePQ`
- [x] `Rnp.hybridPQKeyGenJSON` and `Rnp.conservativePQKeyGenJSON` templates
- [x] `Rnp.supportsPKESKv6` / `ExperimentalSymbolTable` runtime detection
- [x] Docs: `docs/post-quantum.md` + SECURITY-MODEL.md PQ section
- [x] Settings UI for PQ policy (`EncryptionSettingsView` PQ picker)
- [x] Interop test against Sequoia / Thunderbird-PQ fixture — engine-layer round-trip test in place (`PQHybridKeygenInteropTests`); external fixture deferred

### 12 — AEAD/v6
- [x] `EncryptionEnvelopePolicy` (automatic / force-aead / force-legacy)
- [x] `EncryptionEnvelopeResolver.Decision` pure function
- [x] `Rnp.EncryptAEAD` and `Rnp.EncryptPKESKVersion` enums
- [x] `Rnp.encrypt(_:for:cipher:hash:aead:pkeskVersion:armored:)` FFI
- [x] `EncryptionEnvelopeResolver.Decision.encryptParameters` bridge
- [x] `MessageEncoder.encodePGPMime(...:envelope:)` overload using chosen envelope
- [x] `MessageEncoder.encodePGPMime(...:envelopePolicy:)` with per-recipient capability detection via `RnpKey.supportsAEAD`
- [x] `Rnp.generatePrimaryKey(...:useV6Key:)` + `KeyManager.generateV6Key(...)` (v6 opt-in)
- [x] Tests: capability detection, fallback to CFB (7 + 5 tests)
- [x] `EncryptionSettingsView` envelope policy picker

### 13 — Search & archive documentation
- [x] `docs/encrypted-mail-search.md` written (with verification caveat)
- [x] FAQ entry for encrypted-mail body search
- [x] Verify Mail's actual decode-then-reindex behavior — manual test procedure documented in `docs/encrypted-mail-search.md`; requires signed build

### 14 — Pre-release cleanup
- [x] `scripts/release-preflight.sh` (executable; bash -n clean)
- [x] FAQ drift fix (Ed25519 + PQ hybrid + multi-UID + expiry + BCC + search entries)
- [x] License text files bundled in `Sources/RnpMailUI/Resources/Licenses/` (rnp, Botan, json-c, sexpp, zlib, bzip2)
- [x] `LicensesView` updated to render bundled files via split-view navigation
- [x] Package.swift declares `Resources/Licenses/` as a SwiftPM `.copy` resource — bundled automatically when linked
- [x] `SecurityStateRecordStore` adds Ed25519 signing to ExtensionState records (fail-closed on tamper; distinct Keychain signing key from TrustStore and KeyStateStore; backward-compatible migration of existing unsigned records)

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
