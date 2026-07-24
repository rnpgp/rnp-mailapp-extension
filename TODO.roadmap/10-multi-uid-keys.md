# 10 — Multi-UID keys: one key, multiple email addresses

Status: pending · Tier: B · Depends on: nothing

## Goal

Allow a single primary key to carry multiple user IDs (work email + personal
email + alias), with the user choosing which is primary. Today every key
has exactly one UID, which forces users to maintain separate keys for
separate addresses.

## Why this is Tier B

Multi-UID is how PGP was designed to work. The current single-UID
restriction is artificial — librnp fully supports multiple UIDs, and the
FFI (`rnp_key_add_uid`, `rnp_key_signature_set_primary_uid`) is verified
present in `Sources/CRnp/rnp/rnp.h:2501` and `:1724`.

Users with two email accounts (e.g., `alex@work.com` and
`alex@personal.com`) currently have to either pick one address for their
PGP identity or maintain two separate keys. Multi-UID solves this and
makes Autocrypt (07) work correctly when the user picks the right From
address per message.

## Design

### FFI surface (already in `Rnp/RnpKey.swift` partially)

Add:

- `RnpKey.addUID(_ uid: String, passphrase: String) throws` — calls
  `rnp_key_add_uid` with self-signature. UID format is RFC 5322 `"Real
  Name <email>"` like the existing generate flow.
- `RnpKey.setPrimaryUID(_ uid: String) throws` — calls
  `rnp_key_signature_set_primary_uid` on the UID's most recent self-sig.
- `RnpKey.revokeUID(_ uid: String, reason: RevocationReason) throws` — for
  retiring an email address on an existing key.
- Extend `KeyInfo.userIDs: [String]` → `KeyInfo.userIDs: [UserInfo]` where
  `UserInfo` carries `uid`, `isPrimary`, `isRevoked`, `creationDate`.

### Generate flow

In `OnboardingView` and `GenerateKeyForm`, add a "+ Add another email"
button that appends another (name, email) pair. All emails become UIDs on
the same primary key. The first email is primary by default; the user can
change this with a radio.

### Existing-key flow

In `KeyDetailView`, "+ Add user ID" button opens a sheet:

```
Add user ID
───────────
Real name: [Alex Wong        ]
Email:     [alex@personal.com]

[ ] Make this the primary user ID

                       [Cancel]  [Add]
```

The new UID is self-signed with the primary key (requires the secret
unlocked; Touch ID prompt if enabled). After adding, publish is queued
automatically (or after explicit [Publish], per user setting).

### Primary UID selection

In the UID list on `KeyDetailView`, each row has a context-menu option
"Set as primary." Switching primary requires a new self-signature with the
primary-UID subpacket set; the old primary loses the flag.

This matters because: when the engine picks which UID to put in
`Autocrypt:` headers (07), or which UID to display in Mail's banner, the
primary UID is the default.

### Revoking a UID

Per-UID revocation (different from key revocation) marks one email address
as no longer belonging to this key. Useful when an email address is
retired (e.g., leaving a job). Calls `rnp_uid_revoke` if exposed by FFI;
verify.

### Migration

Existing single-UID keys continue to work unchanged. The first launch after
this feature ships detects keys with multiple UIDs already present
(imported from GnuPG) and displays them correctly.

## Tests

- Generate a key with 2 UIDs → both UIDs are listed → fingerprint is one
  key not two.
- Add a UID to an existing key → UID is signed by primary → keyring
  refresh on a second machine shows the new UID.
- Set primary UID → new self-sig has primary-UID flag set (verify via
  `rnp_dump_packets` JSON).
- Revoke a UID → UID is marked revoked in the keyring; the address no
  longer resolves to this key for encryption.
- GnuPG interop: a key with multiple UIDs exported from GnuPG imports
  correctly; the same key exported from RNP imports in GnuPG showing all
  UIDs.

## Acceptance criteria

- A user can generate a key with up to (no fixed limit, but warn at 10)
  email addresses, with one designated primary.
- The primary UID is used for Autocrypt header generation and Mail banner
  display by default.
- Documentation: `docs/key-management.md` gains a "Multiple email addresses
  on one key" section.

## Notes / risks

- Adding a UID requires the secret unlocked. If Touch ID per-operation is
  on (TODO.impl), prompt.
- Don't conflate UIDs with email accounts in Mail. A user can have a
  single key with UIDs for all their Mail accounts; the engine resolves
  the right UID based on the From address at encode time.
- The `Real Name` part of a UID is optional in OpenPGP but conventional.
  Don't require it; allow `"<email>"`-only UIDs.
- Photo UIDs (RFC 4880 §5.2.3.21) are explicitly out of scope for 1.0.
