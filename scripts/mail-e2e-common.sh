#!/bin/bash
# scripts/mail-e2e-common.sh
# Shared helpers for the Mail end-to-end test scripts
# (test-mail-e2e.sh and test-mail-e2e-docker.sh). Not meant to be run
# directly; source it from one of those scripts after setting:
#
#   E2E_ACCOUNT_NAME   Mail account display name to create/use.
#   E2E_SMTP_HOST      SMTP host used for injected messages and Mail.
#   E2E_SMTP_PORT      SMTP port.
#   E2E_IMAP_PORT      IMAP port (account configuration only).
#
# Optional environment overrides:
#   TEST_EMAIL            recipient/account address (default per script).
#   E2E_SENDER_EMAIL      address of the script-generated signing key
#                         (default: e2e-sender@localhost). Kept distinct from
#                         TEST_EMAIL so gpg recipient resolution is unambiguous.
#   E2E_ARRIVAL_TIMEOUT   seconds to wait for a message to arrive (default 60).
#   E2E_STATE_TIMEOUT     seconds to wait for a banner state record (default 20).
#   RNPMAIL_STATE_DIR     override the extension state directory.
#   RNPMAIL_KEYRING_DIR   override the extension keyring directory.
#   REQUIRE_BANNER        when "1", missing banner state records are a hard
#                         failure instead of a SKIP (for CI runners where the
#                         extension is known to be enabled).

# ---------------------------------------------------------------------------
# Result accounting
# ---------------------------------------------------------------------------

E2E_PASS="${E2E_PASS:-0}"
E2E_FAIL="${E2E_FAIL:-0}"
E2E_SKIP="${E2E_SKIP:-0}"

e2e_pass() { E2E_PASS=$((E2E_PASS + 1)); echo "PASS: $*"; }
e2e_fail() { E2E_FAIL=$((E2E_FAIL + 1)); echo "FAIL: $*"; }
e2e_skip() { E2E_SKIP=$((E2E_SKIP + 1)); echo "SKIP: $*"; }
e2e_note() { echo "NOTE: $*"; }

e2e_summary() {
    echo
    echo "=== E2E summary: ${E2E_PASS} passed, ${E2E_FAIL} failed, ${E2E_SKIP} skipped ==="
    [ "${E2E_FAIL}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Configuration / environment detection
# ---------------------------------------------------------------------------

E2E_SENDER_EMAIL="${E2E_SENDER_EMAIL:-e2e-sender@localhost}"
E2E_SENDER_UID="RnpMail E2E Sender <${E2E_SENDER_EMAIL}>"
E2E_ARRIVAL_TIMEOUT="${E2E_ARRIVAL_TIMEOUT:-60}"
E2E_STATE_TIMEOUT="${E2E_STATE_TIMEOUT:-20}"
E2E_GNUPGHOME=""
E2E_SENDER_FPR=""
E2E_USER_FPR=""

e2e_group_container() {
    printf '%s/Library/Group Containers/group.com.rnpgp.RnpMail' "${HOME}"
}

# Sets E2E_STATE_DIR and E2E_BANNER_REQUIRED.
e2e_detect_state_dir() {
    local group_dir fallback_dir
    group_dir="$(e2e_group_container)/ExtensionState"
    fallback_dir="${HOME}/Library/Application Support/RNP Mail Extension/ExtensionState"
    if [ -n "${RNPMAIL_STATE_DIR:-}" ]; then
        E2E_STATE_DIR="${RNPMAIL_STATE_DIR}"
    elif [ -d "${group_dir}" ]; then
        E2E_STATE_DIR="${group_dir}"
    elif [ -d "${fallback_dir}" ]; then
        E2E_STATE_DIR="${fallback_dir}"
    else
        E2E_STATE_DIR="${group_dir}"
    fi
    # When the state directory already exists the extension has written
    # records before, so a missing record means something is broken.
    if [ -d "${E2E_STATE_DIR}" ] || [ "${REQUIRE_BANNER:-0}" = "1" ]; then
        E2E_BANNER_REQUIRED=1
    else
        E2E_BANNER_REQUIRED=0
    fi
    e2e_note "extension state dir: ${E2E_STATE_DIR} (banner assertions $([ "${E2E_BANNER_REQUIRED}" = 1 ] && echo required || echo best-effort))"
}

# Sets E2E_KEYRING_DIR.
e2e_detect_keyring_dir() {
    local group_dir fallback_dir
    group_dir="$(e2e_group_container)/Keyrings"
    fallback_dir="${HOME}/Library/Application Support/RNP Mail Extension"
    if [ -n "${RNPMAIL_KEYRING_DIR:-}" ]; then
        E2E_KEYRING_DIR="${RNPMAIL_KEYRING_DIR}"
    elif [ -d "${group_dir}" ]; then
        E2E_KEYRING_DIR="${group_dir}"
    else
        E2E_KEYRING_DIR="${fallback_dir}"
    fi
    e2e_note "extension keyring dir: ${E2E_KEYRING_DIR}"
}

e2e_have_gpg() {
    command -v gpg >/dev/null 2>&1
}

e2e_have_python3() {
    command -v python3 >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# AppleScript helpers (Mail.app)
# ---------------------------------------------------------------------------

# configure the IMAP/SMTP account in Mail when missing.
e2e_configure_mail_account() {
    # e2e_configure_mail_account <account-name> <user> <email> <imap-port> <smtp-port> <password>
    osascript - "$@" <<'APPLESCRIPT'
on run argv
    set accountName to item 1 of argv
    set accountUser to item 2 of argv
    set accountEmail to item 3 of argv
    set imapPort to (item 4 of argv) as integer
    set smtpPort to (item 5 of argv) as integer
    set accountPassword to item 6 of argv
    tell application "Mail"
        set existingAccounts to name of every account
        if existingAccounts does not contain accountName then
            set newAccount to make new account with properties {name:accountName, user name:accountUser, email addresses:{accountEmail}, full name:"RnpMail E2E"}
            tell newAccount
                set server settings of incoming server to {server name:"127.0.0.1", port:imapPort, use ssl:false, authentication:password}
                set password of incoming server to accountPassword
                set server settings of outgoing server to {server name:"127.0.0.1", port:smtpPort, use ssl:false, authentication:password}
                set password of outgoing server to accountPassword
            end tell
        end if
    end tell
end run
APPLESCRIPT
}

# Prints one property ("subject"|"sender"|"content"|"source") of the first
# message with the exact subject in the test account's INBOX, or
# "__NOT_FOUND__" / "__ERROR__".
e2e_message_property() {
    # e2e_message_property <subject> <property>
    osascript - "${E2E_ACCOUNT_NAME}" "$1" "$2" <<'APPLESCRIPT'
on run argv
    set accountName to item 1 of argv
    set targetSubject to item 2 of argv
    set prop to item 3 of argv
    tell application "Mail"
        try
            set acct to account accountName
            set msgs to {}
            try
                set msgs to messages of mailbox "INBOX" of acct
            on error
                set msgs to messages of inbox
            end try
            repeat with msg in msgs
                if subject of msg is targetSubject then
                    if prop is "subject" then return subject of msg
                    if prop is "sender" then return sender of msg
                    if prop is "content" then return content of msg
                    if prop is "source" then return source of msg
                end if
            end repeat
        on error errMsg
            return "__ERROR__: " & errMsg
        end try
    end tell
    return "__NOT_FOUND__"
end run
APPLESCRIPT
}

# Sends a message from the test account via Mail (exercises the extension's
# outgoing encode path when signing/encryption is toggled in the compose UI).
e2e_send_via_mail() {
    # e2e_send_via_mail <from> <to> <subject> <body>
    osascript - "$@" <<'APPLESCRIPT'
on run argv
    set fromAddress to item 1 of argv
    set toAddress to item 2 of argv
    set theSubject to item 3 of argv
    set theBody to item 4 of argv
    tell application "Mail"
        set newMessage to make new outgoing message with properties {subject:theSubject, content:theBody}
        tell newMessage
            set sender to fromAddress
            set to recipient to toAddress
            set visible to true
        end tell
        send newMessage
    end tell
end run
APPLESCRIPT
}

# Opens the message in its own window, which makes Mail run the extension's
# decode path (and therefore the banner state recording).
e2e_open_message() {
    # e2e_open_message <subject>
    osascript - "${E2E_ACCOUNT_NAME}" "$1" <<'APPLESCRIPT'
on run argv
    set accountName to item 1 of argv
    set targetSubject to item 2 of argv
    tell application "Mail"
        try
            set acct to account accountName
            set msgs to {}
            try
                set msgs to messages of mailbox "INBOX" of acct
            on error
                set msgs to messages of inbox
            end try
            repeat with msg in msgs
                if subject of msg is targetSubject then
                    open msg
                    return "OK"
                end if
            end repeat
        on error errMsg
            return "__ERROR__: " & errMsg
        end try
    end tell
    return "__NOT_FOUND__"
end run
APPLESCRIPT
}

e2e_check_for_new_mail() {
    osascript -e 'tell application "Mail" to check for new mail' >/dev/null 2>&1 || true
}

# Waits until a message with the exact subject exists in the test account.
e2e_wait_for_message() {
    # e2e_wait_for_message <subject> <timeout-seconds>
    local subject="$1" timeout="$2"
    local deadline=$((SECONDS + timeout))
    e2e_check_for_new_mail
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if [ "$(e2e_message_property "${subject}" subject)" = "${subject}" ]; then
            return 0
        fi
        sleep 3
        e2e_check_for_new_mail
    done
    return 1
}

e2e_restart_mail() {
    e2e_note "restarting Mail so the extension reloads the keyring"
    osascript -e 'tell application "Mail" to quit' >/dev/null 2>&1 || true
    sleep 3
    open -a Mail
    sleep 8
}

# ---------------------------------------------------------------------------
# Message assertions
# ---------------------------------------------------------------------------

# Arrival + subject + sender + content assertions for one message.
# Returns 0 when every assertion passed.
e2e_assert_message_basics() {
    # e2e_assert_message_basics <label> <subject> <sender-substring> <content-token>
    local label="$1" subject="$2" want_sender="$3" want_token="$4"
    local ok=0
    if e2e_wait_for_message "${subject}" "${E2E_ARRIVAL_TIMEOUT}"; then
        e2e_pass "${label}: message arrived with expected subject"
    else
        e2e_fail "${label}: message '${subject}' did not arrive within ${E2E_ARRIVAL_TIMEOUT}s"
        return 1
    fi

    local sender
    sender="$(e2e_message_property "${subject}" sender)"
    case "${sender}" in
        *"${want_sender}"*) e2e_pass "${label}: sender matches key owner (${want_sender})" ;;
        *) e2e_fail "${label}: sender '${sender}' does not contain '${want_sender}'"; ok=1 ;;
    esac

    local content
    content="$(e2e_message_property "${subject}" content)"
    case "${content}" in
        *"${want_token}"*) e2e_pass "${label}: content matches expected body" ;;
        *) e2e_fail "${label}: content does not contain expected token '${want_token}'"; ok=1 ;;
    esac
    return "${ok}"
}

# Raw-source assertions: which OpenPGP/MIME structure the stored message has.
# <expect> is one of: signed | encrypted | plain.
e2e_assert_message_source() {
    # e2e_assert_message_source <label> <subject> <expect>
    local label="$1" subject="$2" expect="$3"
    local source
    source="$(e2e_message_property "${subject}" source)"
    case "${expect}" in
        signed)
            case "${source}" in
                *"multipart/signed"*"application/pgp-signature"*)
                    e2e_pass "${label}: source is multipart/signed with application/pgp-signature" ;;
                *)
                    e2e_fail "${label}: source lacks multipart/signed + application/pgp-signature"
                    return 1 ;;
            esac
            ;;
        encrypted)
            case "${source}" in
                *"multipart/encrypted"*"application/pgp-encrypted"*)
                    e2e_pass "${label}: source is multipart/encrypted with application/pgp-encrypted" ;;
                *)
                    e2e_fail "${label}: source lacks multipart/encrypted + application/pgp-encrypted"
                    return 1 ;;
            esac
            ;;
        plain)
            case "${source}" in
                *"application/pgp-signature"*|*"multipart/encrypted"*)
                    e2e_fail "${label}: source unexpectedly contains OpenPGP/MIME parts"
                    return 1 ;;
                *)
                    e2e_pass "${label}: source contains no OpenPGP/MIME parts (plain)" ;;
            esac
            ;;
        *)
            e2e_fail "${label}: unknown source expectation '${expect}'"
            return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Banner state record assertions (extension state file)
# ---------------------------------------------------------------------------

# Prints the per-message state file path for an RFC 822 Message-ID.
# Must stay in sync with SecurityStateRecorder.sanitizedMessageID.
e2e_state_file_for() {
    # e2e_state_file_for <message-id>
    local sanitized
    sanitized="$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9' '-')"
    printf '%s/messages/%s.json' "${E2E_STATE_DIR}" "${sanitized}"
}

e2e_wait_for_file() {
    # e2e_wait_for_file <path> <timeout-seconds>
    local deadline=$((SECONDS + $2))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        [ -f "$1" ] && return 0
        sleep 2
    done
    [ -f "$1" ]
}

# Prints one value from a state record JSON via python3.
e2e_state_value() {
    # e2e_state_value <file> <python-expression-on-d>
    python3 - "$1" "$2" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
try:
    print(eval(sys.argv[2]))  # noqa: S307 - expression is script-controlled
except Exception as exc:  # missing key, no signers, ...
    print("__ERROR__: %s" % exc)
PYEOF
}

# Asserts the banner state record for a message: signature status, trust
# state and encryption flag, plus that the signer matches the sender.
e2e_assert_banner_state() {
    # e2e_assert_banner_state <label> <message-id> <expected-status> <expect-encrypted true|false> <sender-email>
    local label="$1" msgid="$2" want_status="$3" want_enc="$4" sender_email="$5"
    local file
    file="$(e2e_state_file_for "${msgid}")"
    if ! e2e_wait_for_file "${file}" "${E2E_STATE_TIMEOUT}"; then
        if [ "${E2E_BANNER_REQUIRED}" = "1" ]; then
            e2e_fail "${label}: no banner state record at ${file} within ${E2E_STATE_TIMEOUT}s"
            return 1
        fi
        e2e_skip "${label}: banner state (extension wrote no record; old build or extension disabled)"
        return 0
    fi

    local ok=0 status trust is_enc label0
    status="$(e2e_state_value "${file}" "d['signers'][0]['status']")"
    if [ "${status}" = "${want_status}" ]; then
        e2e_pass "${label}: banner signature status is '${want_status}'"
    else
        e2e_fail "${label}: banner signature status is '${status}', expected '${want_status}'"
        ok=1
    fi

    trust="$(e2e_state_value "${file}" "d['signers'][0].get('trust')")"
    case "${trust}" in
        unverified|verified|problem)
            e2e_pass "${label}: banner signer trust recorded ('${trust}')" ;;
        *)
            e2e_fail "${label}: unexpected signer trust '${trust}'"
            ok=1 ;;
    esac

    label0="$(e2e_state_value "${file}" "d['signers'][0]['label']")"
    case "${label0}" in
        *"${sender_email}"*) e2e_pass "${label}: banner signer matches sender (${sender_email})" ;;
        *) e2e_fail "${label}: banner signer '${label0}' does not match sender '${sender_email}'"; ok=1 ;;
    esac

    is_enc="$(e2e_state_value "${file}" "d['isEncrypted']")"
    if [ "${is_enc}" = "${want_enc}" ]; then
        e2e_pass "${label}: banner isEncrypted is ${want_enc}"
    else
        e2e_fail "${label}: banner isEncrypted is '${is_enc}', expected '${want_enc}'"
        ok=1
    fi
    return "${ok}"
}

# ---------------------------------------------------------------------------
# OpenPGP message construction (gpg)
# ---------------------------------------------------------------------------

# Creates a throwaway gpg home with a signing-only sender key.
# Note: gpg in strict RFC 4880 mode defaults to SHA-1 for both the key
# self-signature and document signatures; librnp rejects SHA-1 signatures
# under its default security profile, so SHA-256 is forced everywhere.
e2e_setup_gpg() {
    E2E_GNUPGHOME="$(mktemp -d /tmp/rnpmail-e2e-gpg.XXXXXX)"
    chmod 700 "${E2E_GNUPGHOME}"
    gpg --batch --pinentry-mode loopback --passphrase "" --rfc4880 \
        --cert-digest-algo SHA256 \
        --homedir "${E2E_GNUPGHOME}" \
        --quick-generate-key "${E2E_SENDER_UID}" rsa2048 sign never >/dev/null 2>&1
    E2E_SENDER_FPR="$(gpg --batch --homedir "${E2E_GNUPGHOME}" --with-colons \
        --list-keys "${E2E_SENDER_UID}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
    if [ -z "${E2E_SENDER_FPR}" ]; then
        echo "ERROR: failed to create the E2E sender key with gpg" >&2
        return 1
    fi
    e2e_note "E2E sender key: ${E2E_SENDER_FPR} (throwaway, in ${E2E_GNUPGHOME})"
}

e2e_cleanup_gpg() {
    if [ -n "${E2E_GNUPGHOME}" ] && [ -d "${E2E_GNUPGHOME}" ]; then
        rm -rf "${E2E_GNUPGHOME}"
        E2E_GNUPGHOME=""
    fi
}

# Appends the sender public key (binary OpenPGP packets, i.e. GPG keystore
# format) to the extension's pubring.gpg so it can verify signatures.
e2e_import_sender_pubkey() {
    local pubring="${E2E_KEYRING_DIR}/pubring.gpg"
    mkdir -p "${E2E_KEYRING_DIR}"
    if [ -f "${pubring}" ]; then
        cp "${pubring}" "${pubring}.e2e-backup"
    fi
    if gpg --batch --homedir "${E2E_GNUPGHOME}" --export "${E2E_SENDER_FPR}" >> "${pubring}"; then
        e2e_note "appended E2E sender public key to ${pubring} (backup: ${pubring}.e2e-backup)"
    else
        return 1
    fi
}

# Imports the extension pubring into the gpg home and resolves the recipient
# key fingerprint for TEST_EMAIL. Returns 1 when no key exists.
e2e_resolve_recipient_key() {
    local pubring="${E2E_KEYRING_DIR}/pubring.gpg"
    [ -f "${pubring}" ] || return 1
    gpg --batch --homedir "${E2E_GNUPGHOME}" --import "${pubring}" >/dev/null 2>&1 || true
    E2E_USER_FPR="$(gpg --batch --homedir "${E2E_GNUPGHOME}" --with-colons \
        --list-keys "${TEST_EMAIL}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
    [ -n "${E2E_USER_FPR}" ]
}

e2e_message_headers() {
    # e2e_message_headers <from> <to> <subject> <message-id>
    printf 'From: %s\r\n' "$1"
    printf 'To: %s\r\n' "$2"
    printf 'Subject: %s\r\n' "$3"
    printf 'Message-ID: %s\r\n' "$4"
    printf 'Date: %s\r\n' "$(date '+%a, %d %b %Y %H:%M:%S %z')"
    printf 'MIME-Version: 1.0\r\n'
}

# Builds a PGP/MIME (RFC 3156) signed message. The detached signature covers
# the exact bytes of the first part entity, with no trailing CRLF (the CRLF
# preceding a boundary belongs to the delimiter, RFC 2046 5.1.1).
e2e_build_signed_message() {
    # e2e_build_signed_message <out> <from> <to> <subject> <message-id> <body>
    local out="$1" from="$2" to="$3" subject="$4" msgid="$5" body="$6"
    local work boundary
    work="$(mktemp -d /tmp/rnpmail-e2e-msg.XXXXXX)"
    boundary="----rnpmail-e2e-signed-$RANDOM-$$"
    {
        printf 'Content-Type: text/plain; charset="utf-8"\r\n'
        printf 'Content-Transfer-Encoding: 7bit\r\n'
        printf '\r\n'
        printf '%s' "${body}"
    } > "${work}/part1.bin"
    gpg --batch --yes --rfc4880 --digest-algo SHA256 \
        --pinentry-mode loopback --passphrase "" \
        --homedir "${E2E_GNUPGHOME}" --local-user "${E2E_SENDER_FPR}" \
        --detach-sign --armor --output "${work}/sig.asc" "${work}/part1.bin" || {
        rm -rf "${work}"
        return 1
    }
    {
        e2e_message_headers "${from}" "${to}" "${subject}" "${msgid}"
        printf 'Content-Type: multipart/signed; micalg="pgp-sha256"; protocol="application/pgp-signature"; boundary="%s"\r\n' "${boundary}"
        printf '\r\n'
        printf 'This is an OpenPGP/MIME signed message (RFC 3156).\r\n'
        printf -- '--%s\r\n' "${boundary}"
        cat "${work}/part1.bin"
        printf '\r\n'
        printf -- '--%s\r\n' "${boundary}"
        printf 'Content-Type: application/pgp-signature; name="signature.asc"\r\n'
        printf 'Content-Transfer-Encoding: 7bit\r\n'
        printf '\r\n'
        sed -e 's/$/\r/' "${work}/sig.asc"
        printf -- '--%s--\r\n' "${boundary}"
    } > "${out}"
    rm -rf "${work}"
}

# Builds a PGP/MIME encrypted+signed message for TEST_EMAIL.
e2e_build_encrypted_message() {
    # e2e_build_encrypted_message <out> <from> <to> <subject> <message-id> <body>
    local out="$1" from="$2" to="$3" subject="$4" msgid="$5" body="$6"
    local work boundary
    work="$(mktemp -d /tmp/rnpmail-e2e-msg.XXXXXX)"
    boundary="----rnpmail-e2e-enc-$RANDOM-$$"
    {
        printf 'Content-Type: text/plain; charset="utf-8"\r\n'
        printf 'Content-Transfer-Encoding: 7bit\r\n'
        printf '\r\n'
        printf '%s\r\n' "${body}"
    } > "${work}/inner.bin"
    gpg --batch --yes --rfc4880 --digest-algo SHA256 --trust-model always \
        --pinentry-mode loopback --passphrase "" \
        --homedir "${E2E_GNUPGHOME}" \
        --local-user "${E2E_SENDER_FPR}" --recipient "${E2E_USER_FPR}" \
        --encrypt --sign --armor --output "${work}/blob.asc" "${work}/inner.bin" || {
        rm -rf "${work}"
        return 1
    }
    {
        e2e_message_headers "${from}" "${to}" "${subject}" "${msgid}"
        printf 'Content-Type: multipart/encrypted; protocol="application/pgp-encrypted"; boundary="%s"\r\n' "${boundary}"
        printf '\r\n'
        printf 'This is an OpenPGP/MIME encrypted message (RFC 3156).\r\n'
        printf -- '--%s\r\n' "${boundary}"
        printf 'Content-Type: application/pgp-encrypted\r\n'
        printf 'Content-Transfer-Encoding: 7bit\r\n'
        printf '\r\n'
        printf 'Version: 1\r\n'
        printf -- '--%s\r\n' "${boundary}"
        printf 'Content-Type: application/octet-stream\r\n'
        printf 'Content-Transfer-Encoding: 7bit\r\n'
        printf '\r\n'
        sed -e 's/$/\r/' "${work}/blob.asc"
        printf -- '--%s--\r\n' "${boundary}"
    } > "${out}"
    rm -rf "${work}"
}

# Builds a plain (unsigned, unencrypted) message.
e2e_build_plain_message() {
    # e2e_build_plain_message <out> <from> <to> <subject> <message-id> <body>
    local out="$1" from="$2" to="$3" subject="$4" msgid="$5" body="$6"
    {
        e2e_message_headers "${from}" "${to}" "${subject}" "${msgid}"
        printf 'Content-Type: text/plain; charset="utf-8"\r\n'
        printf 'Content-Transfer-Encoding: 7bit\r\n'
        printf '\r\n'
        printf '%s\r\n' "${body}"
    } > "${out}"
}

# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------

# Logs into IMAP with retries; used to wait for a freshly started server and
# to trigger GreenMail's first-login user auto-creation.
e2e_imap_login() {
    # e2e_imap_login <host> <port> <user> <password>
    python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import imaplib, sys, time
host, port, user, password = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
last_error = None
for attempt in range(15):
    try:
        imap = imaplib.IMAP4(host, port)
        imap.login(user, password)
        imap.logout()
        break
    except (OSError, imaplib.IMAP4.error, imaplib.IMAP4.abort) as exc:
        last_error = exc
        time.sleep(2)
else:
    raise SystemExit(f"IMAP login to {host}:{port} failed after retries: {last_error}")
PYEOF
}

e2e_deliver_via_smtp() {
    # e2e_deliver_via_smtp <host> <port> <from> <to> <file>
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import smtplib, sys, time
host, port, sender, recipient, path = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
with open(path, "rb") as fh:
    data = fh.read()
last_error = None
for attempt in range(5):
    try:
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.sendmail(sender, [recipient], data)
        break
    except (OSError, smtplib.SMTPException) as exc:
        # A freshly started server may accept TCP before speaking SMTP.
        last_error = exc
        time.sleep(2)
else:
    raise SystemExit(f"SMTP delivery to {host}:{port} failed after retries: {last_error}")
PYEOF
}

# Drops the message into a Dovecot maildir (bypasses SMTP; the stock
# local-mail-server.sh Postfix cannot deliver to virtual users).
e2e_deliver_via_maildir() {
    # e2e_deliver_via_maildir <maildir-user-root> <file>
    local root="$1" file="$2"
    mkdir -p "${root}/new" "${root}/cur" "${root}/tmp"
    local dest
    dest="${root}/new/$(date +%s).$RANDOM.$$.e2e"
    cp "${file}" "${dest}"
}

# ---------------------------------------------------------------------------
# Shared test flow
# ---------------------------------------------------------------------------

# Runs the injected-message suite once the account exists in Mail:
# plain, signed-only, and encrypted+signed messages, each with arrival,
# sender, content, source and banner-state assertions.
#
# NOTE on `set -e`: assertion helpers return non-zero when an assertion
# fails, so they are only ever invoked in a condition context (if/&&/||)
# to keep the suite running after a failure.
e2e_run_injected_tests() {
    # e2e_run_injected_tests <deliver-mode: smtp|maildir> <maildir-root>
    local deliver_mode="$1" maildir_root="${2:-}"
    local run_id msgid subject token file
    run_id="$(date +%s)-$$"

    # --- Test 1: plain message (basic assertions, no keys needed) ----------
    subject="RnpMail E2E plain ${run_id}"
    msgid="<e2e-plain-${run_id}@rnpmail-e2e>"
    token="RNP-E2E-PLAIN-${run_id}"
    file="$(mktemp /tmp/rnpmail-e2e-plain.XXXXXX)"
    e2e_build_plain_message "${file}" \
        "RnpMail E2E Sender <${E2E_SENDER_EMAIL}>" "${TEST_EMAIL}" \
        "${subject}" "${msgid}" "Plain control message. Token: ${token}"
    if ! e2e_deliver "${deliver_mode}" "${maildir_root}" "${file}"; then
        e2e_fail "plain: delivery failed"
    elif e2e_assert_message_basics "plain" "${subject}" "${E2E_SENDER_EMAIL}" "${token}"; then
        e2e_assert_message_source "plain" "${subject}" plain || true
    fi
    rm -f "${file}"

    # --- Tests 2/3 need gpg and the extension keyring ----------------------
    if ! e2e_have_gpg; then
        e2e_skip "signed/encrypted: gpg not installed (brew install gnupg)"
        return 0
    fi
    if ! e2e_have_python3; then
        e2e_skip "signed/encrypted: python3 not available"
        return 0
    fi
    if ! e2e_setup_gpg; then
        e2e_skip "signed/encrypted: could not create throwaway gpg key"
        return 0
    fi
    if ! e2e_import_sender_pubkey; then
        e2e_skip "signed/encrypted: could not import sender key into ${E2E_KEYRING_DIR}"
        return 0
    fi
    e2e_restart_mail || true

    # --- Test 2: signed-only message ---------------------------------------
    subject="RnpMail E2E signed ${run_id}"
    msgid="<e2e-signed-${run_id}@rnpmail-e2e>"
    token="RNP-E2E-SIGNED-${run_id}"
    file="$(mktemp /tmp/rnpmail-e2e-signed.XXXXXX)"
    if ! e2e_build_signed_message "${file}" \
        "RnpMail E2E Sender <${E2E_SENDER_EMAIL}>" "${TEST_EMAIL}" \
        "${subject}" "${msgid}" "Signed-only message. Token: ${token}"; then
        e2e_fail "signed: could not build PGP/MIME signed message with gpg"
    elif ! e2e_deliver "${deliver_mode}" "${maildir_root}" "${file}"; then
        e2e_fail "signed: delivery failed"
    elif e2e_assert_message_basics "signed" "${subject}" "${E2E_SENDER_EMAIL}" "${token}"; then
        e2e_assert_message_source "signed" "${subject}" signed || true
        e2e_open_message "${subject}" >/dev/null || true
        e2e_assert_banner_state "signed" "${msgid}" valid False "${E2E_SENDER_EMAIL}" || true
    fi
    rm -f "${file}"

    # --- Test 3: encrypted+signed message ----------------------------------
    if e2e_resolve_recipient_key; then
        subject="RnpMail E2E encrypted ${run_id}"
        msgid="<e2e-encrypted-${run_id}@rnpmail-e2e>"
        token="RNP-E2E-ENCRYPTED-${run_id}"
        file="$(mktemp /tmp/rnpmail-e2e-enc.XXXXXX)"
        if ! e2e_build_encrypted_message "${file}" \
            "RnpMail E2E Sender <${E2E_SENDER_EMAIL}>" "${TEST_EMAIL}" \
            "${subject}" "${msgid}" "Encrypted and signed message. Token: ${token}"; then
            e2e_fail "encrypted: could not build PGP/MIME encrypted message with gpg"
        elif ! e2e_deliver "${deliver_mode}" "${maildir_root}" "${file}"; then
            e2e_fail "encrypted: delivery failed"
        elif e2e_assert_message_basics "encrypted" "${subject}" "${E2E_SENDER_EMAIL}" "${token}"; then
            e2e_assert_message_source "encrypted" "${subject}" encrypted || true
            e2e_open_message "${subject}" >/dev/null || true
            e2e_assert_banner_state "encrypted" "${msgid}" valid True "${E2E_SENDER_EMAIL}" || true
        fi
        rm -f "${file}"
    else
        e2e_skip "encrypted: no public key for ${TEST_EMAIL} in ${E2E_KEYRING_DIR}/pubring.gpg"
        e2e_skip "  generate one in the container app, then re-run"
    fi
}

# Dispatches to the configured delivery mechanism.
e2e_deliver() {
    # e2e_deliver <mode: smtp|maildir> <maildir-root> <file>
    local mode="$1" maildir_root="$2" file="$3"
    case "${mode}" in
        smtp)
            e2e_deliver_via_smtp "${E2E_SMTP_HOST}" "${E2E_SMTP_PORT}" \
                "${E2E_SENDER_EMAIL}" "${TEST_EMAIL}" "${file}" ;;
        maildir)
            e2e_deliver_via_maildir "${maildir_root}" "${file}" ;;
        *)
            echo "ERROR: unknown deliver mode ${mode}" >&2
            return 2 ;;
    esac
}
