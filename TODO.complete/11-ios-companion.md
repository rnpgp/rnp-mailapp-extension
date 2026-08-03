# 11 — iOS companion app

**Priority**: P3
**Status**: not started (scope-decision pending)
**Effort**: XL (~1 month+)
**Dependencies**: 12 (specs/tests), scope decision from ronaldtse

## Problem

iOS users have no good OpenPGP tool. Signal/WhatsApp cover messaging
but not email or file encryption. Thunderbird mobile exists but is
early. An iOS RNP companion would: (a) cover the file-encryption use
case for iOS, (b) sync keys across user's Mac and iPhone, (c) cross-
promote the Mac app.

This is the largest single lift in the roadmap. Don't start until scope
is decided and at least TODOs 01, 05 are shipped.

## Goals / non-goals

**Goals (proposed)**
- File encrypt / decrypt on iOS (Files app integration)
- Key management with iCloud Keychain sync
- Share extension: encrypt/sign from any app's share sheet
- QR-code key exchange between devices

**Non-goals**
- A full Mail client (Apple's Mail.app on iOS doesn't support Mail
  extensions the way macOS does — iOS MailKit is much more restricted)
- iOS App Store submission for v1 (TestFlight first)

## Open scope questions (decide before starting)

1. **iOS MailKit restrictions.** iOS 14+ has Mail extensions but with
   tighter constraints than macOS. Confirm what's actually possible
   for compose-time signing/encryption. May make iOS Mail integration
   not worth it for v1.
2. **iCloud Keychain vs custom sync.** iCloud Keychain syncs across
   devices automatically; custom sync needs a server. Strong preference
   for iCloud Keychain.
3. **iOS-only or iPad too?** iPad with keyboard is a real productivity
   device — make sure UI works there, not just iPhone.
4. **Cross-platform SwiftPM targets.** `MailSecurityEngine` is already
   macOS-only. Need to extract OpenPGP core into a cross-platform
   module. Real refactor.

## Design (sketch only — not authoritative until scope decided)

```
iOSApp/
├── RNP.xcodeproj             (new project, separate from Mac app)
├── Sources/
│   ├── RNPiOS/               (app target)
│   ├── RNPiOSShare/          (share extension)
│   └── Shared/               (cross-platform code from MailSecurityEngine)
└── Tests/
```

Keyring shared via iCloud Keychain. App Group identical bundle ID
prefix.

## Implementation plan (high-level)

1. Scope decision with ronaldtse
2. Extract cross-platform core from MailSecurityEngine
3. Stand up iOS app target
4. Implement file encrypt/decrypt (reuse FileSecurityEngine from TODO 05)
5. iCloud Keychain sync
6. Share extension
7. TestFlight beta
8. App Store submission

## Acceptance criteria

 TBD — depends on scope decision

## Open questions (many)

- iCloud Keychain limitations on third-party key formats?
- iOS MailKit — is iOS 18 needed for the integration we want?
- Code-sharing approach: SwiftPM cross-platform module vs duplicated
  Swift files in two projects?

## Out of scope (for now)

- Android
- Web app

## References

- Apple MailKit on iOS: https://developer.apple.com/documentation/mailkit
- iCloud Keychain: https://developer.apple.com/documentation/security/keychain_services
