# 2026-07-12 Alarm-time evidence snapshot increment

## Problem

Alarm review displayed the persisted detection boxes and timestamp but had no alarm-time image or clip behind them. The previous UI correctly refused to substitute the current live stream, exposing that the ingest pipeline never persisted media evidence.

## Solution

A compact end-to-end snapshot path was added without changing AI models or worker scheduling:

1. After a new alarm is persisted, the backend asynchronously captures one JPEG from the inference/source stream with ffmpeg.
2. The JPEG is stored in a dedicated `rw_alarm_evidence` table as a MEDIUMBLOB, not embedded in `rw_alarm`, `rw_ai_event`, or the platform snapshot.
3. `GET /api/alarm/alarms/:id/evidence` returns the binary image through the normal authenticated application API.
4. Alarm review fetches the image with the user's bearer token and overlays the original persisted detection boxes.
5. Duplicate/merged alarms reuse their first evidence image. Evidence rows cascade-delete with alarms.
6. The default cap is 5,000 images, with a two-capture concurrency limit and bounded queue, timeout, dimensions and image size.
7. Capture failure never blocks alarm ingestion or notification dispatch.
8. Historical alarms that never stored media cannot be reconstructed and retain the explicit missing-evidence message.

## Changed files

Backend:

- `backend/src/alarm-evidence.mjs` (new)
- `backend/src/ai-ingest.mjs`
- `backend/src/store.mjs`
- `backend/src/server.mjs`
- `backend/test/alarm-evidence.test.mjs` (new)

Frontend:

- `frontend/src/composables/useWorkspace.ts`
- `frontend/src/components/WorkspaceDialogs.vue`
- `frontend/src/styles.css`
- `frontend/src/__tests__/alarmReviewDialog.test.ts`
- Compact production `index.html` and `assets/` only

## Deliverable

- Package: `river-watch-alarm-evidence-snapshot-increment-20260712.zip`
- SHA-256: `2f094a105ea7eff4bab7c761019257f8292cd0c127e836c53c3bbbb857e5e24b`
- Size: 1,154,719 bytes
- Digital-twin data, models and training outputs are excluded.

## Verification

- Backend evidence capture/store/API tests: 4 passed.
- Backend changed modules: `node --check` passed.
- Frontend focused tests: 5 passed.
- Frontend full suite: 37 files / 148 tests passed.
- Frontend production build: passed.
- Package internal SHA-256 verification and Linux LF script check: passed.
- The broader backend suite has one pre-existing environment-dependent failure for registration of a real YOLO26 model file; evidence tests pass and the failure is unrelated to this change.

## Apply

```bash
cd /home/ai-river
sha256sum river-watch-alarm-evidence-snapshot-increment-20260712.zip
unzip -o river-watch-alarm-evidence-snapshot-increment-20260712.zip
cd river-watch-alarm-evidence-snapshot-increment-20260712
chmod +x scripts/apply-alarm-evidence-snapshot-increment-20260712.sh
sudo -v
APP_DIR=/home/ai-river/river-watch ./scripts/apply-alarm-evidence-snapshot-increment-20260712.sh
```
