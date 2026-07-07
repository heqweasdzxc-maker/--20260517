# Realtime Overflow Hotfix 2026-07-07

## Field Feedback

Realtime anomaly messages beyond 15 rows did not enter the alarm center.

## Root Cause

The frontend store filtered hidden/dispatched realtime IDs before slicing the first 15 realtime rows. That allowed row 16 to refill the realtime anomaly card when a row in the first 15 was hidden/dispatched. Under the required FIFO rule, rows 1-15 are the realtime card window and rows 16+ must be alarm-center overflow.

Old behavior:

```ts
realtimeRowsForState(state)
  .filter((alarm) => !dispatched.has(alarm.id))
  .slice(0, REALTIME_ALARM_FEED_LIMIT)
```

Because filtering happened before slicing, the raw 16th message could move back into the realtime card and not appear in the alarm center.

## Code Fix

Changed `codex-handoff/frontend/src/stores/platform.ts`.

New behavior:

```ts
function realtimeFeedSplitForState(state: AlarmFlowState) {
  const rows = realtimeRowsForState(state);
  return {
    current: rows.slice(0, REALTIME_ALARM_FEED_LIMIT),
    overflow: rows.slice(REALTIME_ALARM_FEED_LIMIT),
  };
}

function currentRealtimeRowsForState(state: AlarmFlowState): Alarm[] {
  const dispatched = new Set(state.dispatchedRealtimeAlarmIds);
  return realtimeFeedSplitForState(state).current.filter((alarm) => !dispatched.has(alarm.id));
}

function overflowRealtimeRowsForState(state: AlarmFlowState): Alarm[] {
  return realtimeFeedSplitForState(state).overflow;
}
```

The fix makes overflow stable by raw FIFO order:

- raw rows 1-15: realtime anomaly card
- raw rows 16+: alarm center
- dispatched/hidden filtering only affects what remains visible inside the realtime card; it no longer pulls overflow rows back into realtime

## Regression Tests

Updated `codex-handoff/frontend/src/__tests__/navBadges.test.ts`.

Added coverage:

- persisted UTF-8 pending backend alarms beyond 15 enter alarm center
- raw realtime FIFO overflow remains in alarm center instead of refilling hidden realtime slots

The failing test before the fix showed `RT-CH01-D-01` incorrectly refilled the realtime card. After the fix it appears in `alarmRows`.

## Verification

From `E:\river-video-app-V3.0\codex-handoff\frontend`:

```bash
npm run test -- src/__tests__/navBadges.test.ts
npm run test
npm run build
```

Observed result:

- `navBadges.test.ts`: 11 tests passed.
- Full frontend suite: 37 files, 149 tests passed.
- Production build completed successfully.
- Build warnings only: existing Rolldown pure annotation warnings in `@vueuse/core` and chunk size warning.

## Package

This package is cumulative and includes previous brand/header and realtime backend pending-alarm fixes.

- Local directory: `E:\river-video-app-V3.0\river-watch-realtime-overflow-hotfix-20260707`
- Local archive: `E:\river-video-app-V3.0\river-watch-realtime-overflow-hotfix-20260707.zip`
- Archive SHA256: `02017b637bc0cce2d6ebc6d297efb3685ee6b0ff6b2c1206258a881b8f7de869`
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
- `scripts/apply-realtime-overflow-hotfix-20260707.sh`
- `README.md`
- `SHA256SUMS`

## Server Apply Command

Upload `river-watch-realtime-overflow-hotfix-20260707.zip` to `/home/ai-river` on `192.168.2.167`, then run:

```bash
set -e
cd /home/ai-river
sha256sum river-watch-realtime-overflow-hotfix-20260707.zip
unzip -o river-watch-realtime-overflow-hotfix-20260707.zip
cd river-watch-realtime-overflow-hotfix-20260707
chmod +x scripts/apply-realtime-overflow-hotfix-20260707.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-realtime-overflow-hotfix-20260707.sh
```

Expected SHA256:

```text
02017b637bc0cce2d6ebc6d297efb3685ee6b0ff6b2c1206258a881b8f7de869  river-watch-realtime-overflow-hotfix-20260707.zip
```

The script backs up current frontend files under:

```text
/home/ai-river/river-watch/backups/realtime-overflow-hotfix-YYYYMMDD-HHMMSS
```

## Post-Apply Checks

```bash
set -e
cd /home/ai-river/river-watch

grep -RHE 'realtimeFeedSplitForState|overflowRealtimeRowsForState|raw realtime FIFO|A-UTF8-01' \
  frontend/src/stores/platform.ts \
  frontend/src/__tests__/navBadges.test.ts

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

If the UI still does not show overflow rows in the alarm center after applying this package, the next diagnostic boundary is the live `/api/platform/snapshot` payload: verify whether it actually returns more than 15 pending realtime messages or only the first 15.
