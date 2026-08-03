# ADR-0004: SharedKeyring is the single keyring factory

Date: 2026-07-20
Status: Accepted

## Context

Before this refactor, the host app (`KeysManager.init`) and the Mail
extension (`MessageSecurityHandler.makeCore`) each built their own
`KeyManager` from the App Group keyring directory, with subtly
different fallback recipes and error handling. Two code paths meant
two places to update when the keyring location changed, the
passphrase provider evolved, or new fallback locations were needed.

## Decision

`SharedKeyring.makeKeyManager(directory:)` is the single source of
truth. Both the host app and the Mail extension call it. It lives in
`MailExtensionsContainer/Model/SharedKeyring.swift` and is compiled
into both targets.

## Consequences

Positive:
- One place to change keyring construction (location, passphrase
  provider, fallback chain).
- One place to add diagnostic hooks.
- The Mail extension and the host app see identical keyring state.

Negative:
- A subtle bug in `SharedKeyring` affects both targets simultaneously.
  Mitigated by tests.

Neutral:
- The factory returns `KeyManager?` (nullable) so callers can degrade
  gracefully when the keyring is unavailable.

## References

- Code: `MailApp/MailExtensionsContainer/Model/SharedKeyring.swift`
