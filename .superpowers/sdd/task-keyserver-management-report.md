# Task report: keyserver management (add known keyservers)

Branch: `feat/keyserver-management` (from `main`)

## Goal

Let users configure the keyservers used for key discovery and publishing:

1. A `KeyServerSettings` model persisting an ordered keyserver list
   (VKS, WKD, HKPS) in the app-group container, with built-in defaults
   (keys.openpgp.org via VKS, WKD) and user-added custom HKPS servers.
2. A keyserver settings view in the container app: see the list, add /
   remove custom HKPS servers, set the priority order for discovery.
3. The configured HKPS servers wired into key discovery and publishing,
   with fallback to VKS/WKD when HKPS fails.
4. Tests for the settings model and the HKPS fetch; all existing tests
   keep passing. No `MailSecurityEngine` API changes.

## What was implemented

### 1. Settings model (`Sources/KeyServerClient/KeyServerSettings.swift`, new)

- **`KeyServerKind`** — `.vks` (keys.openpgp.org Verified Keyserver API),
  `.wkd` (Web Key Directory), `.hkps` (HKP over HTTPS).
- **`KeyServer`** — one list entry (`kind` + `host`; host is empty for
  WKD, which derives the host from the email domain). `Identifiable` for
  the SwiftUI list; `isCustom` marks entries that are not built-in
  defaults (only customs are removable in the UI).
- **`KeyServerSettings`** — the ordered server list. Earlier entries are
  tried first; on failure the next one is tried (fallback).
  `defaultServers` reproduces the previously hardcoded behavior:
  `[wkd, vks(keys.openpgp.org), hkps(keys.openpgp.org), hkps(keyserver.ubuntu.com)]`.
  `normalizedHKPSHost(_:)` validates user input (accepts pasted URLs,
  strips scheme/path/port, lowercases, RFC 1123 label check; rejects
  empty labels such as `a..b`).
  `sanitized()` drops duplicates and invalid entries.
- **`KeyServerSettingsStore`** — JSON-encodes the settings into
  `UserDefaults` under the `keyServers` key. The default suite is the
  app group (`UserDefaults(suiteName:)`, falling back to `.standard`),
  so the container app and the Mail extension share the configuration —
  the same pattern as `RecipientKeyAutoFetch`. The app-group identifier
  resolution mirrors `AppGroup.identifier` (duplicated with a comment:
  KeyServerClient is a *dependency* of MailSecurityEngine and cannot
  import it). `load()` falls back to the defaults when nothing is
  stored, the data is corrupt, or sanitizing empties the list.

### 2. HKPS client support (`Sources/KeyServerClient/`)

- **`HKPSServer` is now a struct** (`RawRepresentable` over the host
  name) instead of a two-case enum, so custom hosts are representable.
  `.keysOpenPGP`, `.ubuntu`, and `allCases` keep the old call sites
  source-compatible; gained `addURL` next to `lookupURL`.
- **Protocol gained `uploadHKPS(armoredKey:server:)`** — HKP upload via
  POST to `/pks/add` with a `keytext=` form body
  (`URLSessionKeyServerClient` implements it, mapping 400 →
  `.malformedKey`, other non-200 → `.server`). `MockKeyServerClient`
  records `hkpsUploads` and returns a scripted `hkpsUploadResult`.

### 3. Wiring (`Sources/MailSecurityEngine/KeyServerService.swift`)

**Public API unchanged** — same signatures, same default behavior; only
the bodies now iterate the configured list (loaded from the shared store
on every call, so edits take effect without restarting either process):

- `discoverByEmail` — per entry: WKD → advanced then direct; VKS →
  by-email; HKPS skipped (HKP lookup is by fingerprint/key ID, not
  email).
- `discoverByFingerprint` — per entry: VKS → by-fingerprint; HKPS →
  `fetchHKPS` on the entry's host (this is the previously dead-code
  path, now configurable); WKD skipped (needs an email address).
- `upload` — per entry: HKPS → `/pks/add`; VKS → keys.openpgp.org
  upload; WKD skipped (cannot accept uploads). A failing HKPS server
  falls back to VKS and vice versa; the last error is thrown when all
  fail.
- An `internal init(client:fixedSettings:)` (visible via `@testable`)
  lets tests pin the list without touching shared defaults. The
  container app's `KeysManager` and the extension's
  `MessageSecurityCore` needed no changes — they construct the service
  as before and now transparently honor the configured list.

### 4. Settings view (`Sources/RnpMailUI/KeyServerSettingsView.swift`, new)

- Lives in RnpMailUI (like `TrustHistoryView`), so no Xcode project
  edits were needed — the app consumes the repo-root `Package.swift` as
  a local package; `Package.swift` gained `KeyServerClient` in
  RnpMailUI's dependencies.
- Shows the ordered list with kind badges (VKS/WKD/HKPS) and a "Custom"
  badge on user-added HKPS servers; selection-based **Move Up / Move
  Down** sets the discovery priority; **Remove** is enabled only for
  custom HKPS entries; **Reset to Defaults** restores the built-in list;
  a host field + **Add Server** validates and appends a custom HKPS
  server (inline error for invalid/duplicate input). Every mutation
  persists immediately via the store.
- Wired into the container app like the licenses sheet: a
  "Keyservers…" menu item posts `.showKeyServerSettings`, which
  `ContentView` presents as a sheet. All strings added to
  `Localizable.xcstrings` (16 keys × 11 locales, en `translated`,
  others `needs_review`, matching the existing convention; pure
  insertion, no reformatting).

### 5. Tests

- `Tests/KeyServerClientTests/KeyServerSettingsTests.swift` (new):
  defaults match the old hardcoded behavior, Codable roundtrip,
  `isCustom`, sanitizing (dupes/invalid), host normalization edge cases,
  store save/load, persistence across instances, corrupt data →
  defaults, empty list → defaults, reset. Each test uses an isolated
  `UserDefaults` suite, removed in tearDown.
- `Tests/KeyServerClientTests/KeyServerClientTests.swift` (extended):
  HKPS lookup URL construction (`op=get&options=mr&search=0x…`),
  lowercase/spaced fingerprint normalization, custom-server host,
  invalid fingerprint, 404 → `.notFound`, HKPS upload posts `keytext=`
  to `/pks/add`, mock upload recording — all via the existing
  `StubURLProtocol`.
- `Tests/MailSecurityEngineTests/KeyServerServiceSettingsTests.swift`
  (new): configured order is honored, HKPS↔VKS fallback in both
  directions for discovery and upload, WKD/HKPS per-kind applicability
  (WKD skipped for fingerprints, HKPS skipped for emails), last error
  surfaces when all servers fail.

## Verification

All three commands pass on the final sources:

1. `PKG_CONFIG_PATH=…/v0.18.1/lib/pkgconfig swift test -Xlinker -rpath -Xlinker …/lib`
   — **exit 0; 292 tests, 0 failures** (including the new
   `KeyServerSettingsTests` and `KeyServerServiceSettingsTests` suites;
   snapshot warnings are the pre-existing, machine-specific
   font-rendering ones).
2. `xcodebuild -scheme RNP build CODE_SIGNING_ALLOWED=NO` — **BUILD
   SUCCEEDED**.
3. `xcodebuild -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO` —
   **BUILD SUCCEEDED**.

## Notes / follow-ups

- HKPS applies to fingerprint lookups and uploads only; HKP has no
  standardized by-email fetch, so email discovery uses WKD and VKS. If
  by-email HKP search (`op=get&search=<email>`) is wanted later, it is a
  small additive change to the client and service.
- Custom VKS hosts are not offered in the UI (VKS is the
  keys.openpgp.org API); the model tolerates them, and the client would
  need a per-host `baseURL` to actually honor them.
- `KeyServerService` reads the store per call; on a machine where a
  user actually saved custom settings, unit tests that construct the
  service with the default initializer would see them. Tests that pin
  settings use `init(client:fixedSettings:)`, so the suite is
  deterministic regardless.
