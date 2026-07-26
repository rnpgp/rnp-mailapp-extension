# Disaster recovery

If you lose your Mac — to theft, hardware failure, or any other cause —
you want to be able to read your encrypted mail again on a new Mac within
an hour. This page is the operator's manual for that scenario, and for
the steps you take **before** disaster strikes so the recovery is
possible.

This page complements the [Key lifecycle](key-lifecycle.md) overview
with the disaster-specific details.

## The three artifacts that matter

There are three pieces of recovery material. Without **any one of them**,
recovery is impossible or severely degraded.

1. **Revocation certificate** — a small ASCII-armored file that lets you
   tell the world "stop using this key." Generated automatically when
   you create a key. Without it, you cannot retire a compromised or
   lost key on the keyserver.
2. **Paper-key backup** — a hex dump of just the secret-key packets,
   suitable for printing on paper. Without it, you cannot restore the
   ability to decrypt historical mail on a new Mac.
3. **Keyring passphrase** — the master passphrase that decrypts the
   secret-key material on disk. Without it, the paper-key is just
   unreadable bytes.

RNP's recovery wizard (`RNP app → Keys → your key → Save recovery
materials`) walks you through saving all three. You can re-enter the
wizard at any time.

## Saving recovery materials (before disaster)

### Option A: Save to a password manager (recommended)

The revocation certificate and paper-key are both text. Paste them into
a secure note in 1Password, Bitwarden, Apple Passwords, or any other
end-to-end-encrypted password manager. The Keychain on your Mac is NOT
sufficient — it doesn't survive Mac loss unless iCloud Keychain sync is
on.

### Option B: Print on paper

The paper-key format is designed for printing. Use the "Print" button in
the recovery wizard. Store the paper somewhere safe and offline (safe,
lockbox, safety deposit box). Do not store it next to your Mac.

### Option C: iCloud Keychain sync (for the passphrase only)

The recovery wizard offers to sync the keyring passphrase to your
iCloud Keychain. This is opt-in. With it on, you do not need to
remember the passphrase — Apple's Keychain provides it on any of your
Apple devices. Without it, you must remember the passphrase yourself or
store it in a password manager.

iCloud Keychain is end-to-end encrypted by Apple. The threat model is
"trust Apple's E2EE and your iCloud password." If you do not trust
that, do not enable this option.

### Option D: Trusted contact

You can give a copy of the paper-key and passphrase to a trusted
contact (lawyer, spouse). They hold it for you and produce it on
request. This is the strongest hedge against "I lost the paper and
forgot the passphrase."

## Restoring on a new Mac (after disaster)

The recovery wizard runs in reverse:

1. **Install RNP** on the new Mac from the App Store or direct download.
2. **Launch the app**, choose "Restore from backup" in onboarding.
3. **Paste or type your paper-key**. RNP reconstructs the secret key
   packets. The hex parser is whitespace-insensitive and tolerant of
   line wrapping, so OCR or manual typing usually works.
4. **Enter the keyring passphrase** when prompted. If you opted in to
   iCloud Keychain sync, this happens automatically.
5. **Wait for the keyring to rebuild**. Takes a few seconds.
6. **Re-publish your key** (optional but recommended) so contacts know
   you are still reachable.

All your old encrypted mail now decrypts.

## Edge cases

### I lost the paper-key but still have the Mac

You got lucky. Re-run the recovery wizard immediately and save a new
paper backup. Then store it somewhere safer.

### I lost the paper-key and the Mac is gone

You cannot recover the secret material. Your options:

1. Generate a **new key** in the RNP app.
2. Use the **revocation certificate** (if you saved it) to revoke the
   old key with reason `superseded`. This stops others from continuing
   to encrypt to the lost key.
3. **Notify your contacts** out-of-band that you have a new fingerprint.
   The RNP app's `Key Health → Notify contacts` flow produces a
   template email.
4. **Accept that all encrypted mail sent to the lost key is unreadable**.
   There is no cryptographic workaround.

### I forgot the keyring passphrase

OpenPGP does not have a passphrase-reset flow. Without the passphrase,
the secret keyring is unreadable, even with the paper-key.

If you enabled iCloud Keychain sync and you still have access to your
Apple ID, the passphrase is still there — open Keychain Access on any
Mac signed in to the same iCloud and look for "RNP for Mail
keyring."

Otherwise: the situation is unrecoverable. Generate a new key, revoke
the old one (if you still have the revocation certificate), notify
contacts.

### My contact can't decrypt mail I sent

If your recipient says "I can't read your encrypted mail," the most
likely causes are:

- They refreshed from the keyserver and got a stale or revoked copy of
  your key. Re-publish.
- They verified your old fingerprint but you rotated to a new subkey.
  Their client should refresh and pick up the new subkey automatically;
  if not, ask them to re-import.
- Their mail client doesn't support AEAD/v6 and you forced it on. The
  default is "automatic," which falls back to legacy. Check
  `Settings → Encryption → Envelope policy` and reset to automatic if
  needed.

### My own archived key can't decrypt anything

Archived keys are decrypt-only by design. If decryption is failing for
an archived key, the most common cause is the keyring passphrase being
wrong. Check that the passphrase is correct via the RNP app's
`Settings → Security → Verify keyring passphrase`.

If the archived key was somehow deleted (a "Delete forever" path),
recovery is impossible. The whole point of archiving rather than
deleting is to avoid this scenario.

## Threat model summary

| Asset | Protected against | Not protected against |
|---|---|---|
| Paper-key in password manager | Mac loss, Mac theft | Compromised password manager; forgotten master password |
| Paper-key on paper | Compromised password manager; Mac loss | Physical theft of paper; fire/flood |
| iCloud Keychain sync | Mac loss | Compromised Apple ID; forgotten Apple ID password |
| Revocation certificate | Forgetting passphrase (still allows retiring the key) | Loss of the cert itself; revoking by accident |
| Trusted-contact copy | All of the above | Trusted contact becoming untrusted |

For a deeper threat model see [Security model](SECURITY-MODEL.md).

## See also

- [Key lifecycle](key-lifecycle.md) — the operational picture.
- [Scenarios](scenarios.md) — step-by-step walkthroughs including the
  "I lost my Mac" scenario.
- [Security model](SECURITY-MODEL.md) — full threat model.
- [Trust model](trust-model.md) — what happens when fingerprints
  change.
