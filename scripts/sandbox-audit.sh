#!/bin/bash
# scripts/sandbox-audit.sh
# Pre-submission sandbox/entitlement audit for the Mac App Store build.
#
# Run after a local build:
#   ./scripts/sandbox-audit.sh
#
# Override the build directory if you built a Release/AppStore archive:
#   BUILD_DIR=Swift-Rnp/Build/Products/Release ./scripts/sandbox-audit.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_BUILD_DIR="${REPO_ROOT}/Swift-Rnp/Build/Products/Debug"
APP_BUNDLE="${AUDIT_APP_PATH:-${BUILD_DIR:-${DEFAULT_BUILD_DIR}}/Ribose container.app}"
APP_BIN="${APP_BUNDLE}/Contents/MacOS/Ribose container"

# Discover the embedded Mail extension automatically.
APPEX_BUNDLE=""
if [[ -d "${APP_BUNDLE}/Contents/PlugIns" ]]; then
    APPEX_BUNDLE="$(find "${APP_BUNDLE}/Contents/PlugIns" -maxdepth 1 -name '*.appex' | head -n1)"
fi
if [[ -z "${APPEX_BUNDLE}" ]]; then
    APPEX_BUNDLE="${APP_BUNDLE}/Contents/PlugIns/MailPlugin.appex"
fi
APPEX_NAME="$(basename "${APPEX_BUNDLE}" .appex)"
APPEX_BIN="${APPEX_BUNDLE}/Contents/MacOS/${APPEX_NAME}"

ENTITLEMENTS_CONTAINER="${REPO_ROOT}/Swift-Rnp/MailExtensionsContainer/AppStore.entitlements"
ENTITLEMENTS_APPEX="${REPO_ROOT}/Swift-Rnp/MailPlugin/AppStore.entitlements"

FAIL=0

section() {
    echo
    echo "=== $* ==="
}

error() {
    echo "  [FAIL] $*" >&2
    FAIL=1
}

info() {
    echo "  [INFO] $*"
}

# ------------------------------------------------------------------
# 1. Bundle presence.
# ------------------------------------------------------------------
section "Bundle presence"
for path in "${APP_BUNDLE}" "${APP_BIN}" "${APPEX_BUNDLE}" "${APPEX_BIN}"; do
    if [[ ! -e "${path}" ]]; then
        error "Missing: ${path}"
    else
        info "Found: ${path}"
    fi
done

[[ -d "${APP_BUNDLE}" ]] || { echo "Cannot continue without app bundle" >&2; exit 1; }

# ------------------------------------------------------------------
# 2. File-access audit (informational + fail on obvious misuse).
# ------------------------------------------------------------------
section "FileManager usage (informational)"
grep -RIn --include='*.swift' "FileManager\.default" "${REPO_ROOT}/Sources" "${REPO_ROOT}/Swift-Rnp" || info "No FileManager.default usage found"

section "Temporary directory usage"
if grep -RIn --include='*.swift' "NSTemporaryDirectory()" "${REPO_ROOT}/Sources" "${REPO_ROOT}/Swift-Rnp"; then
    error "Found legacy NSTemporaryDirectory() usage"
else
    info "No legacy NSTemporaryDirectory() usage"
fi
grep -RIn --include='*.swift' "\.temporaryDirectory" "${REPO_ROOT}/Sources" "${REPO_ROOT}/Swift-Rnp" || info "No .temporaryDirectory usage found"

section "Hard-coded absolute paths"
if grep -RIn --include='*.swift' "/usr/local\|/opt/homebrew" "${REPO_ROOT}/Sources" "${REPO_ROOT}/Swift-Rnp"; then
    error "Found hard-coded /usr/local or /opt/homebrew paths in source"
else
    info "No hard-coded /usr/local or /opt/homebrew paths in source"
fi

# ------------------------------------------------------------------
# 3. Linked libraries: only system + bundle-resolved libraries allowed.
# ------------------------------------------------------------------
resolve_rpath_lib() {
    local lib="$1"
    local binary_dir="$2"
    local bundle_root="$3"

    local rel="${lib#@rpath/}"
    local candidates=(
        "${binary_dir}/../Frameworks/${rel}"
        "${bundle_root}/Contents/Frameworks/${rel}"
        "${APPEX_BUNDLE}/Contents/Frameworks/${rel}"
    )
    for candidate in "${candidates[@]}"; do
        candidate="$(cd "$(dirname "${candidate}")" 2>/dev/null && pwd -P)/$(basename "${candidate}")" || true
        if [[ -f "${candidate}" ]]; then
            return 0
        fi
    done
    return 1
}

check_linked_libs() {
    local binary="$1"
    local name="$2"
    local bundle_root="$3"
    local binary_dir
    binary_dir="$(dirname "${binary}")"

    section "Linked libraries: ${name}"
    local first=1
    while IFS= read -r line; do
        # Skip the header line that names the binary (one per architecture).
        if [[ ${first} -eq 1 ]]; then
            first=0
            continue
        fi
        [[ "${line}" == *"(architecture "* ]] && continue
        [[ -z "${line}" ]] && continue

        local lib
        lib="$(echo "${line}" | awk '{print $1}')"

        case "${lib}" in
            /usr/lib/*|/usr/lib/swift/*|/System/Library/Frameworks/*|/System/Library/PrivateFrameworks/*)
                info "system: ${lib}"
                ;;
            @rpath/RNPFramework.framework/*)
                info "bundle framework: ${lib}"
                ;;
            @rpath/*)
                if resolve_rpath_lib "${lib}" "${binary_dir}" "${bundle_root}"; then
                    info "bundle-resolved: ${lib}"
                else
                    error "Unresolved @rpath library (not inside bundle): ${lib}"
                fi
                ;;
            @executable_path/*|@loader_path/*)
                local resolved
                resolved="${binary_dir}/${lib#@*/}"
                resolved="$(cd "$(dirname "${resolved}")" 2>/dev/null && pwd -P)/$(basename "${resolved}")" || true
                if [[ -f "${resolved}" ]]; then
                    info "bundle-relative: ${lib} -> ${resolved}"
                else
                    error "Missing bundle-relative library: ${lib}"
                fi
                ;;
            /*)
                error "Non-system absolute library: ${lib}"
                ;;
            *)
                error "Unexpected library reference: ${lib}"
                ;;
        esac
    done < <(otool -L "${binary}")
}

check_linked_libs "${APP_BIN}" "container app" "${APP_BUNDLE}"
check_linked_libs "${APPEX_BIN}" "Mail extension" "${APP_BUNDLE}"

# ------------------------------------------------------------------
# 4. Entitlements reference the expected variables.
# ------------------------------------------------------------------
section "Entitlements"
for file in "${ENTITLEMENTS_CONTAINER}" "${ENTITLEMENTS_APPEX}"; do
    if [[ ! -f "${file}" ]]; then
        error "Missing entitlements file: ${file}"
        continue
    fi

    name="$(basename "$(dirname "${file}")")"
    if ! grep -q '<key>com.apple.security.app-sandbox</key>' "${file}"; then
        error "${name}: app-sandbox entitlement missing"
    fi
    if ! grep -q '$(RNPMAIL_APP_GROUP)' "${file}"; then
        error "${name}: application-groups does not reference \$(RNPMAIL_APP_GROUP)"
    fi
    if ! grep -q '$(RNPMAIL_KEYCHAIN_ACCESS_GROUP)' "${file}"; then
        error "${name}: keychain-access-groups does not reference \$(RNPMAIL_KEYCHAIN_ACCESS_GROUP)"
    fi
    info "${name}: entitlements look correct"
done

# ------------------------------------------------------------------
# 5. Privacy manifests present in both bundles.
# ------------------------------------------------------------------
section "PrivacyInfo.xcprivacy"
for path in \
    "${APP_BUNDLE}/Contents/Resources/PrivacyInfo.xcprivacy" \
    "${APPEX_BUNDLE}/Contents/Resources/PrivacyInfo.xcprivacy"; do
    if [[ -f "${path}" ]]; then
        info "Found: ${path}"
    else
        error "Missing: ${path}"
    fi
done

# ------------------------------------------------------------------
# Summary.
# ------------------------------------------------------------------
echo
if [[ ${FAIL} -ne 0 ]]; then
    echo "AUDIT FAILED — see errors above." >&2
    exit 1
else
    echo "AUDIT PASSED"
    exit 0
fi
