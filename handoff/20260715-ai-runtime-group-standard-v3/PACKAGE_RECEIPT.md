# Package Receipt

- Package: `river-watch-ai-runtime-topology-increment-20260715-v3.zip`
- SHA-256: `db30434b4a351f71a98ef615f3f263b0926be91166581c03358e2b0dfd5c3ff7`
- Size: 16471 bytes
- Target: `192.168.2.167`
- Replaces: v1 and v2
- v2 result: rollback completed; original two batch services restored
- Root cause fixed: all `pgrep -P` child counts treat no match as zero under pipefail
- Additional guard: fail immediately with recent journal logs if systemd marks a group failed
- Migration: stop batch, then start and validate `river-a`, `river-b`, and `structure` sequentially
- Progress: readiness counts logged every 30 seconds
- Verification: clean extraction, all checksums, 11 package tests, full ShellCheck, and archive junk/model-weight scan passed
