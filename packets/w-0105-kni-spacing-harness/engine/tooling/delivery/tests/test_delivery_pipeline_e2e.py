"""Synthetic integration test for input, gate, and seal handoff."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

base = Path(__file__).parents[1]
sys.path.insert(0, str(base))
sys.path.insert(0, str(base / "tests"))

import test_delivery_gate as delivery_fixtures
import delivery_gate
import seal_evidence
import vector_receipt_producer


class DeliveryPipelineEndToEndTests(unittest.TestCase):
    def setUp(self):
        self.fixture = delivery_fixtures.GateTests(methodName="test_complete")
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.root = self.fixture.root

    def test_synthetic_font_to_delivery_gate_to_seal(self):
        from fontTools.ttLib import TTFont

        source_font_sha = delivery_gate.sha(self.fixture.font)
        cmap = TTFont(self.fixture.font).getBestCmap()
        codepoints = sorted(cmap)
        manifest = {
            "schema": "kni.vector-input-manifest.v1",
            "reference_font_sha256": source_font_sha,
            "codepoints": codepoints,
        }
        measurements = {
            "schema": "kni.vector-measurements.v1",
            "reference_font_sha256": source_font_sha,
            "glyphs": [
                {
                    "codepoint": cp,
                    "path_label": "vector",
                    "symmetric_difference_area": 0.0,
                    "area_floor": 1.0,
                    "hausdorff": 0.0,
                    "distance_floor": 1.0,
                }
                for cp in codepoints
            ],
        }
        manifest_path = self.root / "vector-input.json"
        measurements_path = self.root / "vector-measurements.json"
        receipt_path = self.root / "vector-receipt.json"
        manifest_path.write_text(json.dumps(manifest))
        measurements_path.write_text(json.dumps(measurements))

        produced = vector_receipt_producer.produce(
            manifest_path, measurements_path, receipt_path, set(codepoints)
        )
        self.assertEqual(produced["status"], "PASS")

        delivery_manifest = self.root / "delivery-manifest.json"
        delivery_manifest.write_text(json.dumps(self.fixture.manifest))
        evidence_dir = self.root / "evidence"
        result = delivery_gate.evaluate(
            self.fixture.font,
            delivery_manifest,
            evidence_dir,
            128,
            128,
            receipt_path,
            source_font_sha,
        )
        self.assertEqual(result["status"], "PASS", result["failures"])

        sums = json.loads((evidence_dir / "SHA256SUMS.json").read_text())
        review_path = self.root / "visual-review.json"
        review_path.write_text(
            json.dumps(
                {
                    "reviewer": "synthetic test reviewer",
                    "status": "APPROVED",
                    "font_sha256": source_font_sha,
                    "gate_sha256": delivery_gate.sha(evidence_dir / "gate.json"),
                    "images": {name: digest for name, digest in sums.items() if name.endswith(".png")},
                }
            )
        )
        sealed = seal_evidence.seal(evidence_dir, review_path)
        self.assertEqual(sealed["status"], "DELIVERY_READY")
        self.assertEqual(sealed["font_sha256"], source_font_sha)
        self.assertTrue((evidence_dir / "vector-gate-receipt.json").is_file())


if __name__ == "__main__":
    unittest.main()
