# App Store Readiness Checklist

This document tracks what's needed to submit RNP to the Mac App Store.
Tasks marked **[auto]** can be done by a developer; tasks marked
**[human]** require ronaldtse's Apple Developer account.

## Current state

- **AppStore build configuration** exists in the Xcode project (both
  host app and Mail extension targets).
- **AppStore entitlements** are complete for both targets: app-sandbox,
  application-groups, keychain-access-groups, network.client,
  files.user-selected.read-write (host only).
- **release-appstore.yml** workflow exists; triggers automatically
  after a successful direct-download release.
- **sandbox-audit.sh** script exists to verify the sandbox profile.

## Remaining tasks

### [auto] Verify AppStore scheme builds

```bash
xcodebuild -project MailApp/RnpMail.xcodeproj \
  -scheme RNP -configuration AppStore \
  build CODE_SIGNING_ALLOWED=NO
```

If this fails, the AppStore config has a code-level issue that must be
fixed before submission.

### [auto] Privacy nutrition label (PrivacyInfo.xcprivacy)

Both targets already have a `PrivacyInfo.xcprivacy` file. Verify it
declares:
- Network usage (keyserver lookups, WKD, Autocrypt)
- File usage (user-selected files for encrypt/decrypt)

Apple rejects submissions with missing or incorrect privacy manifests.

### [human] Provisioning profiles for App Store

Create MAC_APP_STORE profiles (not MAC_APP_DIRECT) for:
- `com.rnpgp.RNPForMail`
- `com.rnpgp.RNPForMail.MailExtension`

In App Store Connect → Certificates, IDs & Profiles → Profiles.

### [human] App Store Connect record

1. Create a new App in App Store Connect with bundle ID
   `com.rnpgp.RNPForMail`.
2. Fill in: app name ("RNP"), primary language, SKU, bundle ID.
3. Set the primary category: **Utilities**. Secondary: **Productivity**.

### [human] Screenshots

Apple requires screenshots for Mac App Store:
- At least 1 screenshot at 1280×800 or 1440×900.
- Recommended: show the key manager, the Files tab, and Mail
  integration (if possible to capture).

### [human] App metadata

- **Description**: "OpenPGP for your Mac — keys, files, and Mail.
  Powered by librnp, Thunderbird's official end-to-end encryption
  engine."
- **Keywords**: OpenPGP, PGP, encryption, GnuPG, GPG, mail, security,
  privacy, Thunderbird
- **Support URL**: https://github.com/rnpgp/rnp-mailapp-extension/issues
- **Privacy policy URL**: (required — even a simple GitHub-hosted page)
- **Copyright**: Ribose Inc.

### [human] Submission

```bash
# After all above is ready:
gh workflow run release-appstore.yml --repo rnpgp/rnp-mailapp-extension
# OR use Transporter / xcrun altool directly
```

The existing `release-appstore.yml` workflow builds the AppStore
archive and exports it. It currently has `SKIP_UPLOAD=1` — set to `0`
once ready to upload to App Store Connect.

## Known limitations for App Store

- **Mail extensions in App Store**: Apple allows Mail extensions on
  the Mac App Store but the review process is stricter. The extension
  must not access the network in ways Apple doesn't expect (our WKD
  and keyserver lookups should be fine — they're standard HTTPS).
- **Sandbox**: the host app must be fully sandboxed for App Store.
  The AppStore.entitlements already has this. File encryption
  requires `files.user-selected.read-write` (present).
- **Keychain**: the app group keychain access group must match
  between host and extension. Both use
  `XX7DG778PN.group.com.rnpgp.RNPForMail`.

## What CANNOT go in the App Store

- **GnuPG import** (`gpg` CLI shelling): the sandbox blocks arbitrary
  process execution. The KeyringScanner's GnuPG path will fail in a
  sandboxed App Store build. The RNP keyring import path still works.
  Document this in the App Store build's release notes.
- **Developer ID-only features**: the Direct (Developer ID) build can
  do things the App Store build can't (e.g., unsigned binary access).
  These are gated behind `#if !APPSTORE` or runtime checks.
