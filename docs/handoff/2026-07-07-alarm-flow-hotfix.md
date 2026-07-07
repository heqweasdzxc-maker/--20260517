# Alarm flow hotfix handoff - 2026-07-07

## User requirement

The user reported that Alarm Center had no messages. Expected behavior:

- Realtime anomaly card shows only current realtime messages.
- Alarm Center receives the realtime anomaly message list and also supports alarm history query.
- Event Situation further filters, classifies, and deduplicates Alarm Center messages.
- Aggregation windows:
  - 提示: 6 hours
  - 一般: 3 hours
  - 严重: 1 hour
  - 紧急: 30 minutes
- After aggregation, one unified message enters review.
- In the review dialog, choosing ignored or handled sends the message into the work-order loop.
- In the work-order loop, confirming archive moves it to work-order query and hides it from the active loop.

The user said there were two issues, but only issue 1 was present in the latest message. Issue 2 still needs a separate description.

## Root cause

`frontend/src/stores/platform.ts` had this Alarm Center getter:

```ts
alarmRows(state): Alarm[] {
  return state.alarms.filter((alarm) => alarm.status === '已派单' || Boolean(alarm.dispatchId));
}
```

This intentionally excluded pending review alarms, so Alarm Center could appear empty even while realtime anomaly messages existed.

`pendingAlarms` also used the mixed realtime helper, so persisted pending alarms could show in the realtime card. Event Situation used `dedupeAlarms(state.alarms)` with a fixed `60` second dedupe window, which did not match the severity-specific aggregation requirement.

## Local changes

Changed:

- `codex-handoff/frontend/src/stores/platform.ts`
  - Added `currentRealtimeRowsForState`.
  - Added `alarmCenterRowsForState`.
  - Added `activeAlarmCenterRowsForState`.
  - `pendingAlarms` now returns only current realtime detection-derived messages.
  - `alarmRows` now returns current realtime messages plus persisted alarm history.
  - `dedupedAlarms` now aggregates active Alarm Center messages.
  - nav badges now use current realtime count for monitor and active Alarm Center count for alarms.
- `codex-handoff/frontend/src/services/business.ts`
  - Added severity aggregation windows: 提示 21600s, 一般 10800s, 严重 3600s, 紧急 1800s.
  - Updated `dedupeAlarms` to use fixed aggregation buckets anchored on the first event in the bucket.
  - Preserved the latest alarm metadata in each merged bucket for review entry.
- `codex-handoff/frontend/src/views/pages/EventsPage.vue`
  - Event KPI merged count now uses `platform.alarmRows`.
  - Badge text changed from fixed `60s 去重` to severity-window aggregation.
- Tests updated:
  - `business.test.ts`
  - `navBadges.test.ts`
  - `alarmFlowSimplification.test.ts`

## Verification

From `codex-handoff/frontend`:

```bash
npm run test -- src/__tests__/business.test.ts src/__tests__/navBadges.test.ts src/__tests__/alarmFlowSimplification.test.ts
npm run test
npm run build
```

Observed:

- Target tests: `23` passed.
- Full frontend tests: `36` test files, `143` tests passed.
- Production build completed successfully.
- Build warning only:
  - Rolldown ignored existing dependency `/* #__PURE__ */` annotations in `@vueuse/core`.
  - Some existing chunks exceed 500 kB.

## Delivery package

Package:

- `river-watch-alarm-flow-hotfix-20260707.zip`
- Size: `98124648` bytes
- SHA256: `b1f75851bdd316d9e9dbc361ac10745bfedb9f84967a43bc3a35a10f3edecd65`

The zip was generated with Linux-friendly forward-slash paths and contains:

- `frontend/src/stores/platform.ts`
- `frontend/src/services/business.ts`
- `frontend/src/views/pages/EventsPage.vue`
- updated tests
- full `frontend/dist`
- `scripts/apply-alarm-flow-hotfix-20260707.sh`
- `SHA256SUMS`
- `README_ALARM_FLOW_HOTFIX_20260707.md`

## Server apply commands

```bash
cd /home/ai-river
sha256sum river-watch-alarm-flow-hotfix-20260707.zip
unzip -o river-watch-alarm-flow-hotfix-20260707.zip -d /home/ai-river/
cd /home/ai-river/river-watch-alarm-flow-hotfix-20260707
chmod +x scripts/apply-alarm-flow-hotfix-20260707.sh
scripts/apply-alarm-flow-hotfix-20260707.sh
```

If sudo needs non-interactive password:

```bash
SUDO_PASSWORD='your-password' scripts/apply-alarm-flow-hotfix-20260707.sh
```

Post-apply check:

```bash
cd /home/ai-river/river-watch
grep -RHE 'alarmCenterRowsForState|currentRealtimeRowsForState|severityAggregationWindowSeconds|分级时间窗归集' \
  frontend/src/stores/platform.ts \
  frontend/src/services/business.ts \
  frontend/src/views/pages/EventsPage.vue
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|backend' || true
```
