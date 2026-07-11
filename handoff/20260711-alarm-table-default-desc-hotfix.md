# 20260711 Alarm Table Default Desc Hotfix

## Requirement

The alarm center list must default to reverse chronological order: newest alarm time at the top.

User screenshot highlighted the time column and requested default descending time order.

## Root Cause / Risk

The local frontend already sorted alarm rows by `alarmSort` with `{ prop: 'time', order: 'descending' }`, and `alarmSortValue()` used persisted timestamps before display-only `time` text.

However, the Element Plus table did not explicitly bind `default-sort`, and when sort order became null/empty, `sortedAlarms` returned raw source order. This could make the visible table state unstable after refresh, filter/history switching, or clearing table sort.

## Change

Updated `frontend/src/views/pages/AlarmsPage.vue`:

- Added:

```ts
const alarmDefaultSort = { prop: 'time', order: 'descending' } as const;
```

- Initialized sorting from `alarmDefaultSort`.
- Bound the table default sort:

```vue
:default-sort="alarmDefaultSort"
```

- Changed sort-change behavior so null/cleared order falls back to time descending:

```ts
alarmSort.value = order ? { prop: (prop || 'time') as AlarmSortProp, order } : { ...alarmDefaultSort };
```

## Related consistency files included in package

The package also includes current alarm-review evidence-frame source files so source and bundled `dist` remain consistent on the server:

- `frontend/src/components/WorkspaceDialogs.vue`
- `frontend/src/composables/useWorkspace.ts`
- `frontend/src/styles.css`
- `frontend/src/__tests__/alarmFlowSimplification.test.ts`
- `frontend/src/__tests__/alarmReviewDialog.test.ts`

## Package

Generated local package:

- `river-watch-alarm-table-default-desc-hotfix-20260711.zip`
- SHA256: `f758314675c093e86359aaf99d27349f460c55feff1c898b0834f20b07f58ddd`
- Size: about 94 MB

Package includes:

- source files
- frontend `dist`
- README
- SHA256SUMS
- apply script: `scripts/apply-alarm-table-default-desc-hotfix-20260711.sh`

The apply script automatically uses `sudo` for root-owned frontend files.

## Verification

Executed locally under `E:\river-video-app-V3.0\codex-handoff\frontend`:

```bash
npm test -- alarmsFilterLayout.test.ts
npm test
npm run build
```

Results:

- Targeted test: 1 file / 3 tests passed.
- Full frontend tests: 37 files / 146 tests passed.
- Production build passed.
- Build still prints existing third-party Rolldown PURE annotation and chunk-size warnings; unrelated.

## Deploy Commands On 192.168.2.167

After uploading `river-watch-alarm-table-default-desc-hotfix-20260711.zip` to `/home/ai-river`:

```bash
set -e
cd /home/ai-river
sha256sum river-watch-alarm-table-default-desc-hotfix-20260711.zip
unzip -o river-watch-alarm-table-default-desc-hotfix-20260711.zip
cd river-watch-alarm-table-default-desc-hotfix-20260711
chmod +x scripts/apply-alarm-table-default-desc-hotfix-20260711.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-alarm-table-default-desc-hotfix-20260711.sh
```

Expected SHA256:

```text
f758314675c093e86359aaf99d27349f460c55feff1c898b0834f20b07f58ddd
```

## Post-Deploy Check

```bash
set -e
sudo grep -RHE 'alarmDefaultSort|default-sort' \
  /home/ai-river/river-watch/frontend/src/views/pages/AlarmsPage.vue

docker exec deploy-frontend-1 sh -lc "grep -R 'default-sort\|alarmDefaultSort' -n /usr/share/nginx/html/assets | head -20 || true"

curl -fsS http://127.0.0.1:8081/ | head -5
```

UI expectation:

- Open `http://192.168.2.167:8081/alarms`.
- Alarm center list defaults to newest time first.
- Clearing table sort should still return to newest time first.
