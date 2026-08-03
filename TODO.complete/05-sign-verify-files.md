# 05 — Sign + verify file operations

**Priority**: P1
**Status**: shipped
**Effort**: S
**Dependencies**: none

## Problem

File Tools only encrypted and decrypted. Two halves of file security were
missing:

- **Signing** a file so a third party can prove it came from you
- **Verifying** a signature to confirm authenticity

Without these, RNP can't cover the document-authenticity use case (legal
filings, software releases, contracts). Users had to fall back to GnuPG
CLI for signing.

## Goals / non-goals

**Goals**
- Sign any file with the user's signing subkey (armored, inline PGP)
- Detached signatures (.sig) for files that shouldn't be modified
- Verify any PGP signature (inline or detached); show signer identity
- Same UX as encrypt/decrypt (drag in, drag out)
- App Intents for Finder Quick Action: "Sign File" + "Verify Signature"

**Non-goals**
- Cleartext signatures (only useful for text; covered by inline)
- Multiple-signature support (one signer per file for v1)
- Signature subpacket UI (notation, key expiration, etc.) — advanced

## Design

### Deep module: `FileSecurityEngine`

Replaces the previous ad-hoc `encryptFile` / `decryptFile` / `verifyFile`
methods on `KeysManager`. One MECE module, one operation per strategy:

```
MailApp/MailExtensionsContainer/Model/FileSecurity/
├── FileSecurityEngine.swift            (deep module — entry point)
├── FileSecurityOperation.swift         (enum: encrypt/decrypt/sign/verify/signDetached/verifyDetached)
├── FileSecurityResult.swift            (sum type: success(payload, metadata) | failure(reason))
├── Strategies/
│   ├── EncryptStrategy.swift           (handler for .encrypt)
│   ├── DecryptStrategy.swift           (handler for .decrypt)
│   ├── SignStrategy.swift              (handler for .sign)
│   ├── SignDetachedStrategy.swift      (handler for .signDetached)
│   ├── VerifyStrategy.swift            (handler for .verify, .verifyDetached)
│   └── FileSecurityStrategy.swift      (protocol: perform(_:) throws -> FileSecurityResult)
└── FileSecurityError.swift             (keyringUnavailable, recipientNotFound, etc.)
```

**OCP**: Adding "encrypt with password" (symmetric) = adding
`EncryptWithPasswordStrategy`. Existing strategies don't change.

**MECE**: Each operation lives in exactly one strategy file. The engine
dispatches by operation type; no operation logic leaks into the engine.

### Engine signature

```swift
public final class FileSecurityEngine {
    private let keyManager: KeyManager

    public init(keyManager: KeyManager) { self.keyManager = keyManager }

    public func perform(_ operation: FileSecurityOperation) throws -> FileSecurityResult {
        try strategy(for: operation).perform(operation, keyManager: keyManager)
    }

    private func strategy(for operation: FileSecurityOperation) -> FileSecurityStrategy {
        switch operation {
        case .encrypt:              return EncryptStrategy()
        case .decrypt:              return DecryptStrategy()
        case .sign:                 return SignStrategy()
        case .signDetached:         return SignDetachedStrategy()
        case .verify, .verifyDetached: return VerifyStrategy()
        }
    }
}
```

The switch is *intentional* — it's a router, not business logic. Adding
a strategy means adding a case + a strategy file. No existing code is
modified beyond this switch (acceptable per OCP — routers dispatch).

### Operation model

```swift
public enum FileSecurityOperation {
    case encrypt(EncryptRequest)
    case decrypt(DecryptRequest)
    case sign(SignRequest)
    case signDetached(SignRequest)
    case verify(VerifyRequest)
    case verifyDetached(VerifyDetachedRequest)
}

public struct SignRequest {
    public let payload: Data
    public let signingKeyFingerprint: String
    public let armored: Bool       // default true
}

public struct VerifyRequest {
    public let signedPayload: Data
}

public struct VerifyDetachedRequest {
    public let payload: Data
    public let detachedSignature: Data
}

public struct FileSecurityResult {
    public enum Kind {
        case ciphertext(Data)
        case plaintext(Data)
        case signedPayload(Data)
        case detachedSignature(Data)
        case verification(verification: SignatureVerification, payload: Data?)
    }
    public let kind: Kind
}

public struct SignatureVerification {
    public let isValid: Bool
    public let signerFingerprint: String?
    public let signerUserID: String?
    public let signedAt: Date?
}
```

### UI changes (`FileToolsView`)

Add two modes to the existing `Mode` enum: `.sign(file)` and
`.verify(file)`. Each mode has its own panel like encrypt/decrypt panels.
Drag-drop is shared. Result banner adapts to the operation kind.

### App Intents

Two new intents in `FileEncryptionIntents.swift` (rename file →
`FileSecurityIntents.swift`):

```swift
struct SignFileIntent: AppIntent {
    @Parameter(title: "File") var file: IntentFile
    @Parameter(title: "Signing Key") var signingKey: RecipientEntity
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> { ... }
}

struct VerifyFileIntent: AppIntent {
    @Parameter(title: "File") var file: IntentFile
    func perform() async throws -> some IntentResult & ReturnsValue<VerifyResultSnippet> { ... }
}
```

## Implementation plan

1. ✅ Build `FileSecurityEngine` deep module (shipped)
2. ✅ Implement all 5 strategies (shipped)
3. ✅ Refactor `KeysManager.encryptFile`/`decryptFile`/`verifyFile` to
      delegate to the engine (shipped)
4. ✅ Add sign + signDetached + verify modes to `FileToolsView` (shipped)
5. ✅ Add `SignFileIntent` + `VerifyFileIntent` App Intents (shipped)
6. Specs in `docs/specs/file-security.md`

## Acceptance criteria

- [ ] Sign a file → output is inline-armored PGP signature
- [ ] Sign a file detached → output is `.sig` file
- [ ] Verify an inline-signed file → shows signer + validity
- [ ] Verify a detached signature → prompts for the original file
- [ ] Tampered payload → verification fails clearly
- [ ] App Intent: right-click file in Finder → Quick Actions → Sign File
- [ ] Specs in `docs/specs/file-security.md`
- [ ] Tests: `Tests/FileSecurityEngineTests/` (one per strategy)

## Open questions

- **Default signing key.** Use the user's primary signing subkey, or
  ask? Primary is the right default — most users have one key.
- **Detached signature file naming.** `foo.txt` → `foo.txt.sig`? Yes,
  GnuPG convention.

## References

- Code: `MailApp/MailExtensionsContainer/Model/FileSecurity/`
- UI: `MailApp/MailExtensionsContainer/View/FileTools/FileToolsView.swift`
- App Intents: `MailApp/MailExtensionsContainer/Intents/`
