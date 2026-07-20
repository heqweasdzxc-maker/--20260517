#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="river-watch-channel-isolation-evidence-db-cleanup-increment-20260720-v2.zip"

cd "$HERE"
cat package-v2-chunks/part-*.b64 | base64 -d > "$NAME"
sha256sum -c "$NAME.sha256"
unzip -t "$NAME" >/dev/null
echo "REBUILD V2 OK: $HERE/$NAME"

