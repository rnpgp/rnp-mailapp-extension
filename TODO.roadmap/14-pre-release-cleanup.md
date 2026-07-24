# 14 — Pre-release cleanup: licenses, FAQ drift, notarization pre-flight

Status: pending · Tier: Future · Depends on: nothing

## Goal

Land the small-but-blocking items that the human-release process depends
on, so the human's time on Apple account setup, notarization, and App
Review goes smoothly.

This is the file that closes the issues the previous session pushed to the
human (issue #14 subtasks, #80 prep, etc.) with code we can do today.

## Work items

### 1. Bundle full license texts

The `About → Licenses` view currently reads `Vendor/SOURCES.md`, which is
a summary. The BSD-2 / MIT / zlib / bzip2 licenses require distributing
the **full license text** with binaries. Add the full texts to the app
bundle.

- Add `Swift-Rnp/MailExtensionsContainer/Resources/Licenses/` directory.
- Copy the actual `LICENSE` files from each dependency:
  - `LICENSE.rnp.txt` (BSD-2-Clause) — from the librnp source tarball.
  - `LICENSE.botan.txt` (BSD-2-Clause) — from Botan release.
  - `LICENSE.json-c.txt` (MIT) — from json-c source.
  - `LICENSE.sexpp.txt` (BSD-2-Clause) — from sexpp submodule.
  - `LICENSE.zlib.txt` (zlib license) — system library; include anyway.
  - `LICENSE.bzip2.txt` (BSD-style) — system library; include anyway.
- Update `LicensesView.swift` to read each file and display it under a
  header with the project name, upstream URL, and license summary
  (already in `Vendor/SOURCES.md`).
- Add a build phase to copy the licenses into the app bundle's Resources.

### 2. FAQ drift fix

`docs/faq.md` says under "Which key algorithms can I generate?":

> RSA-3072 (the librnp 0.18 default) and ECDSA P-256.

The code supports Ed25519 too (`KeyAlgorithm.ed25519` in
`Sources/MailSecurityEngine/KeyManager.swift`). Fix the FAQ to list all
three (or whatever the actual current surface is). Cross-check
`Sources/RnpMailUI/GenerateKeyForm.swift` to confirm the user-facing
options.

While at it: audit the FAQ and `docs/features.md` for any other drift
against the actual code. Likely candidates:

- "Can I use a SmartCard or hardware token?" — answer is "No" today; this
  is correct, no change.
- Trust model — already aligned.
- Autocrypt — once `07-autocrypt.md` lands, this answer changes.

### 3. `scripts/release-preflight.sh`

A local script that runs every shape check we can run without Apple
secrets, so the real notarization dry-run (with secrets, on CI) fails on
shape errors not on infrastructure.

The script:

```sh
#!/usr/bin/env bash
# scripts/release-preflight.sh — run before tagging a release.
set -euo pipefail

APP_PATH="${1:-build/RnpMail.app}"

echo "== Entitlements plutil lint =="
find "$APP_PATH" -name "*.entitlements" -exec plutil -lint {} \;

echo "== PrivacyInfo plutil lint =="
find "$APP_PATH" -name "PrivacyInfo.xcprivacy" -exec plutil -lint {} \;

echo "== Code signature (ad-hoc check) =="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "== otool dependency audit (no /usr/local or /opt/homebrew) =="
OTOUT=$(otool -L "$APP_PATH/Contents/MacOS/"* "$APP_PATH/Contents/PlugIns/"*/*.appex/Contents/MacOS/* 2>&1)
if echo "$OTOUT" | grep -E "^(/usr/local|/opt/homebrew)"; then
  echo "FAIL: hardcoded Homebrew paths found"
  echo "$OTOUT"
  exit 1
fi

echo "== spctl assessment (ad-hoc; not a Gatekeeper pass) =="
spctl -a -t install -vv "$APP_PATH" || echo "(ad-hoc signed; spctl assessment expected to fail pre-notarization)"

echo "== Framework structure check =="
[[ -d "$APP_PATH/Contents/Frameworks/RNPFramework.framework" ]] \
  && echo "RNPFramework embedded: OK" \
  || { echo "FAIL: RNPFramework not embedded"; exit 1; }

echo "== Version consistency =="
# TODO: compare Info.plist CFBundleShortVersionString against the tag.

echo "Preflight complete."
```

Wire into `.github/workflows/test.yml` as a post-build step on every PR
that touches the Xcode project or scripts.

### 4. README "Install" section polish

The README's install section currently assumes a developer build. Add the
direct-download path (DMG once task 03 lands) and the App Store path (once
task 08 lands), with the Mail extension enable steps clearly photographed
or screenshotted.

### 5. `docs/key-lifecycle.md` (new page)

A user-facing walkthrough of the full key lifecycle, mirroring the scenario
table in `TODO.roadmap/04-key-expiry-recovery.md`. This complements the
technical `docs/trust-model.md` with the practical "what do I do" view.

## Tests

- A CI assertion that the licenses directory contains the six expected
  files.
- A CI step running `scripts/release-preflight.sh` against an unsigned
  build on every PR.

## Acceptance criteria

- The Licenses view shows full text for every dependency license.
- The FAQ and features docs match the actual code surface.
- `scripts/release-preflight.sh` exists, is executable, runs green on a
  clean build, and catches at least the common shape errors (missing
  framework, Homebrew paths, malformed plists).
- `docs/key-lifecycle.md` exists and is linked from the main docs index.

## Notes / risks

- License files are committed verbatim from upstream. Do not edit them to
  "clean up" formatting — they are legal text.
- The pre-flight script should not require Apple secrets. Anything that
  does (real signing, real notarization) stays in the secret-gated
  workflow.
- Version-consistency check between tag and `CFBundleShortVersionString`
  is the same logic the release workflow does; share the script between
  local pre-flight and CI to avoid duplication.
