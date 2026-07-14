# AI Runtime Topology And Model Registry Design

## Objective

Standardize production inference on group supervisors, remove duplicate batch inference, activate the structure group with the verified high-accuracy model, and make both production models visible in Algorithm Management.

## Confirmed Production Topology

- `river-ai-group@river-a`: production inference supervisor for CH01-CH04.
- `river-ai-group@river-b`: production inference supervisor for CH05-CH08.
- `river-ai-group@structure`: production inference supervisor for CH09-CH10.
- `river-ai-batch@river` and `river-ai-batch@structure`: stopped and disabled after group verification, but unit files, worker code, and environment files remain available for rollback.
- Import/UAV inference remains outside this change and stays off until the separate on-demand workflow is implemented.

The cutover must not change camera RTSP settings, alarm thresholds, backend code, frontend assets, or model files.

## Model Assignment

### River channels CH01-CH08

- File: `/opt/river-watch/models/river-anomaly-yolo11n-12cls-20260714.onnx`
- Labels: `willow_fluff,leaf,aquatic_weed,water_discoloration,garbage_bag,plastic_bottle,water_bird,plastic_foam,water_foam,person_in_water,debris,wall_crack`
- Runtime: ONNX Runtime with `MIGraphXExecutionProvider`
- Registry name: `河道异常十二分类模型 20260714`

### Structure channels CH09-CH10

- File: `/opt/river-watch/models/yolo-wall-crack-leak-20260630.onnx`
- Labels: `crack,leak`
- Runtime: ONNX Runtime with `MIGraphXExecutionProvider`
- Registry name: `墙体裂痕/渗漏专用模型 20260630`

The structure model is intentionally retained. Its final training result is precision `0.97332`, recall `0.95532`, mAP50 `0.97655`, and mAP50-95 `0.83993`. The 20260714 twelve-class model has lower overall final metrics and no verified per-class wall-crack metric, so it must not replace the dedicated structure model without a separate controlled evaluation.

## Cutover Safety

Before changing service state, the deployment script must verify:

1. `group@river-a` and `group@river-b` are active.
2. The dedicated structure model exists either in `/opt/river-watch/models` or the application model directory and has SHA-256 `3d7623906d57bdb439a5686dd6b39093c6ca8b9d6e233f3c78027d048d35e3f4`.
3. The deployment backs up all affected environment files and active/enabled unit state.
4. CH09 and CH10 preserve their existing RTSP, authentication, confidence, and sampling values while receiving the exact structure model, labels, and MIGraphX requirements.
5. `batch@structure` remains available until `group@structure` has loaded both child workers and the dedicated model on `MIGraphXExecutionProvider`.
6. Backend health is available.

The script stops `batch@structure`, activates `group@structure`, and polls condition-based health checks. Only after all three group units pass does it stop and disable both batch units. Any failed post-check restores environment files and the previous active/enabled state.

## Model Registry

The increment upserts two stable records into `rw_algorithm`. It changes only those two record IDs and preserves every other model record. The registry payload records the exact source file, labels, input size, confidence/IoU metadata, runtime, channel scope, and training metrics.

No frontend rebuild is required because Algorithm Management already renders records returned by the backend model API.

## Deliverable

One compact incremental ZIP containing shell scripts, a SQL template, tests, checksums, and documentation. It contains no model weights, frontend distribution, database dump, or application source tree.

