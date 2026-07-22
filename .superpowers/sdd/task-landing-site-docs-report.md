# Task Report: Landing Site and Documentation

**Branch:** `automation/landing-site-docs` (from `main`)
**Commit:** `bcc2186` — docs: landing site and user/developer documentation

## Summary

Created a polished, dependency-free landing page at `docs/website/index.html`
and eight new documentation pages under `docs/`, covering installation, usage,
features, trust model, keyservers, development, and FAQ, with a docs index
linking both the new pages and all pre-existing docs. No production code was
touched; the diff contains only new files under `docs/`.

## What was created

### Landing site — `docs/website/index.html` (+ `docs/website/assets/icon.png`)

Single-file HTML with embedded CSS/JS; no frameworks, fonts, or external
assets. The only image is the RNP logo, copied from the repo-root `icon.png`
into `docs/website/assets/` so the site is self-contained.

- Sticky nav (Features / Screenshots / Get Started / Docs / Download).
- Hero: RNP logo, tagline "OpenPGP for Apple Mail, native and polished",
  Download CTA (GitHub Releases) + docs CTA, requirements note.
- Six feature cards with inline SVG icons: key management, trust
  verification, keyserver support, accessibility, localization (11 languages,
  verified against `Localizable.xcstrings`), privacy-first (no telemetry).
  A capability strip below lists PGP/MIME, inline PGP, attachments,
  non-ASCII bodies, sandbox, Keychain, Touch ID, librnp 0.18.1.
- "A look at the app": three pure-CSS window mockups (key manager with
  verified badge, compose security menu with Sign/Encrypt, green verified
  signature banner), explicitly captioned as representative previews —
  no fake screenshots.
- "Get started in three steps" linking to `installation.md` and `usage.md`.
- Documentation card grid linking all new docs plus `SECURITY-MODEL.md`.
- Final CTA and a footer with GitHub, security policy, privacy/telemetry,
  and license links.
- Brand color `#1A7BEC` (plus `#0B54B8` deep blue, `#2E3349` ink from the
  app's `RnpBrand` palette); light/dark via `prefers-color-scheme`,
  responsive grids, `prefers-reduced-motion` support, semantic HTML with
  alt text/ARIA labels.

### Documentation pages

- `docs/index.md` — docs landing page; links every new page and all
  pre-existing docs (`SECURITY-MODEL.md`, `SECURITY.md`, `DEPENDENCIES.md`,
  `TELEMETRY.md`, both `app-store/` files) plus project links.
- `docs/installation.md` — direct-download DMG (`RnpMail-<version>.dmg`,
  Gatekeeper note), Mac App Store status (pipeline exists, link pending),
  build from source (librnp ≥ 0.18.1, Xcode, DEVELOPMENT_TEAM, bundle IDs in
  `Swift-Rnp/Shared/IDs.xcconfig`, Direct/AppStore configurations),
  uninstall steps.
- `docs/usage.md` — enabling the extension, key generate/import/export/
  delete, signing/encrypting from the compose window, banner states on
  receipt, trust decisions, keyserver publishing/discovery, key lifecycle
  (rotate/extend/revoke), Keychain passphrase handling, known limitations
  (from the README, unchanged).
- `docs/features.md` — feature tables mapped to standards and librnp
  capabilities (RFC 4880/3156, VKS/HKPS/WKD, RSA-3072/ECDSA P-256, Ed25519
  trust-store signature, sandbox entitlements, 11 languages, test gates).
- `docs/trust-model.md` — TOFU, manual verification, key-change conflicts
  (encryption blocked until verified), tamper-evident signed `trust.json`
  (fail-closed reset), why no web-of-trust, residual risks.
- `docs/keyserver.md` — VKS upload + email-confirmation flow, discovery by
  email/fingerprint/WKD (advanced and direct)/HKPS, revocation propagation,
  trust & privacy considerations, error table.
- `docs/development.md` — repo layout, prerequisites, swift/xcodebuild test
  matrix, snapshot-test re-recording, e2e harness, audits, release pipeline
  (`release-direct.yml`, `release-appstore.yml`), CI table, contributing
  rules (no force-unwraps, pinned deps, private security reporting).
- `docs/faq.md` — 20 Q&As: no web-of-trust rationale, why MailKit, telemetry,
  conflict blocks, key/passphrase storage, GnuPG import caveat, SmartCards,
  algorithms, attachments/UTF-8, subject-line metadata, revocation,
  bug/security reporting, `--self-test`, license status.

Content was cross-checked against `README.md`, `docs/SECURITY-MODEL.md`,
`docs/TELEMETRY.md`, `docs/DEPENDENCIES.md`, `docs/app-store/*.md`,
`Sources/KeyServerClient/`, `Sources/KeyLifecycle/`,
`Swift-Rnp/MailExtensionsContainer/Resources/Localizable.xcstrings` (11
languages confirmed), `scripts/release-direct.sh` (DMG name), and
`.github/workflows/release-direct.yml` (releases published to
`rnpgp/swift-rnp`).

## Verification

- **Link check:** a Python checker validated every relative link and
  GitHub-style anchor in all 14 markdown files under `docs/` and every local
  `href`/`src` and in-page anchor in `index.html` — all resolve.
- **Browser render:** served `docs/` locally (`python3 -m http.server 8907`)
  and rendered the page in the user's real browser via WebBridge. Screenshots
  verified hero, features, mockups, get-started, docs grid, final CTA, and
  footer in dark mode, plus the hero in light mode (via CDP emulation) — all
  correct. The browser extension could not open `file://` URLs, hence the
  local HTTP server; server stopped and tab group closed afterwards.
- **Scope:** `git status` after the commit shows only the pre-existing
  untracked `.superpowers/sdd/task-localization-report.md` (not mine, left
  alone) and this report; the commit contains only the 10 new files under
  `docs/`.

## Concerns / follow-ups

- The README's release link points to `rnpgp/rnp-mailapp-extension/releases`,
  but the release workflow publishes to `rnpgp/swift-rnp/releases`; the new
  docs use the workflow's URL. The README discrepancy may be worth fixing
  separately (left untouched here to keep the diff docs-only and minimal).
- The Mac App Store link is genuinely pending (README and
  `app-store/metadata.md` both carry TODOs); `installation.md` states this
  rather than inventing a URL.
- The landing page links to `../index.md`, `../installation.md`, etc. These
  resolve when browsing the repo on GitHub or serving `docs/` over HTTP; when
  opening `index.html` via `file://`, browsers will display the raw markdown
  (expected behavior, no broken links).
