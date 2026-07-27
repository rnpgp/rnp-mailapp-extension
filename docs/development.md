# Development

This page covers building, testing, and contributing to the RNP mail
extension. The repository contains two things that work together:

1. a **Swift Package Manager package** with the Swift bindings for librnp and
   all non-MailKit logic, and
2. an **Xcode project** (`MailApp/RnpMail.xcodeproj`) with the container
   app and the MailKit extension, built entirely on that package.

## Repository layout

```
Package.swift                  SwiftPM manifest
Sources/
  CRnp/                        system-library target (pkg-config → librnp)
  Rnp/                         Swift bindings for librnp (FFI wrappers,
                               paper-key, multi-UID, Autocrypt export,
                               v6 keygen, AEAD/v6 encrypt, certification)
  MailSecurityEngine/          PGP/MIME + inline-PGP encode/decode,
                               KeyManager, BCC policy, decryption errors,
                               encryption envelope policy, compose policy,
                               key health, notify-contacts, mailbox scanner,
                               offline publish queue, reply heuristic,
                               signed security-state store
  MailSecurityUI/              AppKit security banner (MailKit-free, testable)
  KeyLifecycle/                subkey rotation, expiry extension, revocation,
                               key transition with certification
  KeyServerClient/             VKS / HKPS / WKD client
  TrustStore/                  TOFU trust records, signed trust.json
  KeyStateStore/               active/archived usage state, signed key-states.json
  Autocrypt/                   level-1 header parser/serializer, observation
                               store, gossip (1.1), per-account policy store
  PostQuantum/                 PQ algorithm catalog (ML-KEM, ML-DSA, SLH-DSA)
  RnpMailUI/                   shared app UI: KeyHealth, RecoveryWizard,
                               AddUserID, ComposeDiagnostics, BCCRefusal,
                               MailboxScan, EncryptionSettings, TransitionWizard,
                               PaperKeyRestore, DeleteForever, ArchivedKeys,
                               EngineEnvironment, InlineRecoverySheets,
                               RecommendedActionBanner
MailApp/
  Swift-Rnp.xcodeproj/         container app + Mail extension project
  MailExtensionsContainer/     the RNP container app (target "RNP"),
                               including RoadmapNavigationCoordinator
  MailPlugin/                  the MailKit extension target (BCC-aware handler)
  Shared/IDs.xcconfig          single source for bundle IDs and app group
  Config/                      build configurations (Direct, AppStore)
Tests/                         497 tests across 20+ files, fixtures, snapshots
Vendor/                        RNPFramework.xcframework + pkg-config stubs
scripts/                       framework build, release preflight, audit, e2e
docs/                          user-facing documentation (12 pages)
TODO.roadmap/                  16 design docs + progress tracker (108/108 done)
```

## Prerequisites

- macOS 12+, Xcode 15+ (Swift 5.9+).
- librnp **0.18.1 or later** (`brew install rnp`, or build from source — see
  [Installation](installation.md#1-install-librnp)).

The `CRnp` system-library target locates librnp via `pkg-config`. When librnp
is in a default prefix (`/usr/local`, Homebrew) nothing extra is needed; for
a custom prefix, point `PKG_CONFIG_PATH` at its `.pc` file and pass an rpath
(`DYLD_LIBRARY_PATH` is not honored by the hardened-runtime test runner):

```sh
export PKG_CONFIG_PATH=/path/to/librnp/lib/pkgconfig:$PKG_CONFIG_PATH
swift build
swift test -Xlinker -rpath -Xlinker /path/to/librnp/lib
```

## Building and testing

### Swift package (no Xcode required)

```sh
swift build
swift test
```

The package suite covers the bindings, the MIME engine, the trust store, the
keyserver client, key lifecycle, and the banner UI (including snapshot
tests).

### Xcode targets

```sh
export PKG_CONFIG_PATH="$(pwd)/Vendor/pkgconfig"

# Container app + Mail extension (compile checks; no signing)
xcodebuild -project MailApp/RnpMail.xcodeproj -scheme MailPlugin \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO
xcodebuild -project MailApp/RnpMail.xcodeproj -scheme RNP \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO

# Container app UI tests (onboarding, key generation, accessibility audits)
xcodebuild -project MailApp/RnpMail.xcodeproj -scheme RNP \
    test CODE_SIGNING_ALLOWED=NO
```

To run the app or have Mail actually load the extension, sign both targets
with your `DEVELOPMENT_TEAM` — see
[Installation](installation.md#build-from-source).

### Snapshot tests

Banner snapshot tests live in `Tests/MailSecurityUITests/`, with reference
PNGs in `Tests/Fixtures/snapshots/`. The references are machine-specific
(fonts, anti-aliasing). If they mismatch on a new machine, delete the
affected PNGs, re-run the tests to re-record, and **review the new images
before committing**.

### End-to-end Mail testing

A local IMAP/SMTP harness (`scripts/local-mail-server.sh` +
`scripts/test-mail-e2e.sh`) drives real Mail integration tests on a dedicated
macOS runner; see the `mail-e2e.yml` workflow. On every OpenPGP message it
decodes, the extension writes a small metadata record (subject, sender,
signature/trust status — never bodies) to `ExtensionState/` in the app-group
container so the harness can assert banner state from outside Mail.

### Audits

```sh
./scripts/sandbox-audit.sh       # sandbox / entitlement audit
./scripts/ci-release-dry-run.sh  # release pipeline dry-run, self-signed cert
```

## Release pipeline

Two channels, both from tags (`v$MARKETING_VERSION`, checked against
`MailApp/Config/Version.xcconfig`):

- **Direct** (`.github/workflows/release-direct.yml`) — builds the `Direct`
  configuration, signs with Developer ID, notarizes and staples, creates
  `RNP-<version>.dmg`, and attaches it to the GitHub Release. Driven by
  `scripts/release-direct.sh`.
- **App Store** (`.github/workflows/release-appstore.yml`) — builds the
  `AppStore` configuration with Apple Distribution signing and uploads to App
  Store Connect. It triggers on successful completion of the direct release
  workflow (on the default branch only).

The vendored `RNPFramework.xcframework` embedded in both targets is built by
`scripts/build-rnp-framework.sh` from pinned, hash-verified sources (librnp
0.18.1, Botan 3.10.0, json-c 0.18). Update procedure and CVE response are in
[Dependency policy](DEPENDENCIES.md).

## CI overview

| Workflow | Purpose |
|---|---|
| `test.yml` | `swift test` against librnp v0.18.1 and librnp from the rnp default branch (macOS). |
| `release-direct.yml` | Tag-triggered notarized DMG release. |
| `release-appstore.yml` | App Store upload after a successful direct release. |
| `release-dry-run.yml` | Rehearses the release pipeline without publishing. |
| `mail-e2e.yml` / `mail-e2e-docker.yml` | End-to-end Mail tests on a self-hosted macOS runner. |

## Contributing

- **Run the full matrix before submitting.** `swift test`, both `xcodebuild`
  builds, and the UI tests must pass. Add tests for behavior changes; the
  project keeps the engine MailKit-free precisely so it stays unit-testable.
- **Follow the existing style.** Swift library targets avoid force-unwraps
  and use explicit error handling; librnp errors surface as `RnpError` with
  the underlying `rnp_result_t`.
- **Keep secrets out of the wrong places.** Passphrases go to the Keychain,
  never UserDefaults or logs — see [Security model](SECURITY-MODEL.md).
- **Dependencies are pinned.** Do not add SPM packages casually, and never
  bump vendored native components without the procedure in
  [Dependency policy](DEPENDENCIES.md).
- **Security issues are not public issues.** Report them privately per the
  [Security policy](SECURITY.md).
- **License status.** The repository currently ships no license file; contact
  the maintainers before reusing code in ways that need an explicit license.

## See also

- [Installation](installation.md)
- [Dependency policy](DEPENDENCIES.md)
- [Security model](SECURITY-MODEL.md)
