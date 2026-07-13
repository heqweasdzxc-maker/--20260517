# 2026-07-13 Alarm evidence v3 deployment result

## Result

Deployment of `river-watch-alarm-evidence-snapshot-increment-20260713-v3.zip` to `192.168.2.167` completed successfully.

- Apply log: `/home/ai-river/alarm-evidence-v3-apply-20260713-133807.log`
- Result marker: `DONE`
- Automatic rollback: not triggered
- Rollback backup retained at: `/home/ai-river/river-watch/backups/alarm-evidence-snapshot-v3-20260713-133807`

## Runtime status

- `deploy-backend-1`: healthy
- `deploy-frontend-1`: healthy
- `deploy-mysql-1`: running
- Backend health endpoint: UP
- Frontend HTTP endpoint: reachable
- Backend became ready after attempt 2/60.
- Frontend became ready after attempt 2/60.

## Active feature verification

Backend markers are present in the running container:

- `scheduleAlarmEvidenceCapture` import and ingest call
- `alarmEvidenceMatch` authenticated API route
- `rw_alarm_evidence` schema, retention, insert, and read logic

Frontend verification:

- Active entry asset: `assets/index-BKSyKpIk.js`
- Evidence API marker: present

## Persisted evidence

Three JPEG evidence records were confirmed, including two captured after the successful v3 deployment:

| Alarm | Camera | Size | Captured |
|---|---|---:|---|
| `A-1783921061917` | `CH09` | 42,379 bytes | `2026-07-13 05:40:01` |
| `A-1783916819407` | `CH10` | 23,872 bytes | `2026-07-13 05:38:26` |
| `A-1783909173004` | `CH10` | 22,909 bytes | `2026-07-13 03:23:31` |

This verifies the full runtime path: new AI alarm ingest -> asynchronous historical frame capture -> MySQL persistence -> authenticated backend evidence API -> deployed frontend evidence viewer.

Existing alarms created before evidence capture was active may still have no historical media and cannot be reconstructed from the current live stream.
