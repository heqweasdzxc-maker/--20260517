# Package Receipt

- Package: `river-watch-ai-runtime-topology-increment-20260715-v2.zip`
- SHA-256: `018f5650af8b1b3764caa98436ec6cec52420b9acc0d51a98ca0586b71081d06`
- Size: 15706 bytes
- Target: `192.168.2.167`
- Replaces: `river-watch-ai-runtime-topology-increment-20260714.zip`
- Production baseline observed: all three group services inactive/disabled; both batch services active/enabled
- Migration: stop batch, then start and validate `river-a`, `river-b`, and `structure` sequentially
- Safety: reject overlapping/partial topology; restore exact pre-deployment service/file/registry state on failure
- Verification: clean extraction, all internal checksums, 8 package tests, full ShellCheck, and archive junk/model-weight scan passed
- Model policy: no ONNX/PT weights or duplicate binary archive are committed to GitHub
