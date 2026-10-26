"""Negative-path tests for vector_gate.validate and its command line (synthetic data only).

Each failure message is asserted by substring. Rejections must leave status FAIL
and never PASS. Behaviour for structurally invalid receipts that currently
raise instead of returning FAIL is intentionally not pinned here.
"""
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

base = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('vector_gate', base / 'vector_gate.py')
vg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vg)
REF = 'a' * 64


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'receipt.json'
        self.receipt = {
            'schema': 'kni.vector-delivery-gate.v1', 'source_font_sha256': REF, 'status': 'PASS',
            'glyphs': [{'codepoint': 65, 'path_label': 'vector', 'symmetric_difference_area': 2.0,
                        'area_floor': 2.0, 'hausdorff': 1.0, 'distance_floor': 1.0}],
            'table_rows': [
                {'codepoint': 65, 'path_label': 'vector', 'metric': 'symmetric_difference_area',
                 'value': 2.0, 'limit': 2.0, 'unit': 'unit^2', 'pass': True},
                {'codepoint': 65, 'path_label': 'vector', 'metric': 'hausdorff',
                 'value': 1.0, 'limit': 1.0, 'unit': 'units', 'pass': True}]}

    def result(self, expected=frozenset({65}), ref=REF):
        self.path.write_text(json.dumps(self.receipt))
        return vg.validate(self.path, ref, set(expected))

    def assertFails(self, needle, **kw):
        r = self.result(**kw)
        self.assertEqual(r['status'], 'FAIL')
        self.assertTrue(any(needle in f for f in r['failures']), (needle, r['failures']))
        return r

    def row(self, metric):
        return next(r for r in self.receipt['table_rows'] if r['metric'] == metric)


class Control(Base):
    def test_control_passes(self):
        r = self.result()
        self.assertEqual((r['status'], r['failures']), ('PASS', []))


class FileAndSchema(Base):
    def test_unreadable_receipt_files(self):
        for raw in (b'', b'{not json', b'{"a":'):
            self.path.write_bytes(raw)
            r = vg.validate(self.path, REF, {65})
            self.assertEqual(r['status'], 'FAIL')
            self.assertTrue(r['failures'][0].startswith('vector receipt unreadable'))
            self.assertEqual((r['glyph_count'], r['table_row_count']), (0, 0))

    def test_missing_receipt_file(self):
        r = vg.validate(self.path, REF, {65})
        self.assertEqual(r['status'], 'FAIL')
        self.assertIsNone(r['receipt_sha256'])

    def test_unsupported_schema(self):
        for value in ('kni.vector-delivery-gate.v2', '', None, 5):
            self.setUp()
            self.receipt['schema'] = value
            self.assertFails('unsupported vector receipt schema')
        self.setUp()
        del self.receipt['schema']
        self.assertFails('unsupported vector receipt schema')

    def test_source_font_hash_mismatch_and_wrong_reference(self):
        self.assertFails('source font hash mismatch', ref='b' * 64)
        self.receipt['source_font_sha256'] = 'b' * 64
        self.assertFails('source font hash mismatch')
        del self.receipt['source_font_sha256']
        self.assertFails('source font hash mismatch')

    def test_receipt_status_not_pass(self):
        for value in ('FAIL', 'N/A', None, True, 'pass'):
            self.setUp()
            self.receipt['status'] = value
            self.assertFails('vector receipt status is not PASS')


class GlyphRows(Base):
    def test_glyph_rows_missing_or_wrong_type(self):
        for value in (None, {}, 'x', 5):
            self.receipt['glyphs'] = value
            self.assertFails('vector receipt glyph rows missing')
        del self.receipt['glyphs']
        self.assertFails('vector receipt glyph rows missing')

    def test_invalid_glyph_row_types(self):
        for row in (None, 5, 'x', [1]):
            self.receipt['glyphs'].append(row)
            self.assertFails('invalid vector glyph row')
            self.receipt['glyphs'].pop()

    def test_invalid_glyph_codepoints(self):
        for cp in (None, True, -1, 0x110000, 'zz', 'U+zz', 1.5, [], {}):
            self.setUp()
            g = dict(self.receipt['glyphs'][0], codepoint=cp)
            self.receipt['glyphs'] = [g]
            self.assertFails('invalid vector glyph codepoint')

    def test_valid_codepoint_spellings_are_accepted(self):
        for cp in ('U+0041', '41', 65):
            self.setUp()
            self.receipt['glyphs'][0]['codepoint'] = cp
            self.assertEqual(self.result()['status'], 'PASS', cp)

    def test_duplicate_glyph_row_even_with_mixed_spelling(self):
        self.receipt['glyphs'].append(dict(self.receipt['glyphs'][0], codepoint='U+0041'))
        self.assertFails('duplicate vector glyph row: 65')

    def test_glyph_path_label(self):
        for label in ('image', None, '', 'Vector'):
            self.setUp()
            self.receipt['glyphs'][0]['path_label'] = label
            self.assertFails('vector path label missing or incorrect')
        del self.receipt['glyphs'][0]['path_label']
        self.assertFails('vector path label missing or incorrect')

    def test_codepoint_coverage_both_directions(self):
        self.assertFails('do not exactly cover the source cmap', expected={65, 66})
        self.assertFails('do not exactly cover the source cmap', expected=set())
        self.receipt['glyphs'].append(dict(self.receipt['glyphs'][0], codepoint=66))
        self.assertFails('do not exactly cover the source cmap')


class TableRows(Base):
    def test_table_rows_missing_or_wrong_type(self):
        for value in (None, {}, 'x', 5):
            self.receipt['table_rows'] = value
            self.assertFails('vector table rows missing')
        del self.receipt['table_rows']
        self.assertFails('vector table rows missing')

    def test_invalid_table_row_types(self):
        for row in (None, 5, 'x', [1]):
            self.receipt['table_rows'].append(row)
            self.assertFails('invalid vector table row')
            self.receipt['table_rows'].pop()

    def test_invalid_table_codepoints(self):
        for cp in (None, True, -1, 0x110000, 'zz', 1.5):
            self.setUp()
            self.row('hausdorff')['codepoint'] = cp
            self.assertFails('invalid vector table codepoint')

    def test_duplicate_metric_row(self):
        self.receipt['table_rows'].append(copy.deepcopy(self.row('hausdorff')))
        self.assertFails('duplicate vector metric row: 65 hausdorff')

    def test_row_path_label(self):
        self.row('hausdorff')['path_label'] = 'image'
        self.assertFails('table row path label missing or incorrect')
        del self.row('hausdorff')['path_label']
        self.assertFails('table row path label missing or incorrect')

    def test_unsupported_metric(self):
        for metric in ('area', None, '', 'Hausdorff'):
            self.setUp()
            self.receipt['table_rows'][1]['metric'] = metric
            self.assertFails('unsupported vector metric')

    def test_unit_mismatch(self):
        for unit in ('px', 'unit^2', None, ''):
            self.setUp()
            self.row('hausdorff')['unit'] = unit
            self.assertFails('hausdorff: unit mismatch')
        self.setUp()
        self.row('hausdorff')['unit'] = 'units'
        self.row('symmetric_difference_area')['unit'] = 'units'
        self.assertFails('symmetric_difference_area: unit mismatch')

    def test_value_must_be_finite_nonnegative_number(self):
        for bad in (-0.001, float('nan'), float('inf'), True, '1.0', None):
            with self.subTest(bad=repr(bad)):
                self.setUp()
                self.row('hausdorff')['value'] = bad
                self.path.write_text(json.dumps(self.receipt))
                r = vg.validate(self.path, REF, {65})
                self.assertEqual(r['status'], 'FAIL')
                self.assertTrue(any('hausdorff: value must be finite and nonnegative' in f for f in r['failures']))

    def test_limit_must_be_finite_nonnegative_number(self):
        for bad in (-1, float('nan'), float('-inf'), False, '1', None):
            with self.subTest(bad=repr(bad)):
                self.setUp()
                self.row('hausdorff')['limit'] = bad
                self.path.write_text(json.dumps(self.receipt))
                r = vg.validate(self.path, REF, {65})
                self.assertEqual(r['status'], 'FAIL')
                self.assertTrue(any('hausdorff: limit must be finite and nonnegative' in f for f in r['failures']))

    def test_value_exceeds_limit_and_boundary(self):
        self.row('hausdorff')['value'] = 1.0000001
        self.row('hausdorff')['pass'] = False
        self.receipt['glyphs'][0]['hausdorff'] = 1.0000001
        r = self.assertFails('hausdorff: measured value exceeds its limit')
        self.assertTrue(any('non-passing metric row' in f for f in r['failures']))

    def test_pass_flag_disagrees_both_ways(self):
        self.row('hausdorff')['pass'] = False
        self.assertFails('pass flag disagrees with the gate criterion')
        self.setUp()
        self.row('hausdorff')['value'] = 2.0
        self.receipt['glyphs'][0]['hausdorff'] = 2.0
        self.row('hausdorff')['pass'] = True
        self.assertFails('pass flag disagrees with the gate criterion')

    def test_pass_flag_must_be_boolean_true_not_truthy(self):
        for flag in (1, 'true', None, 'PASS'):
            self.setUp()
            self.row('hausdorff')['pass'] = flag
            self.assertFails('pass flag disagrees with the gate criterion')

    def test_summary_vs_table_disagree(self):
        self.receipt['glyphs'][0]['hausdorff'] = 0.5
        self.assertFails('hausdorff: summary and table row disagree')
        self.setUp()
        self.receipt['glyphs'][0]['distance_floor'] = 9.0
        self.assertFails('hausdorff: summary and table row disagree')
        self.setUp()
        self.receipt['glyphs'][0]['area_floor'] = 9.0
        self.assertFails('symmetric_difference_area: summary and table row disagree')

    def test_required_rows_must_cover_every_glyph_and_metric(self):
        self.receipt['table_rows'].pop()
        self.assertFails('do not exactly cover every glyph and required metric')
        self.setUp()
        self.receipt['table_rows'] = []
        self.assertFails('do not exactly cover every glyph and required metric')
        self.setUp()
        extra = copy.deepcopy(self.receipt['table_rows'])
        for r in extra:
            r['codepoint'] = 66
        self.receipt['table_rows'] += extra
        self.assertFails('do not exactly cover every glyph and required metric')

    def test_non_passing_row_with_pass_status_still_fails(self):
        self.row('hausdorff')['value'] = 5
        self.row('hausdorff')['pass'] = False
        self.receipt['glyphs'][0]['hausdorff'] = 5
        self.receipt['status'] = 'PASS'
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_failures_accumulate_and_status_is_never_pass(self):
        self.receipt['schema'] = 'x'
        self.receipt['status'] = 'FAIL'
        self.receipt['glyphs'][0]['path_label'] = 'image'
        r = self.result()
        self.assertEqual(r['status'], 'FAIL')
        self.assertGreaterEqual(len(r['failures']), 3)


class CommandLine(Base):
    def cli(self, *extra, codepoints='U+0041'):
        self.path.write_text(json.dumps(self.receipt))
        cmd = [sys.executable, str(base / 'vector_gate.py'), '--receipt', str(self.path),
               '--reference-font-sha256', REF, '--codepoints', codepoints, *extra]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return p

    def test_cli_pass_exit_zero(self):
        p = self.cli()
        self.assertEqual(p.returncode, 0)
        self.assertEqual(json.loads(p.stdout)['status'], 'PASS')

    def test_cli_fail_exit_one(self):
        self.receipt['status'] = 'FAIL'
        p = self.cli()
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(p.stdout)['status'], 'FAIL')

    def test_cli_codepoint_mismatch_exit_one(self):
        p = self.cli(codepoints='U+0041,U+0042')
        self.assertEqual(p.returncode, 1)

    def test_cli_output_file_written_on_fail(self):
        out = Path(self.tmp.name) / 'out.json'
        self.receipt['status'] = 'FAIL'
        p = self.cli('--output', str(out))
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(out.read_text())['status'], 'FAIL')

    def test_cli_missing_required_argument_exit_two(self):
        p = subprocess.run([sys.executable, str(base / 'vector_gate.py'), '--receipt', str(self.path)],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 2)

    def test_cli_unreadable_receipt_exit_one_with_fail_json(self):
        self.path.write_text('{bad')
        p = subprocess.run([sys.executable, str(base / 'vector_gate.py'), '--receipt', str(self.path),
                            '--reference-font-sha256', REF, '--codepoints', 'U+0041'],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(p.stdout)['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
