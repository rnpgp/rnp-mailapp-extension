#!/bin/bash
# scripts/ci-release-dry-run.sh
# Validate the release pipeline end-to-end without any Apple credentials.
#
# This script:
#   1. Builds the container app and Mail extension unsigned (CI only —
#      release-direct.yml handles signing via Apple-Actions/import-codesign-certs).
#   2. Runs scripts/sandbox-audit.sh against the unsigned build.
#   3. Runs scripts/release-direct.sh --dry-run.
#   4. Runs scripts/release-appstore.sh --dry-run.
#
# Usage: ./scripts/ci-release-dry-run.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT="${REPO_ROOT}/Swift-Rnp/Swift-Rnp.xcodeproj"
BUILD_DIR="${REPO_ROOT}/Swift-Rnp/Build"

echo "=== Building unsigned ==="
PKG_CONFIG_PATH="${REPO_ROOT}/Vendor/pkgconfig" \
xcodebuild \
    -project "${PROJECT}" \
    -scheme RNP \
    -configuration Direct \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    build \
    CODE_SIGNING_ALLOWED=NO

echo "=== Running sandbox audit ==="
AUDIT_APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/Direct/RNP.app" \
    "${SCRIPT_DIR}/sandbox-audit.sh"

echo "=== Release direct dry-run ==="
"${SCRIPT_DIR}/release-direct.sh" --dry-run

echo "=== Release App Store dry-run ==="
"${SCRIPT_DIR}/release-appstore.sh" --dry-run

echo "=== CI release dry-run complete ==="
