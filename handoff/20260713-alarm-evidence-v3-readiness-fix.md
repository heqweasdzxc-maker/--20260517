# 2026-07-13 Alarm evidence deployment v3 readiness fix

## Server verification after v2 rollback

The post-deployment diagnostic output from `192.168.2.167` confirms that the v2 deployment automatically rolled back both application layers:

- Backend `server.mjs`: `513dad526c3ef9efe701f1cefac66a8a07deff95108302fb23f60dfe04c583c4`
- Backend `store.mjs`: `bb7b4f2703c8bf068d3a36b321c882811d22710006ea0fc43e3e45b6d51be1a3`
- Backend `ai-ingest.mjs`: `d5159e0cee407654938065711beadd96324f5a3dccb54e3b8a45e7ff7fd093e8`
- Backend `alarm-evidence.mjs`: `de0fb34a257ffc64b45e4541350bb93c4e33897b208f0d516ca3d4ea046d7036`
- Evidence markers are absent from the active backend.
- Active frontend entry asset: `assets/index-axKdEsFH.js`
- Backend, frontend, and MySQL containers are healthy.

The database contains one captured record:

- Alarm: `A-1783909173004`
- Camera: `CH10`
- Type: `image/jpeg`
- Size: `22909` bytes
- Captured: `2026-07-13 03:23:31`

This record proves that the runtime-rebased evidence capture, schema, and ingest integration were active before rollback.

## Root cause

The v2 script restarted the frontend container and immediately ran a one-shot `curl` pipeline. nginx reset that request during normal startup:

```
curl: (56) Recv failure: connection reset
```

Because the script uses `set -Eeuo pipefail`, that transient request failure entered the automatic rollback trap. Backend health and schema creation had already succeeded. The failure was deployment verification timing, not an application compatibility failure.

## v3 change

The v3 increment changes deployment safety only. Alarm, video, menu, database, and inference behavior are unchanged.

1. Replaces one-shot frontend verification with bounded HTTP readiness polling.
2. Uses the same bounded readiness helper for backend startup.
3. Accepts either the exact original runtime hashes or the exact already-patched hashes, making deployment repeatable while still rejecting unknown drift.
4. Verifies active backend evidence markers after restart:
   - `scheduleAlarmEvidenceCapture`
   - `alarmEvidenceMatch`
   - `rw_alarm_evidence`
5. Verifies the exact frontend entry asset and its evidence API marker.
6. Retains complete pre-change host/container backup and automatic rollback.

## Deliverable

- Package: `river-watch-alarm-evidence-snapshot-increment-20260713-v3.zip`
- SHA-256: `d91aab26366dec51d84152c7872139ede576e779fcf1cae4e1d2d4bf88e62fc0`
- Size: `1,179,802` bytes
- Archive entries: `70`
- Internal checksum entries: `58`
- Internal checksums: passed
- Outer checksum: passed
- Linux LF script: passed
- Shell syntax: passed
- Deployment readiness regression: passed

The backend/frontend feature payload is unchanged from the tested runtime-rebased v2 package; v3 changes only the apply script and documentation.

## Apply

```bash
set -e
cd /home/ai-river

sha256sum river-watch-alarm-evidence-snapshot-increment-20260713-v3.zip
# Expected:
# d91aab26366dec51d84152c7872139ede576e779fcf1cae4e1d2d4bf88e62fc0

unzip -o river-watch-alarm-evidence-snapshot-increment-20260713-v3.zip
cd river-watch-alarm-evidence-snapshot-increment-20260713-v3

bash -n scripts/apply-alarm-evidence-snapshot-increment-20260713-v3.sh
chmod +x scripts/apply-alarm-evidence-snapshot-increment-20260713-v3.sh
sudo -v

LOG="/home/ai-river/alarm-evidence-v3-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env APP_DIR=/home/ai-river/river-watch \
  bash scripts/apply-alarm-evidence-snapshot-increment-20260713-v3.sh \
  > "$LOG" 2>&1 &

echo "pid=$!"
echo "log=$LOG"
sleep 8
tail -160 "$LOG"
```

Do not use the superseded `20260712` or `20260713-v2` evidence packages.
