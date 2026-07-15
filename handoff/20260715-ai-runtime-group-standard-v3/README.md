# River Watch AI 推理架构统一增量包 20260715 v3

目标服务器：`192.168.2.167`

## 调整结果

- `river-ai-group@river-a`：运行，负责 CH01-CH04。
- `river-ai-group@river-b`：运行，负责 CH05-CH08。
- `river-ai-group@structure`：运行，负责 CH09-CH10。
- `river-ai-batch@river`：停止并禁用，但保留服务、代码和配置。
- `river-ai-batch@structure`：停止并禁用，但保留服务、代码和配置。
- CH09-CH10 固定使用 `/opt/river-watch/models/yolo-wall-crack-leak-20260630.onnx`。
- 算法管理登记河道十二分类模型和墙体裂痕/渗漏专用模型。

v3 在 v2 的拓扑基线修正上，进一步修复 `pipefail` 将“子进程尚未出现”误判为错误的问题。它兼容当前服务器的全 batch 基线，也兼容已切换完成的全 group 基线和原先的混合基线；混合占用同一通道或部分 group 运行时会拒绝操作。

墙体裂痕/渗漏专用模型为 Ultralytics YOLO11n detect，类别为 `crack,leak`，SHA-256：

```text
3d7623906d57bdb439a5686dd6b39093c6ca8b9d6e233f3c78027d048d35e3f4
```

训练结果：precision `0.97332`、recall `0.95532`、mAP50 `0.97655`、mAP50-95 `0.83993`。

## 边界

- 不携带、覆盖或重复保存 ONNX/PT 权重。
- `/opt` 中模型缺失或哈希不符时，仅从现有 `/home/ai-river/river-watch/models` 导入已校验的专用模型。
- 不修改 CH01-CH10 的 RTSP、认证令牌、现有置信度或抽帧频率。
- 不修改前端、后端、摄像机、告警和视频转发程序。
- 切换前保存相关环境文件、模型文件状态、算法登记记录和五个 systemd 服务状态。
- 任一 group 未在 900 秒内完成预期子进程及 MIGraphX 模型加载时自动回滚。
- 停止两个 batch 后，依次启动并验证 `river-a`、`river-b`、`structure`；每组最多等待 900 秒。
- 三组全部完成子进程、指定模型和 MIGraphX 校验后，才禁用保留的 batch 服务。
- 任一组失败时恢复部署前五个 systemd 服务的启停与启用状态。

## 上传

在本地 PowerShell 执行：

```powershell
scp E:\river-video-app-V3.0\river-watch-ai-runtime-topology-increment-20260715-v3.zip `
    E:\river-video-app-V3.0\river-watch-ai-runtime-topology-increment-20260715-v3.zip.sha256 `
    ai-river@192.168.2.167:/home/ai-river/
```

## 部署

在 `192.168.2.167` 执行：

```bash
set -e
cd /home/ai-river
sha256sum -c river-watch-ai-runtime-topology-increment-20260715-v3.zip.sha256
rm -rf river-watch-ai-runtime-topology-increment-20260715-v3
unzip -o river-watch-ai-runtime-topology-increment-20260715-v3.zip
cd river-watch-ai-runtime-topology-increment-20260715-v3
sha256sum -c SHA256SUMS
bash -n scripts/*.sh
chmod +x scripts/*.sh
sudo -v

LOG="/home/ai-river/ai-runtime-group-standard-v3-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env \
  APP_DIR=/home/ai-river/river-watch \
  OPT_DIR=/opt/river-watch \
  bash scripts/apply-ai-runtime-topology-increment-20260714.sh \
  > "$LOG" 2>&1 &

echo "pid=$!"
echo "log=$LOG"
tail -f "$LOG"
```

停止 batch 后到三组 group 全部就绪之间会存在推理切换窗口。模型首次加载可能持续数分钟，成功日志必须出现 `DONE` 和 `VERIFY OK`；失败会恢复原来的两个 batch。

## 复核

```bash
cd /home/ai-river/river-watch-ai-runtime-topology-increment-20260715-v3
sudo bash scripts/verify-ai-runtime-topology-20260714.sh

sudo journalctl \
  -u river-ai-group@river-a \
  -u river-ai-group@river-b \
  -u river-ai-group@structure \
  --since "15 min ago" --no-pager \
  | grep -Ei 'MIGraphX|YOLO|CH09|CH10|error|failed|Traceback' | tail -200
```

## 手工回滚

应用日志末尾会打印实际备份目录。使用该目录执行：

```bash
cd /home/ai-river/river-watch-ai-runtime-topology-increment-20260715-v3
sudo bash scripts/rollback-ai-runtime-topology-20260714.sh \
  /home/ai-river/river-watch/backups/ai-runtime-group-standard-v3-20260715-实际时间戳
```

应用过程出现错误时会自动执行相同回滚。

