#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_DIR="${1:-}"
[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }
[[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || { echo "ERROR: rollback backup directory is required" >&2; exit 1; }
[[ -f "$BACKUP_DIR/unit-state.tsv" ]] || { echo "ERROR: missing unit-state.tsv" >&2; exit 1; }
[[ -f "$BACKUP_DIR/file-state.tsv" ]] || { echo "ERROR: missing file-state.tsv" >&2; exit 1; }

restore_file_state() {
  local path state key
  while IFS=$'\t' read -r path state key; do
    [[ -n "$path" ]] || continue
    if [[ "$state" == "present" ]]; then
      install -d -m 0755 "$(dirname "$path")"
      cp -a "$BACKUP_DIR/$key" "$path"
    else
      rm -f -- "$path"
    fi
  done < "$BACKUP_DIR/file-state.tsv"
}

restore_unit_state() {
  local unit active enabled
  while IFS=$'\t' read -r unit active enabled; do
    [[ -n "$unit" ]] || continue
    systemctl stop "$unit" >/dev/null 2>&1 || true
    if [[ "$enabled" == "enabled" ]]; then
      systemctl enable "$unit" >/dev/null 2>&1 || true
    elif [[ "$enabled" == "disabled" ]]; then
      systemctl disable "$unit" >/dev/null 2>&1 || true
    fi
    if [[ "$active" == "active" ]]; then
      systemctl start "$unit"
    fi
  done < "$BACKUP_DIR/unit-state.tsv"
}

restore_registry() {
  local container
  container="${MYSQL_CONTAINER:-$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}')}"
  [[ -n "$container" ]] || return 0
  docker exec "$container" sh -lc \
    'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "DELETE FROM rw_algorithm WHERE id IN ('"'"'ALG-RIVER-20260714'"'"','"'"'ALG-STRUCTURE-20260630'"'"');"'
  if [[ -s "$BACKUP_DIR/rw_algorithm-owned-before.sql" ]]; then
    docker exec -i "$container" sh -lc \
      'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
      < "$BACKUP_DIR/rw_algorithm-owned-before.sql"
  fi
}

echo "== Restore environment/model files =="
restore_file_state
systemctl daemon-reload
echo "== Restore model registry =="
restore_registry
echo "== Restore service state =="
restore_unit_state
echo "ROLLBACK DONE"


