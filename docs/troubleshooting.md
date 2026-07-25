# Troubleshooting

Common problems and their fixes.

## The extension doesn't appear in Mail's settings

1. Launch the RNP app at least once so macOS registers the extension.
2. Re-open **Mail → Settings → Extensions**.
3. If built from source: the build must be signed with a development
   team. Mail refuses unsigned or ad-hoc-signed extensions.
4. Check Console.app for `com.apple.mail` errors mentioning the
   extension bundle ID.

## "Couldn't decrypt this message"

The banner shows one of these specific errors:

| Banner text | Cause | Fix |
|---|---|---|
| Encrypted to a key you don't have (key ID ...) | The sender encrypted to a key not in your keyring. | Click **Fetch** to look it up on the keyserver. |
| Encrypted to your archived key ... | The matching key is archived (decrypt-only). | Click **Restore** to un-archive it. |
| Encrypted with a passphrase | Symmetric encryption; no public-key recipient. | Ask the sender for the passphrase and enter it. |
| This message was tampered with | Integrity protection failed (MDC/AEAD mismatch). | Do not trust the contents; contact the sender via another channel. |
| Encrypted with X, which this version doesn't support | The sender used a newer algorithm. | Check for RNP updates. |
| Couldn't unlock your keyring | Passphrase mismatch. | Enter the passphrase manually or reset via the container app. |

## My key expired

See [Key lifecycle — Expiry recovery](key-lifecycle.md#expiry-recovery)
or the [Key Health scenario](scenarios.md#scenario-my-key-is-about-to-expire).

## Encryption is blocked for a contact

A different fingerprint appeared for a known address — a key-change
conflict. Verify the new fingerprint out-of-band and click
**Mark as verified**. See
[Trust model — Key-change conflicts](trust-model.md#key-change-warnings-and-conflicts).

## BCC + encryption doesn't work

PGP/MIME leaks BCC recipients via the PKESK packet list. RNP refuses
and offers three paths (send separately, drop encryption, remove BCC).
See [BCC handling](usage.md#bcc-on-encrypted-mail).

## Spotlight can't find encrypted mail

Encrypted mail body is not searchable. This is fundamental to PGP,
not a bug. See [Encrypted mail and search](encrypted-mail-search.md).

## The app is slow on large mailboxes

The extension decodes every message Mail shows. If you have thousands
of encrypted messages, the first scroll can be slow. Performance is
tracked in `TODO.roadmap/09-compose-recipient-diagnostics.md` (the
inline diagnostics panel) and the MIME parser benchmarks.

## Autocrypt doesn't seem to work

- Verify your outgoing mail includes an `Autocrypt:` header (check
  the message source via Mail → View → Message → Raw Source).
- Verify the recipient's client supports Autocrypt (Thunderbird 115+,
  K-9 Mail, Delta Chat).
- Check that your `prefer-encrypt` setting is `mutual` in
  [Settings](settings.md).

## I lost my keyring passphrase

There is no passphrase-reset flow in OpenPGP. If you have the
paper-key backup AND remember the passphrase, you can restore. If you
forgot the passphrase, the key is unrecoverable. See
[Disaster recovery](disaster-recovery.md).

## Reporting a bug

Open an issue on [GitHub](https://github.com/rnpgp/rnp-mailapp-extension/issues)
with your macOS version, app version, and steps to reproduce. Do not
attach secret keys or message content.

For security vulnerabilities, see [Security policy](SECURITY.md).

## See also

- [FAQ](faq.md)
- [Scenarios](scenarios.md)
- [Settings](settings.md)
- [Disaster recovery](disaster-recovery.md)
