# Apple Export Compliance Letter

Template for App Review's "App Encryption Documentation" upload, used only
if `ITSAppUsesNonExemptEncryption = false` in `Info.plist` is rejected.

RNP for Mail is open-source software; this letter documents the open-source
encryption exemption under 31 CFR § 740.13(e).

---

**To:** Apple App Review
**Re:** Export compliance for *RNP for Mail* (`com.rnpgp.RNPForMail`)
**Date:** [fill in submission date]

## App overview

*RNP for Mail* is an Apple Mail extension and companion container app that
brings OpenPGP encryption and signature verification to Apple Mail on macOS.
The app is **publicly available as open-source software**:

- Source repository: https://github.com/rnpgp/rnp-mailapp-extension
- License: BSD-2-Clause
- No fee is charged for the app or for access to the source code

## Cryptography used

The app uses **standard, publicly known cryptographic algorithms** that are
either published by international standards bodies or have been published
in peer-reviewed academic literature and are widely implemented by other
open-source projects:

- **Symmetric**: AES-128, AES-256 (FIPS 197; NSP NIST standard)
- **AEAD**: OCB, EAX, GCM (RFC 7253, RFC 5297, NIST SP 800-38D)
- **Asymmetric**: RSA (PKCS#1), ECDH on Curve25519 (RFC 7748), EdDSA
  Ed25519 (RFC 8032), ElGamal
- **Hashing**: SHA-1, SHA-2 family (FIPS 180)
- **Post-quantum**: ML-KEM-768 (FIPS 203), ML-DSA-65 (FIPS 204),
  SLH-DSA-SHA2 (FIPS 205) — all NIST post-quantum standards
- **OpenPGP protocol**: RFC 9580 (formerly RFC 4880)

All cryptography is provided by **librnp** (https://github.com/rnpgp/rnp),
a BSD-licensed OpenPGP library, which itself uses **Botan**
(https://botan.randombit.net/) for cryptographic primitives. Neither
library implements any proprietary or non-standard algorithm.

## Applicability of the open-source exemption

Under **31 CFR § 740.13(e)** of the U.S. Export Administration Regulations
(EAR), the following items are exempt from EAR controls:

> (e) **Open source software**. Open source software (i.e., software whose
> source code is publicly available and that is not subject to copyright
> or other restrictions on its use, modification, or redistribution) ...

RNP for Mail meets this exemption because:

1. **Source code is publicly available**: every source file is committed
   to the public GitHub repository, including build scripts, dependency
   manifests, and the vendored librnp / Botan sources.
2. **No use restrictions beyond the BSD license**: the source code is
   freely modifiable and redistributable under BSD-2-Clause.
3. **No fee**: the app is distributed free of charge; the source code is
   available at no cost.
4. **Standard, public algorithms only**: no proprietary cryptography,
   no custom cipher design, no algorithm obfuscation.
5. **Already publicly disclosed**: the cryptography used has been
   published in academic literature and IETF/NIST standards since well
   before the app's first distribution.

## Conclusion

RNP for Mail is **"publicly available"** open-source software within the
meaning of 31 CFR § 740.13(e) and is therefore **not subject to the EAR**.
It qualifies for the Export Administration Regulations' open-source
exemption and may be distributed on the App Store worldwide without
separate encryption export authorization.

Please contact **security@rnpgp.org** if additional documentation is
required.
