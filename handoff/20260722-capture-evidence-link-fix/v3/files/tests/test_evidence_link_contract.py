from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_worker_embeds_the_exact_detection_frame_with_camera_identity():
    source = (ROOT / "ai-pipeline/workers/group_pool_worker.py").read_text(encoding="utf-8")
    assert 'payload["evidenceFrame"]' in source
    assert '"cameraId": channel.camera_id' in source
    assert '"mimeType": "image/jpeg"' in source
    assert "RIVERWATCH-EVIDENCE-V1|" in source


def test_backend_rejects_evidence_whose_camera_does_not_match_alarm():
    source = (ROOT / "backend/src/alarm-evidence.mjs").read_text(encoding="utf-8")
    assert "evidence camera does not match alarm camera" in source
    assert "decodeEmbeddedEvidenceFrame" in source
    assert "legacy evidence has no verifiable camera marker" in source
    assert "missing-exact-frame" in source
    assert source.count("captureJpegFrame(") == 1


def test_frontend_validates_alarm_and_camera_before_displaying_evidence():
    source = (ROOT / "frontend/src/composables/useWorkspace.ts").read_text(encoding="utf-8")
    assert "evidenceMatchesSelectedAlarm" in source
    assert "证据与当前告警设备不匹配" in source
