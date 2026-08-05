# 37 — Sync UI sheet (concrete impl of TODO 32)

**Priority**: P0
**Status**: in progress
**Effort**: M
**Dependencies**: 33 (Phase 1.5 refactor)

## Problem

TODO 32 specifies the design; this TODO is the concrete
implementation work. Kept separate so the spec and impl don't
entangle.

## Implementation

See TODO.complete/32-sync-settings-ui.md for the design.

Concrete files:
- `MailApp/MailExtensionsContainer/View/SyncSettings/SyncSettingsSheet.swift`
- `MailApp/MailExtensionsContainer/Model/SyncSettings/SyncConfiguration.swift`
- `MailApp/MailExtensionsContainer/Model/SyncSettings/CanonicalStoreMigrator.swift`

## Acceptance criteria

- [ ] Sheet added to Tools hub
- [ ] Four sections present and bound to model
- [ ] Migration logic tested manually (Local → per-key dir, back)
