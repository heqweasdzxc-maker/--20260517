# River Watch capture and alarm-evidence fix v4

This revision supersedes v3 for the current production server.

The v3 deployment stopped safely before mutation because the production `server.mjs` had advanced to the event-situation persistent aggregation version. V4 rebases the evidence and capture changes on that exact deployed baseline.

## Preserved production behavior

- persistent event aggregation and `/api/events` remain in the backend;
- event first/latest occurrence and open dedupe lifecycle remain available to the frontend;
- the three-column alarm review details remain unchanged;
- digital-twin and model static resources are not replaced.

## Added behavior

- one high-resolution image per camera every 30 minutes for 10 days;
- exact AI detection frames carry `RIVERWATCH-EVIDENCE-V1|CHxx` provenance;
- backend rejects mismatched or unverifiable evidence;
- frontend loads metadata first and displays only verified persisted evidence.

Archive: `river-watch-capture-evidence-link-increment-20260722-v4.zip`

SHA-256: `65d5758432657008a71ab91e32acee43a15e40fe7be76cf00f089ae456fdc62d`
