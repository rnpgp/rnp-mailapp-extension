# 06 — Keyserver publishing & discovery (VKS / HKPS / WKD)

Status: pending · Milestone: M4 · Depends on: 01

## Goal

Publish your public key where correspondents can find it, and discover/
refresh other people's keys — new `KeyServerClient` SPM target (pure
URLSession, fully mockable) + UI flows + background refresh.

## API surface (verified endpoints)

- keys.openpgp.org VKS:
  - Upload: `POST https://keys.openpgp.org/vks/v1/upload`, body = armored
    public key, `Content-Type: text/plain` → 200; the server then emails a
    verification link per user ID (first upload is NOT discoverable until
    verified).
  - Discover: `GET /vks/v1/by-email/<email>` (404 until verified),
    `GET /vks/v1/by-fingerprint/<fpr>` (works without verification).
- HKPS (keys.openpgp.org + keyserver.ubuntu.com):
  `GET /pks/lookup?op=get&options=mr&search=0x<FPR>` → armored key.
- WKD (recipient discovery, read-only):
  `https://<domain>/.well-known/openpgpkey/hu/<zbase32(sha1(localpart))>?l=<urlencoded localpart>`
  — implement SHA-1 via CryptoKit `Insecure.SHA1` + z-base-32 encoding
  (spec: OpenPGP Web Key Directory draft; implement the encoder locally,
  ~40 lines, no new deps).

## Design

- `KeyServerClient` protocol + `URLSessionKeyServerClient` +
  `MockKeyServerClient` (scripted responses) for tests. Methods:
  `upload(armored:) throws -> UploadReceipt`, `fetchByEmail(_:)`,
  `fetchByFingerprint(_:)`, `fetchWKD(email:)`, all `async`.
- `KeyRefreshService` (in MailSecurityEngine or own target): refresh all
  recipient keys on a schedule (default 24h, container-app driven — no
  background daemon), import updated keys (rotation/revocation propagation),
  log to Activity tab. Respect offline: queue + retry with backoff.
- Publish flow UI (from Keys detail + onboarding last step):
  1. "Publish public key" → uploads → state `pendingVerification(email)`.
  2. Explain: "keys.openpgp.org emailed you a verification link — click it."
     Poll `by-email` every 30s (max 15 min) until visible → state `published`.
  3. Persist publish state per key in the app-group store; surface in Keys
     list (cloud icon states).
- Fetch UI: Recipients tab "+" → by email (WKD first, then VKS by-email,
  then HKPS), by fingerprint; shows fetched key summary → confirm import
  (never silently import — key substitution is an attack vector; tie into
  task 07 trust).

## Tests

- Mock-client tests: all paths incl. 404-until-verified, malformed armor,
  network failure retry, WKD hash correctness against known test vectors
  (use the draft's example: `joe@example.org` → known hu value; look it up in
  the WKD draft when writing the test, don't invent).
- Live integration test against keys.openpgp.org: fetch a well-known key
  (e.g. the rnp signing key from rnpgp/rnp docs) — nightly CI schedule ONLY,
  never per-PR (flakiness).
- Round-trip: upload a throwaway test key from CI nightly, verify by-fpr
  fetch returns it (skip email verification in test).

## Acceptance criteria

- Publish flow completes end-to-end manually against keys.openpgp.org with a
  test key; state machine persisted across app restarts.
- Recipient fetch: WKD domain (test with a known WKD-published address) and
  VKS both import the correct key; failure UX is one sentence + retry.
- No network call from the appex blocks message encode/decode (all key
  resolution is pre-send via container app / cached keyring).

## Notes

- Entitlement: container app needs `com.apple.security.network.client`
  (added in task 02).
- Privacy: document in README that keyserver lookups leak the looked-up
  address to the server (standard caveat), setting to disable WKD.
