# 04 — Key expiry recovery: a path forward for every scenario

Status: pending · Tier: A · Depends on: 02 (archive state)

## Goal

When any key in the system (own or recipient's) is expired or about to
expire, the user must always see **what it means for them** and **what to
do next**, with the most common action available as a single button.

We already have expiry *detection* (`KeyLifecycle.expiryReport()`,
`ExpiredKeyWarning`, the Mail banner). What's missing is **recovery** —
the actionable next step.

## Why this is Tier A

The current UX shows "your key expires in 12 days" and stops there. The
user's reaction is "OK, what do I do?" If they don't figure it out in 12
days, they hit a hard wall: mail stops signing, recipients stop trusting
their signatures, and the path back is opaque. This is exactly the kind of
problem that pushes users to abandon PGP entirely.

## Scenario catalogue

Every scenario has: trigger, impact on the user, recovery steps, and the
copy shown. This is the spec for the recovery wizard.

### Own keys

| # | Scenario | Impact on user | Recovery |
|---|---|---|---|
| 1 | Own primary expires in ≤ 60d | Recipients may stop trusting new signatures; some mailers refuse to encrypt to soon-to-expire keys. | 1. **Extend expiry** (default +2y; slider for 1y/2y/5y/never). 2. **Publish** to keyservers. 3. Optionally **notify contacts** (template email — see below). |
| 2 | Own primary expired, secret available | Can decrypt/verify old mail. Cannot sign new mail. Cannot be encrypted-to by new senders. | Same as #1 (extend), plus a banner: "Recent mail you sent may have arrived unsigned — correspondents should refresh your key." |
| 3 | Own primary expired, secret lost | Cannot extend (no signing material). Cannot sign new mail. | Generate **new key**, then either (a) sign the new key with the old key if a revocation cert + paper backup is available (see `05-key-transition-wizard`), or (b) if no recovery material exists, notify contacts out-of-band, share the new fingerprint via a trusted channel, and revoke the old key with the revocation cert. |
| 4 | Own signing subkey expired | Cannot sign. Decryption unaffected. | **Rotate signing subkey** (one click). Publish. Notify contacts. |
| 5 | Own encryption subkey expired | New mail to you warns senders; some refuse to encrypt. You can still decrypt. | **Rotate encryption subkey** (one click). Publish. Notify contacts. |
| 6 | Own subkey expired AND secret lost | Cannot rotate that subkey. | Generate **new subkey on the primary** (if primary secret available) → publish → notify. If primary secret also lost, see #3. |
| 7 | All own keys expired | Cannot sign or encrypt anything. Decryption of old mail still works. | Per-key recovery (above) + a bulk-action **"Extend all"** button when secret material is available for all. |
| 8 | Own primary revoked | Cannot be used for new mail. Old mail still decrypts (if not deleted — see 02). | Archive the revoked key (decrypt-only). Generate new key with transition signature if old secret was used to revoke (see 05). Notify contacts. |

### Recipient keys

| # | Scenario | Impact on user | Recovery |
|---|---|---|---|
| 9 | Recipient's key expires in ≤ 60d | Mail still encrypts (with warning). Some clients auto-extend by refreshing, so this often self-resolves. | Send a templated **nudge email** ("Hi, your PGP key expires in N days. Consider extending it.") if the user opts in. Auto-refresh picks up extensions automatically. |
| 10 | Recipient's key expired | Encrypting to them may fail or warn; recipient may not be able to read new mail anyway. | 1. **Fetch latest** from keyserver (often they already extended). 2. If still expired, **contact them out-of-band** (template). 3. If unresponsive after N days, choose to **encrypt anyway** (best-effort, with explicit acknowledgment) or **refuse and send plaintext** with a note. |
| 11 | Received mail encrypted to **your** expired key | Decrypts fine (librnp allows this). | Informational banner only: "Encrypted to your key that expired on `<date>`. New senders may have trouble — [Extend]. No action needed to read this message." |

### Received mail from expired signers

| # | Scenario | Impact on user | Recovery |
|---|---|---|---|
| 12 | Received mail signed by expired signer key (signature made **before** expiry) | Verifies with warning. | Informational banner: "Signed by `<key>`, which expired on `<date>`. The signature was made before expiry, so it's still valid. Consider asking the sender to extend their key." |
| 13 | Received mail signed by expired signer key (signature made **after** expiry) | Verification fails. | Treat as invalid signature. Banner: "Signature was made after the key expired. This is unusual — either the sender's clock is wrong, their mail client is misconfigured, or the message is forged. Do not trust." |

## Design

### Key Health view (new top-level tab in the container app)

A single screen showing the status of every key (own and recipient), with
status chips:

- **Healthy** (green dot)
- **Expiring in N days** (amber dot)
- **Expired N days ago** (red dot)
- **Revoked** (gray dot with line-through)
- **Archived** (gray dot)
- **Conflict** (red triangle)

Clicking any row expands the row with: "What this means for you" (one
sentence), "What you can do" (one or more buttons), and "Learn more"
(expanded explanation + link to docs).

Filters: "My keys" / "Recipients" / "Needs attention" (anything not
healthy).

### Inline recovery (where the user already is)

The Key Health view is for browsing; most users will encounter expiry in
context. Recovery flows must be reachable from:

- **Compose window** (signing-key expired): blocking dialog before send.
  "Your signing key expired `<date>`. [Extend now] [Generate new key]
  [Send unsigned]" (last option with warning).
- **Compose window** (encryption-subkey expired): same flow for own
  encryption subkey.
- **Mail banner** (recipient's key expired in incoming encrypted mail):
  informational only, with "Notify sender" if you're reading new mail from
  them.
- **Mail banner** (your key expired and you're reading mail encrypted to
  it): scenario #11 above.
- **Onboarding** (existing imported key is expired): warn at import time
  and offer "Extend" or "Use as-is" (deprecated).

### Notify-contacts template

For actions that change your key (extend, rotate subkey, revoke, transition
to new key), offer to email the contacts who have encrypted to you (from
the `ExtensionState/` records — they track per-message sender/recipient).
The template:

> Subject: My PGP key was updated
>
> Hi,
>
> I just updated my PGP key (`<primary user ID>`). My fingerprint is now:
>
> `<grouped hex fingerprint>`
>
> If you use a keyserver, refreshing should pick up the change
> automatically. If you verify fingerprints out-of-band, please update your
> records.
>
> Thanks,
> `<name>`

With [To: contacts who encrypted to me] [Copy to clipboard] [Don't send].

### Expiry-extension UX

Single-sheet, 30-second interaction:

```
Extend key expiry
─────────────────
Key: Alice <alice@example.com> (Ed25519)
Currently expires: 2026-08-15 (12 days)

New expiry:
  ( ) +1 year   (2027-08-15)
  (•) +2 years  (2028-08-15)   [recommended]
  ( ) +5 years  (2031-08-15)
  ( ) No expiry (not recommended)

[ ] Publish updated key to keyservers after extending
[ ] Notify contacts who encrypted to me (3 people)

                       [Cancel]  [Extend]
```

### Subkey rotation UX (already partly in `KeyLifecycle`)

When the user clicks "Rotate encryption subkey" from Key Health:

```
Rotate encryption subkey
────────────────────────
Key: Alice <alice@example.com>
Current subkey: cv25519, expires 2026-08-15

A new cv25519 subkey will be generated. The old subkey will be
archived (kept for decrypting existing mail) and set to expire in
30 days (grace period for in-flight messages).

[ ] Publish updated key
[ ] Notify contacts

                       [Cancel]  [Rotate]
```

## Tests

For each scenario #1–#13, a unit test that:

1. Constructs a synthetic keyring with the relevant expiry state (use
   fixture keys with crafted expiry offsets).
2. Drives the recovery flow end-to-end (extend / rotate / etc.).
3. Asserts the resulting banner / chip / next-action.

Round-trip tests:

- Extend expiry → publish → second keyring refreshes → warning clears.
- Rotate encryption subkey → old mail still decrypts → new encryption uses
  the new subkey (assert via `rnp_dump_packets` that the PKESK points to
  the new subkey's key ID).
- Notify-contacts template renders with the correct fingerprint grouping
  and the correct To-list (read from `ExtensionState/`).

For scenario #3 (own primary expired + secret lost), the test path covers
the key-transition-wizard hand-off to `05-key-transition-wizard.md`.

For scenario #13 (signature made after expiry), craft a signature via
`librnp` with a backdated creation time and verify the banner.

## Acceptance criteria

- The string "key expired" never appears without a primary action button.
- Every scenario in the catalogue has at least one automated test.
- The Key Health view loads in < 200 ms with 500 keys (perf test).
- Documentation: a new `docs/key-lifecycle.md` page walks through each
  scenario in plain language, mirroring the table above.

## Notes / risks

- The "notify contacts" feature touches `ExtensionState/`, which is
  currently a test-harness affordance. Promote it to a first-class
  per-message record store (signed, in the app group) — needed for both
  this and for `08-mailbox-key-scan`.
- The default extension of +2 years matches Thunderbird and is what most
  users expect. Power users who want no-expiry keys should still have the
  option.
- After extending, the keyring file changes; the engine must publish the
  updated key automatically if the user opted in (default ON).
- For the "encrypt anyway" path in scenario #10 (recipient expired and
  unresponsive): make the acknowledgment checkbox sticky per-recipient so
  the user isn't asked every time.
