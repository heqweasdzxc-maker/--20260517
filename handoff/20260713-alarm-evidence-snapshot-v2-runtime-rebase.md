# 2026-07-13 Alarm evidence snapshot increment v2

## Runtime baseline

The backend source exported from the restored running container was verified:

- Archive: `river-watch-backend-running-src-20260713-102515.tar.gz`
- Archive SHA-256: `00dcc3a38dc3f7697164bce781f24890fe2a90a507b0d4740be8fb26a5f8b030`
- Checksum match: true
- Container: `deploy-backend-1`
- Image: `river-watch/backend:v3-20260624-190253`
- Image ID: `sha256:367259eacc809b56676db0f185c3d2d638a1b7a9e44dfa662d91a3f65b8cfc96`
- Capture time: `2026-07-13T10:25:15+08:00`

The running source contains 4,001 lines in `server.mjs` and 3,099 lines in `store.mjs`. It does not contain the newer `integrations/` tree referenced by the superseded local handoff version.

## Rebase

The evidence feature was reapplied to the exact exported runtime source:

- Wire `scheduleAlarmEvidenceCapture` into the existing ingest queue.
- Add memory/MySQL evidence save and read methods.
- Add `rw_alarm_evidence` with cascade delete.
- Add authenticated binary evidence endpoint.
- Retain the previously tested bounded async ffmpeg JPEG capture helper.
- Retain compact frontend authenticated evidence loading and overlay rendering.

No newer backend imports or unrelated backend behavior were introduced.

## Deployment safety

The v2 apply script:

1. Checks exact SHA-256 baselines for `server.mjs`, `store.mjs`, `ai-ingest.mjs`, and `alarm-evidence.mjs` before any write.
2. Confirms ffmpeg is present.
3. Backs up the complete host and container backend source.
4. Applies the runtime-rebased source overlay.
5. Syntax-checks all changed modules inside the actual container.
6. Restarts and waits for backend health.
7. Verifies schema creation before applying frontend files.
8. Automatically restores host source, container source, and frontend assets if any step fails.

## Baseline hashes

- `server.mjs`: `513dad526c3ef9efe701f1cefac66a8a07deff95108302fb23f60dfe04c583c4`
- `store.mjs`: `bb7b4f2703c8bf068d3a36b321c882811d22710006ea0fc43e3e45b6d51be1a3`
- `ai-ingest.mjs`: `d5159e0cee407654938065711beadd96324f5a3dccb54e3b8a45e7ff7fd093e8`
- `alarm-evidence.mjs`: `de0fb34a257ffc64b45e4541350bb93c4e33897b208f0d516ca3d4ea046d7036`

## Deliverable

- Package: `river-watch-alarm-evidence-snapshot-increment-20260713-v2.zip`
- SHA-256: `121c28927cd333a82c74e87e59a3557fe0c3b6a1f46651e9e1877d3a500b1215`
- Size: 1,172,388 bytes
- Internal checksums: passed
- Linux LF script: passed
- Runtime-rebased backend syntax checks: passed
- Evidence capture/store/API tests: 4 passed
- Frontend full suite: 37 files / 148 tests passed
- Frontend production build: passed

The superseded 20260712 package was renamed locally with `.DO_NOT_USE`.

## Apply

```bash
cd /home/ai-river
sha256sum river-watch-alarm-evidence-snapshot-increment-20260713-v2.zip
unzip -o river-watch-alarm-evidence-snapshot-increment-20260713-v2.zip
cd river-watch-alarm-evidence-snapshot-increment-20260713-v2
chmod +x scripts/apply-alarm-evidence-snapshot-increment-20260713-v2.sh
sudo -v
APP_DIR=/home/ai-river/river-watch ./scripts/apply-alarm-evidence-snapshot-increment-20260713-v2.sh
```
