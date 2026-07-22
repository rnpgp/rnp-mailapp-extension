# Frequently Asked Questions

## General

### What is RNP?

RNP is an OpenPGP security extension for Apple Mail on macOS, plus a
companion key-manager app. It lets you sign, encrypt, decrypt, and verify
email inside Mail.app — no separate mail client needed. It is built on
[librnp](https://github.com/rnpgp/rnp), the open-source OpenPGP (RFC 4880)
library.

### Which macOS versions are supported?

macOS 12 or later.

### Is it free?

Yes. Signed, notarized releases are attached to
[GitHub Releases](https://github.com/rnpgp/swift-rnp/releases).

### Does the app collect telemetry or analytics?

No. No telemetry, analytics, crash reports, or advertising identifiers. The
only network traffic is keyserver queries you initiate. See the
[Telemetry and privacy policy](TELEMETRY.md).

### Why MailKit instead of a classic Mail plugin bundle?

Classic Mail plugins inject code into the Mail process and break regularly
with macOS updates; Apple deprecated them in favor of MailKit extensions.
MailKit gives RNP a supported, sandboxed API (`MEMessageSecurityHandler`)
with a defined security boundary — at the cost of requiring properly signed
builds, which is why unsigned builds are compile checks only.

## Keys and trust

### Why is there no web of trust?

GnuPG-style ownertrust and web-of-trust add significant UX complexity that
few users navigate correctly, and they are not needed for the "verify once,
warn on change" model RNP implements (TOFU + manual fingerprint verification
+ key-change conflicts). It is a deliberate scope cut, not a missing feature.
See [Trust model](trust-model.md).

### Why is encryption to a contact suddenly blocked?

Because a key with a *different fingerprint* appeared for that email
address — imported by you or fetched from a keyserver. RNP flags this as a
conflict and blocks encryption until you verify the new key's fingerprint
with the owner. Key changes are often legitimate (lost key, re-keying), but
they are also what a key-substitution attack looks like, so RNP asks you to
decide. See [Trust model](trust-model.md#key-change-warnings-and-conflicts).

### Where are my keys and passphrases stored?

Keys live in a GPG-compatible keyring in the shared app-group container
(`group.com.rnpgp.RnpMail`), accessible to both the app and the Mail
extension. The keyring passphrase is a random value stored in the macOS
Keychain — never in preferences or plain files. Details and the full threat
model are in [Security model](SECURITY-MODEL.md).

### Can I use my existing GnuPG keys?

Yes. Export the secret key from GnuPG (`gpg --export-secret-keys --armor`)
and import it in the RNP app. If the key's passphrase differs from the
keyring passphrase, the app prompts for it once and offers to save it in the
Keychain or to re-protect the key with the keyring passphrase — see
[Passphrases and the Keychain](usage.md#passphrases-and-the-keychain).

### Can I use a SmartCard or hardware token?

No. Only software keys in the local keyring are supported.

### Which key algorithms can I generate?

RSA-3072 (the librnp 0.18 default) and ECDSA P-256. librnp supports more
through its API; the app surfaces the two most interoperable choices.

## Mail behavior

### Why don't I see the extension in Mail's settings?

Launch the RNP app once so the extension is registered, then re-open
**Mail → Settings → Extensions**. If you built from source, the build must be
signed with a development team — Mail refuses unsigned or ad-hoc-signed
extensions.

### Does it work with attachments and non-English text?

Yes. Outgoing mail uses PGP/MIME (RFC 3156), which preserves attachments and
non-ASCII content exactly. Incoming PGP/MIME and inline-PGP messages are both
understood.

### Will my subject lines be encrypted?

No. OpenPGP protects the message body and attachments; subject, recipients,
and other headers remain visible to the mail system, as with most deployed
email encryption. This is also listed in
[What is not protected](SECURITY-MODEL.md#what-is-not-protected).

### How do I revoke a key?

From the key's detail view in the RNP app. Revocation produces an armored
revocation certificate (kept as `<fingerprint>-revocation.asc` in the
app-group container). Afterwards, re-upload the revoked key to the keyserver
so others stop using it — see [Keyservers](keyserver.md).

## Problems and reporting

### Where do I report bugs?

Open an issue on [GitHub](https://github.com/rnpgp/swift-rnp/issues) with
your macOS version, app version, and steps to reproduce. Do not attach secret
keys or message content.

### How do I report a security vulnerability?

**Privately** — never as a public issue. See [Security policy](SECURITY.md)
for the reporting channel and what to include.

### How do I run local diagnostics?

Launch the app from Terminal with `--self-test` for a local librnp roundtrip
check. Everything stays on your Mac; see
[Telemetry and privacy policy](TELEMETRY.md#local-diagnostics).

## Licensing

### Under what license is RNP released?

The repository currently ships no license file. Contact the maintainers
before reusing the code in ways that require an explicit license. The
vendored cryptographic components (librnp, Botan, json-c) are BSD-2-Clause /
MIT licensed — see [Dependency policy](DEPENDENCIES.md#license-compliance).

## See also

- [Installation](installation.md)
- [Usage](usage.md)
- [Trust model](trust-model.md)
- [Keyservers](keyserver.md)
