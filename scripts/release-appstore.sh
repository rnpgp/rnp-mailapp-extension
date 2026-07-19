#!/bin/bash
# scripts/release-appstore.sh
# Build, sign, and upload a Mac App Store release of RnpMail.
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT="${REPO_ROOT}/Swift-Rnp/Swift-Rnp.xcodeproj"
SCHEME="Ribose container"
CONFIG="AppStore"
BUILD_DIR="${REPO_ROOT}/Swift-Rnp/Build"
ARCHIVE_PATH="${BUILD_DIR}/RnpMail-AppStore.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export-AppStore"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
ASC_API_KEY_P8="${ASC_API_KEY_P8:-}"
ASC_API_KEY_ID="${ASC_API_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
TAG="${TAG:-${GITHUB_REF_NAME:-}}"

mkdir -p "${BUILD_DIR}"

# ------------------------------------------------------------------
# Version handling.
# ------------------------------------------------------------------
VERSION_FILE="${REPO_ROOT}/Swift-Rnp/Config/Version.xcconfig"
if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "Missing version file: ${VERSION_FILE}" >&2
    exit 1
fi

# Auto-increment CURRENT_PROJECT_VERSION from the CI run number. This is only
# persisted for the current archive; the repository is not rewritten.
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    sed -i.bak "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/" "${VERSION_FILE}"
    rm -f "${VERSION_FILE}.bak"
    echo "Set CURRENT_PROJECT_VERSION to ${BUILD_NUMBER}"
fi

MARKETING_VERSION="$(grep 'MARKETING_VERSION' "${VERSION_FILE}" | awk -F'= ' '{print $2}' | tr -d ' ')"
CURRENT_PROJECT_VERSION="$(grep 'CURRENT_PROJECT_VERSION' "${VERSION_FILE}" | awk -F'= ' '{print $2}' | tr -d ' ')"
EXPECTED_TAG="v${MARKETING_VERSION}"

if [[ -n "${TAG}" ]]; then
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
    echo "Vendored framework missing; building it now..."
    "${REPO_ROOT}/scripts/build-rnp-framework.sh"
fi

# ------------------------------------------------------------------
# Archive and export.
# ------------------------------------------------------------------
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"

AUTH_ARGS=()
if [[ -n "${ASC_API_KEY_P8}" && -n "${ASC_API_KEY_ID}" && -n "${ASC_ISSUER_ID}" ]]; then
    AUTH_ARGS=(
        -allowProvisioningUpdates
        -authenticationKeyPath "${ASC_API_KEY_P8}"
        -authenticationKeyID "${ASC_API_KEY_ID}"
        -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
    )
fi

CODE_SIGN_ARGS=()
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    CODE_SIGN_ARGS+=(CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}")
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
    -exportOptionsPlist "${REPO_ROOT}/Swift-Rnp/Config/ExportAppStore.plist" \
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
if [[ -n "${ASC_API_KEY_P8}" && -n "${ASC_API_KEY_ID}" && -n "${ASC_ISSUER_ID}" ]]; then
    echo "=== Uploading to App Store Connect ==="
    xcrun altool --upload-package "${PKG_PATH}" \
        --type macos \
        --apiKey "${ASC_API_KEY_ID}" \
        --apiIssuer "${ASC_ISSUER_ID}" \
        --verbose
else
    echo "ASC secrets not set; skipping App Store Connect upload"
fi

echo "=== Done: ${PKG_PATH} ==="
