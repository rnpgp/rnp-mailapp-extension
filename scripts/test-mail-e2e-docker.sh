#!/bin/bash
# scripts/test-mail-e2e-docker.sh
# End-to-end Mail extension test against a GreenMail Docker container.
#
# Same assertion suite as test-mail-e2e.sh, but messages are injected over
# SMTP into GreenMail instead of a local maildir:
#   - arrival with the expected subject,
#   - sender address matching the signing key owner,
#   - decrypted content matching the original body,
#   - raw source OpenPGP/MIME structure (application/pgp-signature /
#     multipart/encrypted),
#   - the extension's banner state record (JSON in the app group container).
#
# Requirements:
#   - GreenMail running on localhost (SMTP 3025, IMAP 3143). When it is not
#     reachable and docker is available, the script starts a
#     greenmail/standalone container automatically (GREENMAIL_AUTO_START=0
#     disables this).
#   - A signed build of the container app and Mail extension.
#   - The extension enabled in Mail (Mail > Settings > Extensions).
#   - gpg (brew install gnupg) and python3 for message construction.
#   - For the encrypted test: a key for ${TEST_EMAIL} in the extension
#     keyring (generate one in the container app first).
#
# Usage: ./scripts/test-mail-e2e-docker.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMTP_PORT="${GREENMAIL_SMTP_PORT:-3025}"
IMAP_PORT="${GREENMAIL_IMAP_PORT:-3143}"
TEST_EMAIL="${TEST_EMAIL:-test@localhost}"
TEST_PASSWORD="${TEST_PASSWORD:-test}"
TEST_USER="${TEST_USER:-test}"
GREENMAIL_AUTO_START="${GREENMAIL_AUTO_START:-1}"
GREENMAIL_IMAGE="${GREENMAIL_IMAGE:-greenmail/standalone:2.0.1}"
GREENMAIL_CONTAINER="${GREENMAIL_CONTAINER:-rnpmail-greenmail}"

E2E_ACCOUNT_NAME="${E2E_ACCOUNT_NAME:-RnpMail GreenMail Test}"
E2E_SMTP_HOST="127.0.0.1"
E2E_SMTP_PORT="${SMTP_PORT}"
E2E_IMAP_PORT="${IMAP_PORT}"

# shellcheck source=mail-e2e-common.sh
source "${SCRIPT_DIR}/mail-e2e-common.sh"

STARTED_CONTAINER=0

cleanup() {
    e2e_cleanup_gpg
    if [ "${STARTED_CONTAINER}" = "1" ]; then
        echo "=== Stopping GreenMail container ${GREENMAIL_CONTAINER} ==="
        docker stop "${GREENMAIL_CONTAINER}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

port_open() {
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
}

# GreenMail may accept TCP before its SMTP service answers; check the banner.
smtp_ready() {
    python3 - "$1" <<'PYEOF' >/dev/null 2>&1
import smtplib, sys
try:
    with smtplib.SMTP("127.0.0.1", int(sys.argv[1]), timeout=5) as smtp:
        smtp.noop()
except Exception:
    sys.exit(1)
PYEOF
}

echo "=== Checking GreenMail availability ==="
if ! port_open "${SMTP_PORT}"; then
    if [ "${GREENMAIL_AUTO_START}" = "1" ] && command -v docker >/dev/null 2>&1; then
        echo "GreenMail not reachable; starting ${GREENMAIL_IMAGE} as ${GREENMAIL_CONTAINER}..."
        docker rm -f "${GREENMAIL_CONTAINER}" >/dev/null 2>&1 || true
        docker run -d --name "${GREENMAIL_CONTAINER}" \
            -p "3025:3025" -p "3143:3143" "${GREENMAIL_IMAGE}" >/dev/null
        STARTED_CONTAINER=1
        for _ in $(seq 1 60); do
            smtp_ready "${SMTP_PORT}" && port_open "${IMAP_PORT}" && break
            sleep 2
        done
    fi
fi
if ! smtp_ready "${SMTP_PORT}"; then
    echo "ERROR: GreenMail SMTP (127.0.0.1:${SMTP_PORT}) is not reachable." >&2
    echo "Start GreenMail or set GREENMAIL_AUTO_START=1 with docker available." >&2
    exit 2
fi

e2e_detect_state_dir
e2e_detect_keyring_dir

echo "=== Configuring Mail account ==="
e2e_configure_mail_account "${E2E_ACCOUNT_NAME}" "${TEST_USER}" "${TEST_EMAIL}" \
    "${IMAP_PORT}" "${SMTP_PORT}" "${TEST_PASSWORD}"

# GreenMail auto-creates a user on first login; create it now so the
# outgoing and injected messages below cannot bounce.
echo "=== Ensuring GreenMail user ${TEST_EMAIL} exists ==="
e2e_imap_login 127.0.0.1 "${IMAP_PORT}" "${TEST_EMAIL}" "${TEST_PASSWORD}"

echo "=== Sending outgoing message through Mail (exercises encode path) ==="
OUTGOING_SUBJECT="RnpMail E2E outgoing $(date +%s)-$$"
OUTGOING_TOKEN="RNP-E2E-OUTGOING-$$"
e2e_send_via_mail "${TEST_EMAIL}" "${TEST_EMAIL}" "${OUTGOING_SUBJECT}" \
    "Outgoing smoke test. Token: ${OUTGOING_TOKEN}" || e2e_note "send via Mail failed"
# GreenMail accepts and stores any recipient, so arrival is asserted.
e2e_assert_message_basics "outgoing" "${OUTGOING_SUBJECT}" "${TEST_EMAIL}" "${OUTGOING_TOKEN}" || true

echo "=== Running injected plain/signed/encrypted message tests ==="
e2e_run_injected_tests smtp

e2e_summary
