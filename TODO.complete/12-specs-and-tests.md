# 12 — Specs + test coverage

**Priority**: P0 (cross-cutting — applies to every other TODO)
**Status**: in progress
**Effort**: M (ongoing)
**Dependencies**: none

## Problem

The codebase has spec coverage for the engine layer (`MailSecurityEngine`
ships with `Tests/`) but the app layer (File Tools, Tools hub, onboarding,
Mail extension handler) has limited coverage. New features land without
spec docs. Regression risk grows with each PR.

## Goals / non-goals

**Goals**
- Every user-visible feature has a spec in `docs/specs/<feature>.md`
- Every public type in the app layer has at least one test
- CI runs the full test suite on every PR (already true for engine tests)
- Localization audit test exists (already does) — keep it green
- Snapshot tests for SwiftUI views where text/layout matters

**Non-goals**
- 100% line coverage as a hard metric (misleading)
- E2E tests against real Mail (flaky; covers in TODO 07's design)

## Design

### Spec template

```markdown
# Feature name

## User story
As a <user>, I want <capability>, so that <value>.

## Preconditions
- ...

## Main flow
1. ...

## Edge cases
- ...

## Out of scope
- ...

## Test plan
- [ ] Unit: <test name> — <file>
- [ ] UI: <test name> — <file>
- [ ] Localization: every visible string has a translation key

## Localization keys
- `feature.button.label`
- `feature.error.message`
```

### Test pyramid

```
                    ┌─────────────┐
                    │ E2E (Mail)  │   ← flaky, slow; few
                    ├─────────────┤
                    │ Integration │   ← engine + keyring; medium
                    ├─────────────┤
                    │   Unit      │   ← pure logic; many; fast
                    └─────────────┘
```

### What needs specs today

| Feature               | Spec exists?              | Tests?           |
| --------------------- | ------------------------- | ---------------- |
| File Tools            | no                        | minimal          |
| Tools hub             | no                        | none             |
| Onboarding            | no                        | none             |
| Mail extension decode | no (engine has it)        | engine only      |
| Mail extension encode | no (TODO 01 will add)     | none             |
| Keyring scanner       | no                        | none             |
| Shared keyring        | inline comments only      | none             |
| App Intents           | no                        | none             |
| Localization audit    | yes (`docs/i18n.md`)      | yes              |

## Implementation plan

1. Author `docs/specs/template.md` with the template above
2. Author specs for: file-security, tools-hub, onboarding,
   mail-decode, mail-encode, keyring-scanner, app-intents
3. Stand up `Tests/RnpMailAppTests/` with unit tests for the above
4. Wire snapshot testing for SwiftUI views where layout matters
5. Make CI fail when a spec is missing for a new feature

## Acceptance criteria

- [ ] `docs/specs/template.md` exists and is referenced from `CONTRIBUTING.md`
- [ ] Every PR that adds a user-visible feature references a spec
- [ ] Test coverage on app-layer public types ≥ 70%
- [ ] Localization audit test runs in CI (already does)
- [ ] No regressions in green builds

## Open questions

- **Snapshot testing library.** `swift-snapshot-testing` (Pointfree) is
  the standard. Add as SPM test dep.
- **Spec enforcement.** Risky to fail CI on missing spec — start with
  warnings, escalate later.

## References

- Existing tests: `Tests/`
- Existing spec-style doc: `docs/i18n.md`
