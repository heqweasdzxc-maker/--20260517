#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
archive="river-watch-capture-evidence-link-increment-20260722-v3.zip"
cat package-parts/part-*.bin > "$archive"
sha256sum -c "$archive.sha256"
echo "rebuilt: $PWD/$archive"
