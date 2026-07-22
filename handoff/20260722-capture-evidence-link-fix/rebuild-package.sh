#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ARCHIVE="river-watch-capture-evidence-link-increment-20260722.zip"
cat package-chunks/chunk-*.b64 | tr -d '\r\n' | base64 -d > "$ARCHIVE"
sha256sum -c "$ARCHIVE.sha256"
echo "rebuilt: $PWD/$ARCHIVE"
