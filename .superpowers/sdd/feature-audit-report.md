# Feature Audit Report — swift-rnp Mail Extension

**Date:** 2026-07-22
**Scope:** Verify that (a) librnp capabilities, (b) OpenPGP mail features, and
(c) the extension's UI/UX correspond to each other; identify gaps; recommend
follow-ups.
**Method:** Static audit of all Swift sources (`Sources/*`, `Swift-Rnp/*`),
the vendored librnp header (`Sources/CRnp/rnp/rnp.h`, librnp 0.18.x),
entitlements/Info.plists, privacy manifests, tests, and `docs/`. The test
suite was inventoried but **not executed** as part of this audit.

**Headline:** The extension implements a solid, well-tested core: PGP/MIME
and inline-PGP encode/decode, three key algorithms, full key lifecycle,
TOFU trust with tamper-evident persistence, VKS/WKD keyserver access, a
MailKit banner with trust actions, and an 11-language container app. The
most consequential gaps are **no encrypt-to-self** (senders cannot decrypt
their own sent mail), **imported secret keys with a foreign passphrase are
unusable** (no passphrase prompt exists anywhere), the **Touch ID option has
no runtime effect**, and **"Extend expiry" does not extend subkey expiry**.

---

## 1. Feature matrix

Status: **Implemented** / **Partial** / **Missing** / **N/A** (deliberate or out of scope).

### 1.1 Key management

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Generate RSA | Implemented | `Rnp.rsaKeyGenJSON`, `KeyManager.generateKey`, UI menu + onboarding | Fixed at 3072 bits in UI; other sizes possible via JSON but not surfaced (reasonable). |
| Generate ECDSA | Implemented | `Rnp.ecdsaP256KeyGenJSON`, UI | P-256 only; P-384/P-521/Brainpool not surfaced. |
| Generate Ed25519 + Curve25519 | Implemented | `Rnp.ed25519KeyGenJSON`, UI (default) | `docs/features.md` still claims only RSA/ECDSA are surfaced — doc drift (§4.4). |
| Generate DSA/ElGamal/SM2/v6 keys | N/A | librnp `rnp_generate_key_*` unused | Deliberate per `TODO.impl/00-overview.md` interop policy (v4 keys, MDC/CFB). |
| Import armored / binary, public / secret | Implemented | `Rnp.importKeys` (`RNP_LOAD_SAVE_PERMISSIVE`), `KeyManager.importKeys` | Clipboard, file, drag & drop, clipboard auto-detect, onboarding paste. |
| Export public (armored/binary) | Implemented | `RnpKey.exportKey`, `KeyManager.exportKey` | UI exposes armored-to-clipboard only; binary export unused by UI. |
| Export secret | Implemented | `exportKey(secret:)` | Behind confirmation alert in UI. |
| Key inspection: fingerprint, user IDs, subkeys, expiration, algorithm, capabilities | Implemented | `RnpKey`, `KeyInfo`/`SubkeyInfo`, `KeyDetailView` (Overview/Subkeys/User IDs) | QR code (`OPENPGP4FPR:`) for fingerprint comparison is a nice touch. |
| Key inspection: grip, key version, per-UID validity, certifications/signatures | Missing | `rnp_key_get_grip`, `rnp_key_get_version`, `rnp_uid_is_revoked`, `rnp_key_get_signature_*` unused | Signatures/certifications deliberately omitted (see `KeyDetailView.swift:74-75`); grip lookup exists in `KeyIdentifierType` but is never displayed. |
| Key deletion | Implemented | `Rnp.remove`, `KeyManager.deleteKey`, UI alert | Trust records for the deleted key's addresses are **not** cleaned up (stale `trust.json` entries/conflicts remain). |
| Keyring persistence (pubring/secring) | Implemented | `KeyManager` GPG keyrings in app-group container | Binary `pubring.gpg`/`secring.gpg`, atomic writes, empty keyrings removed. |
| Add/remove/revoke user IDs | Missing | `rnp_key_add_uid`, `rnp_uid_remove` not wrapped | Cannot fix a typo'd UID without re-generating externally and re-importing. |
| Change key passphrase / re-protect keys | Missing | `rnp_key_protect`/`rnp_key_unprotect` not wrapped | Single shared keyring passphrase by design, but see §3 P2-4. |

### 1.2 Key lifecycle

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Rotate encryption subkey | Implemented | `KeyLifecycle.rotateEncryptionSubkey`, UI action | New subkey matches primary algorithm family; old subkey retired with 30-day grace expiry. |
| Rotate signing subkey | Implemented | `KeyLifecycle.rotateSigningSubkey`, UI action | Bonus beyond the audit checklist. |
| Extend expiration | **Partial** | `KeyLifecycle.extendExpiry`, UI date picker | **Only the primary's self-signature is updated; subkeys keep their old expiry** (contrast `KeyManager.generateKey`, which sets expiry on primary *and* subkeys). A key with an expired encryption subkey is not rescued by this action. See §3 P2-1. |
| Revoke key + revocation certificate | Implemented | `RnpKey.revoke`, `exportRevocation`, `KeyLifecycle.revoke`, `KeyManager.saveRevocationCertificate` | Rev cert auto-saved at generation (`<fpr>-revocation.asc` in app group) and on revoke; UI requires fingerprint re-entry. |
| Revoke subkey only | Missing | `rnp_key_revoke` works per-handle but UI/lifecycle only revoke primaries | Minor. |
| Expiry reporting / warnings | Implemented | `KeyLifecycle.expiryReport` (60-day threshold), sidebar banner, list badges | Threshold consistent between engine and UI badges. |

### 1.3 Trust and verification

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| TOFU first-seen | Implemented | `TrustStore.noteSeen` (→ `unverified`), called from `KeyManager.importKeys` for every imported UID email | TOFU is anchored at **import/fetch time**, not first message seen — consistent with docs. |
| Manual fingerprint verification | Implemented | `TrustStore.markVerified`; app key detail "Mark as Verified"; Mail banner button (unverified keys) | Full fingerprint + QR code in detail view. |
| Key-change conflict detection | Implemented | `TrustStore.noteSeen` different-fingerprint path → `TrustConflict` + `problem` state | Blocks encryption (`MailSecurityError.trustConflict`), compose warning, app banner. |
| Key-change conflict resolution | **Partial** | `markVerified` / `resolveConflict` | Only "accept the new key" exists. There is **no "reject new key / keep old binding" action** anywhere (app or banner); the conflict banner is not actionable (no button). See §3 P2-2. |
| Trust states (unverified/verified/problem) | Implemented | `TrustState`, exhaustive banner mapping (`mapSignerTrust`, `testSignerTrustMappingExhaustive`) | `.problem` is only ever set by the conflict path — `markProblem` is **never called in production code** (only tests). Expired/revoked recipient keys are not auto-flagged (§3 P3). |
| Trust persistence + tamper detection | Implemented | `trust.json` + detached Ed25519 `trust.json.sig`, per-install signing key in Keychain | Fail-closed to empty on tamper; schema `version` field present (v1, no migrations yet). |
| Single binding per address | Limitation | `TrustDatabase.records: [String: TrustRecord]` | One fingerprint per email; a second legitimate key for the same address always raises a conflict. |

### 1.4 Keyserver

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Publishing via VKS | Implemented | `URLSessionKeyServerClient.upload` → `POST /vks/v1/upload` (keys.openpgp.org) | UI publish sheet with receipt message. |
| Publishing via HKP/HKPS (`pks/add`) | Missing | Not implemented | VKS-only is a reasonable default. |
| Discovery via WKD (advanced + direct) | Implemented | `WKDEncoding` (Z-base-32, draft-koch vectors tested), `KeyServerService.discoverByEmail` | WKD advanced → direct → VKS fallback chain. |
| Discovery via VKS by email / fingerprint | Implemented | `fetchByEmail`, `fetchByFingerprint`, fetch sheet in Recipients tab | |
| Discovery via HKPS | **Partial (dead code)** | `fetchHKPS` + `HKPSServer` exist and are unit-tested via mocks, but **no production caller** — `KeyServerService` never tries HKPS and the UI offers no server choice | Either wire it as a fallback or remove it. |

### 1.5 Mail encryption / signing

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| PGP/MIME encrypt (RFC 3156 §4) | Implemented | `MessageEncoder.encodePGPMime`, `decodePGPMimeEncrypted` | Correct `application/pgp-encrypted` + `Version: 1` structure. |
| PGP/MIME sign (RFC 3156 §5) | Implemented | `encodePGPMime` sign branch, `decodePGPMimeSigned` | Byte-exact part extraction + CRLF canonicalization; `micalg="pgp-sha256"` is **hardcoded** (correct only while the sign hash stays SHA-256). |
| Sign + encrypt combined | Implemented | Embedded sign inside encryption envelope; `processOpenPGPBlob` verifies in one pass with one nested fallback pass | |
| Inline PGP decode | Implemented | `decodeInlineSingle`, `decodeInlineMultipart`, armor-block scanner | Cleartext-signed (`BEGIN PGP SIGNED MESSAGE`) and encrypted blocks; scans leaf parts of arbitrary multiparts. |
| Inline PGP encode | **Partial** | `MessageFormat.inlinePGP` exists in engine with tests; multipart correctly rejected | **Not user-selectable**: `MessageSecurityCore.encode` never sets `format`, so Mail always sends PGP/MIME. |
| Attachments | Implemented | Whole-MIME-entity protection; `testAttachmentRoundtrip` | Inline format correctly refuses multipart. |
| Non-ASCII bodies | Implemented | `testNonASCIIBodyRoundtrip`, charset header preserved | Minor: `replaceTransferEncoding(in:with:)` only *replaces* an existing CTE header (its doc comment says "or appends"); a decoded inline body that gains non-ASCII without a pre-existing CTE header gets none. |
| Multipart/mixed | Implemented (decode) | `decodeInlineMultipart` recursion | Edge gap: a **`multipart/signed` nested inside `multipart/mixed` is not verified** — the recursion only processes armor blocks in leaf bodies, and a bare `BEGIN PGP SIGNATURE` block matches no scanner marker. Rare in practice. |
| Base64 / quoted-printable | Implemented | `MimeMessage.decodedBody`, `decodeQuotedPrintable`, byte-exact corpus tests | |
| Signature verification: valid | Implemented | `Rnp.verifyDetailed` status mapping | |
| Signature verification: invalid | Implemented | `RnpSignatureStatus.invalid` → banner "Invalid signature" | |
| Signature verification: unknown signer | Implemented | `.signerUnknown` → "Unknown signer" | **Dead end UX**: no "fetch signer key from keyserver" action in banner or app. See §3 P2-3. |
| Signature verification: expired | Implemented | `.expired` mapped, banner variants | |
| Encryption to multiple recipients | Implemented | `testMultiRecipientEncryption`; encode adds all resolved recipient keys | |
| **Encryption to sender (encrypt-to-self)** | **Missing** | `MailKitMessage.recipientAddresses = allRecipientAddresses` (To/Cc/Bcc only); encode never adds the sender's key | **The sender cannot decrypt their own sent messages.** Highest-impact gap. See §3 P1-1. |
| Signing with multiple signers | Missing | Single sender key in `encode`; librnp supports repeated `rnp_op_sign_add_signature` | Minor for mail. |
| Password (symmetric) encryption | N/A | `rnp_op_encrypt_add_password` not wrapped | Not a mail feature. |
| AEAD / v6 (RFC 4880bis / crypto-refresh) | N/A (deliberate) | `rnp_op_encrypt_set_aead`, `rnp_op_generate_set_v6_key` unused | `TODO.impl/00-overview.md`: "AEAD/v6 opt-in only". Decode-side AEAD works via librnp when received. |
| Protected headers / Memory Hole (Subject encryption) | Missing | Encoder keeps `Subject` etc. at top level in plaintext | Subject leaks on encrypted mail; modern PGP/MIME UAs (K-9, Thunderbird) support protected headers. See §3 P2-5. |
| Autocrypt (headers, gossip, setup message) | Missing | `rnp_key_export_autocrypt` unused; no header handling | Ecosystem feature; optional. |

### 1.6 Mail.app integration

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| `getEncodingStatus` | Implemented | `MessageSecurityHandler.getEncodingStatus` → `MessageSecurityCore.getEncodingStatus` | Per-recipient trust issues; warning only surfaced when the user toggled encryption on (good). |
| `encode` | Implemented | Sign/encrypt gated on `isSending` and compose toggles | |
| `decodedMessage` | Implemented | Returns `nil` for non-OpenPGP mail so Mail shows it untouched; per-signer `SignerContext` JSON; decode outcomes recorded for the e2e harness | |
| `extensionViewController(signers:)` | Implemented | AppKit banner: encryption line + per-signer trust + actions | Encryption state threaded via signer context with a last-decode fallback for encrypted-but-unsigned mail. |
| `extensionViewController(messageContext:)` / `primaryActionClicked` | N/A (stubs) | Return `nil` | No custom message-context UI — acceptable. |
| `MEComposeSessionHandler` / `MEMessageActionHandler` / `MEContentBlocker` | N/A | Not declared in `MEExtensionCapabilities` | Out of scope for a security handler. |
| Banner: signature/trust/encryption status | Implemented | `MailSecurityBannerView` + `SignerTrustViewModel` (exhaustive status×trust mapping) | |
| Banner actions | Implemented | "View Key in RNP" (deep link), "Copy Fingerprint", "Mark as Verified" (unverified only) | For `problem` keys the resolution path is deep-link → app → verify; coherent. |
| Compose-time recipient trust warnings | Implemented | `RecipientTrustWarning` via `securityError`; problem/conflict recipients also listed in `addressesFailingEncryption` | Matches engine behavior exactly (same trust checks in `encode`). |
| Deep link to container app | Implemented | `rnpmail://review/<fpr>` registered (`CFBundleURLTypes`) and handled in `ContentView.onOpenURL`, incl. pending-review retry on key-list change | |

### 1.7 Container app UX

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Key list | Implemented | `KeysListView` (Table, My Keys/Recipients tabs, search, trust indicator, expiry/revoked badges, context menu) | |
| Key detail | Implemented | `KeyDetailView`: overview, subkeys, user IDs, fingerprint card + QR, trust card | |
| Onboarding | Implemented | Welcome → create/import → done; passphrase strength meter; expiry choice; Touch ID checkbox (see §3 P2-6); rev-cert handoff | Import form contains a **disabled placeholder** "fetch from keyserver" button (`ImportKeyForm.swift:50`) — dead UI. |
| Import / export | Implemented | Clipboard, file, drag & drop, auto-detect; public/secret export with confirmation | |
| Lifecycle actions | Implemented | Rotate (enc/sign), extend expiry (see §3 P2-1), revoke with fingerprint confirmation | |
| Keyserver actions | Implemented | Publish sheet; fetch sheet (email → WKD/VKS, fingerprint → VKS) | HKPS unreachable (§1.4). |
| Trust actions | Implemented | Mark verified in detail; conflict banner; deep-link review | Conflict banner not actionable; no reject path (§3 P2-2). |
| Accessibility | Implemented | Accessibility identifiers throughout, VoiceOver labels/traits, UI-test accessibility audits | |
| Localization | **Partial** | `Localizable.xcstrings`: 11 languages, 188 keys — covers the container app | **The Mail extension banner (`MailSecurityUI`) and trust view-model strings are hardcoded English.** |
| Dark mode | Implemented | Dynamic light/dark colors in both `RnpBrand` and `BannerBrand` | |

### 1.8 Security

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Passphrase storage (Keychain) | Implemented | `KeychainPassphraseStore`: generic-password items, `WhenUnlocked`, shared access group via `RNPMAILKeychainAccessGroup` | Single random (or onboarding-chosen) passphrase protects the whole keyring. |
| Touch ID | **Partial (no runtime effect)** | Biometric item written with `.biometryCurrentSet`/`.userPresence` when onboarding checkbox set | **Nothing in production ever reads the biometric item** — the engine/app providers always call `sharedPassphrase()` (plain item). The toggle is effectively cosmetic; deliberate per task-04 decision (background decode must not prompt) but the UI implies protection. See §3 P2-6. |
| App group sharing | Implemented | `group.com.rnpgp.RnpMail` (config-driven) for keyring, trust store, extension state | Fallback to Application Support / temp dir when the group is unavailable (unsigned builds), degrading gracefully. |
| Sandbox / entitlements | Implemented | Both targets: app-sandbox, app-groups, keychain-access-groups, network.client; container adds user-selected.read-write | Minimal and appropriate. |
| Privacy manifest | Implemented | Both targets have `PrivacyInfo.xcprivacy`; container declares UserDefaults `CA92.1` | No tracking, no collected data. |
| Passphrase prompts for foreign keys | **Missing** | Passphrase provider is a fixed closure returning the one Keychain passphrase | **A secret key imported with a different passphrase (e.g. from GnuPG) can never be unlocked** — no prompt UI, no per-key passphrase storage. See §3 P1-2. |

### 1.9 librnp API coverage (context)

- Header declares ~297 `rnp_*` entry points; the Swift wrapper uses ~80 (~27%).
- Deliberately unused: WoT/certification APIs, signature-subpacket introspection,
  AEAD/v6/PQC knobs, symmetric encryption, security rules, debug/dump helpers,
  alternative I/O adapters.
- Notable unused-but-relevant: `rnp_key_protect` (passphrase change),
  `rnp_key_add_uid`/`rnp_uid_remove`, `rnp_op_verify_get_recipient_*`
  (cannot show *which* keys a received message was encrypted to),
  `rnp_import_signatures` (importing standalone revocations/signatures).

---

## 2. Correspondence check (UI/UX ↔ librnp behavior)

Verified correspondences:

- **Recipient recognition** — `KeyManager.publicKeyUnlocked` matches full UID,
  bare email, case-insensitive `<…>` email; compose warnings and `encode`
  share the same resolution and trust checks, so what the compose indicator
  promises is what `encode` does. Tested (`testRecipientResolutionByEmail`,
  `testTrustConflictBlocksEncryption`).
- **Trust levels** — banner mapping of (signature status × trust state) is
  exhaustive and unit-tested; app badges, list indicators, and banners agree
  on the three-state model.
- **Key changes** — import/fetch → `noteSeen` → conflict → compose block +
  app banner + deep-link review → mark verified → conflict resolved →
  encryption unblocked. End-to-end tested
  (`testMarkVerifiedAllowsEncryptionAfterConflict`).
- **Migrations** — `TrustDatabase.version` (v1) and the documented-stable
  `SignerContext` wire format (optional fields only) are the right seams; no
  migrations needed yet.
- **Keyring sharing** — app and extension open the same app-group keyring
  and Keychain items; both degrade to a temp fallback instead of crashing.
- **Expiry thresholds** — 60-day warning threshold identical in engine,
  list badges, and banners.

Correspondence problems found:

1. **"Extend expiry" vs. actual key validity (functional).**
   `KeyLifecycle.extendExpiry` re-signs only the primary's expiration;
   subkeys keep theirs (`KeyLifecycle.swift:198-210`). `KeyManager.generateKey`
   explicitly sets expiry on primary *and* subkeys, so the codebase knows
   librnp stores them separately. A user with an expired encryption subkey
   who extends expiry still cannot receive encrypted mail. The UI
   ("extendExpiry.title") implies the whole key is extended.
2. **Touch ID checkbox vs. behavior (security UX).** Onboarding's
   `useTouchID` (default on) writes a biometric Keychain item, but every
   production read path uses the plain item (`MessageSecurityHandler.swift:31`,
   `KeysManager.swift:40`). No Touch ID prompt ever occurs; the checkbox
   changes nothing observable. This was a deliberate trade-off (background
   decode must not prompt — see `.superpowers/sdd/task-04-fix-report.md`),
   but the UI does not say so.
3. **Single passphrase vs. imported keys (interop).** The passphrase
   provider ignores the librnp context and always returns the one stored
   passphrase. Keys imported from GnuPG etc. with their own passphrase fail
   signing/decryption with a generic error and no remedy. The UI advertises
   import as a first-class flow (onboarding even leads with it).
4. **Doc drift.** `docs/features.md` claims only RSA/ECDSA are surfaced in
   the UI (Ed25519 has been the default for some time) and omits the
   inline-PGP-send limitation; `TODO.impl/00-overview.md` says hash defaults
   "SHA-384/512" while the code uses SHA-256 everywhere
   (`Rnp.swift`, `KeyLifecycleConfiguration.defaultHash`).
5. **HKPS discovery vs. UI.** The client and tests exist; the service/UI
   never use them. Dead code presented (in `docs/features.md`) as a feature.
6. Minor: `MEMessageSigner.emailAddresses` receives the full user ID string
   ("Alice <a@b.c>") rather than bare addresses; works but is not what the
   field name promises.
7. Minor: `replaceTransferEncoding` does not append a missing CTE header
   despite its comment; stale trust entries survive key deletion; the
   onboarding import form shows a permanently disabled fetch button.

---

## 3. Gaps and recommendations (prioritized)

### P1 — user-blocking or data-loss-class

1. **Encrypt-to-self for outgoing mail.**
   Add the sender's own public key to the recipient set in
   `MessageSecurityCore.encode` (or `MailSecurityEngine.encode`) whenever a
   secret key exists for the sender. Without it, messages in Sent are
   undecryptable by their author — users will experience this as data loss.
   Engine change is a few lines; add a round-trip test ("sender can decrypt
   own sent mail").
2. **Support foreign-passphrase secret keys on import.**
   Today, importing a GnuPG-exported secret key makes it visible but
   unusable. Minimal fix: on import of secret keys, attempt unlock with the
   stored passphrase; on failure, either (a) re-protect the key to the
   keyring passphrase by asking the user for the old one
   (`rnp_key_unlock`/`rnp_key_protect` — needs wrapper), or (b) store a
   per-key passphrase in the Keychain and make the provider consult it by
   key grip (the librnp callback receives the key handle). Also surfaces the
   need for a passphrase-prompt UI, which is currently absent everywhere.

### P2 — correctness / security-UX coherence

3. **Extend expiry should cover subkeys.** Apply
   `setExpirationSeconds` to the primary *and* each live subkey in
   `KeyLifecycle.extendExpiry` (mirroring `KeyManager.generateKey`), with a
   test asserting an expired subkey becomes usable.
4. **Conflict resolution needs a "reject" path.** Add
   `TrustStore.dismissConflict(email:)` (drop the conflict, keep/restore the
   old binding) and expose both "Verify new key" and "Keep current key"
   actions — at minimum in the app's conflict banner (currently a passive
   label); ideally also from the Mail banner's problem state.
5. **Unknown-signer dead end → keyserver fetch action.** The banner's
   "Unknown signer" state offers nothing. Add a "Look up key" action
   (deep link into the app fetch sheet pre-filled, or direct VKS/WKD/HKPS
   lookup by the signature's issuer fingerprint/key ID from
   `rnp_op_verify_signature_get_*`). This also gives `fetchHKPS` its first
   production caller.
6. **Touch ID: make it real or stop promising it.** Either route a
   user-visible unlock through the biometric item for foreground operations
   (app-side actions) while keeping the plain item for background decode,
   or relabel the onboarding checkbox ("store a Touch ID-protected copy")
   so users don't believe decryption requires biometry.
7. **Protected headers (Subject confidentiality).** Adopt the
   Memory-Hole-style approach: move `Subject` into the encrypted/signed
   entity and emit a stub `Subject: [...]` at top level; on decode, restore
   the inner headers. Privacy-relevant and increasingly expected by other
   OpenPGP MUAs.
8. **Passphrase change flow.** Wrap `rnp_key_protect`/`rnp_key_unprotect`
   and offer "change keyring passphrase" (re-protect all secret keys, update
   Keychain). Today the passphrase chosen at onboarding is immutable without
   wiping everything.

### P3 — completeness / polish

9. Surface inline-PGP sending (format choice) or remove the dead engine path.
10. Auto-`markProblem` (or a distinct expired/revoked badge) for recipient
    keys that are expired/revoked at import and at compose time; preflight
    recipient-key expiry in `encodingStatus` instead of failing late in
    `rnp_op_encrypt_execute`.
11. Localize the Mail banner (`MailSecurityUI` + `SignerTrustViewModel`
    strings) into the existing 11-language catalog.
12. Verify `multipart/signed` nested inside `multipart/mixed` on decode.
13. Wire HKPS as a documented fallback (or delete it and fix
    `docs/features.md`); consider HKP `pks/add` upload for
    keyserver.ubuntu.com users.
14. Key inspection extras: key grip, key version (v4), per-UID revocation
    state, "encrypted to" recipient info via `rnp_op_verify_get_recipient_*`.
15. Multiple signers per message via repeated `rnp_op_sign_add_signature`
    (low value for mail; cheap to expose in the engine).
16. Hygiene: prune trust records on key deletion; remove or implement the
    disabled onboarding fetch button; append CTE header when missing after
    inline decode; refresh `docs/features.md` (Ed25519 default, inline-send
    limitation, HKPS status) and the SHA-256 default in
    `TODO.impl/00-overview.md`.
17. Consider supporting multiple concurrent key bindings per address in the
    trust store (current model: one binding/address).
18. Optional ecosystem: Autocrypt header ingestion for recipient discovery.

### Explicitly out of scope (deliberate, verified)

- Web-of-trust / ownertrust / trust signatures (`docs/trust-model.md` scope cut).
- AEAD, v6 keys, PQC — interop policy: v4 + MDC/CFB by default
  (`TODO.impl/00-overview.md`); decode-side support comes free with librnp.
- DSA/ElGamal/SM2 generation, symmetric (password) encryption, compression
  tuning, debug/packet-dump APIs — not mail features.
- `MEComposeSessionHandler`, `MEMessageActionHandler`, content blocker —
  not needed for a security handler.

---

## 4. Appendix

### 4.1 Architecture snapshot

- `Sources/Rnp` — thin, RAII Swift wrapper over librnp FFI (key gen, I/O,
  encrypt/sign/verify incl. detailed per-signature status).
- `Sources/MailSecurityEngine` — keyring (`KeyManager`), MIME parser
  (byte-exact), PGP/MIME + inline encoder/decoder, Keychain passphrase
  store, app-group locations, keyserver service, state recorder for e2e.
- `Sources/KeyLifecycle`, `Sources/TrustStore`, `Sources/KeyServerClient` —
  lifecycle ops, tamper-signed TOFU DB, VKS/WKD/HKPS clients.
- `Sources/MailSecurityUI` (AppKit banner), `Sources/RnpMailUI` (SwiftUI
  design system + onboarding/forms/detail), `Swift-Rnp/MailPlugin` (thin
  MailKit shell), `Swift-Rnp/MailExtensionsContainer` (container app).
- Tests: Rnp (13), engine incl. MIME corpus/property/perf (40+),
  TrustStore (12), KeyLifecycle (8), KeyServerClient (12), banner snapshot
  tests, RnpMailUI localization/onboarding tests, XCUITest suite.
  Suite not executed during this audit.

### 4.2 librnp version

- Vendored `RNPFramework.xcframework`: librnp 0.18.1 + Botan 3.10.0 + json-c
  (pinned, hash-verified per `docs/DEPENDENCIES.md`).
