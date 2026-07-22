# River Watch capture and alarm-evidence link increment (2026-07-22)

This incremental package makes two scoped production changes:

1. Replaces the previous training screenshot scheduler with a clean 10-day run. Each of the 10 configured cameras is captured every 30 minutes, for at most 480 slots. Existing captured images are preserved.
2. Binds alarm evidence to the originating camera and exact AI detection frame. New alarms persist a JPEG carrying an internal camera provenance marker. Backend and frontend checks prevent evidence from another camera from being displayed; unverifiable legacy evidence is blocked instead of being replaced by live video.

The package does not clear alarm data, evidence data, or existing training images. It does not enable batch inference and does not change model files, confidence thresholds, camera URLs, or navigation features.

## Apply

Run as root through `sudo`; the script performs baseline checks before changing files and automatically rolls back on failure.

```bash
sudo env APP_DIR=/home/ai-river/river-watch OPT_DIR=/opt/river-watch \
  bash scripts/apply-capture-evidence-link-fix-20260722.sh
```

## Verify

```bash
sudo env APP_DIR=/home/ai-river/river-watch OPT_DIR=/opt/river-watch \
  bash scripts/verify-capture-evidence-link-fix-20260722.sh
```

The first capture starts asynchronously. Review its status with:

```bash
systemctl status river-training-capture.timer river-training-capture.service --no-pager
journalctl -u river-training-capture.service -n 120 --no-pager
```

## Rollback

Use the rollback directory printed by the apply script:

```bash
sudo env APP_DIR=/home/ai-river/river-watch OPT_DIR=/opt/river-watch \
  bash scripts/rollback-capture-evidence-link-fix-20260722.sh \
  /home/ai-river/river-watch/backups/capture-evidence-link-fix-20260722-YYYYMMDD-HHMMSS
```
