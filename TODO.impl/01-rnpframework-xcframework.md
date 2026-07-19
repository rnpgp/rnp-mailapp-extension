# 01 — Vendored RNPFramework.xcframework

Status: pending · Milestone: M1a · Depends on: PR #13 merged (see 00-overview)

## Goal

Eliminate the "install librnp separately" requirement for the Xcode app:
build a self-contained `RNPFramework.xcframework` (librnp + all non-system
deps statically linked) from pinned rnp sources, consumable both by the SPM
package (binaryTarget) and the Xcode targets. This is REQUIRED for App Store
sandboxing and for any user machine.

## Context

- Today `Sources/CRnp` is a systemLibrary resolving librnp via pkg-config
  from `/usr/local` or `/opt/homebrew` — fine for dev, unacceptable for
  distribution.
- rnp v0.18.1 tag tarball: `https://github.com/rnpgp/rnp/archive/refs/tags/v0.18.1.tar.gz`
  with submodule `src/libsexpp` (github.com/rnpgp/sexpp — clone at the pinned
  submodule commit from the tag).
- Deps: Botan 3 (we build with `-DCRYPTO_BACKEND=botan3`; brew botan is 3.x),
  json-c, zlib (system), bzip2 (system), sexpp (bundled).

## Steps

1. Create `scripts/build-rnp-framework.sh`:
   - Args: `--rnp-ref v0.18.1` (default), `--out Vendor/RNPFramework.xcframework`.
   - Download the rnp tarball, **verify against a SHA256 recorded in
     `scripts/rnp-<ref>.sha256`** (generate this file when writing the script:
     `curl -sL <url> | shasum -a 256`; do NOT invent a hash).
   - Build Botan 3 static (from the Botan release tarball, SHA256-pinned same
     way), json-c static, then rnp with
     `-DCRYPTO_BACKEND=botan3 -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_POSITION_INDEPENDENT_CODE=ON`
     and static dep paths via `-DCMAKE_PREFIX_PATH`.
   - Link ONE combined dylib `RNPFramework` from librnp.a + libbotan-3.a +
     libjson-c.a + libsexpp.a (so consumers link exactly one library;
     system z/bz2/c++ remain dynamic). Export only rnp_* symbols (rnp ships
     `src/lib/librnp.symbols` — use `-exported_symbols_list`).
   - Wrap as `RNPFramework.framework` (Headers: `rnp/rnp.h`, `rnp_err.h`,
     generated `rnp_export.h`, `rnp_ver.h`; Info.plist; module map), then
     `xcodebuild -create-xcframework`.
2. Wire consumers:
   - Package.swift: add `.binaryTarget(name: "RNPFramework", path: "Vendor/RNPFramework.xcframework")`
     and make `CRnp` (or a new target `RnpNative`) depend on it instead of the
     systemLibrary when the framework is present. Keep the pkg-config
     systemLibrary path working for CI/dev WITHOUT the framework (choose one
     mechanism: two package manifests is ugly — prefer: CRnp keeps working via
     pkg-config for `swift test`; Xcode targets link the xcframework directly.
     Decide and document in README; simplest reliable split wins).
   - Xcode: replace `librnp.xcconfig` rpath/pkg-config wiring with
     `FRAMEWORK_SEARCH_PATHS` to `Vendor/` + embed framework in both the app
     (`Contents/Frameworks`) and the appex. Verify no `/usr/local` reference
     remains: `otool -L` on the built .appex must show only `@rpath` + system.
3. CI (`.github/workflows/test.yml`): cache `Vendor/RNPFramework.xcframework`
   keyed by rnp ref + script hash; build it when absent; remove the
   "build librnp from source + sudo install" steps for the xcodebuild legs
   (keep them for the pure-SPM `swift test` legs, which still use pkg-config).
4. Sign the framework in release flows (Developer ID) — hook point in the
   script (`--sign "Developer ID Application: ..."` optional arg, default
   ad-hoc for local dev).
5. Record provenance: `Vendor/SOURCES.md` with exact tarballs, hashes, refs,
   and the licenses (rnp BSD-2, Botan BSD-2, json-c MIT, sexpp BSD) — these
   must also ship in the app's About/Licenses view (task 09 references this).

## Acceptance criteria

- Fresh clone + `./scripts/build-rnp-framework.sh` →
  `Vendor/RNPFramework.xcframework` exists; `file` shows arm64 + x86_64 slices.
- `xcodebuild -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO` succeeds on a
  machine WITHOUT librnp installed (temporarily rename /usr/local/lib/librnp*
  to prove it — restore after).
- `otool -L` on built MailPlugin.appex shows no absolute `/usr/local` or
  `/opt/homebrew` paths.
- `swift test` (pkg-config path) still 44/44 against both local librnp builds.
- CI green.

## Risks / notes

- Universal Botan build is the slowest leg (~10 min) — that's why CI caching
  matters. arm64-only is acceptable for local dev iterations.
- Keep the pinned rnp ref at v0.18.1 until a newer RELEASE exists; bump via
  PR that updates ref + hash + `Vendor/SOURCES.md` (see task 09 dep policy).
