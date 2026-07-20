#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/channel-isolation-evidence-db-cleanup-20260720-$TS"
DB_BACKUP_DIR="${DB_BACKUP_DIR:-/home/ai-river/db-backups}"
DB_BACKUP="$DB_BACKUP_DIR/river-watch-messages-before-cleanup-$TS.sql.gz"
GROUP_READY_TIMEOUT_SEC="${GROUP_READY_TIMEOUT_SEC:-720}"
MUTATION_STARTED=0

AI_FILES=(group_pool_core.py group_pool_runtime.py)
FRONTEND_FILES=(
  frontend/src/composables/useWorkspace.ts
  frontend/src/components/WorkspaceDialogs.vue
  frontend/src/__tests__/alarmReviewDialog.test.ts
)
DB_TABLES=(
  rw_alarm
  rw_event_group
  rw_event_group_alarm
  rw_work_order
  rw_ai_event
  rw_alarm_evidence
  rw_notification
  rw_uav_task
  rw_evidence_bundle
  rw_playback_clip
)
GROUP_UNITS=(
  river-ai-group@river-a.service
  river-ai-group@river-b.service
  river-ai-group@structure.service
)
BATCH_UNITS=(river-ai-batch@river.service river-ai-batch@structure.service)

run_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
run_docker() { run_root docker "$@"; }
fail() { echo "ERROR: $*" >&2; return 1; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }
require_safe_root() {
  local label="$1" path="$2"
  case "$path" in
    /home/ai-river/*|/opt/river-watch) ;;
    *) fail "$label is outside the allowed deployment roots: $path" ;;
  esac
}
mysql_scalar() {
  run_docker exec "$mysql_ctn" sh -lc \
    'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "$1"' sh "$1"
}
mysql_exec() {
  run_docker exec "$mysql_ctn" sh -lc \
    'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "$1"' sh "$1"
}
require_hash() {
  local label="$1" path="$2" expected="$3" actual
  [ -f "$path" ] || fail "$label missing: $path"
  actual="$(file_hash "$path")"
  [ "$actual" = "$expected" ] || fail "$label baseline drift: actual=$actual expected=$expected"
  echo "OK $label $actual"
}
wait_for_http() {
  local label="$1" url="$2"
  for attempt in $(seq 1 60); do
    if curl -fsS -m 5 "$url" >/dev/null 2>&1; then
      echo "$label ready after attempt $attempt/60"
      return 0
    fi
    sleep 2
  done
  fail "$label did not become ready: $url"
}
backup_file() {
  local target="$1" key
  key="$(printf '%s' "$target" | sed 's#^/##; s#/#__#g')"
  if run_root test -f "$target"; then
    run_root cp -a "$target" "$BACKUP_DIR/files/$key"
    printf '%s\t%s\n' "$target" "files/$key" >> "$BACKUP_DIR/file-manifest.tsv"
  else
    printf '%s\tABSENT\n' "$target" >> "$BACKUP_DIR/file-manifest.tsv"
  fi
}
set_env_value() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  run_root awk -v key="$key" '$0 !~ "^" key "=" { print }' "$file" > "$tmp"
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  run_root install -m 0640 -o root -g ai-river "$tmp" "$file"
  rm -f "$tmp"
}
wait_group() {
  local group="$1" expected="$2" unit="river-ai-group@${1}.service" started count
  started="$(date '+%F %T')"
  run_root systemctl enable --now "$unit"
  for _ in $(seq 1 "$GROUP_READY_TIMEOUT_SEC"); do
    systemctl is-active --quiet "$unit" || { sleep 1; continue; }
    count="$(journalctl -u "$unit" --since "$started" --no-pager 2>/dev/null \
      | grep "session ready ${group}-" | grep -c 'MIGraphXExecutionProvider' || true)"
    if [ "$count" -ge "$expected" ]; then
      echo "ready $group sessions=$expected"
      return 0
    fi
    sleep 1
  done
  journalctl -u "$unit" --since "$started" --no-pager | tail -120 || true
  fail "$group did not warm $expected GPU sessions within ${GROUP_READY_TIMEOUT_SEC}s"
}
rollback() {
  local rc=$? line="${BASH_LINENO[0]:-unknown}"
  trap - ERR
  if [ "$MUTATION_STARTED" -eq 1 ]; then
    echo "ERROR: deployment failed near line $line (rc=$rc); automatic rollback" >&2
    APP_DIR="$APP_DIR" OPT_DIR="$OPT_DIR" \
      bash "$PKG_DIR/scripts/rollback-channel-isolation-evidence-db-cleanup-20260720.sh" "$BACKUP_DIR" || true
  fi
  exit "$rc"
}
trap rollback ERR

echo "== River Watch channel isolation + evidence UI + message cleanup =="
echo "APP_DIR=$APP_DIR"
echo "OPT_DIR=$OPT_DIR"
echo "PKG_DIR=$PKG_DIR"
[ "${CONFIRM_CLEAR_MESSAGES:-}" = "YES" ] || fail "set CONFIRM_CLEAR_MESSAGES=YES to authorize database message cleanup"
require_safe_root APP_DIR "$APP_DIR"
require_safe_root OPT_DIR "$OPT_DIR"
[ -d "$APP_DIR/frontend/src" ] || fail "frontend source directory not found"
[ -d "$OPT_DIR/ai-pipeline/workers" ] || fail "AI runtime directory not found"
run_docker info >/dev/null 2>&1 || fail "Docker is unavailable"

backend_ctn="$(run_docker ps --format '{{.Names}}' | grep -E 'backend' | head -1 || true)"
frontend_ctn="$(run_docker ps --format '{{.Names}}' | grep -E 'frontend|nginx|web' | head -1 || true)"
mysql_ctn="$(run_docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}')"
[ -n "$backend_ctn" ] || fail "backend container not found"
[ -n "$frontend_ctn" ] || fail "frontend container not found"
[ -n "$mysql_ctn" ] || fail "MySQL container not found"

echo "== 1. Verify package and exact production baselines =="
(cd "$PKG_DIR" && sha256sum -c SHA256SUMS)
require_hash "runtime group_pool_core.py" "$OPT_DIR/ai-pipeline/workers/group_pool_core.py" "e46a2304219b07f0442fe230dfab0f75ac04f42dcbf3097a028ab66646db177f"
require_hash "runtime group_pool_runtime.py" "$OPT_DIR/ai-pipeline/workers/group_pool_runtime.py" "3905df82fa0f1349db9c3a72e1a7de4991aa6949d16a8e2a5f018da369fa69a4"
require_hash "frontend useWorkspace.ts" "$APP_DIR/frontend/src/composables/useWorkspace.ts" "2739be87edb847370b2b2e984761eee732bda3f51a5e7b9d33420750e1f8653f"
require_hash "frontend WorkspaceDialogs.vue" "$APP_DIR/frontend/src/components/WorkspaceDialogs.vue" "64250cb44447431b7bf44d1264091342d284b5ab08ca1dbc96648ea630f88024"
require_hash "frontend alarmReviewDialog.test.ts" "$APP_DIR/frontend/src/__tests__/alarmReviewDialog.test.ts" "c2504eb325c2f41d74da177ef2efe362d7f160387c7cd7af9ae4339e70d9c1ed"
[ "$(mysql_scalar "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('rw_alarm','rw_event_group','rw_event_group_alarm','rw_work_order','rw_ai_event','rw_alarm_evidence','rw_notification','rw_uav_task','rw_evidence_bundle','rw_playback_clip')")" = "10" ] || fail "one or more cleanup tables are missing"
curl -fsS -m 8 http://127.0.0.1:8080/api/health >/dev/null

echo "== 2. Backup changed files, service state and database messages =="
run_root mkdir -p "$BACKUP_DIR/files" "$BACKUP_DIR/frontend/dist" "$DB_BACKUP_DIR"
run_root chown "$(id -u):$(id -g)" "$BACKUP_DIR" "$BACKUP_DIR/files" "$BACKUP_DIR/frontend" "$BACKUP_DIR/frontend/dist" "$DB_BACKUP_DIR"
: > "$BACKUP_DIR/file-manifest.tsv"
: > "$BACKUP_DIR/service-state.tsv"
for file in "${AI_FILES[@]}"; do
  backup_file "$OPT_DIR/ai-pipeline/workers/$file"
  backup_file "$APP_DIR/ai-pipeline/workers/$file"
done
for rel in "${FRONTEND_FILES[@]}"; do backup_file "$APP_DIR/$rel"; done
for channel in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08 CH09 CH10; do
  backup_file "/etc/river-watch/ai-worker-${channel}.env"
done
run_root cp -a "$APP_DIR/frontend/dist/index.html" "$BACKUP_DIR/frontend/dist/index.html"
run_root cp -a "$APP_DIR/frontend/dist/assets" "$BACKUP_DIR/frontend/dist/assets"
for unit in "${GROUP_UNITS[@]}" "${BATCH_UNITS[@]}"; do
  printf '%s\t%s\t%s\n' "$unit" \
    "$(systemctl is-enabled "$unit" 2>/dev/null || true)" \
    "$(systemctl is-active "$unit" 2>/dev/null || true)" >> "$BACKUP_DIR/service-state.tsv"
done

MUTATION_STARTED=1
run_root systemctl stop "${GROUP_UNITS[@]}" "${BATCH_UNITS[@]}" || true
run_docker stop "$backend_ctn" >/dev/null
for table in "${DB_TABLES[@]}"; do
  printf '%s\t%s\n' "$table" "$(mysql_scalar "SELECT COUNT(*) FROM $table")" >> "$BACKUP_DIR/database-counts-before.tsv"
done
run_docker exec "$mysql_ctn" sh -lc \
  'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" --single-transaction --quick --hex-blob --skip-triggers --no-create-info "$@"' \
  sh "${DB_TABLES[@]}" | gzip -1 > "$DB_BACKUP"
[ -s "$DB_BACKUP" ] || fail "database backup is empty"
gzip -t "$DB_BACKUP"
printf '%s\n' "$DB_BACKUP" > "$BACKUP_DIR/db-backup.path"
sha256sum "$DB_BACKUP" > "$DB_BACKUP.sha256"

echo "== 3. Clear alarm lifecycle messages in one transaction =="
mysql_exec "SET FOREIGN_KEY_CHECKS=0;
START TRANSACTION;
DELETE FROM rw_event_group_alarm;
DELETE FROM rw_alarm_evidence;
DELETE FROM rw_notification;
DELETE FROM rw_playback_clip;
DELETE FROM rw_evidence_bundle;
DELETE FROM rw_uav_task;
DELETE FROM rw_work_order;
DELETE FROM rw_ai_event;
DELETE FROM rw_event_group;
DELETE FROM rw_alarm;
COMMIT;
SET FOREIGN_KEY_CHECKS=1;"
for table in "${DB_TABLES[@]}"; do
  count="$(mysql_scalar "SELECT COUNT(*) FROM $table")"
  printf '%s\t%s\n' "$table" "$count" >> "$BACKUP_DIR/database-counts-after.tsv"
  [ "$count" = "0" ] || fail "$table was not cleared"
done

echo "== 4. Install channel class isolation and preserve all other AI settings =="
for file in "${AI_FILES[@]}"; do
  run_root install -D -m 0644 "$PKG_DIR/ai-pipeline/workers/$file" "$OPT_DIR/ai-pipeline/workers/$file"
  install -D -m 0644 "$PKG_DIR/ai-pipeline/workers/$file" "$APP_DIR/ai-pipeline/workers/$file"
done
RIVER_TYPES="漂浮物,漂浮物聚集,浮游物,水色异常,水位异常,人员落水,非法倾倒"
STRUCTURE_TYPES="墙体裂痕,污水渗漏,地面水渍"
for channel in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
  set_env_value "/etc/river-watch/ai-worker-${channel}.env" ALLOWED_ALARM_TYPES "$RIVER_TYPES"
done
for channel in CH09 CH10; do
  set_env_value "/etc/river-watch/ai-worker-${channel}.env" ALLOWED_ALARM_TYPES "$STRUCTURE_TYPES"
done
run_root rm -rf "$OPT_DIR/ai-pipeline/workers/__pycache__"

echo "== 5. Install evidence UI source and compact prebuilt assets =="
for rel in "${FRONTEND_FILES[@]}"; do
  run_root install -D -m 0644 "$PKG_DIR/$rel" "$APP_DIR/$rel"
done
run_root rm -rf "$APP_DIR/frontend/dist/assets"
run_root cp -a "$PKG_DIR/frontend/dist/assets" "$APP_DIR/frontend/dist/assets"
run_root cp -a "$PKG_DIR/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"
run_docker exec "$frontend_ctn" sh -lc 'rm -rf /usr/share/nginx/html/assets'
run_docker cp "$PKG_DIR/frontend/dist/assets" "$frontend_ctn:/usr/share/nginx/html/assets"
run_docker cp "$PKG_DIR/frontend/dist/index.html" "$frontend_ctn:/usr/share/nginx/html/index.html"

echo "== 6. Restore backend/frontend and group-only inference =="
run_root systemctl disable "${BATCH_UNITS[@]}" >/dev/null 2>&1 || true
run_docker start "$backend_ctn" >/dev/null
run_docker restart "$frontend_ctn" >/dev/null
wait_for_http backend http://127.0.0.1:8080/api/health
wait_for_http frontend http://127.0.0.1:8081/
run_root systemctl daemon-reload
wait_group structure 1
wait_group river-a 2
wait_group river-b 2

echo "== 7. Verify deployed behavior =="
APP_DIR="$APP_DIR" OPT_DIR="$OPT_DIR" \
  bash "$PKG_DIR/scripts/verify-channel-isolation-evidence-db-cleanup-20260720.sh"

echo "== 8. Keep only the latest two rollback sets and three database cleanup backups =="
mapfile -t old_backups < <(find "$APP_DIR/backups" -maxdepth 1 -mindepth 1 -type d -name 'channel-isolation-evidence-db-cleanup-20260720-*' -printf '%T@ %p\n' | sort -rn | awk 'NR>2 {$1=""; sub(/^ /, ""); print}')
for old in "${old_backups[@]:-}"; do [ -n "$old" ] && run_root rm -rf -- "$old"; done
mapfile -t old_db < <(find "$DB_BACKUP_DIR" -maxdepth 1 -type f -name 'river-watch-messages-before-cleanup-*.sql.gz' -printf '%T@ %p\n' | sort -rn | awk 'NR>3 {$1=""; sub(/^ /, ""); print}')
for old in "${old_db[@]:-}"; do [ -n "$old" ] && run_root rm -f -- "$old" "$old.sha256"; done

trap - ERR
MUTATION_STARTED=0
echo "VERIFY OK"
echo "DONE"
echo "Database backup: $DB_BACKUP"
echo "Rollback backup: $BACKUP_DIR"

