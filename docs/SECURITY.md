# Security Policy

## Supported Versions

Security fixes are released for the latest tagged version of the `swift-rnp` repository and for the current `main` branch. Older releases are not supported unless explicitly noted in a release announcement.

| Version | Supported          |
| ------- | ------------------ |
| latest release tag | :white_check_mark: |
| `main`  | :white_check_mark: |
| older   | :x:                |

The project depends on **librnp ≥ 0.18.1**. Older librnp releases contain known vulnerabilities (for example, CVE-2025-13470) and must not be used. The vendored `RNPFramework.xcframework` is rebuilt from pinned sources documented in [`Vendor/SOURCES.md`](../Vendor/SOURCES.md) and [`docs/DEPENDENCIES.md`](DEPENDENCIES.md).

## Reporting a Vulnerability

If you discover a security issue in this project, please report it privately.

- **Preferred:** Open a private security advisory on the upstream librnp repository: <https://github.com/rnpgp/rnp/security/advisories>
- **Alternative:** Email the maintainers at **security@rnpgp.com** (placeholder — replace with the address listed on <https://github.com/rnpgp/rnp/security> if it differs).

Please include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a minimal proof of concept.
- The affected version / commit.
- Whether you believe secret key material is at risk.

We aim to acknowledge reports within **5 business days** and to provide a remediation timeline within **10 business days**. Please do not disclose the issue publicly until a fix is released and coordinated disclosure is agreed upon.

## What We Consider In Scope

- Vulnerabilities in the Swift bindings or container app that could lead to secret key disclosure, signature forgery, message decryption by unauthorized parties, or sandbox escape.
- Memory-safety issues in the Swift/C interop layer (e.g., use-after-free, buffer overflows in `Rnp` wrappers).
- Trust-store tampering that bypasses the fail-closed reset behavior.
- Issues in the Mail extension's handling of untrusted MIME messages that cause crashes or undefined behavior.

## What Is Out of Scope

- Vulnerabilities that require a compromised macOS kernel or Apple Mail host process.
- Physical access attacks against an unlocked Mac.
- Attacks that rely solely on social engineering or installation of a malicious build.
- Issues in upstream dependencies that are not specific to how this project uses them (please report those to the upstream project, e.g., <https://github.com/rnpgp/rnp>).

## Security Model

For a detailed description of assets, trust boundaries, and memory hygiene, see [`docs/SECURITY-MODEL.md`](SECURITY-MODEL.md).

## Acknowledgments

We thank security researchers and downstream users who report vulnerabilities responsibly.
