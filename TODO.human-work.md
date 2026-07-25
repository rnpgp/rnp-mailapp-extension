# Human-only remaining work

This file lists every remaining task that cannot be automated in code.
All codeable work in `TODO.impl/` and `TODO.roadmap/` is complete.

## Apple Developer account (blocks: 03, 08)

These items require an active Apple Developer Program membership
(organizational team preferred for `rnpgp`):

1. **Register identifiers**:
   - App Group: `group.com.rnpgp.RnpMail`
   - App ID (container): `com.rnpgp.RnpMail`
   - App ID (extension): `com.rnpgp.RnpMail.MailExtension`

2. **Generate certificates**:
   - **Developer ID Application** (for direct download distribution)
   - **Apple Distribution** (for Mac App Store distribution)
   - Export each as `.p12` for CI use.

3. **Create App Store Connect API key**:
   - Users & Access → Integrations → Generate key.
   - Key ID + Issuer ID + `.p8` file needed for notarytool + altool.

4. **Configure GitHub secrets** (repo `rnpgp/rnp-mailapp-extension`):
   - `MACOS_CERTIFICATE_P12` — base64-encoded .p12
   - `MACOS_CERTIFICATE_P12_PASSWORD`
   - `KEYCHAIN_PASSWORD`
   - `ASC_API_KEY_P8` — base64-encoded .p8
   - `ASC_API_KEY_ID`
   - `ASC_ISSUER_ID`
   - `TEAM_ID`

5. **App Store Connect app record**:
   - Create the app record for `com.rnpgp.RnpMail`.
   - Privacy policy URL (can be `https://rnpgp.org/privacy`).
   - Encryption export self-classification (open-source ERN route).

## Notarization dry-run (TODO.impl 03)

Once Apple secrets are configured:

1. Tag a test release: `git tag v0.9.0-test && git push origin v0.9.0-test`.
2. The `release-direct` workflow will archive, sign, notarize, staple,
   and upload a DMG to the GitHub Release.
3. Verify `spctl -a -t install -vv` passes on the downloaded DMG.
4. Delete the test tag + release afterward.

## Mac App Store submission (TODO.impl 08)

1. After notarization dry-run passes, the `release-appstore` workflow
   will upload to App Store Connect on the same tag.
2. **TestFlight**: create an external beta group "rnpgp-beta". Dogfood
   for ≥1 week on ≥3 machines (one must be a clean install).
3. **App Review submission**: fill in metadata, screenshots, demo video.
   - Screenshots: 1280×800 minimum. Capture Keys tab, Recipients tab,
     Mail compose with banner, onboarding flow.
   - Review notes: "Enable in Mail → Settings → Extensions after first
     launch. No account required."
   - 60–90s screen recording: create key → enable extension → send
     signed+encrypted → receive + verify banner.
4. Respond to review feedback within 48h. Common rejection causes for
   Mail extensions: reviewer can't find the enable step (mitigate with
   video + notes), app "lacks functionality" standalone (the key
   manager IS the standalone functionality — say so).

## Manual QA (blocks: release)

1. **Manual Mail.app testing** (8 scenarios, issues #15–#22 on GitHub):
   - Install + enable extension in Apple Mail
   - Generate key and sign/encrypt an outgoing message
   - Import recipient key and encrypt/decrypt roundtrip
   - Trust verification and key-change conflict flow
   - Key lifecycle: rotate, extend expiry, revoke
   - Keyserver publishing and discovery (VKS/HKPS/WKD)
   - PGP/MIME, inline PGP, attachments, non-ASCII bodies
   - Accessibility and VoiceOver

2. **Touch ID real-world test** (issue #50):
   - Build and sign the app with a valid development certificate.
   - Enable Touch ID during onboarding.
   - Verify keyring requires Touch ID to unlock on subsequent launches.
   - Verify Mail extension prompts for Touch ID when accessing keyring.

3. **Native-speaker translation review** (issue #80):
   - Review machine translations in `Localizable.xcstrings` for
     German, Japanese, French, Spanish, Chinese, Korean, Italian,
     Portuguese, Russian.

4. **Spotlight re-index verification** (documented in
   `docs/encrypted-mail-search.md`):
   - Send encrypted test messages with unique markers.
   - Open in Mail, wait for Spotlight indexing.
   - Search Spotlight for the markers.
   - Update the doc with results.

## Self-hosted runner (issue #27)

The `mail-e2e` workflow needs a self-hosted macOS runner with:
- A valid Apple development certificate installed.
- Mail.app configured and able to run AppleScript.
- Homebrew packages: `dovecot`, `postfix` (or use GreenMail Docker).
- The extension manually enabled once on the runner.
