---
title: First Launch & Onboarding
description: What happens the first time you open RNP — Touch ID, your first key, and enabling the Mail extension.
---

RNP is two parts that work together:

- the **RNP app** — a key manager where you generate, import, export, verify,
  and maintain OpenPGP keys, and
- the **RNP OpenPGP Mail extension** — signs and encrypts outgoing mail, and
  decrypts and verifies incoming mail, from inside Mail.app.

Both share one keyring through the app group `group.com.rnpgp.RnpMail`, so a
key created in the app is immediately available to Mail.

## The first launch

When you open RNP for the first time, a short onboarding flow walks you
through the essentials:

1. **Welcome** — a quick overview of what RNP does and how the app and the
   Mail extension fit together.
2. **Touch ID (optional)** — you are offered biometric protection for the
   keyring passphrase. If you opt in, the passphrase is stored only in a
   Keychain item guarded by Touch ID, and every process must authenticate to
   read it. You can skip this and enable it later; see
   [Security & Privacy](/security/#touch-id).
3. **Your first key** — generate a new key pair or import an existing one
   (details below). You can also skip and do it later from the key list.

## Your first key

The fastest way to get going is a fresh key pair:

1. Click the **＋** menu in the key list and choose an algorithm —
   **Ed25519** (the default), **RSA-3072**, or **ECDSA P-256**.
2. Enter a user ID that contains the mail address you send from, in the form
   `Alice <alice@example.com>`. The extension matches keys to messages by
   email address, so the address in the user ID **must match the account in
   Mail**.
3. Confirm. The secret key is protected by a random keyring passphrase stored
   in the Keychain — you are not asked to invent one.

Already using OpenPGP elsewhere? Import your existing key instead — from the
clipboard or a file. See [Importing keys](/key-management/#importing-keys).

## Enable the Mail extension

The extension is registered when you launch the RNP app, but Mail does not
activate it automatically:

1. Open **Mail → Settings → Extensions**.
2. Check **RNP OpenPGP** and click **Done**.

If the entry does not appear, launch the RNP app once more and re-open Mail's
settings.

## Send your first protected message

Compose a message in Mail as usual. The security button in the compose window
now offers **Sign** and **Encrypt**:

- **Sign** works right away with the key you just created.
- **Encrypt** needs the recipient's public key — import it in the RNP app, or
  fetch it from a keyserver (see [Keyservers](/keyserver/)).

For everything the compose button and the message banner can do, see
[Using with Mail](/using-with-mail/).

## What to explore next

- [Key Management](/key-management/) — import, export, inspect, rotate, and
  revoke keys.
- [Trust & Verification](/trust-verification/) — verify a correspondent's
  fingerprint and understand the three trust states.
- [Security & Privacy](/security/) — how Touch ID, the Keychain, and the
  sandbox protect your keys.
