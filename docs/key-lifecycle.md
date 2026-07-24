# Key lifecycle

This page walks through the full life of an OpenPGP key in RNP: creation,
backup, distribution, use, rotation, expiry, revocation, retirement, and
migration. Each stage has a recommended action and a recovery path when
things go wrong. The companion page [Trust model](trust-model.md) covers
the trust-state machine; this page covers the *operational* lifecycle.

## At a glance

```
 ┌─────────┐  publish   ┌────────────┐  TOFU    ┌─────────┐
 │ Create  │───────────▶│ Distribute │─────────▶│  Use    │
 └─────────┘            └────────────┘          └─────────┘
      │                                                  │
      │ paper backup                                     │
      ▼                                                  ▼
 ┌─────────────┐         ┌───────────┐         ┌──────────────┐
 │  Recovery   │◀────────│ Retire    │◀────────│  Rotate /    │
 │  materials  │         │ (archive) │         │  Revoke      │
 └─────────────┘         └───────────┘         └──────────────┘
```

## Creation

New keys are generated in the RNP app (onboarding flow or Keys tab →
**Generate key**). Supported algorithms:

| Algorithm | Use case |
|---|---|
| Ed25519 + Curve25519 | Recommended for new keys. Fast, small, modern. |
| ECDSA P-256 + ECDH P-256 | Modern elliptic-curve; widely compatible. |
| RSA-3072 + RSA-3072 | Maximum compatibility with legacy clients. |

A revocation certificate is generated at creation time and stored in
the app-group container as `<fingerprint>-revocation.asc`.

## Recovery materials

After creation, the app prompts you to save recovery materials. Three
artifacts matter:

1. **Revocation certificate.** Lets you tell the world to stop using the
   key if it is ever lost or compromised. Print it; store it in a
   password manager; do not just leave it in the app-group container
   (if your Mac dies, the cert dies with it).
2. **Paper backup (`paperkey` format).** A hex representation of just
   the secret-key packets, printable on paper. This is the seed of
   trust for disaster recovery.
3. **iCloud Keychain sync (opt-in).** When enabled, the keyring
   passphrase syncs to your iCloud Keychain. On a new Mac, restoring
   the paper backup plus the synced passphrase is enough to read all
   your encrypted mail again.

See [Disaster recovery](TODO.roadmap/01-disaster-recovery.md) for the
full design.

## Distribution

To let correspondents encrypt to you:

- **Publish to a keyserver.** The default is
  [keys.openpgp.org](https://keys.openpgp.org); HKPS and other
  keyservers are configurable. See [Keyservers](keyserver.md).
- **Autocrypt.** Outgoing mail carries an `Autocrypt:` header with
  your minimal public key, so recipients using Thunderbird / K-9 Mail
  / Delta Chat pick it up automatically. See
  [Autocrypt](autocrypt.md).
- **In-person exchange.** Print or share the public key directly.

## Verification

Recipients verify your fingerprint via a trusted channel (in person,
phone call, etc.) and mark the key as **verified**. Until then, the key
is **unverified** (TOFU). See [Trust model](trust-model.md).

## Use

For each message, the engine:

1. Resolves recipient addresses to active (non-archived) keys.
2. Picks the best envelope based on recipient capability (AEAD-OCB +
   v6 PKESK when all support it; AEAD-OCB + v3 PKESK for mixed; CFB +
   MDC when any recipient is legacy).
3. Encrypts and signs (if the user opted in), wrapping in PGP/MIME.

For incoming encrypted mail, the engine decrypts (using any key in the
keyring, including archived ones) and verifies any nested signatures.

## Rotation

When you rotate an encryption subkey, a new subkey is generated and the
old subkey is set to expire after a 30-day grace period (so in-flight
messages still decrypt). The old subkey is then **archived** (kept in
the keyring for decrypt-only use of historical mail).

Signing subkey rotation works the same way. Both are one-click actions
in the key detail view.

## Expiry recovery

RNP detects nine expiry scenarios and offers a recovery path for each.
The full table is in [`TODO.roadmap/04-key-expiry-recovery.md`](TODO.roadmap/04-key-expiry-recovery.md);
the most common ones:

- **Own key expires soon** — extend expiry (default +2 years), publish,
  optionally notify contacts.
- **Own key expired, secret available** — same as above; old mail still
  decrypts.
- **Own key expired, secret lost** — generate a replacement; run the
  key-transition wizard if you have a revocation certificate.
- **Recipient's key expired** — fetch the latest from keyserver; if
  still expired, contact them out-of-band.

The Key Health view (in the RNP app) lists every key with a status chip
and a one-click recovery action.

## Revocation

When a key is compromised or retired, revoke it:

1. Revoke with a reason code (`no`, `superseded`, `compromised`,
   `retired`).
2. Publish the revoked key so others refresh.
3. The key is auto-archived (decrypt-only) so historical mail still
   decrypts.

The revocation certificate generated at key-creation time can be used
to revoke even if you have lost the secret material — that is what it
is for.

## Retirement (archive)

Archiving a key makes it decrypt-only. It disappears from the default
key list and is never selected for new signing or encryption. It
remains in the keyring so mail encrypted to it still decrypts.

Archive is reversible. "Delete forever" is not — it requires typing the
fingerprint to confirm.

## Migration to a new key

The key-transition wizard walks through the full migration flow:

1. Generate a new key, copying UIDs from the old key.
2. Certify the new key's UIDs with the old key (transition signature).
3. Revoke the old key with reason `superseded`, naming the new key.
4. Archive the old key.
5. Publish the new key; notify contacts.

Recipients who refresh see both keys, the certification linking them,
and the revocation directing them to the new one. Trust relationships
are preserved.

See [`TODO.roadmap/05-key-transition-wizard.md`](TODO.roadmap/05-key-transition-wizard.md).

## See also

- [Trust model](trust-model.md)
- [Keyservers](keyserver.md)
- [Autocrypt](autocrypt.md)
- [Security model](SECURITY-MODEL.md)
- [Post-quantum cryptography](post-quantum.md)
