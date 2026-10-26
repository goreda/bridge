import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

base = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('vector_gate', base / 'vector_gate.py')
vector_gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vector_gate)


class VectorGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'receipt.json'
        self.receipt = {
            'schema': 'kni.vector-delivery-gate.v1',
            'source_font_sha256': 'a' * 64,
            'status': 'PASS',
            'glyphs': [{'codepoint': 65, 'path_label': 'vector', 'symmetric_difference_area': 2.0,
                        'area_floor': 2.0, 'hausdorff': 1.0, 'distance_floor': 1.0}],
            'table_rows': [
                {'codepoint': 65, 'path_label': 'vector', 'metric': 'symmetric_difference_area',
                 'value': 2.0, 'limit': 2.0, 'unit': 'unit^2', 'pass': True},
                {'codepoint': 65, 'path_label': 'vector', 'metric': 'hausdorff',
                 'value': 1.0, 'limit': 1.0, 'unit': 'units', 'pass': True},
            ],
        }

    def tearDown(self):
        self.tmp.cleanup()

    def result(self):
        self.path.write_text(json.dumps(self.receipt))
        return vector_gate.validate(self.path, 'a' * 64, {65})

    def test_boundary_values_pass_and_all_rows_are_path_labelled(self):
        self.assertEqual(self.result()['status'], 'PASS')

    def test_symmetric_difference_over_floor_fails(self):
        self.receipt['table_rows'][0]['value'] = 2.01
        self.receipt['table_rows'][0]['pass'] = False
        self.receipt['glyphs'][0]['symmetric_difference_area'] = 2.01
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_hausdorff_over_floor_fails(self):
        self.receipt['table_rows'][1]['value'] = 1.01
        self.receipt['table_rows'][1]['pass'] = False
        self.receipt['glyphs'][0]['hausdorff'] = 1.01
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_missing_path_label_fails(self):
        self.receipt['table_rows'][0].pop('path_label')
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_cmap_gap_fails_closed(self):
        self.assertEqual(vector_gate.validate(self._write(), 'a' * 64, {65, 66})['status'], 'FAIL')

    def _write(self):
        self.path.write_text(json.dumps(self.receipt))
        return self.path

    def test_malformed_receipt_fails_closed(self):
        self.path.write_text("{")
        self.assertEqual(vector_gate.validate(self.path, "a" * 64, {65})["status"], "FAIL")

    def test_source_font_hash_mismatch_fails(self):
        self.assertEqual(self.result()['status'], 'PASS')
        self.assertEqual(vector_gate.validate(self.path, 'b' * 64, {65})['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
