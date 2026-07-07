# 2026-07-07 Realtime Overflow Sticky Patch Not Applied Confirmed

## 用户复查输出

服务器：`192.168.2.167`

用户执行检查：

```bash
set -e
cd /home/ai-river

echo "== 1. 检查目标源码是否已有补丁标记 =="
grep -RHE 'realtimeOverflowAlarmRows|syncRealtimeOverflowAlarmRows|keeps overflowed realtime messages' \
  /home/ai-river/river-watch/frontend/src/stores/platform.ts \
  /home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts || true

echo "== 2. 检查备份目录 =="
ls -td /home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-* 2>/dev/null | head -5 || true

echo "== 3. 检查前端容器 =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web' || true
```

输出：

```text
== 1. 检查目标源码是否已有补丁标记 ==
== 2. 检查备份目录 ==
== 3. 检查前端容器 ==
deploy-frontend-1     Up 32 seconds (healthy)   0.0.0.0:8081->80/tcp, [::]:8081->80/tcp
```

## 判断

补丁未应用完成。

依据：

- `/home/ai-river/river-watch/frontend/src/stores/platform.ts` 没有 `realtimeOverflowAlarmRows` 或 `syncRealtimeOverflowAlarmRows`。
- `/home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts` 没有新增回归测试标记。
- 没有生成 `/home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-*` 备份目录。
- 前端容器 healthy 只能说明当前前端服务在线，不能说明 sticky 补丁已应用。

## 下一步建议命令

因为脚本内部会使用 `sudo`，建议先刷新 sudo 凭据，再用日志方式重跑，避免 SSH 连接中断导致无法判断结果：

```bash
set -e
cd /home/ai-river/river-watch-realtime-overflow-sticky-increment-20260707

sudo -v
chmod +x scripts/apply-realtime-overflow-sticky-increment-20260707.sh

LOG="/home/ai-river/realtime-overflow-sticky-apply-$(date +%Y%m%d-%H%M%S).log"
nohup bash -lc 'APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-sticky-increment-20260707.sh' > "$LOG" 2>&1 &

echo "apply_pid=$!"
echo "log=$LOG"
sleep 8
tail -160 "$LOG"
```

应用后复查：

```bash
set -e

echo "== 1. marker =="
grep -RHE 'realtimeOverflowAlarmRows|syncRealtimeOverflowAlarmRows|keeps overflowed realtime messages' \
  /home/ai-river/river-watch/frontend/src/stores/platform.ts \
  /home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts

echo "== 2. backup =="
ls -td /home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-* | head -3

echo "== 3. frontend container =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web'

echo "== 4. page smoke =="
curl -fsS http://127.0.0.1:8081/ | head -5
```
