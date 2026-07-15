# 10 个 worker 占用 GPU 100% 的原因

当前标准拓扑是 `group` 为主：

- `river-a` 4 个 `river_worker.py`
- `river-b` 4 个 `river_worker.py`
- `structure` 2 个 `river_worker.py`

每个 worker 都是独立 Python 进程，各自创建 ONNX Runtime + MIGraphX 会话、各自加载和编译模型，并持续拉取一路视频推理。因此 CH01-CH08 的河道模型被独立加载 8 次，CH09-CH10 的结构模型被独立加载 2 次。已观测到每个进程约占 3.2 GB 显存，10 个会话并发工作时 GPU Busy 到 100% 是这种架构的直接结果。

这不是本次前端或证据修复导致，也不是 `batch` 与 `group` 重复运行；当前 batch 已停止并禁用。要从根本上降低占用，需要在保留 group 服务边界的前提下，改为“同一模型一个共享会话 + 多路帧调度/微批处理”，而不是继续降低采样频率。

