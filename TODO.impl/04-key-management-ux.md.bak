# 04 — Key management UX (container app)

Status: pending · Milestone: M2 · Depends on: 01

## Goal

Make the container app a complete, delightful OpenPGP key manager: generate,
import, inspect, export, delete — with onboarding and Touch ID.

## Context / existing base

- `MailSecurityEngine.KeyManager` already does: generate (RSA/ECDSA JSON),
  import, export, list, delete, recipient resolution, lock-serialized keyring
  dir. The container app (PR #13) has basic generate/import/export/delete
  wiring. `Rnp` wrapper has `RnpKey.fingerprint/userIDs/primaryUserID/hasSecret`,
  `Rnp.allUserIDs()`, `Rnp.remove(key:)`.
- Likely MISSING in the `Rnp` wrapper (add with tests first): key expiry
  get/set (`rnp_key_valid_till64`, expiry setter), subkey enumeration
  (`rnp_key_get_subkey_count/at`), key algo/bits getters
  (`rnp_key_get_alg`, `rnp_key_get_bits`), creation time, revoke
  (`rnp_key_revoke`), uid add/revoke if exposed by FFI. Check
  `include/rnp/rnp.h` in the librnp install for exact names — extend
  `Sources/Rnp` accordingly.

## UX spec

- **Onboarding** (first launch only): 3 screens — welcome/what-this-does →
  "Create new key" (name+email, Ed25519 default with RSA-3072 "maximum
  compatibility" option, expiry 2y default, passphrase w/ strength meter +
  "save to Keychain with Touch ID" default ON) OR "Import existing"
  (file/paste/fetch-by-email placeholder → task 06) → done screen (revocation
  cert saved note + offer "Publish public key" → task 06, may be a stub
  deep-link that becomes live in 06).
- **Keys tab**: list of own keys (primary user ID, fingerprint short, type
  chip [Ed25519/RSA/ECDSA], expiry badge turning amber <60d, red expired);
  detail view: full fingerprint (grouped, copy button), user IDs, subkeys
  table (algo, bits, created, expiry, capabilities), actions: export public /
  export secret (encrypted, confirms) / extend expiry (→ task 05) / revoke
  (→ 05) / delete.
- **Recipients tab**: imported/other keys with same detail view minus secret
  actions; trust state shown (stub "unverified" until task 07).
- **Import**: NSOpenPanel + drag-drop onto the window + clipboard detect
  (offer import when pasteboard contains `-----BEGIN PGP PUBLIC KEY BLOCK-----`).
- **Touch ID**: Keychain item ACL `kSecAttrAccessControl` =
  `.biometryCurrentSet` + `.userPresence`; fallback to passphrase prompt.
  Wrap in `KeychainPassphraseStore` (exists) — extend, don't replace.
- Errors: human sentences + recovery action (never raw rnp codes in UI).

## Tests

- `swift test`: new Rnp wrapper getters/setters round-trip against both
  librnp builds; KeyManager expiry/subkey listing on generated keys.
- XCUITest smoke (`Swift-Rnp` UITest target, runs in CI unsigned):
  onboarding renders, generate-key flow completes with stubbed entropy-fast
  RSA 1024 debug mode? — NO: keep real keygen (RSA-3072 ~2s, acceptable),
  assert key appears in list.

## Acceptance criteria

- New user: launch → key created → public key exported, in <5 minutes,
  without reading docs.
- All key metadata displayed matches `rnp --list-keys`/GnuPG for the same
  keyring (spot-check one RSA and one Ed25519 key).
- Passphrase never touches UserDefaults/disk; Keychain entry has Touch ID ACL.
- `swift test` green on both librnp installs; CI green.

## Notes

- Secret-key export must stay armored+passphrase-protected (librnp protects
  with the key's own passphrase by default) — never offer "export
  unprotected".
