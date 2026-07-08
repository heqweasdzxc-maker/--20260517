# 2026-07-08 Full Backup Image Tar Missing And V3 Remediation

## 现场复核

包：

```text
/home/ai-river/river-watch-deliverable-20260708-101440.tar.gz
SHA256: edf8305244337090afd2a802878e3ea5780db99d8b9493ba649a45cdc4bfe468
```

复核结果：

```text
ls: 无法访问 '/home/ai-river/river-watch-deliverable-20260708-101440/docker/docker-images.tar': 没有那个文件或目录
```

请求镜像：

```text
bitnami/kafka:3.7
docker.m.daocloud.io/library/mysql:8.0
docker.m.daocloud.io/library/redis:7.2
docker.m.daocloud.io/minio/minio:latest
docker.m.daocloud.io/zlmediakit/zlmediakit:master
elasticsearch:8.13.0
emqx/emqx:5.6
minio/minio:latest
mysql:8.0
nacos/nacos-server:v2.3.2
redis:7.2
river-watch/backend:v3-20260624-190253
river-watch/frontend:v3-20260624-190253
tdengine/tdengine:3.2.3.0
zlmediakit/zlmediakit:master
```

本地缺失：

```text
MISSING bitnami/kafka:3.7
MISSING elasticsearch:8.13.0
MISSING emqx/emqx:5.6
MISSING minio/minio:latest
MISSING mysql:8.0
MISSING nacos/nacos-server:v2.3.2
MISSING redis:7.2
MISSING tdengine/tdengine:3.2.3.0
MISSING zlmediakit/zlmediakit:master
```

其中 `mysql:8.0`、`redis:7.2`、`minio/minio:latest`、`zlmediakit/zlmediakit:master` 可以由本机已有 DaoCloud 镜像打 tag 补齐；其余镜像需要拉取或确认是否为非必要服务。

## 判断

`river-watch-deliverable-20260708-101440.tar.gz` 不能作为完整离线交付包使用，因为它没有 `docker/docker-images.tar`。

## 建议执行：镜像补齐并重新打包

```bash
set -e

# 1. 用已有镜像补齐 compose 里可能引用的标准镜像名
for pair in \
  "docker.m.daocloud.io/library/mysql:8.0 mysql:8.0" \
  "docker.m.daocloud.io/library/redis:7.2 redis:7.2" \
  "docker.m.daocloud.io/minio/minio:latest minio/minio:latest" \
  "docker.m.daocloud.io/zlmediakit/zlmediakit:master zlmediakit/zlmediakit:master"
do
  src="${pair% *}"
  dst="${pair#* }"
  if docker image inspect "$src" >/dev/null 2>&1 && ! docker image inspect "$dst" >/dev/null 2>&1; then
    echo "tag $src -> $dst"
    docker tag "$src" "$dst"
  fi
done

# 2. 拉取真正缺失的镜像；如公网不通，再尝试 DaoCloud 前缀
pull_or_mirror() {
  img="$1"
  mirror="docker.m.daocloud.io/$img"
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "OK $img"
    return 0
  fi
  docker pull "$img" || { docker pull "$mirror" && docker tag "$mirror" "$img"; }
}

pull_or_mirror bitnami/kafka:3.7
pull_or_mirror elasticsearch:8.13.0
pull_or_mirror emqx/emqx:5.6
pull_or_mirror nacos/nacos-server:v2.3.2
pull_or_mirror tdengine/tdengine:3.2.3.0

# 3. 重新打包
sudo APP_DIR=/home/ai-river/river-watch /home/ai-river/backup-river-watch-deliverable-v2.sh
```

## 重新打包后必须复核

```bash
set -e
PKG="$(ls -td /home/ai-river/river-watch-deliverable-* | grep -v '\.tar\.gz' | head -1)"
ARCHIVE="$PKG.tar.gz"

echo "PKG=$PKG"
echo "ARCHIVE=$ARCHIVE"
sha256sum "$ARCHIVE"
cat "$ARCHIVE.sha256"
ls -lh "$PKG/docker/docker-images.tar"
tar -tf "$PKG/docker/docker-images.tar" >/dev/null && echo "docker-images.tar readable"

while read -r img; do
  [ -z "$img" ] && continue
  docker image inspect "$img" >/dev/null 2>&1 && echo "OK      $img" || echo "MISSING $img"
done < "$PKG/docker/images-to-save.txt"
```

## 后续改进

V2 脚本目前在 `docker save` 失败时仍继续生成最终包。后续应改成 V3 严格版：任何 compose/requested 镜像缺失或 `docker-images.tar` 未生成，都直接退出，避免误判为完整交付包。
