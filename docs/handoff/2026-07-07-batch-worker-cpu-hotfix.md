# River-Watch Batch Worker CPU Hotfix 2026-07-07

## Evidence Received

Source: pasted output from `ai-river@airiver-sy`.

Key findings:

- `river-ai-batch@river` and `river-ai-batch@structure` are active.
- All 10 relay services remain active.
- ffmpeg relay CPU is low after VAAPI, mostly around `0.8%` to `1.4%` in the latest sample.
- GPU is being used by both batch worker PIDs:
  - PID `192702`
  - PID `192704`
- ROCm reported:
  - GPU use around `13-14%`
  - VRAM around `1%`
  - total VRAM used about `1.98GB`
- Batch workers still consume high CPU:
  - PID `192702`: around `232%`, `170` threads
  - PID `192704`: around `157%`, `84` threads
- Logs repeatedly show:

```text
batch inference fallback to serial: [ONNXRuntimeError] : 2 : INVALID_ARGUMENT : Got invalid dimensions for input: images
```

## Root Cause

The deployed ONNX models accept fixed batch size `1`.

The first batch worker implementation always tried to run grouped frames as a
larger batch before falling back to serial inference. Because the models reject
`batch > 1`, every cycle produced an ONNX Runtime invalid-dimension exception,
then retried serial inference.

This creates:

- repeated exception overhead,
- repeated log overhead,
- no actual batch acceleration,
- extra CPU pressure on top of serial inference and preprocessing.

This is now a confirmed root cause for at least part of the high CPU. If CPU
remains high after this fix, the remaining bottleneck is likely serial
inference/preprocessing/decode throughput or ORT/provider thread behavior.

## Local Hotfix Implemented

File changed:

```text
codex-handoff/ai-pipeline/workers/batch_worker.py
```

Behavior:

- Read model input shape at session load.
- Determine `batch_cap` from the first input dimension.
- If model has fixed batch `1`, skip batch probing and run serial inference
  directly.
- If model has a fixed batch dimension that does not match the current frame
  count, skip batch probing and run serial inference directly.
- If dynamic-batch inference fails once, cache serial mode and log the fallback
  once instead of every cycle.
- Model load log now includes `batch=1` or `batch=dynamic`.

Core change concept:

```python
model_input = self.session.get_inputs()[0]
self.input_name = model_input.name
self.batch_cap = self._batch_cap(model_input.shape)
self._batch_fallback_logged = False
```

```python
if len(frames) == 1 or (self.batch_cap > 0 and self.batch_cap != len(frames)):
    return self.detect_serial(frames)
```

```python
except Exception as exc:
    self.batch_cap = 1
    if not self._batch_fallback_logged:
        log(f"batch inference disabled; fallback to serial: {exc}")
        self._batch_fallback_logged = True
return self.detect_serial(frames)
```

## Regression Test Added

File added:

```text
codex-handoff/ai-pipeline/tests/test_batch_worker.py
```

Test behavior:

- Simulates an ONNX session that accepts only `batch=1`.
- Sets `YoloSession.batch_cap = 1`.
- Calls `detect_many()` with two frames.
- Asserts that the fake session is called only as two single-frame runs:

```text
[(1, 3, 2, 2), (1, 3, 2, 2)]
```

RED result before fix:

```text
batch inference fallback to serial: model accepts only batch=1
FAIL test_fixed_batch_one_session_skips_batch_probe
```

GREEN result after fix:

```text
ok test_fixed_batch_one_session_skips_batch_probe
```

## Local Verification

Commands run locally:

```powershell
python codex-handoff\ai-pipeline\tests\test_batch_worker.py
python -m py_compile codex-handoff\ai-pipeline\workers\batch_worker.py codex-handoff\ai-pipeline\tests\test_batch_worker.py
python codex-handoff\ai-pipeline\tests\test_detect_core.py
```

Results:

```text
ok test_fixed_batch_one_session_skips_batch_probe
py_compile passed
8/8 detect_core tests passed
```

## Hotfix Package

Local package:

```text
E:\river-video-app-V3.0\river-watch-batch-worker-cpu-hotfix-20260707.zip
```

SHA256:

```text
bfbfca7fad13aed381009655cc92480310a8e625a7cc8849344297d46b39653b
```

Package properties:

- 5 entries.
- Linux-friendly zip paths using `/`.
- No `node_modules`.
- No logs.
- No backups.
- No cache directories.

Included files:

```text
README_BATCH_WORKER_CPU_HOTFIX_20260707.md
ai-pipeline/workers/batch_worker.py
ai-pipeline/tests/test_batch_worker.py
scripts/apply-batch-worker-cpu-hotfix-20260707.sh
SHA256SUMS
```

## Field Apply Command

Copy `river-watch-batch-worker-cpu-hotfix-20260707.zip` to `/home/ai-river`,
then run:

```bash
cd /home/ai-river
sha256sum river-watch-batch-worker-cpu-hotfix-20260707.zip

rm -rf /tmp/river-watch-batch-worker-cpu-hotfix-20260707
mkdir -p /tmp/river-watch-batch-worker-cpu-hotfix-20260707
unzip -o river-watch-batch-worker-cpu-hotfix-20260707.zip -d /tmp/river-watch-batch-worker-cpu-hotfix-20260707

APP_DIR=/home/ai-river/river-watch \
bash /tmp/river-watch-batch-worker-cpu-hotfix-20260707/scripts/apply-batch-worker-cpu-hotfix-20260707.sh
```

Expected checksum:

```text
bfbfca7fad13aed381009655cc92480310a8e625a7cc8849344297d46b39653b
```

## Field Verification

```bash
systemctl is-active river-ai-batch@river river-ai-batch@structure

sudo journalctl -u river-ai-batch@river -u river-ai-batch@structure --since "5 min ago" --no-pager \
  | grep -Ei 'loaded model|batch=|fallback|invalid dimensions|error|failed' \
  | tail -120

ps -eo pid,ppid,nlwp,pcpu,pmem,etime,comm,args --sort=-pcpu \
  | grep -E 'batch_worker|ffmpeg' \
  | sed -E 's#(rtsp://[^:/@]+:)[^@]+@#\1******@#g' \
  | head -30

rocm-smi || true
```

Expected:

- Batch services remain active.
- Model load logs include `batch=1` for fixed-batch models.
- Repeated `INVALID_ARGUMENT : Got invalid dimensions for input: images`
  messages stop.
- CPU should drop by the exception/logging overhead.
- If CPU remains high, continue with the next bottleneck investigation:
  serial inference throughput, preprocessing/decode, or ORT/provider threading.
