# Alarm evidence annotations and review layout v2 receipt

- Date: 2026-07-15 Asia/Shanghai
- Target: `192.168.2.167`
- Package: `river-watch-alarm-evidence-annotations-layout-increment-20260715-v2.zip`
- Package SHA-256: `aff5cbb299c263d53305d93dde0aa78e967ec4f693bf375ae8cae9a14d023322`
- Deployment state: deployed and verified on `192.168.2.167`.

## Production deployment receipt

- Completed at: 2026-07-15 21:15:34 Asia/Shanghai.
- Result: `VERIFY OK` and `DONE`.
- Backend health: `UP`, MySQL store.
- Backend and frontend both became ready on readiness attempt 2 of 60.
- Legacy evidence annotations recovered: 650.
- Rollback backup: `/home/ai-river/river-watch/backups/alarm-evidence-annotations-layout-v2-20260715-20260715-211519`.
- No automatic rollback occurred.

## Rebase reason

The v1 deployment guard correctly stopped before applying files because its backend baseline was not the currently deployed production backend. The exact running source was exported from `192.168.2.167` at 2026-07-15 20:22 and verified before creating v2.

## Production baseline

- Baseline archive SHA-256: `bc0e9c589a7d30e9aad555e06818db427c745d1a2e0e1409293eb93177c67849`
- `server.mjs`: `7db1272481c3a6e51797759c22f1cb8574d1c1abed5044b7988baffc6f8182ca`
- `store.mjs`: `5105048363fe6f2fdd0095a6e8a867abe358701b3c3b588c738c284fdb913196`
- `alarm-evidence.mjs`: `de0fb34a257ffc64b45e4541350bb93c4e33897b208f0d516ca3d4ea046d7036`
- `ai-ingest.mjs`: `ed3e7e09eef0a1f1f0380c6a046ad0b37e448572d1616e95ba704b5586fa6cff`
- Host and running-container backend copies were identical.

## Merge scope

- `server.mjs`: only the authenticated evidence metadata route was added.
- `store.mjs`: only AI-event lookup, evidence annotation JSON schema, persistence and loading were added.
- `alarm-evidence.mjs`: evidence capture now stores annotation boxes and coordinate space.
- Frontend: historical annotation metadata and the responsive three-column review detail layout.
- No integrations, security-hardening, WVP, AI topology, model, threshold, stream, or sampling change was introduced.

## Verification

- Real baseline RED: 3 evidence tests passed and 3 failed for the expected missing behavior.
- Rebasing GREEN: all 6 evidence tests passed.
- Full backend suite: 80 of 81 passed. The single failure is the unchanged local-environment YOLO26 model-file assertion.
- Frontend: 39 files and 169 tests passed; production build passed.
- Package: 4 package tests passed, shellcheck passed, Node syntax checks passed, clean-extraction SHA256SUMS passed.

## Acceptance

The server deployment log must end with both `VERIFY OK` and `DONE`. Verify a new alarm from both `/events` and `/alarms`; its historical image must show the original box and label, and desktop judgment details must use three columns.
