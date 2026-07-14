#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-deploy-frontend-1}"
FRONTEND_URL="${FRONTEND_URL:-http://127.0.0.1:8081/}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/alarm-list-full-datetime-increment-20260714-$TS"
NEW_MAIN_REL="$(grep -o 'assets/index-[^"[:space:]]*\.js' "$PKG_DIR/frontend/dist/index.html" | head -1)"
NEW_MAIN_NAME="$(basename "$NEW_MAIN_REL")"
NEW_ALARM_NAME="$(find "$PKG_DIR/frontend/dist/assets" -maxdepth 1 -type f -name 'AlarmsPage-*.js' -printf '%f\n' | head -1)"
MUTATED=0

fail() {
  echo "ERROR: $*" >&2
  return 1
}

wait_frontend() {
  local i
  for i in $(seq 1 60); do
    if curl -fsS -m 5 "$FRONTEND_URL" >/dev/null 2>&1; then
      echo "frontend ready after attempt $i/60"
      return 0
    fi
    sleep 2
  done
  return 1
}

restore_optional() {
  local relative="$1"
  local target="$APP_DIR/$relative"
  local saved="$BACKUP_DIR/host/$relative"
  if [ -f "$saved.was-absent" ]; then
    rm -f "$target"
  elif [ -f "$saved" ]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$saved" "$target"
  fi
}

rollback() {
  local rc=$?
  if [ "$MUTATED" -eq 1 ]; then
    echo "== Automatic rollback =="
    cp -a "$BACKUP_DIR/host/frontend/src/views/pages/AlarmsPage.vue" \
      "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue"
    cp -a "$BACKUP_DIR/host/frontend/src/__tests__/alarmsFilterLayout.test.ts" \
      "$APP_DIR/frontend/src/__tests__/alarmsFilterLayout.test.ts"
    cp -a "$BACKUP_DIR/host/frontend/src/__tests__/alarmFlowSimplification.test.ts" \
      "$APP_DIR/frontend/src/__tests__/alarmFlowSimplification.test.ts"
    restore_optional frontend/src/utils/alarmDateTime.ts
    restore_optional frontend/src/__tests__/alarmDateTime.test.ts

    rm -f "$APP_DIR/frontend/dist/assets/$NEW_MAIN_NAME" \
      "$APP_DIR/frontend/dist/assets/$NEW_ALARM_NAME"
    cp -a "$BACKUP_DIR/host/frontend/dist/assets/." "$APP_DIR/frontend/dist/assets/"
    cp -a "$BACKUP_DIR/host/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"

    docker exec "$FRONTEND_CONTAINER" rm -f \
      "/usr/share/nginx/html/assets/$NEW_MAIN_NAME" \
      "/usr/share/nginx/html/assets/$NEW_ALARM_NAME"
    docker cp "$BACKUP_DIR/container-html/assets/." \
      "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets/"
    docker cp "$BACKUP_DIR/container-html/index.html" \
      "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html"
    docker restart "$FRONTEND_CONTAINER" >/dev/null
    wait_frontend || true
    echo "Rollback restored: $BACKUP_DIR"
  fi
  exit "$rc"
}

trap rollback ERR

echo "== River Watch alarm-list full-datetime increment =="
echo "APP_DIR=$APP_DIR"
echo "PKG_DIR=$PKG_DIR"

[ -d "$APP_DIR/frontend/src/views/pages" ] || fail "frontend source not found: $APP_DIR"
[ -d "$APP_DIR/frontend/dist/assets" ] || fail "frontend dist not found: $APP_DIR/frontend/dist"
docker inspect "$FRONTEND_CONTAINER" >/dev/null 2>&1 || fail "container not found: $FRONTEND_CONTAINER"
[ -n "$NEW_MAIN_REL" ] || fail "new main frontend asset not found in package"
[ -n "$NEW_ALARM_NAME" ] || fail "new Alarm Center asset not found in package"

echo "== 1. Verify package and relevant source baseline =="
(cd "$PKG_DIR" && sha256sum -c SHA256SUMS)

if grep -Fq 'formatAlarmDateTime(row)' "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" && \
   cmp -s "$PKG_DIR/frontend/src/views/pages/AlarmsPage.vue" \
     "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue"; then
  echo "Patch source is already active; refreshing and verifying frontend assets."
else
  grep -Fq 'prop="time" label="时间"' "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" || \
    fail "unexpected Alarm Center time-column baseline"
  grep -Fq "if (prop === 'time') return alarm.updatedAt || alarm.createdAt || alarm.time;" \
    "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" || \
    fail "persisted-timestamp sort baseline is missing"
fi

echo "== 2. Backup changed source, host dist and container assets =="
mkdir -p \
  "$BACKUP_DIR/host/frontend/src/views/pages" \
  "$BACKUP_DIR/host/frontend/src/utils" \
  "$BACKUP_DIR/host/frontend/src/__tests__" \
  "$BACKUP_DIR/host/frontend/dist" \
  "$BACKUP_DIR/container-html"

cp -a "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" \
  "$BACKUP_DIR/host/frontend/src/views/pages/AlarmsPage.vue"
cp -a "$APP_DIR/frontend/src/__tests__/alarmsFilterLayout.test.ts" \
  "$BACKUP_DIR/host/frontend/src/__tests__/alarmsFilterLayout.test.ts"
cp -a "$APP_DIR/frontend/src/__tests__/alarmFlowSimplification.test.ts" \
  "$BACKUP_DIR/host/frontend/src/__tests__/alarmFlowSimplification.test.ts"

for relative in \
  frontend/src/utils/alarmDateTime.ts \
  frontend/src/__tests__/alarmDateTime.test.ts
do
  if [ -f "$APP_DIR/$relative" ]; then
    cp -a "$APP_DIR/$relative" "$BACKUP_DIR/host/$relative"
  else
    touch "$BACKUP_DIR/host/$relative.was-absent"
  fi
done

cp -a "$APP_DIR/frontend/dist/index.html" "$BACKUP_DIR/host/frontend/dist/index.html"
mkdir -p "$BACKUP_DIR/host/frontend/dist/assets"
OLD_HOST_MAIN_REL="$(grep -o 'assets/index-[^"[:space:]]*\.js' "$APP_DIR/frontend/dist/index.html" | head -1)"
if [ -n "$OLD_HOST_MAIN_REL" ] && [ -f "$APP_DIR/frontend/dist/$OLD_HOST_MAIN_REL" ]; then
  cp -a "$APP_DIR/frontend/dist/$OLD_HOST_MAIN_REL" "$BACKUP_DIR/host/frontend/dist/assets/"
fi
for asset in "$APP_DIR"/frontend/dist/assets/AlarmsPage-*.js; do
  [ -f "$asset" ] && cp -a "$asset" "$BACKUP_DIR/host/frontend/dist/assets/"
done
docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html" \
  "$BACKUP_DIR/container-html/index.html"
mkdir -p "$BACKUP_DIR/container-html/assets"
OLD_CONTAINER_MAIN_REL="$(docker exec "$FRONTEND_CONTAINER" sh -lc \
  'grep -o "assets/index-[^\"]*\.js" /usr/share/nginx/html/index.html | head -1')"
if [ -n "$OLD_CONTAINER_MAIN_REL" ]; then
  docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/$OLD_CONTAINER_MAIN_REL" \
    "$BACKUP_DIR/container-html/assets/$(basename "$OLD_CONTAINER_MAIN_REL")"
fi
while IFS= read -r asset; do
  [ -n "$asset" ] || continue
  docker cp "$FRONTEND_CONTAINER:$asset" \
    "$BACKUP_DIR/container-html/assets/$(basename "$asset")"
done < <(docker exec "$FRONTEND_CONTAINER" sh -lc \
  'ls /usr/share/nginx/html/assets/AlarmsPage-*.js 2>/dev/null || true')
echo "Rollback backup: $BACKUP_DIR"

echo "== 3. Apply compact source increment =="
MUTATED=1
install -m 0644 "$PKG_DIR/frontend/src/views/pages/AlarmsPage.vue" \
  "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue"
install -m 0644 "$PKG_DIR/frontend/src/utils/alarmDateTime.ts" \
  "$APP_DIR/frontend/src/utils/alarmDateTime.ts"
install -m 0644 "$PKG_DIR/frontend/src/__tests__/alarmDateTime.test.ts" \
  "$APP_DIR/frontend/src/__tests__/alarmDateTime.test.ts"
install -m 0644 "$PKG_DIR/frontend/src/__tests__/alarmsFilterLayout.test.ts" \
  "$APP_DIR/frontend/src/__tests__/alarmsFilterLayout.test.ts"
install -m 0644 "$PKG_DIR/frontend/src/__tests__/alarmFlowSimplification.test.ts" \
  "$APP_DIR/frontend/src/__tests__/alarmFlowSimplification.test.ts"

cp -a "$PKG_DIR/frontend/dist/assets/." "$APP_DIR/frontend/dist/assets/"
cp -a "$PKG_DIR/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"
if [ -n "$OLD_HOST_MAIN_REL" ] && [ "$OLD_HOST_MAIN_REL" != "$NEW_MAIN_REL" ]; then
  rm -f "$APP_DIR/frontend/dist/$OLD_HOST_MAIN_REL"
fi
for asset in "$APP_DIR"/frontend/dist/assets/AlarmsPage-*.js; do
  [ "$(basename "$asset")" = "$NEW_ALARM_NAME" ] || rm -f "$asset"
done

echo "== 4. Hot update frontend container only =="
docker cp "$PKG_DIR/frontend/dist/assets/." \
  "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets/"
docker cp "$PKG_DIR/frontend/dist/index.html" \
  "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html"
if [ -n "$OLD_CONTAINER_MAIN_REL" ] && [ "$OLD_CONTAINER_MAIN_REL" != "$NEW_MAIN_REL" ]; then
  docker exec "$FRONTEND_CONTAINER" rm -f "/usr/share/nginx/html/$OLD_CONTAINER_MAIN_REL"
fi
while IFS= read -r asset; do
  [ -n "$asset" ] || continue
  [ "$(basename "$asset")" = "$NEW_ALARM_NAME" ] || \
    docker exec "$FRONTEND_CONTAINER" rm -f "$asset"
done < <(docker exec "$FRONTEND_CONTAINER" sh -lc \
  'ls /usr/share/nginx/html/assets/AlarmsPage-*.js 2>/dev/null || true')
docker restart "$FRONTEND_CONTAINER" >/dev/null
wait_frontend || fail "frontend did not become ready"

echo "== 5. Verify active source and compiled Alarm Center asset =="
cmp -s "$PKG_DIR/frontend/src/views/pages/AlarmsPage.vue" \
  "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" || fail "AlarmsPage.vue mismatch"
cmp -s "$PKG_DIR/frontend/src/utils/alarmDateTime.ts" \
  "$APP_DIR/frontend/src/utils/alarmDateTime.ts" || fail "alarmDateTime.ts mismatch"
grep -Fq 'formatAlarmDateTime(row)' "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue"
grep -Fq 'min-width="180"' "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue"

docker exec "$FRONTEND_CONTAINER" test -f "/usr/share/nginx/html/$NEW_MAIN_REL"
docker exec "$FRONTEND_CONTAINER" test -f "/usr/share/nginx/html/assets/$NEW_ALARM_NAME"
docker exec "$FRONTEND_CONTAINER" sh -lc \
  "grep -Fq 'Asia/Shanghai' '/usr/share/nginx/html/assets/$NEW_ALARM_NAME'"

trap - ERR
MUTATED=0

echo "== 6. Keep only the latest three backups for this increment =="
mapfile -t OLD_BACKUPS < <(
  find "$APP_DIR/backups" -mindepth 1 -maxdepth 1 -type d \
    -name 'alarm-list-full-datetime-increment-20260714-*' -printf '%p\n' \
    | sort -r | tail -n +4
)
for old in "${OLD_BACKUPS[@]:-}"; do
  case "$old" in
    "$APP_DIR"/backups/alarm-list-full-datetime-increment-20260714-*) rm -rf -- "$old" ;;
  esac
done

echo "DONE"
echo "Alarm Center format: YYYY-MM-DD HH:mm:ss (Asia/Shanghai)"
echo "Active entry: $NEW_MAIN_REL"
echo "Rollback backup: $BACKUP_DIR"
