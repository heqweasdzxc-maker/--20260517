# 2026-07-10 Activate Floater Pose Model Commands

## Context

Model imported from:

```text
20260710_训练结果.zip
SHA256: 25edd848cad00c803dafd186e447e3b6c67a2ce150425873c766156d1a848f1b
```

Expected server model directory:

```text
/opt/river-watch/models/floater-pose-20260710
```

Main model:

```text
/opt/river-watch/models/floater-pose-20260710/best.onnx
```

Important: this is a YOLO pose/keypoint model. Current worker historically decodes YOLO detection output. Activation may require pose output support in worker. The activation below is reversible and limited to river groups CH01-CH08.

## Activate On 192.168.2.167

```bash
set -euo pipefail

IMPORT_ID="floater-pose-20260710"
MODEL_ONNX="/opt/river-watch/models/$IMPORT_ID/best.onnx"
MODEL_LABELS="floater"
MODEL_IMGSZ="640"
MODEL_CONF="0.25"
ENV_DIR="/etc/river-watch"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ENV_DIR/model-env-backup-$IMPORT_ID-$TS"

[ -f "$MODEL_ONNX" ] || { echo "missing model: $MODEL_ONNX" >&2; exit 1; }

echo "== 1. ONNX quick probe =="
PY="/opt/river-watch/ai-pipeline/.venv/bin/python"
[ -x "$PY" ] || PY="python3"
MODEL="$MODEL_ONNX" "$PY" - <<'PY'
import os
import numpy as np
import onnxruntime as ort
model = os.environ['MODEL']
providers = [p for p in ['MIGraphXExecutionProvider', 'CPUExecutionProvider'] if p in ort.get_available_providers()]
if not providers:
    providers = ort.get_available_providers()
print('available_providers=', ort.get_available_providers())
sess = ort.InferenceSession(model, providers=providers)
print('active_providers=', sess.get_providers())
print('inputs=', [(i.name, i.shape, i.type) for i in sess.get_inputs()])
print('outputs=', [(o.name, o.shape, o.type) for o in sess.get_outputs()])
shape = sess.get_inputs()[0].shape
h = int(shape[2] if isinstance(shape[2], int) else 640)
w = int(shape[3] if isinstance(shape[3], int) else 640)
y = sess.run(None, {sess.get_inputs()[0].name: np.zeros((1, 3, h, w), dtype=np.float32)})
print('runtime_output_shapes=', [tuple(v.shape) for v in y])
PY

echo "== 2. backup current AI env =="
sudo mkdir -p "$BACKUP_DIR"
sudo cp -a "$ENV_DIR"/ai-worker-*.env "$BACKUP_DIR"/ 2>/dev/null || true
echo "backup=$BACKUP_DIR"

echo "== 3. activate model for river CH01-CH08 env files =="
for f in "$ENV_DIR"/ai-worker-CH0{1..8}.env "$ENV_DIR"/ai-worker-CH{01..08}.env; do
  [ -f "$f" ] || continue
  echo "patch $f"
  sudo sed -i \
    -e '/^YOLO_ONNX=/d' \
    -e '/^YOLO_LABELS=/d' \
    -e '/^YOLO_IMGSZ=/d' \
    -e '/^YOLO_CONF=/d' \
    -e '/^MODEL_REQUIRED=/d' "$f"
  {
    echo "YOLO_ONNX=$MODEL_ONNX"
    echo "YOLO_LABELS=$MODEL_LABELS"
    echo "YOLO_IMGSZ=$MODEL_IMGSZ"
    echo "YOLO_CONF=$MODEL_CONF"
    echo "MODEL_REQUIRED=1"
  } | sudo tee -a "$f" >/dev/null
done

echo "== 4. show activated env =="
sudo grep -RHE '^(CAMERA_ID|DETECTORS|YOLO_ONNX|YOLO_LABELS|YOLO_IMGSZ|YOLO_CONF|ORT_PROVIDERS|MODEL_REQUIRED)=' "$ENV_DIR"/ai-worker-CH0{1..8}.env "$ENV_DIR"/ai-worker-CH{01..08}.env 2>/dev/null | sort -u

echo "== 5. restart river AI groups =="
sudo systemctl restart river-ai-group@river-a river-ai-group@river-b
sleep 15
systemctl is-active river-ai-group@river-a river-ai-group@river-b

echo "== 6. inspect logs =="
sudo journalctl -u river-ai-group@river-a -u river-ai-group@river-b --since '5 minutes ago' --no-pager | grep -Ei 'ONNX|provider|MIGraphX|CPUExecutionProvider|YOLO|error|异常|failed|Traceback' || true
```

## Verify Runtime

```bash
set -e

echo "== active groups =="
systemctl is-active river-ai-group@river-a river-ai-group@river-b

echo "== model env =="
sudo grep -RHE '^(CAMERA_ID|YOLO_ONNX|YOLO_LABELS|YOLO_IMGSZ|YOLO_CONF|ORT_PROVIDERS|MODEL_REQUIRED)=' /etc/river-watch/ai-worker-CH0{1..8}.env /etc/river-watch/ai-worker-CH{01..08}.env 2>/dev/null | sort -u

echo "== recent logs =="
sudo journalctl -u river-ai-group@river-a -u river-ai-group@river-b --since '10 minutes ago' --no-pager | tail -120
```

## Rollback

```bash
set -euo pipefail
ENV_DIR="/etc/river-watch"
LATEST_BACKUP="$(ls -td "$ENV_DIR"/model-env-backup-floater-pose-20260710-* | head -1)"
[ -d "$LATEST_BACKUP" ] || { echo "no backup found" >&2; exit 1; }

echo "restore from $LATEST_BACKUP"
sudo cp -a "$LATEST_BACKUP"/*.env "$ENV_DIR"/
sudo systemctl restart river-ai-group@river-a river-ai-group@river-b
sleep 10
systemctl is-active river-ai-group@river-a river-ai-group@river-b
sudo journalctl -u river-ai-group@river-a -u river-ai-group@river-b --since '5 minutes ago' --no-pager | tail -80
```
