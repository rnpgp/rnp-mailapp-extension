#!/bin/bash
# scripts/local-mail-server.sh
# Start a local IMAP + SMTP server for end-to-end Mail testing.
#
# This script uses Dovecot (IMAP) and Postfix (SMTP) installed via Homebrew.
# It configures them for localhost-only use with a single test account.
#
# Usage:
#   ./scripts/local-mail-server.sh start
#   ./scripts/local-mail-server.sh stop
#   ./scripts/local-mail-server.sh status
#
# Requirements:
#   brew install dovecot postfix
set -euo pipefail

COMMAND="${1:-}"
MAIL_SERVER_DIR="${MAIL_SERVER_DIR:-/tmp/rnpmail-local-server}"
MAIL_DOMAIN="${MAIL_DOMAIN:-localhost}"
MAIL_USER="${MAIL_USER:-testuser}"
MAIL_PASSWORD="${MAIL_PASSWORD:-testpass}"
MAIL_EMAIL="${MAIL_EMAIL:-testuser@localhost}"

if [[ -z "${COMMAND}" ]]; then
    echo "Usage: $0 {start|stop|status}" >&2
    exit 2
fi

check_deps() {
    for cmd in dovecot postfix; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "Missing dependency: ${cmd}. Install with: brew install ${cmd}" >&2
            exit 1
        fi
    done
}

write_dovecot_config() {
    local conf="${MAIL_SERVER_DIR}/dovecot.conf"
    mkdir -p "${MAIL_SERVER_DIR}/mail"
    cat > "${conf}" <<EOF
protocols = imap
listen = 127.0.0.1
ssl = no
disable_plaintext_auth = no
mail_location = maildir:${MAIL_SERVER_DIR}/mail/%u
auth_mechanisms = plain login
userdb {
    driver = passwd-file
    args = ${MAIL_SERVER_DIR}/users
}
passdb {
    driver = passwd-file
    args = ${MAIL_SERVER_DIR}/users
}
EOF
    cat > "${MAIL_SERVER_DIR}/users" <<EOF
${MAIL_USER}:{PLAIN}${MAIL_PASSWORD}::${MAIL_SERVER_DIR}/mail/${MAIL_USER}::userdb_mail
EOF
}

write_postfix_config() {
    local conf="${MAIL_SERVER_DIR}/postfix-main.cf"
    cat > "${conf}" <<EOF
myhostname = ${MAIL_DOMAIN}
mydomain = ${MAIL_DOMAIN}
myorigin = \$mydomain
inet_interfaces = 127.0.0.1
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
relayhost =
mynetworks = 127.0.0.0/8
mailbox_command =
home_mailbox = Maildir/
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
EOF
}

start() {
    check_deps
    mkdir -p "${MAIL_SERVER_DIR}"
    write_dovecot_config
    write_postfix_config

    echo "Starting Dovecot on 127.0.0.1:143..."
    dovecot -c "${MAIL_SERVER_DIR}/dovecot.conf"

    echo "Starting Postfix on 127.0.0.1:25..."
    postfix -c "${MAIL_SERVER_DIR}" start

    echo "Local mail server started."
    echo "IMAP: 127.0.0.1:143, SMTP: 127.0.0.1:25"
    echo "Account: ${MAIL_EMAIL} / ${MAIL_PASSWORD}"
}

stop() {
    echo "Stopping Dovecot..."
    dovecot -c "${MAIL_SERVER_DIR}/dovecot.conf" stop 2>/dev/null || true
    echo "Stopping Postfix..."
    postfix -c "${MAIL_SERVER_DIR}" stop 2>/dev/null || true
    echo "Stopped."
}

status() {
    if pgrep -f "dovecot.*${MAIL_SERVER_DIR}" >/dev/null; then
        echo "Dovecot: running"
    else
        echo "Dovecot: stopped"
    fi
    if pgrep -f "postfix.*${MAIL_SERVER_DIR}" >/dev/null; then
        echo "Postfix: running"
    else
        echo "Postfix: stopped"
    fi
}

case "${COMMAND}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "Unknown command: ${COMMAND}" >&2; exit 2 ;;
esac
