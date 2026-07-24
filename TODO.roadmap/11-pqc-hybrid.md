# 11 — Post-quantum hybrid encryption and signing

Status: pending · Tier: Future (post-1.0 opt-in) · Depends on: 12 (AEAD/v6
defaults)

## Goal

Use recipient PQ-capable keys automatically (hybrid encryption to
`ML-KEM-768+X25519` etc. when the recipient advertises it), and offer
opt-in generation of hybrid PQ keys for users who want post-quantum
confidentiality today.

## Why this matters for encrypted email specifically

Email is uniquely vulnerable to "harvest now, decrypt later":

- Email is archived for decades. Messages encrypted today may still be
  sensitive in 2050.
- Adversaries (signal intelligence, large archives) can store ciphertext
  today and decrypt it when a cryptographically relevant quantum computer
  becomes available.
- TLS-protected web sessions have forward secrecy (per-session keys) and
  short value; PGP-encrypted email does not. A single encrypted email
  leaks its plaintext for as long as the ciphertext exists.

PQ key agreement is therefore **more urgent for email than for almost any
other application of public-key crypto**. TLS moved first (X25519+ML-KEM
hybrid is now Chromium default); OpenPGP should follow.

librnp already exposes the algorithms. This roadmap item brings them to
users.

## librnp PQ surface (verified in `Sources/CRnp/rnp/rnp.h`)

Hybrid KEM (encryption), `rnp.h:4122–4127`:

- `ML-KEM-768+X25519`  ← TLS-standard hybrid, recommended default
- `ML-KEM-1024+X448`
- `ML-KEM-768+ECDH-P256`
- `ML-KEM-1024+ECDH-P384`
- `ML-KEM-768+ECDH-BP256`
- `ML-KEM-1024+ECDH-BP384`

Hybrid signing, `rnp.h:4128–4133`:

- `ML-DSA-65+ED25519`  ← recommended default
- `ML-DSA-87+ED448`
- `ML-DSA-65+ECDSA-P256`
- `ML-DSA-87+ECDSA-P384`
- `ML-DSA-65+ECDSA-BP256`
- `ML-DSA-87+ECDSA-BP384`

PQ-only signing (no hybrid, conservative), `rnp.h:4134–4135`:

- `SLH-DSA-SHA2`  (Sphincs+)
- `SLH-DSA-SHAKE`

Notable: **librnp does not expose PQ-only KEM** (just ML-KEM without a
classical partner). That is deliberate and correct — the hybrids provide
classical security if the PQ algorithm breaks, and PQ security if the
classical algorithm breaks. We follow the same policy: never emit PQ-only
encryption; always hybrid.

## Design

### Phase 1: detect and use (default on, transparent)

When encrypting, librnp picks the PKESK algorithm per recipient based on
the recipient's encryption subkey. We do nothing explicit — just verify
it works. Tests:

- Generate a hybrid KEM key (fixture), encrypt to it, decrypt, round-trip.
- Mixed recipient: classical X25519 + hybrid `ML-KEM-768+X25519` in one
  encryption op → two PKESK packets, each with the right algorithm.

When verifying signatures, librnp's verifier handles hybrid signing keys
transparently. No work in our codebase.

### Phase 2: opt-in hybrid key generation

Add to the key generation form (under "Advanced"):

```
Post-quantum hybrid key
───────────────────────
( ) Classical (default; Ed25519 primary + Curve25519 encryption)
(•) Post-quantum hybrid (recommended for long-term confidentiality)
    Primary:    ML-DSA-65+ED25519
    Encryption: ML-KEM-768+X25519
( ) Post-quantum only (SLH-DSA primary; no PQ encryption available)
    Primary: SLH-DSA-SHA2
    Note: messages to you will fall back to classical encryption; your
    signatures are PQ-secure.

About post-quantum: ...
```

The "About post-quantum" disclosure:

> Post-quantum cryptography protects against future quantum computers that
> could break today's public-key crypto. For email, this matters because
> encrypted mail may be stored for years; an attacker who stores your
> ciphertext today could decrypt it when a quantum computer becomes
> available.
>
> Hybrid mode combines a classical algorithm (e.g., X25519) with a
> post-quantum algorithm (e.g., ML-KEM-768). The result is secure if
> **either** algorithm remains unbroken — classical-OR-PQ security.
>
> Trade-offs:
> - Larger keys and signatures (a hybrid primary is ~3 KB; classical is
>   ~100 bytes).
> - Some older PGP software may not read PQ keys correctly; verify with
>   your correspondents before relying on it.
> - SLH-DSA signatures are very large (~50 KB); use sparingly.

Default: classical, with the option to migrate later via the key
transition wizard (05).

### Phase 3: rotation from classical to hybrid

The key transition wizard (05) handles algorithm changes. A user with an
Ed25519 key can run the wizard to generate a new `ML-DSA-65+ED25519 +
ML-KEM-768+X25519` key, sign it with the old key, and notify contacts.

### Documentation

- `docs/SECURITY-MODEL.md` adds a "Post-quantum considerations" section
  explaining harvest-now-decrypt-later.
- `docs/post-quantum.md` (new) explains the algorithms, the trade-offs,
  and the migration path.
- FAQ entry: "Should I generate a post-quantum key?"

## Tests

- Generate `ML-DSA-65+ED25519` + `ML-KEM-768+X25519` keypair; round-trip
  sign/verify and encrypt/decrypt.
- Verify a Thunderbird/Sequoia-signed message from a hybrid signer key
  (fixture).
- Mixed-recipient encryption: classical recipient + hybrid recipient →
  each gets the correct PKESK; round-trip both decryptions.
- Key transition from Ed25519 → hybrid: transition signature (05)
  verifies.
- Performance: hybrid keygen < 5 seconds on M1; hybrid encrypt of 1 MB
  payload < 100 ms (assert no regression vs. classical).

## Acceptance criteria

- A user who opts in to a hybrid key can encrypt and sign with
  correspondingly equipped contacts without thinking about it.
- A user who stays on classical sees no behavior change.
- Round-trip interop verified with at least one other OpenPGP
  implementation that supports PQ hybrids (Sequoia, GnuPG 2.3+, or
  Thunderbird with OpenPGP-Compose-PQ enabled).

## Notes / risks

- **Interop risk**: PQ OpenPGP is still maturing (crypto-refresh §13
  algorithms; draft-ietf-openpgp-pqc). Some clients may not parse hybrid
  keys. For 1.0 we should ship Phase 1 (use) but consider Phase 2
  (generate) experimental until interop is verified.
- **Algorithm choices**: `ML-KEM-768+X25519` is the TLS standard and the
  safest default. `ML-DSA-65+ED25519` matches. SLH-DSA is for users who
  don't trust lattice-based signatures; it's the conservative option.
- **CVE policy**: task 09-polish requires librnp updates within 7 days of a
  CVE. PQ algorithms are new; expect more CVEs in the first few years.
  Document that the librnp pin will track upstream PQ fixes promptly.
- **Key size**: a hybrid key with UIDs and revocation cert can be 10+ KB.
  Autocrypt headers grow correspondingly; test that Thunderbird accepts
  large Autocrypt headers.
- **Performance**: Botan 3.x PQ implementations are reasonably fast but
  not always constant-time. Document this in `docs/SECURITY-MODEL.md`.
- **Future algorithms**: ML-KEM and ML-DSA are FIPS 203/204
  standardized. Newer algorithms (HQC, Falcon) may appear in librnp
  later; the migration path is the key transition wizard.
