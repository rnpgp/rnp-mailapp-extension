# ADR-0001: App Sandbox is required for both targets

Date: 2026-07-15
Status: Accepted

## Context

RNP ships as a macOS app (`com.rnpgp.RNPForMail`) plus a Mail extension
(`com.rnpgp.RNPForMail.MailExtension`). The Direct distribution
channel (Developer ID) does not strictly require sandboxing; only the
App Store channel does.

For the first iteration of the project we considered shipping the
Direct build without sandbox to make GnuPG CLI interop easier. This
lasted about two weeks before the Mail extension failed to load on
real user machines with `pkd: rejecting; plug-ins must be sandboxed`.

## Decision

Both targets — host app AND Mail extension — enable
`com.apple.security.app-sandbox` in every build configuration
(Direct + AppStore).

## Consequences

Positive:
- Mail extension loads reliably across macOS 14.x
- Same entitlement set for both distribution channels (one less fork)
- App Store submission path stays open
- User trust: sandboxing is a meaningful safety promise

Negative:
- GnuPG CLI interop (`gpg --list-secret-keys`) breaks in the sandboxed
  build because arbitrary process execution is blocked. Mitigated by
  gating GnuPG import behind `#if !APPSTORE` and documenting it.
- Network access requires an explicit entitlement (already in place).

Neutral:
- Hardened Runtime is required alongside sandbox; we use version 14.0
  re-sign to keep macOS 14.0–14.3 happy (see commit debef7b).

## References

- PR #166 (sandbox entitlement added to MailPlugin/Direct.entitlements)
- macOS Security: App Sandbox documentation
