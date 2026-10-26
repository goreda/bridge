import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

base = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('vector_receipt_producer', base / 'vector_receipt_producer.py')
producer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(producer)


class VectorReceiptProducerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.manifest = {
            "schema": "kni.vector-input-manifest.v1",
            "reference_font_sha256": "a" * 64,
            "codepoints": ["U+0041", 66],
        }
        self.measurements = {
            "schema": "kni.vector-measurements.v1",
            "reference_font_sha256": "a" * 64,
            "glyphs": [
                {"codepoint": 65, "path_label": "vector", "symmetric_difference_area": 2.0,
                 "area_floor": 2.0, "hausdorff": 1.0, "distance_floor": 1.0},
                {"codepoint": "U+0042", "path_label": "vector", "symmetric_difference_area": 0.0,
                 "area_floor": 1.5, "hausdorff": 0.5, "distance_floor": 1.0},
            ],
        }

    def tearDown(self):
        self.tmp.cleanup()

    def test_builds_deterministic_full_cmap_receipt(self):
        receipt = producer.build_receipt(self.manifest, self.measurements)
        self.assertEqual(receipt["status"], "PASS")
        self.assertEqual([row["codepoint"] for row in receipt["glyphs"]], [65, 66])
        self.assertEqual(len(receipt["table_rows"]), 4)
        self.assertTrue(all(row["path_label"] == "vector" for row in receipt["table_rows"]))
        self.assertEqual(receipt, producer.build_receipt(self.manifest, self.measurements))

    def test_over_limit_metric_emits_failed_receipt(self):
        self.measurements["glyphs"][1]["hausdorff"] = 1.1
        receipt = producer.build_receipt(self.manifest, self.measurements)
        self.assertEqual(receipt["status"], "FAIL")
        self.assertFalse(receipt["table_rows"][-1]["pass"])

    def test_missing_or_extra_measurement_codepoint_is_rejected(self):
        self.measurements["glyphs"].pop()
        with self.assertRaises(producer.ReceiptInputError):
            producer.build_receipt(self.manifest, self.measurements)

    def test_independent_measured_cmap_must_match_manifest(self):
        with self.assertRaises(producer.ReceiptInputError):
            producer.build_receipt(self.manifest, self.measurements, {65})

    def test_reference_hash_mismatch_is_rejected(self):
        self.measurements["reference_font_sha256"] = "b" * 64
        with self.assertRaises(producer.ReceiptInputError):
            producer.build_receipt(self.manifest, self.measurements)

    def test_duplicate_codepoints_are_rejected(self):
        self.manifest["codepoints"] = [65, "U+0041"]
        with self.assertRaises(producer.ReceiptInputError):
            producer.build_receipt(self.manifest, self.measurements)

    def test_wrong_path_label_and_nan_are_rejected(self):
        self.measurements["glyphs"][0]["path_label"] = "image"
        with self.assertRaises(producer.ReceiptInputError):
            producer.build_receipt(self.manifest, self.measurements)
        self.measurements["glyphs"][0]["path_label"] = "vector"
        self.measurements["glyphs"][0]["hausdorff"] = float("nan")
        with self.assertRaises(producer.ReceiptInputError):
            producer.build_receipt(self.manifest, self.measurements)

    def test_cli_produce_writes_manifest_bound_receipt(self):
        manifest = self.root / "input.json"
        measurements = self.root / "measurements.json"
        output = self.root / "receipt.json"
        manifest.write_text(json.dumps(self.manifest))
        measurements.write_text(json.dumps(self.measurements))
        result = producer.produce(manifest, measurements, output)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(json.loads(output.read_text()), result)


if __name__ == "__main__":
    unittest.main()
