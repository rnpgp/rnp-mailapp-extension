# ADR-0003: Lazy-load librnp on first use

Date: 2026-08-03
Status: Accepted

## Context

`KeysManager.init()` originally opened the keyring eagerly — loading
librnp, reading pubring/secring, populating the in-memory list, and
probing Touch ID state. This added 300–500 ms to cold-launch time
before any UI appeared.

The cost was especially painful for users who launch the app to use
File Tools or App Intents (which don't need the key list populated
synchronously).

## Decision

`KeysManager.init()` does no I/O. Heavy work moves to
`bootstrap()`, which:
1. Reads the keyring off the main thread.
2. Probes Touch ID state.
3. Publishes results on the main thread.
4. Sets `isLoading = false` so the UI knows to stop showing the
   `ProgressView`.

`MailExtensionsContainerApp.body.onAppear` calls
`model.manager.bootstrap()`.

## Consequences

Positive:
- Cold-launch time drops by ~250 ms (measured on M2).
- UI shows a `ProgressView` instead of an empty-list flash.
- File Tools / App Intents paths can run before the keyring is ready
  if they're called early; operations surface a clear
  `keyringUnavailable` error that resolves once bootstrap completes.

Negative:
- One extra method call (`bootstrap()`) that callers must remember.
  Mitigated by centralizing it in `.onAppear`.
- `isLoading` is a published flag the UI must respect. Forgetting to
  check it produces an "empty list" flash — accepted for now.

Neutral:
- Future enhancement: pre-warm in background 100 ms after launch so
  the first user-perceived action is instant.

## References

- TODO.complete/06-lazy-librnp-load.md
- Code: `MailApp/MailExtensionsContainer/Model/KeysManager.swift`
