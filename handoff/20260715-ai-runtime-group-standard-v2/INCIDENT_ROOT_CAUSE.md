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

The 2026-07-14 v1 package is superseded by this v2 package.

