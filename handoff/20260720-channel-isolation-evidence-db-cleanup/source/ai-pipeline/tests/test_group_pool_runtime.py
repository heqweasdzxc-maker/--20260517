from pathlib import Path

import numpy as np
import pytest

from group_pool_runtime import (
    ChannelConfig,
    GroupConfig,
    GroupRuntime,
    load_channel_config,
    pool_size_for,
    validate_group_config,
)


class FakeSession:
    def __init__(self, session_id="session-1"):
        self.session_id = session_id
        self.busy = False
        self.submissions = []
        self.restart_requests = []

    def submit(self, task):
        assert task.frame.ndim == 3
        self.busy = True
        self.submissions.append(task)

    def request_restart(self, reason):
        self.restart_requests.append(reason)
        self.busy = False


class FakeBackend:
    def __init__(self):
        self.results = []

    def publish_result(self, channel, result):
        self.results.append((channel.camera_id, result))


def channel(camera_id="CH01", *, model="river.onnx", confidence=0.6, fps=4.0):
    return ChannelConfig(
        camera_id=camera_id,
        model_path=model,
        labels="floating,trash",
        image_size=640,
        providers=("MIGraphXExecutionProvider",),
        confidence=confidence,
        sample_fps=fps,
        detectors=("floating",),
    )


def test_pool_sizes_are_exactly_group_standard():
    assert pool_size_for("river-a") == 2
    assert pool_size_for("river-b") == 2
    assert pool_size_for("structure") == 1
    with pytest.raises(ValueError, match="unsupported group"):
        pool_size_for("batch")


def test_group_rejects_mixed_model_sessions():
    config = GroupConfig("river-a", (channel("CH01"), channel("CH02", model="other.onnx")))
    with pytest.raises(ValueError, match="same model"):
        validate_group_config(config)


def test_load_channel_config_preserves_per_camera_values(tmp_path: Path):
    env_file = tmp_path / "ai-worker-CH03.env"
    env_file.write_text(
        "CAMERA_ID=CH03\nYOLO_ONNX=/models/river.onnx\nYOLO_LABELS=a,b\n"
        "YOLO_CONF=0.73\nSAMPLE_FPS=6\nDETECTORS=floating,color\n"
        "ALLOWED_ALARM_TYPES=漂浮物,水色异常,人员落水\n"
        "ORT_PROVIDERS=MIGraphXExecutionProvider,CPUExecutionProvider\n",
        encoding="utf-8",
    )
    loaded = load_channel_config(env_file)
    assert loaded.camera_id == "CH03"
    assert loaded.confidence == 0.73
    assert loaded.sample_fps == 6
    assert loaded.detectors == ("floating", "color")
    assert loaded.allowed_alarm_types == ("漂浮物", "水色异常", "人员落水")


def test_dispatch_submits_one_latest_frame_and_excludes_offline_channel():
    session = FakeSession()
    backend = FakeBackend()
    runtime = GroupRuntime(
        GroupConfig("river-a", (channel("CH01"), channel("CH02"))),
        [session],
        backend,
    )
    runtime.publish_frame("CH01", np.zeros((4, 4, 3), dtype=np.uint8), 1.0)
    runtime.publish_frame("CH02", np.ones((4, 4, 3), dtype=np.uint8), 1.1)
    runtime.set_channel_online("CH01", False)

    assert runtime.dispatch_once(2.0) is True
    assert len(session.submissions) == 1
    assert session.submissions[0].channel_id == "CH02"
    assert session.submissions[0].frame.shape == (4, 4, 3)


def test_result_uses_channel_confidence_and_releases_only_its_session():
    first = FakeSession("first")
    second = FakeSession("second")
    backend = FakeBackend()
    runtime = GroupRuntime(GroupConfig("river-a", (channel(confidence=0.6),)), [first, second], backend)
    runtime.publish_frame("CH01", np.zeros((2, 2, 3), dtype=np.uint8), 1.0)
    runtime.dispatch_once(2.0)
    runtime.handle_result(
        {
            "session_id": "first",
            "channel_id": "CH01",
            "generation": 1,
            "boxes": [{"score": 0.59}, {"score": 0.60}, {"score": 0.9}],
            "latency_ms": 20,
        }
    )
    assert first.busy is False
    assert second.busy is False
    assert [box["score"] for box in backend.results[0][1]["boxes"]] == [0.6, 0.9]


def test_result_rejects_structure_classes_on_river_channel():
    first = FakeSession("first")
    backend = FakeBackend()
    river_channel = channel(confidence=0.25)
    river_channel = ChannelConfig(
        **{
            **river_channel.__dict__,
            "allowed_alarm_types": ("漂浮物", "漂浮物聚集", "浮游物", "水色异常", "人员落水", "非法倾倒"),
        }
    )
    runtime = GroupRuntime(GroupConfig("river-a", (river_channel,)), [first], backend)

    runtime.handle_result(
        {
            "session_id": "first",
            "channel_id": "CH01",
            "generation": 1,
            "boxes": [
                {"cls": "墙体裂痕", "score": 0.91},
                {"cls": "漂浮物", "score": 0.66},
            ],
        }
    )

    assert backend.results[0][1]["boxes"] == [{"cls": "漂浮物", "score": 0.66}]


def test_failed_session_requests_only_that_session_restart():
    first = FakeSession("first")
    second = FakeSession("second")
    runtime = GroupRuntime(GroupConfig("river-a", (channel(),)), [first, second], FakeBackend())
    first.busy = True
    runtime.handle_result(
        {
            "session_id": "first",
            "channel_id": "CH01",
            "generation": 1,
            "error": "provider failure",
        }
    )
    assert first.restart_requests == ["provider failure"]
    assert second.restart_requests == []
