# 20260711 Local Project Folder Cleanup

## Scope

Local workspace cleaned:

- `E:\river-video-app-V3.0`

## Removed

Removed extracted hotfix/package directories that already had corresponding `.zip` deliverables preserved in the project root:

- `river-watch-alarm-center-sort-hotfix-20260710/`
- `river-watch-alarm-center-source-realtime15-20260710/`
- `river-watch-alarm-flow-hotfix-20260707/`
- `river-watch-alarm-review-evidence-frame-hotfix-20260711/`
- `river-watch-backend-confidence-threshold-hotfix-20260710/`
- `river-watch-batch-worker-cpu-hotfix-20260707/`
- `river-watch-brand-header-20260707/`
- `river-watch-pose-output-decode-hotfix-20260710/`
- `river-watch-realtime-feed-hotfix-20260707/`
- `river-watch-realtime-overflow-hotfix-20260707/`
- `river-watch-realtime-overflow-persist-increment-20260710/`
- `river-watch-realtime-overflow-sticky-increment-20260707/`
- `river-watch-runtime-optimization-20260707/`
- `river-watch-ui-flow-corrections-20260707/`
- `tmp-dist-restore/`

Removed local log files under `codex-handoff`, including old backend/frontend test/build/debug logs.

## Preserved

Kept all source and deliverable files:

- `codex-handoff/`
- all `.zip` deliverable packages
- all `.zip.sha256` checksum files
- `20260710_训练结果.zip`
- project Markdown handoff documents
- requirement/design documents

## Result

Cleanup summary:

- Deleted directories: 15
- Deleted log files: 11
- Space released: about 940.36 MB

Post-cleanup check showed only `codex-handoff/` remains as a top-level directory. No `.log` files remain under the workspace.
