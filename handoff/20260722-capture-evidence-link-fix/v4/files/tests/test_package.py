from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_apply_is_incremental_and_does_not_touch_database_or_batch_topology():
    source = read("scripts/apply-capture-evidence-link-fix-20260722.sh")
    assert "DELETE FROM" not in source
    assert "TRUNCATE" not in source
    assert "river-ai-batch@" not in source
    assert "docker restart \"$BACKEND_CONTAINER\"" in source
    assert "wait_group structure 1" in source
    assert "wait_group river-a 2" in source
    assert "wait_group river-b 2" in source


def test_apply_has_preflight_backups_automatic_rollback_and_retention():
    source = read("scripts/apply-capture-evidence-link-fix-20260722.sh")
    assert "Verify package and exact production baselines" in source
    assert "Syntax-check candidates before mutation" in source
    assert "Backup every changed file and current service state" in source
    assert "automatic rollback" in source
    assert "NR>2" in source


def test_manual_rollback_restores_all_runtime_surfaces():
    source = read("scripts/rollback-capture-evidence-link-fix-20260722.sh")
    assert "group_pool_worker.py" in source
    assert "/app/src/server.mjs" in source
    assert "/app/src/alarm-evidence.mjs" in source
    assert "/usr/share/nginx/html" in source
    assert "river-training-capture.timer" in source


def test_package_contains_only_scoped_runtime_sources():
    expected = [
        "training_capture/training_capture.py",
        "systemd/river-training-capture.service",
        "systemd/river-training-capture.timer",
        "ai-pipeline/workers/group_pool_worker.py",
        "backend/src/server.mjs",
        "backend/src/alarm-evidence.mjs",
        "frontend/src/composables/useWorkspace.ts",
        "frontend/dist/index.html",
    ]
    for relative in expected:
        assert (ROOT / relative).is_file(), relative


def test_rebase_preserves_event_situation_persistent_aggregation():
    backend = read("backend/src/server.mjs")
    frontend = read("frontend/src/composables/useWorkspace.ts")
    assert "listEventGroups" in backend
    assert "pathName === '/api/events'" in backend
    assert "selectedAggregateEvent" in frontend
