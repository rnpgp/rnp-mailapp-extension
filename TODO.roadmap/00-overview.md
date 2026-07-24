# 00 — Overview: Roadmap to a credible encrypted-mail product

This directory is the forward-looking plan, derived from an audit of the full
key lifecycle and message lifecycle against what real encrypted-email users
need. It complements `TODO.impl/`, which was the original 1.0 release plan
(M1–M7, all merged).

## Why this roadmap exists

`TODO.impl/` closed the **mechanical** scope: keys can be created, imported,
published; mail can be signed, encrypted, decoded; trust can be tracked. What
it did not fully close is the **user-trust** scope: what happens when a key
expires, when a Mac dies, when a recipient's key changes, when a user wants
post-quantum confidentiality today. Those are the questions that decide
whether real users (journalists, lawyers, dissidents, archivists, ordinary
people who care about privacy) will trust this product with mail that
matters.

The audit is in two halves:

1. **Key lifecycle**: create → backup → distribute → verify → use → rotate →
   expire → revoke → retire → migrate.
2. **Message lifecycle**: compose → address → encode → send → receive →
   decode → verify → archive → search → re-read years later → reply/forward.

Every gap below is keyed to a lifecycle stage so reviewers can see why it
matters, not just what to build.

## Priority tiers

| Tier | Theme | Items | Rationale |
|---|---|---|---|
| **A** | Recovery & trust | 01–06 | Without these, the first user who loses a Mac, hits an expired key, or BCCs someone loses mail or leaks metadata — and they blame the product. |
| **B** | Better encryption UX | 07–10 | Differentiators. Without Autocrypt and mailbox scan, the cold-start experience is empty and we're invisible to the K-9/Thunderbird/Delta Chat ecosystem. |
| **Future** | Modern crypto & scope cuts | 11–15 | PQC, AEAD/v6, documentation polish, and an explicit list of what's deferred past 1.0. |

## Roadmap

| File | Tier | Title | Depends on |
|---|---|---|---|
| `01-disaster-recovery.md` | A | Paper backup, recovery sheet, iCloud Keychain sync | — |
| `02-archive-key-state.md` | A | Decrypt-only "archived" state so revoked/retired keys still decrypt old mail | — |
| `03-decryption-errors.md` | A | Replace generic "undecryptable" with actionable errors (missing key, wrong passphrase, tampered, unknown algo) | 02 |
| `04-key-expiry-recovery.md` | A | A recovery path for every expiry scenario, not just a warning | 02 |
| `05-key-transition-wizard.md` | A | Guided "migrate to new key" flow with transition signatures | 04 |
| `06-bcc-handling.md` | A | Refuse or re-encrypt when BCC is present (RFC 3156 §6) | — |
| `07-autocrypt.md` | B | Emit and read Autocrypt headers (`rnp_key_export_autocrypt`) | 10 |
| `08-mailbox-key-scan.md` | B | First-run UX: scan INBOX/Sent for keys | 07 |
| `09-compose-recipient-diagnostics.md` | B | Per-recipient status panel in compose | — |
| `10-multi-uid-keys.md` | B | One key, multiple email addresses (`rnp_key_add_uid`) | — |
| `11-pqc-hybrid.md` | Future | Detect and use recipient PQ-capable keys; opt-in hybrid keygen (ML-KEM + X25519, etc.) | 12 |
| `12-aead-v6.md` | Future | AEAD-OCB encryption and v6 PKESK (SEIPDv2) for capable recipients | — |
| `13-search-archive-documentation.md` | Future | Document that encrypted mail body is not Spotlight-searchable | — |
| `14-pre-release-cleanup.md` | Future | Bundle full license texts; FAQ drift fix; notarization pre-flight | — |
| `15-deferred-post-1.0.md` | Future | Hardware tokens, mobile companion, decrypted-body search index, primary-offline flow | — |

## Conventions

Same as `TODO.impl/`: each file is self-contained, pick-up-able by a fresh
session. Branch per task (`NN-short-name`), PR per task, CI must stay green.
All logic that can live outside MailKit lives in SwiftPM targets with `swift
test` coverage; Xcode targets stay thin.

## librnp pinned behavior (verified against vendored `Sources/CRnp/rnp/rnp.h`)

These FFI names are the ones the roadmap relies on. They already exist in the
current pin; new work should call them rather than reinvent.

- Multi-UID: `rnp_key_add_uid`, `rnp_key_signature_set_primary_uid`.
- Transition signatures: `rnp_key_signature_sign` + subpacket setters
  (`rnp_key_signature_set_hash`, `rnp_key_signature_set_key_expiration`, …).
- Autocrypt: `rnp_key_export_autocrypt`.
- AEAD / v6: `rnp_op_encrypt_set_aead`, `rnp_op_encrypt_enable_pquesk_v6`,
  `rnp_op_generate_set_v6_key`.
- PQC: hybrid KEM names (`ML-KEM-768+X25519`, …) and hybrid signing names
  (`ML-DSA-65+ED25519`, …), exposed as algorithm strings.
- Decryption diagnostics: `rnp_dump_packets_to_json` for PKESK key IDs.
- Revocation: `rnp_key_revoke`, `rnp_key_export_revocation`.
