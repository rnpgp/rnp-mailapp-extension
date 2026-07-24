# Encrypted mail and search

This page is honest about what Spotlight can and cannot search in
encrypted mail, and what the long-term plan is.

## The short version

Spotlight can search the **headers** of encrypted mail (From, To,
Subject, Date, Message-ID) but **not the body**. The body is encrypted
at rest in Mail's storage, and Mail's Spotlight indexer cannot read
it.

This is true for every PGP-encrypted mail product, not just RNP. It is
a fundamental property of encryption, not a bug.

## What works

| Searchable | Source |
|---|---|
| From, To, Cc | Outer envelope headers (always visible). |
| Subject | Outer Subject. For messages with protected headers, the
decrypted Subject is what Mail displays after RNP processes the
message; whether Spotlight re-indexes depends on Mail's decode-then-
reindex behavior (verification in progress — see
[`TODO.roadmap/13-search-archive-documentation.md`](TODO.roadmap/13-search-archive-documentation.md)). |
| Date | Outer Date header. |
| Message-ID | Outer Message-ID. |
| Folder, account, flags | Mail metadata. |

## What does not work

| Not searchable | Reason |
|---|---|
| Body text | Encrypted at rest. |
| Attachment contents | Encrypted with the body. |
| Attachment filenames | Inside the encrypted payload for PGP/MIME encrypted mail. |

## Workarounds

Until RNP ships an optional decrypted-body index (post-1.0; significant
security trade-off), the practical workarounds are:

- **Use descriptive Subject lines** for encrypted mail you will need to
  find later. The Subject travels in the protected headers, so it is
  searchable after Mail indexes the decoded message.
- **File encrypted mail into topical folders** as you receive it. Folder
  paths are searchable.
- **Copy the decrypted body** into Apple Notes or a separate encrypted
  vault (1Password, etc.) when you need guaranteed findability.

## The future plan

A local decrypted-body index is possible but comes with a real security
trade-off:

- The index key is a new high-value target (anything that can read it
  can reconstruct the bodies).
- Deterministic tokens in the index leak content patterns.
- Spotlight integration requires `CSSearchableIndex`, which has its own
  sandboxing implications.

The design is in
[`TODO.roadmap/15-deferred-post-1.0.md`](TODO.roadmap/15-deferred-post-1.0.md)
under "Decrypted-body search index." It will ship only after a threat-
model review and only as opt-in.

## Verification: how Mail actually handles decoded bodies

The claims above about what Spotlight can and cannot search depend on
how Mail re-indexes a message after `MEDecodedMessage.data` is handed
back. We have not yet run the verification end-to-end; the manual test
below is the canonical procedure. Once it has been run, update this
section with the observed behavior.

### Manual test procedure

1. **Set up two Macs** (or two Mail accounts on one Mac).
2. **Send three messages** from one account to the other:
   - A plaintext control message containing a unique body string like
     `zzz-test-plaintext-body-123`.
   - An encrypted PGP/MIME message with the same unique body string
     but a different marker (e.g., `zzz-test-encrypted-body-456`).
   - An encrypted PGP/MIME message with protected headers, where the
     unique Subject is `zzz-test-protected-subject-789` and the body
     contains `zzz-test-protected-body-789`.
3. **On the receiving Mac**: open each message in Mail so RNP decodes
   it. Wait 30 seconds for Spotlight to index.
4. **Search Spotlight** (⌘+Space) for each unique marker:
   - Body markers from the plaintext message: should be found.
   - Body markers from the encrypted message: verify whether found or
     not.
   - Protected-Subject markers: verify whether found in the Spotlight
     index or only in Mail's own search.

### What the results mean

- If the encrypted body markers are **not** found: confirms our claim
  above. Spotlight cannot index encrypted-mail bodies. Document the
  finding and move on.
- If the encrypted body markers **are** found after opening the
  message once: Mail re-indexes with the decrypted bytes. This is a
  major UX win; we should update this doc and `docs/features.md` to
  call it out.
- If the protected-Subject marker is found: confirms that protected
  headers' decrypted Subject replaces the outer placeholder in
  Spotlight's index.

### Recording the result

Once verified, add a row to `docs/encrypted-mail-search.md` stating
the result with the test date and the macOS / Mail versions used. If
the result differs from the current claims, update the "What works"
and "What does not work" tables.

## See also

- [Security model](SECURITY-MODEL.md) — what is and isn't protected
- [Usage](usage.md)
