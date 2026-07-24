# 06 — BCC handling: don't leak BCC recipients via PKESK

Status: pending · Tier: A · Depends on: nothing

## Goal

Today, `encryptionRecipients(for:composeContext:)` returns the full To+Cc+Bcc
list and the encoder produces a single PGP/MIME blob with one PKESK per
recipient. Any decrypting recipient can enumerate the PKESK key IDs and see
the entire recipient list — including BCC. That violates RFC 3156 §6 and is
a real privacy leak.

Fix it. Pick the safest option for 1.0 and document the rest.

## Why this is Tier A

This is the kind of bug that gets a CVE. PGP users who BCC a sensitive
third party (a lawyer, a journalist, an anonymous source) expect PGP to
preserve the BCC. Today it does the opposite, silently. Once a user
discovers this the hard way, trust is gone.

RFC 3156 §6 is explicit:

> Ideally, it should NOT be the case that the same encrypted text goes to
> all recipients... under some circumstances this may reveal that the BCC
> recipients are present.

Most PGP clients either ignore this or document the leak. We should not
ship 1.0 with the leak undocumented.

## Design (chosen: refuse with a clear path forward)

When the user attempts to send an encrypted message with BCC recipients:

1. The encode path refuses with a `bccRequiresSpecialHandling` error
   surfaced in the compose window.
2. A sheet explains:
   > Encrypting this message would reveal your BCC recipients to everyone
   > in To and Cc. PGP encryption exposes all recipient key IDs in the
   > message envelope — there is no way to hide a BCC recipient within a
   > single encrypted message.
   >
   > Choose how to proceed:
   >
   > 1. **Send separately** — RNP creates one encrypted message for the To
   >    and Cc recipients (no BCC), plus one separate encrypted message per
   >    BCC recipient. Each BCC recipient sees only themselves.
   > 2. **Remove encryption** — send as plaintext (or signed-only) so BCC
   >    works normally.
   > 3. **Remove BCC recipients** — encrypt as a single message to To + Cc
   >    only.
   > 4. **Cancel** — go back and edit the message.

Option 1 is the one most users actually want; the wizard defaults to it.

### Implementation

In `MessageSecurityCore.encodeOutgoingMessage`, before calling the engine's
encoder:

```swift
if composeContext.shouldEncrypt {
    let bcc = message.recipientAddresses.filter { isBcc($0, in: message) }
    if !bcc.isEmpty {
        throw MailSecurityError.bccRequiresSpecialHandling(bcc: bcc)
    }
}
```

Where `isBcc` requires MailKit's structured access to To/Cc/Bcc separately.
The current `MailMessage.recipientAddresses` flattens them; we need
`MailMessage.toAddresses`, `.ccAddresses`, `.bccAddresses` as separate
fields (mirror the MEMessage shape).

For option 1 (send separately), the engine needs a new
`encodeOutgoingMessageSet` entry point that produces an
`[HandlerEncodedMessage]`. MailKit's `MEMessageEncodingResult` is a single
message — work out with the host app whether multiple sends are supported
via repeated encode calls or whether we need to batch them differently.
Likely: the handler returns one encoded message per BCC set, and the
container app calls Mail's send pipeline N times.

### Incoming-message BCC detection

When the user receives a PGP/MIME message that decrypts successfully but
the ciphertext contains a PKESK for a key that does not match any visible
To/Cc recipient, that means the user was BCC'd. Surface discreetly in the
security banner:

> Encrypted to 3 recipients; you are recipient #2. Recipients: alice@x,
> bob@x (you), [hidden].

The "[hidden]" is the third PKESK key ID, which we cannot map to a name
without their key. This is informational and matches what GnuPG's
`--list-only` shows.

## Tests

- Outgoing with Bcc + shouldEncrypt: refused with the right error and
  three options offered.
- "Send separately" path: produces N+1 encoded messages (one for To+Cc, one
  per Bcc). Each message's PKESK list, inspected via `rnp_dump_packets`,
  matches the expected recipient set.
- "Remove encryption" path: single plaintext (or signed-only) message to
  all recipients including Bcc.
- "Remove BCC" path: single encrypted message to To+Cc only.
- Incoming with hidden third PKESK: banner shows "Recipients: alice, bob
  (you), [hidden]."

## Acceptance criteria

- It is impossible to send an encrypted message with BCC recipients that
  leaks them to non-BCC recipients.
- The refusal is loud (no silent send) but offers at least one encryption-
  preserving path (option 1).
- The privacy caveat is added to `docs/usage.md` and `docs/SECURITY-MODEL.md`
  ("What is NOT protected" gets a new line about metadata visibility).

## Notes / risks

- Some MailKit versions may not expose Bcc separately to extensions; if
  that's the case, we cannot fix this from the extension side and the only
  option is to document. **Verify MailKit's MEMessage shape first** before
  committing to option 1.
- "Send separately" multiplies server load and may interact badly with
  SMTP rate limits. Document; consider a confirmation step when Bcc has
  more than ~10 recipients.
- An alternative design — re-encrypting the body once and wrapping in
  multiple `multipart/encrypted` outer shells — is non-standard and
  interoperates poorly. Do not pursue for 1.0.
- Long-term, the right fix is Sealed Sender / per-recipient-subject
  schemes; out of scope here.
