# 20260711 Alarm Review Evidence Frame Hotfix

## Background

The user reported a major logic bug in the alarm center review dialog: when clicking review on an existing alarm, the dialog should show the alarm-time evidence clip/frame with anomaly boxes, not the current live stream with a newly overlaid box.

Root cause confirmed in the frontend:

- `WorkspaceDialogs.vue` used `<StreamPlayer :camera="selectedAlarmReviewCamera" :sentinel="true" />` inside the alarm review dialog.
- `useWorkspace.ts` built `selectedAlarmReviewCamera` from the current camera and synthesized a detection box when the live camera did not already contain the alarm type.
- This made review evidence depend on current live video instead of persisted alarm-time AI metadata.

## Change

This hotfix changes the review dialog to render a persisted evidence frame:

- Removed the alarm review dialog dependency on `selectedAlarmReviewCamera` and live `StreamPlayer`.
- Added `selectedAlarmEvidenceEvent`, matched from `platform.aiEvents` by alarm id.
- Added `selectedAlarmEvidenceBoxes`, derived from persisted AI event `request.boxes` / `request.detections`.
- Added `selectedAlarmEvidenceTime`, derived from alarm/event metadata.
- Added `evidenceBoxStyle()` and coordinate normalization for 0-1 or 0-100 box coordinate formats.
- Updated dialog UI to show `告警证据片段` and overlay persisted boxes on an evidence frame.
- Added regression tests so the dialog cannot silently return to live-stream review.

Changed files:

- `frontend/src/components/WorkspaceDialogs.vue`
- `frontend/src/composables/useWorkspace.ts`
- `frontend/src/styles.css`
- `frontend/src/__tests__/alarmFlowSimplification.test.ts`
- `frontend/src/__tests__/alarmReviewDialog.test.ts`
- `frontend/dist/`

## Package

Local package generated:

- `river-watch-alarm-review-evidence-frame-hotfix-20260711.zip`
- SHA256: `e0802a830beca381ed6d4ad28d3a3ac67241cec8689d2254169d8e9be4f770dd`
- Size: about 94 MB

Package contents include source files, tests, frontend dist, README, SHA256SUMS, and apply script:

- `scripts/apply-alarm-review-evidence-frame-hotfix-20260711.sh`

## Verification

Executed locally under `E:\river-video-app-V3.0\codex-handoff\frontend`:

```bash
npm test -- alarmFlowSimplification.test.ts alarmReviewDialog.test.ts
npm test
npm run build
```

Results:

- Targeted tests: 2 files / 11 tests passed.
- Full frontend tests: 37 files / 145 tests passed.
- Production build passed.
- Build still prints existing third-party Rolldown PURE annotation warnings and chunk-size warnings; these are unrelated.

## Deploy Commands On 192.168.2.167

After uploading `river-watch-alarm-review-evidence-frame-hotfix-20260711.zip` to `/home/ai-river`:

```bash
set -e
cd /home/ai-river
sha256sum river-watch-alarm-review-evidence-frame-hotfix-20260711.zip
unzip -o river-watch-alarm-review-evidence-frame-hotfix-20260711.zip
cd river-watch-alarm-review-evidence-frame-hotfix-20260711
chmod +x scripts/apply-alarm-review-evidence-frame-hotfix-20260711.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-alarm-review-evidence-frame-hotfix-20260711.sh
```

Expected SHA256:

```text
e0802a830beca381ed6d4ad28d3a3ac67241cec8689d2254169d8e9be4f770dd
```

## Post-Deploy Check

Open:

- `http://192.168.2.167:8081/alarms`

Click an alarm's review button. The dialog should show `告警证据片段`, not a live video player. It should render anomaly boxes from the persisted AI event if the alarm is linked to an `rw_ai_event` record.

Important limitation: this hotfix uses the existing persisted AI metadata in `rw_ai_event`. It does not yet implement actual historical video clip cutting/storage. If a future requirement is to play the real historical video segment, backend recording/clip retrieval must be added as a separate feature rather than falling back to live video.
