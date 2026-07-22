# Trust Model

RNP uses a deliberately simple trust model focused on clarity and actionable
warnings: **trust on first use**, **manual fingerprint verification**, and
**hard stops on key changes**. This document explains the model, its
rationale, and its limits.

## The three states

Every public key RNP knows about is in exactly one of three states:

| State | Meaning | Effect |
|---|---|---|
| **Unverified** | The first key seen for an email address, recorded automatically. | Usable. Encryption and verification proceed normally; the key is shown without a badge. |
| **Verified** | You compared the fingerprint with the owner over a trusted channel and clicked **Mark as verified**. | Usable, shown with a green badge in the key list and in Mail's signature banner. |
| **Problem** | A different fingerprint appeared for an address you already know. | Encryption to that address is **blocked** with a `trustConflict` error until you verify the new key. |

## Trust on first use (TOFU)

The first time a public key is seen for an email address — imported by hand or
fetched from a keyserver — it is recorded as *unverified* and can be used
immediately. This matches how most people actually behave: they install a key
and start sending mail. TOFU trades first-contact assurance for usability,
and makes it up with change detection (below).

## Manual fingerprint verification

Users who want stronger assurance can upgrade a key to *verified*:

1. Open the key's detail sheet in the RNP app. It shows the full fingerprint
   and a copy button.
2. Compare the fingerprint with the key's owner over a channel you trust —
   in person, a phone call, a business card, or a message you have already
   verified. Do not compare it over the same email channel you are trying to
   secure.
3. Click **Mark as verified**.

From then on, Mail's banner shows a green verified indicator for messages
signed by that key.

## Key-change warnings and conflicts

If a *different* fingerprint is later imported or fetched for the same email
address, the new key is marked *problem* and a conflict is raised:

- The RNP app shows a warning banner listing the affected address.
- Encryption to that address is blocked with a `trustConflict` error.
- The conflict clears only when you inspect the new key's fingerprint and
  verify it.

A key change can be legitimate — people replace lost keys, rotate after a
compromise, or re-key on a schedule — or it can be an attempted key
substitution. RNP cannot tell the difference, so it asks the one party who
can: you. The block is the point: silently switching keys would defeat the
purpose of the trust store.

## What the trust store protects against tampering

The trust database lives in the shared app-group container as `trust.json`
with a detached Ed25519 signature in `trust.json.sig`, signed by a key
derived at first launch. The signature is verified on every load; if either
file is modified, corrupted, or deleted, the store resets to empty —
**fail-closed to unverified** rather than trusting corrupted data. The worst
case of a tampered store is that you have to re-verify your keys, never that
a hostile key is silently trusted.

## Why no web-of-trust

GnuPG-style ownertrust, trust signatures, and web-of-trust calculations are
**intentionally out of scope**. They add significant UX complexity — marginal
vs. full trust, trust depth, keyring-wide recomputation — that few users
navigate correctly, and they are not required for the "verify the key once,
warn on change" model used here. This is a deliberate scope cut, not a
missing feature. If you need web-of-trust semantics, GnuPG remains the right
tool; RNP keyrings are GPG-compatible, so keys can move between the two.

## What this model does not cover

- **First-contact authenticity.** TOFU accepts the first key seen for an
  address. If an attacker can intercept that first contact — for example by
  answering your keyserver query with their own key — they win that round.
  Verify fingerprints out-of-band for any correspondence that matters.
- **Keyserver correctness.** A keyserver can return attacker-controlled keys
  (see [Keyservers](keyserver.md#trust-and-privacy-considerations)). The
  conflict mechanism catches *changes*; it cannot vouch for a first key.
- **Compromised hosts.** If the Mac itself is compromised, trust decisions
  made on it cannot be trusted. See [Security model](SECURITY-MODEL.md) for
  the full threat picture.

## See also

- [Usage — trusting keys](usage.md#trusting-keys)
- [Security model](SECURITY-MODEL.md)
- [FAQ](faq.md#why-is-there-no-web-of-trust)
