# 02 — Bundle identifiers, entitlements, privacy manifest

Status: pending · Milestone: M1b · Depends on: 01

## Goal

Replace all placeholder identifiers with the real registered ones, split
build settings into `Direct` and `AppStore` channel configurations, and add
the Apple-required privacy manifest.

## Context

- Placeholders in the Xcode project today: bundle IDs `com.ribose.Container`,
  app group `group.com.ribose.rnp`, `DEVELOPMENT_TEAM` unset (intentionally).
- Proposed real IDs (confirm with the owner — the Apple Dev account checklist
  in 00-overview registers these): container `com.rnpgp.RnpMail`, extension
  `com.rnpgp.RnpMail.MailExtension`, app group `group.com.rnpgp.RnpMail`,
  keychain access group `$(AppIdentifierPrefix)group.com.rnpgp.RnpMail`.
- App Store REQUIREMENTS: app sandbox ON, registered team-prefixed app group,
  network client entitlement for keyserver access (task 06), no dylib loads
  outside the bundle (task 01 solves), `PrivacyInfo.xcprivacy`.

## Steps

1. Ask/decide final IDs (default to the proposed rnpgp ones if the owner is
   unavailable; keep them in ONE place: a new `Swift-Rnp/Shared/IDs.xcconfig`
   included by target build settings).
2. Create channel xcconfigs:
   - `Config/Direct.xcconfig`: sandbox ON (keep parity with MAS where
     possible), app group IDs, `CODE_SIGN_IDENTITY=Developer ID Application`,
     hardened runtime (`ENABLE_HARDENED_RUNTIME=YES`) — needed for notarization.
   - `Config/AppStore.xcconfig`: `CODE_SIGN_IDENTITY=Apple Distribution`,
     sandbox ON (required), same groups. No hardened runtime requirement.
   - Add two build configurations (duplicate Release) named `Direct` and
     `AppStore` on the project; both schemes get matching archive config.
3. Entitlements files (replace the current ones):
   - `MailPlugin/Direct.entitlements` + `MailPlugin/AppStore.entitlements`:
     `com.apple.security.app-sandbox`, `com.apple.security.application-groups`
     = the app group, `com.apple.security.network.client` (keyserver refresh
     from the extension is allowed; primary network use is the container app),
     `keychain-access-groups` = `$(AppIdentifierPrefix)group...`.
   - Container app versions: same + `com.apple.security.files.user-selected.read-write`
     (key import/export), `com.apple.security.network.client`.
4. `PrivacyInfo.xcprivacy` in BOTH targets:
   `NSPrivacyTracking=NO`, empty `NSPrivacyCollectedDataTypes`,
   `NSPrivacyAccessedAPIs` with `NSPrivacyAccessedAPICategoryUserDefaults`
   reason `CA92.1` (app-group prefs) and
   `NSPrivacyAccessedAPICategoryFileTimestamp` reason `C617.1` if any stat
   calls exist (audit first; omit if unused).
5. Keychain sharing: make `KeychainPassphraseStore` accept an explicit
   `kSecAttrAccessGroup` (the team-prefixed group) instead of relying on the
   default — required for MAS; keep the default fallback for unsigned dev.
6. Update README + `docs` references from `com.ribose.*` to the real IDs and
   describe the two build configurations.

## Acceptance criteria

- `grep -r "com.ribose" Swift-Rnp/` → no matches (except git history docs).
- Both configurations archive locally:
  `xcodebuild -scheme MailPlugin -configuration Direct archive CODE_SIGNING_ALLOWED=NO`
  and `-configuration AppStore` (unsigned archive OK for structure check).
- `plutil -lint` passes on all entitlements + PrivacyInfo files.
- App group dir resolves identically in app and appex (log once at debug).

## Risks / notes

- Changing the app group orphans existing dev keyrings — acceptable pre-1.0;
  note migration in README.
- IDs must match the Apple Developer registration EXACTLY or provisioning
  fails at archive/export time; coordinate with the owner (00-overview §Apple
  checklist).
