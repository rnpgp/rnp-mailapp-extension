# 33 — Phase 1.5 refactor: route existing code through protocols

**Priority**: P0
**Status**: in progress
**Effort**: M
**Dependencies**: none (this UNBLOCKS 31, 32, 34)

## Problem

PR #190 added the `KeyringBackend`, `KeyImportSource`, and
`PassphraseStore` protocols. But the existing code (`SharedKeyring`,
`KeyringScanner`, `KeychainPassphraseStore`) doesn't use them yet.
The protocols are currently dead code.

This refactor is the foundation for everything else: Settings UI
needs to swap backends, Getting Started needs to choose backends,
per-key dir backend needs to plug in alongside the local one.

## Goals

- Existing code keeps working — no behavior change
- New code paths route through the protocols
- `SharedKeyring` vends both the legacy `KeyManager` (back-compat) and a new `KeyringBackend`
- `KeyringScanner` conforms to `KeyImportSource` (already partially done)
- `ContentViewModel.keys` can read from `CompositeKeyringBackend` without breaking

## Design

### Strangler-fig pattern

Don't rewrite. Wrap.

```swift
// SharedKeyring.swift — new entry point, side-by-side with the old
public enum SharedKeyring {
    public static func makeBackend(directory: URL) -> KeyringBackend {
        LocalFileKeyringBackend(directory: directory)
    }

    // Existing — kept for back-compat
    public static func makeKeyManager(directory: URL) -> KeyManager? { ... }
}
```

`LocalFileKeyringBackend.load()` returns `[KeyringKeyRecord]` derived
from `KeyManager.listKeys()`. Same data, different shape.

### LocalFileKeyringBackend — real impl

Replace the stub with a real conformance:

```swift
public func load() throws -> [KeyringKeyRecord] {
    guard let manager = SharedKeyring.makeKeyManager(directory: directory) else { return [] }
    let keys = (try? manager.listKeys()) ?? []
    return keys.map { key in
        KeyringKeyRecord(
            id: key.fingerprint,
            primaryUserID: key.primaryUserID,
            allUserIDs: key.userIDs,
            keyBytes: Data(),  // bytes fetched on demand at import time
            hasSecret: key.hasSecret,
            keyCreationDate: key.creationDate,
            keyExpirationDate: key.expirationDate,
            modifiedAt: Date(),
            modifiedBy: "local"
        )
    }
}
```

### KeyringScanner as KeyImportSource

`KeyringScanner` is currently a free enum with static methods. Wrap
it in a `GnuPGImportSource` (already exists as stub) that delegates to
the existing scan logic. Read-only by construction.

### Composite as default

`ContentViewModel` gets a new property:

```swift
private(set) var keyringBackend: CompositeKeyringBackend
```

Initialized with `[LocalFileKeyringBackend(...)]` for now. Settings UI
later swaps in additional sources.

`keys` getter routes through `keyringBackend.load()` instead of
`manager.keys` directly. Same data, different path.

## Implementation plan

1. Implement `LocalFileKeyringBackend.load()` properly
2. Implement `GnuPGImportSource.listAvailable()` properly (delegates to existing KeyringScanner)
3. Add `SharedKeyring.makeBackend()` factory
4. Add `ContentViewModel.keyringBackend` property
5. Route `keys` getter through the backend
6. Verify behavior is unchanged (existing tests still pass)

## Acceptance criteria

- [ ] LocalFileKeyringBackend.load() returns same data as KeysManager.keys
- [ ] GnuPGImportSource.listAvailable() returns same data as KeyringScanner
- [ ] Existing onboarding, import flows, file tools all work
- [ ] ContentViewModel.keys produces same list as before
- [ ] New code can opt into backend abstraction; old code unchanged

## References

- PR #190 (protocols)
- TODO.complete/31-getting-started-storage-choice.md
- TODO.complete/32-sync-settings-ui.md
