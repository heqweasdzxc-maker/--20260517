# 2026-07-07 Realtime Overflow Sticky Increment

## 背景

用户反馈：实时异常消息仍然没有进入告警中心。此前的溢出修复只把当前快照中超过 15 条的实时异常计算为告警中心候选项，但该逻辑没有持久化。

## 根因

实时异常来源于 `camera.detections` 的当前快照。旧逻辑只按当前快照拆分：

- 前 15 条显示在实时异常显示卡。
- 第 16 条及以后显示到告警中心。

问题是：如果下一次快照不再携带第 16 条旧 detection，该消息会同时从实时异常和告警中心消失。也就是说，溢出进入告警中心的消息没有被保留。

## 增量修复

仅修改前端 store 和对应测试：

- `frontend/src/stores/platform.ts`
- `frontend/src/__tests__/navBadges.test.ts`

核心变化：

- 新增 `realtimeOverflowAlarmRows` 状态，用于保留已经从实时异常 FIFO 溢出的消息。
- 新增 `syncRealtimeOverflowAlarmRows()`。
- `refresh()` 和 `refreshRuntimeSnapshot()` 后同步溢出消息。
- 告警中心合并 `overflowRealtimeRowsForState(state)` 与 `state.realtimeOverflowAlarmRows`。
- 登出时清空 `realtimeOverflowAlarmRows`。

## 行为口径

- 实时异常显示卡：只展示当前最新 15 条实时异常。
- 告警中心：接收并保留从实时异常 FIFO 溢出的消息。
- 即使下一次 `camera.detections` 快照已经不含旧 detection，该旧消息也不会从告警中心消失。
- 告警角标与告警中心当前未归档消息保持同步。

## 验证

已在本地 `E:\river-video-app-V3.0\codex-handoff\frontend` 执行：

```bash
npm run test -- src/__tests__/navBadges.test.ts
npm run test
npm run build
```

结果：

- `navBadges.test.ts`: 1 个测试文件，12 条测试通过。
- 全量前端测试：37 个测试文件，150 条测试通过。
- 生产构建通过。
- 构建只有既有 warning：Rolldown 对第三方 `@vueuse/core` pure annotation 的提示，以及大 chunk 提示。

## 增量包

本地包：

- 目录：`river-watch-realtime-overflow-sticky-increment-20260707`
- 压缩包：`river-watch-realtime-overflow-sticky-increment-20260707.zip`
- SHA256：`905544dccd4a6da9a7aa533ecbaed536028429bcc702397c284c10307a9e3735`

包结构复核：

- Zip entries: 49
- Required files missing: none
- Nested `frontend/dist/assets/assets`: 0
- Source entries changed: `frontend/src/stores/platform.ts`, `frontend/src/__tests__/navBadges.test.ts`
- `frontend/dist/index.html` 与 `frontend/dist/assets/` 和最新构建一致。
- 未打包、未删除、未覆盖 `frontend/dist/digital-twin/` 目录。

说明：`frontend/dist/assets/` 中包含前端构建正常产生的懒加载页面 chunk，例如现有菜单页面 chunk。这是为了保证新的 `index.html` 引用的构建资源完整，不代表修改了对应菜单源码。

## 服务器应用命令

将 zip 传到 `/home/ai-river` 后执行：

```bash
set -e
cd /home/ai-river
sha256sum river-watch-realtime-overflow-sticky-increment-20260707.zip
unzip -o river-watch-realtime-overflow-sticky-increment-20260707.zip
cd river-watch-realtime-overflow-sticky-increment-20260707
chmod +x scripts/apply-realtime-overflow-sticky-increment-20260707.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-sticky-increment-20260707.sh
```

期望 SHA：

```text
905544dccd4a6da9a7aa533ecbaed536028429bcc702397c284c10307a9e3735  river-watch-realtime-overflow-sticky-increment-20260707.zip
```

## 回滚

脚本只备份并覆盖本次涉及文件。备份目录格式：

```text
/home/ai-river/river-watch/backups/realtime-overflow-sticky-increment-YYYYMMDD-HHMMSS
```

回滚时从该目录恢复：

- `frontend/src/stores/platform.ts`
- `frontend/src/__tests__/navBadges.test.ts`
- `frontend/dist/index.html`
- `frontend/dist/assets/`

然后重启前端容器。
