# 2026-07-08 Strict Current System Migration Package Command

用户要求：将当前所有更新后的 `192.168.2.167` 系统完整打包，用于迁移测试。

## 当前前置状态

已知最新业务修复应包含 realtime overflow sticky marker：

- `realtimeOverflowAlarmRows`
- `syncRealtimeOverflowAlarmRows`

完整离线迁移包必须包含：

- 当前 `/home/ai-river/river-watch` 程序目录
- `/etc/river-watch` 配置
- `/opt/river-watch` AI pipeline 等配置/脚本
- systemd river/watch 服务文件
- MySQL/Postgres/Mongo 等数据库逻辑 dump
- Docker Compose 需要的全部 Docker 镜像 tar
- 一键安装脚本
- SHA256 校验

## 严格打包命令

在 `192.168.2.167` 执行：

```bash
cat > /home/ai-river/backup-river-watch-deliverable-v3-strict.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
TS="$(date +%Y%m%d-%H%M%S)"
NAME="river-watch-deliverable-current-$TS"
BASE="/home/ai-river/$NAME"
OUT="/home/ai-river/$NAME.tar.gz"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

mkdir -p "$BASE"/{app,etc,opt,systemd,docker,db,logs,meta}
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$BASE/logs/backup.log"; }

log "APP_DIR=$APP_DIR"
[ -d "$APP_DIR" ] || { echo "ERROR: APP_DIR not found: $APP_DIR" >&2; exit 1; }

log "0. verify latest patch markers"
grep -RHE 'realtimeOverflowAlarmRows|syncRealtimeOverflowAlarmRows' \
  "$APP_DIR/frontend/src/stores/platform.ts" >/dev/null || {
  echo "ERROR: latest realtime overflow sticky patch marker not found" >&2
  exit 1
}

log "1. collect required docker images"
(
  docker ps --format '{{.Image}}' || true
  cd "$APP_DIR" && docker compose config --images 2>/dev/null || true
) | sed '/^$/d' | sort -u > "$BASE/docker/images-to-save.txt"

log "2. verify docker images exist locally"
missing=0
while read -r img; do
  [ -z "$img" ] && continue
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "OK      $img" | tee -a "$BASE/docker/image-check.txt"
  else
    echo "MISSING $img" | tee -a "$BASE/docker/image-check.txt"
    missing=1
  fi
done < "$BASE/docker/images-to-save.txt"
if [ "$missing" -ne 0 ]; then
  echo "ERROR: missing docker images; package is not complete for offline migration." >&2
  echo "See: $BASE/docker/image-check.txt" >&2
  exit 2
fi

log "3. dump databases"
mysql_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}' || true)"
if [ -n "$mysql_ctn" ]; then
  log "mysql container=$mysql_ctn"
  docker exec "$mysql_ctn" sh -lc 'mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}" --all-databases --single-transaction --routines --events --triggers --hex-blob --default-character-set=utf8mb4' > "$BASE/db/mysql_all.sql"
fi

pg_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /postgres|postgis/{print $1; exit}' || true)"
if [ -n "$pg_ctn" ]; then
  log "postgres container=$pg_ctn"
  docker exec "$pg_ctn" sh -lc 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' > "$BASE/db/postgres_dumpall.sql"
fi

mongo_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mongo/{print $1; exit}' || true)"
if [ -n "$mongo_ctn" ]; then
  log "mongo container=$mongo_ctn"
  docker exec "$mongo_ctn" sh -lc 'mongodump --archive' > "$BASE/db/mongo.archive" || true
fi

log "4. archive application excluding live runtime db data"
$SUDO tar -C "$(dirname "$APP_DIR")" \
  --warning=no-file-changed \
  --ignore-failed-read \
  --exclude='river-watch/backups' \
  --exclude='river-watch/node_modules' \
  --exclude='river-watch/frontend/node_modules' \
  --exclude='river-watch/backend/node_modules' \
  --exclude='river-watch/.git' \
  --exclude='river-watch/**/*.log' \
  --exclude='river-watch/deploy/mysql' \
  --exclude='river-watch/deploy/postgres' \
  --exclude='river-watch/deploy/postgresql' \
  --exclude='river-watch/deploy/mariadb' \
  --exclude='river-watch/deploy/mongo' \
  --exclude='river-watch/deploy/redis' \
  --exclude='river-watch/deploy/minio' \
  --exclude='river-watch/data/mysql' \
  --exclude='river-watch/data/postgres' \
  --exclude='river-watch/data/postgresql' \
  --exclude='river-watch/data/mariadb' \
  --exclude='river-watch/data/mongo' \
  --exclude='river-watch/data/redis' \
  --exclude='river-watch/data/minio' \
  -czf "$BASE/app/river-watch.tar.gz" "$(basename "$APP_DIR")"

log "5. collect configs and service files"
[ -d /etc/river-watch ] && $SUDO tar -C /etc -czf "$BASE/etc/river-watch-etc.tar.gz" river-watch || true
[ -d /opt/river-watch ] && $SUDO tar -C /opt -czf "$BASE/opt/river-watch-opt.tar.gz" river-watch || true
$SUDO bash -lc "cp -a /etc/systemd/system/*river* /etc/systemd/system/*watch* '$BASE/systemd/' 2>/dev/null || true"
(docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true) > "$BASE/docker/containers.txt"
(cd "$APP_DIR" && docker compose config > "$BASE/docker/docker-compose.rendered.yml" 2>/dev/null || true)

log "6. save docker images"
docker save -o "$BASE/docker/docker-images.tar" $(cat "$BASE/docker/images-to-save.txt")
tar -tf "$BASE/docker/docker-images.tar" >/dev/null

log "7. write one-click installer"
cat > "$BASE/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v docker >/dev/null || { echo "ERROR: docker not installed" >&2; exit 1; }
docker compose version >/dev/null || { echo "ERROR: docker compose plugin not installed" >&2; exit 1; }

$SUDO mkdir -p "$(dirname "$APP_DIR")"
[ -d "$APP_DIR" ] && $SUDO mv "$APP_DIR" "$APP_DIR.bak-$(date +%Y%m%d-%H%M%S)"
$SUDO tar -C "$(dirname "$APP_DIR")" -xzf "$PKG_DIR/app/river-watch.tar.gz"
[ -f "$PKG_DIR/etc/river-watch-etc.tar.gz" ] && $SUDO tar -C /etc -xzf "$PKG_DIR/etc/river-watch-etc.tar.gz" || true
[ -f "$PKG_DIR/opt/river-watch-opt.tar.gz" ] && $SUDO tar -C /opt -xzf "$PKG_DIR/opt/river-watch-opt.tar.gz" || true
$SUDO cp -a "$PKG_DIR"/systemd/* /etc/systemd/system/ 2>/dev/null || true
$SUDO systemctl daemon-reload || true

docker load -i "$PKG_DIR/docker/docker-images.tar"
cd "$APP_DIR"
docker compose up -d
sleep 30

mysql_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}' || true)"
if [ -n "$mysql_ctn" ] && [ -s "$PKG_DIR/db/mysql_all.sql" ]; then
  docker exec -i "$mysql_ctn" sh -lc 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}"' < "$PKG_DIR/db/mysql_all.sql" || true
fi
pg_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /postgres|postgis/{print $1; exit}' || true)"
if [ -n "$pg_ctn" ] && [ -s "$PKG_DIR/db/postgres_dumpall.sql" ]; then
  user="$(docker exec "$pg_ctn" sh -lc 'echo ${POSTGRES_USER:-postgres}')"
  cat "$PKG_DIR/db/postgres_dumpall.sql" | docker exec -i "$pg_ctn" psql -U "$user" -d postgres || true
fi
mongo_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mongo/{print $1; exit}' || true)"
if [ -n "$mongo_ctn" ] && [ -s "$PKG_DIR/db/mongo.archive" ]; then
  cat "$PKG_DIR/db/mongo.archive" | docker exec -i "$mongo_ctn" sh -lc 'mongorestore --archive --drop' || true
fi

docker compose up -d
$SUDO systemctl enable --now river-ai-group@river-a river-ai-group@river-b river-ai-group@structure 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -fsS http://127.0.0.1:8081/ | head -5 || true
echo "install complete"
INSTALL
chmod +x "$BASE/install.sh"

log "8. manifest and checksums"
{
  echo "name=$NAME"
  echo "created_at=$(date -Is)"
  echo "source_host=$(hostname)"
  echo "app_dir=$APP_DIR"
  echo "mysql_container=${mysql_ctn:-}"
  echo "postgres_container=${pg_ctn:-}"
  echo "mongo_container=${mongo_ctn:-}"
} > "$BASE/meta/MANIFEST.txt"
(cd "$BASE" && find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

tar -C /home/ai-river -czf "$OUT" "$NAME"
sha256sum "$OUT" | tee "$OUT.sha256"
log "DONE: $OUT"
BASH

chmod +x /home/ai-river/backup-river-watch-deliverable-v3-strict.sh
sudo APP_DIR=/home/ai-river/river-watch /home/ai-river/backup-river-watch-deliverable-v3-strict.sh
```

## 如果严格脚本提示缺失镜像

先补齐缺失镜像，再重跑脚本。已知此前缺失：

```text
bitnami/kafka:3.7
elasticsearch:8.13.0
emqx/emqx:5.6
nacos/nacos-server:v2.3.2
tdengine/tdengine:3.2.3.0
```

## 生成后复核

```bash
set -e
PKG="$(ls -td /home/ai-river/river-watch-deliverable-current-* | grep -v '\.tar\.gz' | head -1)"
ARCHIVE="$PKG.tar.gz"

echo "PKG=$PKG"
echo "ARCHIVE=$ARCHIVE"
sha256sum "$ARCHIVE"
cat "$ARCHIVE.sha256"
ls -lh "$PKG/docker/docker-images.tar"
tar -tf "$PKG/docker/docker-images.tar" >/dev/null && echo "docker-images.tar readable"
cat "$PKG/docker/image-check.txt"
```
