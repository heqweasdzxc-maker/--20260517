from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_capture_deployment_replaces_old_program_with_ten_day_half_hour_run():
    source = (ROOT / "scripts/apply-capture-evidence-link-fix-20260722.sh").read_text(encoding="utf-8")
    assert "systemctl disable --now river-training-capture.timer" in source
    assert 'rm -rf -- "$INSTALL_DIR"' in source
    assert "MAX_SLOTS=480" in source
    assert "INTERVAL_SEC=1800" in source
    assert "end_epoch=\"$((start_epoch + 10 * 24 * 3600))\"" in source


def test_timer_runs_every_thirty_minutes():
    source = (ROOT / "systemd/river-training-capture.timer").read_text(encoding="utf-8")
    assert "OnUnitActiveSec=30min" in source
    assert "Persistent=true" in source


def test_old_images_are_preserved_during_program_cleanup():
    source = (ROOT / "scripts/apply-capture-evidence-link-fix-20260722.sh").read_text(encoding="utf-8")
    assert "previous captures are preserved" in source
    assert 'rm -rf -- "$OUTPUT_ROOT"' not in source


def test_capture_defaults_match_the_deployed_policy():
    source = (ROOT / "training_capture/training_capture.py").read_text(encoding="utf-8")
    assert "max_slots: int = 480" in source
    assert "interval_sec: int = 1800" in source
    assert 'values.get("MAX_SLOTS", "480")' in source
    assert 'values.get("INTERVAL_SEC", "1800")' in source


def test_frontend_increment_preserves_unrelated_static_features():
    source = (ROOT / "scripts/apply-capture-evidence-link-fix-20260722.sh").read_text(encoding="utf-8")
    assert "rm -rf /usr/share/nginx/html/*" not in source
    assert 'rm -rf "$APP_DIR/frontend/dist"' not in source
    assert "/usr/share/nginx/html/assets" in source
