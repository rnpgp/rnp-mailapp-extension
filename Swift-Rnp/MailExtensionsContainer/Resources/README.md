# Resources

## Localizable.xcstrings

The string catalog for the container app. `en` is the source language.

The translations for `de`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`,
`zh-Hans`, and `zh-Hant` are **machine-generated** (initial pass) and are
marked `state: "needs_review"` in the catalog. They **must be reviewed by
native speakers before release**; flip the state to `"translated"` per string
as review completes. Technical terms (OpenPGP, key, fingerprint, trust,
verified, unverified, armor/ASCII armor) should be kept consistent with each
language's established GnuPG/Apple terminology.

`Tests/RnpMailUITests/LocalizationTests.swift` enforces catalog structure,
per-language coverage, non-empty values, and placeholder preservation, and
includes a pseudo-localization round-trip test.
