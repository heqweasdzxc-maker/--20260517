# Alarm evidence annotations and review layout change receipt

- Date: 2026-07-15 Asia/Shanghai
- Target: `192.168.2.167`
- Package: `river-watch-alarm-evidence-annotations-layout-increment-20260715.zip`
- Package SHA-256: `8535cd09371995ebb8614b3349c61524ed6a20222eeb5ef2418539cc664ad5df`
- Deployment state: not yet deployed; awaiting the server-side receipt containing `VERIFY OK` and `DONE`.

## Reported issues

1. Event review showed a historical image but no anomaly box or label, and displayed `未关联历史标注框`.
2. The detail area below the review image remained two columns instead of three.
3. Ten group workers occupied the GPU at 100 percent.

## Root causes

- The evidence table persisted only the JPEG and `event_id`. The browser resolved boxes from the platform snapshot, which contains only the newest 100 AI events. Older evidence therefore retained the image but lost its annotations in the client.
- The previous layout check covered only the three-item media metadata strip. The actual 13-field judgment detail area still used the old two-column grid.
- The production group topology runs ten independent `river_worker.py` processes. Each process creates its own ONNX Runtime and MIGraphX session and loads one model copy. Eight river channels therefore load the river model eight times and two structure channels load the structure model twice. Continuous concurrent inference can keep GPU Busy at 100 percent.

## Incremental changes

- Persist annotation boxes, labels, confidence, and coordinate space together with alarm evidence.
- Add an authenticated evidence metadata endpoint. It first reads persisted annotations and falls back to the linked database AI event for legacy evidence.
- Backfill recoverable legacy evidence by `event_id` during deployment.
- Make both Event Situation and Alarm Center review dialogs use persisted historical annotations.
- Change the actual 13-field judgment detail section to a three-column responsive grid.
- Keep the patch isolated from AI systemd units, worker topology, models, thresholds, streams, and sampling values.

## Historical-data boundary

Legacy evidence can be repaired only while its linked row still exists in `rw_ai_event`. If that original AI event was already deleted, the exact historical box cannot be reconstructed and the patch deliberately does not fabricate one.

## GPU conclusion

This UI/evidence patch does not change GPU behavior. Batch workers are stopped and disabled; the observed load comes from ten independent group workers. A later optimization should preserve the group service boundary while changing each model family to one shared inference session with multi-channel scheduling or micro-batching.

## Verification before packaging

- Backend evidence regression tests: 6 passed.
- Frontend test suite: 169 passed across 39 files.
- Frontend production build: passed.
- Package integrity and package tests: passed.
- Full backend suite: 80 passed, 1 unrelated environment failure because the local workstation does not contain the production YOLO26 model file; the same failure existed before this change.

## Deployment acceptance

The server-side apply log must end with both `VERIFY OK` and `DONE`. After deployment, verify a newly generated alarm in both `/events` and `/alarms`: the historical evidence must show the original box and label, and the detail section must render three columns on desktop.
