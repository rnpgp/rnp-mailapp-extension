# 08 — Mac App Store pipeline & submission

Status: pending · Milestone: M6 · Depends on: 03, 05 · Needs: Apple account
checklist (00-overview) fully done, incl. app record + export-compliance answers

## Goal

`RnpMail` on the Mac App Store: archive → export → upload to App Store
Connect on tag, TestFlight beta, then App Review submission. (Mail
extensions ARE permitted on the MAS inside container apps — WWDC21 10168.)

## Steps

1. `.github/workflows/release-appstore.yml` (tag `v*`, after release-direct):
   - Archive `-configuration AppStore -allowProvisioningUpdates` with the ASC
     API key (same secrets as task 03).
   - Export: `Config/ExportAppStore.plist` (`method: app-store-connect`,
     upload symbols YES).
   - Upload: `xcrun altool --upload-package build/RnpMail.pkg --type macos
      --apiKey <id> --apiIssuer <issuer>` (or Transporter app).
   - Auto-increment `CURRENT_PROJECT_VERSION` from run number; tag ↔
     MARKETING_VERSION check (as in 03).
2. Sandbox audit BEFORE first upload (checklist):
   - No file access outside app-group container + user-selected files
     (grep for FileManager.default paths, `/usr/local`, tmp misuse).
   - `otool -L` on app + appex: only bundle + system libs (task 01).
   - Entitlements exactly match the App IDs registered (task 02) — MAS
     rejects mismatched groups at upload validation.
   - PrivacyInfo.xcprivacy present in both bundles (task 02).
3. TestFlight: create external group "rnpgp-beta", add builds automatically
   via ASC API (`xcrun altool` can't set groups — use App Store Connect API
   `POST /v1/betaGroups` or do it manually once; document). Dogfood target:
   ≥1 week, ≥3 machines incl. one clean (never had the app).
4. App Review submission package (human, in App Store Connect):
   - Metadata: name, subtitle, description (write from README + UX
     principles), keywords (openpgp, pgp, encryption, mail, privacy),
     category Utilities (secondary: Productivity), privacy policy URL.
   - Screenshots: 1280×800 min set — Keys tab, Recipients, Mail compose with
     banner, onboarding (capture on a demo account, no real keys/emails!).
   - Review notes: "Enable in Mail → Settings → Extensions after first
     launch. No account required. Demo video attached." Attach a 60–90s
     screen recording: create key → enable extension → send signed+encrypted
     → receive + verify banner.
   - Encryption export: answer per the self-classification prepared in the
     account checklist (open-source crypto, ERN notification route).
   - Age rating: 4+; no in-app purchases.
5. Post-approval: GH Release notes get the MAS link; README badge
   ("Download on the Mac App Store").

## Acceptance criteria

- Upload validation passes (no entitlement/sandbox errors) on the first or
  second attempt; build visible in TestFlight.
- App Review approval (allow 1–3 review cycles; respond within 48h).

## Risks / notes

- Common rejection causes for Mail extensions: reviewer can't find the
  enable step (mitigate with the video + notes), app "lacks functionality"
  standalone (the key manager IS the standalone functionality — say so),
  crypto export paperwork incomplete.
- Keep the direct-download channel fully supported regardless — some users
  (and all betas) will use it.
