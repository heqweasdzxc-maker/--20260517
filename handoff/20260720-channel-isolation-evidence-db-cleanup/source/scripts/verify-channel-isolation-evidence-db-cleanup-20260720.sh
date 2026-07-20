#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
run_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
run_docker() { run_root docker "$@"; }
mysql_ctn="$(run_docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}')"
frontend_ctn="$(run_docker ps --format '{{.Names}}' | grep -E 'frontend|nginx|web' | head -1)"

echo "== AI topology and class isolation =="
for unit in river-ai-group@river-a river-ai-group@river-b river-ai-group@structure; do systemctl is-active --quiet "$unit"; echo "active $unit"; done
for unit in river-ai-batch@river river-ai-batch@structure; do ! systemctl is-active --quiet "$unit"; echo "inactive $unit"; done
run_root grep -HE '^ALLOWED_ALARM_TYPES=' /etc/river-watch/ai-worker-CH{01,02,03,04,05,06,07,08,09,10}.env
grep -q 'allowed_alarm_types' "$OPT_DIR/ai-pipeline/workers/group_pool_runtime.py"
grep -q 'allowed_classes' "$OPT_DIR/ai-pipeline/workers/group_pool_core.py"

echo "== Frontend evidence reload =="
grep -q 'async function loadAlarmEvidence' "$APP_DIR/frontend/src/composables/useWorkspace.ts"
grep -q 'reopeningSelectedAlarm' "$APP_DIR/frontend/src/composables/useWorkspace.ts"
grep -q 'selectedAlarmEvidenceStatusText' "$APP_DIR/frontend/src/components/WorkspaceDialogs.vue"
run_docker exec "$frontend_ctn" sh -lc 'grep -Rqs "告警证据加载失败" /usr/share/nginx/html/assets'
curl -fsS -m 8 http://127.0.0.1:8080/api/health
curl -fsS -m 8 http://127.0.0.1:8081/ >/dev/null

echo "== No structure alarm can originate from river channels after cleanup =="
wrong="$(run_docker exec "$mysql_ctn" sh -lc 'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "
SELECT COUNT(*) FROM rw_alarm
WHERE camera_id IN ('\''CH01'\'','\''CH02'\'','\''CH03'\'','\''CH04'\'','\''CH05'\'','\''CH06'\'','\''CH07'\'','\''CH08'\'')
AND type IN ('\''墙体裂痕'\'','\''污水渗漏'\'','\''地面水渍'\'','\''wall_crack'\'','\''crack'\'');"')"
[ "$wrong" = "0" ] || { echo "ERROR: wrong river-channel structure alarms=$wrong" >&2; exit 1; }
echo "wrong_river_structure_alarms=0"
echo "VERIFY OK"
