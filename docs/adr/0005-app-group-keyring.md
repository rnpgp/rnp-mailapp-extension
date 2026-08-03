# ADR-0005: App Group container is the shared keyring location

Date: 2026-07-15
Status: Accepted

## Context

The host app and the Mail extension run in separate processes with
separate containers. They need to share:
- Public + secret OpenPGP keys
- Per-key passphrase (Keychain-backed)
- Trust state
- Autocrypt per-account preferences
- Operation verification session state

Without a shared location, keys imported in the host app would not be
visible to the Mail extension and vice versa.

## Decision

Both targets declare `com.apple.security.application-groups` with the
group `group.com.rnpgp.RNPForMail`. The keyring lives at:

```
~/Library/Group Containers/group.com.rnpgp.RNPForMail/Library/Application Support/RNP/keyring
```

Passphrases live in the Keychain under access group
`XX7DG778PN.group.com.rnpgp.RNPForMail` (Team Prefix + bundle ID).

## Consequences

Positive:
- Keys, trust, and Autocrypt state stay in sync automatically.
- Uninstalling the app preserves the keyring (App Group containers
  survive host-app uninstall by default; we document this in the
  Homebrew Cask so we never trash it).

Negative:
- Bundle ID prefix must match across both targets; renaming is a
  breaking change that loses user data.
- App Store submission requires the application group to be declared
  in both targets' entitlements with the correct access group.

Neutral:
- Backup/restore (TODO 19) reads/writes this directory.

## References

- Entitlements: `MailApp/MailExtensionsContainer/{Direct,AppStore}.entitlements`
- App Group helper: `Sources/MailSecurityEngine/AppGroup.swift`
