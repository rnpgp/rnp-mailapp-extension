# Security Model

This document describes the security model of the RNP Apple Mail OpenPGP extension and its companion container app. It is intended for security reviewers, downstream packagers, and users who want to understand what the project protects and what it does not protect.

## Scope

RNP provides OpenPGP signing, encryption, and key management for Apple Mail on macOS. It is built on top of:

- **librnp** (`v0.18.1` or later) — OpenPGP implementation.
- **Botan** — cryptographic backend used by librnp.
- **json-c** — JSON parsing used by librnp.
- **Apple Mail / MailKit** — host application and extension runtime.
- **macOS** — operating system, keychain, sandbox, and app-group containers.

## Assets

| Asset | Location | Sensitivity |
|---|---|---|
| OpenPGP secret keys | Shared app-group keyring (`pubring.gpg`, `secring.gpg`) | Critical: loss or extraction allows decryption and impersonation. |
| Keyring passphrase | macOS Keychain (access group `$(AppIdentifierPrefix)group.com.rnpgp.RnpMail`) | Critical: protects secret key material in the keyring. |
| Per-key passphrases | macOS Keychain, one generic-password item per key fingerprint | Critical: protects imported keys that were not re-protected with the keyring passphrase. |
| Trust database | Shared app-group container (`trust.json` + `trust.json.sig`) | High: tampering can downgrade a key from verified to unverified or cause denial of service. |
| Revocation certificates | Shared app-group container (`<fingerprint>-revocation.asc`) | High: loss prevents future revocation of the corresponding key. |
| Public keys / recipient keys | Shared app-group keyring | Medium: disclosure reveals contact metadata but not message content. |
| Extension state records | Shared app-group container (`ExtensionState/last-message.json`, `ExtensionState/messages/*.json`) | Medium: subject, message ID, sender, and signature/trust status of recently decoded OpenPGP messages; no message bodies. |
| Mail message bodies | Mail.app process memory and extension `MEMessage` objects | High: the extension reads and writes plaintext during encode/decode. |
| Network traffic to keyservers | `KeyServerClient` over HTTPS | Medium: queries reveal which keys or email addresses are being looked up. |

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                        User / macOS                             │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐ │
│  │    RNP app      │    │           Apple Mail                │ │
│  │  (key manager)  │◄──►│  MailPlugin.appex                   │ │
│  └────────┬────────┘    │  (encode/decode signatures,         │ │
│           │             │   decrypt, verify)                  │ │
│           │             └─────────────────────────────────────┘ │
│           │                          │                          │
│           ▼                          ▼                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │      Shared App Group Container                         │   │
│  │  (keyring, trust database, revocation certs)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │      macOS Keychain (keyring passphrase)                │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼ HTTPS
                  ┌─────────────────┐
                  │  keys.openpgp.org │
                  │  (default SKS/KS) │
                  └─────────────────┘
```

### Boundary notes

- **Apple Mail is trusted.** MailKit controls the plaintext message handed to the extension. RNP assumes the `MEMessage` input is produced by Mail.app and does not attempt to sanitize the host application.
- **App group container is shared.** Both the container app and the Mail extension run with the same app-group identifier. Any process with access to that group could read public keys and the trust database. Secret keys remain encrypted by the keyring passphrase.
- **Keychain is the root of trust for the passphrase.** The keyring passphrase is stored in the user's default keychain via `KeychainPassphraseStore`. It is never written to UserDefaults, preferences files, or logs. With Touch ID enabled, the passphrase additionally sits behind a biometric access control; the Mail extension may then show a system Touch ID prompt the first time it needs the passphrase in its process, and a cancelled prompt fails that sign/decrypt operation gracefully instead of exposing the passphrase. A manual passphrase fallback (verified against the secret keys, without downgrading the Keychain protection) is offered in the container app.
- **Keyserver network boundary.** Key upload, discovery, and revocation-check queries travel over HTTPS to the configured keyserver (default: `keys.openpgp.org`). No other network calls are made.
- **Extension state records.** On every OpenPGP message it decodes, the extension writes a small JSON record (subject, Message-ID, sender, signature/trust status, encryption flag — never message bodies) to `ExtensionState/` in the app group container. These records exist so the end-to-end test harness can assert the banner state from outside Mail, and they carry the same metadata Mail already shows in the message list. They live in the same protection domain as the keyring; unsigned fallback builds use `~/Library/Application Support/RNP Mail Extension/ExtensionState` instead.

## What Is Protected

- **Message confidentiality:** PGP/MIME encrypted messages can only be decrypted by holders of the recipient's secret key.
- **Subject/header confidentiality on the wire:** Encrypted messages use protected headers (`protected-headers="v1"`, "Memory Hole"): the real Subject and other sensitive headers travel inside the encrypted payload; the outer message carries a generic placeholder Subject. Recipients, sender, and date remain visible for routing.
- **Message integrity / authenticity:** PGP/MIME signed messages are verified against the sender's public key; the signature status is surfaced in Mail's banner.
- **Secret key confidentiality at rest:** Secret key material is stored in librnp's GPG-compatible keyring and encrypted with the keyring passphrase, which is stored in the Keychain.
- **Trust-state tamper detection:** The trust database is signed with an Ed25519 key derived at first launch. If `trust.json` or `trust.json.sig` is modified or deleted, the store resets to empty (fail-closed to unverified).
- **Key-substitution detection:** If a new key is imported or fetched for an already-known email address with a different fingerprint, the address is marked as a conflict and encryption is blocked until the user verifies the new fingerprint.

## What Is NOT Protected

- **Host compromise.** If an attacker controls the macOS kernel or the Mail.app process, they can observe plaintext while the extension processes messages.
- **Metadata inside Mail.app.** Subject, headers, recipients, and message size are visible to Mail.app before encryption and after decryption. On the wire the Subject of encrypted messages is protected (see *What Is Protected*); recipients, sender, and date are not.
- **Keyserver availability or correctness.** The default keyserver can be unavailable or return attacker-controlled keys. Users must verify fingerprints out-of-band.
- **Side channels.** RNP does not implement constant-time protections above those provided by librnp/Botan.
- **Phishing / UI spoofing.** MailKit renders the security banner; RNP supplies status text but cannot guarantee that a malicious Mail.app build will display it faithfully.
- **Backup security.** If the user backs up the app-group container without the Keychain, the secret keyring becomes unrecoverable. If the Keychain is backed up separately, restore it together with the keyring.

## Memory Hygiene

- **No force-unwraps in library code.** Swift library targets avoid `!` and use explicit error handling.
- **Sensitive buffers are released when Swift objects are deallocated.** The underlying librnp C types (`rnp_ffi_t`, `rnp_key_handle_t`, etc.) are wrapped in Swift classes with `deinit` calls to `rnp_ffi_destroy` / `rnp_key_handle_destroy`.
- **Passphrases in Swift strings.** Passphrases collected in the UI travel through Swift `String` values. Swift strings are reference-counted and zeroed by the runtime when no longer referenced; we do not perform explicit `memset_s` scrubbing. This matches standard Swift practice but is weaker than a dedicated secrets allocator.
- **Keychain items.** Keychain-stored passphrases use the generic password item class, accessible while the device is unlocked. When the user opts into Touch ID during onboarding, the keyring passphrase is instead stored only in an item guarded by a `SecAccessControl` with `.userPresence` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`): every read then requires Touch ID (with the macOS login password as the system-level fallback), the unprotected copy is deleted, and reads that cannot authenticate leave the stored item untouched. The unlocked passphrase is cached per process so a session prompts at most once.
- **Clipboard exports.** Exported public and secret keys are placed on the general pasteboard. Other apps can read the pasteboard. Secret-key export is gated by a confirmation alert.

## Sandboxing

- The container app and Mail extension use macOS app sandbox entitlements:
  - `com.apple.security.app-sandbox`
  - `com.apple.security.application-groups`
  - `com.apple.security.network.client` (keyserver queries)
  - `com.apple.security.files.user-selected.read-write` (key file import and export)
- The sandbox does not grant arbitrary file-system access. Keyring storage is limited to the app-group container and the temporary fallback directory.

## Reporting Security Issues

See [`SECURITY.md`](SECURITY.md) for disclosure instructions and supported versions.
