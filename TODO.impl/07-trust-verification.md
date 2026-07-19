# 07 — Trust & key verification

Status: pending · Milestone: M5 · Depends on: 04, 06

## Goal

A trustworthy, understandable answer to "is this really their key?": TOFU by
default, deliberate fingerprint verification, key-change warnings, and trust
surfaced in Mail — new `TrustStore` SPM target + UI.

## Model

Three states per recipient key (stored by fingerprint):
`unverified` (default, first seen = TOFU), `verified` (user confirmed
fingerprint), `problem` (expired / revoked / key CHANGED for a known
address — potential MITM, hard warning).

## Design

- `TrustStore`: signed JSON in the app-group container
  (`trust.json` + detached Ed25519 app signature using a per-install app key
  in Keychain — tamper-evident, not a remote trust). API:
  `state(forFpr:)`, `markVerified(fpr:)`, `noteSeen(email:fpr:)`,
  `conflicts() -> [TrustConflict]`. Migration-safe schema versioning.
- Key-change detection: `KeyManager` import path (task 06 fetch + manual
  import) checks existing key for same user ID email; different fingerprint →
  create conflict entry → UI requires explicit "Accept new key" before it
  can be used for encryption (engine refuses to encrypt to conflicted keys
  until resolved; signing verification shows warning).
- Verify UI: side-by-side fingerprint (grouped hex + spaced format) with
  "compare in person / over a trusted channel" copy, optional QR render of
  `OPENPGP4FPR:<FPR>` (CIQRCodeGenerator — no deps) for phone-side
  comparison; [Mark as verified] requires no checkbox-theater, one click is
  fine (the action IS the ceremony).
- Mail surfacing: extend the extension view controller (PR #13) to show per-
  signer trust next to MailKit's banner mapping:
  verified → "Signed by X — verified key"; unverified → "Signed by X — key
  not verified" + [Review in RnpMail] deep link (custom URL scheme
  `rnpmail://review/<fpr>` handled by container app); problem → warning copy.

## Tests

- TrustStore: CRUD, signature tamper-detection (flip a byte → load fails
  closed to `unverified`, logs), schema migration stub.
- Conflict flow: import key A for alice@x, fetch/import different key for
  same address → conflict raised; engine `encrypt` to that address throws
  `trustConflict`; after `markVerified` on new key + retire old, encrypt
  proceeds to the NEW key.
- Mail VC mapping: unit-test the pure mapping function
  `(SignatureStatus, TrustState) -> ViewModel` exhaustively.
- Full suite against both librnp installs.

## Acceptance criteria

- The three states are visible and correct in both the container app and the
  Mail extension UI; key substitution always requires explicit user action.
- Documentation: README "Trust model" section explaining TOFU + manual
  verify + why there's no web-of-trust UI (deliberate scope cut).

## Notes

- Do NOT implement GnuPG-style ownertrust/web-of-trust — out of scope by
  design (documented).
- Deep-link URL scheme must be registered in the container app Info.plist.
