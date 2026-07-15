# 2026-07-15 runtime topology preflight incident

## Result

The first package stopped during preflight before changing services, configuration, models, or database records.

## Observed production baseline

- `river-ai-group@river-a`: inactive and disabled.
- `river-ai-group@river-b`: inactive and disabled.
- `river-ai-group@structure`: inactive and disabled.
- `river-ai-batch@river`: active and enabled.
- `river-ai-batch@structure`: active and enabled.
- Backend health endpoint returned `UP`.
- Both batch processes were using the GPU; observed GPU busy value was 12 percent.
- CH01-CH08 already referenced `river-anomaly-yolo11n-12cls-20260714.onnx` with `MIGraphXExecutionProvider`.

The group logs show that `river-a` and `river-b` received SIGTERM and stopped successfully at 2026-07-14 16:08:40. This was an intentional topology transition, not a group crash.

## Root cause

The first deployment script assumed `river-a`, `river-b`, and `batch@structure` were active. Production had already returned to the all-batch topology, so the preflight rejected a healthy but different baseline.

## v2 correction

- Accept an exclusive all-batch, all-group, or legacy hybrid baseline.
- Reject partial groups or batch/group overlap on the same channel domain.
- Capture rollback state before any mutation.
- Stop both batch services before starting group workers.
- Start and validate `river-a`, `river-b`, and `structure` in sequence.
- Require the expected child count, exact model path, and MIGraphX log evidence for each group.
- Disable retained batch services only after all three groups pass.
- Restore the exact pre-deployment service and file state on any failure.

The 2026-07-14 v1 package was superseded by v2.

## v2 wait-loop incident

The v2 deployment accepted the production baseline, captured rollback state, stopped both batch services, and started `river-a`. Three seconds later, line 150 counted child processes with a `pgrep | wc` pipeline. Before the first child existed, `pgrep` returned 1. Because the script uses `set -o pipefail`, that normal no-match result triggered the error trap. Rollback completed and restored both batch services.

v3 makes all child-count pipelines treat no match as zero, adds a regression test for every `pgrep -P` count, and fails immediately with recent logs if systemd marks a group unit failed. v1 and v2 are superseded by v3.

