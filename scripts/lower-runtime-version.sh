#!/usr/bin/env bash
# lower-runtime-version.sh
#
# Walk every Mach-O bundle inside an .app and re-stamp the Hardened
# Runtime version to 14.0. macOS 14.0–14.3 pluginkit rejects Mail
# extensions whose runtime version exceeds the system's macOS version,
# with errors like "SecStaticCodeCreateWithPath failed -67028" and
# "errSecCSReqFailed -67062" in Console.
#
# Usage:
#   scripts/lower-runtime-version.sh path/to/RNP.app
#
# Re-signs with the existing "Developer ID Application" identity from
# the keychain (must already be imported — e.g. via `fastlane match`).
# Preserves entitlements, provisioning profile reference, identifier,
# and requirements via --preserve-metadata.

set -euo pipefail

APP="${1:?usage: $0 <app-bundle>}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"

if [[ ! -d "${APP}" ]]; then
    echo "ERROR: not a directory: ${APP}" >&2
    exit 1
fi

echo "=== Re-signing with Hardened Runtime version 14.0 ==="
for bundle in \
    "${APP}" \
    "${APP}/Contents/Frameworks/RNPFramework.framework" \
    "${APP}/Contents/PlugIns/MailPlugin.appex"; do
    [[ -e "${bundle}" ]] || continue
    codesign --force --options runtime --runtime-version 14.0 \
        --preserve-metadata=identifier,requirements,entitlements,flags,resource-rules \
        --sign "${IDENTITY}" \
        "${bundle}"
done

echo "=== Runtime version (must be 14.0.0) ==="
codesign -d --verbose=4 "${APP}/Contents/PlugIns/MailPlugin.appex" 2>&1 | grep -E "Runtime|VersionSDK" || true
