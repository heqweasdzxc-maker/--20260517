# 2026-07-12 River Watch UI and database increment deployment success

## Target

- Host: `192.168.2.167`
- Cutoff: `2026-07-12 01:00:00`
- Successful run timestamp: `20260712-183052`

## Result

The repaired InnoDB temporary-table run completed all nine stages:

- Full database backup before cleanup: completed and gzip-readable.
- Transactional runtime/history cleanup: committed.
- Full database backup after cleanup: completed and gzip-readable.
- Frontend source and production assets: deployed.
- Frontend and backend containers: restarted.
- Obsolete extracted patch directories with retained ZIPs: removed.
- Source markers and HTTP page smoke test: passed.

## Database artifacts

- Before: `/home/ai-river/db-backups/river_watch-before-20260712-183052.sql.gz`
- Before SHA-256: `25b9ede73cf52da5d31368b74b15d74f9cdc63ad5950a1a7882ebf3e91a0962e`
- After: `/home/ai-river/db-backups/river_watch-after-20260712-183052.sql.gz`
- After SHA-256: `74ada34e2f984e15395c0ea6f1c14943f14c16bfd1395ad075b9a2a85353b73a`
- Report: `/home/ai-river/db-backups/river-watch-cleanup-20260712-183052.txt`
- Checksums: `/home/ai-river/db-backups/SHA256SUMS-20260712-183052`
- Frontend rollback: `/home/ai-river/river-watch/backups/ops-ui-db-increment-20260712-20260712-183052`

## Row counts

| Table | Before | After |
|---|---:|---:|
| rw_ai_event | 411599 | 6 |
| rw_alarm | 144500 | 6 |
| rw_work_order | 104 | 0 |
| rw_notification | 194127 | 18 |
| rw_evidence_bundle | 4 | 0 |
| rw_playback_clip | 0 | 0 |
| rw_operation_task | 1 | 0 |
| rw_audit_log | 723040 | 24 |

Other cleaned runtime/history task tables remained at zero.

## Service health

- `deploy-backend-1`: healthy
- `deploy-frontend-1`: healthy
- `deploy-mysql-1`: running
- `http://127.0.0.1:8081/`: returned the production HTML page

The failed `181703` run did not delete data. Its pre-cleanup dump and report are redundant after verification of the successful `183052` before/after pair and may be removed to reclaim about 127 MB.
