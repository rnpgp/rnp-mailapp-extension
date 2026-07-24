# Post-quantum cryptography

This page explains how RNP handles post-quantum (PQ) cryptography: what
librnp supports today, what RNP enables by default, and what the
trade-offs are. For background on why PQ matters for email specifically,
see [Security model — Post-quantum considerations](SECURITY-MODEL.md).

## Why post-quantum for email

Email is uniquely vulnerable to "harvest now, decrypt later":

- Email is archived for decades. Messages encrypted today may still be
  sensitive in 2050.
- Adversaries can store ciphertext today and decrypt it when a
  cryptographically relevant quantum computer becomes available.
- TLS-protected sessions have forward secrecy (per-session keys) and
  short value; PGP-encrypted email does not. A single encrypted email
  leaks its plaintext for as long as the ciphertext exists.

PQ key agreement is therefore **more urgent for email than for almost
any other application of public-key crypto**.

## What librnp supports

librnp exposes (verified against the vendored `Sources/CRnp/rnp/rnp.h`):

**Hybrid KEM (encryption).** Classical + ML-KEM (FIPS 203):

| Algorithm | Notes |
|---|---|
| `ML-KEM-768+X25519` | Recommended default; same hybrid TLS uses. |
| `ML-KEM-1024+X448` | Higher security level; larger keys. |
| `ML-KEM-768+ECDH-P256` | FIPS 203 + NIST P-256. |
| `ML-KEM-1024+ECDH-P384` | Higher security level with P-384. |
| `ML-KEM-768+ECDH-BP256` | Brainpool variant. |
| `ML-KEM-1024+ECDH-BP384` | Brainpool variant. |

**Hybrid signing.** Classical + ML-DSA (FIPS 204):

| Algorithm | Notes |
|---|---|
| `ML-DSA-65+ED25519` | Recommended default. |
| `ML-DSA-87+ED448` | Higher security level. |
| `ML-DSA-65+ECDSA-P256` | FIPS 204 + NIST P-256. |
| `ML-DSA-87+ECDSA-P384` | Higher security level. |
| `ML-DSA-65+ECDSA-BP256` | Brainpool variant. |
| `ML-DSA-87+ECDSA-BP384` | Brainpool variant. |

**Conservative PQ signing (hash-based, no lattice).** SLH-DSA:

| Algorithm | Notes |
|---|---|
| `SLH-DSA-SHA2` | Sphincs+ with SHA-2. Very large signatures (~50 KB). |
| `SLH-DSA-SHAKE` | Sphincs+ with SHAKE. |

Notably **librnp does not expose a PQ-only KEM** — only classical+PQ
hybrids. This is by design: the hybrid provides classical-OR-PQ
security, surviving a break of either algorithm. RNP follows the same
policy: we never emit PQ-only encryption, always hybrid.

## RNP policy

Three levels (in Settings → Encryption):

- **Classical (default).** New keys use Ed25519, RSA-3072, or ECDSA
  P-256. Recipients still receive hybrid encryption when their key
  advertises a hybrid KEM subkey — that happens automatically inside
  librnp's encrypt op, independent of this setting.

- **Hybrid.** New keys use `ML-DSA-65+ED25519` for signing and
  `ML-KEM-768+X25519` for encryption. Larger keys, slightly slower,
  maximum long-term confidentiality.

- **Conservative.** New primary uses `SLH-DSA-SHA2` (hash-based;
  hedging against lattice breaks). Encryption subkeys stay classical
  because librnp does not expose a PQ-only KEM. Signatures are
  PQ-secure; messages to you fall back to classical encryption.

## How recipients get hybrid encryption automatically

When you encrypt, librnp iterates the recipient keys and picks the best
PKESK algorithm per recipient. If a recipient has both a classical
encryption subkey and a hybrid `ML-KEM-768+X25519` subkey, librnp uses
the hybrid. The sender does not need to opt in.

This means even users who never generate a PQ key benefit when
correspondents publish PQ-capable keys — the encryption upgrades
silently.

## Trade-offs

PQ keys and signatures are larger than classical ones:

| | Classical | Hybrid | Conservative (SLH-DSA) |
|---|---|---|---|
| Primary key | ~100 B | ~3 KB | ~50 KB |
| Self-signature | ~100 B | ~5 KB | ~50 KB |
| Autocrypt header | ~300 B | ~3.5 KB | ~50 KB |
| Encrypt of 1 MB | ~50 ms | ~80 ms | ~50 ms |
| Sign of 1 KB | ~5 ms | ~15 ms | ~30 ms |

(Approximate, M1-class hardware; your mileage will vary.)

Conservative (SLH-DSA) signatures are large enough to matter for
mailbox quotas and for clients that cap MIME part sizes. Use sparingly.

## Migration from classical to hybrid

The key-transition wizard ([Key lifecycle](key-lifecycle.md)) handles
algorithm changes. A user with an Ed25519 key can run the wizard to
generate a new `ML-DSA-65+ED25519 + ML-KEM-768+X25519` key, sign it
with the old key (transition certification), and notify contacts.

## See also

- [Security model](SECURITY-MODEL.md)
- [Key lifecycle](key-lifecycle.md)
- [Dependencies](DEPENDENCIES.md) (librnp pinning; CVE policy)
