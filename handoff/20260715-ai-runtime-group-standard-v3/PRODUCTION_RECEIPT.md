# AI runtime group-standard v3 production receipt

- Target: `192.168.2.167`
- Deployment completed: 2026-07-15 13:21:53 Asia/Shanghai
- Package: `river-watch-ai-runtime-topology-increment-20260715-v3.zip`
- Package SHA-256: `db30434b4a351f71a98ef615f3f263b0926be91166581c03358e2b0dfd5c3ff7`
- Result: `VERIFY OK` and `DONE`

## Runtime topology

- `river-ai-group@river-a`: active and enabled, 4 child workers.
- `river-ai-group@river-b`: active and enabled, 4 child workers.
- `river-ai-group@structure`: active and enabled, 2 child workers.
- `river-ai-batch@river`: inactive and disabled.
- `river-ai-batch@structure`: inactive and disabled.
- Backend health: `UP` with MySQL store.
- Exact model assignment and production model registry verification passed.

## GPU observation

The final verification sampled GPU busy at 100 percent immediately after the structure model became ready. Ten GPU worker processes were present, each reporting approximately 3.2 GB of VRAM. This is recorded as a post-load observation, not yet a steady-state conclusion. A delayed utilization, error-rate, and per-channel event-flow audit is required before changing runtime parameters.

## Server receipts

- Deployment receipt: `/home/ai-river/river-watch/logs/ops/ai-runtime-group-standard-v3-20260715-20260715-130958.md`
- Rollback state: `/home/ai-river/river-watch/backups/ai-runtime-group-standard-v3-20260715-20260715-130958`
- Rollback script: `/home/ai-river/river-watch-ai-runtime-topology-increment-20260715-v3/scripts/rollback-ai-runtime-topology-20260714.sh`

