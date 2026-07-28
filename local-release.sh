#!/bin/bash
# local-release.sh — Build, sign, notarize RNP for Mail from your local Mac.
#
# Prerequisites (already verified present):
#   - Developer ID Application cert in keychain (XX7DG778PN)
#   - Provisioning profiles installed in ~/Library/MobileDevice/Provisioning Profiles/
#   - ASC API key at ~/src/rnp/apple-mail-ext-certs/integration-team-key/
#   - Xcode 15+ with macOS 14 SDK
#
# Usage: cd ~/src/rnp/rnp-mailapp-extension && bash local-release.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="MailApp/RnpMail.xcodeproj"
ARCHIVE_PATH="/tmp/RNP-for-Mail.xcarchive"
EXPORT_PATH="/tmp/RNP-for-Mail-export"
TEAM_ID="XX7DG778PN"
KEY_ID="783G93WNFD"
ISSUER_ID="69a6de7d-2c76-47e3-e053-5b8c7c11a4d1"
KEY_PATH="$HOME/src/rnp/apple-mail-ext-certs/integration-team-key/rnp-mailapp-ci/AuthKey_${KEY_ID}.p8"

echo "=== 1/6: Clean DerivedData ==="
rm -rf ~/Library/Developer/Xcode/DerivedData/RnpMail-*
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "=== 2/6: Archive ==="
xcodebuild \
  -project "$PROJECT" \
  -scheme RNP \
  -configuration Direct \
  archive \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application"

echo "=== 3/6: Export ==="
cat > /tmp/ExportOptions-Local.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist /tmp/ExportOptions-Local.plist

APP_PATH="${EXPORT_PATH}/RNP.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Exported app not found at $APP_PATH"
  ls -la "$EXPORT_PATH"
  exit 1
fi

echo "=== 4/6: Verify code signature ==="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo ""
echo "App size: $(du -sh "$APP_PATH" | cut -f1)"

echo "=== 5/6: Notarize ==="
echo "Submitting to Apple notarization service..."
xcrun notarytool submit "$APP_PATH" \
  --key "$KEY_PATH" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER_ID" \
  --wait

echo "=== 6/6: Staple ==="
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo ""
echo "=== DONE ==="
echo "Notarized + stapled app: $APP_PATH"
echo ""
echo "Verify with Gatekeeper:"
echo "  spctl -a -t install -vv \"$APP_PATH\""
echo ""
echo "To create a DMG:"
echo "  hdiutil create -volname 'RNP for Mail' -srcfolder '$APP_PATH' -ov -format UDZO /tmp/RNP-for-Mail.dmg"
