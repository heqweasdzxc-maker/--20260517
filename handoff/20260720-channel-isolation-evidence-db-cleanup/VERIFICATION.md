# Verification record

Date: 2026-07-20

## Production diagnosis

- CH01-CH08 were running the river 12-class model, which also contains `wall_crack`.
- The pooled group runtime filtered confidence only. `DETECTORS=floating,color` selected inference modules but was not an output class boundary.
- Production evidence rows contained valid 640x360 JPEG data, so the dark review panel was not caused by empty database media.
- Reopening the same selected alarm did not change the watched alarm ID. The frontend therefore skipped evidence reload and rendered request failures as the generic dark placeholder.

## Increment behavior

- CH01-CH08 allow only river alarm types.
- CH09-CH10 allow only structure alarm types.
- Confidence thresholds and all existing sampling, model, stream and authentication settings are preserved.
- Persisted evidence is reloaded even when the same alarm is opened again; loading, missing, authorization/proxy and invalid-media failures are visible.
- Before cleanup, the deployment stops inference and backend writes, creates and verifies a compressed data-only SQL backup, then clears the alarm lifecycle in one transaction.

## Cleanup scope

Cleared tables: `rw_event_group_alarm`, `rw_alarm_evidence`, `rw_notification`, `rw_playback_clip`, `rw_evidence_bundle`, `rw_uav_task`, `rw_work_order`, `rw_ai_event`, `rw_event_group`, `rw_alarm`.

Configuration, devices, users, roles, thresholds, models, algorithms, streams, storage, imports and training data are not deleted.

## Local verification

- Group runtime tests: 21 passed.
- Increment package tests: 20 passed.
- Frontend tests: 174 passed across 40 files.
- Frontend type check and production build: passed.
- Shell syntax: all three deployment scripts passed `bash -n`.
- Package checksum: `73cb86f6016a2eba899b88699f1ea9aaf2f5323873393f34f95294627fad506d`.
- Archive scope check: no pytest cache, Python bytecode, digital-twin assets or model files.

## Deployment state

The package is ready for `192.168.2.167` but was not remotely executed from this workstation. The apply script has exact baseline gates, explicit cleanup confirmation, automatic rollback and post-deployment verification.
