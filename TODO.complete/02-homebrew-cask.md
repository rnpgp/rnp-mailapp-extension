# 02 — Homebrew Cask distribution

**Priority**: P1
**Status**: shipped (formula in `packaging/homebrew-cask/rnp.rb`; PR to
homebrew-cask pending)
**Effort**: S
**Dependencies**: signed + notarized DMG artifacts in release

## Problem

Power users install everything via `brew install --cask`. Discovering RNP
means going to GitHub releases, downloading a DMG, mounting, dragging —
friction at every step. Homebrew is the de facto distribution channel for
Mac tools; absence reads as "not a real project".

## Goals / non-goals

**Goals**
- `brew install --cask rnp` installs the latest release
- `brew upgrade rnp` picks up new versions
- SHA256 verification enforced
- Automatic updates handled by **Sparkle** (TODO 04) post-install

**Non-goals**
- A Homebrew **formula** (CLI build) — that's TODO 10
- Auto-submission CI — manual PR to homebrew-cask per release is fine

## Design

### Cask formula

Lives in `packaging/homebrew-cask/rnp.rb` in this repo (source of truth).
On each release, copy it into a PR to `Homebrew/homebrew-cask`.

Cask design:
- `version` matches the GitHub release tag (sans `v`)
- `sha256` from the published `SHA256SUMS`
- `url` points at the specific release tarball (not latest, not /releases/download)
- `name`, `desc`, `homepage` set
- `appcast` later — when Sparkle feed exists
- `auto_updates` true once Sparkle ships
- `zap` deletes `~/Library/Containers/com.rnpgp.RNPForMail` and keychain
  key (gated; don't delete keyring by default — see "Known gotchas")

### Known gotchas

1. **Deleting the keyring on `brew uninstall`.** NEVER `trash: {
   '~/Library/.../keyring' }`. The user's keys are sacred (per global
   rule). Only trash preferences and caches.
2. **Code signature.** `brew audit` verifies the signature matches the
   Developer ID. The DMG must be signed + notarized.
3. **Conflicts.** If the user has GPG Suite installed, our app doesn't
   conflict (different bundle IDs), but our `gpg` import scanner reads
   `~/.gnupg`. Document this.

## Implementation plan

1. ✅ Author `packaging/homebrew-cask/rnp.rb` (shipped)
2. ✅ Test `brew install --cask` from local formula
3. PR to `Homebrew/homebrew-cask` (cask submission process)
4. After merge: `brew install --cask rnp` works for everyone

## Acceptance criteria

- [ ] `brew install --cask packaging/homebrew-cask/rnp.rb` succeeds locally
- [ ] App launches from `/Applications/RNP.app` after install
- [ ] `brew uninstall rnp` removes the app but leaves `~/.rnp/` and
      `~/.gnupg/` alone
- [ ] `brew audit --strict packaging/homebrew-cask/rnp.rb` passes
- [ ] PR opened against homebrew-cask

## Open questions

- **Cask name.** `rnp` is short and clear; potential collision in
  homebrew-cask. Reserved name check needed before PR.
- **Auto-updates via Sparkle vs brew.** Sparkle will offer updates faster
  than brew; brew is the install channel, Sparkle is the update channel.
  Mark `auto_updates true` so brew doesn't try to manage updates.

## References

- Cask formula: `packaging/homebrew-cask/rnp.rb`
- Homebrew docs: https://docs.brew.sh/Cask-Cookbook
- Existing DMG artifacts: GitHub release v0.9.6+
