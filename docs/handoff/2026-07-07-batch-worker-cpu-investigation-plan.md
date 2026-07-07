# River-Watch Batch Worker CPU Investigation Plan 2026-07-07

## Context

After applying `river-watch-runtime-optimization-20260707.zip`, the field server reported:

- `river-ai-batch@river` active
- `river-ai-batch@structure` active
- `river-stream-relay@CH01..CH10` active
- ffmpeg relay path uses VAAPI and mostly low CPU
- two `batch_worker.py` processes later showed about `1448%` and `1433%` CPU

The deployment succeeded, but batch worker CPU still requires root cause investigation.

## Debugging Rule

Do not patch first. Gather evidence first. Determine whether CPU is consumed by:

1. frame grabbing / RTSP decode / BGR to RGB conversion,
2. ONNX Runtime CPU fallback,
3. MIGraphX compilation or repeated graph execution overhead,
4. model batch fallback to serial path,
5. busy scheduling loop with no idle sleep,
6. metadata/heartbeat retry loop,
7. thread oversubscription from BLAS/OpenCV/ORT/provider internals.

## Evidence Collection Commands

Run on `ai-river@airiver-sy`.

### 1. Logs and provider confirmation

```bash
set -e
echo "== batch worker logs since apply =="
sudo journalctl -u river-ai-batch@river -u river-ai-batch@structure \
  --since "2026-07-07 14:09:58" --no-pager \
  | grep -Ei 'batch runner|loaded model|providers|fallback|error|failed|sentinel|posted|rtsp|frame read|connected' \
  | tail -240
```

What to look for:

- `loaded model=... providers=[...]`
- whether `MIGraphXExecutionProvider` is active
- repeated `batch inference fallback to serial`
- repeated RTSP reconnect/read failure
- repeated metadata post failure

### 2. Service and environment

```bash
set -e
echo "== service units =="
systemctl cat river-ai-batch@river river-ai-batch@structure

echo "== batch env =="
sudo grep -RHE '^(BATCH_ID|CHANNELS|MAX_BATCH_SIZE|SCHEDULER_TICK_MS|FRAME_STALE_SEC|HEARTBEAT_SEC|SENTINEL_POLL_SEC|RECONNECT_SEC|ORT_PROVIDERS|ORT_INTRA_OP_NUM_THREADS|ORT_INTER_OP_NUM_THREADS|OMP_NUM_THREADS|OPENBLAS_NUM_THREADS|MKL_NUM_THREADS|RIVER_WATCH_RUNTIME_PRESET)=' \
  /etc/river-watch/ai-batch-*.env

echo "== per-channel inference env =="
sudo grep -RHE '^(CAMERA_ID|DETECTORS|SAMPLE_FPS|YOLO_ONNX|YOLO_FALLBACK_ONNX|YOLO_IMGSZ|YOLO_CONF|ORT_PROVIDERS|REQUIRE_GPU_PROVIDER|ORT_INTRA_OP_NUM_THREADS|ORT_INTER_OP_NUM_THREADS|AI_METADATA_EMIT_INTERVAL_SEC)=' \
  /etc/river-watch/ai-worker-CH*.env
```

### 3. Process and thread-level CPU

```bash
set -e
echo "== batch pids =="
pgrep -af 'workers/batch_worker.py|batch_worker.py'

echo "== process summary =="
ps -eo pid,ppid,nlwp,pcpu,pmem,etime,comm,args --sort=-pcpu \
  | grep -E 'batch_worker|python|ffmpeg' \
  | sed -E 's#(rtsp://[^:/@]+:)[^@]+@#\1******@#g' \
  | head -40

echo "== thread cpu top =="
for pid in $(pgrep -f 'batch_worker.py'); do
  echo "--- PID $pid ---"
  ps -L -p "$pid" -o pid,tid,psr,pcpu,pmem,stat,comm --sort=-pcpu | head -40
done

echo "== proc status =="
for pid in $(pgrep -f 'batch_worker.py'); do
  echo "--- PID $pid ---"
  grep -E 'Threads|Cpus_allowed_list|voluntary_ctxt_switches|nonvoluntary_ctxt_switches' /proc/$pid/status
done
```

Interpretation:

- Many hot threads in each process suggests ORT/provider/OpenCV thread oversubscription.
- One or two hot threads suggests Python scheduling/decode loop or serial model execution.

### 4. GPU usage and provider process map

```bash
set -e
echo "== rocm summary =="
rocm-smi || true

echo "== rocm process usage if supported =="
rocm-smi --showpidgpus --showuse --showmemuse --showmeminfo vram || true

echo "== render/video devices =="
ls -l /dev/dri || true
```

Interpretation:

- High CPU with low GPU usage suggests CPU provider fallback, preprocessing/decode bottleneck, or MIGraphX not executing.
- High GPU usage plus high CPU can mean preprocessing/decode plus GPU inference are both saturated.

### 5. Quick controlled isolation without code change

Only run during an acceptable maintenance window.

```bash
set -e
echo "== baseline CPU =="
ps -eo pid,nlwp,pcpu,pmem,comm,args --sort=-pcpu | grep -E 'batch_worker|ffmpeg' | head -20

echo "== stop structure batch for 60s =="
sudo systemctl stop river-ai-batch@structure
sleep 60
ps -eo pid,nlwp,pcpu,pmem,comm,args --sort=-pcpu | grep -E 'batch_worker|ffmpeg' | head -20

echo "== restart structure batch =="
sudo systemctl start river-ai-batch@structure
sleep 20
systemctl is-active river-ai-batch@river river-ai-batch@structure
```

Purpose:

- Determine whether both groups independently spike, or whether one group/channel/model dominates.

### 6. Evidence to paste back

Paste back:

- batch logs,
- batch env,
- per-channel env,
- process/thread CPU,
- ROCm output,
- whether stopping `structure` changes total CPU.

Mask RTSP credentials before sharing raw process lines.

## First Hypotheses To Test

1. `session.detect_many()` is falling back to serial inference every batch because model input does not accept batch size greater than 1.
2. `MIGraphXExecutionProvider` is not actually active for one or both workers, causing CPUExecutionProvider fallback.
3. OpenCV `VideoCapture` decode plus `cv2.cvtColor` is now happening inside batch workers for all channels and consumes large CPU.
4. ORT/provider threads ignore or exceed the intended thread env limits.
5. Main loop has no sleep after processing items, so if frames are always ready it runs as fast as possible. This is expected for throughput but can be too aggressive unless bounded by target inference cadence.

No fix should be applied until the evidence identifies which hypothesis is true.
