"""Negative-path tests for vector_receipt_producer (synthetic data only)."""
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

base = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('vector_receipt_producer', base / 'vector_receipt_producer.py')
vp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vp)
Err = vp.ReceiptInputError
HASH = 'a' * 64


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manifest = {'schema': 'kni.vector-input-manifest.v1', 'reference_font_sha256': HASH,
                         'codepoints': ['U+0041', 66]}
        self.measurements = {'schema': 'kni.vector-measurements.v1', 'reference_font_sha256': HASH, 'glyphs': [
            {'codepoint': 65, 'path_label': 'vector', 'symmetric_difference_area': 2.0, 'area_floor': 2.0,
             'hausdorff': 1.0, 'distance_floor': 1.0},
            {'codepoint': 'U+0042', 'path_label': 'vector', 'symmetric_difference_area': 0.0, 'area_floor': 1.5,
             'hausdorff': 0.5, 'distance_floor': 1.0}]}

    def build(self, cmap=None):
        return vp.build_receipt(self.manifest, self.measurements, cmap)

    def assertErr(self, needle, cmap=None):
        with self.assertRaises(Err) as c:
            self.build(cmap)
        self.assertIn(needle, str(c.exception))

    def write(self):
        m, me = self.root / 'manifest.json', self.root / 'measurements.json'
        m.write_text(json.dumps(self.manifest))
        me.write_text(json.dumps(self.measurements))
        return m, me


class Control(Base):
    def test_control_builds_pass_receipt(self):
        r = self.build({65, 66})
        self.assertEqual(r['status'], 'PASS')
        self.assertEqual([g['codepoint'] for g in r['glyphs']], [65, 66])


class CodepointParsing(Base):
    def test_invalid_codepoint_values(self):
        for bad in ('zz', 'U+zz', '', 'U+', -1, 0x110000, 'U+110000', None, True, 1.5, [], {}):
            with self.subTest(bad=repr(bad)):
                self.setUp()
                self.manifest['codepoints'] = [bad]
                with self.assertRaises(Err) as c:
                    self.build()
                self.assertIn('invalid codepoint', str(c.exception))

    def test_codepoint_function_boundaries(self):
        self.assertEqual(vp.codepoint(0), 0)
        self.assertEqual(vp.codepoint(0x10FFFF), 0x10FFFF)
        self.assertEqual(vp.codepoint('U+10FFFF'), 0x10FFFF)
        for bad in (0x110000, -1, 'U+110000', True, False):
            with self.assertRaises(Err):
                vp.codepoint(bad)

    def test_measurement_codepoint_invalid(self):
        self.measurements['glyphs'][0]['codepoint'] = 'xx'
        self.assertErr('invalid codepoint')


class ManifestChecks(Base):
    def test_manifest_fields(self):
        for mutate in (lambda m: m.pop('schema'), lambda m: m.pop('codepoints'),
                       lambda m: m.pop('reference_font_sha256'), lambda m: m.__setitem__('extra', 1)):
            self.setUp()
            mutate(self.manifest)
            self.assertErr('manifest fields do not match the input manifest schema')

    def test_manifest_not_a_dict(self):
        for value in ([], None, 'x', 5):
            with self.assertRaises(Err) as c:
                vp.build_receipt(value, self.measurements)
            self.assertIn('manifest fields do not match', str(c.exception))

    def test_manifest_schema(self):
        for value in ('kni.vector-input-manifest.v2', '', None):
            self.setUp()
            self.manifest['schema'] = value
            self.assertErr('unsupported input manifest schema')

    def test_reference_hash_format(self):
        for value in ('a' * 63, 'a' * 65, 'A' * 64, 'g' * 64, '', None, 5, ['a'] * 64):
            self.setUp()
            self.manifest['reference_font_sha256'] = value
            self.assertErr('reference_font_sha256 must be 64 lowercase hexadecimal characters')

    def test_codepoints_list(self):
        for value in ([], None, 'U+0041', {'a': 1}, 5):
            self.setUp()
            self.manifest['codepoints'] = value
            self.assertErr('manifest codepoints must be a non-empty list')

    def test_duplicate_manifest_codepoints_even_with_mixed_spelling(self):
        self.manifest['codepoints'] = ['U+0041', 65]
        self.assertErr('manifest contains duplicate codepoints')

    def test_measured_cmap_mismatch_each_direction(self):
        self.assertErr('do not exactly match the measured source cmap', {65})
        self.assertErr('do not exactly match the measured source cmap', {65, 66, 67})
        self.assertErr('do not exactly match the measured source cmap', set())

    def test_empty_measured_cmap_is_not_treated_as_absent(self):
        self.assertErr('do not exactly match the measured source cmap', set())
        self.assertEqual(self.build(None)['status'], 'PASS')


class MeasurementChecks(Base):
    def test_measurement_fields(self):
        for mutate in (lambda m: m.pop('schema'), lambda m: m.pop('glyphs'),
                       lambda m: m.pop('reference_font_sha256'), lambda m: m.__setitem__('extra', 1)):
            self.setUp()
            mutate(self.measurements)
            self.assertErr('measurement fields must be schema, reference_font_sha256, and glyphs')

    def test_measurement_not_a_dict(self):
        for value in ([], None, 'x'):
            with self.assertRaises(Err):
                vp.build_receipt(self.manifest, value)

    def test_measurement_schema(self):
        for value in ('kni.vector-measurements.v2', '', None):
            self.setUp()
            self.measurements['schema'] = value
            self.assertErr('unsupported vector measurements schema')

    def test_measurement_reference_hash_mismatch(self):
        self.measurements['reference_font_sha256'] = 'b' * 64
        self.assertErr('measurement reference font hash does not match the manifest')

    def test_glyphs_must_be_list(self):
        for value in (None, {}, 'x', 5):
            self.setUp()
            self.measurements['glyphs'] = value
            self.assertErr('measurement glyphs must be a list')

    def test_glyph_fields_exact(self):
        fields = list(self.measurements['glyphs'][0])
        for field in fields:
            self.setUp()
            self.measurements['glyphs'][0].pop(field)
            self.assertErr('each measurement glyph needs codepoint')
        self.setUp()
        self.measurements['glyphs'][0]['extra'] = 1
        self.assertErr('each measurement glyph needs codepoint')

    def test_glyph_row_not_a_dict(self):
        for value in (None, 5, 'x', []):
            self.setUp()
            self.measurements['glyphs'][0] = value
            self.assertErr('each measurement glyph needs codepoint')

    def test_duplicate_measurement_codepoint_mixed_spelling(self):
        self.measurements['glyphs'][1] = dict(self.measurements['glyphs'][0], codepoint='U+0041')
        self.assertErr('duplicate measurement codepoint U+0041')

    def test_path_label_must_be_vector(self):
        for value in ('image', '', None, 'Vector'):
            self.setUp()
            self.measurements['glyphs'][0]['path_label'] = value
            self.assertErr('measurement path_label must be vector')

    def test_metric_and_floor_values(self):
        for field in ('symmetric_difference_area', 'area_floor', 'hausdorff', 'distance_floor'):
            for bad, needle in ((True, 'must be numeric'), (False, 'must be numeric'), ('1', 'must be numeric'),
                                (None, 'must be numeric'), ([], 'must be numeric'),
                                (-0.5, 'finite and nonnegative'), (float('nan'), 'finite and nonnegative'),
                                (float('inf'), 'finite and nonnegative'), (float('-inf'), 'finite and nonnegative')):
                with self.subTest(field=field, bad=repr(bad)):
                    self.setUp()
                    self.measurements['glyphs'][0][field] = bad
                    self.assertErr(needle)

    def test_measurement_keyset_missing_and_extra_reported(self):
        self.measurements['glyphs'].pop()
        with self.assertRaises(Err) as c:
            self.build()
        self.assertIn('missing=[66]', str(c.exception))
        self.setUp()
        self.measurements['glyphs'].append(dict(self.measurements['glyphs'][0], codepoint=67))
        with self.assertRaises(Err) as c:
            self.build()
        self.assertIn('extra=[67]', str(c.exception))

    def test_failing_metric_is_recorded_not_raised(self):
        self.measurements['glyphs'][0]['hausdorff'] = 1.0000001
        r = self.build()
        self.assertEqual(r['status'], 'FAIL')
        self.assertEqual([row['pass'] for row in r['table_rows'] if row['codepoint'] == 65], [True, False])


class ProduceAndFiles(Base):
    def test_unreadable_inputs(self):
        m, me = self.write()
        out = self.root / 'out.json'
        for which in ('manifest', 'measurements'):
            self.write()
            (m if which == 'manifest' else me).write_text('{bad')
            with self.assertRaises(Err) as c:
                vp.produce(m, me, out)
            self.assertIn('is unreadable', str(c.exception))
            self.assertFalse(out.exists())
        (m).unlink()
        with self.assertRaises(Err):
            vp.produce(m, me, out)

    def test_non_utf8_input_is_not_misreported_as_success(self):
        m, me = self.write()
        m.write_bytes(b'\xff\xfe')
        out = self.root / 'out.json'
        with self.assertRaises(Exception):
            vp.produce(m, me, out)
        self.assertFalse(out.exists())

    def test_failed_produce_creates_no_output_and_keeps_existing(self):
        m, me = self.write()
        out = self.root / 'out.json'
        out.write_text('previous')
        self.measurements['glyphs'].pop()
        self.write()
        with self.assertRaises(Err):
            vp.produce(m, me, out)
        self.assertEqual(out.read_text(), 'previous')

    def test_produce_with_cmap_mismatch_writes_nothing(self):
        m, me = self.write()
        out = self.root / 'out.json'
        with self.assertRaises(Err):
            vp.produce(m, me, out, {65})
        self.assertFalse(out.exists())

    def test_produce_success_writes_sorted_json(self):
        m, me = self.write()
        out = self.root / 'out.json'
        r = vp.produce(m, me, out, {65, 66})
        self.assertEqual(json.loads(out.read_text()), r)
        self.assertTrue(out.read_text().endswith('\n'))


class CommandLine(Base):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(base / 'vector_receipt_producer.py'), *args],
                              capture_output=True, text=True, timeout=60)

    def cmd(self, cmap=None):
        m, me = self.write()
        out = self.root / 'out.json'
        a = ['--manifest', str(m), '--measurements', str(me), '--output', str(out)]
        if cmap is not None:
            c = self.root / 'cmap.json'
            c.write_text(json.dumps(cmap))
            a += ['--measured-cmap', str(c)]
        return a, out

    def test_cli_pass_exit_zero(self):
        a, out = self.cmd({'schema': 'kni.measured-cmap.v1', 'codepoints': [65, 'U+0042']})
        p = self.run_cli(*a)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout), {'status': 'PASS', 'glyph_count': 2, 'table_row_count': 4})
        self.assertTrue(out.exists())

    def test_cli_failing_metric_exit_one(self):
        self.measurements['glyphs'][0]['hausdorff'] = 9
        a, out = self.cmd()
        p = self.run_cli(*a)
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(p.stdout)['status'], 'FAIL')

    def test_cli_input_error_exit_two_and_no_output(self):
        self.measurements['glyphs'].pop()
        a, out = self.cmd()
        p = self.run_cli(*a)
        self.assertEqual(p.returncode, 2)
        self.assertIn('receipt input error:', p.stderr)
        self.assertFalse(out.exists())

    def test_cli_measured_cmap_schema_errors(self):
        for bad in ({'schema': 'kni.measured-cmap.v2', 'codepoints': [65, 66]},
                    {'schema': 'kni.measured-cmap.v1'},
                    {'schema': 'kni.measured-cmap.v1', 'codepoints': 'U+0041'},
                    [65, 66], "null"):
            with self.subTest(bad=bad):
                self.setUp()
                a, out = self.cmd(bad)
                p = self.run_cli(*a)
                self.assertEqual(p.returncode, 2)
                self.assertIn('measured cmap must use kni.measured-cmap.v1 and a codepoints list', p.stderr)
                self.assertFalse(out.exists())

    def test_cli_measured_cmap_codepoint_error_and_mismatch(self):
        a, out = self.cmd({'schema': 'kni.measured-cmap.v1', 'codepoints': ['zz']})
        self.assertEqual(self.run_cli(*a).returncode, 2)
        a, out = self.cmd({'schema': 'kni.measured-cmap.v1', 'codepoints': [65]})
        p = self.run_cli(*a)
        self.assertEqual(p.returncode, 2)
        self.assertIn('do not exactly match the measured source cmap', p.stderr)

    def test_cli_missing_measured_cmap_file_exit_two(self):
        a, out = self.cmd()
        p = self.run_cli(*a, '--measured-cmap', str(self.root / 'nope.json'))
        self.assertEqual(p.returncode, 2)
        self.assertIn('measured cmap is unreadable', p.stderr)

    def test_cli_missing_arguments_exit_two(self):
        self.assertEqual(self.run_cli('--manifest', 'x').returncode, 2)


if __name__ == '__main__':
    unittest.main()
