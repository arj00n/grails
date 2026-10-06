#!/bin/bash
# Cuts a Sparkle release: builds the DMG, signs it for Sparkle, adds it to the appcast and the site. Publishes nothing.
#
#   Scripts/release.sh [VERSION BUILD] [--github]
#
# VERSION and BUILD come from project.yml (MARKETING_VERSION, CURRENT_PROJECT_VERSION). Passing them only checks that they match:
# edit project.yml first, the script never bumps anything. BUILD must be higher than every build already in the appcast.
# Refuses to run twice for the same version (re-running after a failure before the appcast step is safe).
# See docs/UPDATES.md.
set -euo pipefail
cd "$(dirname "$0")/.."

# ---- Settings -------------------------------------------------------------------------------------------------------------
# Where Sparkle downloads the DMG from ({version} is filled in). The default is the site (this script copies the DMG to site/download/),
# because arj00n/grails is private: an installed app has no login, so GitHub release assets there can't be downloaded. If the releases
# ever live in a public repo, use:
#   DMG_URL_TEMPLATE='https://github.com/arj00n/<public repo>/releases/download/v{version}/Grails-{version}.dmg' Scripts/release.sh
[ -n "${DMG_URL_TEMPLATE:-}" ] || DMG_URL_TEMPLATE='https://grails.arjoon.xyz/download/Grails-{version}.dmg'
GITHUB_REPO="${GITHUB_REPO:-arj00n/grails}"
# The private EdDSA key (exported with generate_keys -x). Never in the repo.
KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/Library/Application Support/Grails-release/sparkle_ed25519_private.key}"
SITE="${SITE_DIR:-site}"
# ---------------------------------------------------------------------------------------------------------------------------

die() { echo "release: $*" >&2; exit 1; }

GITHUB=0; ARGS=()
for a in "$@"; do
  case "$a" in
    --github) GITHUB=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $a" ;;
    *) ARGS+=("$a") ;;
  esac
done

yml() { grep -E "^ +$1:" project.yml | head -1 | sed -E 's/.*: *"?([^"]+)"?.*/\1/'; }
VERSION=$(yml MARKETING_VERSION); BUILD=$(yml CURRENT_PROJECT_VERSION); MIN_OS=$(yml MACOSX_DEPLOYMENT_TARGET)
case ${#ARGS[@]} in
  0) ;;
  2) [ "${ARGS[0]}" = "$VERSION" ] && [ "${ARGS[1]}" = "$BUILD" ] ||
       die "project.yml says $VERSION (build $BUILD), not ${ARGS[0]} (build ${ARGS[1]}). Edit MARKETING_VERSION / CURRENT_PROJECT_VERSION first." ;;
  *) die "usage: Scripts/release.sh [VERSION BUILD] [--github]" ;;
esac
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "MARKETING_VERSION '$VERSION' isn't a version number"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "CURRENT_PROJECT_VERSION '$BUILD' must be a whole number"
[ -f "$KEY_FILE" ] || die "no signing key at $KEY_FILE (see docs/UPDATES.md)"

APPCAST="$SITE/appcast.xml"
DMG_NAME="Grails-$VERSION.dmg"
DMG_URL=$(printf %s "$DMG_URL_TEMPLATE" | sed "s/{version}/$VERSION/g")

# ---- Refuse before building if this version is already out ----------------------------------------------------------------
mkdir -p "$SITE"
if [ ! -f "$APPCAST" ]; then
  cat > "$APPCAST" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Grails</title>
    <link>https://grails.arjoon.xyz/appcast.xml</link>
    <description>Grails updates</description>
    <language>en</language>
  </channel>
</rss>
XML
fi
python3 - "$APPCAST" "$VERSION" "$BUILD" <<'PY' || exit 1
import sys, xml.etree.ElementTree as ET
path, version, build = sys.argv[1], sys.argv[2], int(sys.argv[3])
S = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items = ET.parse(path).getroot().find("channel").findall("item")
for it in items:
    v, b = it.findtext(S + "shortVersionString"), it.findtext(S + "version")
    if v == version or b == str(build):
        sys.exit(f"release: {path} already has {v} (build {b}); bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml")
    if b and b.isdigit() and int(b) >= build:
        sys.exit(f"release: build {build} isn't higher than build {b} ({v}) already in {path}")
PY

# ---- Build -----------------------------------------------------------------------------------------------------------------
Scripts/make-dmg.sh
DMG="dist/$DMG_NAME"
APP="build/dmg/Grails.app"
[ -f "$DMG" ] || die "make-dmg.sh didn't produce $DMG"
plist() { /usr/libexec/PlistBuddy -c "Print $1" "$APP/Contents/Info.plist"; }
[ "$(plist CFBundleShortVersionString)" = "$VERSION" ] && [ "$(plist CFBundleVersion)" = "$BUILD" ] ||
  die "built app is $(plist CFBundleShortVersionString) ($(plist CFBundleVersion)), expected $VERSION ($BUILD)"
PUBLIC_KEY=$(plist SUPublicEDKey)

# ---- Sign for Sparkle and check against the key inside the app ---------------------------------------------------------------
BIN="${SPARKLE_BIN:-build/derived/SourcePackages/artifacts/sparkle/Sparkle/bin}"
[ -x "$BIN/sign_update" ] || die "no sign_update in $BIN (make-dmg.sh resolves Sparkle there)"
SIGNATURE=$("$BIN/sign_update" --ed-key-file "$KEY_FILE" -p "$DMG")
LENGTH=$(stat -f %z "$DMG")
CHECK=$(mktemp -d)/check.swift
cat > "$CHECK" <<'SWIFT'
import CryptoKit
import Foundation
let a = CommandLine.arguments
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: a[1])!)
exit(key.isValidSignature(Data(base64Encoded: a[2])!, for: try Data(contentsOf: URL(fileURLWithPath: a[3]))) ? 0 : 1)
SWIFT
xcrun swift "$CHECK" "$PUBLIC_KEY" "$SIGNATURE" "$DMG" ||
  die "the DMG's signature doesn't match SUPublicEDKey in the app: wrong key file? Installed copies would reject this update."

# ---- Site: the DMG and release.json ------------------------------------------------------------------------------------------
mkdir -p "$SITE/download"
cp "$DMG" "$SITE/download/$DMG_NAME"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
if [ -f "$SITE/release.json" ]; then
  python3 - "$SITE/release.json" "$VERSION" "$DMG_NAME" "$LENGTH" "$SHA" <<'PY'
import json, sys
path, version, name, size, sha = sys.argv[1:]
with open(path) as f: r = json.load(f)
r.update(version=version, file=name, url=f"/download/{name}", bytes=int(size), sha256=sha)   # everything else (extension, …) untouched
with open(path, "w") as f: f.write(json.dumps(r))
PY
fi

# ---- Appcast: newest item first (last, so a failure above leaves it untouched) ----------------------------------------------
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
python3 - "$APPCAST" "$VERSION" "$BUILD" "$MIN_OS" "$DMG_URL" "$LENGTH" "$SIGNATURE" "$PUB_DATE" <<'PY'
import sys
from xml.sax.saxutils import quoteattr
path, version, build, min_os, url, length, sig, date = sys.argv[1:]
item = f"""    <item>
      <title>Grails {version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <enclosure url={quoteattr(url)} length="{length}" type="application/octet-stream" sparkle:edSignature={quoteattr(sig)}/>
    </item>
"""
s = open(path).read()
at = s.find("    <item>")
if at < 0: at = s.find("  </channel>")
if at < 0: sys.exit("release: no <channel> in " + path)
open(path, "w").write(s[:at] + item + s[at:])
PY
xmllint --noout "$APPCAST" || die "$APPCAST is no longer valid XML"

echo
echo "Grails $VERSION (build $BUILD)"
echo "  $DMG  $LENGTH bytes  sha256 $SHA"
echo "  appcast: $APPCAST  ->  $DMG_URL"
echo "  site:    $SITE/download/$DMG_NAME, $SITE/release.json"
echo
echo "Next: version strings in the site pages and vercel.json ($SITE/README.md, Release a new version), then upload the DMG to"
echo "$DMG_URL before deploying the site: installed copies fetch the appcast as soon as it's live."
if [ $GITHUB = 1 ]; then
  echo
  echo "gh release create v$VERSION $DMG --repo $GITHUB_REPO --title \"Grails $VERSION\" --notes \"\""
fi
