# Realtime Feed Hotfix 2026-07-07

## Field Feedback

The server execution receipt showed the previous brand/header package failed during source overwrite:

```text
cp: cannot create regular file '/home/ai-river/river-watch/frontend/src/styles.css': permission denied
```

The user also reported: realtime anomaly card has no messages even though alarms have already occurred.

## Root Cause

The frontend store computed realtime anomaly rows from `camera.detections` only. When the backend had already accepted AI metadata and created pending alarm records, but the platform camera snapshot did not include corresponding `detections`, the realtime anomaly card stayed empty.

In short:

- Backend alarm existed in `alarms`.
- Camera `detections` could be empty.
- `platform.pendingAlarms` ignored persisted backend pending alarms.
- Therefore the realtime anomaly card and monitor badge could show zero.

## Code Fix

Changed `codex-handoff/frontend/src/stores/platform.ts`:

```ts
import { detectionDerivedPendingAlarms, isRuntimeDetectionAlarmId, normalizeConfidencePercent, realtimePendingAlarms, type ConfidenceThresholds } from '../services/realtimeAlarms';
```

`realtimeRowsForState(...)` now uses:

```ts
return realtimePendingAlarms(state.cameras, state.alarms, state.dismissedRuntimeDetectionAlarmIds, [], state.confidenceThresholds)
  .sort(compareRealtimeAlarmRows);
```

This merges:

- runtime camera detections
- persisted backend pending-review alarms

The alarm center still excludes messages currently visible in the realtime FIFO list, so one alarm is not duplicated in realtime anomaly and alarm center at the same time.

## Regression Test

Updated `codex-handoff/frontend/src/__tests__/navBadges.test.ts`.

New scenario:

- camera `detections` is empty
- backend `alarms` contains a `pending-review` alarm
- realtime anomaly feed must show that alarm
- alarm center must not duplicate it while it is in realtime FIFO

Red test before fix:

```text
expected [] to deeply equal [ 'A-BACKEND-1' ]
```

After fix:

```text
navBadges.test.ts: 9 tests passed
```

## Verification

From `E:\river-video-app-V3.0\codex-handoff\frontend`:

```bash
npm run test -- src/__tests__/navBadges.test.ts
npm run test
npm run build
```

Observed result:

- `navBadges.test.ts`: 9 tests passed.
- Full frontend suite: 37 files, 147 tests passed.
- Production build completed successfully.
- Build warnings only: existing Rolldown pure annotation warnings in `@vueuse/core` and chunk size warning.

## Cumulative Package

This package includes both the previous brand/header cleanup and the realtime anomaly feed fix.

- Local directory: `E:\river-video-app-V3.0\river-watch-realtime-feed-hotfix-20260707`
- Local archive: `E:\river-video-app-V3.0\river-watch-realtime-feed-hotfix-20260707.zip`
- Archive SHA256: `b4b02a604e185dacbb66818392462f6dc6660bf251cc07b2f51a14faa56753b8`
- Zip entries checked: 479
- Required files missing from zip: none

Included key files:

- `frontend/src/components/AppShell.vue`
- `frontend/src/views/pages/MonitorPage.vue`
- `frontend/src/styles.css`
- `frontend/src/stores/platform.ts`
- `frontend/src/__tests__/uiCommandCenter.test.ts`
- `frontend/src/__tests__/monitorHeaderCleanup.test.ts`
- `frontend/src/__tests__/navBadges.test.ts`
- `frontend/dist/`
- `scripts/apply-realtime-feed-hotfix-20260707.sh`
- `README.md`
- `SHA256SUMS`

## Server Apply Command

Upload `river-watch-realtime-feed-hotfix-20260707.zip` to `/home/ai-river` on `192.168.2.167`, then run:

```bash
set -e
cd /home/ai-river
sha256sum river-watch-realtime-feed-hotfix-20260707.zip
unzip -o river-watch-realtime-feed-hotfix-20260707.zip
cd river-watch-realtime-feed-hotfix-20260707
chmod +x scripts/apply-realtime-feed-hotfix-20260707.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-feed-hotfix-20260707.sh
```

Expected SHA256:

```text
b4b02a604e185dacbb66818392462f6dc6660bf251cc07b2f51a14faa56753b8  river-watch-realtime-feed-hotfix-20260707.zip
```

The script backs up current frontend files under:

```text
/home/ai-river/river-watch/backups/realtime-feed-hotfix-YYYYMMDD-HHMMSS
```

## Permission Handling

The apply script uses `sudo install` for source files and `sudo cp` for dist, so it is designed to handle the prior permission failure on `frontend/src/styles.css`.

## Post-Apply Diagnostic Commands

After applying, verify backend alarms and frontend realtime markers:

```bash
set -e
cd /home/ai-river/river-watch

grep -RHE 'realtimePendingAlarms|A-BACKEND-1' frontend/src/stores/platform.ts frontend/src/__tests__/navBadges.test.ts

grep -RHE 'AI视频分析系统|洋河股份泗阳基地安环部|topbar-title|video-toolbar-title' \
  frontend/src/components/AppShell.vue \
  frontend/src/views/pages/MonitorPage.vue \
  frontend/src/styles.css

curl -fsS http://127.0.0.1/api/platform/snapshot | head -c 2000
```

If realtime anomaly still appears empty after this patch, the next diagnostic boundary is whether `/api/platform/snapshot` actually returns `alarms` with pending-review-like status and recent timestamps.
