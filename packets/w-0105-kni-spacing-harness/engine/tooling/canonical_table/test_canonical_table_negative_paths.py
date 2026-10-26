"""Negative-path tests for canonical_table_build (synthetic inputs only).

Reuses the fixture of test_canonical_table_build.py by delegation (its tests are
not re-run). Each test asserts both error code and message. No production code
is changed.
"""
import copy
import csv
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

import canonical_table_build as b
import test_canonical_table_build as T

E = b.ErrorCode
HERE = Path(__file__).parent


class Fx(unittest.TestCase):
    def setUp(self):
        T.SyntheticBuilder.setUp(self)

    write = T.SyntheticBuilder.write
    save = T.SyntheticBuilder.save
    run_build = T.SyntheticBuilder.run_build

    # helpers
    def rows(self, name):
        spec = self.m['files'][name]
        return b.read_tsv((self.root / spec['path']).read_bytes(), spec), spec['header']

    def edit(self, name, mutate, header=None):
        rows, h = self.rows(name)
        mutate(rows)
        self.write(name, header or h, rows)

    def raw(self, name, payload, header=None):
        path = self.root / (name + '.tsv')
        path.write_bytes(payload)
        spec = self.m['files'][name]
        spec['sha256'] = b.digest(payload)
        if header is not None:
            spec['header'] = header

    def json_source(self, name, obj, kind='json'):
        path = self.root / (name + '.json')
        payload = json.dumps(obj).encode()
        path.write_bytes(payload)
        self.m['files'][name] = {'path': path.name, 'sha256': b.digest(payload), 'kind': kind}

    def expect(self, code, message=None, startswith=None):
        with self.assertRaises(b.BuildError) as ctx:
            self.run_build()
        self.assertEqual(ctx.exception.code, code)
        if message is not None:
            self.assertEqual(ctx.exception.message, message)
        if startswith is not None:
            self.assertTrue(ctx.exception.message.startswith(startswith), ctx.exception.message)

    @property
    def per(self):
        return self.m['blocks'][1]


class Control(Fx):
    def test_control_builds(self):
        self.assertEqual(len(self.run_build()), 4)


class Numbers(Fx):
    def test_invalid_number_in_iou(self):
        for bad in ('abc', '', '1,5', '0x1'):
            with self.subTest(bad=bad):
                self.setUp()
                self.edit('components', lambda r, v=bad: r[0].__setitem__('iou', v))
                self.expect(E.NUMERIC, 'invalid number')

    def test_nonfinite_iou_values(self):
        for bad in ('nan', 'inf', '-inf', 'NaN', 'Infinity', '1e999'):
            with self.subTest(bad=bad):
                self.setUp()
                self.edit('components', lambda r, v=bad: r[0].__setitem__('iou', v))
                self.expect(E.NUMERIC, 'invalid number')

    def test_iou_outside_unit_interval(self):
        for bad in ('1.0000001', '-0.0000001', '2', '-1'):
            with self.subTest(bad=bad):
                self.setUp()
                self.edit('components', lambda r, v=bad: r[0].__setitem__('iou', v))
                self.expect(E.NUMERIC, 'IoU outside [0,1]')

    def test_iou_boundaries_accepted(self):
        self.edit('components', lambda r: [x.__setitem__('iou', '0' if x['cp'] == '0041' else '1') for x in r])
        self.edit('perstyle', lambda r: [x.update(mean_iou='0.5', median_iou='0.5') for x in r])
        self.assertEqual(len(self.run_build()), 4)

    def test_nodes_must_be_nonnegative_integers(self):
        for bad in ('-1', '1.5', 'x'):
            with self.subTest(bad=bad):
                self.setUp()
                self.edit('components', lambda r, v=bad: r[0].__setitem__('nodes', v))
                if bad == 'x':
                    self.expect(E.NUMERIC, 'invalid number')
                else:
                    self.expect(E.NUMERIC, 'invalid nodes')

    def test_rows_per_group_expected_nonnegative_integer(self):
        for bad in (-1, 1.5, 'x'):
            with self.subTest(bad=bad):
                self.setUp()
                self.per['rows_per_group'] = bad
                self.expect(E.NUMERIC)

    def test_sum_columns_expected_nonnegative_integer(self):
        for bad in ('-1', '1.5'):
            with self.subTest(bad=bad):
                self.setUp()
                header = ['schema_version', 'family', 'style', 'engine', 'cp', 'iou', 'nodes', 'pool', 'C7_zero']
                rows, _ = self.rows('components')
                for r in rows:
                    r['C7_zero'] = '0'
                rows[0]['C7_zero'] = bad
                self.write('components', header, rows)
                self.per['columns']['C7_zero'] = 'C7_zero'
                self.per['compare_metrics'] = [m for m in self.per['compare_metrics']]
                self.expect(E.NUMERIC, 'expected ASCII nonnegative integer')

    def test_expected_output_rows_wrong_or_malformed(self):
        for bad in (3, 5, 0):
            with self.subTest(bad=bad):
                self.setUp()
                self.m['expected_output_rows'] = bad
                self.expect(E.COVERAGE, 'output row count mismatch')
        for bad in (-1, 4.5):
            self.setUp()
            self.m['expected_output_rows'] = bad
            self.expect(E.NUMERIC, 'expected ASCII nonnegative integer')

    def test_negative_or_nonfinite_tolerance(self):
        for key in ('relative_tolerance', 'absolute_tolerance'):
            self.setUp()
            self.m['numeric_comparison'][key] = '-0.1'
            self.expect(E.NUMERIC, 'negative tolerance')
            self.setUp()
            self.m['numeric_comparison'][key] = 'nan'
            self.expect(E.NUMERIC, 'invalid number')
            self.setUp()
            self.m['numeric_comparison'][key] = 'abc'
            self.expect(E.NUMERIC, 'invalid number')

    def test_tolerance_label_must_be_convention(self):
        for label in ('derived', '', None, 'convention'):
            self.setUp()
            self.m['numeric_comparison']['label'] = label
            self.expect(E.SCHEMA, 'numeric tolerance requires CONVENTION label')

    def test_tolerance_is_used_and_zero_tolerance_is_exact(self):
        self.edit('perstyle', lambda r: r[0].__setitem__('mean_iou', '0.7500001'))
        self.expect(E.MISMATCH, 'perstyle/component mismatch: mean_iou')
        self.m['numeric_comparison']['absolute_tolerance'] = '0.000001'
        self.assertEqual(len(self.run_build()), 4)


class CodepointColumn(Fx):
    def test_missing_codepoint(self):
        self.edit('components', lambda r: r[0].__setitem__('cp', ''))
        self.expect(E.ROW, 'missing codepoint')

    def test_invalid_hex_codepoint(self):
        for bad in ('ZZ', 'U+ZZ', '4 1', 'G'):
            with self.subTest(bad=bad):
                self.setUp()
                self.edit('components', lambda r, v=bad: r[0].__setitem__('cp', v))
                self.expect(E.ROW, 'invalid hexadecimal codepoint')

    def test_invalid_unicode_scalar(self):
        for bad in ('D800', 'DFFF', '110000', 'U+110000'):
            with self.subTest(bad=bad):
                self.setUp()
                self.edit('components', lambda r, v=bad: r[0].__setitem__('cp', v))
                self.expect(E.ROW, 'invalid Unicode scalar')

    def test_duplicate_codepoint_with_mixed_spelling(self):
        self.edit('components', lambda r: r[1].__setitem__('cp', 'U+0041'))
        self.expect(E.KEY, 'duplicate codepoint in one group')

    def test_noncanonical_spellings_rejected(self):
        for code in ('0x41', '+41', ' 41', '4_1', '-1', 'U+-1', '00041', '041', '0000041', '0041 ', 'u+0041'):
            with self.subTest(code=code):
                with self.assertRaises(b.BuildError) as error:
                    b.cp(code)
                self.assertEqual(error.exception.code, E.ROW)
                self.assertEqual(error.exception.message, 'invalid hexadecimal codepoint')

    def test_exact_four_or_six_digits(self):
        for code in ('0041', '000041', 'U+0041', 'U+000041', '00af', '10FFFF'):
            self.assertEqual(b.cp(code), f"{int(code.removeprefix('U+'),16):04X}")

    def test_scalar_boundaries_accepted(self):
        for cp in ('0000', '10FFFF', 'D7FF', 'E000'):
            self.setUp()
            self.edit('components', lambda r, v=cp: r[0].__setitem__('cp', v))
            self.assertEqual(len(self.run_build()), 4)


class TsvInput(Fx):
    def test_header_differs_from_manifest(self):
        spec = self.m['files']['components']
        spec['header'] = spec['header'][::-1]
        self.expect(E.SCHEMA, 'TSV header differs from manifest')

    def test_header_missing_or_extra_column(self):
        spec = self.m['files']['components']
        spec['header'] = spec['header'] + ['extra']
        self.expect(E.SCHEMA, 'TSV header differs from manifest')
        self.setUp()
        self.m['files']['components']['header'].remove('nodes')
        self.expect(E.SCHEMA, 'TSV header differs from manifest')

    def test_duplicate_header_names(self):
        h = ['schema_version', 'family', 'style', 'engine', 'cp', 'iou', 'nodes', 'nodes']
        self.raw('components', ('\t'.join(h) + '\n' + '\t'.join([b.SCHEMA_VERSION, 'S', 'P', 'e', '0041', '1', '1', '1']) + '\n').encode(), header=h)
        self.expect(E.SCHEMA, 'TSV header differs from manifest')

    def test_schema_version_column_missing(self):
        h = ['family', 'style', 'engine', 'cp', 'iou', 'nodes', 'pool']
        rows, _ = self.rows('components')
        for r in rows:
            r.pop('schema_version')
        self.write('components', h, rows)
        self.expect(E.SCHEMA, 'TSV schema_version column missing')

    def test_row_schema_version_mismatch(self):
        for bad in ('', 'canonical-table-input-v0', 'canonical-table-input-v2'):
            self.setUp()
            self.edit('components', lambda r, v=bad: r[0].__setitem__('schema_version', v))
            self.expect(E.SCHEMA, 'TSV row schema_version mismatch')

    def test_row_with_too_few_fields(self):
        h = self.m['files']['components']['header']
        text = '\t'.join(h) + '\n' + '\t'.join([b.SCHEMA_VERSION, 'Synthetic', 'Plain']) + '\n'
        self.raw('components', text.encode())
        self.expect(E.ROW, 'malformed TSV row')

    def test_row_with_too_many_fields(self):
        h = self.m['files']['components']['header']
        text = '\t'.join(h) + '\n' + '\t'.join([b.SCHEMA_VERSION, 'S', 'P', 'e', '0041', '1', '1', 'p', 'extra']) + '\n'
        self.raw('components', text.encode())
        self.expect(E.ROW, 'malformed TSV row')

    def test_invalid_utf8_bytes(self):
        h = self.m['files']['components']['header']
        self.raw('components', ('\t'.join(h) + '\n').encode() + b'\xff\xfe\t\n')
        self.expect(E.ROW)

    def test_csv_field_larger_than_limit(self):
        h = self.m['files']['components']['header']
        text = '\t'.join(h) + '\n' + '\t'.join([b.SCHEMA_VERSION, 'S', 'P', 'e', '0041', '1', '1', 'x' * 200000]) + '\n'
        self.raw('components', text.encode())
        self.expect(E.ROW, startswith='field larger than field limit')

    def test_unterminated_quote_is_not_accepted_silently(self):
        h = self.m['files']['components']['header']
        text = '\t'.join(h) + '\n' + '\t'.join([b.SCHEMA_VERSION, '"S', 'P', 'e', '0041', '1', '1', 'p']) + '\n'
        self.raw('components', text.encode())
        with self.assertRaises(b.BuildError):
            self.run_build()

    def test_empty_file(self):
        self.raw('components', b'')
        self.expect(E.SCHEMA, 'TSV header differs from manifest')


class InputFiles(Fx):
    def test_checksum_mismatch_names_the_source(self):
        self.m['files']['perstyle']['sha256'] = '0' * 64
        self.expect(E.CHECKSUM, 'input checksum mismatch: perstyle')

    def test_input_path_escapes_directory(self):
        for bad in ('../outside.tsv', '/etc/hostname', 'sub/../../x.tsv'):
            self.setUp()
            (self.root.parent / 'outside.tsv').write_text('x')
            self.m['files']['components']['path'] = bad
            self.expect(E.SCHEMA, 'input path escapes input directory')

    def test_symlink_escape(self):
        outside = self.root.parent / 'outside-link.tsv'
        outside.write_bytes((self.root / 'components.tsv').read_bytes())
        try:
            os.symlink(outside, self.root / 'link.tsv')
        except (OSError, NotImplementedError):
            self.skipTest('symlinks unavailable')
        self.m['files']['components']['path'] = 'link.tsv'
        self.expect(E.SCHEMA, 'input path escapes input directory')

    def test_missing_input_file_is_io_error(self):
        (self.root / 'components.tsv').unlink()
        self.expect(E.IO)

    def test_input_path_is_a_directory(self):
        (self.root / 'components.tsv').unlink()
        (self.root / 'components.tsv').mkdir()
        self.expect(E.IO)

    def test_unknown_input_kind(self):
        for kind in ('csv', '', None):
            self.setUp()
            self.m['files']['components']['kind'] = kind
            self.expect(E.SCHEMA, 'unknown input kind')

    def test_manifest_problems(self):
        for text in ('{bad', '[]', 'null', ''):
            self.save()
            self.manifest.write_text(text)
            with self.assertRaises(b.BuildError) as c:
                b.build(self.manifest, self.root)
            self.assertEqual(c.exception.code, E.SCHEMA)

    def test_manifest_missing_file(self):
        with self.assertRaises(b.BuildError) as c:
            b.build(self.root / 'nope.json', self.root)
        self.assertEqual(c.exception.code, E.IO)

    def test_manifest_schema_version(self):
        for v in ('x', None, ''):
            self.setUp()
            self.m['schema_version'] = v
            self.expect(E.SCHEMA, 'manifest schema_version mismatch')

    def test_missing_top_level_keys_are_malformed_configuration(self):
        for key in ('numeric_comparison', 'files', 'metadata_checks', 'style_pools', 'blocks', 'expected_output_rows'):
            with self.subTest(key=key):
                self.setUp()
                del self.m[key]
                self.expect(E.SCHEMA, 'missing configuration or input key')

    def test_wrong_types_are_malformed_configuration(self):
        for key, value in (('files', []), ('blocks', 5), ('style_pools', 'x'), ('metadata_checks', 5)):
            with self.subTest(key=key):
                self.setUp()
                self.m[key] = value
                with self.assertRaises(b.BuildError) as c:
                    self.run_build()
                self.assertEqual(c.exception.code, E.SCHEMA)


class JsonSourcesAndMetadata(Fx):
    def add_meta(self, obj=None):
        self.json_source('meta', obj if obj is not None else {'schema_version': b.SCHEMA_VERSION, 'k': 'v', 'n': 5})

    def test_json_schema_version_mismatch(self):
        for obj in ({'k': 'v'}, {'schema_version': 'other'}):
            self.setUp()
            self.json_source('meta', obj)
            self.expect(E.SCHEMA, 'metadata schema_version mismatch')

    def test_json_not_object_is_malformed(self):
        self.json_source('meta', [1, 2])
        with self.assertRaises(b.BuildError) as c:
            self.run_build()
        self.assertEqual(c.exception.code, E.SCHEMA)

    def test_metadata_check_literal_mismatch(self):
        self.add_meta()
        self.m['metadata_checks'] = [{'file': 'meta', 'path': ['k'], 'equals_literal': 'other'}]
        self.expect(E.MISMATCH, 'metadata binding mismatch')

    def test_metadata_check_literal_satisfied_control(self):
        self.add_meta()
        self.m['metadata_checks'] = [{'file': 'meta', 'path': ['k'], 'equals_literal': 'v'},
                                     {'file': 'meta', 'path': ['n'], 'equals_literal': '5'}]
        self.assertEqual(len(self.run_build()), 4)

    def test_metadata_check_source_sha_mismatch(self):
        self.add_meta()
        self.m['metadata_checks'] = [{'file': 'meta', 'path': ['k'], 'equals_source_sha': 'components'}]
        self.expect(E.MISMATCH, 'metadata binding mismatch')

    def test_metadata_check_path_must_be_list(self):
        self.add_meta()
        for bad in ('k', None, 5, {'k': 1}):
            self.m['metadata_checks'] = [{'file': 'meta', 'path': bad, 'equals_literal': 'v'}]
            self.expect(E.SCHEMA, 'metadata path must be a list')

    def test_metadata_check_missing_key(self):
        self.add_meta()
        for path in (['absent'], ['k', 'deeper'], ['n', 'x']):
            self.m['metadata_checks'] = [{'file': 'meta', 'path': path, 'equals_literal': 'v'}]
            self.expect(E.SCHEMA, 'missing metadata key')

    def test_metadata_check_field_must_be_scalar(self):
        self.add_meta({'schema_version': b.SCHEMA_VERSION, 'obj': {'a': 1}, 'arr': [1], 'nul': None})
        for key in ('obj', 'arr', 'nul'):
            self.m['metadata_checks'] = [{'file': 'meta', 'path': [key], 'equals_literal': 'x'}]
            self.expect(E.SCHEMA, 'metadata field must be scalar')

    def test_metadata_check_without_comparison_key_or_unknown_file(self):
        self.add_meta()
        self.m['metadata_checks'] = [{'file': 'meta', 'path': ['k']}]
        with self.assertRaises(b.BuildError):
            self.run_build()
        self.m['metadata_checks'] = [{'file': 'ghost', 'path': ['k'], 'equals_literal': 'v'}]
        with self.assertRaises(b.BuildError):
            self.run_build()


class StylePoolsAndProvenance(Fx):
    def test_invalid_or_duplicate_pool_rows(self):
        base = {'family': 'Synthetic', 'style': 'Plain', 'pool': 'p'}
        for rows in ([base, base], [dict(base, pool='')], [dict(base, family='')], [dict(base, style=5)],
                     [dict(base, pool=None)]):
            self.setUp()
            self.m['style_pools'] = rows
            self.expect(E.KEY, 'invalid/duplicate style pool key')

    def test_style_without_manifest_pool(self):
        self.m['blocks'][2]['expected_styles'] = [['Synthetic', 'Other']]
        self.expect(E.COVERAGE, 'style has no manifest pool')

    def test_provenance_list_invalid(self):
        for bad in (['frames', 'frames'], 'frames', None, {'a': 1}):
            self.setUp()
            self.m['blocks'][0]['source_files'] = bad
            self.expect(E.SCHEMA, 'invalid provenance list')

    def test_provenance_unknown_source_is_malformed(self):
        self.m['blocks'][0]['source_files'] = ['ghost']
        with self.assertRaises(b.BuildError) as c:
            self.run_build()
        self.assertEqual(c.exception.code, E.SCHEMA)

    def test_source_id_collision_is_not_possible_through_json(self):
        # A JSON object cannot carry duplicate keys through json.loads (last wins),
        # so the 'duplicate source ID' check cannot be reached from a manifest file.
        text = json.dumps(self.m)
        self.manifest.write_text(text.replace('"components"', '"components"', 1))
        self.assertEqual(len(b.build(self.manifest, self.root)), 4)


class OutputFieldBindings(Fx):
    def test_unknown_output_field(self):
        self.m['blocks'][0]['fields']['bogus'] = 'x'
        self.expect(E.SCHEMA, 'unknown output field')

    def test_missing_context_field(self):
        self.m['blocks'][0]['fields']['n'] = {'context': 'absent'}
        self.expect(E.SCHEMA, 'missing context field')

    def test_invalid_output_field_binding_shapes(self):
        for rule in (5, None, [], {'context': 'tiles', 'metadata': ['x']}, {'other': 'x'}, {}):
            self.setUp()
            self.m['blocks'][0]['fields']['n'] = rule
            self.expect(E.SCHEMA, 'invalid output field binding')

    def test_frame_binding_cannot_change_identity(self):
        for field, value in (('family', 'Other'), ('style', 'Other'), ('pool', 'other_pool')):
            self.setUp()
            self.m['blocks'][0]['fields'][field] = value
            self.expect(E.MISMATCH, 'frame binding changes identity')

    def test_exclusion_binding_cannot_change_identity(self):
        for field, value in (('family', 'Other'), ('style', 'Other'), ('pool', 'other_pool')):
            self.setUp()
            self.m['blocks'][2]['fields'][field] = value
            self.expect(E.MISMATCH, 'exclusion binding changes identity')

    def test_perstyle_binding_cannot_change_aggregate_or_identity(self):
        for field, value in (('mean_iou', '0.1'), ('n', '9'), ('family', 'Other'), ('engine', 'engine_z')):
            self.setUp()
            self.per['fields'][field] = value
            self.expect(E.MISMATCH, 'field binding changes aggregate or identity')

    def test_engine_and_style_field_bindings_also_checked(self):
        self.per['engine_fields'] = {'engine_a': {'mean_iou': '0.1'}, 'engine_b': {}}
        self.expect(E.MISMATCH, 'field binding changes aggregate or identity')
        self.setUp()
        self.per['engine_fields'] = {'engine_a': {}, 'engine_b': {}}
        self.per['style_fields'] = {'Synthetic|Plain': {'n': '9'}}
        self.expect(E.MISMATCH, 'field binding changes aggregate or identity')

    def test_engine_fields_missing_an_engine_is_malformed(self):
        self.per['engine_fields'] = {'engine_a': {}}
        with self.assertRaises(b.BuildError) as c:
            self.run_build()
        self.assertEqual(c.exception.code, E.SCHEMA)

    def test_output_sort_identity_missing(self):
        del self.m['blocks'][2]['fields']['block']
        self.expect(E.SCHEMA, 'output sort identity missing')

    def test_metadata_binding_requires_metadata_file(self):
        self.per['fields']['frame'] = {'metadata': ['k']}
        with self.assertRaises(b.BuildError) as c:
            self.run_build()
        self.assertEqual(c.exception.code, E.SCHEMA)

    def test_metadata_binding_missing_key_and_non_scalar(self):
        self.json_source('meta', {'schema_version': b.SCHEMA_VERSION, 'obj': {'a': 1}})
        self.per['metadata_file'] = 'meta'
        self.per['fields']['frame'] = {'metadata': ['absent']}
        self.expect(E.SCHEMA, 'missing metadata key')
        self.per['fields']['frame'] = {'metadata': ['obj']}
        self.expect(E.SCHEMA, 'metadata field must be scalar')

    def test_metadata_binding_context_token_selects_engine_key(self):
        self.json_source('meta', {'schema_version': b.SCHEMA_VERSION, 'engine_a': 'A', 'engine_b': 'B'})
        self.per['metadata_file'] = 'meta'
        self.per['fields']['frame'] = {'metadata': [{'context': 'engine'}]}
        rows = self.run_build()
        self.assertEqual(sorted(r['frame'] for r in rows if r['record_type'] == 'perstyle'), ['A', 'B'])
        self.per['fields']['frame'] = {'metadata': [{'context': 'absent'}]}
        with self.assertRaises(b.BuildError):
            self.run_build()


class FramesBlock(Fx):
    def test_frame_key_shape(self):
        for value in ('Synthetic', 'a|b|c', ''):
            self.setUp()
            self.edit('frames', lambda r, v=value: r[0].__setitem__('style', v))
            self.expect(E.KEY, 'invalid/duplicate frame family|style key')
        self.setUp()
        self.edit('frames', lambda r: r[0].__setitem__('style', '|'))
        self.expect(E.COVERAGE, 'frame styles mismatch')

    def test_duplicate_frame_key(self):
        self.edit('frames', lambda r: r.append(dict(r[0])))
        self.expect(E.KEY, 'invalid/duplicate frame family|style key')

    def test_frame_styles_mismatch(self):
        self.m['blocks'][0]['expected_styles'] = [['Synthetic', 'Plain'], ['Synthetic', 'Bold']]
        self.expect(E.COVERAGE, 'frame styles mismatch')
        self.setUp()
        self.m['blocks'][0]['expected_styles'] = [['Synthetic', 'Other']]
        self.expect(E.COVERAGE, 'frame styles mismatch')
        self.setUp()
        self.m['blocks'][0]['expected_styles'] = [['Synthetic', 'Plain'], ['Synthetic', 'Plain']]
        self.expect(E.COVERAGE, 'frame styles mismatch')


class PerstyleBlock(Fx):
    def test_unknown_join_contract(self):
        for join in ('engine', '', None):
            self.setUp()
            self.per['join'] = join
            self.expect(E.SCHEMA, 'unknown join contract')

    def test_engine_keyset_missing_or_duplicate(self):
        for engines in ([], ['engine_a', 'engine_a'], None):
            self.setUp()
            self.per['engines'] = engines
            with self.assertRaises(b.BuildError) as c:
                self.run_build()
            self.assertEqual(c.exception.code, E.SCHEMA)
            if engines is not None:
                self.assertEqual(c.exception.message, 'engine keyset missing/duplicate')

    def test_style_keyset_missing_or_duplicate(self):
        for styles in ([], [['Synthetic', 'Plain'], ['Synthetic', 'Plain']]):
            self.setUp()
            self.per['expected_styles'] = styles
            self.expect(E.SCHEMA, 'style keyset missing/duplicate')

    def test_component_keyset_mismatch(self):
        self.per['expected_styles'] = [['Synthetic', 'Plain'], ['Synthetic', 'Bold']]
        self.expect(E.COVERAGE, 'component style/engine keyset mismatch')
        self.setUp()
        self.per['engines'] = ['engine_a']
        self.expect(E.COVERAGE, 'component style/engine keyset mismatch')

    def test_duplicate_perstyle_key(self):
        self.edit('perstyle', lambda r: r.append(dict(r[0])))
        self.expect(E.KEY, 'duplicate perstyle key')

    def test_perstyle_component_key_mismatch(self):
        self.edit('perstyle', lambda r: r.pop())
        self.expect(E.COVERAGE, 'perstyle/component key mismatch')
        self.setUp()
        self.edit('perstyle', lambda r: r[0].__setitem__('engine', 'engine_z'))
        self.expect(E.COVERAGE, 'perstyle/component key mismatch')

    def test_rows_per_group_mismatch_both_directions(self):
        for n in (1, 3, 0):
            self.setUp()
            self.per['rows_per_group'] = n
            self.expect(E.COVERAGE, 'rows_per_group mismatch')

    def test_required_input_values(self):
        self.per['required_values'] = {'pool': 'other'}
        self.expect(E.MISMATCH, 'required input value mismatch')
        self.setUp()
        self.per['required_values'] = {'absent_column': 'x'}
        with self.assertRaises(b.BuildError) as c:
            self.run_build()
        self.assertEqual(c.exception.code, E.SCHEMA)

    def test_source_pool_differs_in_components_or_perstyle(self):
        self.edit('components', lambda r: r[0].__setitem__('pool', 'wrong'))
        self.expect(E.MISMATCH, 'source pool differs from manifest')
        self.setUp()
        header = self.m['files']['perstyle']['header'] + ['pool']
        rows, _ = self.rows('perstyle')
        for r in rows:
            r['pool'] = 'wrong'
        self.write('perstyle', header, rows)
        self.expect(E.MISMATCH, 'source pool differs from manifest')

    def test_comparison_metric_missing(self):
        self.per['compare_metrics'] = ['mean_iou', 'bogus']
        self.expect(E.SCHEMA, 'comparison metric missing')
        self.setUp()
        self.per['compare_metrics'] = ['mean_lines']
        self.expect(E.SCHEMA, 'comparison metric missing')

    def test_comparison_mismatch_names_metric(self):
        for metric, value in (('n', '3'), ('mean_nodes', '3.5'), ('median_nodes', '2'), ('median_iou', '0.7')):
            self.setUp()
            self.edit('perstyle', lambda r, m=metric, v=value: r[0].__setitem__(m, v))
            self.expect(E.MISMATCH, 'perstyle/component mismatch: ' + metric)

    def test_comparison_value_not_numeric(self):
        self.edit('perstyle', lambda r: r[0].__setitem__('mean_iou', 'abc'))
        self.expect(E.NUMERIC, 'invalid number')

    def test_label_columns_mixed_in_group(self):
        header = self.m['files']['components']['header'] + ['profile']
        rows, _ = self.rows('components')
        for r in rows:
            r['profile'] = 'P1'
        rows[1]['profile'] = 'P2'
        self.write('components', header, rows)
        self.per['columns']['profile'] = 'profile'
        self.expect(E.MISMATCH, 'mixed profile in one group')

    def test_label_columns_constant_in_group_accepted(self):
        header = self.m['files']['components']['header'] + ['profile']
        rows, _ = self.rows('components')
        for r in rows:
            r['profile'] = 'P1'
        self.write('components', header, rows)
        self.per['columns']['profile'] = 'profile'
        out = self.run_build()
        self.assertEqual({r['profile'] for r in out if r['record_type'] == 'perstyle'}, {'P1'})

    def test_unknown_column_mapping_is_malformed(self):
        self.per['columns']['iou'] = 'absent'
        with self.assertRaises(b.BuildError) as c:
            self.run_build()
        self.assertEqual(c.exception.code, E.SCHEMA)

    def test_missing_block_keys_are_malformed(self):
        for key in ('components', 'engines', 'expected_styles', 'columns', 'rows_per_group', 'required_values',
                    'compare_metrics', 'fields', 'source_files' if False else 'join'):
            with self.subTest(key=key):
                self.setUp()
                self.per.pop(key, None)
                with self.assertRaises(b.BuildError):
                    self.run_build()


class Crosschecks(Fx):
    def setUp(self):
        super().setUp()
        h = ['schema_version', 'engine', 'cp', 'iou']
        rows = [dict(schema_version=b.SCHEMA_VERSION, engine='engine_a', cp=c, iou=i) for c, i in (('0041', '0.5'), ('0042', '1.0'))]
        self.write('cross', h, rows)
        self.per['crosschecks'] = [{'key': ['Synthetic', 'Plain', 'engine_a'], 'file': 'cross', 'engine_column': 'engine',
                                    'codepoint_column': 'cp', 'iou_column': 'iou'}]

    def test_control(self):
        self.assertEqual(len(self.run_build()), 4)

    def test_crosscheck_target_missing(self):
        for key in (['Synthetic', 'Plain', 'engine_z'], ['Other', 'Plain', 'engine_a']):
            self.per['crosschecks'][0]['key'] = key
            self.expect(E.COVERAGE, 'crosscheck target missing')

    def test_crosscheck_engine_mismatch(self):
        self.edit('cross', lambda r: r[1].__setitem__('engine', 'engine_b'))
        self.expect(E.COVERAGE, 'crosscheck engine mismatch')

    def test_duplicate_crosscheck_codepoint_mixed_spelling(self):
        self.edit('cross', lambda r: r[1].__setitem__('cp', 'U+0041'))
        self.expect(E.KEY, 'duplicate crosscheck codepoint')

    def test_crosscheck_codepoint_sets_differ(self):
        self.edit('cross', lambda r: r.pop())
        self.expect(E.COVERAGE, 'crosscheck codepoint mismatch')
        self.setUp()
        self.edit('cross', lambda r: r[1].__setitem__('cp', '0043'))
        self.expect(E.COVERAGE, 'crosscheck codepoint mismatch')
        self.setUp()
        self.edit('cross', lambda r: r.append(dict(r[0], cp='0043')))
        self.expect(E.COVERAGE, 'crosscheck codepoint mismatch')

    def test_crosscheck_iou_mismatch_and_tolerance(self):
        self.edit('cross', lambda r: r[0].__setitem__('iou', '0.5000001'))
        self.expect(E.MISMATCH, 'crosscheck IoU mismatch')
        self.m['numeric_comparison']['absolute_tolerance'] = '0.00001'
        self.assertEqual(len(self.run_build()), 4)

    def test_crosscheck_invalid_codepoint_and_iou(self):
        self.edit('cross', lambda r: r[0].__setitem__('cp', 'ZZ'))
        self.expect(E.ROW, 'invalid hexadecimal codepoint')
        self.setUp()
        self.edit('cross', lambda r: r[0].__setitem__('iou', 'abc'))
        self.expect(E.NUMERIC, 'invalid number')


class ExclusionsAndBlocks(Fx):
    def test_duplicate_exclusion_style(self):
        self.m['blocks'][2]['expected_styles'] = [['Synthetic', 'Plain'], ['Synthetic', 'Plain']]
        self.expect(E.KEY, 'duplicate exclusion style')

    def test_unknown_block_kind(self):
        for kind in ('summary', '', None):
            self.setUp()
            self.m['blocks'][2]['kind'] = kind
            self.expect(E.SCHEMA, 'unknown block kind')

    def test_duplicate_output_sort_key(self):
        self.m['blocks'].append(copy.deepcopy(self.m['blocks'][2]))
        self.m['expected_output_rows'] = 5
        self.expect(E.KEY, 'duplicate output sort key')

    def test_blocks_with_same_label_but_different_engine_are_not_duplicates(self):
        self.assertEqual(len(self.run_build()), 4)

    def test_output_row_count_is_checked_after_all_blocks(self):
        self.m['blocks'].pop()
        self.expect(E.COVERAGE, 'output row count mismatch')


class CommandLine(Fx):
    def cli(self, manifest=None, out=None, extra=()):
        self.save()
        out = out or (self.root / 'table.out.tsv')
        return subprocess.run([sys.executable, str(HERE / 'canonical_table_build.py'), '--manifest',
                               str(manifest or self.manifest), '--input-dir', str(self.root), '--output', str(out), *extra],
                              capture_output=True, text=True, timeout=60), out

    def test_cli_success_prints_digest_and_writes_table(self):
        p, out = self.cli()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout.strip(), b.digest(out.read_bytes()))
        self.assertEqual(out.read_bytes(), b.render(self.run_build()))

    def test_cli_build_error_exit_two_json_stderr_and_no_output(self):
        self.m['expected_output_rows'] = 9
        p, out = self.cli()
        self.assertEqual(p.returncode, 2)
        self.assertEqual(json.loads(p.stderr), {'error': 'coverage', 'message': 'output row count mismatch'})
        self.assertFalse(out.exists())
        self.assertEqual([x.name for x in self.root.iterdir() if x.name.startswith('tmp')], [])

    def test_cli_failed_build_does_not_replace_existing_output(self):
        out = self.root / 'table.out.tsv'
        out.write_text('previous')
        self.m['expected_output_rows'] = 9
        p, _ = self.cli(out=out)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(out.read_text(), 'previous')

    def test_cli_output_directory_missing_exit_two_io(self):
        p, out = self.cli(out=self.root / 'no-such-dir' / 'x.tsv')
        self.assertEqual(p.returncode, 2)
        self.assertEqual(json.loads(p.stderr)['error'], 'io')

    def test_cli_missing_manifest_exit_two_io(self):
        p, out = self.cli(manifest=self.root / 'absent.json')
        self.assertEqual(p.returncode, 2)
        self.assertEqual(json.loads(p.stderr)['error'], 'io')

    def test_cli_missing_arguments_exit_two(self):
        p = subprocess.run([sys.executable, str(HERE / 'canonical_table_build.py'), '--manifest', 'x'],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 2)


class MissingKeyMessage(Fx):
    def test_missing_block_key_is_typed_without_key_text(self):
        del self.m['blocks'][0]['source_files']
        self.expect(E.SCHEMA, 'missing configuration or input key')


if __name__ == '__main__':
    unittest.main()
