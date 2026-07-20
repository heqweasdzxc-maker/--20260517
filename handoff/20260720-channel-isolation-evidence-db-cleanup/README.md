# River Watch channel isolation, evidence reload and database cleanup

Date: 2026-07-20

This increment fixes two confirmed production faults and performs the requested message cleanup.

## Confirmed causes

1. CH01-CH08 use the 12-class river model, which includes `wall_crack`. `DETECTORS=floating,color` enabled inference but did not restrict returned classes, so structure results could pass through on river channels.
2. Persisted evidence JPEGs are valid. The review dialog only watched alarm ID changes, so reopening the same selected alarm did not reload evidence. HTTP and proxy failures were silently rendered as the dark missing-evidence background.

## Changes

- Add `ALLOWED_ALARM_TYPES` to pooled group runtime and apply explicit river/structure class isolation.
- Reload persisted evidence when the same alarm is reopened.
- Show loading, 404, authentication/proxy and invalid-media states explicitly.
- Back up and clear current alarm lifecycle messages: alarms, event groups, work orders, notifications, AI events, alarm evidence, alarm-linked UAV tasks, evidence bundles and playback clips.
- Keep device, user, role, threshold, runtime, model, algorithm, stream, storage, import and training data unchanged.
- Keep the latest two rollback directories and latest three cleanup SQL backups.

## Apply

```bash
cd /home/ai-river/river-watch-channel-isolation-evidence-db-cleanup-increment-20260720
sudo -v
LOG="/home/ai-river/channel-isolation-evidence-db-cleanup-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env \
  APP_DIR=/home/ai-river/river-watch \
  OPT_DIR=/opt/river-watch \
  CONFIRM_CLEAR_MESSAGES=YES \
  bash scripts/apply-channel-isolation-evidence-db-cleanup-20260720.sh \
  >"$LOG" 2>&1 &
echo "pid=$!"
echo "log=$LOG"
tail -f "$LOG"
```

The application ends with `DONE`, prints the SQL backup path and rollback directory. New valid alarms may appear again after group inference resumes.

## Rollback

```bash
cd /home/ai-river/river-watch-channel-isolation-evidence-db-cleanup-increment-20260720
sudo env APP_DIR=/home/ai-river/river-watch OPT_DIR=/opt/river-watch \
  bash scripts/rollback-channel-isolation-evidence-db-cleanup-20260720.sh \
  /home/ai-river/river-watch/backups/channel-isolation-evidence-db-cleanup-20260720-YYYYmmdd-HHMMSS
```

