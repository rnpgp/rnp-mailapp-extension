# rnp-cli

Command-line OpenPGP for macOS. Shares the same engine (`librnp` via
`swift-rnp`) and the same keyring as the RNP GUI app.

## Build

```bash
cd rnp-cli
swift build -c release
.build/release/rnp --help
```

`swift build` downloads a pre-built `RNPFramework.xcframework` from the
`swift-rnp` GitHub release. If your keychain has conflicting GitHub
entries (common on machines with multiple GitHub accounts), you may see
`Failed to extract credentials for 'https://github.com'`. Work around:

```bash
# Option A: clear conflicting keychain entries
security delete-internet-password -s github.com  # repeat for each

# Option B: download the xcframework manually and place it where
# SwiftPM looks for cached artifacts
curl -L -o /tmp/rnp-fw.zip \
  https://github.com/rnpgp/swift-rnp/releases/download/v0.1.0/RNPFramework.xcframework.zip
unzip /tmp/rnp-fw.zip -d /tmp/rnp-fw
mkdir -p ~/Library/org.swift.swiftpm/artifacts/swift-rnp
cp -r /tmp/rnp-fw/RNPFramework.xcframework ~/Library/org.swift.swiftpm/artifacts/swift-rnp/
```

## Install

```bash
swift build -c release
cp .build/release/rnp /usr/local/bin/rnp
```

Or, once published to Homebrew:

```bash
brew install rnp
```

## Commands

```
rnp keygen --name "Alice <alice@example.com>" [--algorithm ed25519|rsa|ecdsa]
rnp list [--secret] [--output human|json|porcelain]
rnp encrypt [-r recipient]... [input.pgp] [-o output]
rnp decrypt [input.pgp] [--passphrase X] [-o output]
rnp sign --signer <fpr> [--detached|--cleartext] [input]
rnp verify [--payload original.txt] signed.pgp [--output human|json|porcelain]
```

## Shared keyring

The CLI reads the same keyring as the GUI app — at the App Group
container path. Keys created in the GUI appear in `rnp list` and vice
versa. Override with `RNP_KEYRING_DIR=/path/to/keyring rnp list` for
tests.

## Output formats

`--output` controls `list` and `verify` output:

- **human** (default): readable, multi-line
- **json**: one JSON object per record, array for lists
- **porcelain**: colon-separated, for scripts (mirrors `gpg --with-colons`)

## Why

Power users want PGP from the terminal. Today they install GnuPG via
brew and never touch `librnp`. A native `rnp` CLI gives them:

- A modern OpenPGP implementation (PQC, v6 keys) without GnuPG's
  legacy codepath
- Shared keyring with the GUI app via App Group container
- Scriptable for CI / build pipelines / release tooling

See TODO.complete/10-rnp-cli-macos.md.
