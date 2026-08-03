# 08 — Keyring indexing for large keyrings

**Priority**: P2
**Status**: not started
**Effort**: M
**Dependencies**: benchmark to confirm need (do this before implementing)

## Problem

`KeysListView` filters `manager.keys` with a naive `contains` on every
keystroke. For 50 keys, instant. For 1000+ keys (security researchers,
KSP attendees, keyserver-synced keyrings), it lags visibly.

## Goals / non-goals

**Goals**
- 50-key users see zero behavior change
- 1000-key users get < 50 ms filter latency
- Fuzzy match (substring of fingerprint, email, name, key ID)
- Index updates when keys are added/removed/imported

**Non-goals**
- Full-text search across all UIDs of all keys (overkill for v1)
- Server-side search (no server)

## Design

### Pattern: inverted index

```
KeyringIndex
├── tokens: [String: Set<KeyFingerprint>]   // "alice" → {fpr1, fpr3}
├── fingerprints: [KeyFingerprint: KeyInfo]  // fast lookup
└── search(_ query: String) -> [KeyInfo]

Tokenization: lowercase, split on whitespace and @, dedupe
```

### Update strategy

`KeyringIndex` subscribes to `KeysManager.$keys`. Diff against last
seen; add/remove tokens incrementally.

### When to ship

Don't ship until we have a real benchmark. Write a test that loads 2000
synthetic keys and measures filter latency. If naive is < 100 ms, skip
this TODO entirely.

## Implementation plan

1. Write benchmark in `Tests/KeyringIndexBenchmarkTests/`
2. If naive filter is fine for 2000 keys, close this TODO with rationale
3. If not, implement `KeyringIndex` per design above
4. Wire into `KeysListView`'s filter

## Acceptance criteria

- [ ] Benchmark exists and runs in CI
- [ ] If shipped: 2000-key filter < 50 ms (95th percentile)
- [ ] If skipped: documented rationale in this TODO

## Open questions

- **Is this needed?** Possibly premature optimization. Benchmark first.

## References

- Code: `MailApp/MailExtensionsContainer/View/ContentView/ContentViewModel.filteredKeys`
