#!/bin/bash
set -euo pipefail

plugins="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}/Contents/PlugIns"
dest="${plugins}/GrailsSafari.appex"

if [ "${GRAILS_SAFARI_EXTENSION:-NO}" = "YES" ]; then
  src="${SAFARI_APPEX_SRC:-${BUILT_PRODUCTS_DIR:?}/GrailsSafari.appex}"
  if [ ! -d "$src" ]; then
    echo "embed-safari-extension: GRAILS_SAFARI_EXTENSION=YES but ${src} is missing" >&2
    exit 1
  fi
  mkdir -p "$plugins"
  rm -rf "$dest"
  cp -R "$src" "$dest"
  exit 0
fi

rm -rf "$dest"
