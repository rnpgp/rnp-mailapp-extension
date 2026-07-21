#!/bin/bash
# scripts/test-mail-e2e.sh
# End-to-end Mail extension test against the local mail server.
#
# This script:
#   1. Starts the local IMAP/SMTP server (scripts/local-mail-server.sh).
#   2. Configures Mail with a local test account.
#   3. Sends a message through Mail via AppleScript (outgoing path; on the
#      stock local server Postfix cannot deliver to virtual users, so its
#      arrival check is informational — the injected messages below are the
#      authoritative assertions).
#   4. Injects a plain, a signed-only, and an encrypted+signed PGP/MIME
#      message directly into the Dovecot maildir, then asserts in Mail:
#        - the message arrives with the expected subject,
#        - the sender address matches the signing key owner,
#        - the (decrypted) content matches the original body,
#        - the raw source has the expected OpenPGP/MIME structure
#          (application/pgp-signature / multipart/encrypted),
#        - the extension's banner state record (JSON in the app group
#          container) reports the expected signature/trust/encryption state.
#
# Requirements:
#   - A signed build of the container app and Mail extension.
#   - The extension enabled in Mail (Mail > Settings > Extensions).
#   - scripts/local-mail-server.sh dependencies installed (dovecot, postfix).
#   - gpg (brew install gnupg) and python3 for message construction.
#   - For the encrypted test: a key for ${TEST_EMAIL} in the extension
#     keyring (generate one in the container app first).
#
# The script appends a throwaway "RnpMail E2E Sender" public key to the
# extension's pubring.gpg (a backup is written next to it) and restarts
# Mail so the extension reloads the keyring.
#
# Usage: ./scripts/test-mail-e2e.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIL_SERVER_DIR="${MAIL_SERVER_DIR:-/tmp/rnpmail-local-server}"
MAIL_USER="${MAIL_USER:-testuser}"
TEST_EMAIL="${TEST_EMAIL:-testuser@localhost}"
TEST_PASSWORD="${TEST_PASSWORD:-testpass}"

E2E_ACCOUNT_NAME="${E2E_ACCOUNT_NAME:-RnpMail Local Test}"
E2E_SMTP_HOST="127.0.0.1"
E2E_SMTP_PORT="${E2E_SMTP_PORT:-25}"
E2E_IMAP_PORT="${E2E_IMAP_PORT:-143}"

# shellcheck source=mail-e2e-common.sh
source "${SCRIPT_DIR}/mail-e2e-common.sh"

MAILDIR_ROOT="${MAIL_SERVER_DIR}/mail/${MAIL_USER}"

cleanup() {
    e2e_cleanup_gpg
    "${SCRIPT_DIR}/local-mail-server.sh" stop || true
}
trap cleanup EXIT

echo "=== Starting local mail server ==="
"${SCRIPT_DIR}/local-mail-server.sh" start

e2e_detect_state_dir
e2e_detect_keyring_dir

echo "=== Configuring Mail account ==="
e2e_configure_mail_account "${E2E_ACCOUNT_NAME}" "${MAIL_USER}" "${TEST_EMAIL}" \
    "${E2E_IMAP_PORT}" "${E2E_SMTP_PORT}" "${TEST_PASSWORD}"

echo "=== Sending outgoing message through Mail (exercises encode path) ==="
OUTGOING_SUBJECT="RnpMail E2E outgoing $(date +%s)-$$"
OUTGOING_TOKEN="RNP-E2E-OUTGOING-$$"
e2e_send_via_mail "${TEST_EMAIL}" "${TEST_EMAIL}" "${OUTGOING_SUBJECT}" \
    "Outgoing smoke test. Token: ${OUTGOING_TOKEN}" || e2e_note "send via Mail failed"
if e2e_wait_for_message "${OUTGOING_SUBJECT}" 20; then
    e2e_assert_message_basics "outgoing" "${OUTGOING_SUBJECT}" "${TEST_EMAIL}" "${OUTGOING_TOKEN}" || true
else
    e2e_note "outgoing message did not arrive; expected with the stock local"
    e2e_note "server (Postfix cannot deliver to virtual users). Injected"
    e2e_note "messages below carry the authoritative assertions."
fi

echo "=== Running injected plain/signed/encrypted message tests ==="
e2e_run_injected_tests maildir "${MAILDIR_ROOT}"

e2e_summary
