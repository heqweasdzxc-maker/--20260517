#!/usr/bin/env bash
set -Eeuo pipefail

RIVER_MODEL="/opt/river-watch/models/river-anomaly-yolo11n-12cls-20260714.onnx"
STRUCTURE_MODEL="/opt/river-watch/models/yolo-wall-crack-leak-20260630.onnx"
STRUCTURE_SHA="3d7623906d57bdb439a5686dd6b39093c6ca8b9d6e233f3c78027d048d35e3f4"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
env_value() { awk -F= -v key="$2" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$1"; }
assert_active() { systemctl is-active --quiet "$1" || die "$1 is not active"; }
assert_inactive() {
  if systemctl is-active --quiet "$1"; then
    die "$1 is still active"
  fi
}
assert_enabled() { systemctl is-enabled --quiet "$1" || die "$1 is not enabled"; }
assert_disabled() {
  if systemctl is-enabled --quiet "$1"; then
    die "$1 is still enabled"
  fi
}

assert_main_pid() {
  local unit="$1" expected_children="$2" pid count
  pid="$(systemctl show -p MainPID --value "$unit")"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || die "$unit has invalid MainPID=$pid"
  count="$( { pgrep -P "$pid" -f 'workers/river_worker.py' 2>/dev/null || true; } | wc -l | tr -d ' ')"
  (( count >= expected_children )) || die "$unit has $count/$expected_children child workers"
}

assert_worker_env() {
  local channel="$1" model="$2" provider
  local file="/etc/river-watch/ai-worker-$channel.env"
  [[ -r "$file" ]] || die "missing $file"
  [[ "$(env_value "$file" YOLO_ONNX)" == "$model" ]] || die "$channel model mismatch"
  provider="$(env_value "$file" ORT_PROVIDERS)"
  [[ "$provider" == *MIGraphXExecutionProvider* ]] || die "$channel is not configured for MIGraphXExecutionProvider"
}

echo "== 1. Group-only service topology =="
assert_active river-ai-group@river-a.service
assert_active river-ai-group@river-b.service
assert_active river-ai-group@structure.service
assert_inactive river-ai-batch@river.service
assert_inactive river-ai-batch@structure.service
assert_enabled river-ai-group@river-a.service
assert_enabled river-ai-group@river-b.service
assert_enabled river-ai-group@structure.service
assert_disabled river-ai-batch@river.service
assert_disabled river-ai-batch@structure.service

echo "== 2. MainPID and child workers =="
assert_main_pid river-ai-group@river-a.service 4
assert_main_pid river-ai-group@river-b.service 4
assert_main_pid river-ai-group@structure.service 2

echo "== 3. Exact model assignment =="
for channel in CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08; do
  assert_worker_env "$channel" "$RIVER_MODEL"
done
for channel in CH09 CH10; do
  assert_worker_env "$channel" "$STRUCTURE_MODEL"
done
[[ "$(sha256sum "$STRUCTURE_MODEL" | awk '{print tolower($1)}')" == "$STRUCTURE_SHA" ]] || die "structure model checksum mismatch"

echo "== 4. Backend and registry =="
curl -fsS -m 8 http://127.0.0.1:8080/api/health
MYSQL_CONTAINER="${MYSQL_CONTAINER:-$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}')}"
[[ -n "$MYSQL_CONTAINER" ]] || die "running MySQL container not found"
REGISTRY_COUNT="$(docker exec "$MYSQL_CONTAINER" sh -lc 'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM rw_algorithm WHERE id IN ('"'"'ALG-RIVER-20260714'"'"','"'"'ALG-STRUCTURE-20260630'"'"');"')"
[[ "$REGISTRY_COUNT" == "2" ]] || die "production model registry count=$REGISTRY_COUNT"

echo "== 5. Process summary =="
systemctl is-active river-ai-group@river-a river-ai-group@river-b river-ai-group@structure
systemctl is-enabled river-ai-group@river-a river-ai-group@river-b river-ai-group@structure
systemctl is-active river-ai-batch@river river-ai-batch@structure || true
pgrep -af 'group_worker.py|river_worker.py|batch_worker.py' | head -30 || true
command -v rocm-smi >/dev/null 2>&1 && rocm-smi --showpids --showuse || true
echo "VERIFY OK"

