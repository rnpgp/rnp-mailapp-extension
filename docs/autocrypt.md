# Autocrypt

RNP implements [Autocrypt](https://autocrypt.org/) level 1: the email-
embedded key-distribution standard used by Thunderbird, K-9 Mail,
Delta Chat, Mailpile, and others. With Autocrypt, your public key
travels inside every outgoing message you send, so recipients'
clients can pick it up automatically — no keyserver round-trip, no
manual import.

## How it works

Every signed or encrypted message you send carries an `Autocrypt:`
header with your minimal public key. When someone receives a message
from you, their Autocrypt-aware client:

1. Parses the header.
2. Stores your key against your email address.
3. Uses the latest-seen key as the encryption target for future
   outgoing mail to you.

If a later message from you carries a different key (e.g., after
rotation), the new key replaces the old one. Conflicts (a third party
spoofing a different key from your address) are handled by the same
trust-change detection that protects keyserver refreshes.

## Settings

In Settings → Encryption → Autocrypt:

- **prefer-encrypt = mutual (default).** When both you and a recipient
  advertise `mutual`, RNP defaults outgoing mail to encrypted. This is
  "opportunistic encryption": if both parties have keys, mail is
  encrypted automatically.
- **prefer-encrypt = nopreference.** Encrypt only when you explicitly
  choose to.
- **prefer-encrypt = encrypt.** Like `nopreference` but never
  opportunistic.
- **disable.** Do not emit Autocrypt headers on outgoing mail.

## Reading Autocrypt mail from others

When you receive mail from a Thunderbird / K-9 / Delta Chat user who
has Autocrypt enabled, RNP captures their key automatically. The key
lives in the Autocrypt store (a per-address cache, separate from your
main keyring) and is used for opportunistic encryption.

To use a captured key outside of opportunistic encryption (e.g., to
encrypt your first reply), nothing extra is needed — the engine's
recipient resolution considers both the main keyring and the Autocrypt
store.

## Interop

Verified interop with:

- Thunderbird 115+ (Autocrypt on by default for new accounts).
- K-9 Mail (Android).
- Delta Chat.

Known limitations:

- **Autocrypt Setup Message** (transferring your secret key between
  devices via a special encrypted MIME part) is **not** implemented.
  For multi-device secret-key transfer, use the
  [recovery flow](TODO.roadmap/01-disaster-recovery.md) instead.
- **Autocrypt-Gossip** (level 1.1 — sharing recipients' keys in CC'd
  multi-recipient mail) is reserved for a future release.

## Privacy considerations

- The `Autocrypt:` header is visible in transit (it is a normal RFC 5322
  header). Anyone watching the message can see that you use Autocrypt,
  but cannot read the message body.
- The key in the header is your **public** key. Disclosing it is the
  whole point.
- The header adds ~300 B (Ed25519) to ~3.5 KB (hybrid PQ) per outgoing
  message. Negligible for most mail; measurable for very high-volume
  senders.

## See also

- [Key lifecycle](key-lifecycle.md)
- [Keyservers](keyserver.md) — the other distribution mechanism
- [Autocrypt spec (level 1)](https://autocrypt.org/level1.html)
