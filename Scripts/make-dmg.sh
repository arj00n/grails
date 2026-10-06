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
# XcodeGen 2.46 types a .icon as wrapper.icon. Xcode 27 only compiles it as the app icon when the type is folder.iconcomposer.icon.
sed -i '' 's/lastKnownFileType = wrapper\.icon;/lastKnownFileType = folder.iconcomposer.icon;/' Grails.xcodeproj/project.pbxproj
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

# The installer window: the app and an Applications shortcut over a picture with the steps on it (Scripts/gen-dmg-background.py,
# Scripts/dmg-settings.py). It needs dmgbuild:  python3 -m venv ~/.local/share/grails-dmg && ~/.local/share/grails-dmg/bin/pip install dmgbuild
# Without it the DMG is the plain folder (the app, an Applications shortcut and a few lines of text).
DMGBUILD="${DMGBUILD:-$HOME/.local/share/grails-dmg/bin/dmgbuild}"
rm -f "dist/Grails-$VERSION.dmg"
if [ -x "$DMGBUILD" ]; then
  python3 Scripts/gen-dmg-background.py "$BUILD/dmg-background.tiff" >/dev/null
  GRAILS_APP="$PWD/$BUILD/dmg/Grails.app" GRAILS_DMG_BACKGROUND="$PWD/$BUILD/dmg-background.tiff" \
    "$DMGBUILD" -s Scripts/dmg-settings.py "Grails" "dist/Grails-$VERSION.dmg" >/dev/null
else
  ln -s /Applications "$BUILD/dmg/Applications"
  cat > "$BUILD/dmg/READ ME FIRST.txt" <<TXT
Grails $VERSION

1. Drag Grails into Applications.
2. This build isn't notarised yet, so macOS asks before the first launch. Open System Settings > Privacy & Security, scroll down and click "Open Anyway" next to Grails.
3. Press Get Started.

More: https://grails.arjoon.xyz
TXT
  hdiutil create -volname "Grails $VERSION" -srcfolder "$BUILD/dmg" -ov -format UDZO "dist/Grails-$VERSION.dmg" >/dev/null
fi

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "dist/Grails-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/Grails-$VERSION.dmg"
fi
echo "dist/Grails-$VERSION.dmg ($(du -h "dist/Grails-$VERSION.dmg" | cut -f1))"
