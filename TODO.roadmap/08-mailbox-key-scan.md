# 08 — Mailbox key scan: populate the keyring from received mail

Status: pending · Tier: B · Depends on: 07 (Autocrypt), 09 (compose
diagnostics, for surfacing the result)

## Goal

First-run UX: a user installs RNP and is immediately told "we found keys
for 18 of your contacts — you can encrypt to them now," instead of being
presented with an empty keyring and a "Import key" button.

Scan the user's local mail cache for keys in three forms — Autocrypt
headers, `application/pgp-keys` attachments, and keys embedded in signed
messages — and offer to import them in bulk.

## Why this is Tier B

The empty-keyring cold-start is the single biggest UX obstacle to opportunistic
encryption adoption. Most users have been receiving signed mail for years
without realizing it. Surfacing those keys turns "set up encryption" into a
one-click task.

## Design

### Consent gate

On first launch (after key generation or import), the onboarding asks:

> ### Find keys for your contacts
>
> RNP can scan your local mail to find public keys for people you already
> correspond with. The scan runs entirely on your Mac; nothing is sent
> anywhere.
>
> Sources we'll check:
> - Autocrypt headers
> - Public-key attachments
> - Embedded keys in signed messages
>
> [Scan now] [Maybe later]

Settings → Encryption → "Re-run key scan" lets the user re-trigger later
(e.g., after a major folder sync).

### Implementation

`MailboxKeyScan` service in `MailSecurityEngine`:

1. Enumerate mail messages via MailKit's `MEMessage` (or, if MailKit does
   not expose a mailbox-enumeration API to extensions, document that the
   scan runs from the container app via a separate Mail-AppleScript bridge
   — investigate during implementation).
2. For each message, extract:
   - `Autocrypt:` header → parse per `07-autocrypt.md`.
   - `application/pgp-keys` attachments → armored key block.
   - Signed multipart → extract the signing key from the signature's issuer
     key ID (already available via `RnpSignatureInfo`).
3. Deduplicate by fingerprint. Keep the most recent observation per
   fingerprint (for Autocrypt) or the most complete version (for `pgp-keys`
   attachments, which carry more packets than the signing-key extraction).
4. Cap the scan: default 1000 most-recent messages; user can raise to
   10000 in Settings. The scan runs in chunks of 50, yielding control back
   to the UI every chunk to keep the app responsive.
5. Results list: per-key, show "From: `<primary UID>`, Fingerprint: `<short>`,
   Source: `<Autocrypt / attachment / signature>`, Date: `<observed>`."
   Each row has [Import] [Ignore]. Bulk: [Import all] [Ignore all].

### Privacy

- No network calls during the scan.
- No telemetry on what was scanned, only a local count ("Found N keys in
  M messages").
- Ignored keys are remembered (per-fingerprint) so re-scans don't re-prompt.
- The scan never imports Autocrypt headers from messages in the Spam or
  Trash folder (configurable).

### Interaction with trust

Imported-from-scan keys land in the keyring as `unverified` (TOFU). They're
immediately usable for opportunistic encryption, but the user is nudged to
verify fingerprints for any correspondence that matters (see
`07-trust-verification.md` from `TODO.impl/`).

### Interaction with `ExtensionState/`

The scan populates the same store that `04-key-expiry-recovery.md` uses for
"notify contacts who encrypted to me" — promote `ExtensionState/` to a
first-class per-message record (signed, in the app group, not just a test
harness).

## Tests

- Synthetic mailbox with N messages containing each source type; assert
  the right keys are surfaced.
- Deduplication: same key in Autocrypt + attachment + signature → one row,
  labeled with all three sources.
- Privacy: no network calls made during the scan (network-log assertion).
- Chunked progress: scan of 1000 messages produces 20 progress updates.
- Consent gate: scan does not start without explicit user opt-in.
- Re-scan: ignored keys are not re-prompted.

## Acceptance criteria

- A user with an existing mailbox (Thunderbird import or just months of
  signed mail) completes the scan and gets at least one importable key in
  under 30 seconds.
- The scan does not block the UI; progress is visible.
- Documentation: `docs/usage.md` gains a "Find keys for your contacts"
  section pointing at this feature.

## Notes / risks

- **MailKit API gap risk**: if MailKit does not expose mailbox enumeration
  to extensions, this feature has to live in the container app and use a
  separate mechanism (e.g., `NSSavePanel` to a mailbox export, or
  AppleScript to read Mail's messages). Investigate before committing to
  the design. If no API exists, defer to post-1.0.
- Scanning rate is critical: too slow feels broken, too fast triggers
  Mail's sandbox protections. 50 messages per chunk with a 10 ms yield has
  worked in other contexts; tune during implementation.
- Large attachments (50 MB signed PDFs) should be skipped during the scan
  (just look at headers and small attachments, not full body parse for
  every message).
- The user must be able to delete all scan-imported keys in one action
  ("Forget all scan-imported keys") in case they want to start over.
