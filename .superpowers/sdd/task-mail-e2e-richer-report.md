# Task report: richer Mail end-to-end assertions

Date: 2026-07-21
Branch: `automation/mail-e2e-richer-assertions` (from `main` @ 554ce5a)
Worktree: `/Users/mulgogi/src/rnp/swift-rnp`

## Summary

The AppleScript-based Mail end-to-end scripts previously asserted only "a
message with the expected subject exists and its content matches" — a check
that a plaintext message passes vacuously (the old `test-mail-e2e.sh` also
never gated its exit code on the result). This change:

1. **Enriches the assertions** in both `scripts/test-mail-e2e.sh` and
   `scripts/test-mail-e2e-docker.sh` (shared implementation in the new
   `scripts/mail-e2e-common.sh`):
   - arrival with the exact expected subject (polled, not a fixed `sleep`),
   - sender address matching the signing key owner,
   - decrypted content matching the original body (per-run unique token),
   - raw message source structure via Mail's AppleScript `source` property:
     `multipart/signed` + `application/pgp-signature` for signed messages,
     `multipart/encrypted` + `application/pgp-encrypted` for encrypted ones,
     absence of both for the plain control message,
   - PASS/FAIL/SKIP accounting with a real exit code.
2. **Adds a banner-state check via an extension state file.** The Mail
   extension now records each OpenPGP decode outcome as JSON in the app
   group container (see "Production changes" below); the scripts open the
   message in Mail (triggering the decode) and assert the recorded
   signature status (`valid`), trust state, `isEncrypted` flag, and that
   the recorded signer matches the sender address.
3. **Tests both signed-only and encrypted+signed messages.** AppleScript
   cannot toggle Mail's compose-window security buttons, so inbound test
   messages are constructed directly with `gpg` (PGP/MIME, RFC 3156) using
   a throwaway sender key, and injected into the mail store:
   - local server (`test-mail-e2e.sh`): dropped into the Dovecot maildir
     (the stock `local-mail-server.sh` Postfix cannot deliver to virtual
     users, so SMTP injection does not work there — documented in the
     script header; the AppleScript outgoing send is kept as a smoke test),
   - GreenMail (`test-mail-e2e-docker.sh`): sent over SMTP with python3.
   The sender public key is appended to the extension's `pubring.gpg`
   (backup written next to it) so the extension can verify signatures; the
   recipient public key is read from the extension keyring to build the
   encrypted message, so decryption exercises the real keyring + Keychain
   passphrase path. Key-dependent tests SKIP with clear instructions when
   prerequisites (gpg, user key in the extension keyring) are missing.

## Production changes (minimal, documented in `docs/SECURITY-MODEL.md`)

- `Sources/MailSecurityEngine/SecurityStateRecorder.swift` (new):
  `RecordedMessageSecurity` / `RecordedSigner` Codable records and a
  `SecurityStateRecorder` writing `last-message.json` plus
  `messages/<sanitized-message-id>.json` (atomic, best-effort; a failing
  write only logs and never breaks decoding).
- `Sources/MailSecurityEngine/AppGroup.swift`: new
  `extensionStateDirectory()` next to the existing `keyringDirectory()`
  (app group container with the same Application Support fallback).
- `Sources/MailSecurityEngine/MessageSecurityCore.swift`: optional
  `stateRecorder` initializer parameter (defaults to `nil`, so existing
  call sites and tests are unchanged); on decode it records the security
  outcome plus the envelope `Message-ID`/`Subject`/`From` headers and
  per-signer trust state from the existing `TrustStore`.
- `Swift-Rnp/MailPlugin/MessageSecurityHandler.swift`: wires the recorder
  pointed at `AppGroup.extensionStateDirectory()`.

Records contain message metadata (subject, Message-ID, sender,
signature/trust status) but **never message bodies**; they live in the
same app group protection domain as the keyring. Documented in
`docs/SECURITY-MODEL.md` (Assets table + boundary notes).

## Files changed

- `Sources/MailSecurityEngine/SecurityStateRecorder.swift` (new)
- `Sources/MailSecurityEngine/AppGroup.swift`
- `Sources/MailSecurityEngine/MessageSecurityCore.swift`
- `Swift-Rnp/MailPlugin/MessageSecurityHandler.swift`
- `Tests/MailSecurityEngineTests/SecurityStateRecorderTests.swift` (new)
- `scripts/mail-e2e-common.sh` (new)
- `scripts/test-mail-e2e.sh` (rewritten)
- `scripts/test-mail-e2e-docker.sh` (brought in from
  `automation/robust-snapshot-and-l10n`, then rewritten; it did not exist
  on `main`)
- `.github/workflows/mail-e2e.yml` (trigger paths extended to the new
  script files)
- `docs/SECURITY-MODEL.md`

## Verification

- `bash -n` clean on all three script files; shellcheck shows only benign
  warnings (cross-file SC2034 for the sourced config variables).
- `swift test` (with `PKG_CONFIG_PATH=Vendor/pkgconfig` and
  `-Xlinker -rpath -Xlinker Vendor/RNPFramework.xcframework/macos-arm64_x86_64`):
  full suite **136 tests, 1 failure** which was the new
  `testRecordWithoutMessageIDWritesOnlyLastMessage` (recorder eagerly
  created the `messages/` directory); after making directory creation
  lazy, `swift test --filter SecurityStateRecorderTests` passes 4/4 and
  the recorder change touches no other code path.
- **Message construction validated against the real engine** (scratch
  SwiftPM package in `/tmp`, not committed): gpg-built signed-only and
  encrypted+signed messages were decoded through the real
  `MailSecurityEngine` + `MessageSecurityCore` + `SecurityStateRecorder`:
  signature `valid`, signer label/trust/isEncrypted recorded correctly,
  decrypted body intact. This caught a real interop bug during
  development: gpg in strict RFC 4880 mode defaults to **SHA-1** for both
  the key self-signature and document signatures, which librnp 0.18
  rejects under its default security profile (status `invalid`, and
  signer user IDs unresolvable). Fixed by forcing
  `--cert-digest-algo SHA256` at key generation and `--digest-algo SHA256`
  for signing.
- **GreenMail roundtrip validated in Docker**: all three message types
  delivered via the script's SMTP helper and fetched back over IMAP with
  the MIME structure, armor blocks and body tokens intact. This also
  surfaced and fixed two environment issues: GreenMail users only exist
  after first login (messages bounced — the script now pre-creates the
  user via `e2e_imap_login`), and freshly started GreenMail accepts TCP
  before speaking SMTP/IMAP (readiness probes and delivery retries added).
- The full Mail.app flow was **not** run end-to-end on this machine: the
  AppleScript steps operate on the user's real Mail installation, and the
  MailKit extension decode/banner path can only run inside a signed,
  enabled Mail extension. The AppleScript helpers mirror the previously
  used patterns plus Mail's documented `source` property; they should be
  exercised once on a test machine/runner (`REQUIRE_BANNER=1` makes
  missing banner records a hard failure there).

## Notes / follow-ups

- The scripts append one clearly labeled public key
  (`RnpMail E2E Sender <e2e-sender@localhost>`) to the extension
  keyring's `pubring.gpg`; a backup is written to
  `pubring.gpg.e2e-backup` on first run. The matching secret key is
  throwaway (temp gpg home, deleted on exit).
- Mail is restarted by the scripts after the key import so the extension
  reloads the keyring; this is called out in the script headers.
- The local Dovecot/Postfix server cannot accept SMTP delivery for the
  virtual test user; inbound messages are therefore delivered via maildir
  drop. Making Postfix deliver via Dovecot LMTP would allow the AppleScript
  outgoing-path test to assert arrival locally too — deliberately out of
  scope (`local-mail-server.sh` untouched).
- Banner-state assertions are best-effort by default (SKIP when no state
  records appear, e.g. an extension build predating this change); set
  `REQUIRE_BANNER=1` on runners where the extension is known to be
  enabled and current.
