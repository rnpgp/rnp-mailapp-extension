#!/usr/bin/env bash
#
# scripts/release-preflight.sh
#
# Runs every release-shape check we can run locally WITHOUT Apple
# secrets, so the real notarization/App-Store-upload dry-run on CI
# (which does use secrets) fails on actual issues rather than on
# infrastructure.
#
# What this script checks:
#   1. Entitlements files plutil-lint clean.
#   2. PrivacyInfo.xcprivacy files plutil-lint clean.
#   3. codesign --verify --deep --strict on the app bundle.
#   4. otool -L dependency audit: no /usr/local or /opt/homebrew paths.
#   5. RNPFramework is embedded.
#   6. spctl assessment (best-effort; ad-hoc signed builds fail this
#      pre-notarization — that's expected).
#
# Usage:
#   scripts/release-preflight.sh path/to/RnpMail.app
#
# Exit status: 0 on all-pass, 1 on any failure.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <path-to-app-bundle>" >&2
    exit 2
fi

APP_PATH="$1"

if [[ ! -d "$APP_PATH" ]]; then
    echo "FAIL: app bundle does not exist: $APP_PATH" >&2
    exit 1
fi

fail=0
section() {
    echo
    echo "== $* =="
}

check() {
    if "$@"; then
        echo "ok"
    else
        echo "FAIL"
        fail=1
    fi
}

section "Entitlements plutil lint"
ENT_FOUND=0
while IFS= read -r f; do
    ENT_FOUND=1
    printf "  %s ... " "$f"
    check plutil -lint "$f"
done < <(find "$APP_PATH" -name "*.entitlements" -type f)
[[ $ENT_FOUND -eq 0 ]] && echo "  (no entitlements files in bundle; skip)"

section "PrivacyInfo plutil lint"
PRIV_FOUND=0
while IFS= read -r f; do
    PRIV_FOUND=1
    printf "  %s ... " "$f"
    check plutil -lint "$f"
done < <(find "$APP_PATH" -name "PrivacyInfo.xcprivacy" -type f)
[[ $PRIV_FOUND -eq 0 ]] && echo "  (no PrivacyInfo files in bundle; this is a FAIL for MAS)"
[[ $PRIV_FOUND -eq 0 ]] && fail=1

section "Code signature (deep, strict)"
printf "  codesign --verify --deep --strict --verbose=2 ... "
if codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/tmp/rnp-preflight-codesign.txt 2>&1; then
    echo "ok"
else
    echo "FAIL"
    fail=1
    cat /tmp/rnp-preflight-codesign.txt
fi

section "otool dependency audit (no Homebrew paths)"
OT_DEPS=$(mktemp)
trap 'rm -f "$OT_DEPS"' EXIT

# Audit the main executable and any app extensions.
MAIN_BIN=$(find "$APP_PATH/Contents/MacOS" -type f -perm +111 2>/dev/null | head -1)
if [[ -n "$MAIN_BIN" ]]; then
    otool -L "$MAIN_BIN" > "$OT_DEPS" 2>&1 || true
fi
while IFS= read -r appex; do
    appex_bin=$(find "$appex/Contents/MacOS" -type f 2>/dev/null | head -1)
    [[ -n "$appex_bin" ]] && otool -L "$appex_bin" >> "$OT_DEPS" 2>&1 || true
done < <(find "$APP_PATH/Contents/PlugIns" -name "*.appex" -type d 2>/dev/null)

if grep -E "^(/usr/local|/opt/homebrew)" "$OT_DEPS"; then
    echo "FAIL: hardcoded Homebrew paths found in linkage:"
    grep -E "^(/usr/local|/opt/homebrew)" "$OT_DEPS"
    fail=1
else
    echo "ok (no Homebrew paths)"
fi

section "RNPFramework embedded"
FW_PATH="$APP_PATH/Contents/Frameworks/RNPFramework.framework"
if [[ -d "$FW_PATH" ]]; then
    echo "ok ($FW_PATH)"
else
    echo "FAIL: RNPFramework not embedded at $FW_PATH"
    fail=1
fi

section "spctl assessment (ad-hoc pre-notarization)"
# spctl will fail pre-notarization on ad-hoc or developer-id builds
# without a stapled ticket. Treat failures as informational.
if spctl -a -t install -vv "$APP_PATH" >/tmp/rnp-preflight-spctl.txt 2>&1; then
    echo "ok"
else
    echo "informational (ad-hoc signed builds fail pre-notarization — expected)"
    cat /tmp/rnp-preflight-spctl.txt
fi

echo
if [[ $fail -ne 0 ]]; then
    echo "Preflight: FAIL"
    exit 1
fi
echo "Preflight: PASS"
exit 0
