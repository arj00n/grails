#!/bin/bash
# Builds a Release Grails.app and wraps it in a DMG: dist/Grails-<version>.dmg
#
# Unsigned by default (ad-hoc signed so it launches on Apple Silicon): teammates right-click ▸ Open the first time.
# To sign and notarize, export:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"   NOTARY_PROFILE="grails-notary"   (xcrun notarytool store-credentials)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=build
rm -rf "$BUILD/dmg" "dist/Grails-$VERSION.dmg"; mkdir -p "$BUILD/dmg" dist

xcodegen >/dev/null
xcodebuild -scheme Grails -configuration Release -destination 'platform=macOS' -derivedDataPath "$BUILD/derived" CODE_SIGNING_ALLOWED=NO build >/dev/null
APP="$BUILD/derived/Build/Products/Release/Grails.app"
[ -d "$APP" ] || { echo "build failed: no Grails.app"; exit 1; }
cp -R "$APP" "$BUILD/dmg/Grails.app"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$BUILD/dmg/Grails.app"
else
  codesign --force --deep --sign - "$BUILD/dmg/Grails.app"
fi
codesign --verify --deep --strict "$BUILD/dmg/Grails.app"

ln -s /Applications "$BUILD/dmg/Applications"
cat > "$BUILD/dmg/READ ME FIRST.txt" <<TXT
Grails $VERSION

1. Drag Grails into Applications.
2. The first time, right-click Grails ▸ Open ▸ Open (this build isn't notarized yet).
3. Choose "Join the team library" and pick Team Inspo.grails on the shared drive.

Setup guide: docs/TEAM_SETUP.md in the repository.
TXT

hdiutil create -volname "Grails $VERSION" -srcfolder "$BUILD/dmg" -ov -format UDZO "dist/Grails-$VERSION.dmg" >/dev/null

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "dist/Grails-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/Grails-$VERSION.dmg"
fi
echo "dist/Grails-$VERSION.dmg ($(du -h "dist/Grails-$VERSION.dmg" | cut -f1))"
