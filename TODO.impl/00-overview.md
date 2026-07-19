# 00 — Overview: First-Class OpenPGP Mail Extension

This directory is the executable plan for turning this repo into the best
OpenPGP/LibrePGP security extension for Apple Mail, distributable both from
GitHub Releases (Developer ID + notarized DMG) and the Mac App Store.

Each `NN-name.md` is a self-contained task. A fresh session should be able to
pick up any single file and execute it without further context. Read THIS file
first; then check the "Current state" section — it may be stale.

## Current state (as of 2026-07-19 — VERIFY before starting)

- Repo: `/Users/mulgogi/src/rnp/swift-rnp`, upstream `rnpgp/rnp-mailapp-extension`.
- `main` contains the SwiftPM binding package (merged in PR #12):
  `Package.swift`, `Sources/CRnp` (systemLibrary, pkgConfig `librnp`),
  `Sources/Rnp` (Swift wrapper), `Tests/RnpTests`, `.github/workflows/test.yml`.
- **PR #13 "Make the Apple Mail extension fully functional" is OPEN and
  CI-green** (branch `mail-extension-full`): adds `Sources/MailSecurityEngine`
  (MIME parse, KeyManager, PGP/MIME + inline encode/decode), 44 XCTest total,
  rehabilitated Xcode project (`Swift-Rnp/Swift-Rnp.xcodeproj`, targets
  `MailPlugin` appex / `Ribose container` app / `Swift-Rnp` CLI),
  `librnp.xcconfig`, entitlements with placeholder IDs `group.com.ribose.rnp`
  / `com.ribose.Container`, README "Use with Apple Mail" guide.
  → Task files assume PR #13 is MERGED. First step of any task: check
  `gh pr view 13 --repo rnpgp/rnp-mailapp-extension`; if still open and green,
  merge it (`gh pr merge 13 --rebase`) before starting.
- Local librnp installs for testing (do not modify):
  `/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1` and `.../main`
  (each: `lib/`, `include/rnp/`, `lib/pkgconfig/librnp.pc`).

## Shared commands

```sh
# package tests against a local librnp (both installs must pass)
PKG_CONFIG_PATH=<prefix>/lib/pkgconfig swift test -Xlinker -rpath -Xlinker <prefix>/lib

# Xcode builds (no signing)
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme "Ribose container" build CODE_SIGNING_ALLOWED=NO
```

## Conventions

- Commits: 50/72 rule, focused commits; branch per task `NN-short-name`;
  PR per task unless trivial; CI must stay green (`.github/workflows/test.yml`).
- All logic that can live outside MailKit MUST live in SwiftPM targets and be
  covered by `swift test`. Xcode targets stay thin shells.
- No force-unwraps in library code; RAII/`defer` for FFI resources;
  errors as typed Swift errors carrying `rnp_result_to_string`.
- librnp policy: support v0.18.1 (CVE-2025-13470 baseline) and rnp `main`.
  Interop defaults: v4 keys, AES-256, SHA-384/512, MDC/CFB (AEAD/v6 opt-in only).

## The plan in one paragraph

MailKit is the only sanctioned way to extend Apple Mail (since macOS Sonoma),
and a Mail extension ships inside a container macOS app. Apple allows that app
in the Mac App Store AND as a notarized direct download (WWDC21 session 10168).
We build: (M1) signing/packaging foundation with a vendored
`RNPFramework.xcframework` and both distribution pipelines, (M2) complete key
management UX, (M3) key lifecycle (rotation/expiry/revocation), (M4) keyserver
publishing + discovery (VKS/HKPS/WKD), (M5) trust/verification (TOFU + manual
verify), (M6) App Store submission, (M7) polish (a11y, l10n, perf, threat
model, dependency policy).

## Task map

| File | Milestone | Depends on |
|---|---|---|
| `01-rnpframework-xcframework.md` | M1a vendored librnp framework | PR #13 merged |
| `02-bundle-identifiers-entitlements.md` | M1b IDs, entitlements, privacy manifest | 01 |
| `03-notarized-direct-release.md` | M1c GH Releases DMG pipeline | 01, 02 + Apple secrets |
| `04-key-management-ux.md` | M2 key CRUD, onboarding, Touch ID | 01 |
| `05-key-lifecycle.md` | M3 rotation, expiry, revocation | 04 |
| `06-keyserver-publishing.md` | M4 VKS/HKPS/WKD client + flows | 01 |
| `07-trust-verification.md` | M5 TOFU trust store + verify UI | 04, 06 |
| `08-app-store.md` | M6 MAS pipeline + submission | 03, 05 + Apple account steps |
| `09-polish.md` | M7 a11y/l10n/perf/threat-model | 02–07 |

## Apple Developer account checklist (human-only, needed by 03 and 08)

1. Active Apple Developer Program membership (org team for rnpgp preferred).
2. Identifiers: App Group (proposed `group.com.rnpgp.RnpMail`), App IDs
   `com.rnpgp.RnpMail` + `com.rnpgp.RnpMail.MailExtension` with App Groups
   capability. (Final names are the owner's decision — update task 02.)
3. Certificates: **Developer ID Application** (direct) and **Apple
   Distribution** (MAS); export .p12 for CI.
4. App Store Connect API key (Users & Access → Integrations) — used for both
   notarization and MAS upload.
5. GitHub secrets (repo rnpgp/rnp-mailapp-extension): `MACOS_CERTIFICATE_P12`,
   `MACOS_CERTIFICATE_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `ASC_API_KEY_P8`,
   `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `TEAM_ID`.
6. App Store Connect app record + privacy policy URL + encryption export
   self-classification (OpenPGP → standard open-source ERN route; not legal
   advice). Needed only at task 08.
