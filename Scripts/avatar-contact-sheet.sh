#!/bin/bash
# Renders 24 sample generated avatars, light and dark, to review the blobs by eye.
# Usage: Scripts/avatar-contact-sheet.sh [folder]   (default ~/claude-runs/avatar-samples)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HOME/claude-runs/avatar-samples}"
mkdir -p "$OUT"
cd "$ROOT/Packages/GrailsKit"
GRAILS_AVATAR_SHEET="$OUT" swift test --filter AvatarContactSheetTests
echo "Wrote $OUT/blobs-light.png and $OUT/blobs-dark.png"
