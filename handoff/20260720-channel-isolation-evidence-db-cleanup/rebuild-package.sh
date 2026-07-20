#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="river-watch-channel-isolation-evidence-db-cleanup-increment-20260720.zip"

cd "$HERE"
cat package-chunks/part-*.b64 | base64 -d > "$NAME"
sha256sum -c "$NAME.sha256"
echo "REBUILD OK: $HERE/$NAME"

