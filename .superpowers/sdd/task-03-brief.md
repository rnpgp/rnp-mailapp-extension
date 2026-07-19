# Task 03 — Notarized direct distribution (GH Releases DMG)

Source: `TODO.impl/03-notarized-direct-release.md`

Status: pending. Depends on Task 01 (framework) and Task 02 (IDs/entitlements) being complete.

## Goal

Create a tag-driven GitHub Actions pipeline producing a signed, notarized, stapled `RnpMail-<version>.dmg` attached to the GitHub Release — the install path for non-App-Store users.

## Required final state

1. **Version config**: `Swift-Rnp/Config/Version.xcconfig` (created in Task 02) is the single source for `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. **Export options**: `Swift-Rnp/Config/ExportDirect.plist` with `method: developer-id`, team ID from env / build setting.
3. **Release script**: `scripts/release-direct.sh` runnable locally by maintainers AND in CI:
   - Archive `MailPlugin` scheme with `-configuration Direct`.
   - Export archive with `Config/ExportDirect.plist`.
   - Verify embedded code BEFORE notarizing: `codesign --verify --deep --strict --verbose=2`, plus `otool -L` audit (no `/usr/local`).
   - Build DMG via `create-dmg` (brew; pin version in CI) with `/Applications` symlink.
   - Notarize with `xcrun notarytool submit <dmg> --wait --key <p8> --key-id <id> --issuer <issuer>`.
   - Staple with `xcrun stapler staple <dmg>`.
   - Verify with `spctl -a -t exec -vv` and `xcrun stapler validate`.
   - Output `SHA256SUMS`.
   - Pre-flight check: tag must equal `v$MARKETING_VERSION` (read from `Version.xcconfig`).
4. **Self-test mode**: add `--self-test` to the container app (`MailExtensionsContainer`) that builds an Rnp context, prints `versionStringFull`, and exits 0. This enables the smoke-test job.
5. **GitHub workflow**: `.github/workflows/release-direct.yml` triggered on push of tag `v*`:
   - macos-15 runner (pin).
   - Restore framework cache from Task 01.
   - Import signing certificate into a temporary keychain.
   - Run `scripts/release-direct.sh` with secrets env.
   - Create GitHub Release with DMG + SHA256SUMS (`gh release create ... --generate-notes`).
   - Re-running for the same tag must fail safely (release exists) instead of duplicating assets.
   - Smoke-test job (second job, needs first): on a fresh runner, download the DMG, attach it, `spctl -a -t exec -vv` the app, run the container app once with `--self-test`.
6. **README**: add "Install (direct download)" section with placeholder for screenshots + the Mail → Settings → Extensions enable step.

## Acceptance criteria

- `scripts/release-direct.sh` can be run locally in unsigned mode (for structure verification) without Apple secrets: `CODE_SIGNING_ALLOWED=NO` should produce a `.app` bundle and DMG skeleton. The notarization steps should be skipped when secrets are absent.
- Workflow file is syntactically valid and logically correct (you cannot run actual CI here).
- The container app's `--self-test` runs and exits 0 against the vendored framework in an unsigned local build.

## Current state to extend

- No release script or workflow exists.
- Container app is a SwiftUI app with no command-line argument handling.
- The framework and Xcode project will be wired by Task 01; IDs/entitlements by Task 02.

## Notes

- NEVER commit .p12 or ASC key; secrets only.
- Keychain cleanup must run `if: always()` in CI.
- The appex inside the app must carry the same team ID — inside-out codesign order matters.
- Use placeholder/empty signing identity defaults so local unsigned runs succeed; real signing requires env vars.
