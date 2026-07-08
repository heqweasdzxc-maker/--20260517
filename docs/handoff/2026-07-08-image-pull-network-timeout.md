# 2026-07-08 Image Pull Network Timeout During Deliverable Backup

## 现场输出

用户在 `192.168.2.167` 执行镜像补齐命令时，前 4 个镜像别名补齐成功：

```text
tag docker.m.daocloud.io/library/mysql:8.0 -> mysql:8.0
tag docker.m.daocloud.io/library/redis:7.2 -> redis:7.2
tag docker.m.daocloud.io/minio/minio:latest -> minio/minio:latest
tag docker.m.daocloud.io/zlmediakit/zlmediakit:master -> zlmediakit/zlmediakit:master
```

随后拉取 Kafka 失败：

```text
Error response from daemon: failed to resolve reference "docker.io/bitnami/kafka:3.7": failed to do request: Head "https://registry-1.docker.io/v2/bitnami/kafka/manifests/3.7": dial tcp: lookup registry-1.docker.io: i/o timeout
Error response from daemon: failed to resolve reference "docker.m.daocloud.io/bitnami/kafka:3.7": failed to do request: Head "https://docker.m.daocloud.io/v2/bitnami/kafka/manifests/3.7": dial tcp: lookup docker.m.daocloud.io: i/o timeout
```

连接随后中断。

## 判断

- `mysql:8.0`、`redis:7.2`、`minio/minio:latest`、`zlmediakit/zlmediakit:master` 的 tag 已完成。
- `bitnami/kafka:3.7` 未拉取成功。
- 因为命令启用了 `set -e`，Kafka 拉取失败后，后续 `elasticsearch:8.13.0`、`emqx/emqx:5.6`、`nacos/nacos-server:v2.3.2`、`tdengine/tdengine:3.2.3.0` 和重新打包都没有执行。
- 失败原因是 DNS/网络超时，不是 Dockerfile 或备份包脚本本身的问题。

## 后续建议

如果服务器可以修复外网/DNS，继续拉取缺失镜像并重新打包。

如果服务器无法联网，需要在另一台可联网机器拉取缺失镜像后 `docker save`，再把 tar 拷回 `192.168.2.167` 做 `docker load`，最后重新打包。
