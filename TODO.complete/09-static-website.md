# 09 — Static website (rnpgp.org)

**Priority**: P1
**Status**: shipped (scaffold in `website/`; DNS + GitHub Pages enable pending)
**Effort**: S (scaffold) + S (DNS, content)
**Dependencies**: none (independent)

## Problem

The only face of RNP today is a GitHub README. Users who'd benefit from
RNP never find it. There's no SEO presence, no shareable landing page,
no perceived "real product" feel. A static site is the price of entry
for any serious tool.

## Goals / non-goals

**Goals**
- Landing page with download CTA, branding, screenshots
- "Getting started" guide for non-technical users
- Security model page (who we are, what we do/don't collect, threat model)
- Privacy policy (required for App Store + Sparkle feed hosting)
- Plain HTML/CSS — no build step, no framework, no JS unless required
- Deployable via GitHub Pages from `/docs` or `/website`

**Non-goals**
- A blog (later)
- i18n (English first; localize once copy is stable)
- A CMS (Markdown + Jekyll on Pages is fine)
- A web-based key lookup tool (keys.openpgp.org already exists)

## Design

### Structure

```
website/
├── index.html                 (landing — download CTA, hero, features, screenshots)
├── getting-started.html       (1-page walkthrough: install → gen key → encrypt mail)
├── security.html              (threat model, data flow, sandbox disclosure)
├── privacy.html               (privacy policy — required for Sparkle + App Store)
├── updates/                   (Sparkle appcast.xml goes here once hosted)
├── assets/
│   ├── style.css              (one file, no framework)
│   ├── screenshot-keys.png
│   ├── screenshot-tools.png
│   └── screenshot-mail.png
└── _config.yml                (Jekyll config — minimal)
```

### Branding

- "RNP — OpenPGP for your Mac"
- Subtitle: "Keys, files, and Mail. Powered by librnp, Thunderbird's
  official end-to-end encryption engine."
- Brand blue: `#1A7BEC` (matches in-app accent)
- Single typeface (system-ui) for v1

### CTA

The download button always points at the latest GitHub release DMG.
Resolved client-side via GitHub API:

```js
fetch('https://api.github.com/repos/rnpgp/rnp-mailapp-extension/releases/latest')
  .then(r => r.json())
  .then(release => {
    const dmg = release.assets.find(a => a.name.endsWith('.dmg'));
    document.getElementById('download').href = dmg.browser_download_url;
  });
```

~10 lines of JS; graceful fallback to releases page if API fails.

## Implementation plan

1. ✅ Author `website/index.html` (shipped)
2. ✅ Author `website/getting-started.html` (shipped)
3. ✅ Author `website/security.html` (shipped)
4. ✅ Author `website/privacy.html` (shipped)
5. ✅ Author `website/assets/style.css` (shipped)
6. Take screenshots, drop into `website/assets/`
7. ronaldtse: configure DNS for rnpgp.org → GitHub Pages
8. Enable GitHub Pages on this repo (`/website` root)
9. Move Sparkle appcast here once TODO 04 needs hosting

## Acceptance criteria

- [ ] Site renders on `https://rnpgp.github.io/rnp-mailapp-extension/`
- [ ] Download button resolves to latest release DMG
- [ ] Lighthouse score ≥ 90 on all four axes (perf, a11y, best-practices, SEO)
- [ ] Privacy policy sufficient for App Store submission
- [ ] Mobile-responsive

## Open questions

- **Domain.** rnpgp.org vs rnpgp.com vs staying at github.io? ronaldtse's
  call. The HTML is domain-agnostic.
- **Screenshots.** Need real ones — currently placeholder hero only.
- **i18n.** English-only for v1; revisit once app translations stabilize.

## References

- Site: `website/`
- GitHub Pages: https://docs.github.com/en/pages
