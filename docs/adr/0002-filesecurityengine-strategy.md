# ADR-0002: FileSecurityEngine uses Strategy pattern

Date: 2026-08-03
Status: Accepted

## Context

`KeysManager` originally had three ad-hoc methods for file ops:
`encryptFile`, `decryptFile`, `verifyFile`. Adding `signFile`,
`signFileDetached`, `verifyDetached`, and password-based variants was
going to balloonon the type. Each new verb meant: a new method on
`KeysManager`, a new error case in `FileToolsError`, a new switch
branch in the UI, new App Intent plumbing. Five different concerns
touched for every new operation.

Alternatives considered:

1. **Single mega-method with an op parameter.** Rejected — switches
   breed switches; one `perform(op:)` would force every call site to
   reason about every operation.
2. **One class per operation, no shared engine.** Rejected — common
   concerns (keyring lookup, error mapping) would duplicate; no
   single entry point for tests.
3. **Protocol-oriented with dynamic dispatch.** Rejected for now —
   Swift's enum-with-associated-values gives us closed-set exhaustiveness
   for free; protocol-based dispatch would lose the compiler check.

## Decision

Introduce `FileSecurityEngine` (in
`MailExtensionsContainer/Model/FileSecurity/FileSecurityEngine.swift`)
as the deep module. Operations are cases of `FileSecurityOperation`
enum; each case has its own `Request` struct and its own Strategy
type. The engine's `perform(_:)` is a single router switch — the
only place that grows when adding a verb.

```swift
public enum FileSecurityOperation {
    case encrypt(EncryptRequest)
    case encryptWithPassword(EncryptWithPasswordRequest)   // added later, no existing edits
    case decrypt(DecryptRequest)
    case sign(SignRequest)
    case signDetached(SignRequest)
    case signCleartext(SignRequest)                         // added later
    case verify(VerifyRequest)
    case verifyDetached(VerifyDetachedRequest)
}

public final class FileSecurityEngine {
    public func perform(_ op: FileSecurityOperation) throws -> FileSecurityResult {
        switch op {
        case .encrypt(let r):              return try EncryptStrategy.perform(r, ...)
        case .encryptWithPassword(let r):  return try EncryptWithPasswordStrategy.perform(r, ...)
        // ... one line per verb
        }
    }
}
```

`KeysManager.encryptFile` / `decryptFile` / etc. become thin wrappers
that delegate to the engine. New verbs add: one Request struct + one
Strategy + one enum case + one switch line. No existing code changes.

## Consequences

Positive:
- OCP-compliant: existing strategies are closed for modification.
- MECE: file ops live in exactly one module, not on `KeysManager`.
- The router switch is the only place that "knows about all verbs";
  everything else is single-verb-focused.
- Tests target strategies directly without MailKit/AppKit dependency.

Negative:
- Slight indirection: `KeysManager.encryptFile` → `engine.perform(.encrypt(...))`.
  Acceptable — the indirection is one hop and adds testability.

Neutral:
- The router switch does grow with each verb. This is intentional;
  closed-set exhaustiveness is the point.

## References

- TODO.complete/05-sign-verify-files.md
- TODO.complete/14-password-based-encryption.md
- Code: `MailApp/MailExtensionsContainer/Model/FileSecurity/FileSecurityEngine.swift`
