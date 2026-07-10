# 2026-07-10 Realtime Overflow Backend Persist Increment

## 背景

用户反馈：`192.168.2.167` 服务器中，实时异常超过 15 条后的消息仍未进入告警中心。

## 根因判断

上一版 sticky overflow 修复只解决了前端内存层面的保留：

- 实时异常显示卡仍显示最新 15 条。
- 第 16 条及以后可以在 Pinia state 中暂时进入告警中心。

但它没有把溢出消息写入后端 `/api/alarm/alarms`，因此刷新页面、重新登录、或下一轮快照不再携带旧 detection 后，告警中心仍可能丢失这些消息。

## 本次修复

将“实时异常 FIFO 溢出进入告警中心”升级为后端持久化逻辑：

- 保留 `realtimeOverflowAlarmRows`，保证前端即时显示。
- 新增 `persistedRealtimeOverflowAlarmIds` 和 `persistingRealtimeOverflowAlarmIds`，避免重复写入。
- 新增 `persistRealtimeOverflowAlarmRows()`。
- `refresh()` 和 `refreshRuntimeSnapshot()` 中同步溢出消息后，调用持久化动作。
- 溢出消息调用 `/api/alarm/alarms`，payload 增加 `source: realtime-overflow`。
- 写入成功后同步插入 `state.alarms`，让告警中心立即按后端告警记录口径显示。

## 变更文件

源码只改：

- `frontend/src/stores/platform.ts`
- `frontend/src/__tests__/navBadges.test.ts`

增量包同时包含前端构建产物：

- `frontend/dist/index.html`
- `frontend/dist/assets/`

说明：`dist/assets/` 中包含 Vite 构建生成的现有页面懒加载 chunk，例如 Evidence/Workorder 页面 chunk。这是为了保证新 `index.html` 引用的前端资源完整，不代表修改这些功能源码。

## 验证

本地执行目录：`E:\river-video-app-V3.0\codex-handoff\frontend`

```bash
npm run test -- src/__tests__/navBadges.test.ts
npm run test
npm run build
```

结果：

- `navBadges.test.ts`: 13 tests passed。
- Full frontend suite: 37 files, 151 tests passed。
- Build completed successfully。
- 仅有既有构建 warning：第三方 `@vueuse/core` pure annotation 和大 chunk 提示。

## 增量包

```text
river-watch-realtime-overflow-persist-increment-20260710.zip
SHA256: 6a44f2e04fa9ebb0c06c0ce6a7e15e1c8a9f4791a17555423e858e08bcd8353f
```

结构复核：

- Zip entries: 49
- Required files missing: none
- Nested `frontend/dist/assets/assets`: 0
- Source entries changed: `frontend/src/stores/platform.ts`, `frontend/src/__tests__/navBadges.test.ts`

## 服务器应用命令

将 zip 上传到 `/home/ai-river` 后执行：

```bash
set -e
cd /home/ai-river
sha256sum river-watch-realtime-overflow-persist-increment-20260710.zip
unzip -o river-watch-realtime-overflow-persist-increment-20260710.zip
cd river-watch-realtime-overflow-persist-increment-20260710
chmod +x scripts/apply-realtime-overflow-persist-increment-20260710.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-persist-increment-20260710.sh
```

期望 SHA：

```text
6a44f2e04fa9ebb0c06c0ce6a7e15e1c8a9f4791a17555423e858e08bcd8353f  river-watch-realtime-overflow-persist-increment-20260710.zip
```

## 应用后复核

```bash
set -e

echo "== 1. marker =="
grep -RHE 'persistRealtimeOverflowAlarmRows|persistedRealtimeOverflowAlarmIds|realtime-overflow' \
  /home/ai-river/river-watch/frontend/src/stores/platform.ts \
  /home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts

echo "== 2. frontend =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web'
curl -fsS http://127.0.0.1:8081/ | head -5
```

## 业务验证口径

制造或等待实时异常超过 15 条后：

- 实时异常显示卡只保留最新 15 条。
- 被挤出的旧消息会 POST 到 `/api/alarm/alarms`。
- 告警中心列表中应出现这些旧消息。
- 刷新页面后，已写入后端的溢出消息仍应在告警中心可见。
