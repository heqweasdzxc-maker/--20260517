"""Group-owned latest-frame inference pools for River Watch.

Each production group owns camera capture agents and a fixed number of
single-frame model sessions. Historical frames are replaced, never queued.
"""

from __future__ import annotations

import base64
import json
import multiprocessing as mp
from multiprocessing import shared_memory
import os
from pathlib import Path
import signal
import threading
import time
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Callable, Sequence

import numpy as np

from group_pool_runtime import (
    ChannelConfig,
    GroupConfig,
    GroupRuntime,
    InferenceTask,
    load_channel_config,
    pool_size_for,
    validate_group_config,
)

EVIDENCE_MARKER_PREFIX = b"RIVERWATCH-EVIDENCE-V1|"


def log(group_id: str, message: str) -> None:
    print(f"[{time.strftime('%F %T')}] [{group_id}] {message}", flush=True)


def mask_url(value: str) -> str:
    text = str(value or "")
    if "://" not in text or "@" not in text:
        return text
    scheme, rest = text.split("://", 1)
    credentials, host_path = rest.split("@", 1)
    if ":" not in credentials:
        return text
    user, _ = credentials.split(":", 1)
    return f"{scheme}://{user}:******@{host_path}"


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _parse_roi(value: str | None):
    if not value:
        return None
    parts = tuple(float(item) for item in value.split(","))
    return parts if len(parts) == 4 else None


@dataclass(frozen=True)
class SessionModelConfig:
    model_path: str
    labels: tuple[str, ...]
    image_size: int
    confidence: float
    iou: float
    providers: tuple[str, ...]
    provider_options: dict
    require_gpu: bool
    input_batch_size: int = 1
    session_count: int | None = None

    @classmethod
    def from_channels(cls, channels: Sequence[ChannelConfig]) -> "SessionModelConfig":
        if not channels:
            raise ValueError("model session requires channels")
        values = channels[0].values or {}
        options = json.loads(values.get("ORT_PROVIDER_OPTIONS_JSON", "{}") or "{}")
        return cls(
            model_path=channels[0].model_path,
            labels=tuple(item.strip() for item in channels[0].labels.split(",") if item.strip()),
            image_size=channels[0].image_size,
            confidence=min(channel.confidence for channel in channels),
            iou=float(values.get("YOLO_IOU", "0.45")),
            providers=channels[0].providers,
            provider_options=options,
            require_gpu=_as_bool(values.get("REQUIRE_GPU_PROVIDER"), True),
        )


class CameraCaptureAgent:
    def __init__(
        self,
        channel: ChannelConfig,
        publish: Callable[[str, np.ndarray, float, float], None],
        set_online: Callable[[str, bool], None],
        *,
        capture_factory=None,
        clock: Callable[[], float] = time.time,
        reconnect_sec: float | None = None,
    ):
        self.channel = channel
        self.publish = publish
        self.set_online = set_online
        self.clock = clock
        self.reconnect_sec = float(
            reconnect_sec if reconnect_sec is not None else (channel.values or {}).get("RECONNECT_SEC", "3")
        )
        self._capture_factory = capture_factory
        self._capture = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._last_publish = 0.0

    @property
    def stream_url(self) -> str:
        values = self.channel.values or {}
        return values.get("INFERENCE_STREAM_URL") or values.get("RTSP_URL", "")

    def _open(self):
        if self._capture_factory is not None:
            return self._capture_factory(self.stream_url)
        import cv2

        capture = cv2.VideoCapture(self.stream_url, cv2.CAP_FFMPEG)
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        return capture

    def read_once(self) -> bool:
        if self._capture is None:
            self._capture = self._open()
            if not self._capture.isOpened():
                self.set_online(self.channel.camera_id, False)
                self._capture.release()
                self._capture = None
                return False
            self.set_online(self.channel.camera_id, True)
        ok, bgr = self._capture.read()
        if not ok:
            self.set_online(self.channel.camera_id, False)
            self._capture.release()
            self._capture = None
            return False
        now = self.clock()
        interval = 1.0 / max(0.5, self.channel.sample_fps)
        if now - self._last_publish + 1e-9 < interval:
            return True
        self._last_publish = now
        try:
            import cv2

            pts_ms = float(self._capture.get(cv2.CAP_PROP_POS_MSEC) or now * 1000.0)
        except Exception:
            pts_ms = now * 1000.0
        rgb = np.ascontiguousarray(bgr[..., ::-1])
        self.publish(self.channel.camera_id, rgb, now, pts_ms)
        return True

    def _run(self) -> None:
        log(self.channel.camera_id, f"capture start {mask_url(self.stream_url)}")
        while not self._stop.is_set():
            if not self.read_once():
                self._stop.wait(self.reconnect_sec)
        if self._capture is not None:
            self._capture.release()
            self._capture = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, name=f"capture-{self.channel.camera_id}", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)
        if self._capture is not None:
            self._capture.release()
            self._capture = None


class HttpTransport:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def _request(self, path: str, method: str, payload=None):
        data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(self.base_url + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        with urllib.request.urlopen(request, timeout=8) as response:
            return json.loads(response.read().decode("utf-8"))

    def post(self, path: str, payload: dict):
        return self._request(path, "POST", payload)

    def get(self, path: str):
        return self._request(path, "GET")


class BackendClient:
    def __init__(
        self,
        base_url: str,
        token: str,
        *,
        transport=None,
        clock: Callable[[], float] = time.time,
        frame_encoder: Callable[[str, np.ndarray, int], dict] | None = None,
    ):
        self.transport = transport or HttpTransport(base_url, token)
        self.clock = clock
        self.frame_encoder = frame_encoder or self.encode_evidence_frame
        self._sentinel_enabled = True
        self._sentinel_checked_at = 0.0
        self._last_emit: dict[tuple[str, str], float] = {}
        self._last_heartbeat: dict[str, float] = {}
        self.evidence_frames: dict[str, np.ndarray] = {}

    def sentinel_enabled(self) -> bool:
        now = self.clock()
        if now - self._sentinel_checked_at < 3 and self._sentinel_checked_at:
            return self._sentinel_enabled
        try:
            response = self.transport.get("/api/v1/runtime/sentinel")
            data = response.get("data") if isinstance(response, dict) else {}
            self._sentinel_enabled = not (isinstance(data, dict) and data.get("enabled") is False)
        except Exception:
            pass
        self._sentinel_checked_at = now
        return self._sentinel_enabled

    def build_metadata(self, channel: ChannelConfig, result: dict) -> dict:
        values = channel.values or {}
        return {
            "eventId": result.get("event_id") or f"AI-{int(self.clock() * 1000)}-{uuid.uuid4().hex[:8]}",
            "cameraId": channel.camera_id,
            "pts": float(result.get("pts_ms", 0.0)),
            "boxes": list(result.get("boxes") or []),
            "streamRole": values.get("STREAM_ROLE", "inference"),
            "sourceStreamUrl": values.get("INFERENCE_STREAM_URL") or values.get("RTSP_URL", ""),
            "displayStreamUrl": values.get("DISPLAY_STREAM_URL", ""),
            "coordinateSpace": values.get("COORDINATE_SPACE", "normalized"),
            "model": os.path.basename(channel.model_path) if channel.model_path else "baseline",
            "capturedAtMs": int(float(result.get("captured_at", self.clock())) * 1000),
        }

    @staticmethod
    def tag_evidence_jpeg(camera_id: str, jpeg: bytes) -> bytes:
        if not jpeg.startswith(b"\xff\xd8") or not jpeg.endswith(b"\xff\xd9"):
            raise ValueError("evidence frame is not a JPEG")
        marker = EVIDENCE_MARKER_PREFIX + camera_id.strip().upper().encode("ascii")
        if len(marker) + 2 > 0xFFFF:
            raise ValueError("evidence marker is too long")
        comment = b"\xff\xfe" + (len(marker) + 2).to_bytes(2, "big") + marker
        return jpeg[:2] + comment + jpeg[2:]

    @staticmethod
    def encode_evidence_frame(camera_id: str, frame: np.ndarray, captured_at_ms: int) -> dict:
        import cv2

        if not isinstance(frame, np.ndarray) or frame.ndim != 3 or frame.shape[2] != 3:
            raise ValueError("evidence frame must be an RGB image")
        bgr = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
        ok, encoded = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
        if not ok or encoded.size == 0:
            raise ValueError("failed to encode evidence frame")
        jpeg = BackendClient.tag_evidence_jpeg(camera_id, encoded.tobytes())
        return {
            "cameraId": camera_id,
            "mimeType": "image/jpeg",
            "capturedAtMs": captured_at_ms,
            "dataBase64": base64.b64encode(jpeg).decode("ascii"),
        }

    def _should_emit(self, channel: ChannelConfig, boxes: list[dict]) -> bool:
        values = channel.values or {}
        interval = max(0.0, float(values.get("AI_METADATA_EMIT_INTERVAL_SEC", "10")))
        key = ",".join(sorted({str(box.get("cls") or "unknown") for box in boxes}))
        now = self.clock()
        last = self._last_emit.get((channel.camera_id, key), 0.0)
        if interval and now - last < interval:
            return False
        self._last_emit[(channel.camera_id, key)] = now
        return True

    def publish_result(self, channel: ChannelConfig, result: dict) -> None:
        boxes = list(result.get("boxes") or [])
        self.post_worker_heartbeat(channel, "online", result)
        if not boxes or not self._should_emit(channel, boxes):
            return
        payload = self.build_metadata(channel, result)
        frame = result.get("frame")
        if isinstance(frame, np.ndarray):
            self.evidence_frames[payload["eventId"]] = np.array(frame, copy=True)
            payload["evidenceFrame"] = self.frame_encoder(
                channel.camera_id,
                frame,
                int(payload["capturedAtMs"]),
            )
            while len(self.evidence_frames) > 32:
                self.evidence_frames.pop(next(iter(self.evidence_frames)))
        path = (channel.values or {}).get("POST_PATH", "/api/v1/alarms/metadata")
        self.transport.post(path, payload)

    def post_worker_heartbeat(self, channel: ChannelConfig, status: str, result: dict | None = None) -> None:
        now = self.clock()
        values = channel.values or {}
        interval = float(values.get("HEARTBEAT_SEC", "10"))
        if now - self._last_heartbeat.get(channel.camera_id, 0.0) < interval:
            return
        result = result or {}
        payload = {
            "workerId": channel.camera_id,
            "cameraId": channel.camera_id,
            "status": status,
            "source": values.get("HEARTBEAT_SOURCE", "river-group-pool"),
            "model": os.path.basename(channel.model_path) if channel.model_path else "baseline",
            "runtime": "onnxruntime-group-pool",
            "providers": list(channel.providers),
            "channels": [channel.camera_id],
            "fps": channel.sample_fps,
            "latencyMs": int(float(result.get("latency_ms", 0))),
            "modelReady": True,
            "detail": f"session={result.get('session_id', '-')} boxes={len(result.get('boxes') or [])}",
            "heartbeatAt": time.strftime("%Y-%m-%dT%H:%M:%S+08:00", time.localtime(now)),
        }
        try:
            self.transport.post(values.get("WORKER_STATUS_PATH", "/api/v1/ai/worker-status"), payload)
            self._last_heartbeat[channel.camera_id] = now
        except Exception as exc:
            log(channel.camera_id, f"heartbeat failed: {exc}")


def _session_main(connection, shm_name: str, capacity: int, model: SessionModelConfig) -> None:
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
    os.environ.setdefault("MKL_NUM_THREADS", "1")
    import detect_core as core
    import river_worker

    river_worker.CONFIG["ort_providers"] = list(model.providers)
    river_worker.CONFIG["ort_provider_options"] = model.provider_options
    river_worker.CONFIG["require_gpu_provider"] = model.require_gpu
    river_worker.CONFIG["runtime_preset"] = os.environ.get("RIVER_WATCH_RUNTIME_PRESET", "group-pool")
    yolo = river_worker.YoloOnnx(
        model.model_path, list(model.labels), model.image_size, model.confidence, model.iou
    )
    shm = shared_memory.SharedMemory(name=shm_name)
    try:
        connection.send({"ready": True, "providers": yolo.session.get_providers()})
        while True:
            command = connection.recv()
            if command.get("command") == "stop":
                return
            started = time.monotonic()
            try:
                size = int(command["size"])
                if size > capacity:
                    raise ValueError("frame exceeds shared-memory capacity")
                frame = np.ndarray(
                    tuple(command["shape"]), dtype=np.dtype(command["dtype"]), buffer=shm.buf[:size]
                ).copy()
                boxes = yolo.detect(frame) if any(
                    item in command["detectors"] for item in ("floating", "structure")
                ) else []
                if "color" in command["detectors"]:
                    box = core.analyze_water_color(frame, roi=command.get("color_roi"))
                    if box:
                        boxes.append(box)
                if command.get("enable_level") and "level" in command["detectors"]:
                    box = core.waterline_anomaly(
                        frame, command["level_ref_row"], command["level_tol"], command.get("level_roi")
                    )
                    if box:
                        boxes.append(box)
                connection.send(
                    {
                        "session_id": command["session_id"],
                        "channel_id": command["channel_id"],
                        "generation": command["generation"],
                        "captured_at": command["captured_at"],
                        "pts_ms": command["pts_ms"],
                        "boxes": boxes,
                        "latency_ms": (time.monotonic() - started) * 1000.0,
                    }
                )
            except Exception as exc:
                connection.send(
                    {
                        "session_id": command.get("session_id"),
                        "channel_id": command.get("channel_id"),
                        "generation": command.get("generation", 0),
                        "error": str(exc),
                    }
                )
    finally:
        shm.close()


class ModelSessionProcess:
    def __init__(self, session_id: str, model: SessionModelConfig, *, frame_capacity: int = 12 * 1024 * 1024):
        self.session_id = session_id
        self.model = model
        self.frame_capacity = frame_capacity
        self.busy = False
        self.inflight: InferenceTask | None = None
        self.started_at = 0.0
        self.providers: list[str] = []
        self._shm = shared_memory.SharedMemory(create=True, size=frame_capacity)
        self._parent = None
        self._process = None
        self.restarting = False
        self._closing = threading.Event()
        self._restart_thread: threading.Thread | None = None

    def start(self, timeout: float = 300.0) -> None:
        context = mp.get_context("spawn")
        parent, child = context.Pipe()
        process = context.Process(
            target=_session_main,
            args=(child, self._shm.name, self.frame_capacity, self.model),
            name=f"river-model-session-{self.session_id}",
            daemon=True,
        )
        process.start()
        self._parent = parent
        self._process = process
        if not parent.poll(timeout):
            self.stop()
            raise TimeoutError(f"{self.session_id} model warmup timed out")
        ready = parent.recv()
        if not ready.get("ready"):
            raise RuntimeError(f"{self.session_id} model warmup failed")
        self.providers = list(ready.get("providers") or [])

    def submit(self, task: InferenceTask) -> None:
        if self.busy:
            raise RuntimeError(f"{self.session_id} is busy")
        frame = np.ascontiguousarray(task.frame)
        if frame.nbytes > self.frame_capacity:
            raise ValueError("frame exceeds shared-memory capacity")
        np.ndarray(frame.shape, dtype=frame.dtype, buffer=self._shm.buf[: frame.nbytes])[:] = frame
        channel_values = task.channel_values
        self._parent.send(
            {
                "command": "infer",
                "session_id": self.session_id,
                "channel_id": task.channel_id,
                "generation": task.generation,
                "captured_at": task.captured_at,
                "pts_ms": task.pts_ms,
                "shape": frame.shape,
                "dtype": frame.dtype.str,
                "size": frame.nbytes,
                "detectors": channel_values.get("detectors", ("floating",)),
                "color_roi": channel_values.get("color_roi"),
                "enable_level": channel_values.get("enable_level", False),
                "level_roi": channel_values.get("level_roi"),
                "level_ref_row": channel_values.get("level_ref_row", 0.55),
                "level_tol": channel_values.get("level_tol", 0.06),
            }
        )
        self.inflight = task
        self.started_at = time.monotonic()
        self.busy = True

    def poll(self):
        if not self.busy or self.restarting:
            return None
        if self._process is None or not self._process.is_alive():
            result = {
                "session_id": self.session_id,
                "channel_id": self.inflight.channel_id,
                "generation": self.inflight.generation,
                "error": "model session exited",
            }
        elif not self._parent.poll():
            return None
        else:
            result = self._parent.recv()
        if not result.get("error") and self.inflight is not None:
            result["frame"] = self.inflight.frame
        return result

    def request_restart(self, reason: str) -> None:
        if self.restarting or self._closing.is_set():
            return
        log(self.session_id, f"restart model session: {reason}")
        self.restarting = True
        self.busy = True
        self.inflight = None

        def restart() -> None:
            try:
                self._stop_process()
                self.start(timeout=float(os.environ.get("GROUP_SESSION_WARMUP_SEC", "300")))
                log(self.session_id, f"model session recovered providers={self.providers}")
                self.busy = False
            except Exception as exc:
                log(self.session_id, f"model session restart failed: {exc}")
                self.busy = True
            finally:
                self.restarting = False

        self._restart_thread = threading.Thread(
            target=restart, name=f"restart-{self.session_id}", daemon=True
        )
        self._restart_thread.start()

    def _stop_process(self) -> None:
        if self._process is None:
            return
        if self._process.is_alive():
            try:
                self._parent.send({"command": "stop"})
            except Exception:
                pass
            self._process.join(timeout=5)
        if self._process.is_alive():
            self._process.terminate()
            self._process.join(timeout=5)
        self._process = None

    def stop(self) -> None:
        self._closing.set()
        self._stop_process()
        if self._restart_thread is not None and self._restart_thread.is_alive():
            self._restart_thread.join(timeout=5)
        try:
            self._shm.close()
            self._shm.unlink()
        except FileNotFoundError:
            pass


def _channel_runtime_values(channel: ChannelConfig) -> dict:
    values = channel.values or {}
    return {
        "detectors": channel.detectors,
        "color_roi": _parse_roi(values.get("COLOR_ROI")),
        "enable_level": _as_bool(values.get("ENABLE_WATER_LEVEL_ALARM")),
        "level_roi": _parse_roi(values.get("LEVEL_ROI")),
        "level_ref_row": float(values.get("LEVEL_REF_ROW", "0.55")),
        "level_tol": float(values.get("LEVEL_TOL", "0.06")),
    }


def run_group() -> int:
    group_id = os.environ.get("GROUP_ID", "river-a")
    normalized = group_id.removeprefix("river-ai-group@").removesuffix(".service")
    channels = tuple(item.strip().upper() for item in os.environ.get("CHANNELS", "").split(",") if item.strip())
    if not channels:
        raise SystemExit("CHANNELS must not be empty")
    env_dir = Path(os.environ.get("WORKER_ENV_DIR", "/etc/river-watch"))
    configs = []
    for camera_id in channels:
        config = load_channel_config(env_dir / f"ai-worker-{camera_id}.env")
        values = dict(config.values or {})
        values.setdefault("BACKEND_URL", os.environ.get("BACKEND_URL", "http://127.0.0.1:8080"))
        values.setdefault("AUTH_TOKEN", os.environ.get("AUTH_TOKEN", ""))
        configs.append(ChannelConfig(**{**config.__dict__, "values": values}))
    group_config = GroupConfig(normalized, tuple(configs))
    validate_group_config(group_config)
    model_config = SessionModelConfig.from_channels(configs)
    backend = BackendClient(
        (configs[0].values or {}).get("BACKEND_URL", "http://127.0.0.1:8080"),
        (configs[0].values or {}).get("AUTH_TOKEN", ""),
    )
    sessions = [ModelSessionProcess(f"{normalized}-{index + 1}", model_config) for index in range(pool_size_for(normalized))]
    runtime = GroupRuntime(group_config, sessions, backend)
    stop_event = threading.Event()

    def stop(_signum=None, _frame=None):
        stop_event.set()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    agents = [
        CameraCaptureAgent(channel, runtime.publish_frame, runtime.set_channel_online)
        for channel in configs
    ]
    try:
        for session in sessions:
            session.start(timeout=float(os.environ.get("GROUP_SESSION_WARMUP_SEC", "300")))
            if model_config.require_gpu and "MIGraphXExecutionProvider" not in session.providers:
                raise RuntimeError(f"{session.session_id} GPU provider unavailable: {session.providers}")
            log(normalized, f"session ready {session.session_id} providers={session.providers}")
        for agent in agents:
            agent.start()
        while not stop_event.is_set():
            for session in sessions:
                result = session.poll()
                if result is not None:
                    runtime.handle_result(result)
                if session.busy and session.inflight is not None:
                    deadline = runtime.scheduler.deadline_seconds(session.inflight.channel_id)
                    if time.monotonic() - session.started_at > max(2.0, deadline * 2):
                        runtime.handle_result(
                            {
                                "session_id": session.session_id,
                                "channel_id": session.inflight.channel_id,
                                "generation": session.inflight.generation,
                                "error": "inference watchdog timeout",
                            }
                        )
            if backend.sentinel_enabled():
                while runtime.dispatch_once(time.time()):
                    if all(item.busy for item in sessions):
                        break
            else:
                for channel in configs:
                    backend.post_worker_heartbeat(channel, "online", {"boxes": [], "session_id": "sentinel-disabled"})
            stop_event.wait(0.005)
    finally:
        for agent in agents:
            agent.stop()
        for session in sessions:
            session.stop()
    return 0


def main() -> None:
    raise SystemExit(run_group())


if __name__ == "__main__":
    main()
