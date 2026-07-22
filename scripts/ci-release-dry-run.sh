#!/bin/bash
# scripts/ci-release-dry-run.sh
# Validate the release pipeline end-to-end with a self-signed certificate,
# without any Apple credentials.
#
# This script:
#   1. Creates a temporary keychain and a self-signed code-signing certificate.
#   2. Builds the container app and Mail extension with that certificate.
#   3. Runs scripts/sandbox-audit.sh against the signed build.
#   4. Runs scripts/release-direct.sh --dry-run.
#   5. Runs scripts/release-appstore.sh --dry-run.
#
# Usage: ./scripts/ci-release-dry-run.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT="${REPO_ROOT}/Swift-Rnp/Swift-Rnp.xcodeproj"
BUILD_DIR="${REPO_ROOT}/Swift-Rnp/Build"

KEYCHAIN_PATH="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-release-dry-run.keychain-db"
KEYCHAIN_PASSWORD="ci-dry-run-password"
CERT_NAME="RNP CI Dry-Run"

cleanup() {
    security delete-keychain "${KEYCHAIN_PATH}" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Creating temporary keychain ==="
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security list-keychain -d user -s "${KEYCHAIN_PATH}"

echo "=== Generating self-signed certificate ==="
cat > "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run-cert.conf" <<EOF
[ req ]
default_bits        = 2048
default_md          = sha256
distinguished_name  = dn
x509_extensions     = v3_req
prompt              = no

[ dn ]
CN = ${CERT_NAME}

[ v3_req ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

openssl req -x509 -newkey rsa:2048 \
    -keyout "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run.key" \
    -out "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run.crt" \
    -days 1 -nodes \
    -config "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run-cert.conf"

openssl pkcs12 -export -legacy \
    -out "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run.p12" \
    -inkey "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run.key" \
    -in "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run.crt" \
    -password pass:"${KEYCHAIN_PASSWORD}"

security import "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-dry-run.p12" \
    -P "${KEYCHAIN_PASSWORD}" \
    -A -t cert -f pkcs12 -k "${KEYCHAIN_PATH}"

# Allow the self-signed cert for code signing in this keychain.
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}" >/dev/null 2>&1 || true

echo "=== Building unsigned ==="
PKG_CONFIG_PATH="${REPO_ROOT}/Vendor/pkgconfig" \
xcodebuild \
    -project "${PROJECT}" \
    -scheme RNP \
    -configuration Direct \
    build \
    CODE_SIGNING_ALLOWED=NO

echo "=== Signing with self-signed certificate ==="
APP_BUNDLE="${BUILD_DIR}/Products/Direct/RNP.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Built app not found at ${APP_BUNDLE}" >&2
    exit 1
fi
codesign --sign "${CERT_NAME}" --force --deep --keychain "${KEYCHAIN_PATH}" "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "=== Running sandbox audit ==="
AUDIT_APP_PATH="${BUILD_DIR}/Products/Direct/RNP.app" \
    "${SCRIPT_DIR}/sandbox-audit.sh"

echo "=== Release direct dry-run ==="
"${SCRIPT_DIR}/release-direct.sh" --dry-run

echo "=== Release App Store dry-run ==="
"${SCRIPT_DIR}/release-appstore.sh" --dry-run

echo "=== CI release dry-run complete ==="
