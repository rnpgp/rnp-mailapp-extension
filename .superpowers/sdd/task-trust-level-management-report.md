# Task report: trust level management (reject key change, trust history)

Branch: `feat/trust-level-management` (from `main`)

## Goal

Add a "reject key change" conflict resolution path and a trust history view:

1. `TrustStore.rejectConflict(email:newFpr:)` keeps the old binding and marks
   the new key as problem; encryption afterwards proceeds to the old key.
2. A "Reject new key" / "Keep old binding" action in the trust-conflict
   banner and the key detail view.
3. A trust history view in the container app showing the `TrustRecord`
   history for an address (seen keys, when they were marked
   verified/problem), presented as a "Trust" sheet.
4. No `MailSecurityEngine` API changes; all existing tests keep passing.

## Key finding from probing

A scratch probe (deleted afterwards) imported two different keys for the
same address into one keyring and asked `KeyManager.publicKey(for:)` which
one resolves: **the first-imported (old) key wins**. That makes a
TrustStore-only reject path sufficient for "encrypt to the old key": after
`rejectConflict` restores the old binding as the active record, the
engine's existing checks (`hasConflict` false, resolved key's state not
`.problem`) let `encode` proceed, and it proceeds to the old key. Verified
end-to-end by `testRejectConflictEncryptsToOldKey`, which decrypts the
message with the old key and shows the rejected key cannot decrypt it.

## What was implemented

### 1. TrustStore (`Sources/TrustStore/TrustStore.swift`)

- **History log.** `TrustDatabase` gained `history: [TrustRecord]`, an
  append-only log of binding snapshots. First sightings, newly detected
  conflicts (both the superseded binding and the new problem record),
  `markVerified` / `markProblem` state changes, `resolveConflict`, and
  `rejectConflict` each append snapshots; re-sightings of a known binding
  only touch `lastSeen` (no log spam on every import). Schema stays at
  version 1; the decoder uses `decodeIfPresent` so pre-history databases
  load with an empty log (covered by `testDatabaseWithoutHistoryLogDecodes`).
- **`rejectConflict(email:newFpr:)`** — removes the matching conflict and,
  when the rejected key is the address's current binding (the common case),
  appends the rejected key's problem record to the log and restores the
  previous binding from its latest snapshot (state preserved, e.g. verified
  stays verified). Falls back to `unverified` when the conflict predates
  the history log. No-op when no matching conflict exists. In a conflict
  chain (FPR1→FPR2→FPR3) it only rewrites the active record when the
  rejected key is the current binding, so chains unwind safely one step at
  a time (`testRejectConflictUnwindsConflictChain`).
- **`state(forFpr:)`** falls back to the most recent history snapshot when
  the fingerprint has no active record, so a rejected/superseded key keeps
  its last known state (problem) in the UI instead of reverting to
  unverified.
- **`markVerified`** also appends history snapshots, and when the
  fingerprint only exists in the history log (a previously rejected key),
  it is promoted back to the active verified binding — so the key detail
  view's "Mark as Verified" is never a dead button after a rejection
  (`testMarkVerifiedAfterRejectPromotesNewKey`). This only changes behavior
  in paths that were previously silent no-ops.
- **`history(forEmail:)`** — new public query returning the address's
  snapshots, most recent first; `lastSeen` is the time the state was
  recorded.

### 2. Reject action in the UI (container app)

- **Trust-conflict banner** (`ContentView.bannerStack`): the banner gained
  a "Keep old binding" button (`contentview.trust-conflict-keep-old`) that
  rejects the first shown conflict. `BannerView` learned an optional
  action button and switches to `.accessibilityElement(children: .contain)`
  when an action is present so the button stays individually accessible.
- **Key detail view** (`Sources/RnpMailUI/KeyDetailView.swift`):
  `KeyDetailActions` gained `onRejectNewKey` and `onShowTrustHistory`
  (defaulted, source-compatible); `KeyDetailView` gained
  `hasPendingKeyChange: Bool = false`. When set (the displayed key is the
  new key of an unresolved conflict), the trust card shows a
  "Keep old binding" button (`keydetail.keep-old-binding`) next to
  "Mark as verified". `ContentViewModel.rejectKeyChange(for:)` /
  `hasPendingKeyChange(for:)` wire it via `KeysManager`.

### 3. Trust history view (container app)

- New `Sources/RnpMailUI/TrustHistoryView.swift`: a sheet listing the
  address's snapshots — state icon + badge (reusing `TrustPresentation`),
  abbreviated fingerprint, "First seen" and "Recorded" dates — with an
  empty state. Accessibility identifiers: `trusthistory`,
  `trusthistory.list`, `trusthistory.row.N`, `trusthistory.empty`.
- Opened from the recipient key detail trust card ("Trust history" button,
  `keydetail.trust-history`) via `ContentViewModel.openTrustHistory(for:)`,
  which resolves the key's first user-ID email and loads
  `KeysManager.trustHistory(forEmail:)`.
- 7 new string keys in `Localizable.xcstrings`
  (`detail.keepOldBinding`, `detail.keepOldBinding.help`,
  `trustHistory.title`, `trustHistory.empty.title`,
  `trustHistory.empty.message`, `trustHistory.firstSeen`,
  `trustHistory.recorded`), English plus the 10 shipped languages as
  machine-translated `needs_review` entries, matching the catalog's
  existing convention (validated by `LocalizationTests`).

### 4. Tests

- `Tests/TrustStoreTests/TrustStoreTests.swift` (+12): reject restores
  verified/unverified old binding, rejected key stays problem, no-op
  without conflict, chain unwind, persistence across instances,
  verify-after-reject promotion, history content/order/scoping/normalization,
  history persistence, re-see no-spam, pre-history database migration.
- `Tests/MailSecurityEngineTests/MailSecurityEngineTests.swift` (+1):
  `testRejectConflictEncryptsToOldKey` — after reject, `encode` succeeds,
  the old key decrypts, the rejected key cannot.
- `Tests/RnpMailUITests/TrustHistoryViewTests.swift` (new, 4): render
  tests for the history view (records + empty state) and the key detail
  view with/without `hasPendingKeyChange`, following the project's
  existing host-and-render test style (SwiftUI does not materialize its
  accessibility tree in the unsigned test runner, so identifier-level
  assertions are not possible there — noted after probing).

## Verification

- `PKG_CONFIG_PATH=... swift test -Xlinker -rpath -Xlinker ...` —
  **261 tests, 0 failures** (TrustStoreTests 25, MailSecurityEngineTests 37,
  TrustHistoryViewTests 4, all pre-existing suites unchanged). The
  MailSecurityBanner snapshot mismatches printed during the run are
  pre-existing machine-specific font-rendering warnings (non-fatal without
  `SNAPSHOT_STRICT=1`) on files this task did not touch.
- `xcodebuild -scheme RNP build CODE_SIGNING_ALLOWED=NO` —
  **BUILD SUCCEEDED**.
- `xcodebuild -scheme MailPlugin build CODE_SIGNING_ALLOWED=NO` —
  **BUILD SUCCEEDED**.

Note: the first RNP build attempt failed with
`cannot load module 'RNP' as 'Rnp'` while a full `swift test` was running
concurrently (shared module-cache interference); the identical command
succeeded when re-run after the test run finished. Not related to these
changes.

## Concerns / follow-ups

- `state(forFpr:)` history fallback changes one edge of existing behavior:
  a superseded key (e.g. an old binding after a conflict) now reports its
  last recorded state instead of `unverified`. No existing test depended on
  the old value, and it is arguably more correct (the old key's known trust
  is retained for the signer banner).
- Accept-after-reject relies on the same keyring-resolution quirk as the
  pre-existing accept flow: librnp resolves the first-imported key, so
  fully switching encryption to a newer key still requires retiring the old
  key from the keyring (same as before; `markVerified` promotion makes the
  trust side consistent).
- The conflict banner acts on the first shown conflict only (same
  information the banner already displayed); chains are still resolvable
  one step at a time via the key detail view.
- Trust history is per address; for keys with several user IDs the sheet
  shows the first email's history.
