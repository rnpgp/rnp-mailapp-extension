# Dependency Policy

This document describes how `swift-rnp` and the RnpMail macOS app manage their dependencies, how they are pinned, and how security issues in dependencies are handled.

## Vendored Native Dependencies

The macOS app bundles a self-contained `RNPFramework.xcframework` built by [`scripts/build-rnp-framework.sh`](../scripts/build-rnp-framework.sh). The framework is assembled from the following pinned sources:

| Component | Version / Ref | SHA-256 (tarball) | License | Source |
|---|---|---|---|---|
| rnp | `v0.18.1` | `8133cb825e6672725b33f93b8f4185d702b7444c58240f00d9f3dc886f5b0aae` | BSD-2-Clause | https://github.com/rnpgp/rnp |
| Botan | `3.10.0` | `28a98475e05dc2052654397207b4a78e36e6309b662f7f2888feb78cc948cea6` | BSD-2-Clause | https://github.com/randombit/botan |
| json-c | `json-c-0.18-20240915` | `3112c1f25d39eca661fe3fc663431e130cc6e2f900c081738317fba49d29e298` | MIT | https://github.com/json-c/json-c |
| sexpp | `c641a2f36520bab783657a58650d9fda548b9dec` | N/A (git submodule) | BSD-2-Clause | https://github.com/rnpgp/sexpp |

The pinned hashes are stored in:

- `scripts/rnp-v0.18.1.sha256`
- `scripts/Botan-3.10.0.sha256`
- `scripts/json-c-0.18-20240915.sha256`

`build-rnp-framework.sh` verifies each tarball against its hash before extraction. If the upstream tarball is replaced, the build fails.

### Updating a vendored dependency

1. Update the version/ref in `scripts/build-rnp-framework.sh`.
2. Delete the old `scripts/<component>-<old-version>.sha256` file.
3. Run `scripts/build-rnp-framework.sh`. The script downloads the new tarball and records its SHA-256.
4. Review the diff to `Vendor/SOURCES.md` and the new hash file.
5. Run the full test matrix (`swift test`, `xcodebuild` for `MailPlugin` and `Ribose container`) before committing.

## Swift Package Manager Dependencies

The SwiftPM package at the root of the repository currently has **no external package dependencies**. All library targets (`Rnp`, `MailSecurityEngine`, `KeyLifecycle`, `KeyServerClient`, `TrustStore`, `RnpMailUI`) depend only on:

- Swift stdlib and Foundation.
- The `CRnp` system-library target, which resolves `librnp` via `pkg-config`.

If a future change adds an SPM dependency, it must:

- Pin an exact version or commit using `.exact(...)` or `.revision(...)` in `Package.swift`.
- Be reviewed by a CODEOWNER of the target that consumes it.
- Have a recorded rationale in this file under "SPM dependency rationales".

## CVE Response Policy

1. **Monitor.** The maintainers monitor the following sources:
   - GitHub Security Advisories for `rnpgp/rnp`, `randombit/botan`, and `json-c/json-c`.
   - `security@rnpgp.com` and the private security advisory queue.
   - Apple security updates relevant to macOS sandbox and MailKit.

2. **Triage.** A reported CVE is triaged within **5 business days**. Critical issues affecting secret key confidentiality, signature forgery, or sandbox escape are treated as P0.

3. **Assess impact.** We determine whether the CVE affects code paths used by RnpMail. For example, a vulnerability in GnuPG keyring import may not affect RnpMail because only GPG-compatible keyrings produced by librnp are used.

4. **Update or mitigate.**
   - If an updated upstream release is available, bump the pinned version in `build-rnp-framework.sh`, regenerate `RNPFramework.xcframework`, and update the SHA-256 files.
   - If no update is available, document a mitigation (e.g., disable a feature, add an input filter) and link to the upstream issue.

5. **Release.** Security fixes are released as a new patch version with a note in the release notes and a cross-reference to the CVE.

6. **Disclose.** Coordinated disclosure follows the policy in [`docs/SECURITY.md`](SECURITY.md).

## CODEOWNERS and Review Rules

- Changes to `scripts/build-rnp-framework.sh`, `Vendor/SOURCES.md`, or any `*.sha256` file require review by a maintainer listed in `CODEOWNERS` (to be created if the project grows beyond the current maintainer team).
- `.github/dependabot.yml` is intentionally not enabled for SPM because there are no SPM dependencies and because dependency bumps for the native framework must be coordinated with `build-rnp-framework.sh` rather than a lockfile-only update.

## License Compliance

All vendored components are Open Source. License texts and source URLs are summarized in [`Vendor/SOURCES.md`](../Vendor/SOURCES.md) and rendered in-app via the **About → Licenses** view.

## Unsupported Configurations

- Using a system `librnp` older than `0.18.1` is unsupported and blocked by documentation. CI tests against `v0.18.1` and the rnp `main` branch.
- Replacing `RNPFramework.xcframework` with a locally built framework without updating `Vendor/SOURCES.md` and the SHA-256 files is allowed for local development only; release builds must use the pinned sources.
