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

## Legacy demo application

The `Swift-Rnp/` directory contains the original 2022 proof-of-concept: an
Apple Mail extension, a SwiftUI container app and two CLI targets. That code
does **not** build today — it depends on a private, Intel-only
`RNPFramework` sibling package that was never published — and is preserved
purely for historical/reference purposes. The SwiftPM package described
above is the supported path forward.

## License

The repository currently ships no license file; the original sources carry
no license headers either. Please contact the maintainers before reusing the
code in ways that require an explicit license.
