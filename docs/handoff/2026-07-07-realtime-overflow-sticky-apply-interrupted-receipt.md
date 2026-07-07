# 2026-07-07 Realtime Overflow Sticky Apply Interrupted Receipt

## 服务器回执

服务器：`192.168.2.167`

用户执行：

```bash
set -e
cd /home/ai-river
sha256sum river-watch-realtime-overflow-sticky-increment-20260707.zip
unzip -o river-watch-realtime-overflow-sticky-increment-20260707.zip
cd river-watch-realtime-overflow-sticky-increment-20260707
chmod +x scripts/apply-realtime-overflow-sticky-increment-20260707.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-sticky-increment-20260707.sh
```

## 已确认

SHA256 正确：

```text
905544dccd4a6da9a7aa533ecbaed536028429bcc702397c284c10307a9e3735  river-watch-realtime-overflow-sticky-increment-20260707.zip
```

Zip 已解压出增量文件，包括：

- `frontend/dist/index.html`
- `frontend/dist/assets/*`
- `frontend/src/stores/platform.ts`
- `frontend/src/__tests__/navBadges.test.ts`
- `scripts/apply-realtime-overflow-sticky-increment-20260707.sh`

## 异常点

回执中没有出现 apply 脚本自身输出，例如：

```text
== River Watch realtime overflow sticky incremental patch ==
== 1. Backup only changed files and deploy assets ==
...
Realtime overflow sticky incremental patch applied.
```

连接在脚本执行阶段附近关闭：

```text
Connection closed.
Disconnected from remote host(192.168.2.167) at 20:02:52.
```

因此不能确认补丁已经应用到 `/home/ai-river/river-watch` 或前端容器。

## 建议下一步

重新连接后先做应用状态检查：

```bash
set -e
cd /home/ai-river

echo "== 1. 解压目录和脚本是否存在 =="
ls -lah river-watch-realtime-overflow-sticky-increment-20260707/scripts/apply-realtime-overflow-sticky-increment-20260707.sh

echo "== 2. 检查目标源码是否已有 sticky markers =="
grep -RHE 'realtimeOverflowAlarmRows|syncRealtimeOverflowAlarmRows|keeps overflowed realtime messages' \
  /home/ai-river/river-watch/frontend/src/stores/platform.ts \
  /home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts || true

echo "== 3. 检查备份目录 =="
ls -td /home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-* 2>/dev/null | head -5 || true

echo "== 4. 检查前端容器 =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web' || true
```

如果第 2 步没有 marker，说明脚本未完成应用，使用带日志的方式重跑：

```bash
set -e
cd /home/ai-river/river-watch-realtime-overflow-sticky-increment-20260707
chmod +x scripts/apply-realtime-overflow-sticky-increment-20260707.sh
nohup bash -lc 'APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-sticky-increment-20260707.sh' \
  >/home/ai-river/realtime-overflow-sticky-apply-$(date +%Y%m%d-%H%M%S).log 2>&1 &
echo "apply_pid=$!"
sleep 5
ls -t /home/ai-river/realtime-overflow-sticky-apply-*.log | head -1 | xargs tail -120
```

如果第 2 步已经有 marker，则只需补充验证容器静态资源与页面是否更新。
