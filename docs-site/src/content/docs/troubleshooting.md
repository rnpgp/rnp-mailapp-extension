---
title: Troubleshooting
description: Common issues with the RNP app and Mail extension, and how to fix them.
---

## The extension doesn't appear in Mail's settings

Launch the RNP app once so the extension is registered, then re-open
**Mail → Settings → Extensions**. If you built from source, the build must be
signed with a development team — Mail refuses unsigned or ad-hoc-signed
extensions. See
[Build from source](/getting-started/installation/).

## macOS warns the app was downloaded from the internet

That is Gatekeeper doing its job for any app distributed outside the Mac App
Store. Because RNP is notarized, Control-click the app and choose **Open** to
approve it — you only need to do this once.

## Encryption to a contact is suddenly blocked

A key with a *different fingerprint* appeared for that email address —
imported by you or fetched from a keyserver. RNP flags this as a conflict and
blocks encryption until you verify the new key's fingerprint with the owner.
Key changes are often legitimate (lost key, re-keying), but they are also what
a key-substitution attack looks like, so RNP asks you to decide. See
[Key-change warnings and conflicts](/trust-verification/#key-change-warnings-and-conflicts).

## A key can't sign or decrypt ("passphrase" failures)

Imported keys keep the passphrase they arrived with. If you skipped the
one-time unlock prompt in the RNP app, the extension has no way to unlock that
key — there is deliberately no passphrase prompt inside Mail itself. Open the
RNP app, trigger the prompt (for example by exporting or signing a test
message), and either save the passphrase in the Keychain or re-protect the key
with the keyring passphrase. See
[Passphrases and the Keychain](/security/#passphrases-and-the-keychain).

## The extension keeps asking for Touch ID

With Touch ID enabled, each process authenticates separately: the Mail
extension may prompt the first time it signs or decrypts after its process
starts, and unlocking the container app does not unlock the extension's
process. Cancelling the prompt fails that single operation gracefully — just
try again. If you'd rather not be prompted per operation, check the
**require Touch ID for each operation** setting in the container app's
Security section (a 30-second session window applies by default).

## The keyring shows as locked in the app

With Touch ID enabled, the keyring stays locked until you authenticate. Use
Touch ID, or choose **Enter Passphrase** and type the onboarding passphrase —
it is verified against your keys and the Keychain item stays
Touch ID-protected.

## Keyserver lookup says "not found"

- Check the address or fingerprint for typos.
- The key may exist under a different user ID, or the owner never confirmed
  the verification email — keys.openpgp.org only serves *confirmed* addresses
  for email lookups (fingerprint lookups still work).
- Try another protocol — WKD or HKPS — or ask the owner to publish their key.
- See [Errors you may see](/keyserver/#errors-you-may-see) for the full table.

## No banner appears above a signed message

The banner only appears for OpenPGP messages the extension actually processed.
Check that **RNP OpenPGP** is still enabled under **Mail → Settings →
Extensions**, and that the message really is PGP/MIME or inline PGP. S/MIME
messages are handled by Mail itself, not by RNP.

## The trust database seems to have reset

The trust store is Ed25519-signed and verified on every load. If `trust.json`
or `trust.json.sig` was modified, corrupted, or deleted, the store resets to
empty — **fail-closed to unverified** rather than trusting corrupted data.
Re-verify your correspondents' fingerprints; your keys themselves are not
affected. See [A tamper-evident trust store](/trust-verification/#a-tamper-evident-trust-store).

## Run local diagnostics

Launch the app from Terminal with `--self-test` for a local librnp roundtrip
check:

```sh
"/Applications/RNP.app/Contents/MacOS/RNP" --self-test
```

Everything stays on your Mac.

## Still stuck?

Open an issue on [GitHub](https://github.com/rnpgp/swift-rnp/issues) with your
macOS version, app version, and steps to reproduce. Do not attach secret keys
or message content. For security vulnerabilities, report **privately** via the
[security policy](https://github.com/rnpgp/swift-rnp/blob/main/docs/SECURITY.md).
