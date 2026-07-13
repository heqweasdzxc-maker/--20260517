Exit code: 0
Wall time: 0.1 seconds
Output:
#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-deploy-frontend-1}"
FRONTEND_URL="${FRONTEND_URL:-http://127.0.0.1:8081/}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backups/header-time-weather-increment-20260713-$TS"
EXPECTED_ENTRY="assets/index-BKSyKpIk.js"
NEW_ENTRY="assets/index-CZx9tmRJ.js"
EXPECTED_APPSHELL_SHA="edd6197ad9d1fca25b731b74d3b33cf85fe5465ad4c8267719080d5df56cffe7"
EXPECTED_STYLES_SHA="2f367e586e2900c636fc2dd0b9889a3b7efea96d35cdfe79ba9e9474188bf1ab"
NEW_APPSHELL_SHA="e8b756bd3c5abe0e822d33086fc5b8faebf50ecfbaf6c9ee89a033ab3c2a8789"
NEW_STYLES_SHA="6dbcd77fb2c56bffbd7880def5a1b415b7ab08e572f68f14f1d5fe015f7b0ada"
MUTATED=0

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

sha_of() {
  sha256sum "$1" | awk '{print $1}'
}

current_entry() {
  docker exec "$FRONTEND_CONTAINER" sh -lc \
    'grep -o "assets/index-[^\"]*\.js" /usr/share/nginx/html/index.html | head -1'
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
    cp -a "$BACKUP_DIR/host/frontend/src/components/AppShell.vue" \
      "$APP_DIR/frontend/src/components/AppShell.vue"
    cp -a "$BACKUP_DIR/host/frontend/src/styles.css" \
      "$APP_DIR/frontend/src/styles.css"
    restore_optional frontend/src/composables/useHeaderStatus.ts
    restore_optional frontend/src/__tests__/headerStatus.test.ts
    restore_optional frontend/src/__tests__/uiCommandCenter.test.ts
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

echo "== River Watch header/time/weather increment =="
echo "APP_DIR=$APP_DIR"
echo "PKG_DIR=$PKG_DIR"

[ -d "$APP_DIR/frontend/src/components" ] || fail "frontend source not found: $APP_DIR"
[ -d "$APP_DIR/frontend/dist" ] || fail "frontend dist not found: $APP_DIR/frontend/dist"
docker inspect "$FRONTEND_CONTAINER" >/dev/null 2>&1 || fail "container not found: $FRONTEND_CONTAINER"

echo "== 1. Verify package and production baseline =="
(cd "$PKG_DIR" && sha256sum -c SHA256SUMS)

ENTRY="$(current_entry)"
APP_SHA="$(sha_of "$APP_DIR/frontend/src/components/AppShell.vue")"
STYLE_SHA="$(sha_of "$APP_DIR/frontend/src/styles.css")"

if [ "$ENTRY" = "$NEW_ENTRY" ] && \
   [ "$APP_SHA" = "$NEW_APPSHELL_SHA" ] && \
   [ "$STYLE_SHA" = "$NEW_STYLES_SHA" ]; then
  echo "Patch already active; no files changed."
  curl -fsS -m 8 "$FRONTEND_URL" >/dev/null
  exit 0
fi

[ "$ENTRY" = "$EXPECTED_ENTRY" ] || \
  fail "unexpected frontend baseline: $ENTRY (expected $EXPECTED_ENTRY)"
[ "$APP_SHA" = "$EXPECTED_APPSHELL_SHA" ] || \
  fail "AppShell.vue baseline mismatch: $APP_SHA"
[ "$STYLE_SHA" = "$EXPECTED_STYLES_SHA" ] || \
  fail "styles.css baseline mismatch: $STYLE_SHA"

echo "== 2. Backup only changed source, dist and container assets =="
mkdir -p "$BACKUP_DIR/host/frontend/src/components" \
  "$BACKUP_DIR/host/frontend/src/composables" \
  "$BACKUP_DIR/host/frontend/src/__tests__" \
  "$BACKUP_DIR/container-html"
cp -a "$APP_DIR/frontend/src/components/AppShell.vue" \
  "$BACKUP_DIR/host/frontend/src/components/AppShell.vue"
cp -a "$APP_DIR/frontend/src/styles.css" \
  "$BACKUP_DIR/host/frontend/src/styles.css"
mkdir -p "$BACKUP_DIR/host/frontend/dist"
cp -a "$APP_DIR/frontend/dist/index.html" "$BACKUP_DIR/host/frontend/dist/index.html"
cp -a "$APP_DIR/frontend/dist/assets" "$BACKUP_DIR/host/frontend/dist/assets"

for relative in \
  frontend/src/composables/useHeaderStatus.ts \
  frontend/src/__tests__/headerStatus.test.ts \
  frontend/src/__tests__/uiCommandCenter.test.ts
do
  if [ -f "$APP_DIR/$relative" ]; then
    cp -a "$APP_DIR/$relative" "$BACKUP_DIR/host/$relative"
  else
    touch "$BACKUP_DIR/host/$relative.was-absent"
  fi
done

docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/index.html" \
  "$BACKUP_DIR/container-html/index.html"
docker cp "$FRONTEND_CONTAINER:/usr/share/nginx/html/assets" \
  "$BACKUP_DIR/container-html/assets"
echo "Rollback backup: $BACKUP_DIR"

echo "== 3. Apply compact source increment =="
MUTATED=1
install -m 0644 "$PKG_DIR/frontend/src/components/AppShell.vue" \
  "$APP_DIR/frontend/src/components/AppShell.vue"
install -m 0644 "$PKG_DIR/frontend/src/composables/useHeaderStatus.ts" \
  "$APP_DIR/frontend/src/composables/useHeaderStatus.ts"
install -m 0644 "$PKG_DIR/frontend/src/styles.css" \
  "$APP_DIR/frontend/src/styles.css"
install -m 0644 "$PKG_DIR/frontend/src/__tests__/headerStatus.test.ts" \
  "$APP_DIR/frontend/src/__tests__/headerStatus.test.ts"
install -m 0644 "$PKG_DIR/frontend/src/__tests__/uiCommandCenter.test.ts" \
  "$APP_DIR/frontend/src/__tests__/uiCommandCenter.test.ts"

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

echo "== 5. Verify active version and required markers =="
[ "$(current_entry)" = "$NEW_ENTRY" ] || fail "new frontend entry is not active"
[ "$(sha_of "$APP_DIR/frontend/src/components/AppShell.vue")" = "$NEW_APPSHELL_SHA" ] || \
  fail "new AppShell.vue hash mismatch"
[ "$(sha_of "$APP_DIR/frontend/src/styles.css")" = "$NEW_STYLES_SHA" ] || \
  fail "new styles.css hash mismatch"
grep -q '娲嬫渤鑲′唤娉楅槼鍩哄湴瀹夌幆閮? "$APP_DIR/frontend/src/components/AppShell.vue"
grep -q 'useHeaderStatus' "$APP_DIR/frontend/src/components/AppShell.vue"
grep -q 'api.open-meteo.com' "$APP_DIR/frontend/src/composables/useHeaderStatus.ts"
! grep -q 'title="绯荤粺閫氱煡"' "$APP_DIR/frontend/src/components/AppShell.vue"

trap - ERR
MUTATED=0

echo "== 6. Keep only the latest three backups for this increment =="
mapfile -t OLD_BACKUPS < <(
  find "$APP_DIR/backups" -mindepth 1 -maxdepth 1 -type d \
    -name 'header-time-weather-increment-20260713-*' -printf '%p\n' \
    | sort -r | tail -n +4
)
for old in "${OLD_BACKUPS[@]:-}"; do
  case "$old" in
    "$APP_DIR"/backups/header-time-weather-increment-20260713-*) rm -rf -- "$old" ;;
  esac
done

echo "DONE"
echo "Active entry: $NEW_ENTRY"
echo "Rollback backup: $BACKUP_DIR"
echo "Weather is fetched directly by each connected browser; the server needs no Internet access."

