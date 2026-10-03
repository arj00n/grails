#!/bin/bash
# Builds a Release Stash.app and wraps it in a DMG: dist/Stash-<version>.dmg
#
# Unsigned by default (ad-hoc signed so it launches on Apple Silicon): teammates right-click ▸ Open the first time.
# To sign and notarize, export:
#   DEVELOPER_ID="Developer ID Application: Swish (TEAMID)"   NOTARY_PROFILE="stash-notary"   (xcrun notarytool store-credentials)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=build
rm -rf "$BUILD/dmg" "dist/Stash-$VERSION.dmg"; mkdir -p "$BUILD/dmg" dist

xcodegen >/dev/null
xcodebuild -scheme Stash -configuration Release -destination 'platform=macOS' -derivedDataPath "$BUILD/derived" CODE_SIGNING_ALLOWED=NO build >/dev/null
APP="$BUILD/derived/Build/Products/Release/Stash.app"
[ -d "$APP" ] || { echo "build failed: no Stash.app"; exit 1; }
cp -R "$APP" "$BUILD/dmg/Stash.app"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$BUILD/dmg/Stash.app"
else
  codesign --force --deep --sign - "$BUILD/dmg/Stash.app"
fi
codesign --verify --deep --strict "$BUILD/dmg/Stash.app"

ln -s /Applications "$BUILD/dmg/Applications"
cat > "$BUILD/dmg/READ ME FIRST.txt" <<TXT
Stash $VERSION

1. Drag Stash into Applications.
2. The first time, right-click Stash ▸ Open ▸ Open (this build isn't notarized yet).
3. Choose "Join the team library" and pick Swish Inspo.stash on the shared drive.

Setup guide: docs/TEAM_SETUP.md in the repository.
TXT

hdiutil create -volname "Stash $VERSION" -srcfolder "$BUILD/dmg" -ov -format UDZO "dist/Stash-$VERSION.dmg" >/dev/null

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "dist/Stash-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/Stash-$VERSION.dmg"
fi
echo "dist/Stash-$VERSION.dmg ($(du -h "dist/Stash-$VERSION.dmg" | cut -f1))"
