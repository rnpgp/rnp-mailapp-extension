# Features

This page lists RNP's capabilities and maps them to the underlying OpenPGP
standards and librnp functionality that implements them.

## Message security (Mail extension)

| Feature | Standard / implementation |
|---|---|
| Sign outgoing mail | OpenPGP embedded signatures via librnp, sent as PGP/MIME (`multipart/signed`, RFC 3156) |
| Encrypt outgoing mail | OpenPGP public-key encryption via librnp, sent as PGP/MIME (`multipart/encrypted`, RFC 3156) |
| AEAD-OCB encryption | Used automatically when all recipients support it (per `RNP_KEY_FEATURE_AEAD`); falls back to CFB + MDC for legacy recipients |
| v6 PKESK (SEIPDv2) | Used automatically when all recipients support it, hiding the recipient key ID in transit |
| Autocrypt emit + parse | `Autocrypt:` header on outgoing mail (`rnp_key_export_autocrypt`); per-address observation store on incoming. See [Autocrypt](autocrypt.md). |
| Decrypt incoming mail | PGP/MIME and inline PGP (armored blocks in `text/plain`, including inside `multipart/mixed`) |
| Typed decryption failures | Specific errors: missing secret key (with PKESK key ID), wrong passphrase, integrity failure (MDC/AEAD), unsupported algorithm, symmetric-only, malformed armor. Each carries a one-click recovery action. |
| Verify incoming signatures | Automatic verification with the result surfaced in Mail's message banner |
| Attachments | Preserved exactly by PGP/MIME encode/decode |
| Non-ASCII message bodies | Preserved exactly by PGP/MIME; full UTF-8 handling |
| Protected headers (Subject encryption) | `protected-headers="v1"` ("Memory Hole", K-9 Mail / Thunderbird compatible): sensitive headers travel inside the encrypted payload; the outer Subject is a placeholder |
| Inline-PGP sending | Available in the engine (`MessageFormat.inlinePGP`) for single-part text messages only |
| Compose-window security button | MailKit `MEMessageSecurityHandler`; per-message sign/encrypt toggles |
| Signature status banner | AppKit banner rendered by the extension; verified / unverified / problem states |
| BCC handling | Refuses encrypted send when BCC recipients are present (preventing PKESK leak per RFC 3156 §6); offers three recovery paths |

## Key management (RNP app)

| Feature | Standard / implementation |
|---|---|
| Key generation | RSA-3072, ECDSA P-256, and Ed25519 (recommended) key pairs from librnp key-generation JSON |
| Post-quantum key generation (opt-in) | Hybrid `ML-DSA-65+ED25519` signing + `ML-KEM-768+X25519` encryption; SLH-DSA conservative option. See [Post-quantum cryptography](post-quantum.md). |
| Multi-UID keys | One key, multiple email addresses (`rnp_key_add_uid`) |
| Key import | Armored public and secret keys, from clipboard or file (`rnp_import_keys`) |
| Key export | Armored public key to clipboard; secret-key export behind a confirmation alert |
| Key listing and lookup | By user ID, fingerprint, key ID, or grip |
| Key deletion | Removes the key from the shared keyring |
| Archive (decrypt-only) state | Revoked/retired keys remain in the keyring for decrypting historical mail but are never selected for new operations |
| Subkey rotation | Fresh encryption or signing subkey; the retired subkey expires after a 30-day grace period and is then archived |
| Expiry extension | New expiration date written into the key's self-signature |
| Revocation | Armored revocation certificate per key, stored as `<fingerprint>-revocation.asc` in the app-group container; auto-archives the revoked key |
| Key transition wizard | Migrate to a new key with transition certification, `superseded` revocation, and archiving of the old key |
| Expiry monitoring | Report of primary keys and subkeys expired or expiring within 60 days, with one-click recovery actions (extend / rotate / generate replacement) |
| Disaster recovery (roadmap) | Paper-key backup, recovery sheet wizard, opt-in iCloud Keychain sync for the keyring passphrase — see [`TODO.roadmap/01`](TODO.roadmap/01-disaster-recovery.md) |

## Trust

| Feature | Implementation |
|---|---|
| Trust-on-first-use (TOFU) | First key seen for an address is recorded as *unverified* and usable |
| Manual verification | Full-fingerprint comparison in the key detail sheet; verified keys get a green badge in the app and in Mail's banner |
| Key-change conflicts | A different fingerprint for a known address is flagged *problem*; encryption to that address is blocked with a `trustConflict` error until the user verifies the new key |
| Tamper-evident trust store | `trust.json` plus a detached Ed25519 signature (`trust.json.sig`); any tampering resets the store to empty (fail-closed to unverified) |
| Deliberate scope cut | No GnuPG-style ownertrust, trust signatures, or web-of-trust UI — see [Trust model](trust-model.md) |

## Keyservers

| Feature | Protocol |
|---|---|
| Key upload | VKS (`POST /vks/v1/upload`), default server keys.openpgp.org |
| Discovery by email address | VKS (`GET /vks/v1/by-email/:email`) |
| Discovery by fingerprint | VKS (`GET /vks/v1/by-fingerprint/:fpr`) |
| Discovery via Web Key Directory | WKD advanced and direct methods (draft-koch-openpgp-webkey-service) |
| Discovery via HKPS | HKP over HTTPS (`/pks/lookup`), known servers keys.openpgp.org and keyserver.ubuntu.com |

All keyserver traffic uses HTTPS; the app makes no other network requests.
See [Keyservers](keyserver.md) for the full picture.

## Platform and system integration

| Feature | Implementation |
|---|---|
| Shared keyring | GPG-compatible `pubring.gpg` / `secring.gpg` in the app group `group.com.rnpgp.RnpMail`, shared by the app and the extension |
| Passphrase storage | Random keyring passphrase in the macOS Keychain access group; never in UserDefaults or files |
| Touch ID | Optional biometric unlock, offered during onboarding |
| App sandbox | `com.apple.security.app-sandbox` with only app-groups, network-client (keyservers), and user-selected file read/write entitlements |
| Bundled crypto | Self-contained `RNPFramework.xcframework` (librnp 0.18.1 + Botan 3.10.0 + json-c, pinned and hash-verified — see [Dependency policy](DEPENDENCIES.md)); no dependency on Homebrew at runtime |
| Localization | 11 languages: English, German, Spanish, French, Italian, Japanese, Korean, Portuguese, Russian, Simplified Chinese, Traditional Chinese |
| Accessibility | VoiceOver labels and automated accessibility audits in the UI test suite |
| Privacy | No telemetry, analytics, or crash reporting — see [Telemetry and privacy policy](TELEMETRY.md) |

## Cryptography (via librnp)

- OpenPGP implementation: librnp 0.18.1+ (RFC 4880), with the Botan 3
  cryptographic backend.
- Asymmetric algorithms exposed in the UI: Ed25519 (default), RSA-3072,
  ECDSA / ECDH on NIST P-256, and post-quantum hybrids (ML-DSA-65+ED25519
  signing + ML-KEM-768+X25519 encryption; SLH-DSA-SHA2 conservative
  signing). See [Post-quantum cryptography](post-quantum.md).
- librnp supports further algorithms (larger RSA, DSA, ElGamal) through
  its key-generation JSON; the app surfaces the most interoperable choices.
- Symmetric encryption, hashing, and compression for message protection are
  negotiated by librnp per recipient key preferences, per the OpenPGP
  standard.
- AEAD-OCB authenticated encryption and v6 PKESK (SEIPDv2) are supported
  via the envelope policy (automatic / force-AEAD / force-legacy).

## Testing and quality gates

- Swift package test suite: **497 tests** covering the engine, MIME parser,
  trust store, keyserver client, key lifecycle, key state store, Autocrypt,
  post-quantum catalog, decryption-failure classifier, BCC policy, encryption
  envelope resolver, reply-context heuristic, notify-contacts template,
  mailbox scanner driver, paper-key formatter, offline publish queue, signed
  security-state store, and compose-policy aggregate (`swift test`).
- Snapshot tests for the Mail banner (`Tests/MailSecurityUITests/`).
- Container-app UI tests including onboarding, key generation, and
  accessibility audits.
- Sandbox/entitlement audit (`scripts/sandbox-audit.sh`) and a release
  pipeline dry-run (`scripts/ci-release-dry-run.sh`).
- Local release-preflight (`scripts/release-preflight.sh`) — shape-checks
  codesign, otool, plutil, and framework embedding without Apple secrets.
- End-to-end harness against a local IMAP/SMTP server
  (`scripts/local-mail-server.sh`, `scripts/test-mail-e2e.sh`).

## See also

- [Usage](usage.md)
- [Trust model](trust-model.md)
- [Key lifecycle](key-lifecycle.md)
- [Autocrypt](autocrypt.md)
- [Post-quantum cryptography](post-quantum.md)
- [Encrypted mail and search](encrypted-mail-search.md)
- [Keyservers](keyserver.md)
- [Security model](SECURITY-MODEL.md)
