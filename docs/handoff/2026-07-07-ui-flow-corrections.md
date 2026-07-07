# UI flow corrections handoff - 2026-07-07

## User-reported issues

1. Realtime anomaly and Alarm Center message lists need a clear distinction:
   - Realtime anomaly card should show the current newest messages only.
   - Temporary display size is 15 messages.
   - Messages enter the realtime card as they are produced and leave by FIFO/overflow.
   - Messages leaving the realtime card should enter the Alarm Center list.
   - The circular floating alarm icon should be synchronized with the realtime anomaly card.
2. Evidence chain one-click filing was unclear and always produced an evidence package for one default device/alarm.
3. Link Diagnosis acceptance ledger card was unclear and can be removed if it has no value.
4. Alarm Center current list should not show archived records by default, but archived records must remain searchable through history query.

## Root cause

- `pendingAlarms` had no fixed 15-message display limit.
- `alarmRows` and realtime messages were not separated into current-display, overflow/current-center, and history-query sources.
- Evidence filing used `selectedAlarm || alarms[0]`, which could silently use the first/default alarm.
- Link Diagnosis still rendered the old `ops-run-panel` acceptance ledger.
- Alarm Center used one source for both current list and history query, so archived records could appear in the default list.

## Local changes

Changed:

- `codex-handoff/frontend/src/stores/platform.ts`
  - Added `REALTIME_ALARM_FEED_LIMIT = 15`.
  - `pendingAlarms` now returns only the newest 15 realtime detection messages.
  - Realtime overflow messages enter `alarmRows`.
  - Added `alarmHistoryRows` for history query, including archived records.
  - `alarmRows` excludes archived and false-positive records by default.
  - `createEvidenceBundle(alarmId?: string)` now requires an explicit selected alarm when called from Evidence page and no longer falls back to `alarms[0]`.
- `codex-handoff/frontend/src/views/pages/AlarmsPage.vue`
  - Added `alarmQueryActive`.
  - Default list uses `platform.alarmRows`.
  - Filter/search query mode uses `platform.alarmHistoryRows`.
- `codex-handoff/frontend/src/views/pages/EvidencePage.vue`
  - Added `selectedEvidenceAlarmId` and `evidenceAlarmOptions`.
  - Evidence filing button now reads `为选中告警组卷`.
  - The action calls `createEvidenceBundle(selectedEvidenceAlarmId)`.
- `codex-handoff/frontend/src/composables/useWorkspace.ts`
  - `createEvidenceBundle` now accepts an optional alarm ID and passes it to the store.
- `codex-handoff/frontend/src/views/pages/DiagPage.vue`
  - Removed acceptance ledger card.
  - Removed related ops-run pagination logic.
- `codex-handoff/frontend/src/styles.css`
  - Removed dead `ops-run-*` / `ops-message-*` styles.
- Tests updated:
  - `navBadges.test.ts`
  - `alarmFlowSimplification.test.ts`
  - `evidencePageLayout.test.ts`
  - `diagOpsMerge.test.ts`

## Verification

From `codex-handoff/frontend`:

```bash
npm run test -- src/__tests__/navBadges.test.ts src/__tests__/alarmFlowSimplification.test.ts src/__tests__/evidencePageLayout.test.ts src/__tests__/diagOpsMerge.test.ts
npm run test
npm run build
```

Observed:

- Target tests: `21` passed.
- Full frontend tests: `36` test files, `145` tests passed.
- Production build completed successfully.
- Remaining build warnings are existing dependency annotation/chunk-size warnings.

## Delivery package

Package:

- `river-watch-ui-flow-corrections-20260707.zip`
- Size: `98160545` bytes
- SHA256: `ff49245724348056ff87fe6522f65cc3fa8487800ce8223824374a4c8596997c`

The zip was generated with Linux-friendly forward-slash paths and contains:

- changed source files
- updated tests
- full `frontend/dist`
- `scripts/apply-ui-flow-corrections-20260707.sh`
- `README_UI_FLOW_CORRECTIONS_20260707.md`
- `SHA256SUMS`

## Server apply commands

```bash
cd /home/ai-river
sha256sum river-watch-ui-flow-corrections-20260707.zip
unzip -o river-watch-ui-flow-corrections-20260707.zip -d /home/ai-river/
cd /home/ai-river/river-watch-ui-flow-corrections-20260707
chmod +x scripts/apply-ui-flow-corrections-20260707.sh
scripts/apply-ui-flow-corrections-20260707.sh
```

If sudo needs non-interactive password:

```bash
SUDO_PASSWORD='your-password' scripts/apply-ui-flow-corrections-20260707.sh
```

Post-apply checks:

```bash
cd /home/ai-river/river-watch
grep -RHE 'REALTIME_ALARM_FEED_LIMIT|alarmHistoryRows|selectedEvidenceAlarmId|evidenceAlarmOptions|alarmQueryActive' \
  frontend/src/stores/platform.ts \
  frontend/src/views/pages/AlarmsPage.vue \
  frontend/src/views/pages/EvidencePage.vue

grep -RHE 'ops-run-panel|验收台账' frontend/src/views/pages/DiagPage.vue || echo 'diagnostic ledger removed'

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'frontend|nginx|backend' || true
```
