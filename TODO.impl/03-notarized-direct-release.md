# 03 — Notarized direct distribution (GH Releases DMG)

Status: pending · Milestone: M1c · Depends on: 01, 02 · Needs: Apple secrets
(00-overview checklist items 3–5)

## Goal

Tag-driven GitHub Actions pipeline producing a signed, notarized, stapled
`RnpMail-<version>.dmg` attached to the GitHub Release — the install path for
non-App-Store users.

## Reference flow (verified)

codesign (inside-out: frameworks, appex, then app) → create DMG →
`xcrun notarytool submit <dmg> --wait` → `xcrun stapler staple <dmg>` →
verify `spctl -a -t exec -vv` + `xcrun stapler validate` → upload.
Notarytool accepts the App Store Connect API key directly:
`--key <p8 path> --key-id <id> --issuer <issuer>`.

## Steps

1. `scripts/release-direct.sh` (runnable locally by maintainers AND in CI):
   - `xcodebuild -scheme MailPlugin -configuration Direct archive
      -archivePath build/RnpMail.xcarchive -allowProvisioningUpdates
      -authenticationKeyPath <p8> -authenticationKeyID <id> -authenticationKeyIssuerID <issuer>`
   - Export: `xcodebuild -exportArchive -exportOptionsPlist Config/ExportDirect.plist`
     (`method: developer-id`, team ID from env).
   - Verify embedded code BEFORE notarizing:
     `codesign --verify --deep --strict --verbose=2`, plus
     `otool -L` audit (no /usr/local, from task 01).
   - DMG via `create-dmg` (brew; pin version in CI) with /Applications symlink.
   - Notarize + staple + `spctl` verify; output SHA256SUMS.
2. `.github/workflows/release-direct.yml` (trigger: push tag `v*`):
   - macos-15 runner (pin), restore framework cache (task 01), import cert:
     `security create-keychain` + `security import $MACOS_CERTIFICATE_P12`
     pattern (standard; keep keychain locked to the job).
   - Run `scripts/release-direct.sh` with secrets env.
   - `gh release create "$GITHUB_REF_NAME" dist/*.dmg SHA256SUMS --generate-notes`.
3. Version numbering: single source `Config/Version.xcconfig`
   (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`); the tag must equal
   `v$MARKETING_VERSION` — add a pre-flight check step that fails the release
   on mismatch.
4. Smoke-test job in the same workflow (second job, needs the first): on a
   fresh runner, download the DMG, attach it, `spctl -a -t exec -vv` the app,
   and run the container app once with `--self-test` (add a tiny self-test
   mode to the app: builds Rnp context, prints versionString, exits 0).
5. README "Install (direct download)" section with screenshots placeholder +
   the Mail → Settings → Extensions enable step.

## Acceptance criteria

- Pushing tag `v0.9.0-test` (delete afterwards) yields a GH Release with a
  DMG whose `spctl` assessment passes on a machine that has never seen the app.
- `xcrun stapler validate` passes; download-attach-launch works offline
  (stapled ticket).
- Release run is reproducible: re-running the workflow for the same tag fails
  safely (release exists) instead of duplicating assets.

## Risks / notes

- First notarization of a new bundle ID can take 10–30 min; keep `--wait`
  timeout generous (notarytool default is fine; add `--timeout 30m` wrapper).
- NEVER commit the .p12 or the ASC key; secrets only. Keychain cleanup step
  must run `if: always()`.
- The appex inside the app must carry the SAME team ID or Mail refuses to
  load it — the inside-out codesign order matters; `--deep` on the app is NOT
  sufficient by itself.
