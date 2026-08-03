# 10 — `rnp` CLI for macOS

**Priority**: P2
**Status**: not started
**Effort**: M
**Dependencies**: 5 (sign/verify — for command surface)

## Problem

Power users want PGP from the terminal. Today they install GnuPG via
brew and never touch librnp. A native `rnp` CLI on macOS gives them:

- A modern OpenPGP implementation (PQC, v6 keys) without GnuPG's legacy
- Shared keyring with the GUI app (via App Group container)
- Scriptable for CI / build pipelines / release tooling

## Goals / non-goals

**Goals**
- `brew install rnp` (formula, not cask — CLI only)
- Commands: `keygen`, `list`, `import`, `export`, `encrypt`, `decrypt`,
  `sign`, `verify`
- Shared keyring with RNP.app via App Group
- Reads/writes `~/.rnp/` (same as the app)
- Man page + shell completion

**Non-goals**
- Drop-in GnuPG CLI compatibility (`gpg`-like flags) — different surface
- Replacing `rnp` the librnp CLI (Ribose already ships that for Linux).
  This is a Mac-native Swift CLI that wraps `MailSecurityEngine`.

## Design

### Architecture

A SwiftPM executable target inside the existing workspace:

```
Sources/rnp-cli/
├── main.swift                        (entry; arg parsing)
├── Commands/
│   ├── KeygenCommand.swift           (OCP: one Command per verb)
│   ├── ListCommand.swift
│   ├── ImportCommand.swift
│   ├── EncryptCommand.swift
│   ├── DecryptCommand.swift
│   ├── SignCommand.swift
│   └── VerifyCommand.swift
├── CLIKeyring.swift                  (adapter to MailSecurityEngine KeyManager)
└── OutputFormatter.swift             (text/json/pretty printer)
```

### OCP: one command per file

Adding `rnp keyserver-publish` = adding `KeyserverPublishCommand.swift`
+ registering in `main.swift`. No existing command changes.

### Shared keyring

```swift
import MailSecurityEngine

let keyring = CLIKeyring(at: SharedKeyring.defaultKeyringURL())
// SharedKeyring.defaultKeyringURL() points at:
//   ~/Library/Group Containers/<group-id>/Library/Application Support/RNP/keyring
// Same path the GUI app uses → same keys.
```

### Output formatting

Three modes: human (default), json (`--json`), machine (`--porcelain`).
Powers scripts and CI.

## Implementation plan

1. Add `rnp-cli` executable target to `Package.swift`
2. Implement command surface (start with `keygen`, `list`, `encrypt`,
   `decrypt`, `sign`, `verify`)
3. Man page in `rnp-cli/man/rnp.1`
4. Shell completion via `swift-completion-generator` or hand-written
5. Homebrew formula in `packaging/homebrew-formula/rnp.rb`
6. CI: build CLI in `ci.yml`, attach to release

## Acceptance criteria

- [ ] `rnp keygen --name "..." --email "..."` produces a key visible in RNP.app
- [ ] `rnp encrypt file.txt -r <fpr>` produces armored ciphertext
- [ ] `rnp decrypt file.txt.pgp` decrypts using shared keyring
- [ ] `rnp sign file.txt` produces inline signature
- [ ] `rnp verify file.txt` shows signer + validity
- [ ] `--json` output is stable and parseable
- [ ] Man page renders
- [ ] Homebrew formula installs cleanly

## Open questions

- **Keyring passphrase.** GUI app uses Keychain + Touch ID. CLI can't do
  Touch ID. Fall back to `--passphrase` flag or KEYRING_PASSPHRASE env
  var. Don't write to stderr when reading from terminal.
- **Distribution channel.** Homebrew formula here vs upstreaming to
  homebrew-core. Start here.

## References

- Existing librnp CLI: https://github.com/rnpgp/rnp/tree/main/src
- Swift ArgumentParser: https://github.com/apple/swift-argument-parser
