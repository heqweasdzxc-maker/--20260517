INSERT INTO rw_algorithm (id, model_name, family_name, node_name, format_name, payload)
VALUES (
  'ALG-RIVER-20260714',
  '河道异常十二分类模型 20260714',
  'YOLO11n',
  'C9-GPU-POOL',
  'ONNX',
  JSON_OBJECT(
    'id', 'ALG-RIVER-20260714',
    'name', '河道异常十二分类模型 20260714',
    'family', 'YOLO11n',
    'version', '20260714',
    'format', 'ONNX',
    'node', 'C9-GPU-POOL',
    'fps', 0,
    'latency', 0,
    'utilization', 0,
    'accuracy', 47.5,
    'sourceFile', '/opt/river-watch/models/river-anomaly-yolo11n-12cls-20260714.onnx',
    'inputSize', 640,
    'confidence', 0.35,
    'iou', 0.45,
    'labels', 'willow_fluff,leaf,aquatic_weed,water_discoloration,garbage_bag,plastic_bottle,water_bird,plastic_foam,water_foam,person_in_water,debris,wall_crack',
    'runtime', 'onnxruntime-group/MIGraphXExecutionProvider',
    'status', '运行中',
    'runtimeChannels', JSON_ARRAY('CH01','CH02','CH03','CH04','CH05','CH06','CH07','CH08'),
    'metrics', JSON_OBJECT('precision', 0.585, 'recall', 0.502, 'mAP50', 0.475, 'mAP50_95', 0.234)
  )
)
ON DUPLICATE KEY UPDATE
  model_name = VALUES(model_name),
  family_name = VALUES(family_name),
  node_name = VALUES(node_name),
  format_name = VALUES(format_name),
  payload = VALUES(payload);

INSERT INTO rw_algorithm (id, model_name, family_name, node_name, format_name, payload)
VALUES (
  'ALG-STRUCTURE-20260630',
  '墙体裂痕/渗漏专用模型 20260630',
  'YOLO11n',
  'C9-EDGE-03',
  'ONNX',
  JSON_OBJECT(
    'id', 'ALG-STRUCTURE-20260630',
    'name', '墙体裂痕/渗漏专用模型 20260630',
    'family', 'YOLO11n',
    'version', '20260630',
    'format', 'ONNX',
    'node', 'C9-EDGE-03',
    'fps', 0,
    'latency', 0,
    'utilization', 0,
    'accuracy', 97.655,
    'sourceFile', '/opt/river-watch/models/yolo-wall-crack-leak-20260630.onnx',
    'inputSize', 640,
    'confidence', 0.40,
    'iou', 0.45,
    'labels', 'crack,leak',
    'runtime', 'onnxruntime-group/MIGraphXExecutionProvider',
    'status', '运行中',
    'runtimeChannels', JSON_ARRAY('CH09','CH10'),
    'metrics', JSON_OBJECT('precision', 0.97332, 'recall', 0.95532, 'mAP50', 0.97655, 'mAP50_95', 0.83993),
    'sha256', '3d7623906d57bdb439a5686dd6b39093c6ca8b9d6e233f3c78027d048d35e3f4'
  )
)
ON DUPLICATE KEY UPDATE
  model_name = VALUES(model_name),
  family_name = VALUES(family_name),
  node_name = VALUES(node_name),
  format_name = VALUES(format_name),
  payload = VALUES(payload);

