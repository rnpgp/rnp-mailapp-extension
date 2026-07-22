# Features

This page lists RNP's capabilities and maps them to the underlying OpenPGP
standards and librnp functionality that implements them.

## Message security (Mail extension)

| Feature | Standard / implementation |
|---|---|
| Sign outgoing mail | OpenPGP embedded signatures via librnp, sent as PGP/MIME (`multipart/signed`, RFC 3156) |
| Encrypt outgoing mail | OpenPGP public-key encryption via librnp, sent as PGP/MIME (`multipart/encrypted`, RFC 3156) |
| Decrypt incoming mail | PGP/MIME and inline PGP (armored blocks in `text/plain`, including inside `multipart/mixed`) |
| Verify incoming signatures | Automatic verification with the result surfaced in Mail's message banner |
| Attachments | Preserved exactly by PGP/MIME encode/decode |
| Non-ASCII message bodies | Preserved exactly by PGP/MIME; full UTF-8 handling |
| Inline-PGP sending | Available in the engine (`MessageFormat.inlinePGP`) for single-part text messages only |
| Compose-window security button | MailKit `MEMessageSecurityHandler`; per-message sign/encrypt toggles |
| Signature status banner | AppKit banner rendered by the extension; verified / unverified / problem states |

## Key management (RNP app)

| Feature | Standard / implementation |
|---|---|
| Key generation | RSA-3072 (librnp 0.18 default) and ECDSA P-256 key pairs from librnp key-generation JSON |
| Key import | Armored public and secret keys, from clipboard or file (`rnp_import_keys`) |
| Key export | Armored public key to clipboard; secret-key export behind a confirmation alert |
| Key listing and lookup | By user ID, fingerprint, key ID, or grip |
| Key deletion | Removes the key from the shared keyring |
| Subkey rotation | Fresh encryption or signing subkey; the retired subkey expires after a 30-day grace period |
| Expiry extension | New expiration date written into the key's self-signature |
| Revocation | Armored revocation certificate per key, stored as `<fingerprint>-revocation.asc` in the app-group container |
| Expiry monitoring | Report of primary keys and subkeys expired or expiring within 60 days, with in-app banners |

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
- Asymmetric algorithms exposed in the UI: RSA (3072-bit default) and ECDSA /
  ECDH on NIST P-256. librnp supports further algorithms (Ed25519, larger
  RSA, DSA, ElGamal) through its key-generation JSON; the app currently
  surfaces the two most interoperable choices.
- Symmetric encryption, hashing, and compression for message protection are
  negotiated by librnp per recipient key preferences, per the OpenPGP
  standard.

## Testing and quality gates

- Swift package test suite covering the engine, MIME parser, trust store,
  keyserver client, key lifecycle, and banner UI (`swift test`).
- Snapshot tests for the Mail banner (`Tests/MailSecurityUITests/`).
- Container-app UI tests including onboarding, key generation, and
  accessibility audits.
- Sandbox/entitlement audit (`scripts/sandbox-audit.sh`) and a release
  pipeline dry-run (`scripts/ci-release-dry-run.sh`).
- End-to-end harness against a local IMAP/SMTP server
  (`scripts/local-mail-server.sh`, `scripts/test-mail-e2e.sh`).

## See also

- [Usage](usage.md)
- [Trust model](trust-model.md)
- [Keyservers](keyserver.md)
- [Security model](SECURITY-MODEL.md)
