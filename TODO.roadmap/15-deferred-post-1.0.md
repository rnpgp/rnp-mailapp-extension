# 15 — Deferred past 1.0 (and why)

Status: parked · Tier: Future · Depends on: nothing

## Goal

A single record of features that have been considered and deliberately
deferred past 1.0, with the reason and the trigger that would un-defer
them. This prevents the same conversation from happening three times.

Each entry: the feature, why it's deferred, what would change the decision,
and the rough shape of the work if/when it lands.

---

## 1. Hardware token / SmartCard / YubiKey / OpenPGP card

**Why deferred**: significant FFI surface and UX work; librnp's
smartcard support is via Botan's PKCS#11 / PCSC interface, which is
non-trivial to wire through Swift. macOS SmartCard support is also more
limited than Linux.

**Trigger**: a documented user demand from security-conscious power
users (the audience that would adopt this for high-stakes mail), or a
sponsor who needs it for compliance.

**Shape**: new `Rnp.SmartCardSession` wrapper around Botan's PCSC;
`KeyManager` extension to use an external (`RNP_KEY_LOC_TOKEN`) key for
signing; UI to import the public half of a token-stored key, with a
"signing key is on hardware" indicator. Multi-day effort; security
review required (token presence, PIN caching, etc.).

**Related FAQ**: `docs/faq.md` "Can I use a SmartCard or hardware
token?" — currently "No." Re-answer when this lands.

---

## 2. Primary offline / subkey online key generation flow

**Why deferred**: complex UX (the flow involves generating a primary on an
offline machine, transferring via encrypted USB, generating per-device
subkeys, exporting subkey-only keyrings). The benefit is real (device
loss only compromises one encryption subkey) but the audience is small
for 1.0.

**Trigger**: power-user demand; or as part of a "pro" mode for
journalists / security trainers.

**Shape**: a guided wizard that walks through primary generation, USB
transfer, per-device subkey generation. Probably shares infrastructure
with `05-key-transition-wizard`. The librnp FFI for subkey-only export
exists.

---

## 3. iOS companion app (decryption from share sheet)

**Why deferred**: iOS does not allow third-party Mail extensions the way
macOS does. A companion app would have to work via the iOS share sheet
(user shares an email from Mail to the RNP iOS app, which decrypts and
displays). Different codebase, different crypto story (librnp on iOS is
possible but not trivial), different release pipeline (App Store for
iOS).

**Trigger**: user demand for reading encrypted mail on iPhone / iPad.
Significant.

**Shape**: a new iOS app target sharing the SwiftPM modules
(`MailSecurityEngine`, `Rnp`, `TrustStore`) via a multi-platform
Package.swift. iCloud Keychain sync (see `01-disaster-recovery.md`)
becomes the primary secret-distribution mechanism. The share-sheet
interface to Mail is the UX model. Multi-week effort.

---

## 4. Decrypted-body search index

**Why deferred**: significant security trade-off. A local index of
decrypted message bodies, encrypted at rest with a separate index key,
would enable Spotlight-style body search. But the index key is a new
high-value target, and the index itself leaks content (deterministic
tokens reveal patterns). Requires a threat-model review.

**Trigger**: user demand that materially outweighs the security cost;
or a design that uses oblivious / private-information-retrieval
techniques (research-grade, not ready for production).

**Shape**: a new `SearchIndex` SPM target that consumes decoded
messages, builds a tokenized encrypted index, and exposes a query API.
Spotlight integration via `CSSearchableIndex`. The index key is derived
from a Keychain item with Touch ID ACL. Multi-week effort; security
review first.

---

## 5. Per-identity keyrings (one keyring per Mail account)

**Why deferred**: complex UX (which keyring does this message belong
to? how do you encrypt across accounts?) and limited benefit for most
users. Today, one keyring with all keys + UID-based selection works.

**Trigger**: enterprise / multi-tenant users who need strict isolation
between work and personal keys.

**Shape**: extend `KeyManager` to manage multiple keyring directories,
each tied to a Mail account. Compose with `10-multi-uid-keys.md` for
the common case of "I want my work email and personal email on the same
key."

---

## 6. Sealed Sender / per-recipient subject schemes

**Why deferred**: requires non-standard MIME constructs that other PGP
clients don't understand. Limited interop value.

**Trigger**: a community standard emerges (e.g., a future RFC for
"protected envelope" beyond Memory Hole).

---

## 7. WKD verification and SKS pool / keyserver gossip

**Why deferred**: keys.openpgp.org is the de facto standard and works
without gossip. SKS pool is deprecated. WKD is already implemented
(read-only).

**Trigger**: a keyserver-privacy push that requires gossip; or a
specific institutional WKD deployment that we want to publish to.

---

## 8. Email alias / "hide my email" support

**Why deferred**: Apple's Hide My Email forwards to a real address; PGP
keys are typically bound to the real address. Mapping aliases to
underlying keys is a UX problem more than a crypto one.

**Trigger**: user demand; coordinate with Fastmail / iCloud Hide My
Email semantics.

---

## 9. Time-of-signature verification UI

**Why deferred**: edge-case forensic feature. The verifier already
checks signature creation time vs. key validity; surfacing "this
signature was made at time T, when the key was valid" is interesting
for power users but not blocking.

**Trigger**: legal / forensic use cases.

---

## 10. PQC-only SLH-DSA default

**Why deferred in 11**: SLH-DSA is conservative (hash-based, no lattice
assumptions) but signatures are very large (~50 KB). For 1.0 the
recommended PQ default is the hybrid `ML-DSA-65+ED25519`. SLH-DSA is
offered as an option for users who explicitly don't trust lattice-based
cryptography.

**Trigger**: a break of ML-DSA or a community shift toward SLH-DSA as
the conservative default.

---

## Updates to this list

When something is un-deferred, move it to its own `NN-*.md` file with a
full design (do not just delete it from here — note the move). When
something new is considered and deferred, add it here with the same
fields. Keep this file honest: it's the "we thought about it" record.
