# 2026-07-10 Pose Output Decode Hotfix

## Context

Server: `192.168.2.167`

After importing the latest training result `20260710_训练结果.zip`, the model was activated on CH01-CH08 with:

- `YOLO_ONNX=/opt/river-watch/models/floater-pose-20260710/best.onnx`
- `YOLO_LABELS=floater`
- `YOLO_IMGSZ=640`
- `YOLO_CONF=0.25`
- `MODEL_REQUIRED=1`
- `ORT_PROVIDERS=MIGraphXExecutionProvider`

Model probe showed ONNX output shape `[1,20,8400]`, and active providers included `MIGraphXExecutionProvider`.

Manual backend alarm creation worked and inserted `RT-VERIFY-OVERFLOW-20260710` into `rw_alarm`, proving the backend alarm-center persistence path is usable. Real AI-generated RT rows still did not appear, so the remaining blocker is upstream AI detection/metadata production.

## Root Cause

`river_worker.py` and `batch_worker.py` decoded every value after index 4 as class confidence:

```python
cls_scores = row[4:]
```

For YOLO pose/keypoint output `[x, y, w, h, class_score, keypoints...]`, keypoint columns were incorrectly treated as class scores. The current alarm pipeline only needs box + class confidence, so keypoint columns must be ignored.

## Local Fix

Prepared incremental package:

- Local path: `E:\river-video-app-V3.0\river-watch-pose-output-decode-hotfix-20260710.zip`
- SHA256: `ee9235ceb4371d1b463e1ffa5afca95318aebe0580bce94b2b84263fd18f89a1`
- Package size: about 21 KB

Included files only:

- `ai-pipeline/workers/river_worker.py`
- `ai-pipeline/workers/batch_worker.py`
- `ai-pipeline/tests/test_batch_worker.py`
- `scripts/apply-pose-output-decode-hotfix-20260710.sh`
- `README_POSE_OUTPUT_DECODE_HOTFIX_20260710.md`
- `SHA256SUMS`

No frontend, backend, database, model, Docker image, or system menu files are included.

## Code Change

Both worker decoders now use only the configured class segment:

```python
class_end = 4 + max(1, len(self.labels))
cls_scores = row[4:min(class_end, row.shape[0])]
```

Added regression coverage for pose-style output `[4 + classes + keypoints * 3, candidates]`.

## Local Verification

Commands run locally:

```powershell
& 'C:\Users\LY375\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' codex-handoff\ai-pipeline\tests\test_batch_worker.py
& 'C:\Users\LY375\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' codex-handoff\ai-pipeline\tests\test_detect_core.py
python -m py_compile codex-handoff\ai-pipeline\workers\river_worker.py codex-handoff\ai-pipeline\workers\batch_worker.py codex-handoff\ai-pipeline\tests\test_batch_worker.py
```

Observed:

- `test_batch_worker.py`: 2 tests passed.
- `test_detect_core.py`: 8 tests passed.
- Python syntax check passed.

## Server Apply Command

Upload/copy `river-watch-pose-output-decode-hotfix-20260710.zip` to `/home/ai-river` on `192.168.2.167`, then run:

```bash
set -e
cd /home/ai-river
sha256sum river-watch-pose-output-decode-hotfix-20260710.zip
unzip -o river-watch-pose-output-decode-hotfix-20260710.zip
cd river-watch-pose-output-decode-hotfix-20260710
chmod +x scripts/apply-pose-output-decode-hotfix-20260710.sh
APP_DIR=/home/ai-river/river-watch OPT_DIR=/opt/river-watch ./scripts/apply-pose-output-decode-hotfix-20260710.sh
```

Expected SHA256:

```text
ee9235ceb4371d1b463e1ffa5afca95318aebe0580bce94b2b84263fd18f89a1  river-watch-pose-output-decode-hotfix-20260710.zip
```

## Post-Apply Check

```bash
set -e
sudo journalctl -u river-ai-group@river-a -u river-ai-group@river-b --since "10 minutes ago" --no-pager \
  | grep -Ei 'loaded model|providers|MIGraphX|YOLO|Traceback|error|failed|metadata|alarm|告警' || true

docker exec deploy-mysql-1 sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "
SELECT id,camera_id,type,status,created_at
FROM rw_alarm
WHERE id LIKE '\''RT-%'\''
ORDER BY created_at DESC
LIMIT 30;
"'
```

## Next Suspects If Still No Real RT Rows

If valid camera events still produce no real `RT-*` rows after this patch, investigate:

- RTSP/H264 decode instability in AI worker logs.
- Model confidence threshold too high for the new training result.
- Whether the event metadata post path is reached after detection.
- Whether sampled frames actually contain positive detections.
