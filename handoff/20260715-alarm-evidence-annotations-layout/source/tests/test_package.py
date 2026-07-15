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
            "scripts/apply-alarm-evidence-annotations-layout-increment-20260715.sh",
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


if __name__ == "__main__":
    unittest.main()
