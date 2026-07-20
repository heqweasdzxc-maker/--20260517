# 2026-07-20 通道隔离、告警证据与消息清理交接

## 结论

1. CH01-CH08 使用的河道 12 类模型中包含 `wall_crack`。现有 pooled group runtime 只按置信度过滤，`DETECTORS=floating,color` 仅选择推理模块，不限制模型输出类别，因此河道通道会产生“墙体裂痕”。
2. 生产数据库中的告警证据 JPEG 有效（640x360），黑底不是图片数据为空。前端只监听已选告警 ID；重复打开同一告警时 ID 不变，证据不会重新请求，HTTP/代理/鉴权失败又被统一渲染为深色占位。
3. 修复采用显式通道类别白名单，并在重复打开同一告警时强制重新加载历史证据；加载、404、鉴权/代理和非法媒体状态均显示具体提示。

## 通道边界

- CH01-CH08：漂浮物、漂浮物聚集、浮游物、水色异常、水位异常、人员落水、非法倾倒。
- CH09-CH10：墙体裂痕、污水渗漏、地面水渍。
- 原有模型、置信度、采样率、RTSP、认证和 group 2+2+1 拓扑保持不变；batch 保持停用。

## 数据清理

部署必须显式设置 `CONFIRM_CLEAR_MESSAGES=YES`。脚本先停止 AI group/batch 和后端写入，生成并校验压缩 SQL 备份，再在事务中清理：

`rw_event_group_alarm`, `rw_alarm_evidence`, `rw_notification`, `rw_playback_clip`, `rw_evidence_bundle`, `rw_uav_task`, `rw_work_order`, `rw_ai_event`, `rw_event_group`, `rw_alarm`。

设备、用户、角色、阈值、模型、算法、流媒体、存储策略、导入和训练数据不删除。失败时自动恢复源码、环境、前端资源、数据库记录和服务状态。

## 交付物

- 包名：`river-watch-channel-isolation-evidence-db-cleanup-increment-20260720.zip`
- SHA-256：`73cb86f6016a2eba899b88699f1ea9aaf2f5323873393f34f95294627fad506d`
- 本地路径：`E:\river-video-app-V3.0\river-watch-channel-isolation-evidence-db-cleanup-increment-20260720.zip`
- 本地完整 Git 提交：`e2f04c2238a02ca9d84e0319e192d88d1a8c2795`
- 当前状态：本地完成，尚未在 192.168.2.167 执行。

## 本地验证

- pooled group runtime：21 passed。
- 增量包：20 passed。
- 前端：40 个测试文件、174 passed。
- `vue-tsc` 与生产构建通过。
- 三个部署脚本通过 `bash -n`。
- ZIP 校验通过，未包含 pytest 缓存、Python bytecode、数字孪生大资源或模型文件。

## 部署命令

```bash
cd /home/ai-river
sha256sum -c river-watch-channel-isolation-evidence-db-cleanup-increment-20260720.zip.sha256
rm -rf river-watch-channel-isolation-evidence-db-cleanup-increment-20260720
unzip -o river-watch-channel-isolation-evidence-db-cleanup-increment-20260720.zip
cd river-watch-channel-isolation-evidence-db-cleanup-increment-20260720
sha256sum -c SHA256SUMS
chmod +x scripts/*.sh
sudo -v

LOG="/home/ai-river/channel-isolation-evidence-db-cleanup-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env \
  APP_DIR=/home/ai-river/river-watch \
  OPT_DIR=/opt/river-watch \
  CONFIRM_CLEAR_MESSAGES=YES \
  bash scripts/apply-channel-isolation-evidence-db-cleanup-20260720.sh \
  >"$LOG" 2>&1 &

echo "pid=$!"
echo "log=$LOG"
tail -f "$LOG"
```

以日志出现 `VERIFY OK` 和 `DONE` 为成功标准；日志会同时输出 SQL 备份与回滚目录。
