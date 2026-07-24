# 13 — Document the searchability and archival limits of encrypted mail

Status: pending · Tier: Future · Depends on: nothing

## Goal

Set user expectations honestly about what is and isn't searchable in
encrypted mail, and what the long-term archival story looks like. Today
nothing in the docs addresses this; users will discover the limit by
failing to search and concluding the product is broken.

## Why this matters

The #1 "this is unusable" complaint about encrypted-mail products, after
disaster recovery, is some variant of:

> "I have 10,000 encrypted emails and I can't find the one I need. Spotlight
> doesn't search the body. The product is useless to me."

This is a fundamental PGP limitation (the body is encrypted at rest), not
unique to RNP. But the user doesn't know that. The right fix is a clear
documentation page plus, in the UI, an honest affordance on the search
result.

## Documentation

### New page: `docs/encrypted-mail-search.md`

Contents:

1. **What Spotlight can search**: From, To, Cc, Subject (after the
   extension decodes a protected-headers message and writes the decoded
   version back to Mail — verify this happens), Date, Message-ID. These
   come from headers, which are not encrypted (or are restored from
   protected headers on decode).
2. **What Spotlight cannot search**: the body of an encrypted message.
   This is fundamental: the body is encrypted at rest in Mail's storage,
   and Mail's Spotlight indexer sees the ciphertext, not the plaintext.
3. **Workarounds**:
   - Use specific, descriptive Subject lines (they are searchable for
     protected-headers messages).
   - Tag or file encrypted messages into folders by topic.
   - For high-value messages, copy the decrypted body into a note in
     Apple Notes or a separate encrypted Vault (1Password, etc.).
4. **Future plan**: a post-1.0 optional decrypted-body index, encrypted
   at rest with a separate index key in the Keychain. This is a
   significant security trade-off (the index leaks content to anything
   that can read the index key) and would be opt-in. See
   `15-deferred-post-1.0.md`.

### FAQ entry

> **Can I search encrypted mail by body?**
>
> No. Spotlight can search From, To, Subject, and Date of encrypted mail,
> but not the message body — the body is encrypted at rest and Mail's
> search indexer can't read it. This is true for every PGP-encrypted mail
> product, not just RNP. We recommend descriptive Subject lines for
> encrypted mail you'll need to find later.
>
> See [Encrypted mail and search](encrypted-mail-search.md) for the full
> picture and future plans.

### SECURITY-MODEL.md addition

Add to "What is NOT protected" — or rather, add a new section "What we
cannot do" — the explicit note that message-body search is impossible
without a plaintext index, and that we don't build one.

## UI affordance

In the Mail banner for encrypted messages, a discreet link:

> 🔒 Encrypted — [Why can't I search this message?]

Clicking opens a popover with the short version of the FAQ entry and a
link to the docs page.

## Verification work first

Before writing the docs, verify what Mail actually does on decode. Two
specific questions:

1. When `MEDecodedMessage.data` is returned with the decrypted body, does
   Mail re-index the message for Spotlight with the decrypted body, or
   only with the outer headers?
2. For protected-headers messages, does the decoded Subject replace the
   outer (placeholder) Subject in Spotlight's index?

The answer determines what we can claim in the docs. If Mail re-indexes
with the decrypted body, then Spotlight search works after the user opens
the message once — which is much better than the worst case and should be
documented. If it doesn't, document the actual behavior.

This verification is a single half-day investigation: send encrypted test
messages, open them in Mail, then search via Spotlight.

## Tests

- A documentation review test that asserts the docs page exists and is
  reachable from the FAQ. (Cheap, prevents link rot.)
- A test that verifies the Mail banner link opens the popover without
  crashing.

## Acceptance criteria

- `docs/encrypted-mail-search.md` exists and is linked from the FAQ and
  the SECURITY-MODEL.
- The Mail banner link is present on every encrypted message and opens
  the popover without error.
- The docs accurately describe the verified behavior (whatever it is).

## Notes / risks

- If Mail *does* re-index decrypted bodies, that's a major UX win and we
  should make it prominent. Don't bury it.
- If Mail *does not*, the long-term fix is the decrypted-body index (see
  15). Document that as a future option, not a promise.
- Do not implement the decrypted-body index in 1.0. The security trade-off
  (a separate at-rest index key) needs a threat-model review first.
