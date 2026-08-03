# 06 — Lazy-load librnp on first use

**Priority**: P2
**Status**: shipped
**Effort**: S
**Dependencies**: none

## Problem

On launch, `KeysManager.init()` eagerly opens the keyring (loads
`librnp`, reads pubring/secring, populates the in-memory list). This
adds 300-500 ms to cold-launch time before the onboarding window
appears. Not terrible, but noticeable — and we pay it for users who
launch the app just to use File Tools or App Intents (which don't need
the key list populated immediately).

## Goals / non-goals

**Goals**
- Cold-launch time drops by 200+ ms
- Key list populates lazily, on first UI access
- File Tools / App Intents operations trigger load on demand
- No behavior change for end users beyond faster launch

**Non-goals**
- Lazy-loading individual keys (irrelevant — keyring load is fast once
  librnp is up; the cost is the C library init)
- Background loading animation UI (premature)

## Design

### Pattern: lazy `KeyManager` accessor

```swift
public final class KeysManager: ObservableObject {
    private let keyManagerBox: LazyBox<KeyManager>

    public var keyManager: KeyManager? {
        try? keyManagerBox.value()
    }

    public init() {
        self.keyManagerBox = LazyBox { try SharedKeyring.makeKeyManager() }
    }

    public func withRnp<T>(_ body: (Rnp) throws -> T) throws -> T {
        guard let km = try keyManagerBox.value() else {
            throw KeyringError.unavailable
        }
        return try km.withRnp(body)
    }
}

public final class LazyBox<T> {
    private let make: () throws -> T
    private var cached: T?
    private let lock = NSLock()

    public init(make: @escaping () throws -> T) {
        self.make = make
    }

    public func value() throws -> T? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        do {
            cached = try make()
            return cached
        } catch {
            return nil
        }
    }
}
```

### Observable behavior

The view layer subscribes to `@Published var keys`. The first
`.onAppear` of `KeysListView` calls `model.manager.refresh()` which
triggers `keyManagerBox.value()` → librnp loads → list populates.

Before: launch → 500ms → window appears with keys.
After: launch → 200ms → window appears empty → 300ms later keys populate.

To avoid a visible "empty flash", `KeysListView` shows a 1-frame
`ProgressView` while `model.manager.keys.isEmpty && model.manager.isLoading`.

## Implementation plan

1. ✅ Add `LazyBox<T>` to `SharedKeyring.swift` (shipped)
2. ✅ Refactor `KeysManager` to use lazy box (shipped)
3. ✅ Add `isLoading` published flag for UI (shipped)
4. ✅ Update `KeysListView` to show progress while loading (shipped)
5. Benchmark before/after

## Acceptance criteria

- [ ] Cold-launch time measured with `xcrun xctrace` drops by ≥ 200 ms
- [ ] No empty flash visible to user (loading indicator instead)
- [ ] All existing tests pass
- [ ] No regression in encrypt/decrypt/file ops

## Open questions

- **Pre-warm in background?** Could trigger load 100ms after launch
  asynchronously instead of waiting for first access. Yes — worth doing
  once we measure. Adds 5 lines.

## References

- Code: `MailApp/MailExtensionsContainer/Model/SharedKeyring.swift`
- Pattern: standard lazy-init with thread-safety via `NSLock`
