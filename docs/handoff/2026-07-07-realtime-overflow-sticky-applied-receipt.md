# 2026-07-07 Realtime Overflow Sticky Patch Applied Receipt

## 服务器

`192.168.2.167`

## 应用命令

用户使用日志化方式执行：

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

日志文件：

```text
/home/ai-river/realtime-overflow-sticky-apply-20260707-200731.log
```

## 应用日志摘要

```text
== River Watch realtime overflow sticky incremental patch ==
APP_DIR=/home/ai-river/river-watch
PKG_DIR=/home/ai-river/river-watch-realtime-overflow-sticky-increment-20260707
== 1. Backup only changed files and deploy assets ==
Backup saved: /home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-20260707-200731
== 2. Apply incremental source files ==
== 3. Apply incremental frontend build output ==
== 4. Hot update frontend container assets only ==
Frontend container: deploy-frontend-1
```

## 复查结果

### Marker

目标源码已包含 sticky patch 标记：

```text
/home/ai-river/river-watch/frontend/src/stores/platform.ts:  realtimeOverflowAlarmRows: Alarm[];
/home/ai-river/river-watch/frontend/src/stores/platform.ts:    ...(state.realtimeOverflowAlarmRows || []),
/home/ai-river/river-watch/frontend/src/stores/platform.ts:    realtimeOverflowAlarmRows: [] as Alarm[],
/home/ai-river/river-watch/frontend/src/stores/platform.ts:        this.syncRealtimeOverflowAlarmRows();
/home/ai-river/river-watch/frontend/src/stores/platform.ts:        this.syncRealtimeOverflowAlarmRows();
/home/ai-river/river-watch/frontend/src/stores/platform.ts:      this.realtimeOverflowAlarmRows = [];
/home/ai-river/river-watch/frontend/src/stores/platform.ts:    syncRealtimeOverflowAlarmRows() {
/home/ai-river/river-watch/frontend/src/stores/platform.ts:      if (!overflowRows.length) return this.realtimeOverflowAlarmRows;
/home/ai-river/river-watch/frontend/src/stores/platform.ts:      this.realtimeOverflowAlarmRows = uniqueAlarmsById([
/home/ai-river/river-watch/frontend/src/stores/platform.ts:        ...this.realtimeOverflowAlarmRows,
/home/ai-river/river-watch/frontend/src/stores/platform.ts:      return this.realtimeOverflowAlarmRows;
/home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts:  it('keeps overflowed realtime messages in the alarm center after the next snapshot drops them from detections', () => {
/home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts:    store.syncRealtimeOverflowAlarmRows();
```

### 备份目录

```text
/home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-20260707-200731
```

### 前端容器

刚重启后状态：

```text
deploy-frontend-1     Up 7 seconds (health: starting)   0.0.0.0:8081->80/tcp, [::]:8081->80/tcp
```

### 页面 smoke

`curl -fsS http://127.0.0.1:8081/ | head -5` 返回 HTML 首页：

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
```

## 判断

补丁已经应用到目标系统，前端静态页面可访问。容器复查时处于刚重启后的 `health: starting`，建议 30 秒后再确认 healthy。

## 后续验证命令

```bash
set -e
sleep 30

echo "== frontend health =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web'

echo "== latest apply log tail =="
tail -160 /home/ai-river/realtime-overflow-sticky-apply-20260707-200731.log

echo "== frontend static smoke =="
curl -fsS http://127.0.0.1:8081/ | head -5
```

业务侧还需要继续观察真实告警：当实时异常超过 15 条后，被挤出的旧消息应进入告警中心并保留。
