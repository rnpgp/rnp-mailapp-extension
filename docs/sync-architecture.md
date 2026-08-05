# Cross-device sync architecture

This document specifies how RNP keeps keys and passphrases in sync
across a user's Mac, iPhone, and Linux boxes, and how RNP interacts
with existing keyrings (GnuPG, WKD, keys.openpgp.org).

## TL;DR

- RNP is a **first-class OpenPGP implementation**, not a wrapper
  around GnuPG. It owns its own keyring.
- RNP's canonical keyring lives at `~/.rnp/` (CLI) or App Group
  container (GUI app) or CloudKit (Apple-device sync).
- Every other key source (`~/.gnupg/`, WKD, keys.openpgp.org,
  dropped `.asc` files) is an **import source — read-only**. RNP
  never writes to them. RNP never deletes from them.
- Per-key passphrases live in macOS/iOS Keychain (default) or iCloud
  Keychain (sync across Apple devices).
- On Linux, `rnp` CLI can also look up passphrases from `gpg-agent`
  for keys the user imported from GnuPG.

## Mental model

```
┌──────────────────────────────────────────────────────────────┐
│                       RNP app (UI)                            │
│                                                              │
│   KeysListView ────► CompositeKeyringBackend ──────► [RNP]   │
│                          (unified view)            canonical │
│                                                    store     │
└──────────────────────────────────────────────────────────────┘
                                                              │
              ┌───────────────────────────────────────────────┘
              ▼
┌──────────────────────────────────────────────────────────────┐
│  RNP canonical keyring (RNP owns this; writes go here)        │
│                                                              │
│  ┌────────────────────────┐  ┌────────────────────────────┐ │
│  │ ~/.rnp/                │  │ CloudKit mirror            │ │
│  │  (CLI default)         │  │  (Mac+iOS auto-sync)       │ │
│  │  pubring.gpg           │  │                            │ │
│  │  secring.gpg           │  │                            │ │
│  └────────────────────────┘  └────────────────────────────┘ │
│  ┌────────────────────────┐                                 │
│  │ macOS App Group        │                                 │
│  │  (GUI app default)     │                                 │ │
│  └────────────────────────┘                                 │
└──────────────────────────────────────────────────────────────┘
                                                              ▲
              ┌───────────────────────────────────────────────┘
              │ IMPORT (one-way copy; source never modified)
              │
┌──────────────────────────────────────────────────────────────┐
│  Import sources (read-only — RNP never writes back)           │
│                                                              │
│  ┌────────────────────┐ ┌──────────────────┐ ┌────────────┐ │
│  │ GnuPG keyring      │ │ WKD lookup       │ │ Paste/drop │ │
│  │ ~/.gnupg/          │ │ (per-recipient)  │ │ (.asc)     │ │
│  └────────────────────┘ └──────────────────┘ └────────────┘ │
│  ┌────────────────────┐ ┌──────────────────┐                 │
│  │ keys.openpgp.org   │ │ Existing .rnp    │                 │
│  │ (search by email)  │ │ from another Mac │                 │
│  └────────────────────┘ └──────────────────┘                 │
└──────────────────────────────────────────────────────────────┘
```

## Protocols

### `KeyringBackend` — RNP's canonical store (writes go here)

```swift
public protocol KeyringBackend: AnyObject {
    var identifier: String { get }              // "rnp-local", "rnp-cloudkit"
    var displayName: String { get }
    var availability: BackendAvailability { get }

    func load() throws -> [KeyringKeyRecord]
    func upsert(_ record: KeyringKeyRecord) throws
    /// Remove from RNP's store. NEVER touches import sources.
    func delete(fingerprint: String) throws

    func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable
}
```

### `KeyImportSource` — read-only sources RNP pulls from

Distinct protocol, distinct semantics. **RNP NEVER writes to these.**
The protocol has no write/delete methods — compile-time guarantee.

```swift
public protocol KeyImportSource: AnyObject {
    var identifier: String { get }              // "gnupg", "wkd", "paste"
    var displayName: String { get }
    var availability: BackendAvailability { get }

    /// Returns keys currently visible at this source. Does NOT modify
    /// the source. Does NOT auto-import — caller (UI) decides which
    /// to import via `KeyringBackend.upsert(_:)`.
    func listAvailable() throws -> [KeyringKeyRecord]
}
```

### `PassphraseStore`

```swift
public protocol PassphraseStore: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    var availability: BackendAvailability { get }

    func passphrase(for fingerprint: String) -> String?
    func setPassphrase(_ passphrase: String, for fingerprint: String) throws
    func deletePassphrase(for fingerprint: String) throws
}
```

## Why this design

### Why a separate read-only protocol

The user's absolute rule is **NEVER wipe user keys**. By giving
import sources a different protocol from canonical stores — with no
write/delete methods — the compiler enforces the rule. RNP literally
cannot call `gpg --delete-*` or write to `~/.gnupg/` because no code
path exists for that.

### Why RNP owns its keyring (vs. using GnuPG's)

RNP is a first-class OpenPGP implementation, not a wrapper around
GnuPG. Treating GnuPG's keyring as the canonical store would make RNP
subordinate to GnuPG. Instead:

- RNP's keyring is canonical
- GnuPG's keyring is an import source (read-only)
- Cross-device sync happens within RNP's ecosystem (CloudKit for
  Apple devices, user-chosen file sync for Mac↔Linux)

### Why iCloud split: CloudKit for keys, iCloud Keychain for passphrases

- Key bytes are *already* encrypted by OpenPGP itself (S2K + AES-256).
  CloudKit is fine.
- Passphrases are *raw secrets*. iCloud Keychain is end-to-end
  encrypted by Apple — only the user's devices can read them. Apple
  cannot.

### Why not iCloud Drive for the keyring

iCloud Drive is file-based. A keyring is conceptually a *set* of keys,
not a file. Two Macs importing different keys simultaneously would
either lose a key (last-writer-wins) or create a conflicting copy the
user has to resolve manually. PGP keyrings are binary — no text-merge.

CloudKit handles this correctly: each key is its own record, identified
by fingerprint. Both adds propagate. Both devices end up with both keys.

For users who want file-based sync (Mac↔Linux via Syncthing/git), RNP
offers a per-key `.asc` directory backend — one file per fingerprint,
no binary merge conflicts.

## Cross-device sync within RNP's ecosystem

### Mac ↔ iPhone (iCloud)
- RNP canonical store mirrors to CloudKit
- RNP passphrases sync via iCloud Keychain
- Automatic; no user setup beyond iCloud sign-in
- iOS sees the same keys as Mac

### Mac ↔ Linux (user-chosen file sync)
- User points both Mac CLI and Linux CLI at the same synced `~/.rnp/`
  directory (via Syncthing, Nextcloud, Dropbox, git)
- RNP detects file changes via `observeChanges` and reloads
- For git-based workflows, RNP's per-key `.asc` directory format
  avoids binary merge conflicts
- Passphrases: user manages separately (gpg-agent on Linux for
  GnuPG-imported keys, Keychain on Mac, or prompt-every-time)

### Mac ↔ Mac
- Either iCloud or file-based sync
- iCloud is the easy path
- File-based sync is the explicit-control path

## Critical: delete safety

RNP NEVER deletes user keys without multi-step confirmation AND a
recovery archive. The flow is:

### Three-step confirmation

| Step | What |
|------|------|
| 1 — Warning | "You're about to remove this key from RNP's keyring. The original key in any external source is NOT touched — only RNP's copy." [Continue] / [Cancel] |
| 2 — Type to confirm | Single key: type the fingerprint (or last 16 chars). Multiple keys: type `DELETE`. Prevents misclicks. [Continue] / [Cancel] |
| 3 — Final warning | Choose backup path + passphrase. "Last chance. A backup will be saved to <path>. Without the passphrase, the backup cannot be recovered." [Delete Forever] / [Cancel] |

### Encrypted backup before every delete

Before any key is removed from RNP's canonical store, RNP produces
an OpenPGP-encrypted archive of the key bytes:

- **Format**: standard PGP message (`rnp-keys-deleted-YYYY-MM-DD-HHMMSS.pgp`)
- **Encryption**: symmetric, with a passphrase the user types at delete time
- **Why symmetric, not encrypted-to-self**: the user is deleting the key. Encrypting the backup to the key being deleted would be circular — if they could decrypt the backup, they wouldn't need it.
- **Recovery**: any OpenPGP tool can decrypt. `rnp decrypt backup.pgp` or `gpg -d backup.pgp` recovers the armored key bytes, which can then be re-imported.
- **Default location**: `~/Documents/RNP Backups/`. User can override via NSSavePanel.

### What this protects against

1. **Misclicks** — three explicit confirmations before any deletion.
2. **Wrong key** — step 2 requires typing the fingerprint, so the user knows exactly what they're deleting.
3. **Lost keys** — encrypted backup is always saved before delete.
4. **Forgotten passphrases** — backup is recoverable from any OpenPGP tool, not just RNP.
5. **Source keyrings** — external sources (`~/.gnupg/`, WKD, etc.) are NEVER touched by delete. Delete only ever removes from RNP's canonical store.

### Order of operations

1. User clicks "Delete" in UI
2. `confirmDelete(key)` opens `DeleteKeySheet` (was `.alert`, now `.sheet`)
3. Sheet drives `DeletionConfirmationState` through three steps
4. On step 3 "Delete Forever":
   - `KeyBackupArchive.write(...)` produces the encrypted `.pgp`
   - If write succeeds: delete from RNP's canonical store
   - If write fails: surface error, **do NOT delete**, key stays
5. Show success with backup path + "Reveal in Finder"

### No mass delete

Bulk delete of multiple keys at once is intentionally NOT supported in
the UI. The three-step flow + per-key fingerprint-typing is too
cumbersome for bulk; for bulk, the user can use `rnp` CLI's `delete`
command (which also saves a backup) or use Tools hub's "Backup
keyring" then delete via CLI.

## Critical: never modify import sources

This is enforced by:

1. **Protocol separation** — `KeyImportSource` has no write method.
   Compile-time guarantee.
2. **Import is an explicit copy** — UI surfaces a list; user clicks
   each key to import; RNP calls `KeyringBackend.upsert(_:)` (its own
   store), never touches the source.
3. **Re-import is idempotent** — if the key fingerprint already
   exists in RNP's store, no-op (or "update with newer bytes" if the
   source has a newer version, user-confirmed).
4. **Delete only ever touches RNP's store** — when the user "deletes"
   a key in the UI, RNP removes it from its own backend(s) only. The
   original at the source (e.g. `~/.gnupg/`) is untouched. UI makes
   this clear.

## iOS-specific constraints

iOS MailKit (as of iOS 17) doesn't support `MEComposeSessionHandler`.
iOS app can:
- Display security indicators on incoming mail (read-only)
- Show decrypted-attachments panel
- File encryption via Files app integration
- Share extension (encrypt from any app)

iOS app cannot:
- Sign/encrypt outgoing mail via Apple Mail
- Talk to gpg-agent (no gpg on iOS)
- Read GnuPG keyring (no gpg on iOS, no `~/.gnupg/` access)

For iOS, the available backends are:
- `RNPLocalKeyringBackend` (App Group container)
- `RNPCloudKitBackend` (iCloud sync with Mac)
- `RNPPerKeyDirectoryBackend` (iCloud Drive container — works for
  git-over-iCloud-Drive setups)

For iOS passphrases:
- `KeychainPassphraseStore` (iOS Keychain)
- `SynchronizablePassphraseStore` (iCloud Keychain — sync with Mac)
- `NullPassphraseStore` (prompt every time)

## Implementation phases

### Phase 1: Protocols + refactor (no behavior change)
- Define `KeyringBackend`, `KeyImportSource`, `PassphraseStore` protocols
- Wrap existing `SharedKeyring` → `RNPLocalKeyringBackend` conformance
- Wrap existing `KeyringScanner` → `GnuPGImportSource` conformance (read-only)
- Wrap existing `KeychainPassphraseStore` → `PassphraseStore` conformance
- No UI change. Goal: clean seams for future backends.

### Phase 2: Per-key `.asc` directory backend
- `RNPPerKeyDirectoryBackend` — reads/writes a directory of `<fpr>.asc` files
- One file per fingerprint — git/Syncthing-friendly
- Surfaced as an option in Sync UI ("Where RNP stores your keys")
- This is the recommended backend for cross-platform Mac+Linux sync

### Phase 3: CloudKit canonical store
- `RNPCloudKitBackend` — RNP's keys mirrored to iCloud private DB
- Atomic per-key records (vs. iCloud Drive file-level conflicts)
- Subscribes to remote changes for auto-sync with iOS

### Phase 4: SynchronizablePassphraseStore (iCloud Keychain)
- Wrap with the `PassphraseStore` protocol
- Wire into Sync UI as a Passphrase Store option

### Phase 5: GnuPG agent passphrase store (lookup-only)
- `GnuPGAgentPassphraseStore` — reads passphrases from gpg-agent
- Used ONLY for keys imported from GnuPG on Linux
- After first successful lookup, RNP caches in its own store; doesn't
  keep hitting gpg-agent

### Phase 6: Sync UI
- New sheet in Tools hub
- User picks canonical store, passphrase store, and which import
  sources to expose
- Surfaces availability issues clearly ("iCloud not signed in",
  "gpg-agent not running")

### Phase 7: iOS app target
- New Xcode project `RNPiOS`
- Reuses cross-platform SPM target
- Files app integration + Share extension
- iCloud-only sync (CloudKit + iCloud Keychain)
- No GnuPG agent, no GnuPG keyring import (iOS limitations)

## Privacy

- **No RNP-operated servers.** Sync is 100% Apple infrastructure.
- **No telemetry.** CloudKit diagnostics don't reach us.
- **Apple cannot read passphrases** (iCloud Keychain E2E).
- **Apple can theoretically read key bytes** (CloudKit), but those
  bytes are useless without the passphrases (which Apple can't read).
- **User can disable sync** entirely; the app continues to work
  locally with no behavior change beyond cross-device sync.
- **GnuPG keyring is never modified by RNP.** Read-only.

## References

- Apple CloudKit: https://developer.apple.com/documentation/cloudkit
- iCloud Keychain: https://developer.apple.com/documentation/security/keychain_services
- iOS MailKit limits: https://developer.apple.com/documentation/mailkit
- TODO.complete/11-ios-companion.md
- Implementation plan: ~/.claude/plans/partitioned-snuggling-wren.md
