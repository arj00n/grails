#!/bin/bash
set -euo pipefail

# DEST set means the Linux test. The Xcode default must be the appex Resources folder.

SRC="${SRC:-$SRCROOT/Extensions/chrome}"

if [ -z "${DEST:-}" ]; then
  DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  case "$DEST" in
    *.appex/Contents/Resources) ;;
    *)
      echo "copy-safari-extension-resources: refusing a destination that does not end in .appex/Contents/Resources" >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$DEST"
rsync -a --delete --exclude '.DS_Store' --exclude 'README.md' "$SRC/" "$DEST/"

require() {
  if [ ! -f "$DEST/$1" ]; then
    echo "copy-safari-extension-resources: missing $1" >&2
    exit 1
  fi
}

require manifest.json
require background.js
require lib/client.js
require icons/128.png
require fonts/Geist-Regular.ttf

if [ -f "$DEST/chrome/manifest.json" ]; then
  echo "copy-safari-extension-resources: nested chrome/manifest.json" >&2
  exit 1
fi
if [ -f "$DEST/client.js" ]; then
  echo "copy-safari-extension-resources: flattened client.js at the Resources root" >&2
  exit 1
fi
