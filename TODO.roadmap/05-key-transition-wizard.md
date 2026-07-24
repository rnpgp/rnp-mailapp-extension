# 05 — Key transition wizard: migrate to a new key with continuity

Status: pending · Tier: A · Depends on: 04 (expiry recovery), 02 (archive state)

## Goal

When a user needs to move from one primary key to another (after
compromise, expiry without recovery, or simply rotating to a stronger
algorithm), give them a guided multi-step flow that preserves trust: the new
key is signed by the old key, the old key is revoked with reason
`superseded` pointing at the new key, correspondents are notified, and the
old key is archived so old mail still decrypts.

## Why this is Tier A

Without this wizard, the path to "I need a new key" is:

1. Generate new key.
2. Email everyone and hope they add it.
3. Old key keeps getting used by people who haven't refreshed.
4. Lose track of which mail is signed with which key.

Or worse: delete the old key and orphan all old mail. Power users do this
manually with GnuPG and still get it wrong. We should make it a one-button
flow.

This wizard is the recovery path for several scenarios in
`04-key-expiry-recovery.md` (notably #3 and #8).

## Design

### Entry points

- **From Key Health** (04): a "Migrate to new key…" button on any active
  own-key.
- **From the expiry recovery flow** (04 scenarios #3 and #8): "I lost the
  secret" / "I want to start fresh" paths.
- **From the key detail view**: "Transition to a new key…" action.

### Wizard steps

A multi-page SwiftUI sheet, one step per page, with a progress indicator
(1/5, 2/5, …) and the ability to go back.

**Step 1: Choose or generate the new key.**
- ( ) Generate a new key now (default algorithm: same family as old; Ed25519
  if old was RSA → offer Ed25519 with explanation).
- ( ) Use an existing key already in my keyring.
- ( ) Import a key from file.

**Step 2: Choose user IDs.**
- Copy user IDs from the old key to the new key (default ON).
- Optionally add new user IDs (rare in transition; usually they're the
  same).

**Step 3: Sign the new key with the old key.**
- "This is what tells your contacts that the new key is really yours."
- The engine calls `rnp_key_signature_sign` to add a certification
  signature from old-primary → new-primary-UID(s), type 0x10 (Generic
  Certification) or 0x11 (Persona Certification). Notation: NOTATION
  "rfc4880-transition" or just rely on the certification semantics.
- Requires the old key's secret unlocked; if Touch ID is enabled, prompt.
- If the old key's secret is not available (lost), skip this step with a
  warning that trust must be re-established out-of-band.

**Step 4: Revoke the old key with reason `supersended`.**
- Calls `rnp_key_revoke` with reason code `superseded` and the new key's
  fingerprint in the reason text.
- Confirmation: "This publishes a revocation. After this, your old key
  cannot be used to sign new mail. Old encrypted mail still decrypts."

**Step 5: Publish and notify.**
- Publish the new key (and the revoked old key) to keyservers.
- Show the notify-contacts template from `04-key-expiry-recovery.md`,
  pre-populated with the new fingerprint and To-list from `ExtensionState/`.
- [ ] Publish new key. [ ] Publish revoked old key. [ ] Notify contacts.

**Finish.**
- Old key auto-archived (02).
- New key set as primary for any account identities the old key served.
- Key Health shows: old key archived, new key active.

### Trust continuity for recipients

Recipients who refresh their keyring from the keyserver see:

- The new key, with a certification signature from a key they already trust
  (your old key). Their client (if it respects certifications — many do
  informally) treats the new key as related to the old.
- The old key, revoked with reason "superseded."

Most modern clients will move the recipient's encryption target to the new
key automatically once they refresh. Document this in `docs/key-lifecycle.md`.

### Failure modes

- **Old key's secret not available** (e.g., recovery materials lost): step 3
  is skipped with a clear warning. The user can still complete the wizard;
  their contacts will need out-of-band verification of the new fingerprint.
- **No network during publish**: queue the publish action; complete the
  wizard with a "publish pending" state.
- **User cancels mid-wizard**: rollback to the pre-wizard state. Old key is
  untouched; any new key generated is deleted.

## Tests

- End-to-end: generate old key → run wizard → assert old key is revoked
  with reason `superseded` and archived; assert new key has a certification
  signature from the old key; assert both keys are in the publish queue.
- Failure mode: old key's secret locked and password wrong → wizard
  completes step 3 with the "trust must be re-established" warning; new
  key is generated without the certification.
- Cancellation at each step rolls back cleanly.
- Recipient simulation: a second keyring that trusts the old key imports
  the new key after refresh and sees the certification signature.

## Acceptance criteria

- A user with an existing key can complete the wizard in under three
  minutes (including reading each step's explanation) and end up with a
  published new key, a revoked-and-archived old key, and queued
  notifications.
- All certifications and revocations are GnuPG-compatible (cross-check with
  `gpg --check-sigs`).
- The wizard does not let the user reach "Finish" with both keys revoked
  and no path to decrypt old mail — the old key is always archived, never
  deleted, by this flow.

## Notes / risks

- The certification signature in step 3 should use SHA-256 or stronger
  (`rnp_key_signature_set_hash`); never SHA-1.
- The "superseded" reason code is from RFC 4880 §5.2.3.23 (`retired` is a
  different code; do not confuse them).
- This wizard deliberately does NOT support multi-step key splits (e.g.,
  moving primary offline while keeping a signing subkey online) — that's
  `15-deferred-post-1.0.md`.
- If the user has multiple own keys (different identities) and only wants
  to transition one, the wizard must scope to the chosen key, not all.
