# Package Receipt

- Package: `river-watch-ai-runtime-topology-increment-20260715-v2.zip`
- SHA-256: `b324e89ba81da2123c5998f22823668c249f063e006ed90c6cc946da87d79bb1`
- Size: 15877 bytes
- Target: `192.168.2.167`
- Replaces: `river-watch-ai-runtime-topology-increment-20260714.zip`
- Production baseline observed: all three group services inactive/disabled; both batch services active/enabled
- Migration: stop batch, then start and validate `river-a`, `river-b`, and `structure` sequentially
- Progress: group readiness counts are logged every 30 seconds during model loading
- Safety: reject overlapping/partial topology; restore exact pre-deployment service/file/registry state on failure
- Verification: clean extraction, all internal checksums, 9 package tests, full ShellCheck, and archive junk/model-weight scan passed
- Model policy: no ONNX/PT weights or duplicate binary archive are committed to GitHub
