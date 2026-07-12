# 2026-07-12 River Watch UI and database maintenance increment

## Deliverable

- Package: `river-watch-ops-ui-db-increment-20260712.zip`
- SHA-256: `1ffdf0aceacdeedf94d0c0c0471f9df7736eff06b6999cec28797b1087fc9e6b`
- Database cutoff: `2026-07-12 01:00:00` (Asia/Shanghai / server local datetime)

## Scope

1. Alarm review no longer uses a current live stream. It resolves persisted alarm-time media from alarm metadata, AI event payload, playback clips, or evidence bundles, then overlays the stored detection boxes. When no persisted media exists, the dialog reports the missing evidence and never substitutes live video.
2. Alarm Center defaults to persisted event time descending, newest first. Clearing a custom sort returns to this default.
3. The apply script creates a complete compressed MySQL dump before cleanup, removes only runtime/history rows older than the explicit cutoff, and creates a second complete dump after cleanup.
4. The cleanup excludes cameras, users, algorithms, models, thresholds, notification rules, storage policies, role permissions, runtime configuration, and status tables.
5. Obsolete extracted patch directories are removed only when their matching ZIP is still present. Historical ZIP deliverables and checksums are retained.

## Changed frontend files

- `frontend/src/views/pages/AlarmsPage.vue`
- `frontend/src/components/WorkspaceDialogs.vue`
- `frontend/src/composables/useWorkspace.ts`
- `frontend/src/styles.css`
- `frontend/src/__tests__/alarmsFilterLayout.test.ts`
- `frontend/src/__tests__/alarmFlowSimplification.test.ts`
- `frontend/src/__tests__/alarmReviewDialog.test.ts`
- Current production `frontend/dist`

## Database tables cleaned

- `rw_ai_event`
- `rw_alarm`
- `rw_work_order`
- `rw_notification`
- `rw_evidence_bundle`
- `rw_playback_clip`
- `rw_import_job`
- `rw_operation_task`
- `rw_report_task`
- `rw_export_task`
- `rw_log_search_job`
- `rw_ops_run`
- `rw_audit_log`

Dependent rows are deleted before alarms, inside one transaction. The apply script verifies both gzip dumps and writes SHA-256 checksums plus before/after row counts.

## Verification

- Focused tests: 15 passed.
- Full frontend suite: 37 files, 147 tests passed.
- `vue-tsc --noEmit && vite build`: passed.
- 478 package-internal SHA-256 entries: passed.
- ZIP top-level directory and Linux LF script line endings: verified.
- Build produced only known third-party Rolldown PURE annotation and large-chunk warnings.

## Apply

```bash
cd /home/ai-river
sha256sum river-watch-ops-ui-db-increment-20260712.zip
unzip -o river-watch-ops-ui-db-increment-20260712.zip
cd river-watch-ops-ui-db-increment-20260712
chmod +x scripts/apply-ops-ui-db-increment-20260712.sh
sudo -v
APP_DIR=/home/ai-river/river-watch \
  CUTOFF='2026-07-12 01:00:00' \
  ./scripts/apply-ops-ui-db-increment-20260712.sh
```

The script prints the frontend rollback directory, pre-cleanup database dump, post-cleanup database dump, checksum file, and row-count report.

## Evidence limitation

Old alarms that never persisted an image/clip URL cannot be reconstructed retroactively. They now show an explicit evidence-missing state instead of a misleading live stream. New alarms display historical media whenever the ingest/NVR evidence contract supplies a persisted URL.
