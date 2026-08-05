# 32 — Settings UI: Sync sheet

**Priority**: P0
**Status**: in progress
**Effort**: M
**Dependencies**: 33 (Phase 1.5 refactor)

## Problem

Sync configuration (canonical store, import sources, passphrase
store) is currently invisible to the user. The architecture exists
(protocols from PR #190) but there's no UI to change it.

## Goals

A "Sync" sheet accessible from the Tools hub that lets users:
- See the current canonical store
- Change canonical store (one-way migration, never delete from old)
- Toggle import sources on/off
- Configure write mirrors (copy keys to additional backup locations)
- Configure passphrase store
- Configure delete safety (already shipped — link to it)

## Design

### Sheet structure

Three sections, scrollable:

1. **Canonical store** (radio group)
   - Local RNP keyring
   - Per-key .asc directory (with path picker)
   - iCloud (CloudKit)
   - Note: changing this triggers a one-way copy migration

2. **Import sources** (checkbox list, all read-only)
   - GnuPG keyring (~/.gnupg)
   - WKD (Web Key Directory)
   - keys.openpgp.org
   - Paste from clipboard
   - Drag-drop files

3. **Passphrase store** (radio group)
   - macOS Keychain
   - iCloud Keychain
   - gpg-agent (lookup-only)
   - Prompt every time

4. **Write mirrors** (optional list)
   - "Also copy my keys to: [path]"
   - Used for offline backups, additional sync locations

### Migration when canonical store changes

If user changes canonical store from A to B:
1. Read all keys from A
2. Write them to B
3. Verify B has the same fingerprints
4. Switch active store to B
5. DO NOT delete from A (user can manually clean up)

This is a copy, not a move. Same never-delete principle.

### Availability indicators

Each option shows availability:
- "Available" (green checkmark)
- "Unavailable: <reason>" (red x)
  - iCloud: "Sign into iCloud to enable"
  - gpg-agent: "Start gpg-agent to enable"
  - Per-key dir: "Pick a folder"

## Implementation plan

1. `SyncSettingsSheet` SwiftUI view
2. Bindings to `SyncConfiguration` model (new)
3. Add to Tools hub as a new card
4. Localization keys
5. Migration logic in `CanonicalStoreMigrator` (new)

## Acceptance criteria

- [ ] Sheet accessible from Tools hub
- [ ] All four sections present
- [ ] Availability indicators work for each option
- [ ] Changing canonical store triggers one-way copy migration
- [ ] Migration preserves all keys (verified by fingerprint set comparison)
- [ ] Migration NEVER deletes from old store
- [ ] Spec in `docs/specs/sync-settings.md`

## References

- docs/sync-architecture.md
- TODO.complete/31-getting-started-storage-choice.md
