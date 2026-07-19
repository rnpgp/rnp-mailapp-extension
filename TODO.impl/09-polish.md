# 09 — Polish: accessibility, localization, performance, security posture

Status: pending · Milestone: M7 · Depends on: 02–07

## Goal

The difference between "works" and "best OpenPGP Mail extension": finish the
details that reviewers, power users, and security folks check.

## Work items

1. **Accessibility audit**: VoiceOver pass over every screen (labels, hints,
   traits, logical order), keyboard navigation for all flows (no
   pointer-only actions), Dynamic Type at AX5 without truncation, reduce-
   motion honored in animations. Add a11y identifiers to all interactive
   elements (feeds XCUITest).
2. **Localization groundwork**: convert all UI strings to a String catalog
   (`Localizable.xcstrings`), no string concatenation for sentences, en as
   source; export xliff smoke-test; DE and JA translations are a follow-up
   (community call for translators in README).
3. **Performance**: decode path benchmark — corpus of 100 real-world-shaped
   messages (1KB–25MB, nested multipart, large attachments) through
   MailSecurityEngine; budget: p95 decode+verify < 300ms for ≤1MB messages on
   M1; profile hot spots (expect MIME parser + base64); stream large
   attachments (rnp_input_from_file/output_to_file instead of memory where
   sizes warrant — extend Rnp wrapper with file-stream variants + tests).
4. **Threat model + security docs** (`docs/SECURITY-MODEL.md`): assets
   (secret keys, passphrases, plaintext), trust boundaries (app group,
   keychain, appex↔app, network), what we deliberately do NOT protect
   against (compromised OS, Mail itself), memory hygiene (FFI buffers
   zeroed on free where librnp allows; Swift Data copies minimized),
   reporting instructions (SECURITY.md pointing to rnpgp security contact).
5. **Dependency & CVE policy** (`docs/DEPENDENCIES.md`):
   - librnp: pinned via task 01 framework (ref + SHA256); watch
     rnpgp/rnp releases (GH watch / RSS); CVE → framework rebuild PR within
     7 days (CVE-2025-13470 is the template incident).
   - SPM deps: keep at zero beyond Apple frameworks + CRnp if possible
     (MimeParser was already removed); if any added: exact-version pin +
     license check + `Vendor/SOURCES.md` update.
   - GitHub: enable Dependabot for github-actions; CODEOWNERS for workflows.
6. **Licenses in-app**: About → Licenses view rendering `Vendor/SOURCES.md`
   + full license texts bundled (rnp BSD-2, Botan BSD-2, json-c MIT, sexpp
   BSD, zlib, bzip2) — required by those licenses for binary distribution.
7. **Telemetry stance**: none, ever; document; MAS privacy nutrition label
   stays empty ("Data Not Collected").
8. **Fuzzing hook**: wire the MIME parser into rnp's OSS-Fuzz-adjacent
   approach — a `swift test` fuzz-ish target is impractical; instead add a
   corpus-driven crash-regression test (Tests/Fixtures/mime-corpus/*, seed
   with edge cases: deep nesting, broken boundaries, huge headers, mixed
   EOLs) and document how to run Swift-fuzz locally.

## Acceptance criteria

- VoiceOver script (doc in repo) completes all primary flows; zero missing
  labels found by Xcode Accessibility Inspector audit.
- All user-facing strings extracted; pseudo-localization build renders
  without crashes/truncation at +40% length.
- Perf budget met or exceptions documented with data.
- SECURITY-MODEL.md + DEPENDENCIES.md + SECURITY.md committed and linked
  from README.

## Notes

- This task is intentionally last but items 4–5 can start in parallel with
  04–07; reorder freely if a security review is scheduled earlier.
