# 36 — GnuPG agent passphrase store (lookup-only)

**Priority**: P2
**Status**: shipped
**Effort**: M
**Dependencies**: 33 (Phase 1.5 refactor)

## Problem

Linux users who imported keys from `~/.gnupg/` don't want to re-enter
every passphrase. `gpg-agent` already has them cached; RNP should
look them up rather than re-prompt.

## Goals

- `GnuPGAgentPassphraseStore` — `PassphraseStore` conformance
- Lookup-only — never writes to gpg-agent's cache
- After first successful lookup, RNP caches in its own store (macOS Keychain or chosen store); doesn't keep hitting gpg-agent
- Mac+Linux only (no gpg-agent on iOS)

## Design

### Lookup mechanism

Shells out to `gpg --batch --passphrase-fd N --pinentry-mode loopback <fpr>`:
- `N` is a pipe we write the cached passphrase to (if any)
- If gpg-agent has the passphrase cached, gpg succeeds without prompting
- We capture the passphrase gpg used via `--passphrase-file`

Actually the standard pattern is:
- `gpg-agent` exposes a `--passphrase` query API via Assuan protocol
- Or: we use `gpg --list-secret-keys --with-key-data` which doesn't trigger passphrase prompts

The realistic approach:
- Run `gpg --export-secret-keys <fpr>` — if gpg-agent has the passphrase cached, this succeeds and we get the secret key bytes
- We can't directly extract the passphrase from gpg-agent (security feature)
- So this backend is actually "can gpg-agent decrypt this for us without prompting" — useful for read-only ops, not for caching

### Revised goal

After more thought: we can't extract passphrases from gpg-agent. The
realistic value is:
- For each imported-from-GnuPG key, try `gpg --sign --batch --passphrase '' --local-user <fpr>` to see if gpg-agent has it cached
- If yes: gpg-agent will handle sign ops for us via gpg CLI; we don't need the passphrase
- If no: prompt user as usual

This is more of a "delegate to gpg for sign/decrypt when keys were imported from GnuPG" feature. Out of scope for v1.

## Implementation plan

1. Detect gpg-agent availability
2. (Future) Delegate sign/decrypt ops to gpg for GnuPG-imported keys
3. Document the limitation in the Sync UI

## Acceptance criteria

- [ ] Settings UI accurately reports "gpg-agent integration is lookup-only; not implemented yet"
- [ ] Spec in `docs/specs/gnupg-agent-passphrase.md`

## Out of scope

- Directly reading passphrases from gpg-agent (not possible by design)

## References

- TODO.complete/32-sync-settings-ui.md
