#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="${TARGET_DIR:-/home/ai-river/river-watch-river-anomaly-model-increment-20260714-v2}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/ai-river/river-watch/backups}"
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="$TARGET_DIR/scripts/apply-river-anomaly-model-increment-20260714-v2.sh"
TARGET_MANIFEST="$TARGET_DIR/SHA256SUMS"
OLD_SCRIPT_SHA="4162dca92edf3167bb7b1ba875e7fc67de2decb9c4e4737f43abf1f45e653703"
OLD_MANIFEST_SHA="3ed34c67d1a6cc0a2902f6481873946e521368d9b5886fe8f3768476a8ae7467"
NEW_SCRIPT_SHA="8ec9e783589b828246e27cb026742573d5c007b377471d492d37851cb8b5ba6b"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/model-deploy-waitfix-20260714-$STAMP"
MUTATED=0

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  return 1
}

sha_of() {
  sha256sum "$1" | awk '{print $1}'
}

rollback() {
  local rc=$?
  if [[ "$MUTATED" -eq 1 ]]; then
    cp -a "$BACKUP_DIR/apply-script.sh" "$TARGET_SCRIPT" || true
    cp -a "$BACKUP_DIR/SHA256SUMS" "$TARGET_MANIFEST" || true
    log "Waitfix rollback restored: $BACKUP_DIR"
  fi
  exit "$rc"
}

trap rollback ERR

log "River Watch deployment wait-condition hotfix"
[[ -d "$TARGET_DIR" ]] || fail "target v2 package directory not found: $TARGET_DIR"
[[ -f "$TARGET_SCRIPT" ]] || fail "target apply script not found"
[[ -f "$TARGET_MANIFEST" ]] || fail "target SHA256SUMS not found"

log "1. Verify waitfix package and exact v2 baseline"
(cd "$PACKAGE_DIR" && sha256sum -c SHA256SUMS)
[[ "$(sha_of "$TARGET_SCRIPT")" == "$OLD_SCRIPT_SHA" ]] || fail "target script is not the original v2 baseline"
[[ "$(sha_of "$TARGET_MANIFEST")" == "$OLD_MANIFEST_SHA" ]] || fail "target manifest is not the original v2 baseline"

log "2. Backup and install only the corrected deployment script and manifest"
mkdir -p "$BACKUP_DIR"
cp -a "$TARGET_SCRIPT" "$BACKUP_DIR/apply-script.sh"
cp -a "$TARGET_MANIFEST" "$BACKUP_DIR/SHA256SUMS"
MUTATED=1
install -m 0755 "$PACKAGE_DIR/payload/scripts/apply-river-anomaly-model-increment-20260714-v2.sh" "$TARGET_SCRIPT"
install -m 0644 "$PACKAGE_DIR/payload/SHA256SUMS" "$TARGET_MANIFEST"

log "3. Verify corrected target package"
bash -n "$TARGET_SCRIPT"
[[ "$(sha_of "$TARGET_SCRIPT")" == "$NEW_SCRIPT_SHA" ]]
(cd "$TARGET_DIR" && sha256sum -c SHA256SUMS)

trap - ERR
MUTATED=0

log "4. Keep only the latest two waitfix backups"
mapfile -t OLD_BACKUPS < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name 'model-deploy-waitfix-20260714-*' -printf '%p\n' | sort -r | tail -n +3
)
for old in "${OLD_BACKUPS[@]:-}"; do
  case "$old" in
    "$BACKUP_ROOT"/model-deploy-waitfix-20260714-*) rm -rf -- "$old" ;;
  esac
done

log "DONE"
log "Corrected target: $TARGET_SCRIPT"
log "Backup: $BACKUP_DIR"
