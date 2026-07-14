from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
DB = ROOT / "db"


class RuntimeTopologyPackageTest(unittest.TestCase):
    def read(self, relative: str) -> str:
        path = ROOT / relative
        self.assertTrue(path.is_file(), f"missing package file: {relative}")
        return path.read_text(encoding="utf-8")

    def test_package_contains_no_model_weights(self):
        weights = [
            path.relative_to(ROOT)
            for path in ROOT.rglob("*")
            if path.is_file() and path.suffix.lower() in {".onnx", ".pt", ".engine", ".plan"}
        ]
        self.assertEqual(weights, [])

    def test_apply_script_guards_exact_group_models_and_gpu_provider(self):
        script = self.read("scripts/apply-ai-runtime-topology-increment-20260714.sh")
        for expected in (
            "river-ai-group@river-a.service",
            "river-ai-group@river-b.service",
            "river-ai-group@structure.service",
            "assert_active river-ai-batch@structure.service",
            "/etc/river-watch/ai-worker-$channel.env",
            "/opt/river-watch/models/river-anomaly-yolo11n-12cls-20260714.onnx",
            "/opt/river-watch/models/yolo-wall-crack-leak-20260630.onnx",
            "3d7623906d57bdb439a5686dd6b39093c6ca8b9d6e233f3c78027d048d35e3f4",
            "MIGraphXExecutionProvider",
            "trap 'rollback_on_error",
            "systemctl disable --now river-ai-batch@river.service river-ai-batch@structure.service",
        ):
            self.assertIn(expected, script)
        self.assertNotIn("disable --now river-ai-group", script)
        self.assertNotIn("rm -f /opt/river-watch/models", script)
        self.assertIn("CH01 CH02 CH03 CH04 CH05 CH06 CH07 CH08", script)
        self.assertIn("CH09 CH10", script)

    def test_verify_script_requires_group_only_topology(self):
        script = self.read("scripts/verify-ai-runtime-topology-20260714.sh")
        self.assertIn("assert_active river-ai-group@river-a.service", script)
        self.assertIn("assert_active river-ai-group@river-b.service", script)
        self.assertIn("assert_active river-ai-group@structure.service", script)
        self.assertIn("assert_inactive river-ai-batch@river.service", script)
        self.assertIn("assert_inactive river-ai-batch@structure.service", script)
        self.assertIn("MainPID", script)
        self.assertIn("MIGraphXExecutionProvider", script)
        self.assertNotIn("&& die \"$1 is still active\" || true", script)
        self.assertNotIn("&& die \"$1 is still enabled\" || true", script)

    def test_rollback_uses_saved_state_and_keeps_model_files(self):
        script = self.read("scripts/rollback-ai-runtime-topology-20260714.sh")
        self.assertIn("unit-state.tsv", script)
        self.assertIn("restore_unit_state", script)
        self.assertIn("file-state.tsv", script)
        self.assertNotIn("rm -rf /opt/river-watch/models", script)
        self.assertNotIn("ai-worker-CH", script)

    def test_registry_upsert_owns_only_two_stable_ids(self):
        sql = self.read("db/upsert-production-model-registry.sql")
        self.assertEqual(sql.count("INSERT INTO rw_algorithm"), 2)
        self.assertIn("ALG-RIVER-20260714", sql)
        self.assertIn("ALG-STRUCTURE-20260630", sql)
        self.assertIn("river-anomaly-yolo11n-12cls-20260714.onnx", sql)
        self.assertIn("yolo-wall-crack-leak-20260630.onnx", sql)
        self.assertIn("ON DUPLICATE KEY UPDATE", sql)
        self.assertIn("0.97655", sql)

    def test_shell_scripts_are_syntax_valid(self):
        scripts = sorted(SCRIPTS.glob("*.sh"))
        self.assertGreaterEqual(len(scripts), 3)
        result = subprocess.run(
            ["shellcheck", "-S", "error", *map(str, scripts)],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

