# Settings

RNP exposes its configurable behavior in **Settings**, accessible from
the **RNP** menu (`⌘,`) inside the container app. This page documents
each section.

## Encryption

### Encryption envelope

Controls which OpenPGP encryption envelope RNP uses when encrypting
outgoing mail. Recipients must support the chosen envelope to decrypt.

- **Automatic (recommended).** AEAD-OCB + v6 PKESK when every
  recipient supports it; falls back to AEAD-OCB + v3 PKESK for mixed
  recipients; falls back to CFB + MDC when any recipient is legacy.
- **Force AEAD.** Refuses to encrypt when any recipient lacks AEAD
  support. Use when you only correspond with modern clients.
- **Force legacy.** Always uses CFB + MDC. Maximum compatibility with
  very old PGP clients.

The envelope policy applies per-message based on recipient capability
(probed via each recipient's primary UID self-signature features
subpacket).

### Autocrypt prefer-encrypt

Controls how RNP's Autocrypt advertisement influences opportunistic
encryption on the recipient's side.

- **Mutual (recommended).** Encrypt when both parties opt in. The
  default for new accounts.
- **No preference.** Encrypt only when you explicitly choose to.
- **Encrypt only (manual).** Never opportunistic; user-initiated only.
- **Disable.** Do not emit Autocrypt headers on outgoing mail.

See [Autocrypt](autocrypt.md) for the full interop picture.

### Post-quantum key generation

Controls the algorithm family RNP uses when generating new keys.

- **Classical (default).** Ed25519, RSA-3072, or ECDSA P-256.
- **Hybrid PQ.** ML-DSA-65+ED25519 signing + ML-KEM-768+X25519
  encryption. Larger keys; maximum long-term confidentiality.
- **Conservative.** SLH-DSA-SHA2 (hash-based) signing with classical
  ECDH-Curve25519 encryption. Very large signatures.

This setting affects only new-key generation. Encryption to existing
recipients is always driven by their key's advertised capability, not
by this setting. See [Post-quantum cryptography](post-quantum.md).

## Security

### Touch ID

- **Unlock keyring with Touch ID.** When enabled, the keyring
  passphrase is stored in a Keychain item with a biometric ACL; every
  read requires Touch ID (with login-password fallback).
- **Require Touch ID for each operation.** Stricter mode that re-
  challenges Touch ID before every sign / encrypt / decrypt operation
  after a configurable session timeout (default 30 seconds).

See [Disaster recovery](disaster-recovery.md) for what each setting
means for recovery scenarios.

### Keyring passphrase

- **Change passphrase.** Re-protects every secret key in the keyring
  with a new passphrase. The Keychain entry is updated to match.
- **Verify passphrase.** Sanity check that the current passphrase is
  correct (useful after a long absence).
- **iCloud Keychain sync.** Toggles `kSecAttrSynchronizable` on the
  passphrase item so it syncs across your Apple devices.

## Keyservers

- **Default upload server.** `keys.openpgp.org` (VKS) by default.
- **Additional HKPS servers.** Add or remove HKPS servers used for
  discovery; defaults include `keyserver.ubuntu.com`.
- **WKD discovery.** Toggle Web Key Directory lookups (on by default).
- **Refresh interval.** How often recipient keys are refreshed from
  keyservers (default 24 hours).

See [Keyservers](keyserver.md) for the privacy implications.

## Mailbox scan

- **Re-run mailbox scan.** Re-scans local mail for Autocrypt headers,
  `application/pgp-keys` attachments, and embedded signing keys.
  Useful after a major folder sync.

See [Finding keys for your contacts](usage.md#finding-keys-for-your-contacts).

## Notifications

- **Expiry warnings.** Show a banner when any of your keys expires in
  ≤ 60 days.
- **Key-change conflicts.** Show a banner when a contact's key
  fingerprint changes.

## Diagnostics

- **Self-test.** Launches the app with `--self-test`, which builds a
  fresh Rnp context, prints the version string, and exits 0 if all
  checks pass. See [Telemetry and privacy policy](TELEMETRY.md).
- **View logs.** Opens the in-app log viewer. Logs are local-only;
  nothing is sent anywhere without your explicit action.

## See also

- [Usage](usage.md)
- [Scenarios](scenarios.md)
- [Trust model](trust-model.md)
- [Key lifecycle](key-lifecycle.md)
- [Autocrypt](autocrypt.md)
- [Post-quantum cryptography](post-quantum.md)
- [Disaster recovery](disaster-recovery.md)
