# 05 — Key lifecycle: rotation, expiry, revocation

Status: pending · Milestone: M3 · Depends on: 04

## Goal

Keys never silently expire and rotation is a guided, safe flow: subkey
rotation, primary expiry extension, automatic revocation certificates, and
proactive expiry nudges — in a new `KeyLifecycle` SPM target (swift
test-able) + container-app UI.

## Design

- `KeyLifecycle` (depends on `Rnp`, `MailSecurityEngine.KeyManager`):
  - `rotateEncryptionSubkey(key:)`: generate new encryption subkey (match
    primary algo family: RSA→RSA-3072, Ed25519→cv25519), set old subkey
    expiry to now+grace (30d), save; return summary for UI.
    FFI: subkey generation via `rnp_op_generate_subkey_create` (check rnp.h);
    expiry via the setter added in task 04.
  - `rotateSigningSubkey(key:)`: same for signing subkey.
  - `extendExpiry(key:, newDate:)`: sets primary expiry (librnp ≥0.18
    re-hashes self-signatures away from weak hashes automatically — call this
    out in UI copy as a security upgrade for old keys).
  - `revocationCertificate(for:) -> ArmoredKey`: produce+store at key
    creation time (hook into KeyManager.generate), export on demand.
    FFI: `rnp_key_revoke` with reason into an output (check exact signature
    in rnp.h — it writes the revoked key/revocation to an output stream).
  - `revoke(key:, reason:)`: mark revoked locally, prompt to publish (task 06)
    and to notify correspondents (compose template).
  - `expiryReport() -> [KeyExpiryItem]`: keys/subkeys expiring within 60d or
    expired — drives the nudge badge + Activity tab entries.

## UI

- Keys detail view: "Rotate encryption subkey" / "Rotate signing subkey"
  buttons with explainer sheet (what changes, what correspondents see: they
  must refresh your key — offer publish after rotation via task 06).
- Expiry banner in Keys tab when `expiryReport()` is non-empty:
  "Key … expires in 12 days" + [Extend…] [Rotate subkey…].
- Revocation flow: scary-confirm dialog (type fingerprint to confirm),
  shows the revocation cert save dialog FIRST, then revokes, then offers
  publish.

## Tests

- Round-trip: generate → rotate encryption subkey → old data still
  decryptable during grace, new encryptions use new subkey (verify via
  `Rnp.encrypt` then inspect with `rnp --list-packets` semantics in-test:
  assert recipient subkey fingerprint of the PKESK matches the NEW subkey —
  via `rnp_op_encrypt` + `rnp_dump_packets` or FFI recipient listing).
- extendExpiry: expiry moves, self-signature hash is SHA-256+ for an imported
  SHA-1-selfsig fixture key (add fixture under Tests fixtures).
- Revocation cert generated at creation decrypts/verifies as a revocation
  signature (validate structure via dump).
- expiryReport thresholds: fake keyring with crafted expiry offsets.
- Run full suite against BOTH librnp installs (v0.18.1 + main).

## Acceptance criteria

- All flows above covered by `swift test`; UI strings reviewed for
  non-expert clarity; no flow can leave a key without EITHER a revocation
  cert on disk or an explicit user opt-out.

## Notes

- v4 keys only in these flows (v6 is the advanced toggle — out of scope).
- Keep grace period + thresholds as `KeyLifecycle.Configuration` constants,
  not settings UI (avoid preference creep).
