# River Watch 证据组卷真实性与完整性增量修复

## 修复范围

- 证据包不再把“原始视频、AI 抓拍”等材料伪装成说明 JSON。
- 下载时从 `rw_alarm_evidence` 读取告警发生时刻真实截图或片段。
- 包内包含真实媒体、检测框元数据、告警研判记录、工单记录、清单和逐文件 SHA256。
- 没有历史媒体时标记为“证据不完整”，校验返回失败，下载返回 HTTP 409。
- 旧证据包再次校验或下载时按 2.0 清单动态重建，无需数据库迁移。

## 新证据包结构

```text
manifest.json
captures/alarm-frame.jpg       # 或 captures/alarm-frame.png / media/alarm-clip.mp4
metadata/detection.json
records/review.json
records/workorder.json
checksums.sha256
```

当前系统保存的是告警时刻截图，因此默认输出 JPEG；只有数据库真实保存 MP4 时才输出视频片段，不伪造录像。

## 部署影响

- 只替换 `backend/src/server.mjs`。
- 只重启 `deploy-backend-1` 容器，不重启服务器、前端、数据库或 AI worker。
- 无数据库结构变更、无消息清理、无模型调整。
- 部署前严格校验当前生产基线，哈希不一致时在修改前停止。

## 部署

```bash
cd /home/ai-river
sha256sum -c river-watch-evidence-bundle-integrity-increment-20260720.zip.sha256
sudo rm -rf /home/ai-river/river-watch-evidence-bundle-integrity-increment-20260720
unzip -o river-watch-evidence-bundle-integrity-increment-20260720.zip
sudo chown -R ai-river:ai-river river-watch-evidence-bundle-integrity-increment-20260720
cd river-watch-evidence-bundle-integrity-increment-20260720
sha256sum -c SHA256SUMS
chmod +x scripts/*.sh
sudo -v

LOG="/home/ai-river/evidence-bundle-integrity-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env APP_DIR=/home/ai-river/river-watch BACKEND_CONTAINER=deploy-backend-1 \
  bash scripts/apply-evidence-bundle-integrity-20260720.sh >"$LOG" 2>&1 &
echo "pid=$!"
echo "log=$LOG"
tail -f "$LOG"
```

成功标志为 `VERIFY OK` 和 `DONE`。若失败，脚本自动恢复原文件并重启后端。

## 手工回滚

```bash
sudo env APP_DIR=/home/ai-river/river-watch BACKEND_CONTAINER=deploy-backend-1 \
  bash scripts/rollback-evidence-bundle-integrity-20260720.sh \
  /home/ai-river/river-watch/backups/evidence-bundle-integrity-20260720-YYYYMMDD-HHMMSS
```
