# 03 — Mac App Store submission

**Priority**: P1
**Status**: not started (blocked on ronaldtse — needs Apple account actions)
**Effort**: M (engineering) + human tasks
**Dependencies**: 12 (specs/tests — privacy manifest audit)

## Problem

The Mac App Store is the discovery channel for Mac users who don't read
Hacker News or GitHub trending. Privacy-first tools do well there
(Little Snitch, 1Password, Signal-ish utilities). Currently RNP is
DMG-only.

## Goals / non-goals

**Goals**
- RNP approved and live on the Mac App Store
- Same feature set as the Direct/Developer ID build, with sandbox-only
  exceptions
- Both targets (host + MailPlugin) sandboxed and signed with App Store
  provisioning profile

**Non-goals**
- Replacing the Direct build — both coexist. Direct keeps features the
  sandbox forbids (e.g., GnuPG keyring import).
- iOS App Store (that's TODO 11)

## Design

The project is already structured for two configs:
- `Direct` — Developer ID distribution (current release channel)
- `AppStore` — Mac App Store distribution

Per-target entitlements already exist:
- `MailApp/MailExtensionsContainer/Direct.entitlements`
- `MailApp/MailExtensionsContainer/AppStore.entitlements`
- `MailApp/MailPlugin/Direct.entitlements`
- `MailApp/MailPlugin/AppStore.entitlements`

The release pipeline already has `.github/workflows/release-appstore.yml`
that builds the AppStore config and uploads to App Store Connect — but
`SKIP_UPLOAD=1` is set. Flip to `0` once the steps below are complete.

### Sandbox constraints to verify

| Capability              | Direct | App Store | Notes                                            |
| ----------------------- | :----: | :-------: | ------------------------------------------------ |
| app-sandbox             | ✅     | ✅ (req)  | Required for App Store + Mail extensions         |
| application-groups      | ✅     | ✅        | Shared keyring between host and extension        |
| network.client          | ✅     | ✅        | WKD, keys.openpgp.org, Autocrypt                 |
| keychain-access-groups  | ✅     | ✅        | Shared passphrase store                          |
| files.user-selected.rw | ✅     | ✅        | File Tools encrypt/decrypt                      |
| Process execution (`gpg`)| ✅    | ❌        | KeyringScanner's GnuPG path — gate behind !APPSTORE |

### Hard blockers for App Store

- `KeyringScanner.gpgScan()` shells out to `/usr/local/bin/gpg` or
  `/opt/homebrew/bin/gpg`. The sandbox blocks arbitrary process
  execution. **Fix**: gate behind `#if !APPSTORE` and document the
  AppStore build doesn't import from GnuPG.

## Implementation plan

### Engineering tasks (auto)

1. ✅ Verify AppStore scheme builds (already done previously)
2. Gate GnuPG import path behind `#if !APPSTORE`
3. Audit `PrivacyInfo.xcprivacy` for both targets — confirm declares:
   - Network usage (keyserver lookups, WKD, Autocrypt)
   - File usage (user-selected files for encrypt/decrypt)
4. Generate screenshots at 1280×800 and 1440×900 (Tools hub, key list,
   File Tools, Mail banner)
5. Generate App Store icon set (already in asset catalog)

### Human tasks (ronaldtse)

1. Create MAC_APP_STORE provisioning profiles for:
   - `com.rnpgp.RNPForMail`
   - `com.rnpgp.RNPForMail.MailExtension`
2. Create the App Store Connect record (name, SKU, bundle ID)
3. Set metadata: description, keywords, support URL, privacy policy URL
4. Upload screenshots
5. Set `SKIP_UPLOAD=0` in `release-appstore.yml` and trigger

## Acceptance criteria

- [ ] AppStore scheme builds with no warnings
- [ ] `scripts/sandbox-audit.sh` reports clean sandbox profile
- [ ] Privacy manifests accurate for both targets
- [ ] Submitted to App Store Connect
- [ ] Review approved (Apple's call)
- [ ] Live on Mac App Store

## Open questions

- **Apple's policy on Mail extensions in App Store.** Allowed, but
  review is stricter. Pre-empt by being clear in metadata about what
  the extension accesses (network for key lookups; no message content
  leaves the device except encrypted mail you're sending).
- **Pricing.** Free with donation? Paid? Discussion needed.

## Out of scope

- Marketing site copy (handled in TODO 09)
- Press launch (community announcement — separate)

## References

- Readiness checklist: `docs/app-store-readiness.md`
- Workflow: `.github/workflows/release-appstore.yml`
- Apple Mail extension sandbox rules: Apple Developer docs
