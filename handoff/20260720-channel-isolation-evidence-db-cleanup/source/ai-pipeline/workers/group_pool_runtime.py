from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, Sequence

import numpy as np

from group_pool_core import DeadlineScheduler, LatestFrameMailbox, filter_boxes


@dataclass(frozen=True)
class ChannelConfig:
    camera_id: str
    model_path: str
    labels: str
    image_size: int
    providers: tuple[str, ...]
    confidence: float
    sample_fps: float
    detectors: tuple[str, ...]
    allowed_alarm_types: tuple[str, ...] = ()
    values: dict[str, str] | None = None


@dataclass(frozen=True)
class GroupConfig:
    group_id: str
    channels: tuple[ChannelConfig, ...]


@dataclass(frozen=True)
class InferenceTask:
    session_id: str
    channel_id: str
    generation: int
    captured_at: float
    dispatched_at: float
    frame: np.ndarray
    pts_ms: float
    channel_values: dict


class SessionAdapter(Protocol):
    session_id: str
    busy: bool

    def submit(self, task: InferenceTask) -> None: ...

    def request_restart(self, reason: str) -> None: ...


class BackendAdapter(Protocol):
    def publish_result(self, channel: ChannelConfig, result: dict) -> None: ...


def _parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def _csv(value: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in value.split(",") if item.strip())


def load_channel_config(path: str | Path) -> ChannelConfig:
    values = _parse_env(Path(path))
    camera_id = values.get("CAMERA_ID") or Path(path).stem.removeprefix("ai-worker-")
    return ChannelConfig(
        camera_id=camera_id.upper(),
        model_path=values.get("YOLO_ONNX", ""),
        labels=values.get("YOLO_LABELS", "trash,bottle,plastic,foam,algae,waterweed"),
        image_size=int(values.get("YOLO_IMGSZ", "640")),
        providers=_csv(values.get("ORT_PROVIDERS", "")),
        confidence=float(values.get("YOLO_CONF", "0.35")),
        sample_fps=float(values.get("SAMPLE_FPS", "4")),
        detectors=_csv(values.get("DETECTORS", "floating,color")),
        allowed_alarm_types=_csv(values.get("ALLOWED_ALARM_TYPES", "")),
        values=values,
    )


def pool_size_for(group_id: str) -> int:
    normalized = group_id.removeprefix("river-ai-group@").removesuffix(".service")
    sizes = {"river-a": 2, "river-b": 2, "structure": 1}
    if normalized not in sizes:
        raise ValueError(f"unsupported group: {group_id}")
    return sizes[normalized]


def validate_group_config(config: GroupConfig) -> None:
    if not config.channels:
        raise ValueError("group must contain at least one channel")
    expected = pool_size_for(config.group_id)
    if expected < 1:
        raise ValueError("invalid session pool size")
    first = config.channels[0]
    model_key = (first.model_path, first.labels, first.image_size, first.providers)
    for channel in config.channels:
        if (channel.model_path, channel.labels, channel.image_size, channel.providers) != model_key:
            raise ValueError("all channels in a group must use the same model, labels, image size and providers")
        if channel.sample_fps <= 0:
            raise ValueError(f"{channel.camera_id} sample FPS must be positive")
        if not 0 <= channel.confidence <= 1:
            raise ValueError(f"{channel.camera_id} confidence must be between 0 and 1")


class GroupRuntime:
    def __init__(self, config: GroupConfig, sessions: Sequence[SessionAdapter], backend: BackendAdapter):
        validate_group_config(config)
        if not sessions:
            raise ValueError("at least one model session is required")
        self.config = config
        self.backend = backend
        self.channels = {channel.camera_id: channel for channel in config.channels}
        self.sessions = {session.session_id: session for session in sessions}
        self.mailboxes = {camera_id: LatestFrameMailbox() for camera_id in self.channels}
        self.scheduler = DeadlineScheduler()
        self.online = {camera_id: True for camera_id in self.channels}
        self.last_dispatched_generation = {camera_id: 0 for camera_id in self.channels}
        self.frame_pts: dict[tuple[str, int], float] = {}
        for channel in config.channels:
            self.scheduler.register(channel.camera_id, channel.sample_fps)

    def publish_frame(
        self, channel_id: str, frame: np.ndarray, captured_at: float, pts_ms: float | None = None
    ) -> int:
        generation = self.mailboxes[channel_id].publish(frame, captured_at)
        self.frame_pts[(channel_id, generation)] = float(pts_ms if pts_ms is not None else captured_at * 1000.0)
        stale = [key for key in self.frame_pts if key[0] == channel_id and key[1] < generation]
        for key in stale:
            self.frame_pts.pop(key, None)
        return generation

    def set_channel_online(self, channel_id: str, online: bool) -> None:
        self.online[channel_id] = bool(online)

    def _free_session(self) -> SessionAdapter | None:
        return next((session for session in self.sessions.values() if not session.busy), None)

    def dispatch_once(self, now: float) -> bool:
        session = self._free_session()
        if session is None:
            return False
        available = []
        snapshots = {}
        for channel_id, mailbox in self.mailboxes.items():
            if not self.online[channel_id]:
                continue
            snapshot = mailbox.snapshot()
            if snapshot is None or snapshot.generation <= self.last_dispatched_generation[channel_id]:
                continue
            available.append(channel_id)
            snapshots[channel_id] = snapshot
        channel_id = self.scheduler.next_ready(now, available)
        if channel_id is None:
            return False
        snapshot = snapshots[channel_id]
        channel = self.channels[channel_id]
        task = InferenceTask(
            session_id=session.session_id,
            channel_id=channel_id,
            generation=snapshot.generation,
            captured_at=snapshot.captured_at,
            dispatched_at=float(now),
            frame=snapshot.frame,
            pts_ms=self.frame_pts.pop((channel_id, snapshot.generation), snapshot.captured_at * 1000.0),
            channel_values={
                "detectors": channel.detectors,
                "color_roi": _roi((channel.values or {}).get("COLOR_ROI")),
                "enable_level": _bool((channel.values or {}).get("ENABLE_WATER_LEVEL_ALARM")),
                "level_roi": _roi((channel.values or {}).get("LEVEL_ROI")),
                "level_ref_row": float((channel.values or {}).get("LEVEL_REF_ROW", "0.55")),
                "level_tol": float((channel.values or {}).get("LEVEL_TOL", "0.06")),
            },
        )
        session.submit(task)
        self.last_dispatched_generation[channel_id] = snapshot.generation
        self.scheduler.mark_dispatched(channel_id, now)
        return True

    def handle_result(self, result: dict) -> None:
        session_id = str(result["session_id"])
        session = self.sessions[session_id]
        error = result.get("error")
        if error:
            session.request_restart(str(error))
            return
        session.busy = False
        channel = self.channels[str(result["channel_id"])]
        enriched = dict(result)
        enriched["boxes"] = filter_boxes(
            result.get("boxes", ()), channel.confidence, channel.allowed_alarm_types
        )
        self.backend.publish_result(channel, enriched)


def _bool(value: str | None) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def _roi(value: str | None):
    if not value:
        return None
    parts = tuple(float(item) for item in value.split(","))
    return parts if len(parts) == 4 else None
