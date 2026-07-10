# 2026-07-10 Model Activated And Overflow Persist Apply Still Unconfirmed

## Realtime Overflow Persist Patch

User attempted to apply:

```text
river-watch-realtime-overflow-persist-increment-20260710.zip
SHA256: 6a44f2e04fa9ebb0c06c0ce6a7e15e1c8a9f4791a17555423e858e08bcd8353f
```

The zip SHA matched and unzip succeeded, but the SSH connection closed immediately after extracting the package. The apply script output did not appear.

Then user ran marker check:

```bash
grep -RHE 'persistRealtimeOverflowAlarmRows|persistedRealtimeOverflowAlarmIds|realtime-overflow' \
  /home/ai-river/river-watch/frontend/src/stores/platform.ts \
  /home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts
```

Output stopped at:

```text
== marker ==
Connection closed.
```

No marker lines were shown. Therefore the realtime overflow backend-persist patch is still **not confirmed applied**. Need rerun with `sudo -v` and `nohup`, then check marker and backup directory.

Recommended command:

```bash
set -e
cd /home/ai-river/river-watch-realtime-overflow-persist-increment-20260710
sudo -v
chmod +x scripts/apply-realtime-overflow-persist-increment-20260710.sh
LOG="/home/ai-river/realtime-overflow-persist-apply-$(date +%Y%m%d-%H%M%S).log"
nohup bash -lc 'APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-persist-increment-20260710.sh' > "$LOG" 2>&1 &
echo "apply_pid=$!"
echo "log=$LOG"
sleep 8
tail -160 "$LOG"
```

Post-check:

```bash
set -e
grep -RHE 'persistRealtimeOverflowAlarmRows|persistedRealtimeOverflowAlarmIds|realtime-overflow' \
  /home/ai-river/river-watch/frontend/src/stores/platform.ts \
  /home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts
ls -td /home/ai-river/river-watch/backups/realtime-overflow-persist-increment-* | head -3
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web'
curl -fsS http://127.0.0.1:8081/ | head -5
```

## Model Import

Training package was imported successfully from:

```text
/home/ai-river/20260710_璁粌缁撴灉.zip
SHA256: 25edd848cad00c803dafd186e447e3b6c67a2ce150425873c766156d1a848f1b
```

Extracted to:

```text
/home/ai-river/model-import-floater-pose-20260710
```

Installed to:

```text
/opt/river-watch/models/floater-pose-20260710
```

Key checksums:

```text
68b7c0387247340220d0be06630da38b734919a87cad61c5090b6d882c8f4f97  /opt/river-watch/models/floater-pose-20260710/best.onnx
488b8ce1dec93b0f968d32bd2cc8a21853e836f00113483066c553a999875d0c  /opt/river-watch/models/floater-pose-20260710/best.pt
85731b7ea76d307eb4412f65ea3dd56613608406d947388decf8c6896559ff9f  /opt/river-watch/models/floater-pose-20260710/data.yaml
```

ONNX probe:

```text
available_providers= ['MIGraphXExecutionProvider', 'CPUExecutionProvider']
active_providers= ['MIGraphXExecutionProvider', 'CPUExecutionProvider']
inputs= [('images', [1, 3, 640, 640], 'tensor(float)')]
outputs= [('output0', [1, 20, 8400], 'tensor(float)')]
runtime_output_shapes= [(1, 20, 8400)]
```

## Model Activation

Activation backup:

```text
/etc/river-watch/model-env-backup-floater-pose-20260710-20260710-155626
```

CH01-CH08 env files now point to:

```text
YOLO_ONNX=/opt/river-watch/models/floater-pose-20260710/best.onnx
YOLO_LABELS=floater
YOLO_IMGSZ=640
YOLO_CONF=0.25
MODEL_REQUIRED=1
ORT_PROVIDERS=MIGraphXExecutionProvider
```

AI groups restarted and active:

```text
river-ai-group@river-a active
river-ai-group@river-b active
```

Logs show all CH01-CH08 workers loaded:

```text
加载 YOLO ONNX: /opt/river-watch/models/floater-pose-20260710/best.onnx 类别=['floater']
```

Need continued observation for inference errors because this is a YOLO pose/keypoint model with output shape `[1, 20, 8400]`, while the existing worker historically decoded detection-style outputs.

Recommended runtime observation:

```bash
sudo journalctl -u river-ai-group@river-a -u river-ai-group@river-b --since '15 minutes ago' --no-pager | \
  grep -Ei 'ONNX|provider|MIGraphX|CPUExecutionProvider|YOLO|推理|异常|error|failed|Traceback' || true
```
