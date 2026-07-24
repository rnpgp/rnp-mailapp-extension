# Scenarios

Step-by-step walkthroughs for the situations users actually find themselves
in. Cross-linked from [Usage](usage.md) and the [FAQ](faq.md). Each
scenario says what to do, why, and where to look if something goes wrong.

## Onboarding and first use

### Scenario: I just installed RNP and want to send my first encrypted email

1. **Open the RNP app** from Applications (or Launchpad). On first launch
   the onboarding wizard appears.
2. **Generate a key** in the wizard:
   - Enter your real name and the email address you send mail from.
   - Algorithm: **Ed25519** (recommended for new keys; smaller and faster
     than RSA).
   - Expiry: 2 years (default). Adjustable later.
   - Passphrase: leave blank to let RNP generate a strong one and store
     it in Keychain, or enter your own.
   - Touch ID: recommended ON for daily use.
3. **Save your recovery materials** when prompted:
   - Print the **revocation certificate** (or save to a password
     manager).
   - Print the **paper-key backup** and store somewhere offline.
   - Choose whether to sync the keyring passphrase via **iCloud
     Keychain**.
4. **Publish your public key** so others can encrypt to you:
   - Keys tab → your key → Publish.
   - Default keyserver is `keys.openpgp.org`; you'll get an email
     verification link per user ID.
5. **Enable the Mail extension**:
   - Open Mail → Settings → Extensions.
   - Enable "RNP OpenPGP".
6. **Send your first encrypted email**:
   - Compose a message in Mail to a contact whose key you have.
   - Click the security button in the compose toolbar; toggle Encrypt
     and Sign.
   - Send. The recipient receives a `multipart/encrypted` PGP/MIME
     message.

**Where to look if it doesn't work:**
- If the Encrypt toggle is dimmed: you don't have a key for one of the
  recipients. Use the per-recipient diagnostics panel in compose to see
  which. See *Scenario: my recipient doesn't have a key*.
- If Mail does not show the RNP extension: relaunch Mail, or rebuild
  the launch services database (`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user`).

### Scenario: I already have a PGP key in GnuPG and want to use it in RNP

1. In GnuPG: `gpg --export-secret-keys --armor <keyid> > secret.asc`.
2. Open RNP app → Keys tab → Import → File.
3. Select `secret.asc`. Enter the key's existing passphrase when
   prompted; RNP offers to either save it in Keychain (per-key) or
   re-protect the key with the keyring passphrase (recommended).

**Where to look if it doesn't work:**
- If import fails with "unknown packet type": your GnuPG may emit v6 or
  experimental packets RNP does not yet parse. Export with
  `--rfc4880-only` if available.

## Recovery and disaster

### Scenario: my Mac died and I need to recover my encrypted mail

1. On the new Mac: install RNP from the App Store or the direct
   download.
2. Open the RNP app → choose "Restore from backup" in onboarding.
3. Enter your paper-key (paste or type the hex). RNP reconstructs the
   secret key.
4. The keyring passphrase syncs via iCloud Keychain (if you opted in);
   otherwise enter it manually.
5. All your old encrypted mail now decrypts.

**Where to look if it doesn't work:**
- If the paper-key parser rejects the input: there's a typo. The hex
  formatter groups bytes 6 at a time; check the line wrapping.
- If the keyring passphrase is wrong: try variations; if you have
  forgotten it, the key is unrecoverable. Generate a new key and use
  the revocation certificate to retire the old one.

### Scenario: I forgot my keyring passphrase

You cannot recover the passphrase. Your options:

1. **Reset the keyring**: lose all encrypted mail encrypted to your
   existing keys (devastating).
2. **Use individual-key passphrases** you may have stored per-key.
3. **Restore from paper-key backup** if you have one (this also
   requires the passphrase — so this only works if you remember it
   eventually).

We deliberately do not offer a passphrase-reset flow because there is
no secure way to do one in OpenPGP. See
[Security model](SECURITY-MODEL.md).

## Expiry and rotation

### Scenario: my key is about to expire

1. RNP app → Key Health tab.
2. The expiring key shows an amber chip with the days remaining.
3. Click **Extend expiry**. Default is +2 years; pick what you want.
4. Click **Publish** so correspondents refresh.
5. Optionally click **Notify contacts** to send a templated email to
   people who encrypted to you recently.

**Where to look if it doesn't work:**
- If the **Extend** button is disabled: you may not have the secret
  material locally (the key is public-only, or archived). Use **Generate
  replacement** instead, which walks you through the key transition
  wizard.

### Scenario: my key has already expired

Same as above, but the banner is red and the **Extend** action is the
only one available. Old encrypted mail still decrypts; you cannot sign
or be encrypted-to until you extend or rotate.

### Scenario: I want to rotate my encryption subkey (e.g., annual hygiene)

1. RNP app → Keys tab → your key → detail.
2. Click **Rotate encryption subkey**.
3. Confirm. A new `cv25519` (or matching algorithm) subkey is generated.
   The old subkey expires after a 30-day grace period and is then
   archived (decrypt-only).
4. Click **Publish** and **Notify contacts**.

In-flight encrypted mail sent during the grace period still decrypts;
new encrypted mail to you uses the new subkey.

### Scenario: I lost my key's secret material (laptop + backup both gone)

1. If you have a revocation certificate: import it (`rnpmail://revoke/`)
   to publish the revocation.
2. Generate a new key in the RNP app.
3. Manually notify your contacts out-of-band (encrypted mail is now
   impossible until they get your new key).
4. Have them verify your new fingerprint via a trusted channel.

This is the worst case. There is no in-band recovery. See
[Disaster recovery](TODO.roadmap/01-disaster-recovery.md).

## Trust and verification

### Scenario: someone sent me encrypted mail I can't read

1. Open the message in Mail. The RNP banner shows why:
   - **"Encrypted to a key you don't have (key ID ABCDEF…). [Fetch]"**
     — click Fetch to look up the key ID on a keyserver. If you find it,
     import and the message decrypts.
   - **"Encrypted to your archived key …"** — you archived the matching
     key. Click **Restore** to un-archive it.
   - **"Encrypted with a passphrase"** — symmetric encryption; ask the
     sender for the passphrase and enter it in the banner.
   - **"This message was tampered with"** — integrity failure. Do not
     trust the contents; contact the sender via another channel.
   - **"Encrypted with X, which this version of RNP doesn't support"**
     — update RNP; if it's already current, ask the sender what client
     they used.

### Scenario: my contact's key changed

1. RNP app → Key Health shows a red **conflict** chip for that contact.
2. Encryption to that contact is **blocked** until you resolve.
3. Click **Verify fingerprint**. Compare the new fingerprint with the
   contact out-of-band (in person, phone call, etc.).
4. If it matches: click **Mark as verified**. Encryption unblocks.
5. If it doesn't match: leave it blocked. The change is likely a
   key-substitution attack.

### Scenario: I want to mark a contact as verified (after comparing fingerprints)

1. RNP app → Recipients tab → the contact's key → detail.
2. Click **Mark as verified**.
3. From now on, Mail's banner shows a green verified indicator for
   messages signed by that key.

## BCC

### Scenario: I want to BCC someone on an encrypted email

You can't, in a single encrypted message. PGP/MIME encrypts one
ciphertext for all recipients, and any decrypting recipient can see the
recipient list — including BCC.

When you attempt to send encrypted with BCC, RNP refuses and offers:

1. **Send separately** — RNP creates one encrypted message for To+Cc
   and one separate encrypted message per BCC recipient. Each BCC
   recipient sees only themselves.
2. **Remove encryption** — send plaintext (or signed-only) so BCC works
   normally.
3. **Remove BCC** — encrypt as a single message to To+Cc only.

Pick option 1 if you need both encryption and BCC. See
[Usage — BCC on encrypted mail](usage.md#bcc-on-encrypted-mail).

## Migration

### Scenario: I want to migrate to a new key

Use the **Key transition wizard** (Key Health → Migrate to new key…):

1. Generate a new key (RNP copies your existing UIDs onto it).
2. The wizard certifies the new key with the old key (a "transition
   signature").
3. The old key is revoked with reason `superseded`, naming the new key.
4. The old key is **archived** (decrypt-only) so historical mail still
   decrypts.
5. The wizard publishes both keys and offers to notify contacts.

Recipients who refresh see the certification linking the two keys and
trust continuity is preserved.

### Scenario: I want to use post-quantum encryption

Three settings (Settings → Encryption → Post-quantum):

- **Classical (default)**: Ed25519 / RSA / ECDSA. Recipients still
  receive hybrid encryption when their key advertises a hybrid KEM
  subkey — that happens automatically.
- **Hybrid**: ML-DSA-65+ED25519 signing + ML-KEM-768+X25519 encryption.
  Larger keys; maximum long-term confidentiality.
- **Conservative**: SLH-DSA-SHA2 (hash-based) signing + classical
  ECDH-Curve25519 encryption. For users who distrust lattice-based
  cryptography.

See [Post-quantum cryptography](post-quantum.md) for the full trade-off
table.

## Multi-device and multi-account

### Scenario: I want one key for both my work and personal email

Use **multi-UID keys**:

1. Generate (or use) one key for your primary email.
2. RNP app → key detail → **Add user ID**.
3. Enter your other email address (real name optional).
4. Optionally mark the new UID as primary.
5. Publish.

Now both email addresses resolve to the same key. Recipients encrypting
to either address use the same key.

### Scenario: I want to read encrypted mail on a second Mac

1. On Mac #1: RNP app → key detail → **Export secret key (armored)**.
2. Transfer the file to Mac #2 (encrypted USB, AirDrop to a sandboxed
   destination, etc.).
3. On Mac #2: RNP app → Import → File. The secret key is added to the
   keyring.

If you enabled iCloud Keychain sync for the passphrase (recovery
wizard), Mac #2 picks up the passphrase automatically. Otherwise enter
it manually.

## Compose

### Scenario: I want to send my public key to someone

Three paths:

1. **Publish to keyserver** (default). Most long-term contacts refresh
   from keyservers; no per-message action needed.
2. **Autocrypt**: every signed or encrypted mail you send carries your
   minimal public key in the `Autocrypt:` header. Recipients using
   Thunderbird / K-9 / Delta Chat pick it up automatically.
3. **Attach manually** to a message: RNP app → key detail → **Copy
   public key** → paste into Mail.

### Scenario: I'm replying to an encrypted message

RNP defaults replies to encrypted-and-signed when:

- The original message was encrypted.
- The original sender has a usable key in your keyring.
- You haven't manually disabled encryption in the compose toolbar.

The compose banner shows "Replying to an encrypted message; defaults
set to encrypted + signed." Override via the toolbar if needed.

## See also

## Settings

### Scenario: I want to switch from "automatic" envelope to "force AEAD"

If you only correspond with modern clients and want to ensure no
legacy encryption ever goes out, change the envelope policy:

1. **Settings → Encryption → Envelope.**
2. Choose **Force AEAD**.
3. Recipients without AEAD-capable keys will be flagged at compose
   time and encryption will be refused.

See [Settings](settings.md).

### Scenario: I want Autocrypt to be silent for my work account

Per-account Autocrypt prefer-encrypt lets you opt out for specific
addresses (e.g. a shared mailbox) without disabling Autocrypt
globally.

1. **Settings → Encryption → Autocrypt per-account.**
2. Add an override for the address; pick **No preference** or
   **Disable**.

Outgoing mail from other addresses keeps its global setting.

## Mailbox scan

### Scenario: I want to populate my keyring from mail I already have

1. **Settings → Mailbox scan → Re-run.**
2. RNP scans local mail for Autocrypt headers, `application/pgp-keys`
   attachments, and embedded signing keys.
3. The results list shows each discovered key with its source.
4. Click **Import** per key, or **Import all** for bulk.

The scan runs locally; nothing is sent anywhere. See
[Finding keys for your contacts](usage.md#finding-keys-for-your-contacts).

## Post-quantum

### Scenario: I want my new key to be post-quantum secure

1. **Settings → Encryption → Post-quantum.**
2. Pick **Hybrid PQ** (recommended) or **Conservative**.
3. **Keys → Generate key**. New keys use the chosen algorithm family.
4. Existing keys are not changed; encrypt-and-decrypt to them
   continues normally.

Recipients still receive hybrid PQ encryption when their key
advertises a hybrid KEM subkey — that happens automatically inside
the engine, regardless of this setting.

See [Post-quantum cryptography](post-quantum.md).

## Archive

### Scenario: I want to retire a key but keep decrypting old mail

1. **Keys → your key → Archive.**
2. The key moves to the Archived section; it is no longer used for
   new operations but old encrypted mail still decrypts.
3. To reverse: **Keys → Archived → Restore to active**.

### Scenario: I want to permanently delete a key

1. **Keys → Archived → [the key] → Delete forever….**
2. The sheet asks you to type the full fingerprint to confirm.
3. All mail encrypted to the key becomes undecryptable.

Use sparingly. Archive is reversible; delete-forever is not.

## See also

- [Usage](usage.md)
- [FAQ](faq.md)
- [Key lifecycle](key-lifecycle.md)
- [Trust model](trust-model.md)
- [Autocrypt](autocrypt.md)
- [Post-quantum cryptography](post-quantum.md)
- [Encrypted mail and search](encrypted-mail-search.md)
- [Security model](SECURITY-MODEL.md)
