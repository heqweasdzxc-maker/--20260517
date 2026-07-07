# Realtime Overflow Hotfix Apply Receipt 2026-07-07

## Server

- Host: `192.168.2.167`
- User prompt context: field receipt after applying `river-watch-realtime-overflow-hotfix-20260707.zip`

## Command Executed

```bash
set -e
cd /home/ai-river
sha256sum river-watch-realtime-overflow-hotfix-20260707.zip
unzip -o river-watch-realtime-overflow-hotfix-20260707.zip
cd river-watch-realtime-overflow-hotfix-20260707
chmod +x scripts/apply-realtime-overflow-hotfix-20260707.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-hotfix-20260707.sh
```

## SHA256 Verified

```text
02017b637bc0cce2d6ebc6d297efb3685ee6b0ff6b2c1206258a881b8f7de869  river-watch-realtime-overflow-hotfix-20260707.zip
```

This matches the expected package hash.

## Apply Result

The script completed successfully:

```text
Realtime overflow hotfix applied.
```

Backup created:

```text
/home/ai-river/river-watch/backups/realtime-overflow-hotfix-20260707-194125
```

Frontend container hot-updated:

```text
Frontend container: deploy-frontend-1
Successfully copied 109MB to deploy-frontend-1:/usr/share/nginx/html/
```

## Marker Verification From Server Output

The server output confirmed the patched frontend source contains:

```text
function realtimeFeedSplitForState(state: AlarmFlowState)
return realtimeFeedSplitForState(state).current.filter((alarm) => !dispatched.has(alarm.id));
function overflowRealtimeRowsForState(state: AlarmFlowState): Alarm[]
return realtimeFeedSplitForState(state).overflow;
...overflowRealtimeRowsForState(state),
```

The regression markers are also present:

```text
expect(store.alarmRows.map((item) => item.id)).toEqual(['A-UTF8-01']);
it('keeps overflow based on the raw realtime FIFO instead of refilling hidden realtime slots', () => {
```

Brand/header markers are present, though terminal locale displayed Chinese as mojibake:

```text
AI视频分析系统
洋河股份泗阳基地安环部
topbar-title
video-toolbar-title
```

## Container Status At Apply Time

```text
deploy-backend-1      Up 51 minutes (healthy)                    0.0.0.0:8080->8080/tcp
deploy-frontend-1     Up Less than a second (health: starting)   0.0.0.0:8081->80/tcp
deploy-minio-1        Up 51 minutes                              127.0.0.1:9000-9001->9000-9001/tcp
deploy-mysql-1        Up 51 minutes                              127.0.0.1:3306->3306/tcp
deploy-redis-1        Up 51 minutes                              127.0.0.1:6379->6379/tcp
deploy-zlmediakit-1   Up 51 minutes                              0.0.0.0:1935->1935/tcp, 0.0.0.0:10000->10000/tcp/udp, 0.0.0.0:8060->80/tcp
```

`deploy-frontend-1` was in `health: starting` immediately after restart. This is expected briefly after hot update; follow-up should confirm it becomes healthy.

## Recommended Follow-Up Commands

Run after 20-60 seconds:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -fsS http://127.0.0.1:8081/ >/tmp/river-watch-frontend.html && echo frontend-ok
```

Check live snapshot counts if the UI still does not show expected overflow rows:

```bash
curl -fsS http://127.0.0.1:8080/api/platform/snapshot | python3 - <<'PY'
import json, sys
payload=json.load(sys.stdin).get('data', {})
alarms=payload.get('alarms') or []
cameras=payload.get('cameras') or []
print('alarms=', len(alarms))
print('cameras=', len(cameras))
print('first_alarm_ids=', [a.get('id') for a in alarms[:20]])
print('first_alarm_status=', [a.get('status') for a in alarms[:20]])
PY
```

If the backend snapshot itself does not return more than 15 relevant pending/realtime alarms, the remaining issue is backend data generation or snapshot payload composition rather than the frontend FIFO split.
