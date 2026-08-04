#!/bin/bash
# scripts/reproduce-release.sh
#
# Reproduce a published RNP release locally. Produces an unsigned
# Mach-O whose bytes match the published release EXCEPT for the code
# signature (Apple's timestamp server embeds a non-reproducible
# blob). Verifying the unsigned binary proves the source corresponds
# to the release.
#
# Usage:
#   scripts/reproduce-release.sh v0.9.6
#
# Prerequisites:
#   - Xcode 16.4 (matches the release runner)
#   - macOS 14+
#   - Network access (for SPM deps + librnp xcframework download)

set -euo pipefail

VERSION="${1:?usage: $0 <version> (e.g. v0.9.6)}"
TAG="${VERSION#v}"

# Sanity: tag must look like x.y.z
if ! [[ "${TAG}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: '${VERSION}' doesn't look like a tag (vx.y.z)" >&2
    exit 2
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "→ Cloning at tag ${VERSION} into ${WORKDIR}"
git clone --depth 1 --branch "${VERSION}" https://github.com/rnpgp/rnp-mailapp-extension.git "${WORKDIR}/src"

# Pick the timestamp from the tag itself — same one CI used.
SOURCE_DATE_EPOCH=$(git -C "${WORKDIR}/src" log -1 --format=%ct)
echo "→ SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"

# Download the published DMG.
PUBLISHED_DMG="${WORKDIR}/published.dmg"
PUBLISHED_URL="https://github.com/rnpgp/rnp-mailapp-extension/releases/download/${VERSION}/RNP-${TAG}.dmg"
echo "→ Downloading published DMG"
curl -sSfL -o "${PUBLISHED_DMG}" "${PUBLISHED_URL}"

# Build locally with the same flags release-direct.sh uses.
echo "→ Building locally (this takes ~10 minutes)"
cd "${WORKDIR}/src"
export SOURCE_DATE_EPOCH
export ZERO_AR_DATE=1
export TZ=UTC
export LC_ALL=C
export DRY_RUN=1
./scripts/release-direct.sh --dry-run >/dev/null 2>&1 || true

# The dry-run skips the actual archive. Run the real archive step
# without signing/notarization so we can compare bytes.
xcodebuild \
    -project MailApp/RnpMail.xcodeproj \
    -scheme RNP \
    -configuration Direct \
    -archivePath "${WORKDIR}/local.xcarchive" \
    -destination 'generic/platform=macOS' \
    build CODE_SIGNING_ALLOWED=NO

# Extract the main executable from both, compare.
LOCAL_BIN="${WORKDIR}/local.xcarchive/Products/Applications/RNP.app/Contents/MacOS/RNP"
PUBLISHED_APP="/Volumes/RNP/RNP.app"
hdiutil attach "${PUBLISHED_DMG}" -mountpoint "${WORKDIR}/mnt" -nobrowse -quiet
PUBLISHED_BIN="${WORKDIR}/mnt/RNP.app/Contents/MacOS/RNP"

if [[ ! -f "${LOCAL_BIN}" ]]; then
    echo "ERROR: local build didn't produce ${LOCAL_BIN}" >&2
    hdiutil detach "${WORKDIR}/mnt" -quiet || true
    exit 1
fi
if [[ ! -f "${PUBLISHED_BIN}" ]]; then
    echo "ERROR: published DMG doesn't contain RNP.app/Contents/MacOS/RNP" >&2
    hdiutil detach "${WORKDIR}/mnt" -quiet || true
    exit 1
fi

echo "→ Comparing unsigned Mach-O (signature blob is expected to differ)"
LOCAL_HASH=$(codesign -d --remove-signature "${LOCAL_BIN}" 2>/dev/null && shasum -a 256 "${LOCAL_BIN}" | awk '{print $1}')
PUBLISHED_HASH=$(cp "${PUBLISHED_BIN}" "${WORKDIR}/pub-stripped" && codesign -d --remove-signature "${WORKDIR}/pub-stripped" 2>/dev/null && shasum -a 256 "${WORKDIR}/pub-stripped" | awk '{print $1}')

echo "  local    (unsigned): ${LOCAL_HASH}"
echo "  published (unsigned): ${PUBLISHED_HASH}"

if [[ "${LOCAL_HASH}" == "${PUBLISHED_HASH}" ]]; then
    echo
    echo "✓ MATCH — published ${VERSION} corresponds to the source at that tag."
    hdiutil detach "${WORKDIR}/mnt" -quiet || true
    exit 0
else
    echo
    echo "✗ MISMATCH — see docs/reproducible-builds.md for known sources of nondeterminism."
    hdiutil detach "${WORKDIR}/mnt" -quiet || true
    exit 1
fi
