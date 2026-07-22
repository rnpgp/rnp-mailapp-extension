# Usage

RNP consists of two parts that work together:

- the **RNP app** — a key manager where you generate, import, export, verify,
  and maintain OpenPGP keys, and
- the **RNP OpenPGP Mail extension** — signs and encrypts outgoing mail, and
  decrypts and verifies incoming mail, from inside Mail.app.

Both share one keyring through the app group `group.com.rnpgp.RnpMail`, so a
key created in the app is immediately available to Mail.

## Enabling the extension

The extension is registered when you launch the RNP app, but Mail does not
activate it automatically:

1. Open **Mail → Settings → Extensions**.
2. Check **RNP OpenPGP** and click **Done**.

If the entry does not appear, launch the RNP app once more and re-open Mail's
settings. Mail.app refuses to load extensions that are unsigned or ad-hoc
signed, so self-built copies must be signed with a development team — see
[Installation](installation.md#build-from-source).

## Managing keys

Open the RNP app to manage keys. The key list shows each key's user ID,
fingerprint, and verification status.

### Generating a key

1. Click the **＋** menu and choose **RSA-3072** or **ECDSA P-256**.
2. Enter a user ID that contains the mail address you send from, in the form
   `Alice <alice@example.com>`. The extension matches keys to messages by
   email address, so the address in the user ID must match the account in
   Mail.
3. Confirm. The secret key is protected by a random keyring passphrase stored
   in the Keychain — you are not asked to invent one.

### Importing keys

Use the import (arrow-down) menu to import an armored key **from the
clipboard** or **from a file**. Both public keys (recipients' keys) and secret
keys (your own, e.g. exported from another OpenPGP tool) are accepted.

Imported secret keys keep whatever passphrase protection they arrived with.
When a key's passphrase differs from the keyring passphrase, the app asks for
the key's passphrase (showing its user ID and fingerprint) and offers to save
it in the Keychain — or to re-protect the key with the keyring passphrase, so
you only ever need one passphrase; see
[Passphrases and the Keychain](#passphrases-and-the-keychain).

### Exporting keys

From a key's detail view you can copy the **armored public key** to the
clipboard — this is what you send to correspondents or upload to a keyserver.
Secret-key export is available for backups and is gated by a confirmation
alert. Exported keys are placed on the general pasteboard, which other apps
can read; clear it afterwards if that matters to you.

### Deleting keys

Deleting a key removes it from the shared keyring. Deleting a secret key is
permanent unless you have exported a backup — messages encrypted to that key
can no longer be decrypted.

### Key details and fingerprints

Click a key to open its detail sheet: full fingerprint (with a copy button),
creation and expiry dates, verification status, and trust actions. The
fingerprint is the key's identity — compare it over a trusted channel before
marking a key as verified. See [Trust model](trust-model.md).

## Sending signed and encrypted mail

Compose a message in Mail as usual. The security button in the compose window
now offers two options:

- **Sign** — attaches a digital signature made with your key. Recipients can
  verify that the message really came from you and was not altered.
- **Encrypt** — encrypts the message so only the recipients can read it.
  Encryption requires the recipients' public keys: import them in the RNP app
  first, or fetch them from a keyserver (see [Keyservers](keyserver.md)).

Outgoing messages are sent as **PGP/MIME** (RFC 3156), which preserves
attachments and non-ASCII text exactly.

## Reading signed and encrypted mail

Incoming OpenPGP mail is handled automatically:

- **Encrypted** mail addressed to one of your keys is decrypted in place.
- **Signed** mail is verified, and the result is shown in a banner above the
  message:
  - a **green banner** when the signature is valid and the signer's key is
    one you have verified,
  - a neutral banner when the signature is valid but the key is unverified
    (the normal state for new correspondents — see
    [Trust model](trust-model.md)),
  - a **warning banner** when the signature is invalid, the message was
    altered, or the signer's key conflicts with a key you already trust.

Both PGP/MIME and inline-PGP (armored blocks in `text/plain` parts) messages
are understood on receipt.

## Trusting keys

RNP uses trust-on-first-use: the first key seen for an email address works
immediately and is recorded as *unverified*. To raise assurance, open the
key's detail sheet, compare the fingerprint with the owner over a trusted
channel (in person, a phone call, a signed message you already trust), and
click **Mark as verified**.

If a *different* key later appears for the same address — imported by you or
fetched from a keyserver — RNP raises a conflict: the app shows a warning,
the address is flagged, and encryption to it is blocked until you verify the
new fingerprint. This protects against silent key substitution. The full
model is described in [Trust model](trust-model.md).

## Publishing and finding keys

You can upload your public key to a keyserver so others can find it by email
address, and fetch correspondents' keys by address or fingerprint. VKS
(keys.openpgp.org), HKPS, and Web Key Directory are supported. Details,
privacy notes, and the verification-email flow are in
[Keyservers](keyserver.md).

## Keeping keys healthy

Keys and subkeys can expire. The RNP app warns you about keys that are
expired or expiring soon, and lets you:

- **Rotate a subkey** — generate a fresh encryption or signing subkey; the
  old one expires after a 30-day grace period so correspondents can pick up
  the updated key.
- **Extend expiry** — push the expiration date of a key into the future.
- **Revoke a key** — produce a revocation certificate (stored as
  `<fingerprint>-revocation.asc` in the app-group container) marking the key
  as no longer valid. Publish the revoked key afterwards so others stop using
  it.

## Passphrases and the Keychain

Generated keys share a single keyring passphrase stored in the macOS
Keychain (access group `$(AppIdentifierPrefix)group.com.rnpgp.RnpMail`) —
never in preferences or plain files.

When you enable Touch ID during onboarding, the passphrase is stored only in
a Keychain item protected by a biometric access control, and every process
must authenticate to read it:

- On subsequent launches the container app shows the keyring as locked until
  you unlock it with Touch ID. If Touch ID fails or is cancelled, choose
  "Enter Passphrase" and type the passphrase you picked during onboarding;
  it is verified against your keys and the Keychain item stays
  Touch ID-protected.
- The Mail extension may show a system Touch ID prompt the first time it
  signs or decrypts a message after its process starts. Cancelling the
  prompt fails that operation (nothing crashes and nothing is overwritten);
  the next attempt prompts again, and unlocking in the container app does
  not unlock the extension's process.
- Without Touch ID, the passphrase is stored with the standard
  device-unlocked accessibility and reads never prompt. Biometric storage
  requires a signed build with the keychain entitlements; unsigned local
  builds silently fall back to that plain storage.

Imported keys protected by a different (foreign) passphrase are unlocked once
via a prompt in the app; the entered passphrase is then either stored in the
Keychain under the key's fingerprint (the Mail extension reads it from there
when signing or decrypting) or replaced by re-protecting the key with the
keyring passphrase.

## Known limitations

- **One passphrase per key.** Imported keys with a foreign passphrase need a
  one-time unlock prompt in the app; there is no passphrase prompt inside
  Mail itself, so a key whose passphrase was never entered (prompt skipped)
  cannot sign or decrypt.
- **No SmartCard/HSM support.** Only software keys in the local keyring can
  be used.
- **Inline PGP is receive-mostly.** The extension sends PGP/MIME. Decoding
  accepts both PGP/MIME and inline PGP; inline-PGP *sending* exists in the
  engine for single-part text messages only.
- **Metadata stays visible to Mail.** Subject lines, recipients, and message
  sizes are handled by Mail.app outside the encrypted payload.

## See also

- [Installation](installation.md)
- [Trust model](trust-model.md)
- [Keyservers](keyserver.md)
- [Features](features.md)
- [FAQ](faq.md)
