# Task 01 — Vendored RNPFramework.xcframework

Source: `TODO.impl/01-rnpframework-xcframework.md`

Status: in progress. Partial work exists: `scripts/build-rnp-framework.sh` and an arm64-only `Vendor/RNPFramework.xcframework` built via the script's `USE_PREFIX` fast path.

## Goal

Eliminate the "install librnp separately" requirement for the Xcode app: build a self-contained universal `RNPFramework.xcframework` (librnp + all non-system deps statically linked) from pinned rnp sources, consumable by the Xcode targets. This is REQUIRED for App Store sandboxing and distribution.

## Required final state

1. `scripts/build-rnp-framework.sh`:
   - Args: `--rnp-ref v0.18.1` (default), `--out Vendor/RNPFramework.xcframework`.
   - Download the rnp tarball, verify against a SHA256 recorded in `scripts/rnp-<ref>.sha256` (generate this file when writing the script: `curl -sL <url> | shasum -a 256`; do NOT invent a hash).
   - Build Botan 3 static, json-c static, then rnp with `-DCRYPTO_BACKEND=botan3 -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING_OFF -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_POSITION_INDEPENDENT_CODE=ON` and static dep paths via `-DCMAKE_PREFIX_PATH`.
   - Link ONE combined dylib `RNPFramework` from librnp.a + libbotan-3.a + libjson-c.a + libsexpp.a (system z/bz2/c++ remain dynamic). Export only rnp_* symbols (use `-exported_symbols_list`).
   - Wrap as `RNPFramework.framework` (Headers: `rnp/rnp.h`, `rnp_err.h`, generated `rnp_export.h`, `rnp_ver.h`; Info.plist; module map), then `xcodebuild -create-xcframework`.
   - Optional `--sign "Developer ID Application: ..."` arg, default ad-hoc for local dev.
2. `Vendor/SOURCES.md` with exact tarballs, hashes, refs, and licenses (rnp BSD-2, Botan BSD-2, json-c MIT, sexpp BSD).
3. Wire Xcode consumers:
   - Replace `librnp.xcconfig` usage with `FRAMEWORK_SEARCH_PATHS` to `Vendor/` + embed framework in both the app (`Contents/Frameworks`) and the appex.
   - Verify no `/usr/local` reference remains: `otool -L` on the built .appex must show only `@rpath` + system.
4. CI (`.github/workflows/test.yml`):
   - Cache `Vendor/RNPFramework.xcframework` keyed by rnp ref + script hash.
   - Build it when absent; remove the "build librnp from source + sudo install" steps for the xcodebuild legs (keep them for the pure-SPM `swift test` legs, which still use pkg-config).
5. Keep `swift test` (pkg-config path) working. The SPM `Package.swift` currently uses `CRnp` systemLibrary with pkg-config. The simplest reliable split is acceptable: Xcode targets use the vendored framework; SPM tests use pkg-config. If you can cleanly add a `binaryTarget` without breaking `swift test`, do so; otherwise document the split in `Vendor/SOURCES.md` and the README.

## Acceptance criteria

- Fresh clone + `./scripts/build-rnp-framework.sh` → `Vendor/RNPFramework.xcframework` exists; `file` shows arm64 + x86_64 slices.
- `xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO` succeeds on a machine WITHOUT librnp installed.
- `otool -L` on built `MailPlugin.appex` shows no absolute `/usr/local` or `/opt/homebrew` paths.
- `swift test` (pkg-config path) still 44/44 against both local librnp installs:
  - `/Users/mulgogi/src/rnp/rnp/builds/downstream/v0.18.1`
  - `/Users/mulgogi/src/rnp/rnp/builds/downstream/main`
- CI green (at least the workflow file is valid and logically correct; you cannot run actual CI here).

## Current state to extend

- `scripts/build-rnp-framework.sh` exists and has both a fast local-prefix path and a full source-build path. The source-build path has not been run end-to-end. Review and fix any bugs (e.g. hash verification ordering, sexpp shallow-clone checkout) before running it.
- `Vendor/RNPFramework.xcframework` currently only contains a `macos-arm64` slice built from local arm64 static libs. It must be replaced with a universal `macos-arm64_x86_64` slice.
- `Swift-Rnp/Shared/RNPFramework.xcconfig` exists; `Swift-Rnp/librnp.xcconfig` is deleted in the working tree but the project file may still reference it — clean that up.
- `scripts/patch-xcodeproj.rb` already wired `FRAMEWORK_SEARCH_PATHS`, linking, and embedding for `MailPlugin` and `Ribose container`. Verify it is correct and update it if needed.

## Notes

- Universal Botan build is the slowest leg (~10 min). CI caching matters.
- Keep rnp ref at v0.18.1.
- Do not commit built tarballs or work dirs (`.build/framework-work` is already git-ignored via `.build/`).
