#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
OPT_DIR="${OPT_DIR:-/opt/river-watch}"
BACKUP_DIR="${1:-$(find "$APP_DIR/backups" -maxdepth 1 -mindepth 1 -type d -name 'channel-isolation-evidence-db-cleanup-20260720-*' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)}"
case "$APP_DIR" in /home/ai-river/*) ;; *) echo "ERROR: unsafe APP_DIR: $APP_DIR" >&2; exit 1 ;; esac
case "$OPT_DIR" in /opt/river-watch) ;; *) echo "ERROR: unsafe OPT_DIR: $OPT_DIR" >&2; exit 1 ;; esac
case "$BACKUP_DIR" in "$APP_DIR"/backups/channel-isolation-evidence-db-cleanup-20260720-*) ;; *) echo "ERROR: unsafe rollback directory: $BACKUP_DIR" >&2; exit 1 ;; esac
[ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ] || { echo "ERROR: rollback backup not found" >&2; exit 1; }

run_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
run_docker() { run_root docker "$@"; }
backend_ctn="$(run_docker ps -a --format '{{.Names}}' | grep -E 'backend' | head -1)"
frontend_ctn="$(run_docker ps -a --format '{{.Names}}' | grep -E 'frontend|nginx|web' | head -1)"
mysql_ctn="$(run_docker ps -a --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}')"

echo "Restoring from $BACKUP_DIR"
run_root systemctl stop river-ai-group@river-a.service river-ai-group@river-b.service river-ai-group@structure.service \
  river-ai-batch@river.service river-ai-batch@structure.service || true
run_docker stop "$backend_ctn" >/dev/null 2>&1 || true

while IFS=$'\t' read -r target saved; do
  [ -n "$target" ] || continue
  if [ "$saved" = "ABSENT" ]; then
    run_root rm -f "$target"
  else
    run_root cp -a "$BACKUP_DIR/$saved" "$target"
  fi
done < "$BACKUP_DIR/file-manifest.tsv"

run_root rm -rf "$APP_DIR/frontend/dist/assets"
run_root cp -a "$BACKUP_DIR/frontend/dist/assets" "$APP_DIR/frontend/dist/assets"
run_root cp -a "$BACKUP_DIR/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"
run_docker exec "$frontend_ctn" sh -lc 'rm -rf /usr/share/nginx/html/assets' || true
run_docker cp "$BACKUP_DIR/frontend/dist/assets" "$frontend_ctn:/usr/share/nginx/html/assets" || true
run_docker cp "$BACKUP_DIR/frontend/dist/index.html" "$frontend_ctn:/usr/share/nginx/html/index.html" || true

if [ -f "$BACKUP_DIR/db-backup.path" ]; then
  DB_BACKUP="$(cat "$BACKUP_DIR/db-backup.path")"
  [ -s "$DB_BACKUP" ] || { echo "ERROR: database rollback file missing: $DB_BACKUP" >&2; exit 1; }
  run_docker exec "$mysql_ctn" sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "
SET FOREIGN_KEY_CHECKS=0;
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
SET FOREIGN_KEY_CHECKS=1;"'
  { printf 'SET FOREIGN_KEY_CHECKS=0;\n'; gzip -dc "$DB_BACKUP"; printf '\nSET FOREIGN_KEY_CHECKS=1;\n'; } \
    | run_docker exec -i "$mysql_ctn" sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
fi

run_docker start "$backend_ctn" >/dev/null
run_docker restart "$frontend_ctn" >/dev/null
run_root systemctl daemon-reload
while IFS=$'\t' read -r unit enabled active; do
  case "$enabled" in enabled) run_root systemctl enable "$unit" >/dev/null 2>&1 || true ;; disabled) run_root systemctl disable "$unit" >/dev/null 2>&1 || true ;; esac
  [ "$active" = "active" ] && run_root systemctl start "$unit" || run_root systemctl stop "$unit" || true
done < "$BACKUP_DIR/service-state.tsv"

echo "ROLLBACK DONE"
echo "Restored database: ${DB_BACKUP:-not-recorded}"
