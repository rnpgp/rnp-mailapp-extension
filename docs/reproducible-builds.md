# Reproducible builds

This doc explains how to verify that a published RNP release corresponds
to the source code at the corresponding tag.

## What "reproducible" means here

A build is *fully reproducible* when anyone can produce a byte-identical
binary from the same source + same toolchain. RNP releases are **almost
reproducible**: the unsigned Mach-O inside the app bundle can be
reproduced bit-for-bit, but the **code signature blob** is non-
reproducible because Apple's timestamp server embeds a unique token per
notarization request.

That means:
- **Verifiable**: anyone can confirm the published binary corresponds to
  the source by stripping the signature from both and comparing.
- **Not bit-identical**: re-notarizing the same source produces a
  different `.dmg` because the timestamp differs.

This is the same trade-off every Developer ID–distributed macOS app
faces. The trade-off is worth it — without notarization, macOS 14+
refuses to run the app at all.

## How to verify a release

```bash
scripts/reproduce-release.sh v0.9.6
```

The script:
1. Clones the repo at the specified tag
2. Downloads the published `.dmg`
3. Builds locally with `SOURCE_DATE_EPOCH` set to the tag's commit
   timestamp, `ZERO_AR_DATE=1`, `TZ=UTC`, `LC_ALL=C`
4. Strips the signature from both binaries
5. Compares SHA-256

A match means the published release was built from the source at the
tag, with no supply-chain shenanigans.

## What `release-direct.sh` does

The release pipeline sets:
- `SOURCE_DATE_EPOCH` — the tag's commit timestamp; libraries that honor
  it use this instead of `__DATE__` / `__TIME__`
- `ZERO_AR_DATE=1` — `ar` archives use a zero timestamp
- `TZ=UTC` — date-stamping is consistent across runner timezones
- `LC_ALL=C` — locale-independent sort order in any tool that sorts

What we can't control:
- **Swift module AST hashes** — embedded in `.swiftmodule` files; vary
  across Xcode point releases. Pin to Xcode 16.4.
- **Code signature blob** — embedded by Apple's timestamp server.
- **Mach-O UUID** — historically random; modern `ld` respects
  `SOURCE_DATE_EPOCH` if the linker is recent enough.

## Verifying without running the script

If you don't trust `reproduce-release.sh`, you can do the same steps
manually:

```bash
git clone --depth 1 --branch v0.9.6 https://github.com/rnpgp/rnp-mailapp-extension.git
cd rnp-mailapp-extension
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
export ZERO_AR_DATE=1 TZ=UTC LC_ALL=C
xcodebuild -project MailApp/RnpMail.xcodeproj -scheme RNP \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO \
    -destination 'generic/platform=macOS'

# Compare the unsigned Mach-O against the published DMG's
codesign -d --remove-signature MailApp/Build/Products/Direct/RNP.app/Contents/MacOS/RNP
shasum -a 256 MailApp/Build/Products/Direct/RNP.app/Contents/MacOS/RNP
```

Then download the published DMG, mount, strip its signature, and
compare.

## Limitations

- **App Store builds** are not reproducible — Apple's pipeline handles
  them and we don't control the toolchain.
- **Sparkle updates** — the EdDSA signature on `appcast.xml` is
  generated from the published DMG, so reproducing a build doesn't
  reproduce the appcast signature.
- **Xcode version drift** — minor Xcode releases can produce different
  binaries. The release pins Xcode 16.4; reproducing users need the
  same.

## See also

- TODO.complete/28-reproducible-builds.md
- Reproducible Builds project: https://reproducible-builds.org/
- Apple code signing + timestamps: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
