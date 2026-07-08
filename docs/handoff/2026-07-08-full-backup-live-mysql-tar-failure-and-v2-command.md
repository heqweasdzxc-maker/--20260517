# 2026-07-08 Full Backup Live MySQL Tar Failure And V2 Command

## 现场现象

用户在 `192.168.2.167` 执行完整交付备份脚本时，第一步程序目录打包失败：

```text
== 1. 备份程序目录 ==
tar: river-watch/deploy/mysql/binlog.000035: 在我们读入文件时文件发生了变化
tar: river-watch/deploy/mysql/river_watch/rw_ai_event.ibd: 在我们读入文件时文件发生了变化
tar: river-watch/deploy/mysql/river_watch/rw_alarm.ibd: 在我们读入文件时文件发生了变化
```

## 判断

这不是数据库损坏，而是脚本把正在运行的 MySQL 物理数据目录纳入了 `tar`。MySQL 运行期间 `binlog.*`、`*.ibd` 会持续变化，`tar` 因 `set -e` 退出。

完整可交付备份应采用：

- 程序目录：打包源码、配置、compose、前端构建产物、脚本等。
- 数据库：使用逻辑 dump，例如 `mysqldump`、`pg_dumpall`。
- 运行态数据库物理目录：从程序包 tar 中排除，避免不一致和备份中断。

## 修正策略

V2 备份脚本在程序目录打包时排除：

- `river-watch/deploy/mysql`
- `river-watch/deploy/postgres`
- `river-watch/deploy/postgresql`
- `river-watch/deploy/mariadb`
- `river-watch/deploy/mongo`
- `river-watch/deploy/redis`
- `river-watch/deploy/minio`
- `river-watch/data/mysql`
- `river-watch/data/postgres`
- `river-watch/data/postgresql`
- `river-watch/data/mariadb`
- `river-watch/data/mongo`
- `river-watch/data/redis`
- `river-watch/data/minio`

数据库通过 dump 单独导出。

## 源服务器 V2 命令

```bash
rm -f /home/ai-river/backup-river-watch-deliverable.sh
cat > /home/ai-river/backup-river-watch-deliverable-v2.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
TS="$(date +%Y%m%d-%H%M%S)"
NAME="river-watch-deliverable-$TS"
BASE="/home/ai-river/$NAME"
OUT="/home/ai-river/$NAME.tar.gz"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

mkdir -p "$BASE"/{app,etc,opt,systemd,docker,db,logs,meta}
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$BASE/logs/backup.log"; }

log "APP_DIR=$APP_DIR"
[ -d "$APP_DIR" ] || { echo "ERROR: APP_DIR not found: $APP_DIR" >&2; exit 1; }

log "1. dump databases first"
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

log "2. archive application, excluding live database/runtime data"
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

log "3. collect configs"
[ -d /etc/river-watch ] && $SUDO tar -C /etc -czf "$BASE/etc/river-watch-etc.tar.gz" river-watch || true
[ -d /opt/river-watch ] && $SUDO tar -C /opt -czf "$BASE/opt/river-watch-opt.tar.gz" river-watch || true
$SUDO bash -lc "cp -a /etc/systemd/system/*river* /etc/systemd/system/*watch* '$BASE/systemd/' 2>/dev/null || true"

log "4. save docker images"
(docker ps --format '{{.Image}}' || true; cd "$APP_DIR" && docker compose config --images 2>/dev/null || true) | sed '/^$/d' | sort -u > "$BASE/docker/images-to-save.txt"
if [ -s "$BASE/docker/images-to-save.txt" ]; then
  docker save -o "$BASE/docker/docker-images.tar" $(cat "$BASE/docker/images-to-save.txt")
fi
(docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true) > "$BASE/docker/containers.txt"
(cd "$APP_DIR" && docker compose config > "$BASE/docker/docker-compose.rendered.yml" 2>/dev/null || true)

log "5. write one-click installer"
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
[ -f "$PKG_DIR/docker/docker-images.tar" ] && docker load -i "$PKG_DIR/docker/docker-images.tar" || true

cd "$APP_DIR"
docker compose up -d
sleep 25

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

log "6. manifest and checksum"
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

chmod +x /home/ai-river/backup-river-watch-deliverable-v2.sh
sudo APP_DIR=/home/ai-river/river-watch /home/ai-river/backup-river-watch-deliverable-v2.sh
```
