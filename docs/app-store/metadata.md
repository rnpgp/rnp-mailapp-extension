# App Store Connect Metadata — RnpMail

> Template for the Mac App Store submission. Replace all `TODO` placeholders
> with real values before submitting in App Store Connect.

## App Information

| Field | Value |
|-------|-------|
| Name | RnpMail |
| Subtitle | OpenPGP for Apple Mail |
| Category (Primary) | Utilities |
| Category (Secondary) | Productivity |
| Age Rating | 4+ |
| In-App Purchases | None |

## Description

RnpMail brings OpenPGP signing and encryption to Apple Mail on macOS.
Generate or import PGP keys, then sign, encrypt, and decrypt mail right from
the compose window and message reader — no separate mail client required.

Key features:

- Generate RSA or ECDSA PGP keys in a few clicks.
- Import existing public or secret keys from the clipboard or a file.
- Sign and encrypt outgoing messages with Mail’s native security button.
- Automatically decrypt incoming mail and verify sender signatures.
- Trust-on-first-use with manual fingerprint verification and clear conflict
  warnings when a key changes.

Your private key never leaves your Mac. Passphrases are stored in the
Keychain, and keys live in a shared app-group container so the container app
and the Mail extension work together securely.

## Keywords

openpgp, pgp, encryption, mail, privacy

## Privacy Policy URL

TODO: https://example.com/rnpmail/privacy

## Support URL

TODO: https://example.com/rnpmail/support

## App Review Information

- **Review notes:**
  After first launch, enable the extension in **Mail → Settings → Extensions**
  by checking **RNP OpenPGP**. No account or server is required; the app
  functions as a standalone key manager and provides the Mail extension.
  A 60–90 second demo video is attached showing: create key → enable extension
  → compose signed+encrypted message → receive and verify banner.

- **Demo account:** Not required.

- **Demo video note:**
  TODO: Attach the screen recording here (create key, enable extension, send
  signed/encrypted mail, receive verified banner). Capture on a demo account
  with fake keys and addresses.

## Export Compliance

Use the self-classification prepared in the Apple Developer account checklist.
RnpMail uses the open-source librnp implementation of OpenPGP; submit the
Encryption Registration (ERN) notification if required for your jurisdiction.

## Release Automation Notes

`.github/workflows/release-appstore.yml` uses a `workflow_run` trigger that
depends on the successful completion of `.github/workflows/release-direct.yml`.
`workflow_run` triggers are only evaluated on the repository's default branch,
so the App Store upload path will not run automatically from this branch. It
becomes active after the branch is merged to `main` and a matching version tag
is pushed.

