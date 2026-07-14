# River model deployment wait-condition hotfix 2026-07-14

## Failure evidence

The v2 deployment passed package, ONNX, backup, install and class-mapping checks. `river-a` logged the expected new model at `14:26:36`, but the apply script failed at `14:26:38` because the model name appeared before the separate ONNX provider log.

Automatic rollback ran and reported:

```text
Automatic rollback started
Rollback restored: /home/ai-river/river-watch/backups/river-anomaly-model-20260714-v2-20260714-142635
```

This was a deployment condition race, not a model validation failure.

## Fix

- Continue polling after the model-load message until the GPU provider message appears.
- Extend the condition-based wait from two minutes to six minutes for MIGraphX compilation.
- Fail immediately on known model, ONNX Runtime, GPU-provider or traceback errors.
- Require both the expected model name and `MIGraphXExecutionProvider` before success.
- Replace only the v2 deployment script and its full-package `SHA256SUMS` manifest.
- Verify the exact original v2 script and manifest hashes before replacement.
- Do not modify models, application files, environments, databases or services while applying the waitfix.

## Verification

- Wait-condition regression tests: 2 passed
- Corrected v2 target manifest simulation: passed
- Waitfix ZIP clean extraction and all internal checksums: passed
- Waitfix ZIP SHA-256: `2cabf59eb69ecf268a2d5c44a8773c3e3140f28aba14dea0181b597abdcbc777`

Artifact: `river-watch-model-deploy-waitfix-20260714.zip`
