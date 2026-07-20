from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
from typing import Iterable

import numpy as np


@dataclass(frozen=True)
class FrameSnapshot:
    frame: np.ndarray
    captured_at: float
    generation: int


class LatestFrameMailbox:
    def __init__(self) -> None:
        self._lock = Lock()
        self._frame: np.ndarray | None = None
        self._captured_at = 0.0
        self._generation = 0

    def publish(self, frame: np.ndarray, captured_at: float) -> int:
        with self._lock:
            self._frame = np.array(frame, copy=True)
            self._captured_at = float(captured_at)
            self._generation += 1
            return self._generation

    def snapshot(self) -> FrameSnapshot | None:
        with self._lock:
            if self._frame is None:
                return None
            return FrameSnapshot(
                frame=np.array(self._frame, copy=True),
                captured_at=self._captured_at,
                generation=self._generation,
            )


@dataclass
class _ChannelDeadline:
    interval: float
    next_due: float
    registration_order: int


class DeadlineScheduler:
    def __init__(self) -> None:
        self._channels: dict[str, _ChannelDeadline] = {}
        self._registration_counter = 0

    def register(self, channel_id: str, fps: float, *, now: float = 0.0) -> None:
        value = float(fps)
        if value <= 0:
            raise ValueError("fps must be greater than zero")
        if channel_id in self._channels:
            order = self._channels[channel_id].registration_order
        else:
            order = self._registration_counter
            self._registration_counter += 1
        self._channels[channel_id] = _ChannelDeadline(1.0 / value, float(now), order)

    def deadline_seconds(self, channel_id: str) -> float:
        return self._channels[channel_id].interval

    def mark_dispatched(self, channel_id: str, now: float) -> None:
        state = self._channels[channel_id]
        state.next_due = float(now) + state.interval

    def next_ready(self, now: float, available_channels: Iterable[str]) -> str | None:
        available = set(available_channels)
        ready = [
            (state.next_due, state.registration_order, channel_id)
            for channel_id, state in self._channels.items()
            if channel_id in available and state.next_due <= float(now) + 1e-9
        ]
        if not ready:
            return None
        ready.sort()
        return ready[0][2]


def filter_boxes(
    boxes: Iterable[dict], confidence: float, allowed_classes: Iterable[str] | None = None
) -> list[dict]:
    threshold = float(confidence)
    allowed = {str(item).strip() for item in (allowed_classes or ()) if str(item).strip()}
    return [
        dict(box)
        for box in boxes
        if float(box.get("score", 0.0)) >= threshold
        and (not allowed or str(box.get("cls") or box.get("label") or box.get("name") or "").strip() in allowed)
    ]
