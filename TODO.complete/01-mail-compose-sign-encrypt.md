# 01 — Mail compose: sign + encrypt outgoing messages

**Priority**: P0
**Status**: in progress — engine implementation shipped; verification +
default-policy UX remaining
**Effort**: M (downgraded from L — most of the work is already done)
**Dependencies**: 12 (specs/tests), 5 (sign/verify files — sign logic reuse)

## Problem

**Earlier diagnosis was wrong.** Mail compose IS implemented end-to-end:

- `MessageSecurityHandler.encode` (MailPlugin) → calls
- `MessageSecurityCore.encode` (MailSecurityEngine) → calls
- `MailSecurityEngine.encode(_:)` → librnp signs/encrypts and produces
  PGP/MIME (RFC 3156) output

The flow works when Mail's compose window has "Sign" and "Encrypt"
toggled on. What's actually missing:

1. **Verification.** No end-to-end test exists that confirms sign +
   encrypt + send + receive + decrypt works on a real Mail setup.
2. **Default policy.** Today the user has to manually toggle "Sign" and
   "Encrypt" in Mail's compose window for every message. There's no
   per-account default ("always sign as this identity").
3. **Visibility.** Users don't know the buttons exist. No in-app
   guidance for first-time compose.

## Goals / non-goals

**Goals**
- End-to-end test proving sign + encrypt + send + decrypt works
- Per-account default policy (sign always, encrypt when keys available)
- In-app onboarding hint pointing users to Mail's compose buttons

**Non-goals**
- Re-implementing encoding (already done)
- Per-recipient key picker UI in compose (later TODO)
- Custom compose-time UI (MailKit doesn't allow it anyway)

## Design

The deep module already exists:

```
MailSecurityEngine.encode(EncodingRequest) throws -> EncodedMessage
```

Adding new policies = new fields on `EncodingRequest` or new methods on
`MailSecurityEngine`. The encode path itself doesn't change (OCP).

### Default policy storage

Per-account policy lives in the existing `AccountKeyedPolicyStore`
(Autocrypt prefs). Add a sibling:

```
Sources/MailSecurityEngine/
└── OutgoingMessageSecurityPolicyStore.swift
    ├── policy(for account: String) -> OutgoingMessageSecurityPolicy
    └── setPolicy(_:for:) throws
```

`OutgoingMessageSecurityPolicy` is a struct with `.sign`,
`.encryptWhenKeysAvailable`, `.requireVerifiedKeys` flags.

`MessageSecurityHandler.getEncodingStatus` reads this store to set
initial `shouldSign` / `shouldEncrypt` defaults when Mail asks.

## Implementation plan

1. ✅ Audit existing `MessageSecurityCore.encode` — works
2. Author `Tests/MailSecurityEngineTests/EndToEndEncodeDecodeTests.swift`
   (sign + encrypt → round-trip → decrypt + verify)
3. Add `OutgoingMessageSecurityPolicyStore`
4. Wire `getEncodingStatus` to read the policy
5. Add UI in `EncryptionSettingsView` for per-account defaults

## Acceptance criteria

- [ ] End-to-end test passes in CI
- [ ] Per-account default policy UI in Encryption Settings
- [ ] Replying to an encrypted thread auto-enables encryption
- [ ] Specs in `docs/specs/mail-compose.md`

## Open questions

- **Should we sign by default if the user has a signing key?** Still
  needs product decision.
- **Reply-to-encrypted-thread auto-encrypt.** Still needs investigation.

## Out of scope

- PGP/Inline output (PGP/MIME only)
- Per-recipient key picker UI

## References

- Existing encode path: `MailApp/MailPlugin/MessageSecurityHandler.swift:94`
- Engine: `Sources/MailSecurityEngine/MailSecurityEngine.swift:294`
- Core orchestrator: `Sources/MailSecurityEngine/MessageSecurityCore.swift:339`
