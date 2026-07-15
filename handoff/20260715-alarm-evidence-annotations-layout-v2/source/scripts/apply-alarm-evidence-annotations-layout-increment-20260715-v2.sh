#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/alarm-evidence-annotations-layout-v2-20260715-$TS"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
BACKEND_CHANGED=0
FRONTEND_CHANGED=0

run_docker() {
  $SUDO docker "$@"
}

fail() {
  echo "ERROR: $*" >&2
  return 1
}

wait_for_http() {
  label="$1"
  url="$2"
  attempts="${3:-60}"
  delay="${4:-2}"
  for attempt in $(seq 1 "$attempts"); do
    if curl -fsS -m 5 "$url" >/dev/null 2>&1; then
      echo "$label ready after attempt $attempt/$attempts"
      return 0
    fi
    sleep "$delay"
  done
  fail "$label did not become ready: $url"
}

check_container_hash() {
  file="$1"
  expected="$2"
  actual="$(run_docker exec "$backend_ctn" sha256sum "/app/src/$file" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || fail "backend baseline drift: $file actual=$actual expected=$expected"
  echo "OK backend $file $actual"
}

check_host_hash() {
  relative="$1"
  expected="$2"
  actual="$(sha256sum "$APP_DIR/$relative" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || fail "frontend baseline drift: $relative actual=$actual expected=$expected"
  echo "OK frontend $relative $actual"
}

rollback() {
  code=$?
  trap - ERR
  echo "== Automatic rollback after deployment failure ==" >&2

  if [ "$FRONTEND_CHANGED" -eq 1 ]; then
    for rel in \
      frontend/src/components/WorkspaceDialogs.vue \
      frontend/src/composables/useWorkspace.ts \
      frontend/src/styles.css \
      frontend/src/__tests__/alarmReviewDialog.test.ts \
      frontend/src/__tests__/alarmFlowSimplification.test.ts
    do
      [ -f "$BACKUP_DIR/$rel" ] && $SUDO cp -a "$BACKUP_DIR/$rel" "$APP_DIR/$rel"
    done
    $SUDO rm -rf "$APP_DIR/frontend/dist/assets"
    $SUDO cp -a "$BACKUP_DIR/frontend/dist/assets" "$APP_DIR/frontend/dist/assets"
    $SUDO cp -a "$BACKUP_DIR/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"
    run_docker exec "$frontend_ctn" sh -lc 'rm -rf /usr/share/nginx/html/assets' || true
    run_docker cp "$BACKUP_DIR/frontend/dist/assets" "$frontend_ctn:/usr/share/nginx/html/assets" || true
    run_docker cp "$BACKUP_DIR/frontend/dist/index.html" "$frontend_ctn:/usr/share/nginx/html/index.html" || true
    run_docker restart "$frontend_ctn" >/dev/null 2>&1 || true
  fi

  if [ "$BACKEND_CHANGED" -eq 1 ]; then
    for file in server.mjs store.mjs alarm-evidence.mjs; do
      [ -f "$BACKUP_DIR/backend/host/$file" ] && $SUDO cp -a "$BACKUP_DIR/backend/host/$file" "$APP_DIR/backend/src/$file"
      [ -f "$BACKUP_DIR/backend/container/$file" ] && run_docker cp "$BACKUP_DIR/backend/container/$file" "$backend_ctn:/app/src/$file" || true
    done
    run_docker restart "$backend_ctn" >/dev/null 2>&1 || true
  fi

  echo "Rollback backup: $BACKUP_DIR" >&2
  exit "$code"
}

trap rollback ERR

echo "== River Watch historical annotation and 3-column review increment v2 =="
echo "APP_DIR=$APP_DIR"
echo "PKG_DIR=$PKG_DIR"

[ -d "$APP_DIR/backend/src" ] || fail "backend source directory not found"
[ -d "$APP_DIR/frontend/src" ] || fail "frontend source directory not found"
run_docker info >/dev/null 2>&1 || fail "Docker is unavailable"

backend_ctn="$(run_docker ps --format '{{.Names}}' | grep -E 'backend' | head -1 || true)"
frontend_ctn="$(run_docker ps --format '{{.Names}}' | grep -E 'frontend|nginx|web' | head -1 || true)"
mysql_ctn="$(run_docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}')"
[ -n "$backend_ctn" ] || fail "backend container not found"
[ -n "$frontend_ctn" ] || fail "frontend container not found"
[ -n "$mysql_ctn" ] || fail "MySQL container not found"

echo "== 1. Verify package and exact deployed baseline =="
(cd "$PKG_DIR" && sha256sum -c SHA256SUMS)
check_container_hash server.mjs 7db1272481c3a6e51797759c22f1cb8574d1c1abed5044b7988baffc6f8182ca
check_container_hash store.mjs 5105048363fe6f2fdd0095a6e8a867abe358701b3c3b588c738c284fdb913196
check_container_hash alarm-evidence.mjs de0fb34a257ffc64b45e4541350bb93c4e33897b208f0d516ca3d4ea046d7036
check_container_hash ai-ingest.mjs ed3e7e09eef0a1f1f0380c6a046ad0b37e448572d1616e95ba704b5586fa6cff
check_host_hash frontend/src/components/WorkspaceDialogs.vue e97e85e25f303d987d1c66794bb0c7605ff6d2d0f5c3167b3ff179ab90b0f2da
check_host_hash frontend/src/composables/useWorkspace.ts df9990aed012c165eed46504bb27a5dbcfafc3891c9a064b4c31c38c876d6772
check_host_hash frontend/src/styles.css 6dbcd77fb2c56bffbd7880def5a1b415b7ab08e572f68f14f1d5fe015f7b0ada

echo "== 2. Backup only changed files =="
$SUDO mkdir -p \
  "$BACKUP_DIR/backend/host" \
  "$BACKUP_DIR/backend/container" \
  "$BACKUP_DIR/frontend/src/components" \
  "$BACKUP_DIR/frontend/src/composables" \
  "$BACKUP_DIR/frontend/src/__tests__" \
  "$BACKUP_DIR/frontend/dist"
for file in server.mjs store.mjs alarm-evidence.mjs; do
  $SUDO cp -a "$APP_DIR/backend/src/$file" "$BACKUP_DIR/backend/host/$file"
  run_docker cp "$backend_ctn:/app/src/$file" "$BACKUP_DIR/backend/container/$file"
done
for rel in \
  frontend/src/components/WorkspaceDialogs.vue \
  frontend/src/composables/useWorkspace.ts \
  frontend/src/styles.css \
  frontend/src/__tests__/alarmReviewDialog.test.ts \
  frontend/src/__tests__/alarmFlowSimplification.test.ts
do
  [ -f "$APP_DIR/$rel" ] && $SUDO cp -a "$APP_DIR/$rel" "$BACKUP_DIR/$rel"
done
$SUDO cp -a "$APP_DIR/frontend/dist/index.html" "$BACKUP_DIR/frontend/dist/index.html"
$SUDO cp -a "$APP_DIR/frontend/dist/assets" "$BACKUP_DIR/frontend/dist/assets"
echo "Rollback backup: $BACKUP_DIR"

echo "== 3. Apply backend annotation persistence and metadata API =="
BACKEND_CHANGED=1
for file in server.mjs store.mjs alarm-evidence.mjs; do
  $SUDO cp -a "$PKG_DIR/backend/src/$file" "$APP_DIR/backend/src/$file"
  run_docker cp "$PKG_DIR/backend/src/$file" "$backend_ctn:/app/src/$file"
done
run_docker exec "$backend_ctn" sh -lc 'node --check /app/src/server.mjs && node --check /app/src/store.mjs && node --check /app/src/alarm-evidence.mjs'
run_docker restart "$backend_ctn" >/dev/null
wait_for_http backend http://127.0.0.1:8080/api/health 60 2

echo "== 4. Backfill recoverable legacy annotations =="
# Variables expand inside the container shell.
# shellcheck disable=SC2016
run_docker exec -i "$mysql_ctn" sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
  < "$PKG_DIR/db/backfill-alarm-evidence-annotations.sql"
# Variables expand inside the container shell.
# shellcheck disable=SC2016
backfilled_count="$(run_docker exec "$mysql_ctn" sh -lc 'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM rw_alarm_evidence WHERE COALESCE(JSON_LENGTH(JSON_EXTRACT(annotation_data, '\''$.boxes'\'')), 0) > 0"')"
echo "evidence_with_annotations=$backfilled_count"

echo "== 5. Apply compact frontend source and assets =="
FRONTEND_CHANGED=1
for rel in \
  frontend/src/components/WorkspaceDialogs.vue \
  frontend/src/composables/useWorkspace.ts \
  frontend/src/styles.css \
  frontend/src/__tests__/alarmReviewDialog.test.ts \
  frontend/src/__tests__/alarmFlowSimplification.test.ts
do
  $SUDO cp -a "$PKG_DIR/$rel" "$APP_DIR/$rel"
done
$SUDO rm -rf "$APP_DIR/frontend/dist/assets"
$SUDO cp -a "$PKG_DIR/frontend/dist/assets" "$APP_DIR/frontend/dist/assets"
$SUDO cp -a "$PKG_DIR/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"
run_docker exec "$frontend_ctn" sh -lc 'rm -rf /usr/share/nginx/html/assets'
run_docker cp "$PKG_DIR/frontend/dist/assets" "$frontend_ctn:/usr/share/nginx/html/assets"
run_docker cp "$PKG_DIR/frontend/dist/index.html" "$frontend_ctn:/usr/share/nginx/html/index.html"
run_docker restart "$frontend_ctn" >/dev/null
wait_for_http frontend http://127.0.0.1:8081/ 60 2

echo "== 6. Verify =="
curl -fsS http://127.0.0.1:8080/api/health
curl -fsS http://127.0.0.1:8081/ >/dev/null
# Variables expand inside the container shell.
# shellcheck disable=SC2016
run_docker exec "$mysql_ctn" sh -lc 'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='\''rw_alarm_evidence'\'' AND COLUMN_NAME='\''annotation_data'\''"' | grep -qx 1
run_docker exec "$backend_ctn" sh -lc '
  grep -q alarmEvidenceMetadataMatch /app/src/server.mjs
  grep -q annotation_data /app/src/store.mjs
  grep -q "annotations: evidenceAnnotations(payload)" /app/src/alarm-evidence.mjs
'
main_js="$(sed -n 's#.*src="/\(assets/index-[^"]*\.js\)".*#\1#p' "$PKG_DIR/frontend/dist/index.html" | head -1)"
main_css="$(sed -n 's#.*href="/\(assets/index-[^"]*\.css\)".*#\1#p' "$PKG_DIR/frontend/dist/index.html" | head -1)"
[ -n "$main_js" ] || fail "main frontend JS was not found"
[ -n "$main_css" ] || fail "main frontend CSS was not found"
run_docker exec "$frontend_ctn" sh -lc "grep -q 'evidence/metadata' '/usr/share/nginx/html/$main_js'"
run_docker exec "$frontend_ctn" sh -lc "grep -q 'alarm-review-detail-grid' '/usr/share/nginx/html/$main_css'"

echo "== 7. Keep only the latest two rollback backups for this increment =="
mapfile -t old_backups < <(find "$APP_DIR/backups" -maxdepth 1 -mindepth 1 -type d -name 'alarm-evidence-annotations-layout-v2-20260715-*' -printf '%T@ %p\n' | sort -rn | awk 'NR>2 {$1=""; sub(/^ /, ""); print}')
for old_backup in "${old_backups[@]:-}"; do
  [ -n "$old_backup" ] && $SUDO rm -rf -- "$old_backup"
done

trap - ERR
echo "VERIFY OK"
echo "DONE"
echo "Rollback backup: $BACKUP_DIR"
echo "Legacy evidence annotations recovered: $backfilled_count"
