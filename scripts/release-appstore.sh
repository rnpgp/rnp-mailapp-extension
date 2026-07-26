#!/bin/bash
# scripts/release-appstore.sh
# Build, sign, and upload a Mac App Store release of RNP.
#
# Environment variables (all optional for local unsigned dry-runs):
#   DEVELOPMENT_TEAM       Apple Team ID
#   SIGNING_IDENTITY       Optional signing identity override
#   ASC_API_KEY_P8         Path to App Store Connect API .p8 file
#   ASC_API_KEY_ID         App Store Connect API Key ID
#   ASC_ISSUER_ID          App Store Connect Issuer ID
#   BUILD_NUMBER           CI run number to set as CURRENT_PROJECT_VERSION
#   TAG                    Git tag (e.g. v1.2.3) to validate against MARKETING_VERSION
#   RNP_REF                rnp version to vendor (default: v0.18.1)
#   SKIP_UPLOAD            If set, build and export but do not upload
#   UPLOAD_ONLY            If set, upload a previously exported archive without rebuilding

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

PROJECT="${REPO_ROOT}/Swift-Rnp/Swift-Rnp.xcodeproj"
SCHEME="RNP"
CONFIG="AppStore"
BUILD_DIR="${REPO_ROOT}/Swift-Rnp/Build"
ARCHIVE_PATH="${BUILD_DIR}/RNP-AppStore.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export-AppStore"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
ASC_API_KEY_P8="${ASC_API_KEY_P8:-}"
ASC_API_KEY_ID="${ASC_API_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
TAG="${TAG:-${GITHUB_REF_NAME:-}}"
RNP_REF="${RNP_REF:-v0.18.1}"
SKIP_UPLOAD="${SKIP_UPLOAD:-}"
UPLOAD_ONLY="${UPLOAD_ONLY:-}"

mkdir -p "${BUILD_DIR}"

# ------------------------------------------------------------------
# Helpers.
# ------------------------------------------------------------------
has_asc_secrets() {
    [[ -n "${ASC_API_KEY_P8}" && -n "${ASC_API_KEY_ID}" && -n "${ASC_ISSUER_ID}" ]]
}

build_auth_args() {
    if has_asc_secrets; then
        AUTH_ARGS=(
            -allowProvisioningUpdates
            -authenticationKeyPath "${ASC_API_KEY_P8}"
            -authenticationKeyID "${ASC_API_KEY_ID}"
            -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
        )
    else
        AUTH_ARGS=()
    fi
}

# ------------------------------------------------------------------
# Upload-only path: no build, just upload the existing archive/export.
# ------------------------------------------------------------------
if [[ -n "${UPLOAD_ONLY}" ]]; then
    build_auth_args
    if [[ ${#AUTH_ARGS[@]} -eq 0 ]]; then
        echo "ASC secrets not set; cannot upload" >&2
        exit 1
    fi

    EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions-AppStore.plist"
    if [[ ! -f "${EXPORT_OPTIONS_PLIST}" ]]; then
        echo "Missing export options plist: ${EXPORT_OPTIONS_PLIST}" >&2
        echo "Run a build/export pass first (without UPLOAD_ONLY)." >&2
        exit 1
    fi

    echo "=== Uploading to App Store Connect ==="
    xcodebuild \
        -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
        -uploadApp \
        "${AUTH_ARGS[@]}"

    echo "=== Done ==="
    exit 0
fi

# ------------------------------------------------------------------
# Version handling.
# ------------------------------------------------------------------
VERSION_FILE="${REPO_ROOT}/Swift-Rnp/Config/Version.xcconfig"
if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "Missing version file: ${VERSION_FILE}" >&2
    exit 1
fi

VERSION_BACKUP="${VERSION_FILE}.bak"
RESTORE_BACKUP=0

restore_version_file() {
    if [[ ${RESTORE_BACKUP} -eq 1 && -f "${VERSION_BACKUP}" ]]; then
        mv "${VERSION_BACKUP}" "${VERSION_FILE}"
        echo "Restored ${VERSION_FILE}"
    fi
}
trap restore_version_file EXIT

# Auto-increment CURRENT_PROJECT_VERSION from the CI run number. This is only
# persisted for the current archive; the repository is not rewritten.
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    cp "${VERSION_FILE}" "${VERSION_BACKUP}"
    RESTORE_BACKUP=1
    sed -i.bak "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/" "${VERSION_FILE}"
    echo "Set CURRENT_PROJECT_VERSION to ${BUILD_NUMBER}"
fi

MARKETING_VERSION="$(grep 'MARKETING_VERSION' "${VERSION_FILE}" | awk -F'= ' '{print $2}' | tr -d ' ')"
CURRENT_PROJECT_VERSION="$(grep 'CURRENT_PROJECT_VERSION' "${VERSION_FILE}" | awk -F'= ' '{print $2}' | tr -d ' ')"
EXPECTED_TAG="v${MARKETING_VERSION}"

if [[ -n "${TAG}" && ! "${TAG}" =~ ^[0-9]+/merge$ ]]; then
    if [[ "${TAG}" != "${EXPECTED_TAG}" ]]; then
        echo "Tag mismatch: expected ${EXPECTED_TAG}, got ${TAG}" >&2
        exit 1
    fi
    echo "Releasing ${EXPECTED_TAG} (build ${CURRENT_PROJECT_VERSION})"
else
    echo "Local run: expected tag is ${EXPECTED_TAG} (build ${CURRENT_PROJECT_VERSION}); continuing"
fi

# ------------------------------------------------------------------
# Ensure the vendored framework is present.
# ------------------------------------------------------------------
FRAMEWORK="${REPO_ROOT}/Vendor/RNPFramework.xcframework"
if [[ ! -d "${FRAMEWORK}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "DRY-RUN: vendored framework missing; would run RNP_REF=${RNP_REF} scripts/build-rnp-framework.sh"
    else
        echo "Vendored framework missing; building it now..."
        RNP_REF="${RNP_REF}" "${REPO_ROOT}/scripts/build-rnp-framework.sh"
    fi
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "DRY-RUN: would archive scheme '${SCHEME}' configuration '${CONFIG}' to ${ARCHIVE_PATH}"
    echo "DRY-RUN: would export archive to ${EXPORT_PATH} using Config/ExportAppStore.plist"
    if [[ -n "${SKIP_UPLOAD}" ]]; then
        echo "DRY-RUN: SKIP_UPLOAD set; would skip App Store Connect upload"
    elif has_asc_secrets; then
        echo "DRY-RUN: would upload exported .pkg to App Store Connect with ASC API credentials"
    else
        echo "DRY-RUN: ASC secrets not set; would skip upload"
    fi
    echo "DRY-RUN: complete"
    exit 0
fi

# ------------------------------------------------------------------
# Archive and export.
# ------------------------------------------------------------------
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"

build_auth_args

CODE_SIGN_ARGS=()
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    CODE_SIGN_ARGS+=(CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}")
fi

# Prepare a temporary export-options plist with the literal Team ID substituted.
EXPORT_OPTIONS_TEMPLATE="${REPO_ROOT}/Swift-Rnp/Config/ExportAppStore.plist"
EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions-AppStore.plist"
if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    sed "s/__TEAM_ID__/${DEVELOPMENT_TEAM}/g" "${EXPORT_OPTIONS_TEMPLATE}" > "${EXPORT_OPTIONS_PLIST}"
else
    sed "s/__TEAM_ID__//g" "${EXPORT_OPTIONS_TEMPLATE}" > "${EXPORT_OPTIONS_PLIST}"
fi

xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    archive \
    -archivePath "${ARCHIVE_PATH}" \
    "${AUTH_ARGS[@]}" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    "${CODE_SIGN_ARGS[@]}"

xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    "${AUTH_ARGS[@]}"

PKG_PATH="$(find "${EXPORT_PATH}" -maxdepth 1 -name '*.pkg' | head -n1)"
if [[ -z "${PKG_PATH}" ]]; then
    echo "Could not find exported .pkg" >&2
    exit 1
fi
echo "=== Exported package ==="
ls -lh "${PKG_PATH}"

# ------------------------------------------------------------------
# Upload to App Store Connect (only when ASC secrets are present).
# ------------------------------------------------------------------
if [[ -n "${SKIP_UPLOAD}" ]]; then
    echo "SKIP_UPLOAD set; skipping App Store Connect upload"
elif has_asc_secrets; then
    echo "=== Uploading to App Store Connect ==="
    xcodebuild \
        -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
        -uploadApp \
        "${AUTH_ARGS[@]}"
else
    echo "ASC secrets not set; skipping App Store Connect upload"
fi

# Discard the Version.xcconfig backup on a successful run.
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    rm -f "${VERSION_BACKUP}"
    RESTORE_BACKUP=0
fi

echo "=== Done: ${PKG_PATH} ==="
