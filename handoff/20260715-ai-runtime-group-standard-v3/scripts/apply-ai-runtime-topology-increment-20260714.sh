#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${BACKUP_ROOT:-$APP_DIR/backups}"
BACKUP_DIR="$BACKUP_ROOT/ai-runtime-group-standard-v3-20260715-$STAMP"
STATE_FILE="$BACKUP_DIR/unit-state.tsv"
FILE_STATE="$BACKUP_DIR/file-state.tsv"
RECEIPT_DIR="$APP_DIR/logs/ops"
RECEIPT="$RECEIPT_DIR/ai-runtime-group-standard-v3-20260715-$STAMP.md"

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
unit_active() { systemctl is-active --quiet "$1"; }

assert_runtime_baseline() {
  local batch_river=0 river_a=0 river_b=0 batch_structure=0 group_structure=0

  if unit_active river-ai-batch@river.service; then batch_river=1; fi
  if unit_active river-ai-group@river-a.service; then river_a=1; fi
  if unit_active river-ai-group@river-b.service; then river_b=1; fi
  if unit_active river-ai-batch@structure.service; then batch_structure=1; fi
  if unit_active river-ai-group@structure.service; then group_structure=1; fi

  if (( batch_river == 1 && river_a == 0 && river_b == 0 )); then
    log "accepted baseline: batch river with both river groups stopped"
  elif (( batch_river == 0 && river_a == 1 && river_b == 1 )); then
    log "accepted baseline: both river groups with batch river stopped"
  else
    die "unsafe river baseline: batch=$batch_river river-a=$river_a river-b=$river_b"
  fi

  if (( batch_structure == 1 && group_structure == 0 )); then
    log "accepted baseline: batch structure with structure group stopped"
  elif (( batch_structure == 0 && group_structure == 1 )); then
    log "accepted baseline: structure group with batch structure stopped"
  else
    die "unsafe structure baseline: batch=$batch_structure group=$group_structure"
  fi
}

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

wait_group() {
  local unit="$1" expected="$2" model="$3" since="$4"
  local deadline=$((SECONDS + 900)) next_report=$SECONDS
  local main_pid child_count logs model_count provider_count
  while (( SECONDS < deadline )); do
    child_count=0
    model_count=0
    provider_count=0
    if systemctl is-active --quiet "$unit"; then
      main_pid="$(systemctl show -p MainPID --value "$unit")"
      if [[ "$main_pid" =~ ^[1-9][0-9]*$ ]]; then
        child_count="$( { pgrep -P "$main_pid" -f 'workers/river_worker.py' 2>/dev/null || true; } | wc -l | tr -d ' ')"
      fi
      logs="$(journalctl -u "$unit" --since "$since" --no-pager 2>/dev/null || true)"
      model_count="$(printf '%s\n' "$logs" | grep -Fc "$model" || true)"
      provider_count="$(printf '%s\n' "$logs" | grep -c 'MIGraphXExecutionProvider' || true)"
      if (( child_count >= expected && model_count >= expected && provider_count >= expected )); then
        log "$unit ready: main_pid=$main_pid children=$child_count model_logs=$model_count provider_logs=$provider_count"
        return 0
      fi
    fi
    if systemctl is-failed --quiet "$unit"; then
      journalctl -u "$unit" --since "$since" --no-pager | tail -160 >&2 || true
      die "$unit entered failed state during startup"
    fi
    if (( SECONDS >= next_report )); then
      log "waiting for $unit: children=$child_count/$expected model_logs=$model_count/$expected provider_logs=$provider_count/$expected"
      next_report=$((SECONDS + 30))
    fi
    sleep 5
  done
  journalctl -u "$unit" --since "$since" --no-pager | tail -160 >&2 || true
  die "$unit did not load $expected MIGraphX workers within 900 seconds"
}

verify_group_children() {
  local unit="$1" expected="$2" main_pid count
  assert_active "$unit"
  main_pid="$(systemctl show -p MainPID --value "$unit")"
  [[ "$main_pid" =~ ^[1-9][0-9]*$ ]] || die "$unit has no MainPID"
  count="$( { pgrep -P "$main_pid" -f 'workers/river_worker.py' 2>/dev/null || true; } | wc -l | tr -d ' ')"
  (( count >= expected )) || die "$unit has $count/$expected child workers"
}

require_root

log "River Watch AI runtime group-standard v3"
log "1. Preflight current runtime baseline and backend"
assert_runtime_baseline
curl -fsS -m 8 http://127.0.0.1:8080/api/health >/dev/null
[[ -r "$RIVER_MODEL" ]] || die "missing river model: $RIVER_MODEL"
for group_env in /etc/river-watch/ai-group-river-a.env /etc/river-watch/ai-group-river-b.env; do
  [[ -r "$group_env" ]] || die "missing group env: $group_env"
done
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
mkdir -p "$BACKUP_DIR" "$RECEIPT_DIR"
: > "$FILE_STATE"
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

log "6. Stop batch inference before starting group workers"
systemctl enable river-ai-group@river-a.service river-ai-group@river-b.service river-ai-group@structure.service
systemctl stop river-ai-batch@river.service river-ai-batch@structure.service

log "7. Start and validate river-a"
RIVER_A_SINCE="$(date --iso-8601=seconds)"
systemctl restart river-ai-group@river-a.service
wait_group river-ai-group@river-a.service 4 "$RIVER_MODEL" "$RIVER_A_SINCE"

log "8. Start and validate river-b"
RIVER_B_SINCE="$(date --iso-8601=seconds)"
systemctl restart river-ai-group@river-b.service
wait_group river-ai-group@river-b.service 4 "$RIVER_MODEL" "$RIVER_B_SINCE"

log "9. Start and validate structure"
STRUCTURE_SINCE="$(date --iso-8601=seconds)"
systemctl restart river-ai-group@structure.service
wait_group river-ai-group@structure.service 2 "$STRUCTURE_MODEL" "$STRUCTURE_SINCE"

log "10. Disable retained batch services after all groups are ready"
systemctl disable river-ai-batch@river.service river-ai-batch@structure.service
verify_group_children river-ai-group@river-a.service 4
verify_group_children river-ai-group@river-b.service 4
verify_group_children river-ai-group@structure.service 2
assert_enabled river-ai-group@river-a.service
assert_enabled river-ai-group@river-b.service
assert_enabled river-ai-group@structure.service

log "11. Register the two production models"
docker exec -i "$MYSQL_CONTAINER" sh -lc \
  'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
  < "$PKG_DIR/db/upsert-production-model-registry.sql"

log "12. Final verification"
"$PKG_DIR/scripts/verify-ai-runtime-topology-20260714.sh"

cat > "$RECEIPT" <<EOF
# AI runtime group-standard v3 receipt

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

