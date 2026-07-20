from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_increment_contains_only_scoped_runtime_and_frontend_sources() -> None:
    expected = {
        "ai-pipeline/workers/group_pool_core.py",
        "ai-pipeline/workers/group_pool_runtime.py",
        "frontend/src/composables/useWorkspace.ts",
        "frontend/src/components/WorkspaceDialogs.vue",
        "frontend/src/__tests__/alarmReviewDialog.test.ts",
    }
    actual = {
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*")
        if path.is_file() and ("/workers/" in f"/{path.relative_to(ROOT).as_posix()}" or "/frontend/src/" in f"/{path.relative_to(ROOT).as_posix()}")
    }
    assert expected <= actual


def test_apply_requires_explicit_cleanup_confirmation_and_backup_first() -> None:
    source = (ROOT / "scripts/apply-channel-isolation-evidence-db-cleanup-20260720.sh").read_text(encoding="utf-8")
    assert 'CONFIRM_CLEAR_MESSAGES:-}' in source
    assert 'mysqldump' in source
    assert 'gzip -t "$DB_BACKUP"' in source
    assert source.index('gzip -t "$DB_BACKUP"') < source.index('DELETE FROM rw_alarm;')
    assert 'START TRANSACTION;' in source
    assert 'database-counts-before.tsv' in source
    assert 'database-counts-after.tsv' in source
    assert 'require_safe_root APP_DIR "$APP_DIR"' in source
    assert 'require_safe_root OPT_DIR "$OPT_DIR"' in source


def test_cleanup_does_not_touch_configuration_or_model_tables() -> None:
    source = (ROOT / "scripts/apply-channel-isolation-evidence-db-cleanup-20260720.sh").read_text(encoding="utf-8")
    deleted = set(re.findall(r"DELETE FROM (rw_[a-z_]+)", source))
    assert "rw_alarm" in deleted
    assert "rw_event_group" in deleted
    assert "rw_work_order" in deleted
    assert not deleted & {
        "rw_camera",
        "rw_algorithm",
        "rw_runtime_config",
        "rw_user",
        "rw_role_permission",
        "rw_storage_policy",
        "rw_import_job",
    }


def test_frontend_assets_are_compact() -> None:
    assert (ROOT / "frontend/dist/index.html").is_file()
    assert (ROOT / "frontend/dist/assets").is_dir()
    assert not (ROOT / "frontend/dist/digital-twin").exists()
    assert not (ROOT / "frontend/dist/models").exists()


def test_rollback_rejects_paths_outside_deployment_roots() -> None:
    source = (ROOT / "scripts/rollback-channel-isolation-evidence-db-cleanup-20260720.sh").read_text(encoding="utf-8")
    assert 'ERROR: unsafe APP_DIR' in source
    assert 'ERROR: unsafe OPT_DIR' in source
    assert 'ERROR: unsafe rollback directory' in source

