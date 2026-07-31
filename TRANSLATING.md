# Translating RNP for Mail

RNP for Mail ships with localizations for **11 locales** declared in `MailApp/MailExtensionsContainer/Resources/Localizable.xcstrings`:

| Code | Language |
|------|----------|
| `en` | English (source language) |
| `de` | German |
| `es` | Spanish |
| `fr` | French |
| `it` | Italian |
| `ja` | Japanese |
| `ko` | Korean |
| `pt` | Portuguese |
| `ru` | Russian |
| `zh-Hans` | Chinese (Simplified) |
| `zh-Hant` | Chinese (Traditional) |

As of writing, **only English has translations**. Every other locale is `state="new"` (a stub) — meaning users in those locales see English fallbacks at runtime. We need native-speaker passes.

## How to translate

### Option A: In Xcode (best for individuals)

1. Open `MailApp/RnpMail.xcodeproj` in Xcode.
2. Navigate to **MailExtensionsContainer → Resources → Localizable.xcstrings**.
3. The String Catalog editor opens. Pick a locale column and fill in values.
4. Mark each translated value as **state = "Translated"** (Xcode does this automatically when you type).
5. Commit and open a PR.

### Option B: Edit the JSON directly (best for bulk / scripted work)

The file is plain JSON. Each key looks like:

```json
"onboarding.welcome.title": {
  "extractionState": "manual",
  "localizations": {
    "en": {
      "stringUnit": {
        "state": "translated",
        "value": "Welcome to RNP for Mail"
      }
    },
    "de": {
      "stringUnit": {
        "state": "new",
        "value": ""
      }
    }
  }
}
```

Set `state` to `"translated"` and `value` to your translation. Validate with `plutil -lint` or by re-opening in Xcode.

### Option C: Use the status script

```bash
scripts/i18n-status.sh
```

prints per-locale coverage:

```
locale      translated /  total   coverage
--------------------------------------------
de                  0 /    269     0.0%
es                  0 /    269     0.0%
…
```

Use it to see what's still missing in your locale, or `--fail-below 80` to fail CI when coverage drops.

## Glossary

Keep translations consistent across the app. Suggested canonical translations:

| English | Notes |
|---------|-------|
| OpenPGP | Keep as-is (proper noun). |
| Key | OpenPGP term. Use the native-language equivalent carefully; some locales keep "Key" in English. |
| Keyring | "Key store" / "Schlüsselbund" / "鍵束" — be consistent. |
| Fingerprint | The 40-char SHA-1 identifier. Don't translate to "thumbprint". |
| Sign / Encrypt / Decrypt | Action verbs; keep parallel. |
| Passphrase | Not "password" — distinguishes from login credentials. |
| Touch ID | Apple trademark; keep as-is. |
| Mail extension | macOS concept; some locales keep "Mail-Erweiterung" etc. |

## Critical strings

Some strings are surfaced in security-critical contexts (warnings, errors). Translating them wrong could mislead the user about their safety. Be especially careful with:

- `error.*` keys
- `warning.*` keys
- `banner.*` keys (the trust-conflict and expired-key banners)
- `foreignPassphrase.*` keys

When in doubt, prefer literal accuracy over fluency for these.

## Tests

`MailApp/Ribose containerUITests/LocalizationAuditTests.swift` runs in CI and enforces that the **~20 onboarding-critical keys** have non-stub translations in every declared locale. The test fails on first launch in any untranslated locale — preventing us from shipping a release that looks broken to new users.

To run the test locally:

```bash
xcodebuild test \
  -project MailApp/RnpMail.xcodeproj \
  -scheme RNP \
  -only-testing:Ribose_containerUITests/LocalizationAuditTests
```

It will fail until translations are added; that's intentional.

## How to declare a new locale

1. Add the locale code to `expectedLocales` in `LocalizationAuditTests.swift`.
2. In Xcode's String Catalog, click **+** → choose the locale. Xcode adds the column to the catalog.
3. Add translations.
4. Open a PR — CI will catch any missing critical keys.
