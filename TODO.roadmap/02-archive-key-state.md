# 02 — Archive-key state (decrypt-only, never used for new mail)

Status: pending · Tier: A · Depends on: nothing

## Goal

A user who revokes or retires a key must not have to choose between (a)
keeping clutter in their key list that could be selected by mistake for new
encryption, and (b) deleting the secret and orphaning every encrypted
message ever sent to that key.

Add an **archived** state: decrypt-only, hidden from the default key list,
never selected as a signer or encryption recipient.

## Why this is Tier A

The current binary (active vs deleted) is a trap:

- User revokes their old key after rotation.
- App helpfully offers to delete the revoked key (to "clean up").
- User accepts.
- Every encrypted message in their archive that was sent to the old key
  becomes undecryptable. There is no warning that this is what "delete"
  means. There is no undo.

GnuPG and Enigmail both solve this with a soft-delete / trust-disable that
retains secret material. We must too.

## Design

### State

Extend `KeyInfo` with:

```swift
public enum KeyUsageState: String, Codable {
    case active    // selectable for sign / encrypt / decrypt / verify
    case archived  // decrypt + verify only; never selected for new operations
}
public struct KeyInfo {
    // existing fields...
    public let usageState: KeyUsageState
}
```

Storage: a sidecar `key-states.json` in the app-group container mapping
`fingerprint → KeyUsageState`. Keep the keyring itself untouched (librnp
still sees all keys); the state is enforced at the MailSecurityEngine /
KeyManager selection layer.

### Behavior

- **Decryption**: archived keys participate normally. librnp iterates the
  whole secret keyring; we don't need to do anything except *not* exclude
  them.
- **Signing**: the compose/sign path skips archived keys when resolving the
  sender's signing key.
- **Encryption to self** (BCC self, sent-mail storage): skips archived keys.
- **Encryption to recipients**: if a recipient has only an archived key,
  surface as "Recipient's only key is archived — they may not be reachable
  at this address anymore" (rare; usually means stale address).
- **Default key list (Keys tab)**: archived keys live in a collapsible
  "Archived" section at the bottom, with copy "These keys can decrypt old
  mail but are not used for new mail."
- **Trust**: archived keys retain their trust state. A verified-then-
  archived key is still verified for verification of old signatures.

### Transitions

| From | To | Trigger |
|---|---|---|
| active | archived | User clicks "Archive" on a key detail view; OR user completes the revoke flow (default post-revoke action). |
| archived | active | User clicks "Restore to active" (with a warning that this key will become selectable for new mail again). |
| archived | (deleted) | User clicks "Delete forever" — extra confirmation: "All mail encrypted to this key will become permanently undecryptable. Type the fingerprint to confirm." |

### Auto-archive triggers

- After revoking a key with reason `superseded` (see `05-key-transition`),
  auto-archive with banner "Archived — kept for decrypting old mail."
- After rotating a subkey, the retired subkey is implicitly archived
  (handled in `KeyLifecycle`).
- If a key has been expired for more than 90 days and the user has another
  active key for the same primary user ID, offer to archive.

### Migration on first launch

Existing installs (where users have already deleted keys the bad way):
nothing to migrate — the damage is done. For still-present revoked keys
(detectable via `isRevoked`), prompt: "Your revoked key `<fingerprint>` is
still in your keyring. Archive it so it can decrypt old mail but won't be
used for new mail?"

## Tests

- Generate → revoke → archive → old encrypted test message still decrypts.
- Archive → attempt to sign with archived key: refused with a clear error.
- Archive → attempt to encrypt-to-self: skipped; falls back to next active
  key or fails with a clear "no active signing/encryption key" error.
- Archive → "Restore to active" → key participates normally again.
- Archive → "Delete forever" → key removed from keyring; subsequent
  decryption of old ciphertext fails with the missing-key error from
  `03-decryption-errors.md`.
- Auto-archive after revoke: revoking with reason `superseded` leaves the
  key archived, not deleted.
- First-launch migration: a revoked key present at startup is offered for
  archival.

## Acceptance criteria

- A user who completes the key-transition flow (05) ends up with the old
  key archived and all their old mail still decryptable, with no extra
  clicks.
- The default key list shows zero clutter from archived keys until the user
  expands the Archived section.
- It is impossible to delete the secret material of any key without typing
  its fingerprint.

## Notes / risks

- `key-states.json` should be signed together with `trust.json` (same
  Ed25519 app key) so that tampering is detected the same way. Consider
  merging both files into one signed `state.json` if the schemas align.
- Do **not** store this state in the keyring via librnp's key flags — that
  would mutate the key and conflict with keyserver refresh. It is a local
  engine layer.
- If a key is archived and later the user imports a refreshed copy (e.g.,
  the contact extended the key), the archived state should be respected
  (the user explicitly retired it locally). Surface "Refreshed, but still
  archived per your previous choice" so the user can reverse.
