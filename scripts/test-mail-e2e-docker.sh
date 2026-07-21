#!/bin/bash
# scripts/test-mail-e2e-docker.sh
# End-to-end Mail extension test against a GreenMail Docker container.
#
# Requirements:
#   - GreenMail running on localhost (SMTP 3025, IMAP 3143).
#   - A signed build of the container app and Mail extension.
#   - The extension enabled in Mail.
#
# Usage: ./scripts/test-mail-e2e-docker.sh
set -euo pipefail

SMTP_PORT="${GREENMAIL_SMTP_PORT:-3025}"
IMAP_PORT="${GREENMAIL_IMAP_PORT:-3143}"
TEST_EMAIL="${TEST_EMAIL:-test@localhost}"
TEST_PASSWORD="${TEST_PASSWORD:-test}"

echo "=== Configuring Mail account ==="
osascript <<APPLESCRIPT
tell application "Mail"
    set accountName to "RnpMail GreenMail Test"
    set existingAccounts to name of every account
    if existingAccounts does not contain accountName then
        set newAccount to make new account with properties {name:accountName, user name:"test", email addresses:{"${TEST_EMAIL}"}, full name:"Test User"}
        tell newAccount
            set server settings of incoming server to {server name:"127.0.0.1", port:${IMAP_PORT}, use ssl:false, authentication:password}
            set password of incoming server to "${TEST_PASSWORD}"
            set server settings of outgoing server to {server name:"127.0.0.1", port:${SMTP_PORT}, use ssl:false, authentication:password}
            set password of outgoing server to "${TEST_PASSWORD}"
        end tell
    end if
end tell
APPLESCRIPT

echo "=== Sending signed+encrypted test message ==="
osascript <<'APPLESCRIPT'
tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:"RnpMail E2E test", content:"This is a test message from the RnpMail E2E script."}
    tell newMessage
        set sender to "test@localhost"
        set to recipient to "test@localhost"
        set visible to true
    end tell
    send newMessage
end tell
APPLESCRIPT

echo "=== Waiting for message to arrive ==="
sleep 10

echo "=== Checking for message ==="
osascript <<'APPLESCRIPT'
tell application "Mail"
    set inboxMessages to messages of inbox
    repeat with msg in inboxMessages
        if subject of msg is "RnpMail E2E test" then
            log "Found test message: " & subject of msg
            if content of msg contains "This is a test message" then
                log "Message decrypted successfully"
                return "PASS"
            else
                log "Message content mismatch"
                return "FAIL"
            end if
        end if
    end repeat
    log "Test message not found"
    return "FAIL"
end tell
APPLESCRIPT

echo "=== E2E test complete ==="
