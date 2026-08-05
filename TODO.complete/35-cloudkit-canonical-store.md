# 35 — CloudKit canonical store

**Priority**: P1
**Status**: not started
**Effort**: L
**Dependencies**: 33 (Phase 1.5 refactor)

## Problem

Mac+iOS users want automatic sync without configuring anything
beyond iCloud sign-in. The current architecture supports this in
theory but the CloudKit backend doesn't exist yet.

## Goals

- `RNPCloudKitBackend` — `KeyringBackend` conformance backed by iCloud private DB
- Atomic per-key records (one `RNPKey` per fingerprint)
- `CKQuerySubscription` for cross-device push notifications
- Idempotent upsert (same fingerprint, same bytes → no-op)
- Conflict: latest `modifiedAt` wins

## Design

### Record schema

Already specified in `docs/sync-architecture.md`:

```
RNPKey:
  fingerprint:        String  (record name)
  primaryUserID:      String
  allUserIDs:         [String]
  keyBytes:           Bytes
  hasSecret:          Bool
  keyCreationDate:    Date
  keyExpirationDate:  Date?
  modifiedAt:         Date
  modifiedBy:         String
```

### Sync flow

Local upsert → CKModifyRecordsOperation → CloudKit propagates →
remote device's `CKQuerySubscription` fires → fetch + merge.

### Subscription

One subscription per device, registered on first launch. Token
persisted to UserDefaults. Remote notifications wake the app to
fetch.

### Privacy

- Private DB only — never public
- User's iCloud account is the only identity
- No RNP-operated servers
- See `docs/sync-architecture.md` for the iCloud Keychain split for passphrases

## Implementation plan

1. CloudKit schema (set up via CloudKit Dashboard first time)
2. `RNPCloudKitBackend` skeleton
3. Push path (`upsert`)
4. Pull path (`load`, `fetchAllKeys`)
5. Subscription registration
6. Background fetch handling
7. Conflict resolution
8. Error handling (quota, network, auth)
9. Tests with two Macs (no simulator for CloudKit)

## Acceptance criteria

- [ ] Backend writes a key → second Mac sees it within 30s
- [ ] Backend deletes a key → second Mac removes it (after the canonical delete flow ran locally first)
- [ ] Conflict (same fingerprint, different bytes on two Macs) → latest modifiedAt wins, no data loss
- [ ] iCloud disabled → backend returns `.unavailable`
- [ ] Spec in `docs/specs/cloudkit-backend.md`

## References

- docs/sync-architecture.md
- TODO.complete/32-sync-settings-ui.md
