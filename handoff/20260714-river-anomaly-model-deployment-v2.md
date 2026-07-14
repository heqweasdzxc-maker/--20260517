# River anomaly model deployment v2 2026-07-14

## Why v2 is required

The first package stopped before mutation because it expected `river-ai-group@structure`. Production diagnostics showed the actual topology is:

- `river-ai-group@river-a`: active, CH01-CH04
- `river-ai-group@river-b`: active, CH05-CH08
- `river-ai-batch@river`: active, CH01-CH08
- `river-ai-batch@structure`: active, CH09-CH10
- `river-ai-group@structure`: inactive and unused

The river group and batch paths are currently running in parallel. This existing architecture explains the high GPU load, but architecture consolidation remains a separate task at the user's request.

## v2 transition

1. Require both river group services, river batch and one valid structure service to be active before mutation.
2. Preserve CH01-CH08 confidence thresholds and all unrelated worker settings.
3. Install and validate the same new model for every river inference path.
4. Pause `river-ai-batch@river` while group services remain available.
5. Restart and verify `river-a`, then `river-b`, with the new model and `MIGraphXExecutionProvider`.
6. Start and verify `river-ai-batch@river` with the same model and provider.
7. Leave `river-ai-batch@structure` running and unchanged throughout the transition.
8. Update camera metadata only after all river paths pass validation.
9. Restore files, environments, metadata and the original service topology on any post-mutation failure.

## Model identity

- ONNX SHA-256: `31ce290cdea402591c2d3c458c9d8a850a07af5006413492800c5e84f416ca63`
- PyTorch SHA-256: `7bb56918d36efaa99c4f2fb1fa327d5ef043351096337f11124b1aeadcebadd9`
- Classes: 12
- Input: `640x640`

## Final v2 artifact

- ZIP: `river-watch-river-anomaly-model-increment-20260714-v2.zip`
- ZIP SHA-256: `ac7ad0225fa88352841ac1262f35c48f2e2bbd043e97c2b27fc5de8be5de2768`
- ZIP entries: 18
- Clean extraction and every internal `SHA256SUMS` entry verified
- No `last.pt`, Python bytecode or training-cache files included
- Local tests: `test_detect_core.py` 9 passed; `test_batch_worker.py` 2 passed

The first package made no server changes because it failed during preflight. Only the v2 package should be used for the next deployment attempt.
