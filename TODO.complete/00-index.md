# RNP — Engineering Roadmap

This directory contains all open engineering work, ranked by impact. Each file
is a self-contained spec: problem, design, plan, acceptance criteria, open
questions. Pick one up, execute, mark done.

## Priority legend

| Priority | Meaning                                            |
| -------- | -------------------------------------------------- |
| **P0**   | Blocks the core product promise. Do first.         |
| **P1**   | Major audience or trust multiplier.                |
| **P2**   | Quality-of-life / performance.                      |
| **P3**   | Strategic / future bets.                            |

## Status legend

`not started` · `in progress` · `blocked` · `shipped`

## Index

| #  | Title                            | Pri | Status        | Effort | Owner     | Blocked-on          |
| -- | -------------------------------- | --- | ------------- | ------ | --------- | ------------------- |
| 01 | Mail compose sign + encrypt      | P0  | not started   | L      | engineer  | —                   |
| 02 | Homebrew Cask distribution       | P1  | shipped       | S      | engineer  | external PR         |
| 03 | App Store submission             | P1  | not started   | M      | ronaldtse | Apple account       |
| 04 | Sparkle auto-update              | P1  | shipped       | S      | engineer  | appcast hosting     |
| 05 | Sign + verify files              | P1  | shipped       | S      | engineer  | —                   |
| 06 | Lazy librnp load                 | P2  | shipped       | S      | engineer  | —                   |
| 07 | Async decryption queue (Mail)    | P2  | not started   | M      | engineer  | —                   |
| 08 | Keyring indexing                 | P2  | not started   | M      | engineer  | benchmark           |
| 09 | Static website                   | P1  | shipped       | S      | engineer  | GitHub Pages enable |
| 10 | `rnp` CLI for macOS              | P2  | not started   | M      | engineer  | —                   |
| 11 | iOS companion                    | P3  | not started   | XL     | engineer  | scope decision      |
| 12 | Specs + test coverage            | P0  | in progress   | M      | engineer  | —                   |

## Dependency graph

```
12 (specs/tests) ──┬─► 1 (Mail compose)
                   ├─► 5 (sign/verify files) ──┬─► 1
                   │                           └─► 10 (CLI)
                   ├─► 7 (async decrypt)
                   └─► 8 (keyring indexing)

4 (Sparkle) ─► (independent, but unblocks post-release bug fixes reaching users fast)
2 (Cask)    ─► (independent, but depends on signed + notarized DMG artifacts)
9 (Website) ─► (independent)
3 (App Store) ─► depends on 12 (privacy manifest audit), needs ronaldtse
```

## Engineering principles (apply to every TODO)

These are non-negotiable for new work in this repo.

1. **Open/Closed.** Adding a new operation = adding a new handler type, never
   editing a switch in existing code. Adding a new key algorithm = adding a
   `KeyAlgorithm` case + an `AlgorithmSpec`, never editing generation logic.
2. **MECE.** Each concern lives in exactly one module. File operations belong
   in `FileSecurityEngine`. Mail operations belong in `MailSecurityHandler`.
   Key lifecycle belongs in `KeyLifecycleService`. No overlap, no orphans.
3. **Model-driven, semantically-driven.** Classes and methods are named after
   domain nouns and verbs (`SignOperation`, `verifyDetachedSignature`,
   `OutgoingMessageEncryptionStrategy`), never after implementation details
   (`CryptoHelper`, `performAction`, `handleStuff`).
4. **DRY.** Three similar lines is acceptable; four is a smell; five is a
   refactor. But never abstract prematurely — wrong abstraction is worse than
   duplication.
5. **Performance matters, but clarity first.** Don't micro-optimize at the
   expense of readability. Measure before optimizing. A 200 ms savings that
   obscures the code path is a regression.
6. **Specs throughout.** Every user-visible feature ships with a spec doc
   (`docs/specs/<feature>.md`) and at least one test per acceptance
   criterion. No spec, no merge.
7. **No hand-rolled serialization.** Use Codable / SwiftData / platform
   primitives. Never write `toJSON`/`fromJSON` by hand.
8. **No AI attribution.** No `Co-authored-by` trailers, no "Generated with"
   footers. The user is the sole author.

## How to pick up a TODO

1. Read the file end-to-end.
2. Read the linked code paths.
3. Sketch the design in the spec's **Open questions** section if anything's
   unclear; talk to ronaldtse before implementing if there's a fork.
4. Open ONE PR per TODO unless TODOs are tightly coupled (per user feedback:
   bundle related changes, don't open one PR per file).
5. Rebase-merge. Don't squash — preserve the commit history.
6. Mark the TODO `shipped` and update the index.
