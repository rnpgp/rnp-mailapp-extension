---
title: Security & Privacy
description: Touch ID, the Keychain, the app sandbox, and exactly what RNP protects — and what it does not.
---

RNP is built defense-in-depth: sandboxed processes, Keychain-held passphrases,
optional Touch ID gating, and a tamper-evident trust database. This page
summarizes the model; the full
[security model](https://github.com/rnpgp/swift-rnp/blob/main/docs/SECURITY-MODEL.md)
lives in the repository for reviewers.

## Passphrases and the Keychain

Generated keys share a single **random keyring passphrase** stored in the
macOS Keychain (access group `$(AppIdentifierPrefix)group.com.rnpgp.RnpMail`)
— never in preferences, UserDefaults, plain files, or logs. You are never
asked to invent a passphrase for a generated key.

Imported keys protected by a different (foreign) passphrase are unlocked once
via a prompt in the app; the entered passphrase is then either stored in the
Keychain under the key's fingerprint (the Mail extension reads it from there
when signing or decrypting) or replaced by re-protecting the key with the
keyring passphrase.

## Touch ID

When you enable Touch ID during onboarding, the keyring passphrase is stored
only in a Keychain item protected by a biometric access control, and every
process must authenticate to read it:

- On subsequent launches the container app shows the keyring as locked until
  you unlock it with Touch ID. If Touch ID fails or is cancelled, choose
  **Enter Passphrase** and type the passphrase you picked during onboarding;
  it is verified against your keys and the Keychain item stays
  Touch ID-protected.
- The Mail extension may show a system Touch ID prompt the first time it
  signs or decrypts a message after its process starts. Cancelling the prompt
  fails that operation gracefully (nothing crashes and nothing is
  overwritten); the next attempt prompts again, and unlocking in the container
  app does not unlock the extension's process.
- Without Touch ID, the passphrase is stored with the standard
  device-unlocked accessibility and reads never prompt.

Independently of how the passphrase is stored, the optional **"require Touch
ID for each operation"** setting (container app → Security) gates every
secret-key operation behind a fresh user-presence verification. A session
timeout (default 30 seconds) re-arms the prompt, so one operation's burst of
passphrase requests prompts only once; a manually entered, key-verified
passphrase counts as verification for the same window.

:::note
Biometric Keychain storage requires a signed build with the keychain
entitlements; unsigned local builds silently fall back to plain
device-unlocked storage.
:::

## Sandbox

Both the container app and the Mail extension run with the macOS app sandbox:

- `com.apple.security.app-sandbox`
- `com.apple.security.application-groups`
- `com.apple.security.network.client` (keyserver queries)
- `com.apple.security.files.user-selected.read-write` (key file import/export)

The sandbox does not grant arbitrary file-system access. Keyring storage is
limited to the app-group container (and a temporary fallback directory for
unsigned builds).

## Privacy

RNP collects **no telemetry, analytics, crash reports, or advertising
identifiers**. The only network traffic is the keyserver queries you initiate
— key upload, discovery, and revocation checks. See the
[telemetry and privacy policy](https://github.com/rnpgp/swift-rnp/blob/main/docs/TELEMETRY.md).

Local diagnostics are available by launching the app from Terminal with
`--self-test` for a local librnp roundtrip check; everything stays on your
Mac.

## What is protected

- **Message confidentiality** — PGP/MIME encrypted messages can only be
  decrypted by holders of the recipient's secret key.
- **Subject/header confidentiality on the wire** — encrypted messages use
  protected headers (`protected-headers="v1"`); the real Subject travels
  inside the encrypted payload.
- **Message integrity and authenticity** — PGP/MIME signatures are verified
  against the sender's public key, with the result in Mail's banner.
- **Secret keys at rest** — encrypted with the keyring passphrase, which lives
  in the Keychain.
- **Trust-state tamper detection** — the trust database is Ed25519-signed; any
  modification fails closed to *unverified*.
- **Key-substitution detection** — a new key for a known address blocks
  encryption until you verify it.

## What is not protected

- **Host compromise** — if an attacker controls the macOS kernel or Mail.app,
  they can observe plaintext while the extension processes messages.
- **Metadata inside Mail.app** — recipients, sender, date, and message size
  are visible to Mail.app before encryption and after decryption.
- **Keyserver availability or correctness** — a keyserver can be unavailable
  or return attacker-controlled keys; verify fingerprints out-of-band.
- **Side channels** — no constant-time protections beyond those provided by
  librnp/Botan.
- **Backup security** — if you back up the app-group container without the
  Keychain, the secret keyring becomes unrecoverable; restore them together.

## Reporting a vulnerability

**Privately — never as a public issue.** See the
[security policy](https://github.com/rnpgp/swift-rnp/blob/main/docs/SECURITY.md)
for the reporting channel and what to include.
