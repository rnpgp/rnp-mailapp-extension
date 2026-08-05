# ADR-0006: Canonical store vs import source — protocol separation

Date: 2026-08-05
Status: Accepted

## Context

RNP needs to read keys from many places: its own keyring (local
files), the user's GnuPG keyring (`~/.gnupg/`), WKD lookups,
keys.openpgp.org, pasted ASCII armor, drag-dropped files. Some of
these are read/write (RNP's own store); most are read-only (everything
else).

The user's absolute rule — never wipe user keys — means RNP must
NEVER write to `~/.gnupg/`, NEVER call `gpg --delete-*`, NEVER modify
a WKD-fetched key's source. These are read-only by intent.

## Decision

Two distinct protocols:

- `KeyringBackend` — RNP's canonical store. Has `load`, `upsert`,
  `delete`, `observeChanges`. RNP writes here.
- `KeyImportSource` — read-only. Has ONLY `listAvailable`. No write
  methods. Compile-time guarantee.

A type cannot conform to both. GnuPG conforms to `KeyImportSource`;
RNP's local keyring conforms to `KeyringBackend`.

## Consequences

Positive:
- **Compile-time enforcement** of the never-write-to-external rule.
  A future contributor can't accidentally add a write method to
  GnuPGImportSource because the protocol doesn't have one.
- **Clear mental model**: when reviewing code, you can tell at a
  glance whether a given type can modify user data.
- **Future-proof**: new external sources (LDAP, more keyservers,
  YubiKey) are obvious `KeyImportSource` conformances. No temptation
  to add write methods.

Negative:
- Slight protocol proliferation. We accept this; the alternative
  (one protocol with optional write methods) is worse — it makes
  writes a runtime check instead of a compile-time check.

Neutral:
- The `CompositeKeyringBackend` wraps multiple `KeyringBackend`s for
  the unified view. It does NOT wrap `KeyImportSource`s — those are
  surfaced separately in the Import menu.

## References

- PR #190 (protocols introduced)
- docs/sync-architecture.md
- TODO.complete/33-refactor-sharedkeyring-through-protocols.md
