#!/bin/bash
# Runs the GrailsSync S3 test against local MinIO, or against whatever GRAILS_S3_* is already set.
# Local credentials are the MinIO root user for 127.0.0.1 only. They are not a Cloudflare token.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT="${SWIFT:-$HOME/swift/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin}"
if [[ -x "$SWIFT/swift" ]]; then export PATH="$SWIFT:$PATH"; fi

if [[ -z "${GRAILS_S3_ENDPOINT:-}" ]]; then
  if [[ -z "${MINIO_BIN:-}" ]]; then
    if [[ -x /tmp/minio-community ]]; then MINIO_BIN=/tmp/minio-community; else MINIO_BIN=/tmp/minio; fi
  fi
  MINIO="$MINIO_BIN"
  DATA="${GRAILS_MINIO_DATA:-/tmp/grails-minio-ce}"
  mkdir -p "$DATA"
  if ! curl -sf -o /dev/null "http://127.0.0.1:9000/minio/health/live"; then
    MINIO_ROOT_USER=grailstest MINIO_ROOT_PASSWORD=grailstest \
      "$MINIO" server "$DATA" --address 127.0.0.1:9000 >/tmp/grails-minio.log 2>&1 &
    echo $! >/tmp/grails-minio.pid
    for _ in $(seq 1 50); do
      curl -sf -o /dev/null "http://127.0.0.1:9000/minio/health/live" && break
      sleep 0.2
    done
  fi
  export GRAILS_S3_ENDPOINT="http://127.0.0.1:9000"
  export GRAILS_S3_BUCKET="${GRAILS_S3_BUCKET:-grails-test}"
  export GRAILS_S3_KEY_ID=grailstest
  export GRAILS_S3_SECRET=grailstest
  export GRAILS_S3_REGION="${GRAILS_S3_REGION:-us-east-1}"
fi
export GRAILS_S3_REQUIRED=1
cd "$ROOT/Packages/GrailsSync"
swift test --filter S3IntegrationTests
