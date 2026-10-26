"""Negative-path tests for vector_v2 (synthetic inputs only; no production changes).

Covers: manifest/measurement/cmap validation errors, independent cmap file
checks, hash bindings, receipt tampering, producer side effects on failure,
and the command line exit codes. Run from the delivery directory, or with that
directory on PYTHONPATH.
"""
import contextlib
import copy
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import vector_v2 as v
from vector_v2 import (BINDINGS, MANIFEST, MEASUREMENT, METHOD, RECEIPT, InputError,
                       build_receipt, gate, produce, read, schema_check, sha, verified_inputs)

CMAP_SCHEMA = 'kni.measured-cmap.v2'


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ref = self.root / 'ref.bin'
        self.cand = self.root / 'cand.bin'
        self.ref.write_bytes(b'synthetic reference byte stream')
        self.cand.write_bytes(b'synthetic candidate byte stream')
        self.ctx = {'reference_font_sha256': sha(self.ref), 'candidate_font_sha256': sha(self.cand),
                    'upm': 1000, 'params': {'grid': 0.5, 'margin': 1}, 'method': METHOD,
                    'scope': 'outlines-only'}
        self.manifest = {'schema': MANIFEST, **copy.deepcopy(self.ctx), 'codepoints': [65, 66]}
        self.rows = [{'codepoint': cp, 'path_label': 'vector', 'symmetric_difference_area': 0.25,
                      'area_floor': 1, 'hausdorff': 0.1, 'distance_floor': 0.5} for cp in (65, 66)]
        self.measurements = {'schema': MEASUREMENT, **copy.deepcopy(self.ctx), 'n_a_count': 0,
                             'glyphs': copy.deepcopy(self.rows)}
        self.cmap = {'schema': CMAP_SCHEMA, 'reference_font_sha256': sha(self.ref), 'codepoints': [65, 66]}
        self.receipt = self.root / 'receipt.json'

    def write(self):
        self.pm, self.pme, self.pc = (self.root / n for n in ('manifest.json', 'measurement.json', 'cmap.json'))
        self.pm.write_text(json.dumps(self.manifest))
        self.pme.write_text(json.dumps(self.measurements))
        self.pc.write_text(json.dumps(self.cmap))
        return (self.pm, self.pme, self.pc, self.ref, self.cand)

    def args(self):
        return self.write()

    def build(self):
        return build_receipt(self.manifest, self.measurements, [65, 66], 'c' * 64)

    def na(self, cp=66, reason='empty outline'):
        self.measurements['glyphs'][1] = {'codepoint': cp, 'status': 'n/a', 'reason': reason}
        self.measurements['n_a_count'] = 1

    def assertInputError(self, fn, *a, startswith=None, equals=None):
        with self.assertRaises(InputError) as c:
            fn(*a)
        if startswith is not None:
            self.assertTrue(str(c.exception).startswith(startswith), str(c.exception))
        if equals is not None:
            self.assertEqual(str(c.exception), equals)
        return c.exception

    def gate_failure(self, receipt=None):
        out = gate(receipt or self.receipt, *self.args())
        self.assertEqual(out['status'], 'FAIL')
        self.assertEqual(out['schema'], RECEIPT)
        self.assertEqual(len(out['failures']), 1)
        return out['failures'][0]


class TestControl(Fixture):
    def test_control_fixture_passes_end_to_end(self):
        args = self.args()
        r = produce(*args, self.receipt)
        self.assertEqual(r['status'], 'PASS')
        self.assertEqual(gate(self.receipt, *args)['status'], 'PASS')


class V1ManifestDuplicates(Fixture):
    def test_v1_duplicate_manifest_codepoint_is_rejected_by_schema(self):
        # The explicit duplicate check in validate_inputs is behind the schema's
        # uniqueItems, so through the public functions the error is a schema error.
        self.manifest['codepoints'] = [65, 65]
        self.assertInputError(self.build, startswith='schema:')

    def test_v1_manifest_codepoint_list_shape(self):
        for bad in ([], [65, True], [65, -1], [65, 1114112], [65, 65.5], ['65'], None):
            with self.subTest(bad=bad):
                self.manifest['codepoints'] = bad
                self.assertInputError(self.build, startswith='schema:')


class V2MeasurementSha(Fixture):
    def test_v2_invalid_measurement_sha_values(self):
        for bad in ('', 'c' * 63, 'c' * 65, 'C' * 64, 'g' * 64, ' ' + 'c' * 63):
            with self.subTest(bad=bad):
                self.assertInputError(lambda: build_receipt(self.manifest, self.measurements, [65, 66], bad),
                                      equals='invalid measurement SHA')

    def test_v2_valid_sha_is_embedded_unchanged(self):
        r = build_receipt(self.manifest, self.measurements, [65, 66], '0123456789abcdef' * 4)
        self.assertEqual(r['measurement_sha256'], '0123456789abcdef' * 4)


class V3V4V5CmapFile(Fixture):
    def run_verified(self):
        return verified_inputs(*self.args())

    def test_v3_cmap_schema_mismatches(self):
        cases = {
            'wrong schema string': lambda c: c.__setitem__('schema', 'kni.measured-cmap.v1'),
            'missing schema': lambda c: c.pop('schema'),
            'missing codepoints': lambda c: c.pop('codepoints'),
            'missing hash': lambda c: c.pop('reference_font_sha256'),
            'extra key': lambda c: c.__setitem__('note', 'x'),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name):
                self.setUp()
                mutate(self.cmap)
                self.assertInputError(self.run_verified, equals='independent cmap schema mismatch')

    def test_v3_cmap_not_an_object(self):
        for text in ('[]', 'null', '"x"', '5'):
            with self.subTest(text=text):
                self.args()
                self.pc.write_text(text)
                self.assertInputError(lambda: verified_inputs(self.pm, self.pme, self.pc, self.ref, self.cand),
                                      equals='independent cmap schema mismatch')

    def test_v3_cmap_file_unreadable_or_invalid_json(self):
        self.args()
        self.pc.write_text('{not json')
        self.assertInputError(lambda: verified_inputs(self.pm, self.pme, self.pc, self.ref, self.cand))
        self.pc.unlink()
        self.assertInputError(lambda: verified_inputs(self.pm, self.pme, self.pc, self.ref, self.cand))

    def test_v3_cmap_duplicate_key_and_nonfinite(self):
        self.args()
        for text in ('{"schema":"%s","schema":"%s"}' % (CMAP_SCHEMA, CMAP_SCHEMA), '{"codepoints":[NaN]}'):
            self.pc.write_text(text)
            self.assertInputError(lambda: verified_inputs(self.pm, self.pme, self.pc, self.ref, self.cand))

    def test_v4_invalid_cmap_codepoints(self):
        for bad in ([True, 66], [65, -1], [65, 0x110000], [65.0, 66], ['65', 66], [None], 'abc', 65, {'a': 1}):
            with self.subTest(bad=bad):
                self.setUp()
                self.cmap['codepoints'] = bad
                self.assertInputError(self.run_verified, equals='invalid independent cmap codepoints')

    def test_v4_cmap_codepoint_bounds_accepted(self):
        for cps in ([0, 1114111],):
            self.setUp()
            self.manifest['codepoints'] = cps
            self.measurements['glyphs'] = [dict(self.rows[0], codepoint=c) for c in cps]
            self.cmap['codepoints'] = cps
            self.assertEqual(self.run_verified()['status'], 'PASS')

    def test_v4_cmap_set_differences_and_duplicates(self):
        for cps in ([65], [65, 66, 67], [65, 66, 66], [], [65, 67]):
            with self.subTest(cps=cps):
                self.setUp()
                self.cmap['codepoints'] = cps
                self.assertInputError(self.run_verified, equals='independent reference cmap mismatch')

    def test_v5_cmap_hash_mismatch(self):
        self.cmap['reference_font_sha256'] = 'd' * 64
        self.assertInputError(self.run_verified, equals='independent cmap hash mismatch')

    def test_v5_cmap_hash_matching_candidate_instead_of_reference_is_rejected(self):
        self.cmap['reference_font_sha256'] = self.ctx['candidate_font_sha256']
        self.assertInputError(self.run_verified, equals='independent cmap hash mismatch')

    def test_v5_cmap_hash_not_hex_is_rejected(self):
        self.cmap['reference_font_sha256'] = 'zz'
        self.assertInputError(self.run_verified, equals='independent cmap hash mismatch')

    def test_order_font_hash_checked_before_cmap_hash(self):
        self.cmap['reference_font_sha256'] = 'd' * 64
        self.ref.write_bytes(b'changed')
        self.assertInputError(self.run_verified, equals='font byte hash mismatch')


class V11Variants(Fixture):
    def test_font_hash_mismatch_each_side(self):
        for path in ('ref', 'cand'):
            with self.subTest(path=path):
                self.setUp()
                args = self.args()
                getattr(self, path).write_bytes(b'changed bytes')
                self.assertInputError(lambda: verified_inputs(*args), equals='font byte hash mismatch')

    def test_n_a_count_both_directions(self):
        self.measurements['n_a_count'] = 1
        self.assertInputError(self.build, equals='n_a_count mismatch')
        self.setUp()
        self.na()
        self.measurements['n_a_count'] = 0
        self.assertInputError(self.build, equals='n_a_count mismatch')
        self.setUp()
        self.na()
        self.measurements['n_a_count'] = 2
        self.assertInputError(self.build, equals='n_a_count mismatch')

    def test_n_a_count_negative_or_non_integer(self):
        for bad in (-1, 1.5, '0', None, True):
            with self.subTest(bad=bad):
                self.measurements['n_a_count'] = bad
                self.assertInputError(self.build, startswith='schema:')

    def test_binding_mismatch_names_the_key(self):
        # method and scope are schema constants on both sides, so only these
        # four bindings can mismatch between two schema-valid documents.
        cases = [('reference_font_sha256', 'd' * 64), ('candidate_font_sha256', 'e' * 64),
                 ('upm', 2000), ('params', {'grid': 1, 'margin': 2})]
        for key, value in cases:
            with self.subTest(key=key):
                m = copy.deepcopy(self.measurements)
                m[key] = value
                self.assertInputError(lambda: build_receipt(self.manifest, m, [65, 66], 'c' * 64),
                                      equals='binding mismatch: ' + key)

    def test_binding_method_and_scope_mismatch_is_a_schema_error(self):
        for key, value in (('method', 'unknown'), ('scope', 'full')):
            with self.subTest(key=key):
                m = copy.deepcopy(self.measurements)
                m[key] = value
                self.assertInputError(lambda: build_receipt(self.manifest, m, [65, 66], 'c' * 64),
                                      startswith='schema:')

    def test_params_partial_change_each_field(self):
        for params in ({'grid': 0.5, 'margin': 2}, {'grid': 0.25, 'margin': 1}):
            m = copy.deepcopy(self.measurements)
            m['params'] = params
            self.assertInputError(lambda: build_receipt(self.manifest, m, [65, 66], 'c' * 64),
                                  equals='binding mismatch: params')

    def test_upm_int_float_equivalence_is_accepted(self):
        m = copy.deepcopy(self.measurements)
        m['upm'] = 1000.0
        self.assertEqual(build_receipt(self.manifest, m, [65, 66], 'c' * 64)['status'], 'PASS')

    def test_measurement_keyset_variants(self):
        for cps in ([65], [65, 67], [65, 66, 67], [67, 68]):
            with self.subTest(cps=cps):
                self.measurements['glyphs'] = [dict(self.rows[0], codepoint=c) for c in cps]
                self.assertInputError(self.build, equals='measurement keyset mismatch')

    def test_duplicate_measurement_numeric_and_na(self):
        self.measurements['glyphs'].append(dict(self.rows[0]))
        self.assertInputError(self.build, equals='duplicate measurement codepoint')
        self.setUp()
        self.measurements['glyphs'] = [{'codepoint': 65, 'status': 'n/a', 'reason': 'a'},
                                       {'codepoint': 65, 'status': 'n/a', 'reason': 'b'}]
        self.measurements['n_a_count'] = 2
        self.assertInputError(self.build, equals='duplicate measurement codepoint')

    def test_measurement_row_schema_errors(self):
        cases = {
            'negative value': lambda g: g.__setitem__('hausdorff', -0.0001),
            'string value': lambda g: g.__setitem__('hausdorff', '0.1'),
            'null value': lambda g: g.__setitem__('area_floor', None),
            'bool value': lambda g: g.__setitem__('distance_floor', False),
            'missing field': lambda g: g.pop('symmetric_difference_area'),
            'extra field': lambda g: g.__setitem__('extra', 1),
            'wrong label': lambda g: g.__setitem__('path_label', 'raster'),
            'codepoint negative': lambda g: g.__setitem__('codepoint', -1),
            'codepoint too large': lambda g: g.__setitem__('codepoint', 1114112),
            'codepoint bool': lambda g: g.__setitem__('codepoint', True),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name):
                self.setUp()
                mutate(self.measurements['glyphs'][0])
                self.assertInputError(self.build, startswith='schema:')

    def test_n_a_row_schema_errors(self):
        for glyph in ({'codepoint': 66, 'status': 'n/a'},
                      {'codepoint': 66, 'status': 'n/a', 'reason': ''},
                      {'codepoint': 66, 'status': 'n/a', 'reason': 5},
                      {'codepoint': 66, 'status': 'NA', 'reason': 'x'},
                      {'codepoint': 66, 'status': 'n/a', 'reason': 'x', 'hausdorff': 0},
                      {'codepoint': 66, 'status': 'n/a', 'reason': 'x', 'symmetric_difference_area': None}):
            with self.subTest(glyph=glyph):
                self.setUp()
                self.measurements['glyphs'][1] = glyph
                self.measurements['n_a_count'] = 1
                self.assertInputError(self.build, startswith='schema:')

    def test_measurements_document_level_schema_errors(self):
        for mutate in (lambda m: m.__setitem__('glyphs', []), lambda m: m.pop('glyphs'),
                       lambda m: m.__setitem__('extra', 1), lambda m: m.__setitem__('upm', 0),
                       lambda m: m.__setitem__('upm', -5), lambda m: m.__setitem__('params', {'grid': 0, 'margin': 1}),
                       lambda m: m.__setitem__('params', {'grid': 1, 'margin': -1}),
                       lambda m: m.__setitem__('params', {'grid': 1}),
                       lambda m: m.__setitem__('schema', 'kni.vector-measurements.v1'),
                       lambda m: m.__setitem__('schema', 'kni.vector-measurements.v3'),
                       lambda m: m.__setitem__('reference_font_sha256', 'A' * 64)):
            self.setUp()
            mutate(self.measurements)
            self.assertInputError(self.build, startswith='schema:')

    def test_manifest_document_level_schema_errors(self):
        for mutate in (lambda m: m.pop('codepoints'), lambda m: m.__setitem__('extra', 1),
                       lambda m: m.__setitem__('schema', 'kni.vector-input-manifest.v1'),
                       lambda m: m.__setitem__('schema', 'kni.vector-input-manifest.v3'),
                       lambda m: m.__setitem__('upm', 0),
                       lambda m: m.__setitem__('candidate_font_sha256', 'xyz')):
            self.setUp()
            mutate(self.manifest)
            self.assertInputError(self.build, startswith='schema:')

    def test_nonfinite_values_from_python_and_from_json_text(self):
        for bad in (float('nan'), float('inf'), float('-inf')):
            self.setUp()
            self.measurements['glyphs'][0]['hausdorff'] = bad
            self.assertInputError(self.build, equals='nonfinite numeric value')
        self.setUp()
        self.measurements['upm'] = float('inf')
        self.assertInputError(self.build, equals='nonfinite numeric value')

    def test_nonfinite_json_constants_and_overflow(self):
        p = self.root / 'x.json'
        for text in ('{"x":NaN}', '{"x":Infinity}', '{"x":-Infinity}'):
            p.write_text(text)
            self.assertInputError(read, p, equals='nonfinite JSON constant')
        p.write_text('{"x":1e999}')
        obj = read(p)
        self.assertInputError(v.finite_tree, obj, equals='nonfinite numeric value')

    def test_duplicate_json_keys_top_level_and_nested(self):
        p = self.root / 'x.json'
        for text in ('{"a":1,"a":2}', '{"a":{"b":1,"b":2}}', '[{"k":1,"k":1}]'):
            p.write_text(text)
            self.assertInputError(read, p, equals='duplicate JSON key')

    def test_read_failure_modes(self):
        p = self.root / 'x.json'
        self.assertInputError(read, p)                      # missing file
        p.write_bytes(b'')
        self.assertInputError(read, p)                      # empty
        p.write_bytes(b'\xff\xfe')
        self.assertInputError(read, p)                      # not UTF-8
        p.write_text('{"a":')
        self.assertInputError(read, p)                      # truncated

    def test_n_a_never_produces_pass_with_every_failure_mix(self):
        self.na()
        self.assertEqual(self.build()['status'], 'N/A')
        self.measurements['glyphs'][0]['symmetric_difference_area'] = 2.0
        self.assertEqual(self.build()['status'], 'FAIL')

    def test_exact_floor_boundary_is_pass(self):
        self.measurements['glyphs'][0]['hausdorff'] = 0.5
        self.measurements['glyphs'][0]['symmetric_difference_area'] = 1
        self.assertEqual(self.build()['status'], 'PASS')

    def test_failure_on_each_metric_separately(self):
        self.measurements['glyphs'][0]['symmetric_difference_area'] = 1.0000001
        r = self.build()
        self.assertEqual(r['status'], 'FAIL')
        failed = [(row['codepoint'], row['metric']) for row in r['table_rows'] if not row['pass']]
        self.assertEqual(failed, [(65, 'symmetric_difference_area')])
        self.setUp()
        self.measurements['glyphs'][1]['hausdorff'] = 0.5000001
        failed = [(row['codepoint'], row['metric']) for row in self.build()['table_rows'] if not row['pass']]
        self.assertEqual(failed, [(66, 'hausdorff')])


class V8ProducerSideEffects(Fixture):
    def test_failed_produce_does_not_create_output(self):
        self.cmap['codepoints'] = [65]
        args = self.args()
        self.assertInputError(lambda: produce(*args, self.receipt), equals='independent reference cmap mismatch')
        self.assertFalse(self.receipt.exists())

    def test_failed_produce_leaves_existing_output_untouched(self):
        self.receipt.write_text('previous contents')
        self.cmap['reference_font_sha256'] = 'd' * 64
        args = self.args()
        self.assertInputError(lambda: produce(*args, self.receipt))
        self.assertEqual(self.receipt.read_text(), 'previous contents')

    def test_produce_overwrites_a_previous_receipt_with_the_new_one(self):
        args = self.args()
        self.receipt.write_text('stale')
        r = produce(*args, self.receipt)
        self.assertEqual(read(self.receipt), r)

    def test_produced_file_is_sorted_key_json_with_trailing_newline_and_no_nonfinite(self):
        args = self.args()
        produce(*args, self.receipt)
        text = self.receipt.read_text()
        self.assertTrue(text.endswith('\n'))
        self.assertEqual(text, json.dumps(json.loads(text), sort_keys=True, indent=2) + '\n')

    def test_produce_is_deterministic(self):
        args = self.args()
        produce(*args, self.receipt)
        first = self.receipt.read_bytes()
        produce(*args, self.receipt)
        self.assertEqual(first, self.receipt.read_bytes())

    def test_receipt_is_independent_of_row_order_in_measurements(self):
        args = self.args()
        a = produce(*args, self.receipt)
        self.measurements['glyphs'].reverse()
        args = self.args()
        b = produce(*args, self.receipt)
        # the bound file hash differs (bytes differ); everything else must match
        a.pop('measurement_sha256'), b.pop('measurement_sha256')
        self.assertEqual(a, b)


class V9ReceiptTampering(Fixture):
    def setUp(self):
        super().setUp()
        self.produced = produce(*self.args(), self.receipt)

    def tamper(self, mutate):
        r = copy.deepcopy(self.produced)
        mutate(r)
        self.receipt.write_text(json.dumps(r))
        return self.gate_failure()

    def test_control_untouched_receipt_passes(self):
        self.assertEqual(gate(self.receipt, *self.args())['status'], 'PASS')

    def test_each_top_level_field_tampered(self):
        mutations = {
            'status': lambda r: r.__setitem__('status', 'FAIL'),
            'status_na': lambda r: r.__setitem__('status', 'N/A'),
            'n_a_count': lambda r: r.__setitem__('n_a_count', 1),
            'measurement_sha256': lambda r: r.__setitem__('measurement_sha256', 'f' * 64),
            'glyphs_value': lambda r: r['glyphs'][0].__setitem__('hausdorff', 0.2),
            'glyphs_dropped': lambda r: r['glyphs'].pop(),
            'glyphs_reordered': lambda r: r['glyphs'].reverse(),
            'table_pass_flag': lambda r: r['table_rows'][0].__setitem__('pass', False),
            'table_value': lambda r: r['table_rows'][0].__setitem__('value', 0.0),
            'table_limit': lambda r: r['table_rows'][0].__setitem__('limit', 99),
            'table_unit': lambda r: r['table_rows'][0].__setitem__('unit', 'px'),
            'table_dropped': lambda r: r['table_rows'].pop(),
            'unmeasurable': lambda r: r.__setitem__('unmeasurable', [{'codepoint': 65, 'reason': 'x'}]),
            'upm': lambda r: r.__setitem__('upm', 2000),
            'params': lambda r: r.__setitem__('params', {'grid': 1, 'margin': 1}),
            'reference_font_sha256': lambda r: r.__setitem__('reference_font_sha256', 'f' * 64),
            'candidate_font_sha256': lambda r: r.__setitem__('candidate_font_sha256', 'f' * 64),
        }
        for name, mutate in mutations.items():
            with self.subTest(field=name):
                self.assertTrue(self.tamper(mutate))

    def test_schema_level_tampering_is_rejected_with_schema_or_difference_message(self):
        for name, mutate in {
            'extra_field': lambda r: r.__setitem__('extra', 1),
            'missing_status': lambda r: r.pop('status'),
            'missing_glyphs': lambda r: r.pop('glyphs'),
            'wrong_schema': lambda r: r.__setitem__('schema', 'kni.vector-delivery-gate.v1'),
            'null_status': lambda r: r.__setitem__('status', None),
        }.items():
            with self.subTest(field=name):
                msg = self.tamper(mutate)
                self.assertTrue(msg.startswith('schema:') or msg.startswith('receipt differs'), msg)

    def test_receipt_file_problems(self):
        for raw in (b'', b'not json', b'[]', b'null', b'\xff\xfe', b'{"a":1,"a":2}', b'{"status":NaN}'):
            with self.subTest(raw=raw):
                self.receipt.write_bytes(raw)
                self.assertTrue(self.gate_failure())
        self.receipt.unlink()
        self.assertTrue(self.gate_failure())

    def test_receipt_for_different_measurements_is_rejected(self):
        self.measurements['glyphs'][0]['hausdorff'] = 0.2
        args = self.args()
        out = gate(self.receipt, *args)
        self.assertEqual(out['status'], 'FAIL')
        self.assertEqual(out['failures'], ['receipt differs from recomputed hash-bound measurements'])

    def test_receipt_from_other_input_files_is_rejected_after_each_input_changes(self):
        for target in ('manifest', 'measurement', 'cmap'):
            with self.subTest(target=target):
                self.setUp()
                args = self.args()
                path = {'manifest': self.pm, 'measurement': self.pme, 'cmap': self.pc}[target]
                text = path.read_text()
                path.write_text(text + '\n ')   # whitespace-only change
                if target == 'measurement':
                    self.assertEqual(gate(self.receipt, *args)['status'], 'FAIL')   # file hash is bound
                else:
                    self.assertEqual(gate(self.receipt, *args)['status'], 'PASS')

    def test_gate_reports_failed_status_for_fail_and_na_receipts_that_are_genuine(self):
        self.na()
        args = self.args()
        produce(*args, self.receipt)
        out = gate(self.receipt, *args)
        self.assertEqual((out['status'], out['n_a_count']), ('N/A', 1))
        self.assertTrue(out['failures'])
        self.setUp()
        self.measurements['glyphs'][0]['hausdorff'] = 5
        args = self.args()
        produce(*args, self.receipt)
        out = gate(self.receipt, *args)
        self.assertEqual(out['status'], 'FAIL')
        self.assertTrue(out['failures'])

    def test_gate_never_returns_pass_when_inputs_are_invalid(self):
        self.cmap['codepoints'] = [65]
        out = gate(self.receipt, *self.args())
        self.assertEqual(out['status'], 'FAIL')


class V6CommandLine(Fixture):
    def run_cli(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, 'argv', ['vector_v2.py'] + argv), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                rc = v.main()
            except SystemExit as e:
                rc = e.code
        return rc, out.getvalue(), err.getvalue()

    def argv(self, action):
        m, me, c, r, d = self.args()
        return [action, '--manifest', str(m), '--measurements', str(me), '--cmap', str(c),
                '--reference', str(r), '--candidate', str(d), '--receipt', str(self.receipt)]

    def test_produce_pass_exit_zero_and_prints_json(self):
        rc, out, _ = self.run_cli(self.argv('produce'))
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)['status'], 'PASS')
        self.assertTrue(self.receipt.exists())

    def test_produce_fail_exit_one_when_not_all_pass(self):
        self.measurements['glyphs'][0]['hausdorff'] = 5
        rc, out, _ = self.run_cli(self.argv('produce'))
        self.assertEqual(rc, 1)
        self.assertEqual(json.loads(out)['status'], 'FAIL')

    def test_produce_na_exit_one_never_zero(self):
        self.na()
        rc, out, _ = self.run_cli(self.argv('produce'))
        self.assertEqual(rc, 1)
        self.assertEqual(json.loads(out)['status'], 'N/A')

    def test_produce_input_error_exit_two_and_message_on_stderr(self):
        self.cmap['codepoints'] = [65]
        rc, out, err = self.run_cli(self.argv('produce'))
        self.assertEqual(rc, 2)
        self.assertEqual(out, '')
        self.assertIn('input error: independent reference cmap mismatch', err)
        self.assertFalse(self.receipt.exists())

    def test_gate_pass_exit_zero(self):
        self.run_cli(self.argv('produce'))
        rc, out, _ = self.run_cli(self.argv('gate'))
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)['status'], 'PASS')

    def test_gate_tampered_receipt_exit_one(self):
        self.run_cli(self.argv('produce'))
        r = read(self.receipt)
        r['status'] = 'FAIL'
        self.receipt.write_text(json.dumps(r))
        rc, out, _ = self.run_cli(self.argv('gate'))
        self.assertEqual(rc, 1)
        self.assertEqual(json.loads(out)['status'], 'FAIL')

    def test_gate_input_problem_exits_one_with_fail_json_not_zero(self):
        self.run_cli(self.argv('produce'))
        self.cand.write_bytes(b'changed')
        rc, out, _ = self.run_cli(self.argv('gate'))
        self.assertEqual(rc, 1)
        self.assertEqual(json.loads(out)['status'], 'FAIL')

    def test_argparse_errors_exit_two(self):
        base = self.argv('produce')
        for argv in ([], ['bogus'], base[:-2], ['produce'], base + ['--unknown', 'x']):
            with self.subTest(argv=argv[:3]):
                rc, _, err = self.run_cli(argv)
                self.assertEqual(rc, 2)
                self.assertTrue(err)


if __name__ == '__main__':
    unittest.main()
