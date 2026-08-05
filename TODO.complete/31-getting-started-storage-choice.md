# 31 — Getting Started: choose canonical store

**Priority**: P0
**Status**: in progress
**Effort**: M
**Dependencies**: 33 (Phase 1.5 refactor)

## Problem

Today, first-launch onboarding silently uses the App Group container
as the canonical store. Users with existing GnuPG keyrings, users who
want iCloud sync, users who want a synced folder for Mac+Linux — all
get the local default whether it fits them or not. They have to find
Sync settings later.

Worse: a user who imports from `~/.gnupg/` during onboarding thinks
they're "using GnuPG" — but RNP actually copied the keys into its own
App Group container. They have two keyrings now and don't know it.

## Goals

- First-launch flow asks the user where RNP should keep its keys
- Choices: local (default), restore from backup, per-key dir (synced folder)
- CloudKit option appears once iCloud is signed in
- Subsequent steps adapt: "Restore from backup" → file picker; "Local" → generate or import

## Design

### Where this lives

Onboarding is currently driven by `OnboardingView` (in swift-rnp's
`RnpMailUI` target). Two options:

1. **Modify swift-rnp** to add a storage-choice step.
2. **Wrap onboarding in the host app** with a pre-step.

Option 2 is cleaner — keeps swift-rnp's onboarding reusable, lets the
host app inject its own step. We add a `StorageChoiceSheet` shown
before `OnboardingView` if no canonical store has been chosen yet.

### Storage choice UI

```
┌─────────────────────────────────────────────────────────────┐
│  Where should RNP keep your keys?                            │
│                                                              │
│  ● Local keyring (recommended)                              │
│      ~/Library/Group Containers/.../keyring                │
│      Fastest. Stays on this Mac.                            │
│                                                              │
│  ○ Synced folder                                            │
│      One .asc file per key in a folder you pick.            │
│      Sync via iCloud Drive, Dropbox, Syncthing, git.        │
│      Best for Mac+Linux workflows.                         │
│                                                              │
│  ○ iCloud (CloudKit)                                        │
│      Automatic sync to your iPhone.                        │
│      Requires iCloud sign-in.                              │
│                                                              │
│  ○ Restore from backup                                      │
│      Pick an encrypted .pgp backup file.                    │
│      You'll need the passphrase you set when deleting.      │
│                                                              │
│  [Continue]                          [Skip — use default]   │
└─────────────────────────────────────────────────────────────┘
```

### State persistence

`UserDefaults.standard["canonicalStoreChoice"]` stores the chosen
backend identifier (`"rnp-local"`, `"rnp-asc-dir:<path>"`,
`"rnp-cloudkit"`, etc.). The composite backend reads this on launch
and configures itself.

### What happens next

After the choice:
- Local → standard onboarding (generate or import)
- Synced folder → user picks the folder via NSOpenPanel; standard
  onboarding but writes go to that folder
- iCloud → confirm iCloud is signed in; standard onboarding
- Restore from backup → NSSavePanel; user enters passphrase; keys
  import; skip generate/import step

## Implementation plan

1. `StorageChoiceSheet` SwiftUI view
2. Wire into `MailExtensionsContainerApp` onboarding presentation
3. Persist choice to UserDefaults
4. Backend factory reads UserDefaults on launch
5. Localization keys

## Acceptance criteria

- [ ] First launch shows the choice sheet before generate/import step
- [ ] User can pick each of the 4 options
- [ ] iCloud option disabled with clear message if not signed in
- [ ] Choice persists across launches
- [ ] "Skip — use default" preserves current behavior
- [ ] Spec in `docs/specs/getting-started-storage.md`

## References

- docs/sync-architecture.md
- TODO.complete/32-sync-settings-ui.md
