#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
INSTALL_DIR="${INSTALL_DIR:-/opt/river-watch/training-capture}"
CONFIG_FILE="${CONFIG_FILE:-/etc/river-watch/training-capture.conf}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/home/ai-river/training-captures}"
ENV_DIR="${ENV_DIR:-/etc/river-watch}"
OWNER="${OWNER:-ai-river}"
GROUP="${GROUP:-ai-river}"
MAX_BYTES="${MAX_BYTES:-21474836480}"
MIN_FREE_BYTES="${MIN_FREE_BYTES:-10737418240}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-deploy-backend-1}"
FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-deploy-frontend-1}"
UNIT_DIR="/etc/systemd/system"
STATE_DIR="/var/lib/river-watch-training-capture"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/capture-evidence-link-fix-20260722-$TS"
MUTATION_STARTED=0

GROUP_UNITS=(
  river-ai-group@river-a.service
  river-ai-group@river-b.service
  river-ai-group@structure.service
)

fail() { echo "ERROR: $*" >&2; return 1; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }
container_hash() { docker exec "$1" sha256sum "$2" | awk '{print $1}'; }

require_hash() {
  local label="$1" path="$2" expected="$3" actual
  [ -f "$path" ] || fail "$label missing: $path"
  actual="$(file_hash "$path")"
  [ "$actual" = "$expected" ] || fail "$label baseline drift: actual=$actual expected=$expected"
  echo "OK $label $actual"
}

require_container_hash() {
  local label="$1" container="$2" path="$3" expected="$4" actual
  actual="$(container_hash "$container" "$path")"
  [ "$actual" = "$expected" ] || fail "$label baseline drift: actual=$actual expected=$expected"
  echo "OK $label $actual"
}

wait_http() {
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

wait_group() {
  local group_id="$1" expected_sessions="$2" unit="river-ai-group@${1}.service"
  local started ready_count
  started="$(date '+%F %T')"
  systemctl restart "$unit"
  for _ in $(seq 1 720); do
    if systemctl is-active --quiet "$unit"; then
      ready_count="$(journalctl -u "$unit" --since "$started" --no-pager 2>/dev/null \
        | grep "session ready ${group_id}-" | grep -c 'MIGraphXExecutionProvider' || true)"
      if [ "$ready_count" -ge "$expected_sessions" ]; then
        echo "ready $group_id sessions=$expected_sessions"
        return 0
      fi
    fi
    sleep 1
  done
  journalctl -u "$unit" --since "$started" --no-pager | tail -120 || true
  fail "$group_id did not warm $expected_sessions GPU sessions"
}

rollback_on_error() {
  local rc=$? line="${BASH_LINENO[0]:-unknown}"
  trap - ERR
  if [ "$MUTATION_STARTED" -eq 1 ]; then
    echo "ERROR: deployment failed near line $line (rc=$rc); automatic rollback" >&2
    APP_DIR="$APP_DIR" OPT_DIR="$OPT_DIR" INSTALL_DIR="$INSTALL_DIR" \
      CONFIG_FILE="$CONFIG_FILE" OUTPUT_ROOT="$OUTPUT_ROOT" \
      BACKEND_CONTAINER="$BACKEND_CONTAINER" FRONTEND_CONTAINER="$FRONTEND_CONTAINER" \
      bash "$PACKAGE_DIR/scripts/rollback-capture-evidence-link-fix-20260722.sh" "$BACKUP_DIR" || true
  fi
  exit "$rc"
}
trap rollback_on_error ERR

echo "== River Watch capture and alarm-evidence camera binding increment =="
[ "$(id -u)" -eq 0 ] || fail "run this script with sudo"
case "$APP_DIR" in /home/ai-river/*) ;; *) fail "unsafe APP_DIR: $APP_DIR" ;; esac
[ "$OPT_DIR" = "/opt/river-watch" ] || fail "unsafe OPT_DIR: $OPT_DIR"
for command_name in python3 ffmpeg ffprobe systemctl sha256sum docker curl; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done
docker inspect "$BACKEND_CONTAINER" >/dev/null 2>&1 || fail "backend container not found"
docker inspect "$FRONTEND_CONTAINER" >/dev/null 2>&1 || fail "frontend container not found"
for unit in "${GROUP_UNITS[@]}"; do
  systemctl is-active --quiet "$unit" || fail "$unit is not active before deployment"
done

echo "== 1. Verify package and exact production baselines =="
(cd "$PACKAGE_DIR" && sha256sum -c SHA256SUMS)
require_hash "host group_pool_worker.py" "$APP_DIR/ai-pipeline/workers/group_pool_worker.py" \
  "66c22821e6aadc115ca300fceed5d6d68107c7994dc2d4ad3a6eb6f63fad2d01"
require_hash "runtime group_pool_worker.py" "$OPT_DIR/ai-pipeline/workers/group_pool_worker.py" \
  "66c22821e6aadc115ca300fceed5d6d68107c7994dc2d4ad3a6eb6f63fad2d01"
require_hash "host backend server.mjs" "$APP_DIR/backend/src/server.mjs" \
  "16177ade503de4f094a90aa74a7a540c6fdc57da2068be784ba5ab6a09eae5cd"
require_hash "host alarm-evidence.mjs" "$APP_DIR/backend/src/alarm-evidence.mjs" \
  "300358dc4956c26ed0b02bb01eb55b27968484127df81512f79bc9601004a6fb"
require_container_hash "runtime backend server.mjs" "$BACKEND_CONTAINER" "/app/src/server.mjs" \
  "16177ade503de4f094a90aa74a7a540c6fdc57da2068be784ba5ab6a09eae5cd"
require_container_hash "runtime alarm-evidence.mjs" "$BACKEND_CONTAINER" "/app/src/alarm-evidence.mjs" \
  "300358dc4956c26ed0b02bb01eb55b27968484127df81512f79bc9601004a6fb"
require_hash "frontend useWorkspace.ts" "$APP_DIR/frontend/src/composables/useWorkspace.ts" \
  "9225deb785c46bd0674eca6f050bf8a1c5af0b4f27dea862975f504c32e20e1d"
curl -fsS -m 8 http://127.0.0.1:8080/api/health >/dev/null
curl -fsS -m 8 http://127.0.0.1:8081/ >/dev/null

echo "== 2. Syntax-check candidates before mutation =="
docker cp "$PACKAGE_DIR/backend/src/server.mjs" "$BACKEND_CONTAINER:/tmp/river-watch-server-candidate.mjs"
docker cp "$PACKAGE_DIR/backend/src/alarm-evidence.mjs" "$BACKEND_CONTAINER:/tmp/river-watch-evidence-candidate.mjs"
docker exec "$BACKEND_CONTAINER" node --check /tmp/river-watch-server-candidate.mjs
docker exec "$BACKEND_CONTAINER" node --check /tmp/river-watch-evidence-candidate.mjs
docker exec "$BACKEND_CONTAINER" rm -f /tmp/river-watch-server-candidate.mjs /tmp/river-watch-evidence-candidate.mjs
PYTHONDONTWRITEBYTECODE=1 "$OPT_DIR/ai-pipeline/.venv/bin/python" - <<PY
from pathlib import Path
compile(Path("$PACKAGE_DIR/ai-pipeline/workers/group_pool_worker.py").read_text(encoding="utf-8"), "group_pool_worker.py", "exec")
PY

echo "== 3. Backup every changed file and current service state =="
mkdir -p \
  "$BACKUP_DIR/host/ai-app" "$BACKUP_DIR/host/ai-runtime" \
  "$BACKUP_DIR/host/backend" "$BACKUP_DIR/runtime/backend" \
  "$BACKUP_DIR/host/frontend" "$BACKUP_DIR/runtime/frontend-html" \
  "$BACKUP_DIR/capture/install" "$BACKUP_DIR/capture/etc" "$BACKUP_DIR/capture/systemd" \
  "$STATE_DIR"
cp -a "$APP_DIR/ai-pipeline/workers/group_pool_worker.py" "$BACKUP_DIR/host/ai-app/"
cp -a "$OPT_DIR/ai-pipeline/workers/group_pool_worker.py" "$BACKUP_DIR/host/ai-runtime/"
cp -a "$APP_DIR/backend/src/server.mjs" "$APP_DIR/backend/src/alarm-evidence.mjs" "$BACKUP_DIR/host/backend/"
docker cp "$BACKEND_CONTAINER:/app/src/server.mjs" "$BACKUP_DIR/runtime/backend/server.mjs"
docker cp "$BACKEND_CONTAINER:/app/src/alarm-evidence.mjs" "$BACKUP_DIR/runtime/backend/alarm-evidence.mjs"
cp -a "$APP_DIR/frontend/src/composables/useWorkspace.ts" "$BACKUP_DIR/host/frontend/useWorkspace.ts"
cp -a "$APP_DIR/frontend/dist" "$BACKUP_DIR/host/frontend/dist"
docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/." "$BACKUP_DIR/runtime/frontend-html"
for unit in "${GROUP_UNITS[@]}"; do
  printf '%s\t%s\t%s\n' "$unit" \
    "$(systemctl is-enabled "$unit" 2>/dev/null || true)" \
    "$(systemctl is-active "$unit" 2>/dev/null || true)" >> "$BACKUP_DIR/group-state.tsv"
done
printf 'timer_enabled=%s\n' "$(systemctl is-enabled river-training-capture.timer 2>/dev/null || true)" \
  > "$BACKUP_DIR/capture-state.env"
printf 'timer_active=%s\n' "$(systemctl is-active river-training-capture.timer 2>/dev/null || true)" \
  >> "$BACKUP_DIR/capture-state.env"
if [ -d "$INSTALL_DIR" ]; then cp -a "$INSTALL_DIR" "$BACKUP_DIR/capture/install/training-capture"; fi
if [ -f "$CONFIG_FILE" ]; then cp -a "$CONFIG_FILE" "$BACKUP_DIR/capture/etc/training-capture.conf"; fi
for unit_name in river-training-capture.service river-training-capture.timer; do
  if [ -f "$UNIT_DIR/$unit_name" ]; then cp -a "$UNIT_DIR/$unit_name" "$BACKUP_DIR/capture/systemd/$unit_name"; fi
done
printf '%s\n' "$BACKUP_DIR" > "$STATE_DIR/latest-backup"
sha256sum "$BACKUP_DIR/host/ai-app/group_pool_worker.py" \
  "$BACKUP_DIR/host/backend/server.mjs" "$BACKUP_DIR/host/backend/alarm-evidence.mjs" \
  "$BACKUP_DIR/host/frontend/useWorkspace.ts" > "$BACKUP_DIR/SHA256SUMS"

MUTATION_STARTED=1

echo "== 4. Install exact-frame AI and camera-bound backend =="
install -m 0644 -o "$OWNER" -g "$GROUP" "$PACKAGE_DIR/ai-pipeline/workers/group_pool_worker.py" \
  "$APP_DIR/ai-pipeline/workers/group_pool_worker.py"
install -m 0644 -o root -g root "$PACKAGE_DIR/ai-pipeline/workers/group_pool_worker.py" \
  "$OPT_DIR/ai-pipeline/workers/group_pool_worker.py"
rm -rf "$OPT_DIR/ai-pipeline/workers/__pycache__"
install -m 0644 -o "$OWNER" -g "$GROUP" "$PACKAGE_DIR/backend/src/server.mjs" \
  "$APP_DIR/backend/src/server.mjs"
install -m 0644 -o "$OWNER" -g "$GROUP" "$PACKAGE_DIR/backend/src/alarm-evidence.mjs" \
  "$APP_DIR/backend/src/alarm-evidence.mjs"
docker cp "$PACKAGE_DIR/backend/src/server.mjs" "$BACKEND_CONTAINER:/app/src/server.mjs"
docker cp "$PACKAGE_DIR/backend/src/alarm-evidence.mjs" "$BACKEND_CONTAINER:/app/src/alarm-evidence.mjs"
docker restart "$BACKEND_CONTAINER" >/dev/null
wait_http backend http://127.0.0.1:8080/api/health

echo "== 5. Restart only the verified group topology =="
wait_group structure 1
wait_group river-a 2
wait_group river-b 2

echo "== 6. Install frontend source and prebuilt assets =="
install -m 0644 -o "$OWNER" -g "$GROUP" "$PACKAGE_DIR/frontend/src/composables/useWorkspace.ts" \
  "$APP_DIR/frontend/src/composables/useWorkspace.ts"
install -m 0644 -o "$OWNER" -g "$GROUP" "$PACKAGE_DIR/frontend/src/__tests__/alarmReviewDialog.test.ts" \
  "$APP_DIR/frontend/src/__tests__/alarmReviewDialog.test.ts"
install -d -m 0755 -o "$OWNER" -g "$GROUP" "$APP_DIR/frontend/dist"
rm -rf "$APP_DIR/frontend/dist/assets"
install -m 0644 -o "$OWNER" -g "$GROUP" "$PACKAGE_DIR/frontend/dist/index.html" \
  "$APP_DIR/frontend/dist/index.html"
cp -a "$PACKAGE_DIR/frontend/dist/assets" "$APP_DIR/frontend/dist/assets"
chown -R "$OWNER:$GROUP" "$APP_DIR/frontend/dist/assets"
docker exec "$FRONTEND_CONTAINER" sh -lc 'rm -rf /usr/share/nginx/html/assets /usr/share/nginx/html/index.html'
docker cp "$PACKAGE_DIR/frontend/dist/index.html" "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html"
docker cp "$PACKAGE_DIR/frontend/dist/assets" "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets"
docker restart "$FRONTEND_CONTAINER" >/dev/null
wait_http frontend http://127.0.0.1:8081/

echo "== 7. Replace old capture program with a clean 10-day half-hour run =="
systemctl disable --now river-training-capture.timer 2>/dev/null || true
systemctl stop river-training-capture.service 2>/dev/null || true
rm -rf -- "$INSTALL_DIR"
rm -f -- "$CONFIG_FILE" "$UNIT_DIR/river-training-capture.service" "$UNIT_DIR/river-training-capture.timer"
systemctl daemon-reload
echo "previous captures are preserved under $OUTPUT_ROOT"
install -d -m 0755 "$INSTALL_DIR" "$OUTPUT_ROOT" "$(dirname "$CONFIG_FILE")"
install -m 0755 "$PACKAGE_DIR/training_capture/training_capture.py" "$INSTALL_DIR/training_capture.py"
install -m 0644 "$PACKAGE_DIR/systemd/river-training-capture.service" "$UNIT_DIR/river-training-capture.service"
install -m 0644 "$PACKAGE_DIR/systemd/river-training-capture.timer" "$UNIT_DIR/river-training-capture.timer"
available_bytes="$(df -PB1 "$OUTPUT_ROOT" | awk 'NR==2 {print $4}')"
[ -n "$available_bytes" ] && [ "$available_bytes" -ge "$MIN_FREE_BYTES" ] \
  || fail "less than the configured minimum free space is available"
start_epoch="$(date +%s)"
end_epoch="$((start_epoch + 10 * 24 * 3600))"
run_id="river-training-10d-$TS"
run_dir="$OUTPUT_ROOT/$run_id"
install -d -m 0755 "$run_dir"
cat > "$CONFIG_FILE" <<EOF
RUN_ID=$run_id
START_EPOCH=$start_epoch
END_EPOCH=$end_epoch
OUTPUT_ROOT=$OUTPUT_ROOT
RUN_DIR=$run_dir
ENV_DIR=$ENV_DIR
MAX_SLOTS=480
INTERVAL_SEC=1800
MAX_BYTES=$MAX_BYTES
MIN_FREE_BYTES=$MIN_FREE_BYTES
OWNER=$OWNER
GROUP=$GROUP
EOF
chmod 0640 "$CONFIG_FILE"
chown "$OWNER:$GROUP" "$OUTPUT_ROOT" "$run_dir" 2>/dev/null || true
python3 -m py_compile "$INSTALL_DIR/training_capture.py"
systemctl daemon-reload
systemctl enable --now river-training-capture.timer
systemctl start --no-block river-training-capture.service

echo "== 8. Verify deployment =="
APP_DIR="$APP_DIR" OPT_DIR="$OPT_DIR" INSTALL_DIR="$INSTALL_DIR" CONFIG_FILE="$CONFIG_FILE" \
  OUTPUT_ROOT="$OUTPUT_ROOT" BACKEND_CONTAINER="$BACKEND_CONTAINER" FRONTEND_CONTAINER="$FRONTEND_CONTAINER" \
  bash "$PACKAGE_DIR/scripts/verify-capture-evidence-link-fix-20260722.sh"

echo "== 9. Retain only the latest two rollback sets =="
mapfile -t old_backups < <(find "$APP_DIR/backups" -maxdepth 1 -mindepth 1 -type d \
  -name 'capture-evidence-link-fix-20260722-*' -printf '%T@ %p\n' \
  | sort -rn | awk 'NR>2 {$1=""; sub(/^ /, ""); print}')
for old in "${old_backups[@]:-}"; do [ -n "$old" ] && rm -rf -- "$old"; done

trap - ERR
MUTATION_STARTED=0
echo "VERIFY OK"
echo "DONE"
echo "run_id=$run_id"
echo "run_dir=$run_dir"
echo "rollback_backup=$BACKUP_DIR"
echo "The first capture is running asynchronously. Existing captures were not deleted."
