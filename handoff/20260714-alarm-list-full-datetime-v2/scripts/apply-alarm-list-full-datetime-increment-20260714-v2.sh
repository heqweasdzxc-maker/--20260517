#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-deploy-frontend-1}"
FRONTEND_URL="${FRONTEND_URL:-http://127.0.0.1:8081/}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/alarm-list-full-datetime-increment-20260714-v2-$TS"
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

verify_page_chunks() {
  local dist="$1"
  local main_rel
  main_rel="$(grep -o 'assets/index-[^"[:space:]]*\.js' "$dist/index.html" | head -1)"
  [ -n "$main_rel" ] || fail "main frontend entry not found"
  [ -f "$dist/$main_rel" ] || fail "main frontend entry is missing: $main_rel"

  while IFS= read -r page_chunk; do
    [ -n "$page_chunk" ] || continue
    [ -f "$dist/assets/$page_chunk" ] || fail "referenced page chunk is missing: $page_chunk"
  done < <(grep -oE '[A-Za-z]+Page-[A-Za-z0-9_-]+\.js' "$dist/$main_rel" | sort -u)
}

rollback() {
  local rc=$?
  if [ "$MUTATED" -eq 1 ]; then
    echo "== Automatic rollback =="
    cp -a "$BACKUP_DIR/host/frontend/src/views/pages/AlarmsPage.vue" \
      "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue"
    restore_optional frontend/src/utils/alarmDateTime.ts
    restore_optional frontend/src/__tests__/alarmDateTime.test.ts
    restore_optional frontend/src/__tests__/alarmsFilterLayout.test.ts
    restore_optional frontend/src/__tests__/alarmFlowSimplification.test.ts

    rm -rf "$APP_DIR/frontend/dist/assets"
    cp -a "$BACKUP_DIR/host/frontend/dist/assets" "$APP_DIR/frontend/dist/assets"
    cp -a "$BACKUP_DIR/host/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"

    docker exec "$FRONTEND_CONTAINER" sh -lc 'rm -rf /usr/share/nginx/html/assets'
    docker cp "$BACKUP_DIR/container-html/assets" \
      "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets"
    docker cp "$BACKUP_DIR/container-html/index.html" \
      "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html"
    docker restart "$FRONTEND_CONTAINER" >/dev/null
    wait_frontend || true
    echo "Rollback restored: $BACKUP_DIR"
  fi
  exit "$rc"
}

trap rollback ERR

echo "== River Watch alarm-list full-datetime v2 =="
echo "APP_DIR=$APP_DIR"
echo "PKG_DIR=$PKG_DIR"

[ -d "$APP_DIR/frontend/src/views/pages" ] || fail "frontend source not found: $APP_DIR"
[ -d "$APP_DIR/frontend/dist/assets" ] || fail "frontend dist not found: $APP_DIR/frontend/dist"
docker inspect "$FRONTEND_CONTAINER" >/dev/null 2>&1 || fail "container not found: $FRONTEND_CONTAINER"

echo "== 1. Verify package checksums and complete page-chunk closure =="
(cd "$PKG_DIR" && sha256sum -c SHA256SUMS)
verify_page_chunks "$PKG_DIR/frontend/dist"
if command -v node >/dev/null 2>&1; then
  node "$PKG_DIR/scripts/verify-frontend-dist-closure.mjs" "$PKG_DIR/frontend/dist"
fi

echo "== 2. Backup frontend source, host assets and container assets =="
mkdir -p \
  "$BACKUP_DIR/host/frontend/src/views/pages" \
  "$BACKUP_DIR/host/frontend/src/utils" \
  "$BACKUP_DIR/host/frontend/src/__tests__" \
  "$BACKUP_DIR/host/frontend/dist" \
  "$BACKUP_DIR/container-html"

cp -a "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" \
  "$BACKUP_DIR/host/frontend/src/views/pages/AlarmsPage.vue"
for relative in \
  frontend/src/utils/alarmDateTime.ts \
  frontend/src/__tests__/alarmDateTime.test.ts \
  frontend/src/__tests__/alarmsFilterLayout.test.ts \
  frontend/src/__tests__/alarmFlowSimplification.test.ts
do
  if [ -f "$APP_DIR/$relative" ]; then
    cp -a "$APP_DIR/$relative" "$BACKUP_DIR/host/$relative"
  else
    touch "$BACKUP_DIR/host/$relative.was-absent"
  fi
done

cp -a "$APP_DIR/frontend/dist/index.html" "$BACKUP_DIR/host/frontend/dist/index.html"
cp -a "$APP_DIR/frontend/dist/assets" "$BACKUP_DIR/host/frontend/dist/assets"
docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html" \
  "$BACKUP_DIR/container-html/index.html"
docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets" \
  "$BACKUP_DIR/container-html/assets"
echo "Rollback backup: $BACKUP_DIR"

echo "== 3. Apply source and complete assets dependency closure =="
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

rm -rf "$APP_DIR/frontend/dist/assets.next"
cp -a "$PKG_DIR/frontend/dist/assets" "$APP_DIR/frontend/dist/assets.next"
rm -rf "$APP_DIR/frontend/dist/assets"
mv "$APP_DIR/frontend/dist/assets.next" "$APP_DIR/frontend/dist/assets"
cp -a "$PKG_DIR/frontend/dist/index.html" "$APP_DIR/frontend/dist/index.html"

echo "== 4. Hot update frontend container only =="
docker exec "$FRONTEND_CONTAINER" sh -lc 'rm -rf /usr/share/nginx/html/assets'
docker cp "$PKG_DIR/frontend/dist/assets" \
  "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets"
docker cp "$PKG_DIR/frontend/dist/index.html" \
  "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html"
docker restart "$FRONTEND_CONTAINER" >/dev/null
wait_frontend || fail "frontend did not become ready"

echo "== 5. Verify deployed hashes and menu page chunks =="
verify_page_chunks "$APP_DIR/frontend/dist"
cmp -s "$PKG_DIR/frontend/src/views/pages/AlarmsPage.vue" \
  "$APP_DIR/frontend/src/views/pages/AlarmsPage.vue" || fail "AlarmsPage.vue mismatch"
cmp -s "$PKG_DIR/frontend/src/utils/alarmDateTime.ts" \
  "$APP_DIR/frontend/src/utils/alarmDateTime.ts" || fail "alarmDateTime.ts mismatch"

while IFS= read -r -d '' package_file; do
  relative="${package_file#"$PKG_DIR/frontend/dist/"}"
  expected="$(sha256sum "$package_file" | awk '{print $1}')"
  actual="$(docker exec "$FRONTEND_CONTAINER" sha256sum "/usr/share/nginx/html/$relative" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || fail "container asset hash mismatch: $relative"
done < <(find "$PKG_DIR/frontend/dist" -type f -print0)

MAIN_REL="$(grep -o 'assets/index-[^"[:space:]]*\.js' "$PKG_DIR/frontend/dist/index.html" | head -1)"
ALARM_ASSET="$(find "$PKG_DIR/frontend/dist/assets" -maxdepth 1 -type f -name 'AlarmsPage-*.js' -printf '%f\n' | head -1)"
docker exec "$FRONTEND_CONTAINER" sh -lc \
  "grep -Fq 'Asia/Shanghai' '/usr/share/nginx/html/assets/$ALARM_ASSET'"

trap - ERR
MUTATED=0

echo "== 6. Keep only the latest three v2 backups =="
mapfile -t OLD_BACKUPS < <(
  find "$APP_DIR/backups" -mindepth 1 -maxdepth 1 -type d \
    -name 'alarm-list-full-datetime-increment-20260714-v2-*' -printf '%p\n' \
    | sort -r | tail -n +4
)
for old in "${OLD_BACKUPS[@]:-}"; do
  case "$old" in
    "$APP_DIR"/backups/alarm-list-full-datetime-increment-20260714-v2-*) rm -rf -- "$old" ;;
  esac
done

echo "DONE"
echo "Alarm Center format: YYYY-MM-DD HH:mm:ss (Asia/Shanghai)"
echo "All menu page chunks are present."
echo "Active entry: $MAIN_REL"
echo "Rollback backup: $BACKUP_DIR"
