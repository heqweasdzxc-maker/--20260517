# 2026-07-08 Full Backup And One-click Deploy Commands

目的：从 `192.168.2.167` 导出 River Watch 系统完整可交付包，包含程序、配置、数据库 dump、Docker 镜像、systemd 文件、校验文件和目标服务器一键安装脚本。

## 源服务器执行

在 `192.168.2.167` 上执行。默认应用目录为 `/home/ai-river/river-watch`。

```bash
cat > /home/ai-river/backup-river-watch-deliverable.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
TS="$(date +%Y%m%d-%H%M%S)"
NAME="river-watch-deliverable-$TS"
BASE="/home/ai-river/$NAME"
OUT="/home/ai-river/$NAME.tar.gz"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

mkdir -p "$BASE"/{app,etc,opt,systemd,docker,db,logs,scripts,meta}

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$BASE/logs/backup.log"; }

log "APP_DIR=$APP_DIR"
log "BASE=$BASE"

log "1. archive application"
if [ ! -d "$APP_DIR" ]; then echo "ERROR: APP_DIR not found: $APP_DIR" >&2; exit 1; fi
$SUDO tar -C "$(dirname "$APP_DIR")" \
  --exclude='river-watch/backups' \
  --exclude='river-watch/node_modules' \
  --exclude='river-watch/frontend/node_modules' \
  --exclude='river-watch/backend/node_modules' \
  --exclude='river-watch/.git' \
  --exclude='river-watch/**/*.log' \
  -czf "$BASE/app/river-watch.tar.gz" "$(basename "$APP_DIR")"

log "2. collect configs"
[ -d /etc/river-watch ] && $SUDO tar -C /etc -czf "$BASE/etc/river-watch-etc.tar.gz" river-watch || true
[ -d /opt/river-watch ] && $SUDO tar -C /opt -czf "$BASE/opt/river-watch-opt.tar.gz" river-watch || true
$SUDO bash -lc "ls /etc/systemd/system/*river* /etc/systemd/system/*watch* 2>/dev/null" > "$BASE/systemd/systemd-file-list.txt" || true
while read -r f; do [ -f "$f" ] && $SUDO cp -a "$f" "$BASE/systemd/"; done < "$BASE/systemd/systemd-file-list.txt"

log "3. collect docker metadata"
(docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true) > "$BASE/docker/containers.txt"
(docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' || true) > "$BASE/docker/images.txt"
if [ -f "$APP_DIR/docker-compose.yml" ] || [ -f "$APP_DIR/compose.yml" ] || [ -f "$APP_DIR/docker-compose.yaml" ]; then
  (cd "$APP_DIR" && docker compose config > "$BASE/docker/docker-compose.rendered.yml" 2>/dev/null || true)
  (cd "$APP_DIR" && docker compose config --images 2>/dev/null || true) | sort -u > "$BASE/docker/compose-images.txt"
fi
(docker ps --format '{{.Image}}' || true; cat "$BASE/docker/compose-images.txt" 2>/dev/null || true) | sed '/^$/d' | sort -u > "$BASE/docker/images-to-save.txt"
if [ -s "$BASE/docker/images-to-save.txt" ]; then
  log "4. save docker images"
  docker save -o "$BASE/docker/docker-images.tar" $(cat "$BASE/docker/images-to-save.txt")
else
  log "4. no docker images found to save"
fi

log "5. dump databases"
pg_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /postgres|postgis/{print $1; exit}' || true)"
if [ -n "$pg_ctn" ]; then
  log "postgres container=$pg_ctn"
  docker exec "$pg_ctn" sh -lc 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' > "$BASE/db/postgres_dumpall.sql"
fi
mysql_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}' || true)"
if [ -n "$mysql_ctn" ]; then
  log "mysql container=$mysql_ctn"
  docker exec "$mysql_ctn" sh -lc 'mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}" --all-databases --single-transaction --routines --events --triggers' > "$BASE/db/mysql_all.sql" || true
fi
mongo_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mongo/{print $1; exit}' || true)"
if [ -n "$mongo_ctn" ]; then
  log "mongo container=$mongo_ctn"
  docker exec "$mongo_ctn" sh -lc 'mongodump --archive' > "$BASE/db/mongo.archive" || true
fi
find "$APP_DIR" -type f \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -print > "$BASE/db/sqlite-files.txt" || true
if [ -s "$BASE/db/sqlite-files.txt" ]; then
  mkdir -p "$BASE/db/sqlite"
  while read -r f; do cp -a "$f" "$BASE/db/sqlite/$(basename "$f")"; done < "$BASE/db/sqlite-files.txt"
fi

log "6. archive likely related docker volumes"
mkdir -p "$BASE/docker/volumes"
docker volume ls --format '{{.Name}}' | grep -Ei 'river|watch|deploy|postgres|postgis|mysql|maria|mongo|redis|minio|media|upload|alarm|ai' > "$BASE/docker/volumes.txt" || true
while read -r vol; do
  [ -z "$vol" ] && continue
  mp="$(docker volume inspect -f '{{.Mountpoint}}' "$vol" 2>/dev/null || true)"
  [ -d "$mp" ] || continue
  safe="$(echo "$vol" | tr '/:' '__')"
  log "volume $vol -> $safe.tgz"
  $SUDO tar -C "$mp" -czf "$BASE/docker/volumes/$safe.tgz" . || true
done < "$BASE/docker/volumes.txt"

log "7. write installer"
cat > "$BASE/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/ai-river/river-watch}"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log(){ echo "[$(date '+%F %T')] $*"; }

command -v docker >/dev/null || { echo "ERROR: docker not installed" >&2; exit 1; }
docker compose version >/dev/null || { echo "ERROR: docker compose plugin not installed" >&2; exit 1; }

log "1. install app to $APP_DIR"
$SUDO mkdir -p "$(dirname "$APP_DIR")"
if [ -d "$APP_DIR" ]; then
  $SUDO mv "$APP_DIR" "$APP_DIR.bak-$(date +%Y%m%d-%H%M%S)"
fi
$SUDO tar -C "$(dirname "$APP_DIR")" -xzf "$PKG_DIR/app/river-watch.tar.gz"

log "2. restore /etc and /opt configs"
[ -f "$PKG_DIR/etc/river-watch-etc.tar.gz" ] && $SUDO tar -C /etc -xzf "$PKG_DIR/etc/river-watch-etc.tar.gz" || true
[ -f "$PKG_DIR/opt/river-watch-opt.tar.gz" ] && $SUDO tar -C /opt -xzf "$PKG_DIR/opt/river-watch-opt.tar.gz" || true
if [ -d "$PKG_DIR/systemd" ]; then
  for f in "$PKG_DIR"/systemd/*.service "$PKG_DIR"/systemd/*.timer; do
    [ -f "$f" ] && $SUDO cp -a "$f" /etc/systemd/system/
  done
  $SUDO systemctl daemon-reload || true
fi

log "3. load docker images"
[ -f "$PKG_DIR/docker/docker-images.tar" ] && docker load -i "$PKG_DIR/docker/docker-images.tar" || true

log "4. start compose services"
cd "$APP_DIR"
docker compose up -d
sleep 20

log "5. restore database dumps on clean target"
pg_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /postgres|postgis/{print $1; exit}' || true)"
if [ -n "$pg_ctn" ] && [ -s "$PKG_DIR/db/postgres_dumpall.sql" ]; then
  user="$(docker exec "$pg_ctn" sh -lc 'echo ${POSTGRES_USER:-postgres}')"
  cat "$PKG_DIR/db/postgres_dumpall.sql" | docker exec -i "$pg_ctn" psql -U "$user" -d postgres || true
fi
mysql_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mysql|mariadb/{print $1; exit}' || true)"
if [ -n "$mysql_ctn" ] && [ -s "$PKG_DIR/db/mysql_all.sql" ]; then
  docker exec -i "$mysql_ctn" sh -lc 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}"' < "$PKG_DIR/db/mysql_all.sql" || true
fi
mongo_ctn="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'BEGIN{IGNORECASE=1} /mongo/{print $1; exit}' || true)"
if [ -n "$mongo_ctn" ] && [ -s "$PKG_DIR/db/mongo.archive" ]; then
  cat "$PKG_DIR/db/mongo.archive" | docker exec -i "$mongo_ctn" sh -lc 'mongorestore --archive --drop' || true
fi

log "6. restart services"
docker compose up -d
$SUDO systemctl enable --now river-ai-group@river-a river-ai-group@river-b river-ai-group@structure 2>/dev/null || true

log "7. smoke check"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -fsS http://127.0.0.1:8081/ | head -5 || true
log "install complete"
INSTALL
chmod +x "$BASE/install.sh"

log "8. write manifest and checksums"
{
  echo "name=$NAME"
  echo "created_at=$(date -Is)"
  echo "source_host=$(hostname)"
  echo "app_dir=$APP_DIR"
  echo "postgres_container=${pg_ctn:-}"
  echo "mysql_container=${mysql_ctn:-}"
  echo "mongo_container=${mongo_ctn:-}"
  echo "archive=$OUT"
} > "$BASE/meta/MANIFEST.txt"
(cd "$BASE" && find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

log "9. create final archive"
tar -C /home/ai-river -czf "$OUT" "$NAME"
sha256sum "$OUT" | tee "$OUT.sha256"
log "DONE: $OUT"
BASH

chmod +x /home/ai-river/backup-river-watch-deliverable.sh
sudo APP_DIR=/home/ai-river/river-watch /home/ai-river/backup-river-watch-deliverable.sh
ls -lh /home/ai-river/river-watch-deliverable-*.tar.gz /home/ai-river/river-watch-deliverable-*.tar.gz.sha256
```

## 目标服务器执行

将 `river-watch-deliverable-*.tar.gz` 和 `.sha256` 复制到目标服务器 `/home/ai-river/` 后执行：

```bash
set -e
cd /home/ai-river
sha256sum -c river-watch-deliverable-*.tar.gz.sha256
PKG="$(ls -t river-watch-deliverable-*.tar.gz | head -1)"
tar -xzf "$PKG"
DIR="${PKG%.tar.gz}"
cd "$DIR"
sudo APP_DIR=/home/ai-river/river-watch ./install.sh
```

## 验收检查

```bash
set -e
cd /home/ai-river/river-watch

echo "== docker =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo "== frontend =="
curl -fsS http://127.0.0.1:8081/ | head -5

echo "== ai systemd =="
systemctl is-active river-ai-group@river-a river-ai-group@river-b river-ai-group@structure || true

echo "== db containers =="
docker ps --format '{{.Names}} {{.Image}}' | grep -Ei 'postgres|postgis|mysql|mariadb|mongo|redis' || true
```

## 注意事项

- 目标服务器需先安装 Docker、Docker Compose plugin。
- 若要求 GPU 推理，目标服务器还需 NVIDIA 驱动、CUDA/NVIDIA Container Toolkit，并且 Docker 能看到 GPU。
- 摄像头 RTSP 地址、授权、内网 DNS、固定 IP、端口映射可能需要按目标现场调整。
- 该包包含 Docker 镜像，文件可能较大。若目标服务器可联网，也可不使用 `docker save/load`，但交付稳定性会降低。
