# 07 — Autocrypt: interop with K-9, Thunderbird, Delta Chat

Status: pending · Tier: B · Depends on: 10 (multi-UID, for the right UID to
be exported)

## Goal

Emit `Autocrypt:` headers on outgoing mail and parse them on incoming mail,
implementing Autocrypt level 1. This makes RNP interoperate with the modern
opportunistic-encryption ecosystem — Thunderbird, K-9 Mail, Delta Chat,
Mailpile, and others — without users having to think about keyservers.

## Why this is Tier B

Without Autocrypt, every Thunderbird/Android user corresponding with an
RNP user has to manually fetch the RNP user's key from a keyserver, and
vice versa. Most users don't. Autocrypt automates the exchange inside the
email itself, with conservative defaults.

This is also the foundation for `08-mailbox-key-scan`, which reads
Autocrypt headers from received mail to populate the keyring.

## Design

### Emit

In `MessageEncoder.encodePGPMime` and `encodeInline`, when the sender has
an active signing key for the From address:

```swift
if let signer, let fromAddress = primaryFromAddress(in: topHeaders) {
    let autocryptKey = try rnp.exportAutocrypt(
        key: signer,
        uid: fromAddress  // rnp_key_export_autocrypt lets you pick the UID
    )
    topHeaders.append(.init(
        name: "Autocrypt",
        value: "addr=\(fromAddress); prefer-encrypt=mutual; keydata=\(base64(autocryptKey))"
    ))
}
```

Use `rnp_key_export_autocrypt` (verified in `Sources/CRnp/rnp/rnp.h:1293`):
it produces the minimal Autocrypt key (5 packets: primary, UID, self-sig,
encryption subkey, subkey self-sig), base64-encoded for the header.

`prefer-encrypt=mutual` is the default. Make it configurable per-account
in Settings → Encryption → "Default Autocrypt preference":
- `mutual` (default; opportunistically encrypt when the recipient also
  advertises mutual).
- `nopreference` (encrypt when the user explicitly asks).
- `encrypt` (never automatically; user-initiated only — uncommon).
- `disable` (don't emit Autocrypt headers at all).

### Parse

In `MessageDecoder.decodeUnlocked`, after parsing the MIME:

```swift
if let header = parsed.headers.first(where: { $0.name.lowercased() == "autocrypt" }) {
    try? autocryptStore.observe(header: header.value, date: parsed.date)
}
```

`AutocryptStore` (new SwiftPM target) implements the Autocrypt level 1
algorithm:

- For each `(addr, message_date)` observed, the latest valid key wins
  (newer message replaces older).
- Invalid keys (failed parse, expired, revoked) are ignored.
- Keys are stored in a separate cache keyed by email address, NOT
  automatically merged into the main keyring — that happens only when the
  user sends encrypted mail to that address for the first time.

### `prefer-encrypt=mutual` handling

When composing and the user has not explicitly chosen to encrypt:

- If for every recipient, the Autocrypt store has `prefer-encrypt=mutual`
  (or the keyring has a verified key for them), default `shouldEncrypt =
  true` and surface "Encryption on (Autocrypt mutual)".
- If any recipient has `prefer-encrypt != mutual` or is unknown, default
  to plaintext with a discoverable toggle.

This is "opportunistic encryption" — the user can always override.

### Autocrypt Setup Message

Out of scope for 1.0 but reserved: the Autocrypt Setup Message (a special
encrypted MIME part that lets the user transfer their secret key between
devices) is a future feature. Document the limitation; for now, users use
the recovery flow from `01-disaster-recovery.md`.

## Tests

- Emit: generate a key, encode a message, parse the `Autocrypt:` header
  and verify the keydata parses to a 5-packet Autocrypt key via
  `rnp_dump_packets_to_json`.
- Parse: a fixture message with an Autocrypt header updates the
  `AutocryptStore`; a later message from the same sender with a newer key
  replaces it; a malformed header is ignored.
- Mutual: a sender with `prefer-encrypt=mutual` and a recipient with
  `prefer-encrypt=mutual` → compose defaults to encrypted.
- Thunderbird interop: a fixture Thunderbird-generated Autocrypt header
  round-trips (fixture committed under `Tests/Fixtures/autocrypt/`).
- Gossip keys (`Autocrypt-Gossip` header in CC'd multi-recipient mail) —
  level 1.1; optional, document and skip in tests for now.

## Acceptance criteria

- A Thunderbird user receiving mail from an RNP user automatically picks
  up the RNP user's key (manually verified with a test send).
- An RNP user receiving mail from a Thunderbird Autocrypt user
  automatically has the key available for opportunistic encryption.
- The `Autocrypt:` header is present on every signed or encrypted outgoing
  message (and on plaintext replies when the user has `prefer-encrypt=mutual`).
- Documentation: a new `docs/autocrypt.md` page explains what we emit and
  parse, the `prefer-encrypt` settings, and the relationship to keyservers.

## Notes / risks

- The base64 in the `Autocrypt:` header can be large (RSA-3072 ≈ 2 KB;
  Ed25519+cv25519 ≈ 300 bytes). For long keys consider folding per RFC
  5322; librnp's exporter should produce already-folded output, but verify.
- The Autocrypt store is per-account in the long run (different From
  addresses see different stores). For 1.0, a single store keyed by email
  is fine.
- "Latest valid key wins" can be attacked by an attacker who can forge
  mail from the sender. Autocrypt explicitly accepts this risk for the
  opportunistic-encryption use case; out-of-band verification (see
  `07-trust-verification.md`) remains the path to strong trust.
- Autocrypt and protected headers (Memory Hole) compose well; the
  `Autocrypt:` header stays at the outer level (it's routing metadata).
