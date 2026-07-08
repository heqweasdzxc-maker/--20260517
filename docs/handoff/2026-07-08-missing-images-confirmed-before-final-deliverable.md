# 2026-07-08 Missing Images Confirmed Before Final Deliverable

## 现场复查

用户在 `192.168.2.167` 执行镜像检查：

```text
MISSING bitnami/kafka:3.7
MISSING elasticsearch:8.13.0
MISSING emqx/emqx:5.6
MISSING nacos/nacos-server:v2.3.2
MISSING tdengine/tdengine:3.2.3.0
OK      mysql:8.0
OK      redis:7.2
OK      minio/minio:latest
OK      zlmediakit/zlmediakit:master
```

## 判断

镜像别名补齐已经生效：

- `mysql:8.0`
- `redis:7.2`
- `minio/minio:latest`
- `zlmediakit/zlmediakit:master`

剩余 5 个是真正缺失镜像：

- `bitnami/kafka:3.7`
- `elasticsearch:8.13.0`
- `emqx/emqx:5.6`
- `nacos/nacos-server:v2.3.2`
- `tdengine/tdengine:3.2.3.0`

如果要求完整离线一键部署，必须补齐这 5 个镜像后重新打包，否则目标服务器必须联网拉取，不能算完整离线交付。

## 推荐离线补齐路径

在一台可联网、有 Docker 的机器上执行：

```bash
set -e
mkdir -p /tmp/river-watch-missing-images
cd /tmp/river-watch-missing-images

for img in \
  bitnami/kafka:3.7 \
  elasticsearch:8.13.0 \
  emqx/emqx:5.6 \
  nacos/nacos-server:v2.3.2 \
  tdengine/tdengine:3.2.3.0
do
  docker pull "$img"
done

docker save -o river-watch-missing-images-20260708.tar \
  bitnami/kafka:3.7 \
  elasticsearch:8.13.0 \
  emqx/emqx:5.6 \
  nacos/nacos-server:v2.3.2 \
  tdengine/tdengine:3.2.3.0

sha256sum river-watch-missing-images-20260708.tar > river-watch-missing-images-20260708.tar.sha256
ls -lh river-watch-missing-images-20260708.tar river-watch-missing-images-20260708.tar.sha256
```

将两个文件拷回 `192.168.2.167:/home/ai-river/` 后执行：

```bash
set -e
cd /home/ai-river
sha256sum -c river-watch-missing-images-20260708.tar.sha256
docker load -i river-watch-missing-images-20260708.tar

for img in \
  bitnami/kafka:3.7 \
  elasticsearch:8.13.0 \
  emqx/emqx:5.6 \
  nacos/nacos-server:v2.3.2 \
  tdengine/tdengine:3.2.3.0 \
  mysql:8.0 \
  redis:7.2 \
  minio/minio:latest \
  zlmediakit/zlmediakit:master
do
  docker image inspect "$img" >/dev/null 2>&1 && echo "OK      $img" || echo "MISSING $img"
done

sudo APP_DIR=/home/ai-river/river-watch /home/ai-river/backup-river-watch-deliverable-v2.sh
```

重新打包后必须确认：

```bash
set -e
PKG="$(ls -td /home/ai-river/river-watch-deliverable-* | grep -v '\.tar\.gz' | head -1)"
ARCHIVE="$PKG.tar.gz"

sha256sum "$ARCHIVE"
cat "$ARCHIVE.sha256"
ls -lh "$PKG/docker/docker-images.tar"
tar -tf "$PKG/docker/docker-images.tar" >/dev/null && echo "docker-images.tar readable"
```
