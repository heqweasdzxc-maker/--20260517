# River anomaly model deployment 2026-07-14

## Objective

Deploy `河道异常二次训练_20260714.zip` to `192.168.2.167` as a reversible model-only increment without changing unrelated application behavior.

## Source verification

- Source ZIP SHA-256: `a476d3b0b36ded9cf621d5d7f68734a0ebd1706928a597c29cd1ae46cbde39c1`
- ONNX SHA-256: `31ce290cdea402591c2d3c458c9d8a850a07af5006413492800c5e84f416ca63`
- PyTorch SHA-256: `7bb56918d36efaa99c4f2fb1fa327d5ef043351096337f11124b1aeadcebadd9`
- Architecture: YOLO11n detection
- Input size: `640x640`
- ONNX opset: `17`
- Precision: `0.585`
- Recall: `0.502`
- mAP50: `0.475`
- mAP50-95: `0.234`

Class order:

```text
willow_fluff,leaf,aquatic_weed,water_discoloration,garbage_bag,plastic_bottle,water_bird,plastic_foam,water_foam,person_in_water,debris,wall_crack
```

## Compatibility changes

The runtime class mapper was extended for classes introduced by this model:

- `aquatic_weed` -> plankton/aquatic vegetation alarm category
- `garbage_bag` -> floating object category
- `plastic_foam` and `water_foam` -> floating cluster category
- `water_bird` -> ignored (`None`), because it is a normal scene object

Existing worker callers already skip mappings that return `None`.

## Deployment boundary

- Changes only `CH01-CH08`, `river-a`, and `river-b`.
- Does not modify or restart `river-ai-group@structure` or CH09-CH10.
- Preserves every existing per-channel `YOLO_CONF`, RTSP URL, token, fallback and provider setting.
- Requires `MIGraphXExecutionProvider` in all CH01-CH08 worker environments.
- Refuses deployment if the parallel `river-ai-batch@river` service is active.
- Validates the ONNX graph with the installed server runtime before mutation.
- Activates `river-a` as the canary before `river-b`.
- Updates camera model metadata only after both groups pass model and GPU-provider checks.
- Automatically restores model files, worker environments, mappings and database metadata if a deployment step fails.
- Retains only the latest three backups from this increment.

## Local verification

- `test_detect_core.py`: 9 passed
- `test_batch_worker.py`: 2 passed
- Python compile check passed for `detect_core.py`, `river_worker.py` and `batch_worker.py`
- Final package must pass internal `SHA256SUMS` verification and ZIP SHA-256 verification before upload.

## Artifacts

- `river-watch-river-anomaly-model-increment-20260714.zip`
- Package ZIP SHA-256: `5a363d199fe83ca0903f30982e7aaf572197f6341199d40c5a353997b201661d`
- `river-watch-river-anomaly-model-increment-20260714.zip.sha256`
- Apply script: `scripts/apply-river-anomaly-model-increment-20260714.sh`

The package contains 18 ZIP entries. A clean extraction passed every internal `SHA256SUMS` check and contained no `last.pt`, Python bytecode or training-cache files. Run `bash -n` against the apply script on the Linux server before activation.

Deployment is not considered complete until the server log contains `DONE` and confirms both river groups loaded the new model through `MIGraphXExecutionProvider`.
