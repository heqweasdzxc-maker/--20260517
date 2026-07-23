#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_DIR="${1:?usage: rollback-capture-evidence-link-fix-20260722.sh BACKUP_DIR}"
APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
INSTALL_DIR="${INSTALL_DIR:-/opt/river-watch/training-capture}"
CONFIG_FILE="${CONFIG_FILE:-/etc/river-watch/training-capture.conf}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-deploy-backend-1}"
FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-deploy-frontend-1}"
UNIT_DIR="/etc/systemd/system"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }
[ -d "$BACKUP_DIR" ] || { echo "ERROR: backup not found: $BACKUP_DIR" >&2; exit 1; }
case "$BACKUP_DIR" in "$APP_DIR"/backups/capture-evidence-link-fix-20260722-*) ;; *)
  echo "ERROR: invalid rollback directory" >&2; exit 1 ;;
esac

echo "== Restore capture program and timer =="
systemctl disable --now river-training-capture.timer 2>/dev/null || true
systemctl stop river-training-capture.service 2>/dev/null || true
rm -rf -- "$INSTALL_DIR"
rm -f -- "$CONFIG_FILE" "$UNIT_DIR/river-training-capture.service" "$UNIT_DIR/river-training-capture.timer"
if [ -d "$BACKUP_DIR/capture/install/training-capture" ]; then
  cp -a "$BACKUP_DIR/capture/install/training-capture" "$INSTALL_DIR"
fi
if [ -f "$BACKUP_DIR/capture/etc/training-capture.conf" ]; then
  install -D -m 0640 "$BACKUP_DIR/capture/etc/training-capture.conf" "$CONFIG_FILE"
fi
for unit_name in river-training-capture.service river-training-capture.timer; do
  if [ -f "$BACKUP_DIR/capture/systemd/$unit_name" ]; then
    cp -a "$BACKUP_DIR/capture/systemd/$unit_name" "$UNIT_DIR/$unit_name"
  fi
done
systemctl daemon-reload
if grep -q '^timer_enabled=enabled$' "$BACKUP_DIR/capture-state.env" 2>/dev/null; then
  systemctl enable river-training-capture.timer >/dev/null 2>&1 || true
fi
if grep -q '^timer_active=active$' "$BACKUP_DIR/capture-state.env" 2>/dev/null; then
  systemctl start river-training-capture.timer || true
fi

echo "== Restore AI, backend and frontend =="
install -m 0644 -o ai-river -g ai-river "$BACKUP_DIR/host/ai-app/group_pool_worker.py" \
  "$APP_DIR/ai-pipeline/workers/group_pool_worker.py"
install -m 0644 -o root -g root "$BACKUP_DIR/host/ai-runtime/group_pool_worker.py" \
  "$OPT_DIR/ai-pipeline/workers/group_pool_worker.py"
install -m 0644 -o ai-river -g ai-river "$BACKUP_DIR/host/backend/server.mjs" \
  "$APP_DIR/backend/src/server.mjs"
install -m 0644 -o ai-river -g ai-river "$BACKUP_DIR/host/backend/alarm-evidence.mjs" \
  "$APP_DIR/backend/src/alarm-evidence.mjs"
docker cp "$BACKUP_DIR/runtime/backend/server.mjs" "$BACKEND_CONTAINER:/app/src/server.mjs"
docker cp "$BACKUP_DIR/runtime/backend/alarm-evidence.mjs" "$BACKEND_CONTAINER:/app/src/alarm-evidence.mjs"
install -m 0644 -o ai-river -g ai-river "$BACKUP_DIR/host/frontend/useWorkspace.ts" \
  "$APP_DIR/frontend/src/composables/useWorkspace.ts"
rm -rf "$APP_DIR/frontend/dist"
cp -a "$BACKUP_DIR/host/frontend/dist" "$APP_DIR/frontend/dist"
docker exec "$FRONTEND_CONTAINER" sh -lc 'rm -rf /usr/share/nginx/html/*'
docker cp "$BACKUP_DIR/runtime/frontend-html/." "$FRONTEND_CONTAINER:/usr/share/nginx/html"
docker restart "$BACKEND_CONTAINER" "$FRONTEND_CONTAINER" >/dev/null || true

while IFS=$'\t' read -r unit enabled active; do
  [ -n "$unit" ] || continue
  if [ "$enabled" = "enabled" ]; then systemctl enable "$unit" >/dev/null 2>&1 || true; fi
  if [ "$active" = "active" ]; then systemctl restart "$unit" || true; else systemctl stop "$unit" || true; fi
done < "$BACKUP_DIR/group-state.tsv"

echo "ROLLBACK DONE"
echo "Existing capture images under the output root were preserved."
