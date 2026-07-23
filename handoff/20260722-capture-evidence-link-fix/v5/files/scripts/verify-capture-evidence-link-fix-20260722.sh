#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
INSTALL_DIR="${INSTALL_DIR:-/opt/river-watch/training-capture}"
CONFIG_FILE="${CONFIG_FILE:-/etc/river-watch/training-capture.conf}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/home/ai-river/training-captures}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-deploy-backend-1}"
FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-deploy-frontend-1}"

echo "== Verify service health =="
curl -fsS -m 8 http://127.0.0.1:8080/api/health
curl -fsS -m 8 http://127.0.0.1:8081/ >/dev/null
for unit in river-ai-group@river-a.service river-ai-group@river-b.service river-ai-group@structure.service; do
  systemctl is-active --quiet "$unit" || { echo "ERROR: $unit is not active" >&2; exit 1; }
done
systemctl is-active --quiet river-training-capture.timer

echo "== Verify capture policy =="
grep -qx 'MAX_SLOTS=480' "$CONFIG_FILE"
grep -qx 'INTERVAL_SEC=1800' "$CONFIG_FILE"
grep -q 'OnUnitActiveSec=30min' /etc/systemd/system/river-training-capture.timer
[ -x "$INSTALL_DIR/training_capture.py" ]
run_dir="$(awk -F= '$1=="RUN_DIR" {print substr($0, index($0,"=")+1)}' "$CONFIG_FILE")"
[ -n "$run_dir" ] && [ -d "$run_dir" ]
case "$run_dir" in "$OUTPUT_ROOT"/*) ;; *) echo "ERROR: unsafe run directory" >&2; exit 1 ;; esac

echo "== Verify exact-frame and camera-binding markers =="
grep -q 'evidenceFrame' "$OPT_DIR/ai-pipeline/workers/group_pool_worker.py"
grep -q 'decodeEmbeddedEvidenceFrame' "$APP_DIR/backend/src/alarm-evidence.mjs"
grep -q 'assertStoredEvidenceMatchesAlarm' "$APP_DIR/backend/src/server.mjs"
grep -q 'evidenceMatchesSelectedAlarm' "$APP_DIR/frontend/src/composables/useWorkspace.ts"
docker exec "$BACKEND_CONTAINER" grep -q 'assertStoredEvidenceMatchesAlarm' /app/src/server.mjs
docker exec "$BACKEND_CONTAINER" grep -q 'decodeEmbeddedEvidenceFrame' /app/src/alarm-evidence.mjs
docker exec "$FRONTEND_CONTAINER" sh -lc \
  "grep -R -q 'evidenceMatchesSelectedAlarm\|已阻止显示' /usr/share/nginx/html/assets"

echo "== Verify production OpenCV exact-frame encoder =="
PYTHONPATH="$OPT_DIR/ai-pipeline/workers" PYTHONDONTWRITEBYTECODE=1 \
  "$OPT_DIR/ai-pipeline/.venv/bin/python" - <<'PY'
import base64
import numpy as np
from group_pool_worker import BackendClient

encoded = BackendClient.encode_evidence_frame("CH02", np.zeros((8, 8, 3), dtype=np.uint8), 1)
data = base64.b64decode(encoded["dataBase64"])
assert encoded["cameraId"] == "CH02"
assert data.startswith(b"\xff\xd8") and data.endswith(b"\xff\xd9")
assert b"RIVERWATCH-EVIDENCE-V1|CH02" in data
print("exact-frame encoder OK")
PY

echo "VERIFY OK"
echo "capture_run_dir=$run_dir"
