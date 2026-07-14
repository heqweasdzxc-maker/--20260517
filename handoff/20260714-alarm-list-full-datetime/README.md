# River Watch Alarm List Full Datetime Increment 20260714

## 变更内容

- 告警中心列表列名由“时间”调整为“日期时间”。
- 完整时间统一显示为 `YYYY-MM-DD HH:mm:ss`，时区固定为 `Asia/Shanghai`。
- 时间字段优先级保持为 `updatedAt -> createdAt -> time`。
- 仅有 `HH:mm:ss` 的历史兼容数据仍原样显示，不虚构日期。
- 默认排序仍使用数据库返回的原始持久化时间，最新告警在最上方。

## 影响范围

本包只更新告警中心前端源码、相关测试和已验证的前端生产静态文件。不会修改后端、数据库、AI 模型、推理服务或摄像头配置。

## 本地验证

- 前端全量测试：39 个测试文件、168 项测试全部通过。
- `npm run build`：通过。

## 部署

上传 ZIP 和外部 `.sha256` 文件到 `/home/ai-river` 后执行：

```bash
set -e
cd /home/ai-river
sha256sum -c river-watch-alarm-list-full-datetime-increment-20260714.zip.sha256
rm -rf river-watch-alarm-list-full-datetime-increment-20260714
unzip -o river-watch-alarm-list-full-datetime-increment-20260714.zip
cd river-watch-alarm-list-full-datetime-increment-20260714
bash -n scripts/apply-alarm-list-full-datetime-increment-20260714.sh
sudo -v

LOG="/home/ai-river/alarm-list-full-datetime-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env \
  APP_DIR=/home/ai-river/river-watch \
  FRONTEND_CONTAINER=deploy-frontend-1 \
  bash scripts/apply-alarm-list-full-datetime-increment-20260714.sh \
  > "$LOG" 2>&1 &

echo "pid=$!"
echo "log=$LOG"
sleep 8
tail -200 "$LOG"
```

日志出现 `DONE` 表示部署成功。脚本只重启 `deploy-frontend-1`，失败时自动恢复本次部署前的源码和容器静态文件。
