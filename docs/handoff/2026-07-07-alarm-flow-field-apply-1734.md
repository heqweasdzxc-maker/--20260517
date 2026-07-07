# Alarm flow hotfix field apply receipt - 2026-07-07 17:34

## Source

User pasted the server execution receipt from `ai-river@airiver-sy` after applying `river-watch-alarm-flow-hotfix-20260707.zip` on `192.168.2.167`.

## Result summary

The apply completed successfully.

Evidence from receipt:

- `sha256sum river-watch-alarm-flow-hotfix-20260707.zip` matched expected package hash:
  - `b1f75851bdd316d9e9dbc361ac10745bfedb9f84967a43bc3a35a10f3edecd65`
- Zip extracted under:
  - `/home/ai-river/river-watch-alarm-flow-hotfix-20260707`
- Installer started:
  - `scripts/apply-alarm-flow-hotfix-20260707.sh`
- Backup directory created:
  - `/home/ai-river/river-watch/backups/alarm-flow-hotfix/20260707-173416`
- Installer steps completed:
  - `1/4 copy alarm flow source files and tests`
  - `2/4 replace built frontend dist`
  - `3/4 hot-update frontend container if it is running`
  - `4/4 verify installed markers`
- Frontend container hot-updated and restarted:
  - `Successfully copied 109MB to deploy-frontend-1:/usr/share/nginx/html/`
  - `frontend container restarted: deploy-frontend-1`
- Installed marker grep showed expected symbols:
  - `currentRealtimeRowsForState`
  - `alarmCenterRowsForState`
  - `severityAggregationWindowSeconds`
  - `EventsPage.vue` severity-window badge marker

## Interpretation

The deployment script finished without an error and the frontend container was restarted. The code-level install markers are present in the deployed files.

Remaining verification is business/runtime acceptance:

- Browser hard refresh or clear cache.
- Confirm realtime anomaly card only shows current live detections.
- Confirm Alarm Center shows current realtime messages plus persisted alarm history.
- Confirm Event Situation aggregates by severity windows.
- Confirm ignore/handled review actions enter the work-order loop.
- Confirm work-order archive moves records to work-order query and hides them from the active loop.

## Suggested post-apply commands

```bash
cd /home/ai-river/river-watch

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|backend|mysql|mariadb|db' || true

grep -RHE 'alarmCenterRowsForState|currentRealtimeRowsForState|severityAggregationWindowSeconds|分级时间窗归集' \
  frontend/src/stores/platform.ts \
  frontend/src/services/business.ts \
  frontend/src/views/pages/EventsPage.vue

curl -I http://127.0.0.1/ || true
curl -s http://127.0.0.1/index.html | grep -E 'index-|AlarmsPage|EventsPage|MonitorPage' || true
```

If the browser still shows old behavior, force refresh or clear frontend cache because the container was restarted with new hashed assets.
