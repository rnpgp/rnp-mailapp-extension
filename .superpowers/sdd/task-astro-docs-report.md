# Task Report: Astro + Starlight Documentation Site

## Summary

Built a complete, static documentation and product site for the RNP Apple Mail
OpenPGP extension in `docs-site/`, using **Astro 7.1.3**, **@astrojs/starlight
0.41.4**, **@astrojs/vue 7.0.1** (Vue 3.5.40), **Tailwind CSS 4.3.3** via
**@tailwindcss/vite 4.3.3**, all on **Vite 8.1.5** (single deduped instance —
verified with `pnpm why vite`). Package management with pnpm 11.12.0;
`package.json` + `pnpm-lock.yaml` committed.

## What was built

### Landing page — `src/pages/index.astro`

- Hero with the RNP logo (`public/icon.png`, copied from the repo root),
  tagline, "Download for macOS" (GitHub Releases) and "Read the manual" CTAs,
  and an ambient brand-color glow animation.
- Six feature cards with inline SVG icons: key management, trust verification,
  keyserver support, accessibility, localization, privacy-first — each linking
  into the manual.
- "Signature status at a glance" UI-preview section: three Mail security
  banner mockups (verified / unverified / problem) styled after the real
  banner rendered by `MailSecurityUI`, with the app's actual state colors.
- "Try it" section embedding two live Vue islands (fingerprint checker +
  keyserver lookup).
- Security strip (Touch ID, Keychain, sandbox, tamper-evident trust store),
  download CTA, and a full footer.
- Dark mode with a toggle that shares Starlight's `starlight-theme`
  localStorage key and `data-theme` attribute, so landing and docs stay in
  sync; no-flash inline script in `<head>`.
- Scroll-reveal animations (IntersectionObserver), smooth hover transitions,
  `prefers-reduced-motion` respected, responsive layout throughout.

### User manual — `src/content/docs/` (9 pages, Starlight)

| Page | Covers |
| --- | --- |
| `getting-started/installation.mdx` | DMG, App Store, build-from-source (Tabs + Steps), uninstall |
| `getting-started/first-launch.md` | Onboarding, Touch ID offer, first key, enabling the extension |
| `key-management.mdx` | Generate (Ed25519/RSA-3072/ECDSA P-256), import, export, inspect, delete, subkey rotation, expiry, revocation |
| `trust-verification.mdx` | Three states (+ live demo), TOFU, manual verify, key-change conflicts, trust history, tamper-evident store, no-WoT rationale |
| `keyserver.mdx` | VKS publish + email confirmation, discovery (VKS/WKD/HKPS), custom keyserver management, revocation checks, privacy, error table |
| `using-with-mail.mdx` | Enable extension, compose sign/encrypt, protected headers, banner states, banner actions (fetch key, view in RNP, copy fingerprint, mark verified, report issue) |
| `security.md` | Touch ID, Keychain storage, sandbox entitlements, privacy/no-telemetry, protected vs. not-protected, vuln reporting |
| `troubleshooting.md` | 10 common issues (missing extension, Gatekeeper, trustConflict, passphrases, Touch ID prompts, locked keyring, keyserver errors, …) |
| `faq.md` | Adapted from `docs/faq.md`, all internal links retargeted |

Content was kept accurate against the repository: `docs/*.md`, the README,
`Sources/TrustStore` (trust history log), `Sources/MailSecurityUI` (banner
actions), `Sources/KeyServerClient` (VKS base URL), and the container app
(`ContentView.swift`, `Localizable.xcstrings`) — which confirmed the ＋ menu
offers **Ed25519 (default), RSA-3072, and ECDSA P-256**, and that a
**Key Servers…** settings sheet manages custom VKS/HKPS/WKD servers.

### Vue islands — `src/components/`

- **`FingerprintTool.vue`** — paste an OpenPGP fingerprint; normalizes input,
  validates 40-hex length and character set, renders the canonical 10×4
  grouped form, derives the long key ID, copy-to-clipboard, sample fill.
  Used on the landing page and linked from Key Management.
- **`TrustStateDemo.vue`** — interactive unverified/verified/problem selector
  rendering a mock Mail banner with the app's state colors and the practical
  effect of each state (including the `trustConflict` encryption block).
  Embedded in Trust & Verification.
- **`KeyserverLookup.vue`** — enter an email address; computes the exact VKS
  URL and both WKD URLs (advanced + direct), including the real WKD `hu` hash
  (SHA-1 of the lowercase local part, z-base-32 encoded, via
  `crypto.subtle`). Purely local; no network requests. Embedded in Keyservers
  and on the landing page.

### Styling & config

- `src/styles/global.css` — Tailwind 4 theme+utilities layers (preflight
  deliberately skipped so it cannot fight Starlight's styles),
  `@custom-variant dark` keyed to `[data-theme='dark']`, Starlight accent
  tokens overridden to the RNP brand (`#1A7BEC` light / `#58A0F4` dark),
  landing base styles and animation helpers.
- `astro.config.mjs` — Starlight (logo, GitHub social, edit links, 3-group
  sidebar matching the manual structure), Vue integration, Tailwind Vite
  plugin; commented note on setting `base` for GitHub Pages project deploys.
- `public/favicon.svg` — brand-gradient lock icon.
- `docs-site/.gitignore` — `dist/`, `node_modules/`, `.astro/`, env files.

## Verification

- `pnpm install` — clean (after approving esbuild's postinstall via
  `docs-site/pnpm-workspace.yaml` `allowBuilds`, which pnpm 11 requires;
  lockfile passes the configured supply-chain policy check).
- `pnpm build` — succeeds: 11 pages prerendered, Pagefind search index built,
  sitemap generated.
- Served `dist/` locally (`npx serve -l 4173 dist`): all 10 routes return
  HTTP 200.
- All 3 Vue islands confirmed bundled as client chunks
  (`dist/_astro/{FingerprintTool,KeyserverLookup,TrustStateDemo}.*.js`) and
  referenced via `component-url` in the landing page.
- Tailwind output confirmed: brand-color arbitrary-value utilities and 61
  `[data-theme=dark]` dark-variant rules generated.
- Link check over every built HTML file: 23 unique root-relative links — no
  broken targets; every `href="#fragment"` anchor also verified to exist.
- Spot-checked rendered HTML: landing hero/title/6 feature cards present;
  docs pages carry Starlight chrome with the full sidebar.

## Deploy notes

Static output in `docs-site/dist/` — deployable to Netlify/Vercel as-is. For
GitHub Pages project sites, set `base: '/swift-rnp'` in `astro.config.mjs`
(marked with a comment there).

## Concerns / follow-ups

- The Mail banner "screenshots" are faithful CSS mockups, not captured app
  screenshots (the repo's snapshot fixtures are transparent-background test
  renders, unsuitable for a marketing page). Real screenshots can be dropped
  in later without structural changes.
- The `site` URL is set to `https://rnpgp.github.io` as a placeholder; adjust
  when the production URL is known.
- Starlight's Pagefind search indexes the docs pages; the custom landing page
  is outside Pagefind's scope by design (it's not part of the docs
  collection).
