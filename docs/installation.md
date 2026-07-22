# Installation

RNP runs on **macOS 12 or later**. There are three ways to install it:
direct download (recommended for most users), the Mac App Store, or building
from source.

## Direct download (DMG)

Each [GitHub Release](https://github.com/rnpgp/swift-rnp/releases) carries a
Developer ID-signed and notarized disk image, `RNP-<version>.dmg`.

1. Download the latest `RNP-<version>.dmg` and open it.
2. Drag **RNP** into **Applications**. (The app bundle on disk is `RNP.app`;
   Finder and the Dock display it as **RNP**.)
3. Launch RNP from Applications and generate or import your OpenPGP key —
   see [Usage](usage.md#managing-keys).
4. Enable the Mail extension as described in
   [Enabling the extension](usage.md#enabling-the-extension).

> **Gatekeeper note.** On first launch, macOS may warn that the app was
> downloaded from the internet. Because the app is notarized, Control-click
> the app and choose **Open** to approve it.

## Mac App Store

An App Store build is prepared with the same sandbox and app group as the
direct-download release, signed with an Apple Distribution certificate and
uploaded by the
[`release-appstore.yml`](https://github.com/rnpgp/swift-rnp/blob/main/.github/workflows/release-appstore.yml)
pipeline. The store link is announced with the first App Store release; the
submission template and review notes live in
[`app-store/metadata.md`](app-store/metadata.md).

## Build from source

Building from source requires:

- **macOS 12+** with Xcode 15 or later (Swift 5.9+).
- **librnp 0.18.1 or later.** Version 0.18.1 is a security release fixing
  CVE-2025-13470 — older versions must not be used.

### 1. Install librnp

Either install the prebuilt package:

```sh
brew install rnp
```

or build librnp from source:

```sh
brew install botan json-c cmake pkg-config
git clone --recurse-submodules https://github.com/rnpgp/rnp.git
cmake -B rnp/build -DCRYPTO_BACKEND=botan3 -DBUILD_TESTING=OFF \
      -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release rnp
cmake --build rnp/build --parallel
sudo cmake --install rnp/build   # installs into /usr/local
```

### 2. Clone and open the project

```sh
git clone https://github.com/rnpgp/swift-rnp.git
cd swift-rnp
open Swift-Rnp/Swift-Rnp.xcodeproj
```

For a first local try-out no Apple Developer account is needed: select the
**RNP** scheme and run it (Product → Run). Unsigned local builds
work, but Mail.app will not load an unsigned or ad-hoc-signed extension, and
the keyring then lives in `~/Library/Application Support/RNP Mail Extension`
instead of the shared app-group container.

### 3. Sign for Mail integration

For Mail.app to load the extension, both targets must be signed:

1. In each target's **Signing & Capabilities** tab, set your
   **DEVELOPMENT_TEAM** (the project deliberately ships with it empty).
2. The default bundle identifiers are `com.rnpgp.RnpMail` (container) and
   `com.rnpgp.RnpMail.MailExtension` (extension), single-sourced in
   `Swift-Rnp/Shared/IDs.xcconfig`. If you change them, keep the extension ID
   prefixed by the app ID, and update the app group `group.com.rnpgp.RnpMail`
   in the same file to a group registered to your team.
3. Run the **RNP** scheme again so the signed extension is
   embedded and registered.

Command-line builds (as used in CI) work without signing configuration:

```sh
export PKG_CONFIG_PATH="$(pwd)/Vendor/pkgconfig"
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme RNP \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` builds are compile checks only — Mail will not load
the resulting extension.

### Release configurations

- **Direct** — Developer ID-signed, notarized direct downloads (default for
  local builds).
- **AppStore** — Apple Distribution-signed Mac App Store uploads. Use
  `-configuration AppStore` when archiving for App Store Connect.

Both share the same app group and sandboxing; only the signing identity
differs. The release pipeline is documented in
[Development](development.md#release-pipeline).

## After installing

Continue with the [Usage guide](usage.md) to create or import a key, enable
the extension in Mail, and send your first signed and encrypted message.

## Uninstalling

1. In Mail, uncheck **RNP OpenPGP** under Mail → Settings → Extensions.
2. Move the RNP app from Applications to the Trash.
3. Optionally delete the shared data (keyring, trust database, revocation
   certificates) from the app-group container
   `~/Library/Group Containers/group.com.rnpgp.RnpMail`, and the keyring
   passphrase item from the Keychain. **This permanently destroys your secret
   keys** — export them first if you might need them again.
