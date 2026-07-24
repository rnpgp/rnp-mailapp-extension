# 01 — Disaster recovery: paper backup, recovery sheet, iCloud Keychain sync

Status: pending · Tier: A · Depends on: nothing

## Goal

A user who loses their Mac must be able to recover access to all their
encrypted mail in less than an hour, with no support ticket. Today they
cannot: the secret key lives in the app-group keyring; the passphrase lives
in the local Keychain; neither is recoverable from a fresh install.

## Why this is Tier A

This is the single biggest blocker to recommending the product to anyone
whose mail actually matters. The conversation that plays out without it:

> "I installed RNP, encrypted mail for two years, my Mac died, and now I
> can't read any of it. There was no warning. There was no backup. You
> ruined two years of correspondence."

We can either solve this before release or have it as the #1 complaint in
the App Store reviews.

## The threat model for recovery

Three things need to survive device loss:

1. **Secret-key material** (the actual private keys). Must come from a
   user-controlled backup: paper (`paperkey`), encrypted USB, password
   manager, or a trusted contact. We do not sync the secret key to iCloud
   Drive — too many ways for that to leak.
2. **Keyring passphrase.** Can sync via iCloud Keychain
   (`kSecAttrSynchronizable = true` on the generic password item) because
   Apple Keychain sync is end-to-end encrypted and the passphrase alone is
   useless without the secret key.
3. **Revocation certificates.** Must be exportable to paper / password
   manager; never just live in the app-group container.

## Design

### 1. `paperkey`-style export

Add `Rnp.exportSecretKeyPaper(fingerprint:) -> String` returning a hex
representation of the secret-key packets (matching the `paperkey` tool's
output format so it can be re-imported by upstream `paperkey | gpg
--import` on Linux). Format:

```
# RNP paperkey backup
# Key fingerprint: <FPR>
# Created: <ISO date>
# Algorithm: <algo + bits>
#
# To restore: paperkey --restore < this-file | gpg --import
# Or:        paste into RNP app → Import → Paper backup
<paperkey-compatible hex lines>
```

Also support **QR codes** for shorter keys (Ed25519 + cv25519 fits in ~10 QR
codes; QR a 2D barcode with Reed-Solomon error correction so partial print
decay survives). For RSA-3072 the hex is long; QR works but the user prints
multiple pages.

UI: from a key's detail view → "Print paper backup…" opens a print dialog
with the hex + QR + recovery instructions laid out for an 8.5×11 sheet.

### 2. Recovery sheet wizard

At the end of onboarding (after key generation), an interrupting sheet
titled **"Save your recovery materials"** with three steps. Each step has
"Done" and "Skip for now"; "Skip for now" is sticky (the wizard re-appears
on next launch until at least the paper backup step is completed).

1. **Print your revocation certificate.** "If your key is ever lost or
   compromised, this certificate tells the world to stop using it. Print it
   now and store it somewhere safe — without it, you cannot revoke your
   key." Buttons: [Print revocation cert] [Save to 1Password…] (writes the
   `.asc` as an attachment to a new 1Password item via share extension).
2. **Print your paper backup.** "This lets you restore all your encrypted
   mail on a new Mac. Store it somewhere safe and offline. Anyone with this
   paper and your passphrase can read your mail." Button: [Print paper
   backup].
3. **Sync your passphrase to iCloud Keychain?** "If you turn this on, your
   keyring passphrase syncs to your iCloud Keychain. On a new Mac, you'll
   only need to restore the paper backup — the passphrase comes
   automatically. iCloud Keychain is end-to-end encrypted by Apple."
   Buttons: [Use iCloud Keychain sync] [Keep passphrase on this Mac only].

### 3. iCloud Keychain sync (opt-in)

`KeychainPassphraseStore`: when the user opts in (or via Settings →
Security), re-create the generic password item with
`kSecAttrSynchronizable = kCFBooleanTrue`. The access-control constraints
already in place (Touch ID ACL when enabled) compose with the synchronizable
attribute.

Document: when the user changes the passphrase, the synchronized item is
updated automatically. When the user turns the setting off, the item is
re-created with `kSecAttrSynchronizable = kCFBooleanFalse` (the previous
synchronized copy is removed by the system on the next sync).

### 4. Restore flow

In onboarding, "Restore from backup" path:

1. "Do you have your paper backup?" — [Yes, paste/type] [No, scan QR] (later).
2. User enters the hex (or scans QR pages).
3. App reconstructs the secret key, asks for the passphrase (auto-filled
   from iCloud Keychain if synced, else prompted).
4. Keyring restored. All old encrypted mail decrypts.

## Tests

- `paperkey` round-trip: generate Ed25519 + RSA-3072 → export paper →
  re-import via the hex path → fingerprint and secret-key presence match.
  Cross-check with upstream `paperkey` tool if installed (skip in CI).
- Recovery wizard completion: tests for the SwiftUI flow driving each step
  to "Done" and to "Skip for now" (skip is sticky).
- iCloud Keychain sync: unit-test the attribute set on the Keychain item;
  do not actually exercise iCloud sync in CI (no Apple ID available).
- Restore flow: a fixture paper backup re-imports successfully and the
  fixture's encrypted test message decrypts.

## Acceptance criteria

- A new user who completes onboarding ends the session with: a revocation
  cert in their password manager or on paper, a paper backup in a safe
  place, and a conscious decision about iCloud Keychain sync — no
  exceptions.
- A simulated device-loss scenario (delete app + container + Keychain)
  recovers all encrypted test mail within five minutes, given the paper
  backup and the iCloud-synced passphrase.
- The wizard cannot be permanently dismissed without doing at least the
  paper backup step.

## Notes / risks

- **QR scanning** is not in scope for the first cut; paste/type is enough.
  Scanning can land in a follow-up.
- **Secret-key sync via iCloud Drive** is deliberately out of scope. The
  threat model favors user-controlled offline storage; iCloud Drive sync
  would shift trust to Apple's E2EE guarantees and the user's iCloud
  password.
- **Recovery from a forgotten passphrase** is impossible in OpenPGP by
  design; do not pretend otherwise. The wizard should say this explicitly
  when the user skips paper backup.
- The wizard should not nag users who use a single imported existing key
  (e.g., migrated from GnuPG) — they likely have a paper backup already.
  Detect this and offer the wizard as a menu item instead of an interrupt.
