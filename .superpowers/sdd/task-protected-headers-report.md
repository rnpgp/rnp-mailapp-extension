# Task report: Protected headers (Subject encryption)

**Branch:** `feat/protected-headers` (from `main`)
**Commit:** `3f67373` — feat: protected headers (Memory Hole) for PGP/MIME encrypted mail

## Goal

Encrypt the Subject and other sensitive headers in PGP/MIME messages so they
don't leak in plaintext, matching modern PGP/MIME user agents (K-9 Mail,
Thunderbird) — the `protected-headers="v1"` ("Memory Hole") scheme.

## What was implemented

### Encoding — `Sources/MailSecurityEngine/MessageEncoder.swift`

- New internal `ProtectedHeaders` constants: the protected header set
  (`subject`, `from`, `to`, `cc`, `date`, `message-id`, `references`,
  `in-reply-to`, `reply-to`) and the placeholder subject `"Encrypted message"`.
- In `encodePGPMime`, encrypt branch only: when the message has protectable
  headers, the MIME entity being protected is wrapped by
  `protectedHeadersEntity(protected:entity:eol:)` into a
  `multipart/mixed; protected-headers="v1"` whose first part is
  `text/rfc822-headers; protected-headers="v1"` carrying the protected header
  block and whose second part is the original MIME entity. The whole structure
  is what gets signed and encrypted, so the protected headers are covered by
  the signature as well (K-9 layout, which Thunderbird also reads).
- The outer `Content-Type: multipart/encrypted` gains
  `protected-headers="v1"`, and the outer `Subject` is replaced by
  `"Encrypted message"`. Routing headers (From, To, Date, …) stay at the outer
  level as well — Mail's message list needs them — but their protected copies
  win for display after decryption.
- Sign-only and inline-PGP encoding are unchanged (backward compatible).

### Decoding — `Sources/MailSecurityEngine/MessageDecoder.swift`

- `decodePGPMimeEncrypted` checks the outer `multipart/encrypted` for
  `protected-headers="v1"`. When present, `extractProtectedHeaders(from:eol:)`
  recovers the real headers from the decrypted payload in two layouts:
  - **K-9 style:** multipart with a leading `text/rfc822-headers` part; the
    remaining part becomes the content entity (multiple content parts are
    reassembled into a `multipart/mixed`).
  - **Thunderbird style:** the payload itself is a full RFC 822 message whose
    non-`Content-*` headers are the protected ones.
- `mergingProtectedHeaders(_:into:)` replaces outer envelope headers with
  their protected counterparts in place (no duplicates); envelope headers not
  covered by the protected set are kept.
- When the parameter is absent, or the payload carries no recoverable
  protected headers, decoding falls back to the previous behavior (outer
  headers + decrypted entity) — full backward compatibility.

The `MailSecurityEngine` public API is unchanged, per the task constraint.

### Docs

`docs/faq.md`, `docs/usage.md`, `docs/SECURITY-MODEL.md`, `docs/features.md`
previously stated that subjects are never encrypted; updated to describe the
protected-headers behavior and its limits (recipients/date still visible;
Mail.app sees the subject locally before encryption / after decryption).

## Tests — `Tests/MailSecurityEngineTests/ProtectedHeadersTests.swift` (10 tests)

Encoding:

- `testEncryptHidesSubjectBehindPlaceholder` — outer has
  `protected-headers="v1"` + placeholder Subject; the real subject (incl.
  non-ASCII) does not appear anywhere in the encoded bytes.
- `testProtectedHeadersInnerStructure` — decrypts the payload by hand and
  asserts the K-9-style structure (multipart/mixed + text/rfc822-headers with
  the real Subject/From/To + original entity).
- `testSignOnlyKeepsSubjectInClear` — sign-only messages are unchanged
  (backward compatibility).

Decoding:

- `testProtectedHeadersRoundtripRestoresRealHeaders` — sign+encrypt roundtrip:
  real Subject/From/To/Message-ID restored exactly once each, valid signature,
  placeholder gone.
- `testProtectedHeadersAttachmentRoundtrip` — multipart/mixed with attachment
  survives; subject restored; attachment bytes intact.
- `testTamperedOuterSubjectIsIgnored` — a forged outer Subject does not affect
  the displayed (protected) subject; signature stays valid.

Foreign layouts / backward compatibility:

- `testLegacyEncryptedMessageWithoutProtectedHeadersDecodes` — old-style
  message without the parameter shows outer headers.
- `testThunderbirdStyleProtectedHeadersDecoded` — Thunderbird layout decoded.
- `testK9StyleMultiPartContentIsRebuilt` — multi-part content reassembly.
- `testProtectedHeadersParameterWithoutHeadersFallsBack` — parameter present
  but nothing inside degrades to outer headers.

## Verification (all run on this branch)

1. `PKG_CONFIG_PATH=/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker /Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1/lib`
   → **318 tests passed, 0 failed** (all 10 new tests pass; all pre-existing
   tests still pass). Log: `.superpowers/sdd/task-protected-headers-swift-test.log`.
   (Three pre-existing snapshot-test warnings about machine-specific font
   rendering remain, as before.)
2. `PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme RNP build CODE_SIGNING_ALLOWED=NO`
   → **BUILD SUCCEEDED**. Log: `.superpowers/sdd/task-protected-headers-xcode-rnp.log`.
3. `PKG_CONFIG_PATH=$(pwd)/Vendor/pkgconfig xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO`
   → **BUILD SUCCEEDED**. Log: `.superpowers/sdd/task-protected-headers-xcode-mailplugin.log`.

## Notes / follow-ups

- **Placeholder subject in message lists:** before decoding, Mail's message
  list shows "Encrypted message" for protected mail (same as K-9/Thunderbird
  correspondents see). After the extension decodes the message, the real
  subject is displayed.
- **E2E harness:** the injected GPG-built messages
  (`scripts/mail-e2e-common.sh`) carry no protected-headers parameter and are
  decoded by the fallback path, so they are unaffected. The
  `e2e_send_via_mail` smoke test correlates by exact subject; if that compose
  session sends encrypted, the wire subject is now the placeholder — its
  arrival assertion was already non-fatal (`e2e_note`), but a future harness
  run against a deliverable server may need to expect the placeholder subject
  (or the decoded one, depending on Mail's indexing). Not verified here —
  the harness needs a live Mail.app setup.
- Header folding: protected header values are re-serialized unfolded (as the
  engine already does elsewhere); line-length SHOULDs are not enforced.
- Old K-9 versions that omitted the outer `protected-headers` parameter are
  not sniffed (extraction is gated on the parameter, per spec); they fall
  back to outer headers, which is safe.
