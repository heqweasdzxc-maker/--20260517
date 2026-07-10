# 2026-07-10 Overflow Backend Create Verified Source Field Gap

## Server Verification

User executed a direct backend create request on `192.168.2.167`:

```bash
curl -fsS -X POST http://127.0.0.1:8080/api/alarm/alarms \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "id":"RT-VERIFY-OVERFLOW-20260710",
    "cameraId":"CH01",
    "cameraName":"1号桥东",
    "type":"floater",
    "severity":"一般",
    "confidence":88,
    "status":"待研判",
    "time":"15:59:00",
    "pts":"00:00:00.000",
    "owner":"AI 推理服务",
    "dedupeCount":1,
    "snapshot":"realtime-overflow verify",
    "source":"realtime-overflow"
  }'
```

Backend returned success:

```json
{"code":0,"msg":"ok","data":{"id":"RT-VERIFY-OVERFLOW-20260710","cameraId":"CH01","cameraName":"1号桥东","type":"floater","severity":"一般","confidence":88,"status":"待研判","time":"15:59:00","pts":"00:00:00.000","owner":"AI 推理服务","dedupeCount":1,"snapshot":"realtime-overflow verify"}}
```

MySQL verification:

```text
id                              camera_id  type     status  created_at           source
RT-VERIFY-OVERFLOW-20260710     CH01       floater  待研判  2026-07-10 08:15:02  NULL
```

## Conclusions

1. Backend alarm create path is working: `/api/alarm/alarms` can create `RT-*` records in `rw_alarm`.
2. Alarm Center should be able to show the created `RT-VERIFY-OVERFLOW-20260710` record.
3. Backend currently strips or does not persist `source` from the request payload, so `JSON_EXTRACT(payload, '$.source')` is NULL.
4. Future verification should query `id LIKE 'RT-%'` unless backend is patched to preserve `source`.
5. If real overflow rows are still absent, the likely reasons are: no browser/frontend session open to trigger the frontend persist code, fewer than 16 realtime anomaly rows, or the new model not producing enough valid detections.

## Recommended Next Check

```bash
set -e

echo "== RT rows in backend =="
docker exec deploy-mysql-1 sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "
SELECT id,camera_id,type,status,created_at
FROM rw_alarm
WHERE id LIKE '\''RT-%'\''
ORDER BY created_at DESC
LIMIT 30;
"'

echo "== recent AI logs for detections/errors =="
sudo journalctl -u river-ai-group@river-a -u river-ai-group@river-b --since "30 minutes ago" --no-pager | \
  grep -Ei 'metadata|alarm|box|detect|YOLO|推理|异常|error|failed|Traceback' || true
```
