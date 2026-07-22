# Task Report: Astro docs-site redesign ("truly stunning", rnpgp.org theme)

**Branch:** `docs/astro-redesign-stunning` (from `main`)
**Commit:** `b7fa0a9` — docs-site: redesign with rnpgp.org design language
**Status:** DONE

## Goal

Make `docs-site/` (Astro 7 + Starlight + Vue islands + Tailwind 4) visually
stunning by adopting the design language of rnpgp.org, while keeping all
existing content and functionality. Site must build with `pnpm build`, use
brand blue `#1A7BEC`, meet WCAG AA, avoid external UI frameworks, and respect
`prefers-reduced-motion`.

## What rnpgp.org's design language actually is (extracted from the live site)

Pulled `https://www.rnpgp.org` HTML + its compiled CSS and extracted the real
design tokens and component idioms rather than guessing:

- **Fonts:** self-hosted IBM Plex Sans (400/500/600/700) + IBM Plex Mono —
  the exact woff2 files rnpgp.org serves (SIL OFL).
- **Tokens:** light `#f8fbfe` bg / white surface / `#dfe8f2` hairlines /
  `#23273a` fg; dark `#0b0e1a` bg / `#12162c` surface / `#232a4a` hairlines;
  accent `#1a7bec` (light) → `#5ea2f5` (dark), teal `#00dfb7`, gold `#ffdc4a`.
- **Idioms:** `mono-label` uppercase mono eyebrows (`§ 01 — …`), 1px
  blue→teal `gradient-rule` under headings, `card`/`card-hover` with
  lift+accent-border, `chip` pills, navy hero band
  (`linear-gradient(160deg,#0c1230,#0f1a44,#0a2a33)` + radial blue/teal/gold
  glows + fading grid overlay), app-widget chrome (dim header bar + mono
  label + pulsing teal live-dot + "Computed locally — nothing leaves this
  page." footer), window chrome with macOS traffic lights, always-dark navy
  footer topped by a gradient rule.

## Changes

### New files
- `docs-site/public/fonts/*.woff2` (8 files, ~160 KB) — IBM Plex Sans
  400/400i/500/600/700 + Mono 400/500/700, vendored from rnpgp.org.
- `docs-site/public/rnp-symbol.svg` — official RNP three-circle brand mark
  (gold/blue/teal), fetched from rnpgp.org brand assets; used in nav, hero
  watermark, and footer.

### `docs-site/src/styles/global.css` (rewritten — the design system)
- `@font-face` for the 8 vendored fonts; preloads on the landing page.
- Design tokens (`:root` + `:root[data-theme='dark']`) with rnpgp.org values.
- `@theme inline` token utilities (`bg-background`, `text-soft`,
  `border-line`, `bg-tint-blue`, `shadow-lift`, …) so templates stay
  theme-agnostic; `font-sans`/`font-mono` mapped to IBM Plex.
- Component classes in `@layer components`: `.mono-label`, `.gradient-rule`,
  `.card`/`.card-hover`, `.chip` (+teal/gold/outline), `.btn` (+primary,
  ghost, white, outline-white, lg, sm), `.link-arrow`, `.feature-icon`,
  `.widget` (+header/body/footer, `.live-dot`), `.window` (+titlebar,
  traffic-light dots), `.field-input`/`.field-label`, `.hero-band`,
  `.hero-grid`, `.band-tint`, `.band-gold`, `.site-footer`, `.step-number`,
  `.skip-link`.
- **Cascade-layer fix:** the site imports only `theme.css` + `utilities.css`
  (no preflight). Without the full `tailwindcss` import there is no canonical
  layer order, so `@layer components` landed *after* utilities and `.chip`
  silently defeated `.hidden` (the nav chip stayed visible on mobile). Added
  an explicit `@layer theme, base, components, utilities;` declaration before
  the imports and moved `@font-face` after them (@import must lead the file).
- Landing base styles: IBM Plex, link reset (preflight is off), brand
  selection color, `:focus-visible` outlines, smooth scroll.
- Starlight mapping: full `--sl-color-*` palette for both themes (accent
  `#1A7BEC`/deep `#0f5fc4` light, `#5ea2f5` dark; aside tints incl. remapped
  `tip` → brand teal), `--sl-font`/`--sl-font-mono` → IBM Plex.
- Docs polish: brand-colored underlined content links, inline-code pills,
  rounded/shadowed Expressive Code frames, card-styled tables, rounded tinted
  asides, mono-label sidebar group labels + tint pill for the current page,
  accent ToC hover/current, translucent blurred header, card-style
  pagination, `prefers-reduced-motion` guards for widgets/cards/reveal
  (docs pages are outside `.landing-root`, so the guard is global now).

### `docs-site/src/pages/index.astro` (redesigned)
- Sticky blurred nav: RNP symbol + "for Apple Mail" chip, section links,
  theme toggle (synced with Starlight's `starlight-theme`), Download button.
- **Hero:** always-dark navy band with grid overlay + faint RNP-symbol
  watermark; mono eyebrow, 3.4rem headline "OpenPGP for Apple Mail, native
  and polished.", sub, white/outline CTAs, mono trust facts; right side a
  mock **Mail window** (traffic lights, app icon, verified-signature banner
  with fingerprint, skeleton text, Encrypted/Verified chips).
- Gold band crediting librnp/Thunderbird with a link to rnpgp.org.
- `§ 01 — Features`: 6 icon cards (existing copy) with hover lift +
  icon-tile inversion + "Learn more →".
- `§ 02 — The app`: mock **Key Manager window** (key list with
  Verified/Conflict chips, detail pane with grouped fingerprint, action
  buttons) + the 3 Mail banner states as cards.
- `§ 03 — Try it`: **all three** Vue islands (previously only two) framed as
  app widgets.
- `§ 04 — Security`: split layout, 4 security-point cards.
- `§ 05 — Get started`: three numbered step cards with links into the manual.
- `§ 06 — Download`: navy band CTA; always-dark footer with gradient rule,
  Manual/Project link columns, license line.
- a11y: skip-link, semantic `<main>`, `scroll-mt-20` on anchored sections.

### Vue islands (`src/components/*.vue`)
- All three wrapped in widget chrome: dim header bar with mono label +
  pulsing teal live-dot, body, mono footer note. Same logic; no behavior
  removed.
- `FingerprintTool.vue`: formatted-output panel restyled; clipboard failure
  now shows "Copy failed" instead of being silently swallowed.
- `KeyserverLookup.vue`: new **loading state** — pulsing skeleton bar in the
  WKD rows while the async SHA-1 `hu` hash computes (`aria-busy`).
- `TrustStateDemo.vue`: inactive tabs previously used light-theme state
  colors (e.g. `#0E7A55`, ~2.5:1 on dark navy — illegible). Tabs now use CSS
  vars with brighter dark variants (`#3ECF9A` etc.); scoped
  `prefers-reduced-motion` rule added for the banner transition.

### `docs-site/astro.config.mjs`
- `expressiveCode.styleOverrides`: `borderRadius: 0.75rem`, IBM Plex Mono,
  per-theme `codeBackground` (`#f4f8fd` light / `#0f1326` dark).

## Verification

- `pnpm build` — clean, 11 pages (+ pagefind index + sitemap).
- **Screenshot review** (Playwright/Chromium, 1440×900 and 390×844, light +
  dark, scrolled per section): hero, features, app preview, demos, security,
  steps, CTA/footer, mobile hero/features, installation (tabs, steps, tip
  aside), keyserver (styled table + widget), trust-verification (widget in
  docs), troubleshooting (terminal code frame). All render as designed in
  both themes; dark mode has no jarring shifts.
- **Link check:** scripted crawl of every internal `href`/`src` in
  `dist/**/*.html` — all resolve (11 pages). Found and fixed a stale
  `ec.w36nc.css` reference caused by Astro's content cache holding the old
  Expressive Code hash; cleared `.astro/`/`node_modules/.astro`/`.vite` and
  re-verified clean (note: this cache staleness also exists on `main`
  whenever the EC config changes — the fix is `astro sync`/cache clear, not
  a code change).
- Interactions exercised live: theme toggle, trust-state tab switching,
  fingerprint sample/validation/copy, keyserver URL generation incl. loading
  state.
- Contrast: body/link/accent text in both themes meets WCAG AA
  (`#0f5fc4` links on light ≈ 5.9:1; `#5ea2f5` on `#0b0e1a` ≈ 6.9:1; fixed
  the dark trust-tab violation noted above).

## Files touched

- `docs-site/src/styles/global.css` (rewritten)
- `docs-site/src/pages/index.astro` (rewritten)
- `docs-site/src/components/FingerprintTool.vue`
- `docs-site/src/components/KeyserverLookup.vue`
- `docs-site/src/components/TrustStateDemo.vue`
- `docs-site/astro.config.mjs` (Expressive Code style overrides)
- `docs-site/public/fonts/` (8 new woff2), `docs-site/public/rnp-symbol.svg`

## Concerns / follow-ups

- IBM Plex currently covers the **latin subset only** (same as rnpgp.org).
  The docs site content is English-only today, so this is fine; if docs get
  localized, add the matching subsets or fall back per-locale.
- The UI previews are faithful **mock** windows, not real screenshots (the
  repo has none; `docs/app-store/screenshots-checklist.md` tracks producing
  real ones). Swapping in real screenshots later is a drop-in change.
- No automated visual-regression tests exist; verification was manual via
  Playwright screenshots (scripts were throwaway, not committed).
