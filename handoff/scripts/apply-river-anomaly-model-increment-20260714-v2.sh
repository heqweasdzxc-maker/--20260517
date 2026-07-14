#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-deploy-mysql-1}"
MODEL_NAME="river-anomaly-yolo11n-12cls-20260714.onnx"
PT_NAME="river-anomaly-yolo11n-12cls-20260714.pt"
LABELS="willow_fluff,leaf,aquatic_weed,water_discoloration,garbage_bag,plastic_bottle,water_bird,plastic_foam,water_foam,person_in_water,debris,wall_crack"
MODEL_SHA="31ce290cdea402591c2d3c458c9d8a850a07af5006413492800c5e84f416ca63"
PT_SHA="7bb56918d36efaa99c4f2fb1fa327d5ef043351096337f11124b1aeadcebadd9"
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/river-anomaly-model-20260714-v2-$STAMP"
RECEIPT="$APP_DIR/logs/ops/river-anomaly-model-20260714-v2-$STAMP.md"
MUTATED=0
DB_UPDATED=0
BATCH_RIVER_WAS_ACTIVE=0
STRUCTURE_UNIT=""

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

restore_optional() {
  local target="$1"
  local saved="$2"
  if [[ -f "$saved.was-absent" ]]; then
    rm -f -- "$target"
  elif [[ -f "$saved" ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$saved" "$target"
  fi
}

wait_model_unit() {
  local unit="$1"
  local label="$2"
  local since="$3"
  local i logs
  for i in $(seq 1 60); do
    if systemctl is-active --quiet "$unit"; then
      logs="$(journalctl -u "$unit" --since "$since" --no-pager 2>&1 || true)"
      if grep -Fq "$MODEL_NAME" <<<"$logs"; then
        if grep -Eqi 'InvalidArgument|Load model.*fail|onnxruntime.*error|GPU inference required|MIGraphX.*(fail|error)|Traceback' <<<"$logs"; then
          printf '%s\n' "$logs" | tail -120
          return 1
        fi
        if ! grep -Fq 'MIGraphXExecutionProvider' <<<"$logs"; then
          log "$label loaded the model but GPU provider was not confirmed"
          printf '%s\n' "$logs" | tail -120
          return 1
        fi
        log "$label active with $MODEL_NAME on MIGraphXExecutionProvider"
        return 0
      fi
    fi
    sleep 2
  done
  journalctl -u "$unit" --since "$since" --no-pager | tail -160 || true
  return 1
}

restart_river_services() {
  systemctl restart river-ai-group@river-a.service || true
  systemctl restart river-ai-group@river-b.service || true
  if [[ "$BATCH_RIVER_WAS_ACTIVE" -eq 1 ]]; then
    systemctl restart river-ai-batch@river.service || true
  fi
}

rollback() {
  local rc=$?
  if [[ "$MUTATED" -eq 1 ]]; then
    log "Automatic rollback started"
    cp -a "$BACKUP_DIR/app-detect_core.py" "$APP_DIR/ai-pipeline/workers/detect_core.py"
    cp -a "$BACKUP_DIR/opt-detect_core.py" "$OPT_DIR/ai-pipeline/workers/detect_core.py"
    for ch in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
      cp -a "$BACKUP_DIR/env/ai-worker-$ch.env" "/etc/river-watch/ai-worker-$ch.env"
    done
    if [[ -f "$BACKUP_DIR/channels.yaml" ]]; then
      cp -a "$BACKUP_DIR/channels.yaml" "$APP_DIR/ai-pipeline/config/channels.yaml"
    fi
    restore_optional "$APP_DIR/models/$MODEL_NAME" "$BACKUP_DIR/app-models/$MODEL_NAME"
    restore_optional "$APP_DIR/models/$PT_NAME" "$BACKUP_DIR/app-models/$PT_NAME"
    restore_optional "$OPT_DIR/models/$MODEL_NAME" "$BACKUP_DIR/opt-models/$MODEL_NAME"
    restore_optional "$OPT_DIR/models/$PT_NAME" "$BACKUP_DIR/opt-models/$PT_NAME"
    for suffix in model-info.yaml classes-en.txt classes-zh.txt results.csv; do
      restore_optional "$APP_DIR/models/river-anomaly-yolo11n-12cls-20260714.$suffix" \
        "$BACKUP_DIR/app-models/river-anomaly-yolo11n-12cls-20260714.$suffix"
    done
    if [[ "$DB_UPDATED" -eq 1 && -s "$BACKUP_DIR/rw_camera-river.sql" ]]; then
      docker exec -i "$MYSQL_CONTAINER" sh -lc \
        'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
        < "$BACKUP_DIR/rw_camera-river.sql" || true
    fi
    systemctl daemon-reload || true
    restart_river_services
    log "Rollback restored: $BACKUP_DIR"
  fi
  exit "$rc"
}

trap rollback ERR

log "River Watch river anomaly model increment"
log "PACKAGE_DIR=$PACKAGE_DIR"
log "APP_DIR=$APP_DIR"

[[ -d "$APP_DIR" ]] || fail "app directory not found: $APP_DIR"
[[ -x "$OPT_DIR/ai-pipeline/.venv/bin/python" ]] || fail "AI Python runtime not found"
[[ -f "$APP_DIR/ai-pipeline/workers/detect_core.py" ]] || fail "app detect_core.py not found"
[[ -f "$OPT_DIR/ai-pipeline/workers/detect_core.py" ]] || fail "runtime detect_core.py not found"
docker inspect "$MYSQL_CONTAINER" >/dev/null 2>&1 || fail "MySQL container not found: $MYSQL_CONTAINER"
systemctl is-active --quiet river-ai-group@river-a.service || fail "river-a is not active before deployment"
systemctl is-active --quiet river-ai-group@river-b.service || fail "river-b is not active before deployment"
systemctl is-active --quiet river-ai-batch@river.service || fail "river batch is not active before deployment"
BATCH_RIVER_WAS_ACTIVE=1
if systemctl is-active --quiet river-ai-batch@structure.service; then
  STRUCTURE_UNIT="river-ai-batch@structure.service"
elif systemctl is-active --quiet river-ai-group@structure.service; then
  STRUCTURE_UNIT="river-ai-group@structure.service"
else
  fail "neither batch nor group structure inference is active before deployment"
fi
log "Detected topology: river group + batch; structure=$STRUCTURE_UNIT"

for ch in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
  env_file="/etc/river-watch/ai-worker-$ch.env"
  [[ -f "$env_file" ]] || fail "missing worker env: $env_file"
  grep -Eq '^ORT_PROVIDERS=.*MIGraphXExecutionProvider' "$env_file" || \
    fail "$env_file is not configured for MIGraphX GPU inference"
done

log "1. Verify package checksums"
(cd "$PACKAGE_DIR" && sha256sum -c SHA256SUMS)
[[ "$(sha_of "$PACKAGE_DIR/models/$MODEL_NAME")" == "$MODEL_SHA" ]] || fail "ONNX hash mismatch"
[[ "$(sha_of "$PACKAGE_DIR/models/$PT_NAME")" == "$PT_SHA" ]] || fail "PT hash mismatch"

log "2. Validate ONNX model with the installed server runtime"
MODEL_PATH="$PACKAGE_DIR/models/$MODEL_NAME" \
  "$OPT_DIR/ai-pipeline/.venv/bin/python" - <<'PY'
import os
import numpy as np
import onnxruntime as ort

path = os.environ["MODEL_PATH"]
available = ort.get_available_providers()
provider = "CPUExecutionProvider" if "CPUExecutionProvider" in available else available[0]
session = ort.InferenceSession(path, providers=[provider])
model_input = session.get_inputs()[0]
shape = [dim if isinstance(dim, int) and dim > 0 else fallback for dim, fallback in zip(model_input.shape, [1, 3, 640, 640])]
output = session.run(None, {model_input.name: np.zeros(shape, dtype=np.float32)})[0]
if output.ndim != 3 or (16 not in output.shape[1:]):
    raise SystemExit(f"unexpected output shape {output.shape}; expected YOLO detect 4+12 classes")
print(f"ONNX preflight OK provider={provider} input={shape} output={tuple(output.shape)}")
PY

log "3. Backup runtime, env, model and camera metadata"
mkdir -p "$BACKUP_DIR/env" "$BACKUP_DIR/app-models" "$BACKUP_DIR/opt-models" \
  "$APP_DIR/models" "$OPT_DIR/models" "$(dirname "$RECEIPT")"
cp -a "$APP_DIR/ai-pipeline/workers/detect_core.py" "$BACKUP_DIR/app-detect_core.py"
cp -a "$OPT_DIR/ai-pipeline/workers/detect_core.py" "$BACKUP_DIR/opt-detect_core.py"
[[ -f "$APP_DIR/ai-pipeline/config/channels.yaml" ]] && \
  cp -a "$APP_DIR/ai-pipeline/config/channels.yaml" "$BACKUP_DIR/channels.yaml"
for ch in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
  cp -a "/etc/river-watch/ai-worker-$ch.env" "$BACKUP_DIR/env/ai-worker-$ch.env"
done

for spec in \
  "$APP_DIR/models/$MODEL_NAME:$BACKUP_DIR/app-models/$MODEL_NAME" \
  "$APP_DIR/models/$PT_NAME:$BACKUP_DIR/app-models/$PT_NAME" \
  "$OPT_DIR/models/$MODEL_NAME:$BACKUP_DIR/opt-models/$MODEL_NAME" \
  "$OPT_DIR/models/$PT_NAME:$BACKUP_DIR/opt-models/$PT_NAME"
do
  target="${spec%%:*}"
  saved="${spec#*:}"
  if [[ -f "$target" ]]; then cp -a "$target" "$saved"; else touch "$saved.was-absent"; fi
done

for suffix in model-info.yaml classes-en.txt classes-zh.txt results.csv; do
  target="$APP_DIR/models/river-anomaly-yolo11n-12cls-20260714.$suffix"
  saved="$BACKUP_DIR/app-models/river-anomaly-yolo11n-12cls-20260714.$suffix"
  if [[ -f "$target" ]]; then cp -a "$target" "$saved"; else touch "$saved.was-absent"; fi
done

docker exec "$MYSQL_CONTAINER" sh -lc \
  'mysqldump --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" rw_camera --no-create-info --skip-triggers --replace --where="id IN ('\''CH01'\'','\''CH02'\'','\''CH03'\'','\''CH04'\'','\''CH05'\'','\''CH06'\'','\''CH07'\'','\''CH08'\'')"' \
  > "$BACKUP_DIR/rw_camera-river.sql"

log "4. Install model and add only the new class mappings"
MUTATED=1
install -m 0644 "$PACKAGE_DIR/models/$MODEL_NAME" "$APP_DIR/models/$MODEL_NAME"
install -m 0644 "$PACKAGE_DIR/models/$PT_NAME" "$APP_DIR/models/$PT_NAME"
install -m 0644 "$PACKAGE_DIR/models/$MODEL_NAME" "$OPT_DIR/models/$MODEL_NAME"
install -m 0644 "$PACKAGE_DIR/models/$PT_NAME" "$OPT_DIR/models/$PT_NAME"
install -m 0644 "$PACKAGE_DIR/metadata/model_info.yaml" \
  "$APP_DIR/models/river-anomaly-yolo11n-12cls-20260714.model-info.yaml"
install -m 0644 "$PACKAGE_DIR/metadata/classes_en.txt" \
  "$APP_DIR/models/river-anomaly-yolo11n-12cls-20260714.classes-en.txt"
install -m 0644 "$PACKAGE_DIR/metadata/classes_zh.txt" \
  "$APP_DIR/models/river-anomaly-yolo11n-12cls-20260714.classes-zh.txt"
install -m 0644 "$PACKAGE_DIR/metadata/results.csv" \
  "$APP_DIR/models/river-anomaly-yolo11n-12cls-20260714.results.csv"

for target in \
  "$APP_DIR/ai-pipeline/workers/detect_core.py" \
  "$OPT_DIR/ai-pipeline/workers/detect_core.py"
do
  TARGET_FILE="$target" "$OPT_DIR/ai-pipeline/.venv/bin/python" - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["TARGET_FILE"])
text = path.read_text(encoding="utf-8")
weed_anchor = '    "water_grass": CAT_PLANKTON,\n'
color_anchor = '    "water_discoloration": CAT_COLOR,\n'
if '"aquatic_weed": CAT_PLANKTON' not in text:
    if weed_anchor not in text:
        raise SystemExit(f"mapping anchor missing in {path}")
    text = text.replace(weed_anchor, weed_anchor + '    "aquatic_weed": CAT_PLANKTON,\n', 1)
if '"water_bird": None' not in text:
    if color_anchor not in text:
        raise SystemExit(f"mapping anchor missing in {path}")
    additions = (
        '    "garbage_bag": CAT_FLOATING,\n'
        '    "plastic_foam": CAT_FLOATING_CLUSTER,\n'
        '    "water_foam": CAT_FLOATING_CLUSTER,\n'
        '    # Water birds are normal scene objects and must not create alarms.\n'
        '    "water_bird": None,\n'
    )
    text = text.replace(color_anchor, color_anchor + additions, 1)
path.write_text(text, encoding="utf-8")
PY
done

PYTHONDONTWRITEBYTECODE=1 "$OPT_DIR/ai-pipeline/.venv/bin/python" - <<PY
import sys
sys.path.insert(0, "$OPT_DIR/ai-pipeline/workers")
import detect_core as core
assert core.map_class("aquatic_weed") == core.CAT_PLANKTON
assert core.map_class("garbage_bag") == core.CAT_FLOATING
assert core.map_class("plastic_foam") == core.CAT_FLOATING_CLUSTER
assert core.map_class("water_foam") == core.CAT_FLOATING_CLUSTER
assert core.map_class("water_bird") is None
print("class mapping verification OK")
PY

log "5. Patch CH01-CH08 model settings while preserving confidence thresholds"
for ch in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
  env_file="/etc/river-watch/ai-worker-$ch.env"
  sed -i \
    -e '/^YOLO_ONNX=/d' \
    -e '/^YOLO_LABELS=/d' \
    -e '/^YOLO_IMGSZ=/d' \
    -e '/^MODEL_REQUIRED=/d' \
    "$env_file"
  {
    echo "YOLO_ONNX=$OPT_DIR/models/$MODEL_NAME"
    echo "YOLO_LABELS=$LABELS"
    echo "YOLO_IMGSZ=640"
    echo "MODEL_REQUIRED=1"
  } >> "$env_file"
done

if [[ -f "$APP_DIR/ai-pipeline/config/channels.yaml" ]]; then
  MANIFEST="$APP_DIR/ai-pipeline/config/channels.yaml" MODEL_PATH="$OPT_DIR/models/$MODEL_NAME" MODEL_LABELS="$LABELS" \
    "$OPT_DIR/ai-pipeline/.venv/bin/python" - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["MANIFEST"])
lines = path.read_text(encoding="utf-8").splitlines()
inside = False
seen_model = seen_labels = False
for index, line in enumerate(lines):
    if line == "  river:":
        inside = True
        continue
    if inside and line.startswith("  ") and not line.startswith("    "):
        inside = False
    if not inside:
        continue
    if line.strip().startswith("yolo_onnx:"):
        lines[index] = f"    yolo_onnx: {os.environ['MODEL_PATH']}"
        seen_model = True
    elif line.strip().startswith("yolo_labels:"):
        lines[index] = f"    yolo_labels: {os.environ['MODEL_LABELS']}"
        seen_labels = True
if not (seen_model and seen_labels):
    raise SystemExit("river profile model fields not found in channels.yaml")
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
fi

log "6. Pause river batch while group services take over the model transition"
systemctl stop river-ai-batch@river.service

log "7. Canary activate river-a only"
CANARY_SINCE="$(date --iso-8601=seconds)"
systemctl restart river-ai-group@river-a.service
wait_model_unit river-ai-group@river-a.service river-a "$CANARY_SINCE" || fail "river-a canary failed"

log "8. Activate river-b"
RIVER_B_SINCE="$(date --iso-8601=seconds)"
systemctl restart river-ai-group@river-b.service
wait_model_unit river-ai-group@river-b.service river-b "$RIVER_B_SINCE" || fail "river-b activation failed"

log "9. Activate river batch with the same model"
BATCH_SINCE="$(date --iso-8601=seconds)"
systemctl start river-ai-batch@river.service
wait_model_unit river-ai-batch@river.service river-batch "$BATCH_SINCE" || fail "river batch activation failed"

log "10. Update camera runtime metadata after all river services are healthy"
cat > "$BACKUP_DIR/update-rw-camera.sql" <<SQL
UPDATE rw_camera
SET payload = JSON_SET(
  payload,
  '$.streams.inference.model', '$MODEL_NAME',
  '$.streams.inference.labels', '$LABELS',
  '$.streams.inference.imgsz', 640,
  '$.inferenceModel', '$MODEL_NAME',
  '$.inferenceLabels', '$LABELS'
)
WHERE id IN ('CH01','CH02','CH03','CH04','CH05','CH06','CH07','CH08');
SQL
docker exec -i "$MYSQL_CONTAINER" sh -lc \
  'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
  < "$BACKUP_DIR/update-rw-camera.sql"
DB_UPDATED=1

log "11. Final verification and receipt"
systemctl is-active --quiet river-ai-group@river-a.service
systemctl is-active --quiet river-ai-group@river-b.service
systemctl is-active --quiet river-ai-batch@river.service
systemctl is-active --quiet "$STRUCTURE_UNIT"
[[ "$(sha_of "$OPT_DIR/models/$MODEL_NAME")" == "$MODEL_SHA" ]]
for ch in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
  grep -Fq "YOLO_ONNX=$OPT_DIR/models/$MODEL_NAME" "/etc/river-watch/ai-worker-$ch.env"
  grep -Fq "YOLO_LABELS=$LABELS" "/etc/river-watch/ai-worker-$ch.env"
done

{
  echo "# River anomaly model deployment receipt"
  echo
  echo "- Time: $(date '+%F %T %Z')"
  echo "- Model: $OPT_DIR/models/$MODEL_NAME"
  echo "- ONNX SHA256: $MODEL_SHA"
  echo "- Labels: $LABELS"
  echo "- Scope: CH01-CH08 / river-a + river-b + river batch"
  echo "- Structure service: $STRUCTURE_UNIT (unchanged and not restarted)"
  echo "- Transition: river batch paused while group canary validation ran"
  echo "- Confidence: preserved from each existing worker env"
  echo "- Backup: $BACKUP_DIR"
  echo
  echo '```text'
  systemctl is-active river-ai-group@river-a river-ai-group@river-b river-ai-batch@river "$STRUCTURE_UNIT"
  grep -H -E '^(YOLO_ONNX|YOLO_LABELS|YOLO_CONF|ORT_PROVIDERS)=' /etc/river-watch/ai-worker-CH0{1,2,3,4,5,6,7,8}.env
  echo '```'
} > "$RECEIPT"

trap - ERR
MUTATED=0

log "12. Keep only the latest three backups for this model increment"
mapfile -t OLD_BACKUPS < <(
  find "$APP_DIR/backups" -mindepth 1 -maxdepth 1 -type d \
    -name 'river-anomaly-model-20260714-v2-*' -printf '%p\n' | sort -r | tail -n +4
)
for old in "${OLD_BACKUPS[@]:-}"; do
  case "$old" in
    "$APP_DIR"/backups/river-anomaly-model-20260714-v2-*) rm -rf -- "$old" ;;
  esac
done

log "DONE"
log "Active model: $MODEL_NAME"
log "Receipt: $RECEIPT"
log "Rollback backup: $BACKUP_DIR"
