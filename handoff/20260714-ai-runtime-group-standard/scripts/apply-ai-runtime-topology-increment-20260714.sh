#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${BACKUP_ROOT:-$APP_DIR/backups}"
BACKUP_DIR="$BACKUP_ROOT/ai-runtime-group-standard-20260714-$STAMP"
STATE_FILE="$BACKUP_DIR/unit-state.tsv"
FILE_STATE="$BACKUP_DIR/file-state.tsv"
RECEIPT_DIR="$APP_DIR/logs/ops"
RECEIPT="$RECEIPT_DIR/ai-runtime-group-standard-20260714-$STAMP.md"

RIVER_MODEL="/opt/river-watch/models/river-anomaly-yolo11n-12cls-20260714.onnx"
STRUCTURE_MODEL="/opt/river-watch/models/yolo-wall-crack-leak-20260630.onnx"
STRUCTURE_MODEL_APP="$APP_DIR/models/yolo-wall-crack-leak-20260630.onnx"
STRUCTURE_SHA="3d7623906d57bdb439a5686dd6b39093c6ca8b9d6e233f3c78027d048d35e3f4"
RIVER_CHANNELS=(CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08)
STRUCTURE_CHANNELS=(CH09 CH10)
ALL_UNITS=(
  river-ai-group@river-a.service
  river-ai-group@river-b.service
  river-ai-group@structure.service
  river-ai-batch@river.service
  river-ai-batch@structure.service
)
MUTATED=0

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR: $*" >&2; return 1; }
require_root() { [[ "$(id -u)" -eq 0 ]] || die "run with sudo"; }
sha256_of() { sha256sum "$1" | awk '{print tolower($1)}'; }

env_value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

upsert_env() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { found=0 }
    index($0, key "=") == 1 {
      if (!found) print key "=" value
      found=1
      next
    }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" > "$tmp"
  install -m 0640 "$tmp" "$file"
  rm -f "$tmp"
}

assert_active() { systemctl is-active --quiet "$1" || die "$1 is not active"; }
assert_enabled() { systemctl is-enabled --quiet "$1" || die "$1 is not enabled"; }

assert_channel_model() {
  local channel="$1" expected="$2" provider
  local file="/etc/river-watch/ai-worker-$channel.env"
  [[ -r "$file" ]] || die "missing worker env: $file"
  [[ "$(env_value "$file" YOLO_ONNX)" == "$expected" ]] || die "$channel model is not $expected"
  provider="$(env_value "$file" ORT_PROVIDERS)"
  [[ "$provider" == *MIGraphXExecutionProvider* ]] || die "$channel does not request MIGraphXExecutionProvider"
}

capture_unit_state() {
  : > "$STATE_FILE"
  local unit active enabled
  for unit in "${ALL_UNITS[@]}"; do
    active="$(systemctl is-active "$unit" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    printf '%s\t%s\t%s\n' "$unit" "${active:-unknown}" "${enabled:-unknown}" >> "$STATE_FILE"
  done
}

backup_file() {
  local path="$1" key
  key="$(printf '%s' "$path" | sed 's#^/##; s#/#__#g')"
  if [[ -e "$path" ]]; then
    cp -a "$path" "$BACKUP_DIR/$key"
    printf '%s\tpresent\t%s\n' "$path" "$key" >> "$FILE_STATE"
  else
    printf '%s\tabsent\t%s\n' "$path" "$key" >> "$FILE_STATE"
  fi
}

find_mysql_container() {
  docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}'
}

backup_registry() {
  local container="$1"
  docker exec "$container" sh -lc \
    'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" rw_algorithm --no-create-info --complete-insert --where="id IN ('"'"'ALG-RIVER-20260714'"'"','"'"'ALG-STRUCTURE-20260630'"'"')"' \
    > "$BACKUP_DIR/rw_algorithm-owned-before.sql"
}

rollback_on_error() {
  local line="$1" rc=$?
  trap - ERR
  log "deployment failed at line $line (rc=$rc)"
  if [[ "$MUTATED" -eq 1 ]]; then
    "$PKG_DIR/scripts/rollback-ai-runtime-topology-20260714.sh" "$BACKUP_DIR" || true
  fi
  exit "$rc"
}
trap 'rollback_on_error "$LINENO"' ERR

wait_structure_group() {
  local since="$1" deadline=$((SECONDS + 600)) main_pid child_count logs model_count provider_count
  while (( SECONDS < deadline )); do
    if systemctl is-active --quiet river-ai-group@structure.service; then
      main_pid="$(systemctl show -p MainPID --value river-ai-group@structure.service)"
      child_count=0
      if [[ "$main_pid" =~ ^[1-9][0-9]*$ ]]; then
        child_count="$(pgrep -P "$main_pid" -f 'workers/river_worker.py' 2>/dev/null | wc -l | tr -d ' ')"
      fi
      logs="$(journalctl -u river-ai-group@structure.service --since "$since" --no-pager 2>/dev/null || true)"
      model_count="$(printf '%s\n' "$logs" | grep -Fc "$STRUCTURE_MODEL" || true)"
      provider_count="$(printf '%s\n' "$logs" | grep -c 'MIGraphXExecutionProvider' || true)"
      if (( child_count >= 2 && model_count >= 2 && provider_count >= 2 )); then
        log "structure group ready: main_pid=$main_pid children=$child_count model_logs=$model_count provider_logs=$provider_count"
        return 0
      fi
    fi
    sleep 5
  done
  journalctl -u river-ai-group@structure.service --since "$since" --no-pager | tail -160 >&2 || true
  die "structure group did not load two MIGraphX workers within 600 seconds"
}

verify_group_children() {
  local unit="$1" expected="$2" main_pid count
  assert_active "$unit"
  main_pid="$(systemctl show -p MainPID --value "$unit")"
  [[ "$main_pid" =~ ^[1-9][0-9]*$ ]] || die "$unit has no MainPID"
  count="$(pgrep -P "$main_pid" -f 'workers/river_worker.py' 2>/dev/null | wc -l | tr -d ' ')"
  (( count >= expected )) || die "$unit has $count/$expected child workers"
}

require_root
mkdir -p "$BACKUP_DIR" "$RECEIPT_DIR"
: > "$FILE_STATE"

log "1. Preflight current river groups and backend"
assert_active river-ai-group@river-a.service
assert_active river-ai-group@river-b.service
assert_active river-ai-batch@structure.service
curl -fsS -m 8 http://127.0.0.1:8080/api/health >/dev/null
[[ -r "$RIVER_MODEL" ]] || die "missing river model: $RIVER_MODEL"
for channel in "${RIVER_CHANNELS[@]}"; do
  assert_channel_model "$channel" "$RIVER_MODEL"
done

log "2. Verify high-accuracy structure model"
if [[ -r "$STRUCTURE_MODEL" ]] && [[ "$(sha256_of "$STRUCTURE_MODEL")" == "$STRUCTURE_SHA" ]]; then
  log "verified existing structure model"
else
  [[ -r "$STRUCTURE_MODEL_APP" ]] || die "verified structure model not found in /opt or application models"
  [[ "$(sha256_of "$STRUCTURE_MODEL_APP")" == "$STRUCTURE_SHA" ]] || die "application structure model checksum mismatch"
fi

MYSQL_CONTAINER="${MYSQL_CONTAINER:-$(find_mysql_container)}"
[[ -n "$MYSQL_CONTAINER" ]] || die "running MySQL container not found"

log "3. Capture rollback state"
capture_unit_state
for file in \
  /etc/river-watch/ai-group-structure.env \
  /etc/river-watch/ai-worker-CH09.env \
  /etc/river-watch/ai-worker-CH10.env \
  "$STRUCTURE_MODEL"
do
  backup_file "$file"
done
backup_registry "$MYSQL_CONTAINER"
MUTATED=1

log "4. Install verified structure model when needed"
if [[ ! -r "$STRUCTURE_MODEL" ]] || [[ "$(sha256_of "$STRUCTURE_MODEL")" != "$STRUCTURE_SHA" ]]; then
  install -d -m 0755 "$(dirname "$STRUCTURE_MODEL")"
  install -m 0644 "$STRUCTURE_MODEL_APP" "$STRUCTURE_MODEL"
fi
[[ "$(sha256_of "$STRUCTURE_MODEL")" == "$STRUCTURE_SHA" ]]

log "5. Configure structure group without replacing stream, token, confidence or sampling values"
[[ -f /etc/river-watch/ai-group-structure.env ]] || install -m 0640 /dev/null /etc/river-watch/ai-group-structure.env
upsert_env /etc/river-watch/ai-group-structure.env GROUP_ID structure
upsert_env /etc/river-watch/ai-group-structure.env GROUP_NAME "结构缺陷推理 CH09-CH10"
upsert_env /etc/river-watch/ai-group-structure.env GROUP_MODE live
upsert_env /etc/river-watch/ai-group-structure.env CHANNELS CH09,CH10
upsert_env /etc/river-watch/ai-group-structure.env GROUP_MODEL "$STRUCTURE_MODEL"
upsert_env /etc/river-watch/ai-group-structure.env WORKER_ENV_DIR /etc/river-watch
upsert_env /etc/river-watch/ai-group-structure.env WORKER_SCRIPT workers/river_worker.py
upsert_env /etc/river-watch/ai-group-structure.env RIVER_WATCH_RUNTIME_PRESET c9-gpu-64g

for channel in "${STRUCTURE_CHANNELS[@]}"; do
  env_file="/etc/river-watch/ai-worker-$channel.env"
  [[ -f "$env_file" ]] || die "missing worker env: $env_file"
  upsert_env "$env_file" DETECTORS structure
  upsert_env "$env_file" YOLO_ONNX "$STRUCTURE_MODEL"
  upsert_env "$env_file" YOLO_FALLBACK_ONNX ""
  upsert_env "$env_file" YOLO_LABELS crack,leak
  upsert_env "$env_file" YOLO_IMGSZ 640
  upsert_env "$env_file" MODEL_REQUIRED 1
  upsert_env "$env_file" ORT_PROVIDERS MIGraphXExecutionProvider
  upsert_env "$env_file" REQUIRE_GPU_PROVIDER 1
  [[ -n "$(env_value "$env_file" YOLO_CONF)" ]] || upsert_env "$env_file" YOLO_CONF 0.40
  assert_channel_model "$channel" "$STRUCTURE_MODEL"
done

log "6. Replace structure batch with structure group and validate"
CANARY_SINCE="$(date --iso-8601=seconds)"
systemctl stop river-ai-batch@structure.service
systemctl enable river-ai-group@structure.service
systemctl restart river-ai-group@structure.service
wait_structure_group "$CANARY_SINCE"

log "7. Standardize all production inference on group services"
systemctl enable river-ai-group@river-a.service river-ai-group@river-b.service river-ai-group@structure.service
systemctl disable --now river-ai-batch@river.service river-ai-batch@structure.service
verify_group_children river-ai-group@river-a.service 4
verify_group_children river-ai-group@river-b.service 4
verify_group_children river-ai-group@structure.service 2
assert_enabled river-ai-group@river-a.service
assert_enabled river-ai-group@river-b.service
assert_enabled river-ai-group@structure.service

log "8. Register the two production models"
docker exec -i "$MYSQL_CONTAINER" sh -lc \
  'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
  < "$PKG_DIR/db/upsert-production-model-registry.sql"

log "9. Final verification"
"$PKG_DIR/scripts/verify-ai-runtime-topology-20260714.sh"

cat > "$RECEIPT" <<EOF
# AI runtime group-standard receipt

- Time: $(date '+%F %T %Z')
- River services: group@river-a CH01-CH04, group@river-b CH05-CH08
- Structure service: group@structure CH09-CH10
- Structure model: $STRUCTURE_MODEL
- Structure SHA-256: $STRUCTURE_SHA
- Batch services: retained, stopped and disabled
- Rollback state: $BACKUP_DIR
EOF

trap - ERR
MUTATED=0
log "DONE"
log "receipt=$RECEIPT"
log "rollback=$PKG_DIR/scripts/rollback-ai-runtime-topology-20260714.sh $BACKUP_DIR"

