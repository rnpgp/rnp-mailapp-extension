# swift-rnp

Swift bindings for [librnp](https://github.com/rnpgp/rnp), the OpenPGP
(RFC 4880) library, built as a Swift Package Manager package.

The package exposes a small, safe, `Data`-based Swift API over the librnp C
FFI: key generation, key import/export, encryption/decryption, embedded and
detached signing/verification, and keyring save/load.

## Requirements

- **librnp ≥ 0.18.1.** Version 0.18.1 is a security release fixing
  [CVE-2025-13470](https://github.com/rnpgp/rnp/security/advisories)
  (PKESK session keys were generated without cryptographically random
  values) — do not use older releases. The test suite also passes against
  librnp built from the rnp `main` branch.
- **Swift 5.9+** (Xcode 15 or a swift.org toolchain).
- **macOS 12+** (other platforms are untested; see "Platform support").

## Installing librnp

Either install a prebuilt package:

```sh
brew install rnp
```

or build from source (this is what CI does; note that Homebrew's `botan`
formula is Botan 3, hence `CRYPTO_BACKEND=botan3`):

```sh
brew install botan json-c cmake pkg-config
git clone --recurse-submodules https://github.com/rnpgp/rnp.git
cmake -B rnp/build -DCRYPTO_BACKEND=botan3 -DBUILD_TESTING=OFF \
      -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release rnp
cmake --build rnp/build --parallel
sudo cmake --install rnp/build   # installs into /usr/local
```

## Building and testing

The `CRnp` system-library target locates librnp via `pkg-config`
(`librnp.pc`). When librnp is installed in a default prefix (`/usr/local`,
Homebrew), no extra setup is needed:

```sh
swift build
swift test
```

When librnp lives in a custom prefix, point `pkg-config` at it and make the
dynamic linker find the library. Note that `DYLD_LIBRARY_PATH` is **not**
honored by Xcode's hardened-runtime test runner, so pass an rpath instead:

```sh
export PKG_CONFIG_PATH=/path/to/librnp/lib/pkgconfig:$PKG_CONFIG_PATH
swift build
swift test -Xlinker -rpath -Xlinker /path/to/librnp/lib
```

(If `pkg-config` wiring is unavailable, the equivalent explicit flags are
`swift build -Xcc -I<prefix>/include -Xlinker -L<prefix>/lib -Xlinker -lrnp`.)

## Usage

```swift
import Foundation
import Rnp

// Context with in-memory keyrings; all passphrase prompts get "password".
let rnp = try Rnp(password: "password")

// Generate an RSA-3072 key pair (librnp 0.18 default), password-protected.
try rnp.generateKey(json: Rnp.rsaKeyGenJSON(userid: "Test <t@t>"))
let key = try rnp.requireKey("Test <t@t>")

// Encrypt and decrypt.
let message = Data("hello OpenPGP".utf8)
let encrypted = try rnp.encrypt(message, for: [key])
let decrypted = try rnp.decrypt(encrypted)
assert(decrypted == message)

// Sign (embedded or detached) and verify.
let signed = try rnp.sign(message, with: key)
let verified = try rnp.verify(signed)
let signature = try rnp.signDetached(message, with: key)
try rnp.verifyDetached(signature: signature, data: message)
```

The API surface covers: version queries (`Rnp.versionString`,
`Rnp.versionStringFull`), key generation from JSON
(`Rnp.rsaKeyGenJSON` / `Rnp.ecdsaP256KeyGenJSON` or your own JSON),
key lookup (`locateKey` / `requireKey` by userid, fingerprint, keyid or
grip), key export (`RnpKey.exportKey`, armored public/secret) and import
(`importKeys`), keyring save/load (`savePublicKeys`, `saveSecretKeys`,
`loadKeys`), encryption (`encrypt` / `decrypt`) and signing
(`sign` / `signDetached` / `verify` / `verifyDetached`). librnp errors are
thrown as `RnpError`, carrying the `rnp_result_t` code and its
`rnp_result_to_string()` description.

## Platform support

CI (`.github/workflows/test.yml`) runs on **macOS only**, against librnp
`v0.18.1` and librnp from the rnp default branch. A Linux leg was considered,
but GitHub's Ubuntu runners ship no Swift toolchain and the required install
dance could not be validated reliably; the package itself has no
macOS-specific code beyond Foundation/XCTest, so Linux support should be a
matter of CI plumbing (contributions welcome).

## Use with Apple Mail

The `Swift-Rnp/` directory contains `Swift-Rnp.xcodeproj`, an Apple Mail
OpenPGP extension plus its container app, built entirely on the SwiftPM
package above:

- **`MailSecurityEngine`** (SwiftPM target, `Sources/MailSecurityEngine`) —
  all non-MailKit logic: PGP/MIME (RFC 3156) and inline-PGP encode/decode of
  RFC 822 message data, and a `KeyManager` backed by a keyring directory
  (`pubring.gpg` / `secring.gpg`) with generate/import/export/list/delete.
  Fully covered by `swift test` — no Xcode required.
- **`MailPlugin`** (app extension target) — a thin MailKit shell
  (`MEMessageSecurityHandler`) delegating all OpenPGP work to
  `MailSecurityEngine`.
- **Ribose container** (SwiftUI app target) — key manager UI (generate
  RSA/ECDSA keys, import armored keys from clipboard or file, export the
  armored public key to the clipboard, delete keys).
- **`Swift-Rnp`** (CLI target) — small `Rnp` demo: version print plus a
  generate/encrypt/decrypt smoke roundtrip.

The shared keyring lives in the app group container `group.com.rnpgp.RnpMail`
so both processes see the same keys; key passphrases are stored in the
Keychain (access group `$(AppIdentifierPrefix)group.com.rnpgp.RnpMail`), never
in UserDefaults.

### Install librnp

Either `brew install rnp`, or build from source as shown in
[Installing librnp](#installing-librnp). Version 0.18.1 or later is required.

The Xcode project finds librnp the same way the package does: pkg-config
(see `Swift-Rnp/librnp.xcconfig`). When librnp is not in a standard prefix,
point pkg-config at it when invoking `xcodebuild`:

```sh
PKG_CONFIG_PATH=/path/to/librnp/lib/pkgconfig \
  xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin build
```

(For a custom prefix also pass `LIBRNP_PREFIX=/path/to/librnp` so the
runtime rpath is right; `/usr/local` and `/opt/homebrew` are covered by
default.)

### Build and run

For a first local try-out no Apple Developer account is needed:

1. Open `Swift-Rnp/Swift-Rnp.xcodeproj` in Xcode.
2. Select the **Ribose container** scheme and build/run it
   (Product → Run). Unsigned local builds work; Xcode simply embeds no
   entitlements, and the keyring then lives in
   `~/Library/Application Support/RNP Mail Extension` instead of the app
   group container.
3. In the app, generate a key pair (＋ menu → RSA-3072 or ECDSA P-256) with
   a user ID matching your mail address ("Alice <alice@example.com>"), or
   import an existing key (arrow-down menu → from clipboard or file).

For Mail.app to actually load the extension you must sign both targets:

4. In each target's **Signing & Capabilities** tab, set your
   **DEVELOPMENT_TEAM** (the project deliberately ships with it empty).
   The default bundle IDs are `com.rnpgp.RnpMail` (container) and
   `com.rnpgp.RnpMail.MailExtension` (extension). IDs are single-sourced in
   `Swift-Rnp/Shared/IDs.xcconfig` and injected into both targets' entitlements
   and Info.plist at build time. If you change them, keep the extension ID
   prefixed by the app ID, and update the app group `group.com.rnpgp.RnpMail`
   in `Swift-Rnp/Shared/IDs.xcconfig` to a group registered to your team.
5. Run the **Ribose container** scheme once more so the signed extension is
   embedded and registered, then enable it in
   **Mail → Settings → Extensions** (check "RNP OpenPGP").
6. Compose a message: the security button in the compose window now offers
   sign and encrypt. Encrypting requires the recipients' public keys —
   import them in the container app first. Incoming signed/encrypted mail
   is decrypted and verified automatically, with the signature status shown
   in the message banner.

Command-line builds (as used in CI) work without signing configuration. The
Xcode project consumes the SwiftPM package, whose `CRnp` system-library target
resolves headers and linking via `pkg-config`. Point `PKG_CONFIG_PATH` at the
vendored framework's `.pc` file:

```sh
export PKG_CONFIG_PATH="$(pwd)/Vendor/pkgconfig"
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme MailPlugin \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Swift-Rnp/Swift-Rnp.xcodeproj -scheme "Ribose container" \
    -configuration Direct build CODE_SIGNING_ALLOWED=NO
```

Two release-channel configurations are provided:
- `Direct` — for Developer ID-signed, notarized direct downloads (default for
  local builds).
- `AppStore` — for Apple Distribution-signed Mac App Store uploads.

Both share the same app group and sandboxing; only the signing identity differs.
Use `-configuration AppStore` when archiving for App Store Connect.

### Install (direct download)

The latest signed and notarized DMG is attached to each [GitHub
Release](https://github.com/rnpgp/rnp-mailapp-extension/releases).

1. Download `RnpMail-<version>.dmg` and open it.
2. Drag **RnpMail** (the `Ribose container` app) into **Applications**.
3. Launch the app from Applications, generate or import your OpenPGP key.
4. Open **Mail → Settings → Extensions**, check **RNP OpenPGP**, and click
   **Done**.
5. Compose a message; use the security button in the compose window to sign
   and/or encrypt.

> On first launch, macOS may show a Gatekeeper warning because the app is
> distributed outside the Mac App Store. Control-click the app and choose
> **Open** to approve it.

### Limitations

- **MailKit requires proper signing.** Mail.app refuses to load extensions
  that are ad-hoc signed or unsigned, so `CODE_SIGNING_ALLOWED=NO` builds
  are for compile checks only. The Xcode project embeds a self-contained
  `RNPFramework.xcframework` (built by `scripts/build-rnp-framework.sh`) in
  both the container app and the Mail extension, so a signed deployment has
  no dependency on `/usr/local` or `/opt/homebrew`.
- **Inline PGP vs PGP/MIME.** The extension emits PGP/MIME (RFC 3156)
  messages, which preserve attachments and non-ASCII content exactly; on
  decode it accepts both PGP/MIME and inline-PGP (armored blocks in
  text/plain parts, including inside multipart/mixed). Inline-PGP *encoding*
  is available in the engine (`MessageFormat.inlinePGP`) for single-part
  text messages only.
- **One keyring passphrase.** All generated keys share a single random
  passphrase stored in the Keychain; imported keys keep whatever protection
  they arrived with, so their passphrases are not asked for — operations
  needing such a key's secret material can fail. There is no per-key
  passphrase UI.
- **No SmartCard/HSM support.** Only software keys in the local keyring can
  be used; librnp's G10 keyring format is not used by the key manager.

## License

The repository currently ships no license file; the original sources carry
no license headers either. Please contact the maintainers before reusing the
code in ways that require an explicit license.
