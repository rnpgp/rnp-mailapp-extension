# Telemetry and Privacy Policy

## Telemetry Stance

**RnpMail collects no telemetry, analytics, crash reports, or usage statistics.**

The app does not include third-party analytics SDKs, advertising identifiers, or network endpoints for diagnostics. The only network traffic initiated by the app is:

- Key upload, discovery, and revocation-check queries to the configured OpenPGP keyserver (default: `keys.openpgp.org`) over HTTPS.
- macOS system services (e.g., Mail.app, iCloud, Keychain) outside the app's control.

No message content, subject lines, contacts, key fingerprints, or key metadata are sent to the developers or to any service other than the user-selected keyserver.

## Mac App Store Privacy Nutrition Label

Because no telemetry is collected, the App Store privacy nutrition label remains empty:

- **Data Not Collected:** The app does not collect any data linked to the user's identity or device.
- **No tracking.**
- **No third-party data sharing.**

This is consistent with the `PrivacyInfo.xcprivacy` manifest included in the `Ribose container` target, which declares no collected data categories.

## Local Diagnostics

Users and developers can run local diagnostics that do not transmit data:

- Launch the container app from Terminal with `--self-test` to perform a local librnp roundtrip check.
- Run `swift test` for the full unit-test suite.
- Console.app and `log stream` can capture local logs on the user's own Mac.

These diagnostics are entirely opt-in and remain on the user's device.

## What Could Change This Policy

If future versions add optional crash reporting or telemetry, the change will be:

1. Documented in this file and in the App Store privacy nutrition label.
2. Opt-in by default (disabled until the user explicitly enables it).
3. Reviewed through the same security process as code changes.

As of the current release, no such feature exists.
