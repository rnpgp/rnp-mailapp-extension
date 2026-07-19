# Task 02 — Bundle identifiers, entitlements, privacy manifest

Source: `TODO.impl/02-bundle-identifiers-entitlements.md`

Status: pending. Depends on Task 01 (framework) being complete.

## Goal

Replace all placeholder identifiers with real registered ones, split build settings into `Direct` and `AppStore` channel configurations, and add the Apple-required privacy manifest.

## Required final state

1. **Single-source IDs**: create `Swift-Rnp/Shared/IDs.xcconfig` with:
   - `RNPMAIL_BUNDLE_ID_CONTAINER = com.rnpgp.RnpMail`
   - `RNPMAIL_BUNDLE_ID_EXTENSION = com.rnpgp.RnpMail.MailExtension`
   - `RNPMAIL_APP_GROUP = group.com.rnpgp.RnpMail`
   - `RNPMAIL_KEYCHAIN_ACCESS_GROUP = $(AppIdentifierPrefix)$(RNPMAIL_APP_GROUP)`
   Include this xcconfig in the project and reference these variables in target build settings / Info.plist where possible.
2. **Channel xcconfigs** under `Swift-Rnp/Config/`:
   - `Direct.xcconfig`: sandbox ON, app group IDs, `CODE_SIGN_IDENTITY=Developer ID Application`, hardened runtime ON.
   - `AppStore.xcconfig`: `CODE_SIGN_IDENTITY=Apple Distribution`, sandbox ON, same groups, no hardened-runtime requirement.
   - `Version.xcconfig`: `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` single source.
   - Add `Direct` and `AppStore` build configurations (duplicate Release) on the project; set both schemes' archive action to the matching configuration.
3. **Entitlements files** (replace current ones):
   - `MailPlugin/Direct.entitlements` + `MailPlugin/AppStore.entitlements`: sandbox, application-groups, network.client, keychain-access-groups.
   - `MailExtensionsContainer/Direct.entitlements` + `MailExtensionsContainer/AppStore.entitlements`: sandbox, application-groups, files.user-selected.read-write, network.client, keychain-access-groups.
4. **PrivacyInfo.xcprivacy** in both targets:
   - `NSPrivacyTracking=NO`
   - empty `NSPrivacyCollectedDataTypes`
   - `NSPrivacyAccessedAPIs`: `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` (app-group prefs); include `NSPrivacyAccessedAPICategoryFileTimestamp` reason `C617.1` only if the code actually stats files — audit first, omit if unused.
5. **Keychain sharing**: update `KeychainPassphraseStore` to accept an explicit `kSecAttrAccessGroup` (team-prefixed group) read from `IDs.xcconfig` / Info.plist, with a fallback to no access group for unsigned dev builds.
6. **AppGroup.swift**: read the app group identifier from `IDs.xcconfig` via `Bundle.main.object(forInfoDictionaryKey:)` or a build-time injected value; keep a sensible fallback for unsigned dev.
7. **Project**: update `Swift-Rnp/Swift-Rnp.xcodeproj/project.pbxproj` to use the new xcconfigs, entitlements, Info.plist keys, and privacy manifest files. Remove any stale `librnp.xcconfig` reference.
8. **README**: update the "Use with Apple Mail" section from `com.ribose.*` to the real IDs and describe the `Direct`/`AppStore` build configurations.

## Acceptance criteria

- `grep -r "com.ribose" Swift-Rnp/` → no matches (except git history).
- Both configurations archive locally:
  - `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin -configuration Direct archive CODE_SIGNING_ALLOWED=NO`
  - `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin -configuration AppStore archive CODE_SIGNING_ALLOWED=NO`
- `plutil -lint` passes on all entitlements + PrivacyInfo files.
- App group dir resolves identically in app and appex (log once at debug).

## Current state to extend

- Placeholder IDs are used: `com.ribose.Container` (container bundle ID), `com.ribose.swift-rnp.container.MailPlugin` (extension), `group.com.ribose.rnp` (app group), `$(AppIdentifierPrefix)group.com.ribose.rnp` (keychain group).
- `Swift-Rnp/Shared/AppGroup.swift` hardcodes `group.com.ribose.rnp`.
- `Swift-Rnp/Shared/KeychainPassphraseStore.swift` does not set `kSecAttrAccessGroup`.
- `Swift-Rnp/MailPlugin/MailPlugin.entitlements` and `MailExtensionsContainer/MailExtensionsContainer.entitlements` use the old group.
- The container app target likely uses a generated Info.plist; if injecting custom keys proves difficult, switch it to an explicit `MailExtensionsContainer/Info.plist`.
- The project may still reference the deleted `Swift-Rnp/librnp.xcconfig`; clean that up.

## Notes

- Use `com.rnpgp.RnpMail` as the default real IDs; only change if the owner explicitly says otherwise.
- Changing the app group orphans existing dev keyrings — acceptable pre-1.0; note migration in README.
