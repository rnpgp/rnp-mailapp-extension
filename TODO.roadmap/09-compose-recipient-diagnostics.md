# 09 — Compose-window per-recipient diagnostics

Status: pending · Tier: B · Depends on: nothing (but uses the data already
computed by `MessageSecurityCore`)

## Goal

In the compose window, show per-recipient status so the user knows — before
they hit Send — exactly what will happen. Today, problems surface only at
send time, as a single error.

## Why this is Tier B

The compose window is where encryption decisions are made. Surfacing the
per-recipient state ("Alice verified, Bob missing, Carol expired") converts
the encryption UX from "guess what will happen" to "see what will happen."
This is the second-most-important UX improvement (after disaster recovery)
for users to actually trust the encryption.

MailKit's `MEOutgoingMessageEncodingStatus` already gives us
`canSign` / `canEncrypt` / `addressesFailingEncryption`. We need to expose
more of what `MessageSecurityCore` already computes (trust state, expiry,
conflicts) and surface it in the compose UI.

## Design

### Data source

Extend `HandlerEncodingStatus` with a richer per-recipient view:

```swift
public struct RecipientStatus: Equatable, Identifiable {
    public enum State: Equatable {
        case verified
        case unverified
        case missingKey
        case expired(daysUntilExpiry: Int?)
        case keyChangedConflict
        case archived  // only an archived key exists for this address
        case revoked
    }

    public let address: String
    public let displayName: String?
    public let state: State
    public let fingerprintShort: String?  // last 16 hex chars
    public let algorithmLabel: String?    // "Ed25519", "RSA-3072"
    public let suggestedAction: SuggestedAction?

    public var id: String { address }
}

public enum SuggestedAction: Equatable {
    case fetchFromKeyserver
    case extendOwnKey
    case rotateOwnSubkey
    case verifyFingerprint
    case resolveConflict
    case restoreFromArchive
    case addToAllowedPlaintextRecipients
}
```

`MessageSecurityCore.getEncodingStatus` already does the per-recipient
computation; extend it to return `[RecipientStatus]`.

### Compose UI

The compose window cannot be redesigned from inside a Mail extension —
MailKit gives us a banner area. Use it.

A compact summary line in the banner:

```
🔒 Encrypt to 3 of 4 recipients.
   ✓ alice@x  ✓ bob@x   ✓ carol@x
   ⚠ dave@x — no key  [Lookup]
```

Clicking the line expands a per-recipient panel with details and per-row
action buttons. Each row also has a small contextual menu (right-click or
"…" button) for less-common actions (verify fingerprint, view key detail,
allow plaintext).

For `addressesFailingEncryption` (MailKit's existing field), each address
shows its specific reason via the richer `RecipientStatus.state` — not just
"failing."

### Recommended-action banner

Above the per-recipient panel, a single-line recommendation:

- All recipients have verified keys: "Encrypt and sign to N recipients."
- All recipients have keys but some are unverified: "Encrypt to N
  recipients. Verify fingerprints to confirm identities." with [Verify…] for
  the unverified ones.
- One recipient missing a key: "Encrypt to N-1. `<addr>` has no key —
  [Lookup] or [Send plaintext to all]."
- One recipient has a conflict: "Encryption blocked for `<addr>` — key
  changed. [Review conflict]."
- Own signing key expired: "Your signing key expired `<date>`. [Extend]
  [Send unsigned]."

### Reply-context awareness

When the user is replying to an encrypted message they received:

- If the original sender is in the To field and has a usable key, default
  `shouldEncrypt = true` and `shouldSign = true`.
- Surface a one-line note: "Replying to an encrypted message; defaults set
  to encrypted + signed."

MailKit's compose context may already do this; verify before implementing.

### Allow-list for plaintext-to-some

When one or more recipients have no key, the user can choose to send
plaintext to those while encrypting to the rest. This requires either
sending separate messages (see `06-bcc-handling.md`'s option 1 pattern)
or sending a single plaintext message (no encryption to anyone). Surface
the choice clearly.

For 1.0, only the single-plaintext-message fallback is supported; the
"send encrypted to some, plaintext to others" requires multiple SMTP sends
and is the same code path as BCC-splitting in 06.

## Tests

- Each `RecipientStatus.State` is produced for the right underlying
  condition.
- The recommendation banner copy matches the state combination.
- Reply-to-encrypted default: the context correctly defaults
  `shouldEncrypt` and `shouldSign`.
- Clicking [Lookup] triggers a `KeyServerService.discoverByEmail`.
- Clicking [Extend] opens the expiry-extension sheet from
  `04-key-expiry-recovery.md`.

## Acceptance criteria

- The user can see, at any moment while composing, which recipients will
  receive encrypted mail and which will not.
- Every per-recipient warning has a one-click action.
- The recommendation banner never uses the words "error" or "failed" when
  there is a usable path forward; it states the path.
- The compose UX review document (in `docs/`) shows screenshots of each
  state and the corresponding copy.

## Notes / risks

- MailKit's compose banner area is limited; the per-recipient panel may
  have to be a popover rather than always-visible. Test with realistic
  recipient counts (1, 5, 20).
- Don't over-nag. A green "all good" banner is fine; don't pop a sheet for
  unverified-but-usable keys.
- The `[Lookup]` action should be rate-limited (already done elsewhere in
  the engine via `MessageSecurityCore`'s fetch throttling).
- VoiceOver labels for each status chip are required (a11y audit item from
  TODO.impl 09).
