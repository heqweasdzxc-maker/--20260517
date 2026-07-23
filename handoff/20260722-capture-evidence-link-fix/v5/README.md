# River Watch capture and alarm-evidence fix v5

This revision supersedes v4 for the current production server.

V4 stopped safely before mutation because production `frontend/src/composables/useWorkspace.ts` was already on the 2026-07-20 channel-isolation/evidence revision (`9225deb785c46bd0674eca6f050bf8a1c5af0b4f27dea862975f504c32e20e1d`). V5 rebases the strict alarm-evidence binding on that exact deployed frontend baseline.

## Preserved production behavior

- channel isolation and the existing evidence loading/error states remain intact;
- persistent event aggregation, first/latest occurrence and open dedupe lifecycle remain intact;
- three-column alarm review details remain unchanged;
- digital-twin and model static resources are not replaced;
- no database cleanup, batch inference, model or confidence changes are included.

## Added behavior

- one high-resolution image per camera every 30 minutes for 10 days;
- exact AI detection frames carry `RIVERWATCH-EVIDENCE-V1|CHxx` provenance;
- backend rejects mismatched or unverifiable evidence;
- frontend validates alarm and camera metadata before loading media and displays only verified persisted annotations.

Archive: `river-watch-capture-evidence-link-increment-20260723-v5.zip`

SHA-256: `77635acc1c9d1b230a7475cf12a7d6fc0cb812dde9685994ccc5b782aa9e63e7`
