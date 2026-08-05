# RNP — Engineering Roadmap

This directory contains all open engineering work, ranked by impact. Each
file is a self-contained spec: problem, design, plan, acceptance
criteria, open questions. Pick one up, execute, mark done.

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
| 01 | Mail compose sign + encrypt      | P0  | in progress   | M      | engineer  | verification        |
| 02 | Homebrew Cask distribution       | P1  | shipped       | S      | engineer  | external PR         |
| 03 | App Store submission             | P1  | not started   | M      | ronaldtse | Apple account       |
| 04 | Sparkle auto-update              | P1  | shipped       | S      | engineer  | appcast hosting     |
| 05 | Sign + verify files              | P1  | shipped       | S      | engineer  | —                   |
| 06 | Lazy librnp load                 | P2  | shipped       | S      | engineer  | —                   |
| 07 | Async decryption queue (Mail)    | P2  | shipped       | M      | engineer  | —                   |
| 08 | Keyring indexing                 | P2  | shipped       | M      | engineer  | —                   |
| 09 | Static website                   | P1  | shipped       | S      | engineer  | GitHub Pages enable |
| 10 | `rnp` CLI for macOS              | P2  | shipped       | M      | engineer  | —                   |
| 11 | iOS companion                    | P3  | superseded by 38 | XL  | engineer  | scope decision      |
| 12 | Specs + test coverage            | P0  | in progress   | M      | engineer  | —                   |
| 13 | ADRs + CONTRIBUTING + template   | P1  | shipped       | S      | engineer  | —                   |
| 14 | Password-based encryption        | P1  | shipped       | S      | engineer  | —                   |
| 15 | Cleartext signed messages        | P2  | shipped       | S      | engineer  | —                   |
| 16 | AEAD encryption option           | P2  | shipped       | S      | engineer  | —                   |
| 17 | YubiKey / smartcard support      | P2  | not started   | L      | engineer  | librnp smartcard    |
| 18 | Encrypted attachment UI banner   | P1  | shipped       | S      | engineer  | —                   |
| 19 | Keyring backup / restore         | P1  | shipped       | S      | engineer  | —                   |
| 20 | Unified typed errors             | P1  | shipped       | S      | engineer  | —                   |
| 21 | Unified logging (os.Logger)      | P1  | shipped       | S      | engineer  | —                   |
| 22 | ContentView refactor             | P2  | shipped       | M      | engineer  | —                   |
| 23 | Snapshot testing infra           | P2  | shipped       | M      | engineer  | —                   |
| 24 | Localization QA infra            | P1  | shipped       | M      | engineer  | —                   |
| 25 | Onboarding polish + test CTA     | P1  | shipped       | S      | engineer  | —                   |
| 26 | Keyboard shortcut audit          | P2  | shipped       | S      | engineer  | —                   |
| 27 | Dark mode + a11y audit           | P2  | shipped       | M      | engineer  | —                   |
| 28 | Reproducible builds              | P3  | shipped       | L      | engineer  | —                   |
| 29 | SBOM + supply-chain hardening    | P2  | shipped       | M      | engineer  | —                   |
| 30 | Fuzzing + S/MIME interop         | P3  | not started   | XL     | engineer  | —                   |
| 31 | Getting Started storage choice   | P0  | in progress   | M      | engineer  | 33                  |
| 32 | Sync settings UI design          | P0  | in progress   | M      | engineer  | 33                  |
| 33 | Phase 1.5 refactor: route code through protocols | P0 | in progress | M | engineer | — |
| 34 | Per-key .asc directory backend   | P1  | in progress   | S      | engineer  | 33                  |
| 35 | CloudKit canonical store         | P1  | not started   | L      | engineer  | 33                  |
| 36 | GnuPG agent passphrase store     | P2  | not started   | M      | engineer  | —                   |
| 37 | Sync UI sheet (impl of 32)       | P0  | in progress   | M      | engineer  | 33                  |
| 38 | iOS companion app                | P3  | not started   | XL     | engineer  | scope decision      |

## Dependency graph

```
33 (Phase 1.5 refactor) ──┬─► 31 (Getting Started)
                          ├─► 32 (Sync UI design)
                          ├─► 34 (Per-key .asc)
                          ├─► 35 (CloudKit)
                          └─► 37 (Sync UI impl)

31 ─► onboarding flow update
32 + 37 ─► Sync settings sheet
35 + 38 ─► iOS app

12 (specs/tests) ──► cross-cutting; ongoing
17, 30 ──► librnp API gaps; deferred
```

## Engineering principles (apply to every TODO)

These are non-negotiable for new work in this repo.

1. **Open/Closed.** Adding a new operation = adding a new handler type,
   never editing a switch in existing code. Adding a new key algorithm =
   adding a `KeyAlgorithm` case + an `AlgorithmSpec`, never editing
   generation logic.
2. **MECE.** Each concern lives in exactly one module. File operations
   belong in `FileSecurityEngine`. Mail operations belong in
   `MailSecurityHandler`. Key lifecycle belongs in `KeyLifecycleService`.
   No overlap, no orphans. Canonical stores vs import sources are
   separate protocols — see ADR-0006.
3. **Model-driven, semantically-driven.** Classes and methods are named
   after domain nouns and verbs (`SignOperation`, `verifyDetachedSignature`,
   `OutgoingMessageEncryptionStrategy`), never after implementation
   details (`CryptoHelper`, `performAction`, `handleStuff`).
4. **DRY.** Three similar lines is acceptable; four is a smell; five is
   a refactor. But never abstract prematurely — wrong abstraction is
   worse than duplication.
5. **Performance matters, but clarity first.** Don't micro-optimize at
   the expense of readability. Measure before optimizing. A 200 ms
   savings that obscures the code path is a regression.
6. **Specs throughout.** Every user-visible feature ships with a spec
   doc (`docs/specs/<feature>.md`) and at least one test per acceptance
   criterion. No spec, no merge.
7. **No hand-rolled serialization.** Use Codable / SwiftData / platform
   primitives. Never write `toJSON`/`fromJSON` by hand.
8. **No AI attribution.** No `Co-authored-by` trailers, no "Generated
   with" footers. The user is the sole author.
9. **Use the framework.** Don't reinvent. SwiftUI + Combine + os.Logger
   + Keychain + App Sandbox + Swift Concurrency. Lean on the platform.
10. **Tests, not doubles.** Real instances. Real keyrings in test
    sandboxes (`~/.rnp/`, never `~/.gnupg/`). Behavior assertions, not
    mock-call assertions.
11. **Never delete user keys.** Multi-step confirmation + encrypted
    backup before any delete (ADR-0007). External keyrings are
    read-only `KeyImportSource`s, never modified (ADR-0006).

## How to pick up a TODO

1. Read the file end-to-end.
2. Read the linked code paths.
3. Sketch the design in the spec's **Open questions** section if
   anything's unclear; talk to ronaldtse before implementing if there's
   a fork.
4. Open ONE PR per TODO unless TODOs are tightly coupled (per user
   feedback: bundle related changes, don't open one PR per file).
5. Rebase-merge. Don't squash — preserve the commit history.
6. Mark the TODO `shipped` and update the index.
