# 38 — iOS companion app

**Priority**: P3
**Status**: not started (scope-decision pending)
**Effort**: XL (~1 month+)
**Dependencies**: 33 (Phase 1.5 refactor), 35 (CloudKit)

## Problem

iOS users have no good OpenPGP tool. RNP on iOS would cover file
encryption, key management with iCloud sync, share extension.

## Goals (proposed)

- File encrypt / decrypt on iOS (Files app integration)
- Key management with iCloud Keychain sync
- Share extension: encrypt/sign from any app's share sheet
- QR-code key exchange between devices
- Same engine (librnp) as macOS

## Non-goals

- iOS MailKit compose (not supported by Apple as of iOS 17)
- iOS App Store submission for v1 (TestFlight first)

## Open scope questions (decide before starting)

1. **iOS MailKit restrictions**: confirm what's possible for
   compose-time signing/encryption. iOS MailKit is much more
   restricted than macOS. iOS app may be read-only for Mail.
2. **iCloud Keychain vs custom sync**: iCloud Keychain syncs across
   devices automatically. Use it.
3. **iOS-only or iPad too**: iPad with keyboard is a real productivity
   device — UI must work there.
4. **Cross-platform SwiftPM targets**: extract OpenPGP core into a
   cross-platform module. Real refactor.

## Design (sketch only — not authoritative until scope decided)

```
iOSApp/
├── RNPiOS.xcodeproj             (new project)
├── Sources/
│   ├── RNPiOS/                  (app target)
│   ├── RNPiOSShare/             (share extension)
│   └── Shared/                  (cross-platform code from MailSecurityEngine)
└── Tests/
```

Keyring shared via iCloud Keychain. App Group identical bundle ID
prefix.

## Implementation plan (high-level)

1. Scope decision with ronaldtse
2. Extract cross-platform core from MailSecurityEngine
3. Stand up iOS app target
4. Implement file encrypt/decrypt (reuse FileSecurityEngine)
5. iCloud Keychain sync
6. Share extension
7. TestFlight beta
8. App Store submission

## Acceptance criteria

 TBD — depends on scope decision

## References

- TODO.complete/11-ios-companion.md (original — superseded by this)
- docs/sync-architecture.md
