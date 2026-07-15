from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PackageTest(unittest.TestCase):
    def test_required_files_exist(self):
        required = [
            "backend/src/server.mjs",
            "backend/src/store.mjs",
            "backend/src/alarm-evidence.mjs",
            "frontend/src/components/WorkspaceDialogs.vue",
            "frontend/src/composables/useWorkspace.ts",
            "frontend/src/styles.css",
            "frontend/dist/index.html",
            "db/backfill-alarm-evidence-annotations.sql",
            "scripts/apply-alarm-evidence-annotations-layout-increment-20260715-v2.sh",
        ]
        for relative in required:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_annotation_flow_is_present(self):
        server = (ROOT / "backend/src/server.mjs").read_text(encoding="utf-8")
        store = (ROOT / "backend/src/store.mjs").read_text(encoding="utf-8")
        evidence = (ROOT / "backend/src/alarm-evidence.mjs").read_text(encoding="utf-8")
        workspace = (ROOT / "frontend/src/composables/useWorkspace.ts").read_text(encoding="utf-8")
        self.assertIn("alarmEvidenceMetadataMatch", server)
        self.assertIn("annotation_data", store)
        self.assertIn("annotations: evidenceAnnotations(payload)", evidence)
        self.assertIn("capturedAlarmEvidenceMetadata", workspace)

    def test_review_details_use_three_columns(self):
        dialog = (ROOT / "frontend/src/components/WorkspaceDialogs.vue").read_text(encoding="utf-8")
        styles = (ROOT / "frontend/src/styles.css").read_text(encoding="utf-8")
        self.assertEqual(dialog.count('class="alarm-review-detail-item"'), 13)
        self.assertIn(".alarm-review-detail-grid", styles)
        self.assertIn("grid-template-columns: repeat(3, minmax(0, 1fr));", styles)

    def test_package_is_rebased_on_exported_production_backend(self):
        script = (ROOT / "scripts/apply-alarm-evidence-annotations-layout-increment-20260715-v2.sh").read_text(encoding="utf-8")
        server = (ROOT / "backend/src/server.mjs").read_text(encoding="utf-8")
        store = (ROOT / "backend/src/store.mjs").read_text(encoding="utf-8")
        self.assertIn("7db1272481c3a6e51797759c22f1cb8574d1c1abed5044b7988baffc6f8182ca", script)
        self.assertIn("5105048363fe6f2fdd0095a6e8a867abe358701b3c3b588c738c284fdb913196", script)
        for marker in (
            "configureIntegrationsFromEnv",
            "createWvpSyncFromEnv",
            "applySecurityHeaders",
            "bootSecurityCheck",
            "emitAudit",
            "emitMetric",
        ):
            self.assertNotIn(marker, server + store)


if __name__ == "__main__":
    unittest.main()
