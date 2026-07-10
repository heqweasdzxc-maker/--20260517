# 2026-07-10 告警中心唯一事实源 / 实时异常最新15条补丁

## 背景

用户确认新的业务规则：所有异常标注信息都进入告警中心；实时异常只显示告警信息中的最新 15 条。

旧逻辑问题：前端实时异常由摄像头 detections、告警中心记录、overflow 暂存和前端异步 POST 混合计算。真实告警超过 15 条时，超过部分依赖浏览器前端异步落库，容易出现“实时异常有 15 条，但告警中心缺失”的问题。

## 本次实现

本地工作目录：`E:\river-video-app-V3.0`

增量包：`river-watch-alarm-center-source-realtime15-20260710.zip`

SHA256：`6856c83f70b31badb01134f498ab86026010be41ebc8cd24c8dbea0ade1a77ab`

## 改动文件

- `codex-handoff/frontend/src/stores/platform.ts`
  - `pendingAlarms` / 监控角标改为从 active alarm records 取最新 15 条。
  - `alarmRows` 保留全部未归档、未误报告警，不再排除实时异常当前 15 条。
  - `alarmHistoryRows` 保留全部告警，可查询已归档/误报历史。
  - `persistRealtimeOverflowAlarmRows()` 改为空操作，前端不再负责 overflow 落库。
  - 刷新快照时不再调用前端 overflow 持久化。

- `codex-handoff/frontend/src/__tests__/navBadges.test.ts`
  - 更新为告警中心唯一事实源测试。
  - 覆盖实时异常最新 15 条、告警中心全量 active、历史可查归档/误报、前端不再 POST overflow。

## 验证

在 `E:\river-video-app-V3.0\codex-handoff\frontend` 执行：

```bash
npm test -- src/__tests__/navBadges.test.ts
npm test
npm run build
```

结果：

- `navBadges.test.ts`: 6 passed
- 全量前端单测：37 files / 144 tests passed
- 前端构建成功
- 构建仅出现第三方 Element Plus/Rolldown pure annotation warning 和 chunk size warning，不影响产物生成

## 服务器部署命令

将 zip 放到 `/home/ai-river` 后执行：

```bash
cd /home/ai-river
unzip -o river-watch-alarm-center-source-realtime15-20260710.zip -d river-watch-alarm-center-source-realtime15-20260710
cd river-watch-alarm-center-source-realtime15-20260710
chmod +x scripts/apply-alarm-center-source-realtime15-20260710.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-alarm-center-source-realtime15-20260710.sh
```

脚本会备份并只覆盖：

- `frontend/src/stores/platform.ts`
- `frontend/src/__tests__/navBadges.test.ts`
- `frontend/dist`

并热更新 `deploy-frontend-1:/usr/share/nginx/html/` 静态资源。