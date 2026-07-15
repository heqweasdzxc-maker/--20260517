# Production baseline provenance

- Target: `192.168.2.167`
- Exported at: 2026-07-15 20:22:06 Asia/Shanghai
- Source archive: `river-watch-alarm-evidence-rebase-baseline-20260715-202205.tar.gz`
- Archive SHA-256: `bc0e9c589a7d30e9aad555e06818db427c745d1a2e0e1409293eb93177c67849`
- Backend container: `deploy-backend-1`
- Backend image: `river-watch/backend:v3-20260624-190253`
- Backend status at export: healthy

## Exact backend baseline

- `server.mjs`: `7db1272481c3a6e51797759c22f1cb8574d1c1abed5044b7988baffc6f8182ca`
- `store.mjs`: `5105048363fe6f2fdd0095a6e8a867abe358701b3c3b588c738c284fdb913196`
- `alarm-evidence.mjs`: `de0fb34a257ffc64b45e4541350bb93c4e33897b208f0d516ca3d4ea046d7036`
- `ai-ingest.mjs`: `ed3e7e09eef0a1f1f0380c6a046ad0b37e448572d1616e95ba704b5586fa6cff`

The host copies and running-container copies had identical hashes. The v2 backend was produced by applying only the tested historical-annotation changes to this exported baseline.
