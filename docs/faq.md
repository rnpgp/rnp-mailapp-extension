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

No. Only software keys in the local keyring are supported. Hardware-token
support is on the post-1.0 roadmap — see `TODO.roadmap/15-deferred-post-1.0.md`.

### Which key algorithms can I generate?

RNP surfaces three algorithm families for new keys:

- **RSA-3072** — maximum compatibility with old clients; larger keys.
- **ECDSA P-256** — modern elliptic-curve primary with ECDH P-256
  encryption subkey.
- **Ed25519** — Ed25519 signing primary with Curve25519 encryption subkey.
  Recommended for new keys.

Post-quantum hybrid algorithms (ML-KEM-768+X25519 for encryption,
ML-DSA-65+ED25519 for signing) are supported by librnp and used
automatically when a recipient advertises a hybrid-capable key.
Generating your own hybrid key is opt-in — see
[Post-quantum cryptography](post-quantum.md).

### Can one key cover multiple email addresses?

Yes. A primary key can carry multiple user IDs (UIDs), so you can use one
key for both work and personal email. Add UIDs from the key detail view in
the RNP app. The engine picks the UID matching the From address when
generating Autocrypt headers and resolving recipients.

### What happens when my key expires?

You can still decrypt and verify old mail — expiration does not affect
read paths. You cannot sign new mail or be encrypted-to until you extend
the key or rotate to a new subkey. The Key Health view in the RNP app
shows expiring keys and offers one-click recovery:

- **Extend expiry** (when you still have the secret material).
- **Rotate subkey** (replaces the encryption or signing subkey; primary
  identity is preserved).
- **Migrate to a new key** (when the secret is lost; opens the key
  transition wizard, which signs the new key with the old one and
  revokes the old with reason `superseded`).

See [Key lifecycle](key-lifecycle.md) for the full scenario table.

### What is the BCC behavior on encrypted mail?

Encrypted mail to BCC recipients is **refused by default**. PGP/MIME
encrypts one ciphertext for all recipients, and any decrypting recipient
can enumerate the recipient list — including BCC — by inspecting the
PKESK packets. RFC 3156 §6 calls this out explicitly.

When you attempt to send an encrypted message with BCC recipients, RNP
stops and offers three paths: send separately (one encrypted message
per BCC set), drop encryption for the whole message, or remove the BCC
recipients. See [BCC handling](usage.md#bcc-on-encrypted-mail).

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

Yes, for encrypted PGP/MIME mail. Outgoing encrypted messages use protected
headers (`protected-headers="v1"`, the "Memory Hole" scheme also used by K-9
Mail and Thunderbird): the real Subject and other sensitive headers move into
the encrypted payload, and the outer message carries a generic placeholder
("Encrypted message"). Recipients whose mail app understands protected headers
see the real subject after decryption; others see the placeholder. Recipients,
sender, and date remain visible — the mail system needs them for routing and
for the message list. See also
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
