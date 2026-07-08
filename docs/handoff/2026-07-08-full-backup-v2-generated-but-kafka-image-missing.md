# 2026-07-08 Full Backup V2 Generated But Kafka Image Missing

## 服务器输出

用户在 `192.168.2.167` 执行 V2 完整交付备份脚本，输出：

```text
== 1. 导出数据库 ==
mysql container=deploy-mysql-1
mysqldump: [Warning] Using a password on the command line interface can be insecure.
== 2. 备份程序目录，排除运行态数据库目录 ==
== 3. 备份配置 ==
== 4. 备份 Docker 镜像 ==
Error response from daemon: No such image: bitnami/kafka:3.7
== 5. 生成一键安装脚本 ==
== 6. 生成校验和最终交付包 ==
edf8305244337090afd2a802878e3ea5780db99d8b9493ba649a45cdc4bfe468  /home/ai-river/river-watch-deliverable-20260708-101440.tar.gz
DONE: /home/ai-river/river-watch-deliverable-20260708-101440.tar.gz
```

## 判断

备份包已生成：

```text
/home/ai-river/river-watch-deliverable-20260708-101440.tar.gz
SHA256: edf8305244337090afd2a802878e3ea5780db99d8b9493ba649a45cdc4bfe468
```

但不能直接判断为“完整离线可交付包”。原因：

```text
Error response from daemon: No such image: bitnami/kafka:3.7
```

这表示 compose 或镜像清单引用了 `bitnami/kafka:3.7`，但源服务器本机 Docker image store 中没有该镜像。若目标服务器不能联网拉取，该包一键部署可能失败。

## 需要复核

在源服务器执行：

```bash
set -e
PKG_DIR="/home/ai-river/river-watch-deliverable-20260708-101440"
ARCHIVE="/home/ai-river/river-watch-deliverable-20260708-101440.tar.gz"

echo "== 1. archive checksum =="
sha256sum "$ARCHIVE"
cat "$ARCHIVE.sha256"

echo "== 2. docker image package exists =="
ls -lh "$PKG_DIR/docker/docker-images.tar" || true

echo "== 3. image list requested by package =="
cat "$PKG_DIR/docker/images-to-save.txt" || true

echo "== 4. check local availability of requested images =="
while read -r img; do
  [ -z "$img" ] && continue
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "OK     $img"
  else
    echo "MISSING $img"
  fi
done < "$PKG_DIR/docker/images-to-save.txt"

echo "== 5. inspect docker-images.tar =="
tar -tf "$PKG_DIR/docker/docker-images.tar" >/dev/null && echo "docker-images.tar readable" || echo "docker-images.tar missing or invalid"
```

## 修复建议

如果出现 `MISSING bitnami/kafka:3.7`：

- 若目标服务器可联网：可在交付说明中注明目标会拉取该镜像，但这不是纯离线交付。
- 若要求完整离线交付：需要先在源服务器拉取缺失镜像，再重新打包：

```bash
docker pull bitnami/kafka:3.7
sudo APP_DIR=/home/ai-river/river-watch /home/ai-river/backup-river-watch-deliverable-v2.sh
```

更稳妥的后续版本应在发现缺失镜像时直接退出，避免生成看似完整但目标环境无法部署的交付包。
