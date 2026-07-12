# 2026-07-12 DB cleanup MEMORY limit failure and v2 repair

## Server receipt

The first apply of `river-watch-ops-ui-db-increment-20260712.zip` stopped during database cleanup with:

```text
ERROR 1114 (HY000) at line 6: The table 'tmp_old_alarm_ids' is full
```

The failure occurred while populating the temporary old-alarm ID table, before the first DELETE statement. The MySQL client disconnected and the open transaction rolled back. No database rows were deleted. Frontend deployment steps 6-9 were not reached.

The following artifacts were created safely before the failure:

- Frontend rollback backup: `/home/ai-river/river-watch/backups/ops-ui-db-increment-20260712-20260712-181703`
- Pre-cleanup full database dump under `/home/ai-river/db-backups/`

## Root cause

The temporary table used `ENGINE=MEMORY`, so its capacity was bounded by MySQL `max_heap_table_size` / `tmp_table_size`. The server's accumulated alarm IDs exceeded that limit.

## Repair

The temporary table now uses `ENGINE=InnoDB`. This keeps the table transaction-local while allowing disk-backed storage for large histories.

For the already-extracted server package, the safe in-place repair is:

```bash
cd /home/ai-river/river-watch-ops-ui-db-increment-20260712
sed -i 's/) ENGINE=MEMORY;/) ENGINE=InnoDB;/' scripts/apply-ops-ui-db-increment-20260712.sh
grep -n 'ENGINE=' scripts/apply-ops-ui-db-increment-20260712.sh
sudo -v
APP_DIR=/home/ai-river/river-watch \
  CUTOFF='2026-07-12 01:00:00' \
  ./scripts/apply-ops-ui-db-increment-20260712.sh
```

A rerun intentionally creates a new full pre-cleanup dump. The failed-run dump must be retained until the successful run and post-cleanup dump are verified.

## Corrected deliverable

- Package: `river-watch-ops-ui-db-increment-20260712-v2.zip`
- SHA-256: `3b89e21d19a423e98f12154bf71e22dd2d5a0759c62c45d72a83cb2c18c41344`
- Internal checksums: passed
- Confirmed script marker: `) ENGINE=InnoDB;`
