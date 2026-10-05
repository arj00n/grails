#!/bin/bash
# Usage: Scripts/gen-fixture-library.sh ~/Desktop/Big.grails 20000
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c release --package-path Packages/GrailsKit grails-fixture "$@"
