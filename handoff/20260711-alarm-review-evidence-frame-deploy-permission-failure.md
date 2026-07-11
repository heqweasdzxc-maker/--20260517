# 20260711 Alarm Review Evidence Frame Deploy Permission Failure

## Context

User applied `river-watch-alarm-review-evidence-frame-hotfix-20260711.zip` on `192.168.2.167`.

Package verification succeeded:

```text
e0802a830beca381ed6d4ad28d3a3ac67241cec8689d2254169d8e9be4f770dd  river-watch-alarm-review-evidence-frame-hotfix-20260711.zip
```

Unzip succeeded and the apply script started.

## Failure

The apply script created the backup successfully:

```text
Backup saved: /home/ai-river/river-watch/backups/alarm-review-evidence-frame-hotfix-20260711-20260711-132229
```

Then it failed during source file copy:

```text
cp: cannot create regular file '/home/ai-river/river-watch/frontend/src/composables/useWorkspace.ts': Permission denied
```

This means the hotfix did not fully apply. The system may be in a partial state because `WorkspaceDialogs.vue` may have copied before the failure, but `useWorkspace.ts`, frontend dist, and frontend container assets were not completed.

## Required Recovery

Re-run the same apply script with sudo so it can write root-owned frontend files:

```bash
set -e
cd /home/ai-river/river-watch-alarm-review-evidence-frame-hotfix-20260711
sudo -v
sudo env APP_DIR=/home/ai-river/river-watch bash scripts/apply-alarm-review-evidence-frame-hotfix-20260711.sh
```

Then verify markers and frontend:

```bash
set -e

echo "== source markers =="
sudo grep -RHE 'alarm-evidence-frame|selectedAlarmEvidenceEvent|selectedAlarmEvidenceBoxes|evidenceBoxStyle' \
  /home/ai-river/river-watch/frontend/src/components/WorkspaceDialogs.vue \
  /home/ai-river/river-watch/frontend/src/composables/useWorkspace.ts \
  /home/ai-river/river-watch/frontend/src/styles.css

echo "== container/page =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|web'
curl -fsS http://127.0.0.1:8081/ | head -5

echo "== built asset marker =="
docker exec deploy-frontend-1 sh -lc "grep -R 'alarm-evidence-frame\|selectedAlarmEvidenceEvent' -n /usr/share/nginx/html/assets | head -20 || true"
```

## Note

Do not judge the UI until the sudo re-run completes, because the previous run stopped before dist/container hot update.
