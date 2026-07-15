# Package Receipt

> **SUPERSEDED:** Do not deploy v2. Its production run accepted the all-batch baseline and rolled back safely, but a pipefail-unsafe child-count command treated the normal pre-child state as an error. Use [20260715 v3](../20260715-ai-runtime-group-standard-v3/README.md).

- Package: `river-watch-ai-runtime-topology-increment-20260715-v2.zip`
- SHA-256: `b324e89ba81da2123c5998f22823668c249f063e006ed90c6cc946da87d79bb1`
- Size: 15877 bytes
- Target: `192.168.2.167`
- Result: rollback completed; both batch services restored
- Superseded by: `river-watch-ai-runtime-topology-increment-20260715-v3.zip`
- Reason: `pgrep` no-match returned 1 under `set -o pipefail`
