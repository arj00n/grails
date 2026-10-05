#!/bin/bash
# Puts Grails back to a first run, so the next launch starts onboarding: quits the app, forgets the library, the onboarding step, the
# extension pairing and the pairing token, drops stale import journals, and moves the default library (~/Pictures/Grails Library.grails,
# the one onboarding makes) to the Trash. Other libraries are never touched. Used after every build (see PROGRESS.md).
#
#   Scripts/reset-app.sh            reset, then open Grails
#   Scripts/reset-app.sh --no-open  reset only
set -u
APP="/Applications/Grails.app"
SUPPORT="$HOME/Library/Application Support/Grails"
LIB="$HOME/Pictures/Grails Library.grails"

if pgrep -x Grails >/dev/null; then
  osascript -e 'tell application "Grails" to quit' >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8; do pgrep -x Grails >/dev/null || break; sleep 1; done
  pgrep -x Grails >/dev/null && { echo "Grails is still running (a dialog may be open); close it and run this again."; exit 1; }
fi

for k in libraryPath onboarding.v1 extensionPaired workspaces; do defaults delete xyz.arjoon.grails "$k" 2>/dev/null; done
rm -f "$SUPPORT/api-token"
rm -rf "$SUPPORT/Imports"
# to the Trash with plain mv (asking Finder would raise a macOS "wants to control Finder" prompt)
[ -e "$LIB" ] && mv "$LIB" "$HOME/.Trash/Grails Library $(date +%H%M%S).grails"
echo "reset"
[ "${1:-}" = "--no-open" ] || open -a "$APP"
