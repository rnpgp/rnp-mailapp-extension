# 34 — Per-key .asc directory backend

**Priority**: P1
**Status**: in progress
**Effort**: S
**Dependencies**: 33 (Phase 1.5 refactor)

## Problem

For cross-platform sync (Mac+Linux via Syncthing/git/Dropbox), the
binary `pubring.gpg` format is wrong — file-level conflict resolution
loses keys. Users want one file per key.

## Goals

- `RNPPerKeyDirectoryBackend` — `KeyringBackend` conformance
- One `<fingerprint>.asc` file per key
- Atomic per-key sync — adding a key on Mac propagates to Linux as one new file
- File deletes on Linux propagate to Mac (file watcher)
- Git-friendly: file add/remove is the natural diff

## Design

### File layout

```
~/Sync/rnp-keys/
├── 1a2b3c4d5e6f....asc      # armored public key
├── 5e6f70819203....asc      # armored public key
├── ...                       # one per fingerprint
└── .rnp/                     # metadata (optional)
    └── manifest.json         # last-modified timestamps, source tracking
```

### Conflict resolution

If two devices add different keys → both files appear → no conflict.
If two devices modify the SAME key (rare — same fingerprint, different bytes) → latest modifiedAt wins, kept as `<fpr>.asc`; older renamed to `<fpr>.asc.conflict-<date>` for user review.

### Why this is better than binary keyring

| | Binary `pubring.gpg` | Per-key `.asc` |
|--|--|--|
| Conflict on add | Loses one key | Both files coexist |
| Conflict on update | Binary merge impossible | File rename, user reviews |
| Git diff | Opaque | Readable |
| Grep | Useless | Works |
| Sync via Syncthing | Risky | Safe |

## Implementation plan

1. `RNPPerKeyDirectoryBackend` class
2. Implements `KeyringBackend` protocol
3. Surfaces in Sync UI (TODO 32) as a canonical store option
4. Default recommendation for users who want cross-platform sync

## Acceptance criteria

- [ ] Backend writes one .asc per fingerprint
- [ ] Reading scans the directory, parses each .asc
- [ ] Conflicts create `.conflict-<date>` files (don't lose data)
- [ ] Spec in `docs/specs/per-key-asc-backend.md`

## References

- TODO.complete/32-sync-settings-ui.md
- docs/sync-architecture.md (per-key .asc section)
