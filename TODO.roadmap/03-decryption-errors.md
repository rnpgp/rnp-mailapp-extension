# 03 — Decryption errors that tell the user what to do next

Status: pending · Tier: A · Depends on: 02 (archive state)

## Goal

When a message fails to decrypt, the user should know **why** and **what to
do about it**, in one sentence with at most two buttons. Today the engine
returns a generic `MailSecurityError.malformedMessage("undecryptable
content")` and the Mail banner shows essentially that.

## Why this is Tier A

A user who sees "undecryptable content" on a message they need to read does
the same thing every time: assumes the product is broken, opens a support
ticket or posts a bad review. 90% of the time the actual cause is one of:

- The key isn't in the keyring anymore (was archived, deleted, or never
  imported).
- The passphrase is wrong.
- The message was tampered with.
- The sender used an algorithm we don't support (or a v6-only feature we
  haven't enabled).
- The message was encrypted with a symmetric passphrase (no public-key
  recipient).
- The ASCII armor is malformed.

Each one has a different recovery path. Surface them.

## Design

### Error taxonomy

Replace the generic error with a typed enum in `MailSecurityEngine`:

```swift
public enum DecryptionFailure: Error, Equatable {
    /// We don't have any of the recipient keys. Lists the key IDs we
    /// observed in PKESK packets so the user can correlate.
    case missingSecretKey(pkeskKeyIDs: [String], suggestedAction: MissingKeyAction)

    /// The passphrase didn't unlock any key in the keyring.
    case wrongPassphrase

    /// librnp reported an integrity-protection failure (MDC mismatch, AEAD
    /// authentication failure). The message was tampered with or corrupted.
    case integrityFailure

    /// The message was encrypted with an algorithm or version we don't
    /// support (e.g., a future v6-only algorithm). Lists the offending
    /// algorithm name.
    case unsupportedAlgorithm(String)

    /// The message is symmetrically encrypted (no public-key recipient) and
    /// needs a passphrase.
    case symmetricEncryption

    /// ASCII armor is malformed. Best-effort: line number if known.
    case malformedArmor(detail: String)

    /// Catch-all for errors librnp doesn't classify. Surface the librnp
    /// string but downgrade the prominence of the "unknown" copy.
    case unknown(librnpMessage: String)
}

public enum MissingKeyAction: Equatable {
    case fetchFromKeyserver(keyID: String)
    case restoreFromArchive(fingerprint: String, archivedDate: Date)
    case importKeyManually
    case none  // we don't have a key ID to act on (hidden-recipient v6 PKESK)
}
```

### Producing the errors

In `MessageDecoder.decodePGPMimeEncrypted`, when `rnp.verifyDetailed` throws
or returns an empty payload:

1. Call `rnp_dump_packets_to_json` on the ciphertext (librnp FFI; verified
   in `Sources/CRnp/rnp/rnp.h`). Parse the JSON for `pkesk` packets; extract
   the recipient key IDs.
2. For each key ID, check the keyring:
   - Present and active → wrong passphrase path.
   - Present and archived → `restoreFromArchive(fingerprint:,
     archivedDate:)`.
   - Absent → `fetchFromKeyserver(keyID:)` (the engine already has
     `KeyServerService`).
3. If no key IDs are visible (v6 PKESK with anonymous recipients), fall back
   to "encrypted to a hidden recipient; try refreshing your keyring."
4. If dump shows an unknown algorithm name, classify as
   `unsupportedAlgorithm`.

For inline-PGP, the same logic runs on the armor block instead of a MIME
part.

### Surfacing in Mail

The Mail banner already has security-information plumbing. Extend the
`SecurityInformation` struct with a `decryptionFailure: DecryptionFailure?`
field and a mapping to (banner text, primary action, secondary action):

| Failure | Banner text | Primary action | Secondary |
|---|---|---|---|
| `missingSecretKey` (key ID known) | "Encrypted to a key you don't have (key ID <hex>). [Fetch]" | Fetch from keyserver | Import manually… |
| `missingSecretKey` (archived) | "Encrypted to your archived key (<date>). [Restore]" | Restore from archive | — |
| `missingSecretKey` (anonymous v6) | "Encrypted to a hidden recipient. Refresh your keyring and try again." | Refresh all | — |
| `wrongPassphrase` | "Couldn't unlock your keyring. [Enter passphrase]" | Enter passphrase | Reset passphrase… |
| `integrityFailure` | "This message was tampered with. Do not trust its contents." | — | Report… |
| `unsupportedAlgorithm` | "Encrypted with `<algo>`, which this version of RNP doesn't support." | Check for updates | Open message source |
| `symmetricEncryption` | "Encrypted with a passphrase. [Enter passphrase]" | Enter passphrase | — |
| `malformedArmor` | "This message's PGP armor is malformed (<detail>)." | Open message source | — |
| `unknown` | "Couldn't decrypt this message. <librnp string>" | Open diagnostics | Report… |

### Symmetric-passphrase path

For `symmetricEncryption`, prompt for a passphrase, call
`rnp.decryptSymmetric(message:passphrase:)` (wrapper already exposes
symmetric decrypt via librnp). Cache nothing — the user re-enters on every
read unless they explicitly opt to remember in Keychain.

## Tests

For each failure type, a fixture ciphertext that triggers it, and an
assertion on the produced `DecryptionFailure` and the resulting banner
view-model.

- `missingSecretKey`: encrypt to a key not in the keyring; assert the
  banner shows the right key ID and the fetch action.
- `restoreFromArchive`: archive a key, then attempt to decrypt an old
  message encrypted to it; assert the banner offers "Restore from archive."
- `wrongPassphrase`: lock the keyring with a wrong passphrase; assert the
  banner offers "Enter passphrase."
- `integrityFailure`: flip one byte in an encrypted message; assert the
  tamper banner (and that we never display a partial decryption).
- `unsupportedAlgorithm`: synthesize is not trivial — skip in CI; cover
  with a unit test on the mapping function given a fake librnp string.
- `symmetricEncryption`: encrypt with `gpg --symmetric` (or librnp
  equivalent) and verify the passphrase flow.

## Acceptance criteria

- The string "undecryptable content" no longer appears in any user-visible
  surface. Grep the codebase for it and confirm.
- Every decryption failure has a primary action button that either resolves
  the failure (fetch, restore, enter passphrase) or explains why the
  message is unrecoverable (tampered, unsupported algorithm).
- For a sampled corpus of real-world PGP/MIME messages (the corpus from
  task 09-polish), the failure categorization is correct on ≥95% of
  un decryptable cases.

## Notes / risks

- The dump-packets call adds ~1–5 ms per decryption failure. Acceptable.
  Only call it on the failure path.
- `rnp_dump_packets_to_json` returns the recipient key IDs in the form
  librnp prints them (typically 16- or 8-hex key IDs). Match those against
  the keyring via `RnpKey.keyID` (add a getter if not present).
- Don't claim the message is "tampered" if we're not certain. MDC failures
  are very rare on legitimate mail; if we see them, integrity failure is
  the right call. AEAD authentication failures likewise. Other librnp
  errors during decryption should fall to `unknown`, not `integrityFailure`.
- The "Report…" action composes a feedback template with the librnp error
  string and the message's first 500 bytes of header (NEVER the body).
  That's enough for triage.
