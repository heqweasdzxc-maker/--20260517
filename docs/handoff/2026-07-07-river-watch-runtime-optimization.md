# River-Watch 2026-07-07 Runtime Optimization Handoff

> Purpose: preserve the full operational record so another agent or engineer can continue even if this Codex thread is unavailable.

## Current Context

- Local workspace: `E:\river-video-app-V3.0`
- Field server discussed: `192.168.2.167`, host prompt shown as `ai-river@airiver-sy`
- Application path on server: `/home/ai-river/river-watch`
- AI runtime path on server: `/opt/river-watch/ai-pipeline`
- Runtime configuration path on server: `/etc/river-watch`
- Current deliverable package:
  - `E:\river-video-app-V3.0\river-watch-runtime-optimization-20260707.zip`
  - SHA256: `9d2436e05975e0963206e0bcc4a433b337f7c55148423860ec3c502c49d417dc`
  - SHA file: `E:\river-video-app-V3.0\river-watch-runtime-optimization-20260707.zip.sha256`

## User Requirements Captured

1. Review the system content, development progress, and quality of the folder.
2. Migrate the complete usable program from the field service for local validation.
3. Provide command lines when direct server access is not possible.
4. Confirm whether omissions exist.
5. Check whether inference service was not started after reboot and whether GPU inference is used.
6. Copy backup/package files into a local verification folder when available.
7. Fix two business issues:
   - Sentinel mode must only control inference. It must not affect already reported realtime anomaly messages.
   - CPU usage reached 100%. GPU should do inference. If transcoding causes CPU pressure, find the best path that both transcodes and lowers CPU usage.
8. Do not solve load only by lowering collection frequency. Use a more suitable high-concurrency architecture and more efficient processing logic.
9. Organize and optimize the whole system into one overwrite package. Avoid:
   - function/menu loss after overwrite,
   - continuously accumulating old system files,
   - bloated deployment,
   - inefficient execution logic.
10. Save the above record to GitHub so other agents can continue.

## Field Findings From Pasted Server Logs

### AI services after reboot

- Initial AI systemd services failed because `/opt/river-watch/ai-pipeline/.venv/bin/python` was missing.
- GPU runtime was installed and smoke-tested:
  - `onnxruntime-migraphx-1.23.2`
  - providers included `MIGraphXExecutionProvider` and `CPUExecutionProvider`
- This confirmed the intended path is GPU inference through ONNX Runtime MIGraphX, with CPU fallback.

### Channel/env generation

- `gen-ai-worker-env.py` needed to exclude reserved `CH11/CH12` from active validation.
- Local and server-side logic were patched so reserved channels do not block live group validation.

### Auth and RTSP

- AI metadata ingest initially hit 401 until `AUTH_TOKEN` was added from `AI_INGEST_TOKEN`.
- RTSP failures showed host `db-managed` resolution errors.
- True RTSP URLs were extracted from MySQL `rw_camera.payload` into `/etc/river-watch/ai-worker-CH01..CH10.env`.
- After that, RTSP connected.

### CPU/GPU pressure

- Before optimization:
  - 10 `ffmpeg` stream relays used `libx264`, each consuming high CPU.
  - Multiple `river_worker.py` processes consumed very high CPU.
  - GPU was saturated.
- Display relay was switched to AMD VAAPI:
  - `h264_vaapi`
  - relay CPU dropped to about 2-3% per ffmpeg process in pasted observations.
- Remaining architectural issue:
  - Original AI design used one process and one ONNX Runtime session per camera.
  - That caused duplicated model sessions, duplicated decode loops, thread contention, and poor high-concurrency behavior.

## Root Cause Summary

1. Sentinel logic was applied too broadly:
   - It suppressed or hid realtime anomaly outputs that had already been generated.
   - Correct behavior: sentinel controls inference on/off only; it must not erase, hide, or suppress already reported alarms/messages.

2. CPU load had two sources:
   - Soft transcoding with `libx264`.
   - One inference worker process/session per camera.

3. Runtime bloat risk:
   - Repeated `.bak-*`, temporary tar files, old frontend hashed assets, and old generated artifacts could pile up.
   - Partial frontend overwrites risk missing route chunks/menu pages because Vite output is hash-based.

## Implemented Local Changes

### Backend

File: `codex-handoff/backend/src/server.mjs`

- Metadata ingestion route for `/api/ai/metadata` and `/api/v1/alarms/metadata` no longer suppresses metadata when sentinel mode is off.
- It now reads the body and always calls `aiIngest.ingest(body)`.
- Sentinel state is still persisted in runtime snapshot, but not used to suppress already submitted AI metadata.

Test updated:

- `codex-handoff/backend/test/api.test.mjs`
- Test name: `persists sentinel shutdown in snapshot without suppressing AI metadata ingestion`
- It asserts metadata ingestion still returns an alarm while sentinel is disabled.

### Frontend store

File: `codex-handoff/frontend/src/stores/platform.ts`

- Realtime anomalies and navigation badges no longer depend on `sentinelEnabled`.
- `selectedAlarm` fallback uses `detectionDerivedPendingAlarms(...)`.
- `pendingAlarms` always uses `realtimePendingAlarms(...)`.
- `navBadgeByKey.monitor` uses the realtime pending alarm count.
- `ensureRealtimeDetectionAlarm` no longer returns early when sentinel is disabled.
- Removed the unused `persistedPendingAlarms` helper.

### Realtime alarm service

File: `codex-handoff/frontend/src/services/realtimeAlarms.ts`

- Added protection against duplicate realtime-derived alarms when a real active alarm already exists for the same camera/type.
- Active real alarms suppress the derived runtime item.
- Archived or false-positive records do not suppress new realtime detections.

Tests updated:

- `codex-handoff/frontend/src/__tests__/navBadges.test.ts`
- `codex-handoff/frontend/src/__tests__/realtimeAlarms.test.ts`
- `codex-handoff/frontend/src/__tests__/streamPlayerStatus.test.ts`

Note: `streamPlayerStatus.test.ts` was aligned with the component's actual `FIRST_FRAME_TIMEOUT_MS = 20_000`.

### AI worker

File: `codex-handoff/ai-pipeline/workers/river_worker.py`

- Added `mask_url(value)` to avoid leaking RTSP credentials in logs.
- Added ONNX Runtime session thread constraints:
  - `ORT_INTRA_OP_NUM_THREADS=1`
  - `ORT_INTER_OP_NUM_THREADS=1`
  - sequential execution mode
- YOLO loads when detectors include `floating` or `structure`.
- Startup logging masks the RTSP URL.

### AI batch worker

New file: `codex-handoff/ai-pipeline/workers/batch_worker.py`

Purpose: replace multiple independent camera inference processes with group-level high-concurrency runners.

Main behavior:

- Reads group env:
  - `CHANNELS`
  - `WORKER_ENV_DIR`
  - `MAX_BATCH_SIZE`
  - `SCHEDULER_TICK_MS`
  - `FRAME_STALE_SEC`
  - `HEARTBEAT_SEC`
  - `SENTINEL_POLL_SEC`
- Reads per-channel env from `/etc/river-watch/ai-worker-CHxx.env`.
- Uses one frame grabber thread per camera and keeps only the latest frame.
- Shares ONNX Runtime sessions by model key.
- Attempts batch inference and falls back to serial inference if a model cannot accept batched input.
- Supports detectors:
  - `floating`
  - `structure`
  - color/level baseline logic where configured.
- Posts metadata using the existing backend contract.
- Polls sentinel state to pause/resume inference only.
- Posts group heartbeat to `/api/v1/ai/worker-status`.
- Posts per-camera heartbeat to `/api/v1/device/status`.
- Masks RTSP URLs in logs.

### systemd

New file: `codex-handoff/deploy/systemd/river-ai-batch@.service`

- Runs `/opt/river-watch/ai-pipeline/.venv/bin/python workers/batch_worker.py`.
- Uses env file `/etc/river-watch/ai-batch-%i.env`.
- Sets conservative thread env values.
- Intended instances:
  - `river-ai-batch@river`
  - `river-ai-batch@structure`

### Runtime installer

New file: `codex-handoff/scripts/apply-runtime-optimization-20260707.sh`

Purpose: bounded, production-oriented overwrite installer.

Key behavior:

- Uses a package directory separate from the live app directory.
- Backs up overwritten files under:
  - `/home/ai-river/river-watch/backups/runtime-optimization/<timestamp>/`
- Keeps only the latest 5 runtime optimization backups.
- Copies whitelisted source files only.
- Clean-overwrites `frontend/dist` so stale hashed assets do not accumulate.
- Copies AI worker files into `/opt/river-watch/ai-pipeline/workers`.
- Installs `/etc/systemd/system/river-ai-batch@.service`.
- Restores business sample rates:
  - `CH01=4`
  - `CH02=4`
  - `CH03=6`
  - `CH04=4`
  - `CH05=4`
  - `CH06=4`
  - `CH07=6`
  - `CH08=4`
  - `CH09=2`
  - `CH10=2`
- Sets `YOLO_IMGSZ=640`.
- Constrains ORT/BLAS thread pools.
- Configures display relay to:
  - `h264_vaapi`
  - fps `12`
  - max width `1280`
- Creates:
  - `/etc/river-watch/ai-batch-river.env`
  - `/etc/river-watch/ai-batch-structure.env`
- Hot-updates backend/frontend containers using `docker cp`, avoiding `docker compose --build` and internet dependency.
- Disables legacy services:
  - `river-ai-group@river-a`
  - `river-ai-group@river-b`
  - `river-ai-group@structure`
- Enables:
  - `river-ai-batch@river`
  - `river-ai-batch@structure`
- Restarts `river-stream-relay@CH01..CH10`.
- Performs targeted cleanup of known old backup files older than 7 days.

### Runtime optimization README

File: `codex-handoff/README_RUNTIME_OPTIMIZATION_20260707.md`

- Documents scope, overwritten files, apply commands, verification commands, expected results, and rollback steps.

## Deliverable Package

Final package:

```text
E:\river-video-app-V3.0\river-watch-runtime-optimization-20260707.zip
```

SHA256:

```text
9d2436e05975e0963206e0bcc4a433b337f7c55148423860ec3c502c49d417dc
```

Package content characteristics:

- 484 entries.
- Linux-friendly zip paths using `/`.
- Contains:
  - backend patch and backend test,
  - frontend source patches,
  - complete rebuilt `frontend/dist`,
  - AI workers,
  - systemd unit,
  - installer,
  - README,
  - `SHA256SUMS`.
- Excludes:
  - `node_modules`,
  - `.git`,
  - `__pycache__`,
  - test result folders,
  - log files,
  - old `.bak-*` files,
  - old `.tar.gz` backups,
  - old zip/model deployment bundles.

## Server Apply Commands

Copy `river-watch-runtime-optimization-20260707.zip` to the server, then run:

```bash
cd /home/ai-river
sha256sum river-watch-runtime-optimization-20260707.zip

rm -rf /tmp/river-watch-runtime-optimization-20260707
mkdir -p /tmp/river-watch-runtime-optimization-20260707
unzip -o river-watch-runtime-optimization-20260707.zip -d /tmp/river-watch-runtime-optimization-20260707

APP_DIR=/home/ai-river/river-watch \
bash /tmp/river-watch-runtime-optimization-20260707/scripts/apply-runtime-optimization-20260707.sh
```

Expected checksum:

```text
9d2436e05975e0963206e0bcc4a433b337f7c55148423860ec3c502c49d417dc
```

## Post-Apply Verification Commands

```bash
systemctl is-active river-ai-batch@river river-ai-batch@structure

systemctl list-units --type=service --state=running \
  'river-ai-batch@*.service' \
  'river-stream-relay@*.service' \
  --no-pager

ps -eo pid,pcpu,pmem,comm,args --sort=-pcpu \
  | sed -E 's#(rtsp://[^:/@]+:)[^@]+@#\1******@#g' \
  | grep -E 'batch_worker|river_worker|ffmpeg|node src/server' \
  | head -30

journalctl -u river-ai-batch@river -u river-ai-batch@structure --since "10 min ago" --no-pager

grep -RHE '^(RELAY_CODEC|RELAY_FPS|RELAY_MAX_WIDTH)=' /etc/river-watch/stream-relay-CH*.env

grep -RHE '^(CHANNELS|MAX_BATCH_SIZE|ORT_INTRA_OP_NUM_THREADS|ORT_INTER_OP_NUM_THREADS)=' /etc/river-watch/ai-batch-*.env
```

Expected:

- `river-ai-batch@river` and `river-ai-batch@structure` are active.
- Legacy AI group units are stopped.
- Relay uses `h264_vaapi`, not `libx264`.
- Backend metadata still creates alarms even when sentinel is off.
- Frontend realtime anomaly badges/messages remain visible when sentinel is off.
- CPU should be lower on ffmpeg relay; AI CPU should improve due to fewer ORT sessions and fewer process-level thread pools.

## Rollback

Backups are written under:

```text
/home/ai-river/river-watch/backups/runtime-optimization/<timestamp>/
```

Manual rollback:

```bash
sudo systemctl disable --now river-ai-batch@river river-ai-batch@structure
sudo systemctl enable --now river-ai-group@river-a river-ai-group@river-b river-ai-group@structure
docker restart deploy-backend-1 deploy-frontend-1
```

Then restore backed-up files from the timestamped backup directory as needed.

## Local Verification Already Completed

Commands/results:

```text
frontend npm run test: 36 files passed, 142 tests passed
frontend npm run build: passed
backend sentinel metadata targeted test: 5 tests passed
node --check backend/src/server.mjs: passed
node --check frontend/dist/assets/index-CtQUtpmY.js: passed
python py_compile batch_worker.py river_worker.py gen-ai-worker-env.py: passed
zip content audit: no node_modules, no __pycache__, no logs, no old backups, no backslash paths
```

Notes:

- Full backend test previously had one unrelated local model-readiness assertion failure around `YOLO26` model availability/status. The targeted sentinel metadata test passed.
- Frontend build warnings from Rolldown/Element Plus pure annotations and chunk size are non-fatal.
- Local folder `C:\Users\TIMI\Documents\TEST` did not exist when checked, so the package was not copied there.

## GitHub Save Status

GitHub target confirmed by user:

```text
heqweasdzxc-maker/--20260517
```

Repository check result:

- Repository exists.
- Visibility: public.
- Default branch: `main`.
- Connector permissions include `push: true` and `admin: true`.

Saved path:

```text
docs/handoff/2026-07-07-river-watch-runtime-optimization.md
```

Recommended commit message:

```text
docs: add river watch runtime optimization handoff
```

If a binary artifact should also be preserved on GitHub, use a GitHub Release or Git LFS. The current connector can reliably create/update UTF-8 text files, but the 98 MB zip should not be committed as a normal repository file unless the repository explicitly supports that policy.
