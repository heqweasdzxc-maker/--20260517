# 河道异常二次训练模型增量包 20260714 v2

目标服务器：`192.168.2.167`

## 模型

- YOLO11n detection，输入 `640x640`
- ONNX opset 17，12 类
- Precision `0.585`
- Recall `0.502`
- mAP50 `0.475`
- mAP50-95 `0.234`
- ONNX SHA-256：`31ce290cdea402591c2d3c458c9d8a850a07af5006413492800c5e84f416ca63`

类别顺序：

```text
willow_fluff,leaf,aquatic_weed,water_discoloration,garbage_bag,plastic_bottle,water_bird,plastic_foam,water_foam,person_in_water,debris,wall_crack
```

## 部署边界

- 适配服务器当前 `river-a`、`river-b`、`batch@river` 并行运行的真实拓扑。
- 部署切换期间先暂停 `batch@river`，由 group 服务继续承接 CH01-CH08；group 验证成功后再启动并验证 batch。
- 不修改、不重启 `batch@structure`，不会覆盖 CH09-CH10 的结构病害模型。
- 保留现有每通道 `YOLO_CONF` 和后台分类置信度设置。
- 新增类别映射：水草、垃圾袋、塑料泡沫、水泡沫；水鸟明确忽略，不产生异常告警。
- 部署前用服务器 ONNX Runtime 做零输入推理验证。
- `river-a` 先灰度，确认模型和 MIGraphX GPU provider 后再启动 `river-b`。
- 任一步失败自动恢复模型、环境、类别映射和摄像机数据库元数据。

## 上传

在本地 PowerShell 执行：

```powershell
scp E:\river-video-app-V3.0\river-watch-river-anomaly-model-increment-20260714-v2.zip `
    E:\river-video-app-V3.0\river-watch-river-anomaly-model-increment-20260714-v2.zip.sha256 `
    ai-river@192.168.2.167:/home/ai-river/
```

## 部署

```bash
set -e
cd /home/ai-river
sha256sum -c river-watch-river-anomaly-model-increment-20260714-v2.zip.sha256
rm -rf river-watch-river-anomaly-model-increment-20260714-v2
unzip -o river-watch-river-anomaly-model-increment-20260714-v2.zip
cd river-watch-river-anomaly-model-increment-20260714-v2
chmod +x scripts/apply-river-anomaly-model-increment-20260714-v2.sh
bash -n scripts/apply-river-anomaly-model-increment-20260714-v2.sh
sudo -v

LOG="/home/ai-river/river-anomaly-model-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env APP_DIR=/home/ai-river/river-watch OPT_DIR=/opt/river-watch \
  bash scripts/apply-river-anomaly-model-increment-20260714-v2.sh \
  > "$LOG" 2>&1 &

echo "pid=$!"
echo "log=$LOG"
sleep 10
tail -200 "$LOG"
```

成功日志必须包含 `DONE`，并显示 `river-a`、`river-b`、`river-batch` 均通过 `MIGraphXExecutionProvider` 加载新模型。
