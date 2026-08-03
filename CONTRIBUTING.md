# Contributing to RNP

Thanks for considering a contribution. This doc covers the practical
stuff: dev setup, running tests, opening PRs, code style, and where to
ask for help.

## Quick start

```bash
git clone https://github.com/rnpgp/rnp-mailapp-extension.git
cd rnp-mailapp-extension
open MailApp/RnpMail.xcodeproj
```

Xcode 16.4 or later. macOS 14+ both for development and as the
deployment target.

The Xcode project pulls in `swift-rnp` and `Sparkle` via SwiftPM; on
first build Xcode resolves them automatically. The binary
`RNPFramework.xcframework` (librnp) is downloaded from
`github.com/rnpgp/swift-rnp/releases`.

## Running tests

```bash
xcodebuild test \
  -project MailApp/RnpMail.xcodeproj \
  -scheme RNP \
  -destination 'platform=macOS'
```

CI runs the same scheme (`.github/workflows/ci.yml`) on every PR. The
job is consolidated into one job per PR (per user feedback — keep CI
fast).

For the engine-layer tests (MailSecurityEngine, FileSecurityEngine,
etc.), `swift test` from `swift-rnp` runs them directly.

## Branching & PRs

- One PR per coherent change. Don't open one PR per file; conversely
  don't bundle unrelated work.
- Branch from `main`, rebase onto latest `main` before merge.
- Use **rebase-merge**, not squash-merge. We want the commit history to
  read as a sequence of reviewable, atomic commits.
- Default commit message style: `<type>(<scope>): <subject>`. Types:
  `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `ci`. Scope is
  the subsystem (`file-ops`, `mail`, `keyring`, etc.).

## Code review expectations

- New user-visible feature? Needs a spec at `docs/specs/<feature>.md`
  (template at `docs/specs/_template.md`). No spec, no merge.
- Architectural decision? Add an ADR at `docs/adr/NNNN-<name>.md`.
- No AI attribution. Commits must look like normal human work — no
  `Co-authored-by: Claude`, no "Generated with" footers.
- No `--no-verify` to skip hooks. If a hook fails, fix the underlying
  issue.

## Code style

SwiftLint isn't enforced yet (planned). In the meantime:

- Follow the style of nearby code.
- 4-space indentation, no tabs in new files.
- `final` by default; open only when subclass is required.
- Access modifiers explicit (`private`, `internal`, `public`).
- Comments explain *why*, not *what*. Well-named code documents itself.
- No hand-rolled serialization. Use `Cododable` or platform primitives.

See `TODO.complete/00-index.md` for the full set of engineering
principles this repo follows.

## Architecture

Read these first:

- `docs/adr/` — load-bearing decisions
- `TODO.complete/00-index.md` — engineering roadmap + principles
- `MailApp/MailExtensionsContainer/Model/FileSecurity/FileSecurityEngine.swift`
  — the deep module for file operations (Strategy pattern, ADR-0002)
- `MailApp/MailExtensionsContainer/Model/SharedKeyring.swift` — single
  factory for the keyring (ADR-0004)

## Filing issues

- Bugs and feature requests: [GitHub Issues](https://github.com/rnpgp/rnp-mailapp-extension/issues)
- **Security vulnerabilities**: email `security@ribose.com`, NOT
  GitHub. We respond within 48 hours.
- Translation contributions: see `TRANSLATING.md`.

## Translations

RNP ships with 10 locales. To contribute a new translation or improve
an existing one, read `TRANSLATING.md`. The keys live in
`MailApp/MailExtensionsContainer/Resources/Localizable.xcstrings`.

## Helpful scripts

- `scripts/release-direct.sh` — build, sign, notarize a release
- `scripts/sandbox-audit.sh` — verify entitlements + sandbox profile
- `scripts/ci-release-dry-run.sh` — what CI runs as a release smoke test
- `scripts/build-rnp-framework.sh` — rebuild the librnp binary artifact

## License

By contributing, you agree that your contributions are licensed under
the BSD-2-Clause license (see `LICENSE`).
