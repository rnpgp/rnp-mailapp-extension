#!/bin/bash
# scripts/release-direct.sh
# Build, sign, notarize, and package a Developer ID release of RNP.
#
# Environment variables (all optional for local unsigned dry-runs):
#   DEVELOPMENT_TEAM       Apple Team ID
#   SIGNING_IDENTITY       "Developer ID Application: ..."
#   ASC_API_KEY_P8         Path to App Store Connect API .p8 file
#   ASC_API_KEY_ID         App Store Connect API Key ID
#   ASC_ISSUER_ID          App Store Connect Issuer ID
#   CREATE_DMG             Path to create-dmg binary (default: create-dmg from PATH)

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown argument: ${arg}" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT="${REPO_ROOT}/MailApp/RnpMail.xcodeproj"
SCHEME="RNP"
CONFIG="Direct"
BUILD_DIR="${REPO_ROOT}/MailApp/Build"
ARCHIVE_PATH="${BUILD_DIR}/RNP.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export"
DIST_DIR="${REPO_ROOT}/dist"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
ASC_API_KEY_P8="${ASC_API_KEY_P8:-}"
ASC_API_KEY_ID="${ASC_API_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
CREATE_DMG="${CREATE_DMG:-create-dmg}"

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# ------------------------------------------------------------------
# Version sanity check: tag must be v$MARKETING_VERSION.
# ------------------------------------------------------------------
VERSION_FILE="${REPO_ROOT}/MailApp/Config/Version.xcconfig"
if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "Missing version file: ${VERSION_FILE}" >&2
    exit 1
fi
MARKETING_VERSION="$(grep 'MARKETING_VERSION' "${VERSION_FILE}" | awk -F'= ' '{print $2}' | tr -d ' ')"
EXPECTED_TAG="v${MARKETING_VERSION}"

if [[ -n "${RELEASE_TAG:-}${GITHUB_REF_NAME:-}" ]]; then
    # RELEASE_TAG (workflow_dispatch retries) wins over GITHUB_REF_NAME
    # (tag-push triggers); GITHUB_REF_NAME cannot be reliably overridden
    # at step level because GitHub Actions preserves its default value.
    REF_TAG="${RELEASE_TAG:-${GITHUB_REF_NAME}}"
    if [[ "${REF_TAG}" != */merge && ! "${REF_TAG}" =~ ^[0-9]+/merge$ ]]; then
        # Allow pre-release suffixes (e.g. v0.9.0-test, v1.0.0-rc1) on the same version.
        if [[ "${REF_TAG}" != "${EXPECTED_TAG}" && ! "${REF_TAG}" =~ ^${EXPECTED_TAG}-.+ ]]; then
            echo "Tag mismatch: expected ${EXPECTED_TAG} (or ${EXPECTED_TAG}-<suffix>), got ${REF_TAG}" >&2
            exit 1
        fi
        echo "Releasing ${REF_TAG}"
    else
        echo "Local or PR run: expected tag is ${EXPECTED_TAG} (skipping tag check)"
    fi
else
    echo "Local or PR run: expected tag is ${EXPECTED_TAG} (skipping tag check)"
fi

# ------------------------------------------------------------------
# Ensure the vendored framework is present.
# ------------------------------------------------------------------
FRAMEWORK="${REPO_ROOT}/Vendor/RNPFramework.xcframework"
if [[ ! -d "${FRAMEWORK}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "DRY-RUN: vendored framework missing; would run scripts/build-rnp-framework.sh"
    else
        echo "Vendored framework missing; building it now..."
        "${REPO_ROOT}/scripts/build-rnp-framework.sh"
    fi
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "DRY-RUN: would archive scheme '${SCHEME}' configuration '${CONFIG}' to ${ARCHIVE_PATH}"
    echo "DRY-RUN: would export archive to ${EXPORT_PATH} using Config/ExportDirect.plist"
    echo "DRY-RUN: would verify code signature and linked libraries"
    echo "DRY-RUN: would create DMG ${DIST_DIR}/RNP-${MARKETING_VERSION}.dmg"
    if [[ -n "${ASC_API_KEY_P8}" && -n "${ASC_API_KEY_ID}" && -n "${ASC_ISSUER_ID}" ]]; then
        echo "DRY-RUN: would submit ${DIST_DIR}/RNP-${MARKETING_VERSION}.dmg for notarization and staple it"
    else
        echo "DRY-RUN: ASC secrets not set; would skip notarization"
    fi
    echo "DRY-RUN: complete"
    exit 0
fi

# ------------------------------------------------------------------
# Archive and export.
# ------------------------------------------------------------------
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"

# The pbxproj already has CODE_SIGN_STYLE=Manual, CODE_SIGN_IDENTITY,
# and PROVISIONING_PROFILE_SPECIFIER set for the Direct config.
# Don't override at command line — it caused conflicts on CI
# (DVTPortal session validation, per-target override confusion).

xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    archive \
    -archivePath "${ARCHIVE_PATH}" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application"

# Generate the export options plist with the real team ID substituted in.
# Static $(TEAM_ID) in ExportDirect.plist is not resolved by -exportArchive
# and a literal placeholder triggers a segfault inside disttool/xcodebuild.
EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions.plist"
cat > "${EXPORT_OPTIONS_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.rnpgp.RNPForMail</key>
        <string>RNP for Mail Direct</string>
        <key>com.rnpgp.RNPForMail.MailExtension</key>
        <string>RNP for Mail Extension Direct</string>
    </dict>
</dict>
</plist>
PLIST

xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

APP_BUNDLE="$(find "${EXPORT_PATH}" -name 'RNP.app' -maxdepth 1 | head -n1)"
if [[ -z "${APP_BUNDLE}" ]]; then
    echo "Could not find exported .app bundle" >&2
    exit 1
fi
APP_NAME="$(basename "${APP_BUNDLE}")"

# ------------------------------------------------------------------
# Re-sign with Hardened Runtime version 14.0.
#
# Xcode 16.4 embeds Runtime Version=15.5.0 (the macOS SDK it was built
# against) into every Mach-O binary's code signature. macOS 14.0–14.3
# pluginkit rejects Mail extensions whose runtime version exceeds the
# system's macOS version, so the .appex fails to register with
# "SecStaticCodeCreateWithPath failed -67028" / "errSecCSReqFailed
# -67062" in Console. Fixed in macOS 14.4+, but we want to support
# 14.0–14.3 users too.
#
# `codesign --runtime-version 14.0` re-stamps the runtime version
# without touching anything else (entitlements, provisioning profile,
# CDHash algorithm all preserved via --preserve-metadata). The result
# is a binary that macOS 14.x pluginkit accepts.
# ------------------------------------------------------------------
echo "=== Re-signing with Hardened Runtime version 14.0 ==="
for bundle in \
    "${APP_BUNDLE}" \
    "${APP_BUNDLE}/Contents/Frameworks/RNPFramework.framework" \
    "${APP_BUNDLE}/Contents/PlugIns/MailPlugin.appex"; do
    [[ -e "${bundle}" ]] || continue
    codesign --force --options runtime --runtime-version 14.0 \
        --preserve-metadata=identifier,requirements,entitlements,flags,resource-rules \
        --sign "Developer ID Application" \
        "${bundle}"
done

# ------------------------------------------------------------------
# Verification.
# ------------------------------------------------------------------
echo "=== Code signature ==="
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" || true

echo "=== Runtime version (must be 14.0.0) ==="
codesign -d --verbose=4 "${APP_BUNDLE}/Contents/PlugIns/MailPlugin.appex" 2>&1 | grep -E "Runtime|VersionSDK" || true

echo "=== Linked libraries ==="
APPEX="${APP_BUNDLE}/Contents/PlugIns/MailPlugin.appex/Contents/MacOS/MailPlugin"
otool -L "${APPEX}"

if otool -L "${APPEX}" | grep -E '/usr/local|/opt/homebrew'; then
    echo "ERROR: appex links to absolute non-system paths" >&2
    exit 1
fi

# ------------------------------------------------------------------
# DMG.
# ------------------------------------------------------------------
DMG_NAME="RNP-${MARKETING_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
rm -f "${DMG_PATH}"

if [[ -x "$(command -v "${CREATE_DMG}")" ]]; then
    "${CREATE_DMG}" \
        --volname "RNP Installer" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --app-drop-link 450 185 \
        "${DMG_PATH}" \
        "${APP_BUNDLE}"
else
    echo "create-dmg not found; creating a raw compressed disk image"
    hdiutil create -srcfolder "${APP_BUNDLE}" -volname "RNP" -fs HFS+ \
        -format UDZO -o "${DMG_PATH}"
fi

# ------------------------------------------------------------------
# Notarization (only when ASC secrets are present).
# ------------------------------------------------------------------
if [[ -n "${ASC_API_KEY_P8}" && -n "${ASC_API_KEY_ID}" && -n "${ASC_ISSUER_ID}" ]]; then
    echo "=== Submitting for notarization ==="
    xcrun notarytool submit "${DMG_PATH}" \
        --key "${ASC_API_KEY_P8}" \
        --key-id "${ASC_API_KEY_ID}" \
        --issuer "${ASC_ISSUER_ID}" \
        --wait --timeout 30m

    echo "=== Stapling ==="
    xcrun stapler staple "${DMG_PATH}"

    echo "=== Gatekeeper assessment ==="
    spctl -a -t exec -vv "${APP_BUNDLE}"
    xcrun stapler validate "${DMG_PATH}"
else
    echo "ASC secrets not set; skipping notarization"
fi

# ------------------------------------------------------------------
# Checksums.
# ------------------------------------------------------------------
cd "${DIST_DIR}"
shasum -a 256 "${DMG_NAME}" > SHA256SUMS
cat SHA256SUMS

echo "=== Done: ${DMG_PATH} ==="
