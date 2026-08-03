# 07 — Async decryption queue (Mail)

**Priority**: P2
**Status**: not started
**Effort**: M
**Dependencies**: 12 (specs/tests)

## Problem

Today `MessageSecurityHandler.decodedMessage(forMessageData:)` decrypts
synchronously on whatever queue Mail calls it on. When a user opens a
thread with 20 encrypted messages, Mail blocks on 20 sequential
decryptions — each 50-200 ms for typical messages. The UI feels frozen.

## Goals / non-goals

**Goals**
- Multiple messages decrypt in parallel (up to N workers)
- Cached results — opening a thread the second time is instant
- Decryption off the main thread
- Back-pressure: don't queue 1000 messages at once

**Non-goals**
- Cross-thread keyring (each worker has its own Rnp FFI handle)
- Pre-emptive decryption of unopened threads

## Design

### Architecture

```
DecryptionQueue (actor)
├── workers: [DecryptionWorker]    // N=3 by default
├── cache: NSCache<NSData, DecodedMessageBox>
└── enqueue(_ message: MEMessage) async -> MEDecodedMessage

DecryptionWorker
├── own Rnp handle (no cross-thread sharing)
├── idle by default
└── pulls from queue when capacity available
```

### Cache key

`SHA256(message raw bytes)` — message IDs aren't stable across Mail's
state mutations.

### Backpressure

When queue depth > 50, callers receive `.throttled` and Mail's UI shows
a "decoding..." state. Avoids OOM on pathological folders.

### Testability

`DecryptionQueue` takes a `Decryptor` protocol — production injects
`RnpDecryptor`, tests inject a `MockDecryptor` that returns canned
results with configurable latency.

## Implementation plan

1. Define `Decryptor` protocol
2. Implement `RnpDecryptor` (wraps `Rnp.decrypt`)
3. Implement `DecryptionQueue` actor with worker pool
4. Wire into `MessageSecurityHandler.decodedMessage`
5. Add latency test (`Tests/DecryptionQueueTests/`)

## Acceptance criteria

- [ ] Opening a 20-message encrypted thread: 1st message visible < 100ms;
      all 20 done in < 1s (parallelism=3)
- [ ] Re-opening same thread: instant (cache hit)
- [ ] No main-thread stalls measured via Instruments
- [ ] Tests cover: parallel decryption, cache hit, cache eviction,
      backpressure

## Open questions

- **Worker count.** 3 is the macOS default for IO + CPU mix. Measure.
- **Cache eviction policy.** NSCache default is fine; LRU by bytes.

## References

- Code: `MailApp/MailPlugin/MessageSecurityHandler.swift:217`
- Swift actors: Swift Concurrency docs
