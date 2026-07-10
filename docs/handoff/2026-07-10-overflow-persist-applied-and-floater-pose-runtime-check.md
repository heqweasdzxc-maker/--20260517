# 2026-07-10 Overflow Persist Applied And Floater Pose Runtime Check

## Realtime Overflow Backend Persist Patch

Server: `192.168.2.167`

Package:

```text
river-watch-realtime-overflow-persist-increment-20260710.zip
SHA256: 6a44f2e04fa9ebb0c06c0ce6a7e15e1c8a9f4791a17555423e858e08bcd8353f
```

Applied via nohup log:

```text
/home/ai-river/realtime-overflow-persist-apply-20260710-155935.log
```

Apply log confirms:

```text
== River Watch realtime overflow backend-persist incremental patch ==
APP_DIR=/home/ai-river/river-watch
PKG_DIR=/home/ai-river/river-watch-realtime-overflow-persist-increment-20260710
== 1. Backup only changed files and frontend assets ==
Backup saved: /home/ai-river/river-watch/backups/realtime-overflow-persist-increment-20260710-155935
== 2. Apply incremental source files ==
== 3. Apply frontend build output ==
== 4. Hot update frontend container assets only ==
Frontend container: deploy-frontend-1
== 5. Verify backend-persist overflow markers ==
...
Realtime overflow backend-persist incremental patch applied.
```

Post-check marker lines exist in target source:

```text
persistedRealtimeOverflowAlarmIds
persistRealtimeOverflowAlarmRows
source: 'realtime-overflow'
```

Backup directory:

```text
/home/ai-river/river-watch/backups/realtime-overflow-persist-increment-20260710-155935
```

Frontend check:

```text
deploy-frontend-1 Up 40 seconds (healthy) 0.0.0.0:8081->80/tcp
```

Page smoke returned HTML:

```html
<!doctype html>
<html lang="zh-CN">
```

## Floater Pose Model Runtime Check

Previously imported and activated model:

```text
/opt/river-watch/models/floater-pose-20260710/best.onnx
```

CH01-CH08 env files point to:

```text
YOLO_ONNX=/opt/river-watch/models/floater-pose-20260710/best.onnx
YOLO_LABELS=floater
YOLO_IMGSZ=640
YOLO_CONF=0.25
MODEL_REQUIRED=1
ORT_PROVIDERS=MIGraphXExecutionProvider
```

Recent AI group logs show model loaded for river-a/river-b workers:

```text
加载 YOLO ONNX: /opt/river-watch/models/floater-pose-20260710/best.onnx 类别=['floater']
```

The filtered log check over the last 15 minutes did not show `error`, `failed`, or `Traceback` in the provided output.

## Remaining Business Verification

Technical deployment is complete. Business behavior still needs live verification:

- Realtime anomaly card should show only newest 15 messages.
- The 16th and later overflow messages should POST to `/api/alarm/alarms` with `source: realtime-overflow`.
- These records should remain visible in Alarm Center after page refresh.

Recommended verification commands:

```bash
set -e

echo "== recent backend alarm create logs =="
docker logs deploy-backend-1 --since 20m 2>&1 | grep -Ei 'realtime-overflow|/api/alarm/alarms|POST.*alarm|rw_alarm' || true

echo "== recent alarm rows containing RT or floater =="
docker exec deploy-mysql-1 sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SELECT id,camera_id,type,status,created_at FROM rw_alarm WHERE id LIKE '\''RT-%'\'' OR JSON_EXTRACT(payload,'\''$.source'\'') = '\''\"realtime-overflow\"'\'' ORDER BY created_at DESC LIMIT 20;"' || true
```

If there are no rows, wait for/trigger more than 15 simultaneous realtime anomaly messages and check again.
