# Brand/Header Update 2026-07-07

## Scope

This record preserves the latest frontend branding/header change for River Watch / AI video analysis system handoff.

## Requested Changes

- Change the top-left brand text from `River-Watch` to `AI视频分析系统`.
- Add the centered top navigation title `洋河股份泗阳基地安环部`.
- Remove old route/page title text from the top-left area, including display patterns such as `实时视频墙` and `实时监管/实时视频墙`.
- Remove the visible `实时视频墙` heading from the realtime monitor page panel while keeping the toolbar controls and menu logic.

## Local Files Changed

- `codex-handoff/frontend/src/components/AppShell.vue`
- `codex-handoff/frontend/src/views/pages/MonitorPage.vue`
- `codex-handoff/frontend/src/styles.css`
- `codex-handoff/frontend/src/__tests__/uiCommandCenter.test.ts`
- `codex-handoff/frontend/src/__tests__/monitorHeaderCleanup.test.ts`

## Package

- Local directory: `E:\river-video-app-V3.0\river-watch-brand-header-20260707`
- Local archive: `E:\river-video-app-V3.0\river-watch-brand-header-20260707.zip`
- Archive SHA256: `8bbf5e814cf8b35460fcfde1e7d8a338fc61c1a830dbcc7f5d369570abd849b3`
- Zip entries checked: 477
- Required files missing from zip: none

## Included Package Files

- `frontend/src/components/AppShell.vue`
- `frontend/src/views/pages/MonitorPage.vue`
- `frontend/src/styles.css`
- `frontend/src/__tests__/uiCommandCenter.test.ts`
- `frontend/src/__tests__/monitorHeaderCleanup.test.ts`
- `frontend/dist/`
- `scripts/apply-brand-header-20260707.sh`
- `README.md`
- `SHA256SUMS`

## Verification Commands Run

From `E:\river-video-app-V3.0\codex-handoff\frontend`:

```bash
npm run test -- src/__tests__/uiCommandCenter.test.ts src/__tests__/monitorHeaderCleanup.test.ts
npm run test
npm run build
```

Observed result:

- Target tests passed: 2 test files, 5 tests.
- Full test suite passed: 37 test files, 146 tests.
- Production build completed successfully.
- Build warnings only: existing Rolldown pure annotation warnings in `@vueuse/core` and chunk size warning.

## Marker Check

Present in source/build package:

- `AI视频分析系统`
- `洋河股份泗阳基地安环部`
- `topbar-title`
- `video-toolbar-title`

Removed from the relevant source files:

- `route-title__main`
- `route-title__sub`
- `routeSubtitle`
- `<h2>实时视频墙</h2>`

Note: `River-Watch不落盘录像文件` remains in storage-policy wording and is not the top-left product brand.

## Server Apply Command

Upload `river-watch-brand-header-20260707.zip` to `/home/ai-river` on `192.168.2.167`, then run:

```bash
set -e
cd /home/ai-river
sha256sum river-watch-brand-header-20260707.zip
unzip -o river-watch-brand-header-20260707.zip
cd river-watch-brand-header-20260707
chmod +x scripts/apply-brand-header-20260707.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-brand-header-20260707.sh
```

Expected SHA256:

```text
8bbf5e814cf8b35460fcfde1e7d8a338fc61c1a830dbcc7f5d369570abd849b3  river-watch-brand-header-20260707.zip
```

The apply script creates a backup under:

```text
/home/ai-river/river-watch/backups/brand-header-YYYYMMDD-HHMMSS
```

## Notes

The local Windows environment does not currently expose a `git` command, so this handoff was saved through the GitHub connector rather than a local git commit/push workflow.
