# RNP Mail Extension Documentation

RNP is an OpenPGP security extension for Apple Mail on macOS, together with its
companion key-manager app. It signs, encrypts, decrypts, and verifies mail
directly inside Mail.app, using the [librnp](https://github.com/rnpgp/rnp)
implementation of OpenPGP (RFC 4880).

A landing page with a product overview lives in
[`website/index.html`](website/index.html) — open it in a browser, no build
step required.

## User guides

- [Installation](installation.md) — direct-download DMG, Mac App Store, and
  building from source.
- [Usage](usage.md) — enable the extension, manage keys, sign and encrypt,
  verify signatures, and make trust decisions.
- [Features](features.md) — the full feature list, mapped to OpenPGP and
  librnp capabilities.
- [Trust model](trust-model.md) — trust-on-first-use, manual fingerprint
  verification, and key-change conflicts.
- [Keyservers](keyserver.md) — publishing and discovering keys over VKS,
  HKPS, and WKD.
- [FAQ](faq.md) — common questions and answers.

## Developer guides

- [Development](development.md) — repository layout, build and test
  instructions, and how to contribute.

## Security and privacy

- [Security model](SECURITY-MODEL.md) — assets, trust boundaries, sandboxing,
  and memory hygiene.
- [Security policy](SECURITY.md) — supported versions and how to report a
  vulnerability.
- [Telemetry and privacy policy](TELEMETRY.md) — the app collects no
  telemetry; this document explains the stance in detail.
- [Dependency policy](DEPENDENCIES.md) — pinned vendored sources, update
  procedure, and CVE response.

## Release documentation

- [App Store metadata](app-store/metadata.md) — App Store Connect submission
  template.
- [App Store screenshots checklist](app-store/screenshots-checklist.md) —
  requirements and production notes for store screenshots.

## Project links

- Repository: <https://github.com/rnpgp/swift-rnp>
- Releases (signed, notarized DMG): <https://github.com/rnpgp/swift-rnp/releases>
- Upstream OpenPGP engine: <https://github.com/rnpgp/rnp>
