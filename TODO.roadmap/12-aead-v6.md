# 12 — AEAD-OCB encryption and v6 PKESK (SEIPDv2) for capable recipients

Status: pending · Tier: Future (post-1.0 default-on) · Depends on: nothing

## Goal

Use modern OpenPGP crypto where the recipient supports it:

- **AEAD-OCB** for authenticated encryption (replaces CFB + MDC), resistant
  to malleability and chosen-ciphertext attacks beyond what MDC offers.
- **PKESK v6** → **SEIPDv2** for recipients whose keys support it, which
  hides the recipient key ID (better metadata privacy) and is the
  envelope for future algorithms including PQ hybrids (11).

## Why this matters

CFB + MDC is the legacy OpenPGP encryption mode. It works but has known
sharp edges (MDC is a hash, not a MAC; malleability is detectable but the
detection is brittle). AEAD (RFC 7253 OCB) is the modern OpenPGP standard
since the crypto-refresh.

PKESK v3 leaks the recipient key ID in the clear (visible to anyone who
sees the ciphertext). PKESK v6 wraps it in a one-shot DH so the key ID is
hidden unless you have the secret. This is a real privacy improvement for
encrypted mail: today, anyone watching a message in transit can see who
it's for.

## librnp surface (verified in `Sources/CRnp/rnp/rnp.h`)

- `rnp_op_encrypt_set_aead(op, alg)` — `alg = "OCB"` enables AEAD (`:3807`).
- `rnp_op_encrypt_set_aead_bits(op, bits)` — chunk size in bits (`:3817`).
- `rnp_op_encrypt_enable_pkesk_v6(op)` — emit PKESK v6 → SEIPDv2 (`:3693`).
- `RNP_KEY_FEATURE_AEAD` flag (`:153`) on recipient keys indicates AEAD
  support.
- `rnp_op_generate_set_v6_key(op)` — generate v6 keys (`:1224`).

## Design

### Defaults

Detect recipient support and pick the best envelope:

| Recipient capability | Envelope | Notes |
|---|---|---|
| Supports AEAD + v6 | AEAD-OCB + PKESK v6 + SEIPDv2 | Best privacy and integrity. |
| Supports AEAD only | AEAD-OCB + PKESK v3 | Modern encryption, v6 not advertised. |
| Neither | CFB + MDC (current default) | Backward compat. |

When a single message has multiple recipients with mixed capabilities, the
sender's choice applies to the whole message — librnp can emit multiple
PKESK versions in one message, but the body's SEIPD version is one. Pick
the **highest common denominator**: if any recipient doesn't support v6,
fall back to v3 PKESK for all (still AEAD if all support AEAD).

### Settings

A toggle in Settings → Encryption:

```
Encryption envelope
───────────────────
( ) Automatic (recommended) — use AEAD/v6 when recipients support it
( ) Force AEAD (refuse to encrypt to recipients that lack AEAD support)
( ) Force legacy (CFB + MDC; maximum compatibility)
```

Most users stay on Automatic. Power users who want to enforce modern crypto
pick Force AEAD. The legacy option exists for correspondents on very old
clients.

### v6 key generation

When the user opts in (Settings → Advanced → "Generate v6 keys"), new keys
are v6 (calls `rnp_op_generate_set_v6_key`). v6 keys interop with modern
clients but not with very old ones. Default for 1.0: v4 keys (current
behavior); v6 opt-in.

v6 keys are a prerequisite for some PQ algorithms (11) and for PKESK v6.
Document this in the migration guide.

### Backward compatibility

Incoming PGP/MIME with PKESK v3 / SEIPDv1 (current majority) decrypts and
verifies as today — librnp's verifier handles all envelope versions
transparently. We do not need to do anything special on the decode side.

### Interaction with PQC

When PQ hybrid KEM is used (11), v6 PKESK is mandatory (the PQ algorithms
are not defined for v3). The encoder must call `rnp_op_encrypt_enable_pquesk_v6`
whenever any recipient has a hybrid KEM subkey.

## Tests

- Encrypt to an AEAD+V6-capable recipient → ciphertext uses AEAD-OCB and
  PKESK v6 (verify via `rnp_dump_packets`).
- Encrypt to a v3-only recipient → ciphertext falls back to CFB+MDC and
  PKESK v3.
- Mixed-recipient message → uses the highest common denominator.
- Force-AEAD setting: encryption to a non-AEAD recipient fails with a
  clear error.
- v6 keygen: generated key has version 6; round-trip with a v6-capable
  recipient.
- Interop: a v3-encrypted message from GnuPG still decrypts.

## Acceptance criteria

- The default setting ("Automatic") produces the most modern envelope the
  recipient supports, with no user intervention.
- No regression on legacy message compatibility.
- Documentation: `docs/security.md` gains an "Encryption envelopes"
  section explaining AEAD/v6 and when each is used.

## Notes / risks

- **AEAD-EAX is deprecated** (per `rnp.h:3804` comment). Never emit it.
  Reading EAX-encrypted messages is fine for legacy compat.
- **PKESK v6 leaks more bandwidth, not less** (~100 bytes more per
  recipient). The trade-off is recipient anonymity vs. message size.
  Acceptable.
- **Chunk size**: `rnp_op_encrypt_set_aead_bits` controls the chunk size
  for streaming AEAD. Default to a reasonable value (e.g., 2^16 = 64 KiB)
  for compatibility with librnp's defaults. Larger chunks = less overhead
  but more memory.
- **First-receiver interop**: Thunderbird 115+ supports AEAD; older
  Thunderbird does not. Sequoia supports both. GnuPG 2.3+ supports AEAD.
  Document the matrix.
- **Future**: when librnp enables SEIPDv2 by default, we can remove the
  v3 fallback path. Track upstream.
