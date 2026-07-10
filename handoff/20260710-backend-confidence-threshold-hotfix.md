# 2026-07-10 后端置信度阈值过滤热修

## 问题

用户反馈：置信度阈值调高后，低于阈值的异常仍然产生标注/告警。按业务逻辑，小于设定置信度的异常应被过滤，不显示、不保存；只有大于等于设定置信度的异常标注才有效。

## 根因

前端原先从 `detections` 派生实时异常时会按 `confidenceThresholds` 过滤。改成“告警中心唯一事实源”后，实时异常直接显示后端已保存的 `rw_alarm` 记录。

后端 `/api/ai/metadata` 的 `buildMetadataEvent()` 只过滤禁用类别，没有读取 `runtimeConfig.confidenceThresholds`，因此低置信度 metadata 仍会生成 alarm 并保存到 `rw_alarm`。

## 修复

- `backend/src/ai-metadata.mjs`
  - 读取 `store.getRuntimeConfig('confidenceThresholds')`。
  - 按 cameraId 获取阈值，默认 50。
  - boxes 先过滤禁用类别，再过滤低于阈值的框。
  - 如果有异常框但全部低于阈值，返回 `ignored: true`、`reason: 'below-confidence-threshold'`，不生成 alarm，不保存。
  - 等于阈值视为有效。

- `backend/test/ai-metadata.test.mjs`
  - 增加低于阈值不生成告警测试。
  - 增加等于阈值生成告警测试。

## 增量包

```text
river-watch-backend-confidence-threshold-hotfix-20260710.zip
```

SHA256：

```text
113b9fd0644fd547c0dc9b14b31e106351dfb4dcf690fbe55fce659d49bb310e
```

## 本地验证

在 `E:\river-video-app-V3.0\codex-handoff\backend` 执行：

```bash
node --test test/ai-metadata.test.mjs
npm test
```

结果：

- `ai-metadata.test.mjs`: 4 passed
- `npm test`: 74 passed / 1 failed
- 剩余失败为既有模型文件状态测试：`strict production registers only real model files and reports AI readiness from worker heartbeats`，与本次置信度阈值过滤无关。

## 服务器部署命令

```bash
cd /home/ai-river
unzip -o river-watch-backend-confidence-threshold-hotfix-20260710.zip -d river-watch-backend-confidence-threshold-hotfix-20260710
cd river-watch-backend-confidence-threshold-hotfix-20260710
chmod +x scripts/apply-backend-confidence-threshold-hotfix-20260710.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-backend-confidence-threshold-hotfix-20260710.sh
```

脚本会：

- 备份 `/home/ai-river/river-watch/backend/src/ai-metadata.mjs`
- 覆盖后端源码和测试
- 热更新 `deploy-backend-1:/app/src/ai-metadata.mjs`
- 重启 backend 容器并等待 `/api/health`

## 注意

该修复阻止后续低置信度告警入库。历史已经保存到 `rw_alarm` 的低置信度记录不会自动删除，需要单独核查后清理。