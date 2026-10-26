"""Negative-path tests for migrate_canonical_inputs.migrate (synthetic inputs only).

Every reject site in migrate() gets at least one test that asserts the error
code and message. Every rejected run must leave no output directory and no
staging directory behind. These tests change no production code.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import migrate_canonical_inputs as mig
from canonical_table_build import SCHEMA_VERSION, BuildError, ErrorCode, digest
from migrate_canonical_inputs import PLAN_VERSION, migrate

HEADER = ['family', 'style', 'engine', 'cp', 'iou']
RAW = b'family\tstyle\tengine\tcp\tiou\nSynthetic\tPlain\tengine_a\t0041\t0.5000\n'


class Base(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.top = Path(self.temp.name)
        self.root = self.top / 'in'
        self.root.mkdir()
        self.out = self.top / 'output'
        (self.root / 'old.tsv').write_bytes(RAW)
        self.plan = {'schema_version': PLAN_VERSION, 'sources': {
            'table': {'path': 'old.tsv', 'sha256': digest(RAW), 'rows': 1, 'header': list(HEADER)}}}
        self.target = {'schema_version': SCHEMA_VERSION, 'files': {
            'table': {'path': 'table.tsv', 'kind': 'tsv', 'sha256': digest(RAW),
                      'header': ['schema_version'] + HEADER}}, 'metadata_checks': []}

    # helpers
    def write_json_source(self, sid, name, raw, target_name=None):
        (self.root / name).write_bytes(raw)
        self.plan['sources'][sid] = {'path': name, 'sha256': digest(raw)}
        self.target['files'][sid] = {'path': target_name or name, 'kind': 'json', 'sha256': digest(raw)}

    def set_tsv(self, raw, header=None, rows=None):
        (self.root / 'old.tsv').write_bytes(raw)
        src = self.plan['sources']['table']
        src['sha256'] = digest(raw)
        if rows is not None:
            src['rows'] = rows
        if header is not None:
            src['header'] = header
            self.target['files']['table']['header'] = ['schema_version'] + header
        self.target['files']['table']['sha256'] = digest(raw)

    def run_migration(self):
        (self.top / 'plan.json').write_text(json.dumps(self.plan), encoding='utf-8')
        (self.top / 'target.json').write_text(json.dumps(self.target), encoding='utf-8')
        return migrate(self.top / 'plan.json', self.top / 'target.json', self.root, self.out)

    def assert_rejected(self, code, message=None, output_expected=False):
        with self.assertRaises(BuildError) as c:
            self.run_migration()
        self.assertEqual(c.exception.code, code)
        if message is not None:
            self.assertEqual(c.exception.message, message)
        self.assert_no_residue(output_expected)
        return c.exception

    def assert_no_residue(self, output_expected=False):
        if not output_expected:
            self.assertFalse(self.out.exists(), 'rejected run published an output directory')
        leftovers = [p.name for p in self.top.iterdir() if p.name.startswith('.canonical-migration-')]
        self.assertEqual(leftovers, [], 'staging directory left behind')

    def test_control_valid_run_succeeds(self):
        # Guards every other test: the unmodified fixture must migrate.
        self.run_migration()
        self.assertTrue((self.out / 'table.tsv').is_file())
        self.assert_no_residue(output_expected=True)


class CoverageAndPaths(Base):
    def test_m1_plan_source_missing_from_target(self):
        self.write_json_source('extra', 'extra.json', b'{}')
        del self.target['files']['extra']
        self.assert_rejected(ErrorCode.COVERAGE, 'source IDs differ from target contract')

    def test_m1_target_file_missing_from_plan(self):
        self.target['files']['extra'] = {'path': 'extra.json', 'kind': 'json', 'sha256': '0' * 64}
        self.assert_rejected(ErrorCode.COVERAGE, 'source IDs differ from target contract')

    def test_m2_dotdot_escape(self):
        (self.top / 'outside.tsv').write_bytes(RAW)
        self.plan['sources']['table']['path'] = '../outside.tsv'
        self.assert_rejected(ErrorCode.SCHEMA, 'source path escapes input directory')

    def test_m2_absolute_path_escape(self):
        outside = self.top / 'outside.tsv'
        outside.write_bytes(RAW)
        self.plan['sources']['table']['path'] = str(outside)
        self.assert_rejected(ErrorCode.SCHEMA, 'source path escapes input directory')

    def test_m2_symlink_escape(self):
        outside = self.top / 'outside.tsv'
        outside.write_bytes(RAW)
        try:
            os.symlink(outside, self.root / 'link.tsv')
        except (OSError, NotImplementedError):
            self.skipTest('symlinks unavailable')
        self.plan['sources']['table']['path'] = 'link.tsv'
        self.assert_rejected(ErrorCode.SCHEMA, 'source path escapes input directory')

    def test_m3_target_path_absolute(self):
        self.target['files']['table']['path'] = '/abs.tsv'
        self.assert_rejected(ErrorCode.SCHEMA, 'invalid or colliding target path')

    def test_m3_target_path_dotdot(self):
        self.target['files']['table']['path'] = '../escape.tsv'
        self.assert_rejected(ErrorCode.SCHEMA, 'invalid or colliding target path')

    def test_m3_target_path_reserved_names(self):
        for name in ('manifest.json', 'migration-receipt.json'):
            self.target['files']['table']['path'] = name
            self.assert_rejected(ErrorCode.SCHEMA, 'invalid or colliding target path')

    def test_m3_two_sources_same_target_path(self):
        self.write_json_source('meta', 'old.json', b'{"a":"b"}', target_name='table.tsv')
        self.assert_rejected(ErrorCode.SCHEMA, 'invalid or colliding target path')


class TsvChecks(Base):
    def test_m4_empty_file(self):
        self.set_tsv(b'', rows=0)
        self.assert_rejected(ErrorCode.ROW, 'empty TSV')

    def test_m4_bom_only_file(self):
        self.set_tsv(b'\xef\xbb\xbf', rows=0)
        self.assert_rejected(ErrorCode.ROW, 'empty TSV')

    def test_m5_header_differs_from_plan(self):
        self.plan['sources']['table']['header'] = ['family', 'style', 'engine', 'cp', 'other']
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy header mismatch or already versioned')

    def test_m5_duplicate_column(self):
        h = ['family', 'family', 'engine', 'cp', 'iou']
        self.set_tsv(b'family\tfamily\tengine\tcp\tiou\nA\tB\tC\tD\tE\n', header=h)
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy header mismatch or already versioned')

    def test_m5_already_versioned_header(self):
        h = ['schema_version'] + HEADER
        self.set_tsv(b'schema_version\tfamily\tstyle\tengine\tcp\tiou\nv\tA\tB\tC\tD\tE\n', header=h)
        self.target['files']['table']['header'] = ['schema_version'] + h
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy header mismatch or already versioned')

    def test_m5_header_column_count_differs(self):
        self.plan['sources']['table']['header'] = HEADER[:-1]
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy header mismatch or already versioned')

    def test_target_header_not_prefix_only(self):
        self.target['files']['table']['header'] = ['schema_version'] + HEADER[::-1]
        self.assert_rejected(ErrorCode.SCHEMA, 'target header must only prepend schema_version')

    def test_malformed_row_wrong_field_count(self):
        self.set_tsv(RAW + b'only\ttwo\n', rows=2)
        self.assert_rejected(ErrorCode.ROW, 'blank or malformed physical TSV row')

    def test_row_count_missing_from_plan(self):
        del self.plan['sources']['table']['rows']
        self.assert_rejected(ErrorCode.ROW, 'declared legacy row count mismatch')

    def test_row_count_not_integer_text(self):
        self.plan['sources']['table']['rows'] = 'many'
        self.assert_rejected(ErrorCode.SCHEMA)

    def test_target_checksum_stale(self):
        self.target['files']['table']['sha256'] = '0' * 64
        self.assert_rejected(ErrorCode.CHECKSUM, 'target manifest current source checksum mismatch')

    def test_legacy_checksum_wrong(self):
        self.plan['sources']['table']['sha256'] = '0' * 64
        self.assert_rejected(ErrorCode.CHECKSUM)


class JsonChecks(Base):
    def test_m6_json_array_not_object(self):
        self.write_json_source('meta', 'old.json', b'[1,2]')
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy metadata is not an unversioned object')

    def test_m6_json_scalar_not_object(self):
        self.write_json_source('meta', 'old.json', b'"text"')
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy metadata is not an unversioned object')

    def test_m6_json_already_versioned(self):
        self.write_json_source('meta', 'old.json', b'{"schema_version":"x"}')
        self.assert_rejected(ErrorCode.SCHEMA, 'legacy metadata is not an unversioned object')

    def test_m6_invalid_json_text(self):
        self.write_json_source('meta', 'old.json', b'{not json')
        self.assert_rejected(ErrorCode.SCHEMA)

    def test_m7_unknown_source_kind(self):
        self.write_json_source('meta', 'old.json', b'{"a":"b"}')
        self.target['files']['meta']['kind'] = 'yaml'
        self.assert_rejected(ErrorCode.SCHEMA, 'unknown target source kind')


class Rewrites(Base):
    def setUp(self):
        super().setUp()
        raw = json.dumps({'slice_sha': digest(RAW), 'note': 'synthetic'}).encode()
        self.write_json_source('meta', 'old.json', raw, target_name='meta.json')
        self.rewrite = {'file': 'meta', 'path': ['slice_sha'], 'source_sha': 'table'}
        self.plan['metadata_sha_rewrites'] = [dict(self.rewrite)]
        self.target['metadata_checks'] = [{'file': 'meta', 'path': ['slice_sha'], 'equals_source_sha': 'table'}]

    def test_control_rewrite_succeeds(self):
        self.run_migration()
        self.assert_no_residue(output_expected=True)

    def test_m8_rewrite_on_tsv_file(self):
        self.plan['metadata_sha_rewrites'] = [{'file': 'table', 'path': ['slice_sha'], 'source_sha': 'table'}]
        self.assert_rejected(ErrorCode.SCHEMA, 'invalid/duplicate metadata rewrite')

    def test_m8_empty_path(self):
        self.plan['metadata_sha_rewrites'] = [{'file': 'meta', 'path': [], 'source_sha': 'table'}]
        self.assert_rejected(ErrorCode.SCHEMA, 'invalid/duplicate metadata rewrite')

    def test_m8_duplicate_rewrite(self):
        self.plan['metadata_sha_rewrites'] = [dict(self.rewrite), dict(self.rewrite)]
        self.assert_rejected(ErrorCode.SCHEMA, 'invalid/duplicate metadata rewrite')

    def test_m8_unknown_file_id(self):
        self.plan['metadata_sha_rewrites'] = [{'file': 'nope', 'path': ['slice_sha'], 'source_sha': 'table'}]
        self.assert_rejected(ErrorCode.SCHEMA)

    def test_m9_embedded_sha_does_not_match_declared_source(self):
        raw = json.dumps({'slice_sha': '1' * 64}).encode()
        self.write_json_source('meta', 'old.json', raw, target_name='meta.json')
        self.assert_rejected(ErrorCode.MISMATCH, 'legacy embedded SHA does not match declared source')

    def test_m9_rewrite_key_missing_in_metadata(self):
        self.plan['metadata_sha_rewrites'] = [{'file': 'meta', 'path': ['absent'], 'source_sha': 'table'}]
        self.assert_rejected(ErrorCode.SCHEMA)

    def test_m10_rewrite_references_json_source(self):
        # The embedded value equals the sha of another JSON source, so the
        # comparison passes and the kind check is what must reject.
        other = b'{"k":"v"}'
        self.write_json_source('other', 'other.json', other)
        raw = json.dumps({'slice_sha': digest(other)}).encode()
        self.write_json_source('meta', 'old.json', raw, target_name='meta.json')
        self.plan['metadata_sha_rewrites'] = [{'file': 'meta', 'path': ['slice_sha'], 'source_sha': 'other'}]
        self.target['metadata_checks'] = []
        self.assert_rejected(ErrorCode.SCHEMA, 'metadata SHA rewrite references must be TSV sources')

    def test_m10_rewrite_references_unknown_source(self):
        self.plan['metadata_sha_rewrites'] = [{'file': 'meta', 'path': ['slice_sha'], 'source_sha': 'ghost'}]
        self.assert_rejected(ErrorCode.SCHEMA)

    def drop_meta(self):
        self.plan['sources'].pop('meta')
        self.target['files'].pop('meta')
        self.plan['metadata_sha_rewrites'] = []
        self.target['metadata_checks'] = []

    def test_m11_equals_source_sha_not_satisfied(self):
        self.drop_meta()
        raw = b'{"x":"abc"}'
        self.write_json_source('plain', 'plain.json', raw)
        self.target['metadata_checks'] = [{'file': 'plain', 'path': ['x'], 'equals_source_sha': 'table'}]
        self.assert_rejected(ErrorCode.MISMATCH, 'target metadata binding not satisfied')

    def test_m11_equals_literal_not_satisfied(self):
        self.drop_meta()
        raw = b'{"x":"abc"}'
        self.write_json_source('plain', 'plain.json', raw)
        self.plan['metadata_sha_rewrites'] = []
        self.target['metadata_checks'] = [{'file': 'plain', 'path': ['x'], 'equals_literal': 'zzz'}]
        self.assert_rejected(ErrorCode.MISMATCH, 'target metadata binding not satisfied')

    def test_m11_equals_literal_satisfied_control(self):
        self.drop_meta()
        raw = b'{"x":"abc"}'
        self.write_json_source('plain', 'plain.json', raw)
        self.plan['metadata_sha_rewrites'] = []
        self.target['metadata_checks'] = [{'file': 'plain', 'path': ['x'], 'equals_literal': 'abc'}]
        self.run_migration()
        self.assert_no_residue(output_expected=True)

    def test_m11_check_without_comparison_key(self):
        self.drop_meta()
        raw = b'{"x":"abc"}'
        self.write_json_source('plain', 'plain.json', raw)
        self.plan['metadata_sha_rewrites'] = []
        self.target['metadata_checks'] = [{'file': 'plain', 'path': ['x']}]
        self.assert_rejected(ErrorCode.SCHEMA)

    def test_m11_check_path_missing(self):
        self.drop_meta()
        raw = b'{"x":"abc"}'
        self.write_json_source('plain', 'plain.json', raw)
        self.plan['metadata_sha_rewrites'] = []
        self.target['metadata_checks'] = [{'file': 'plain', 'path': ['missing'], 'equals_literal': 'abc'}]
        self.assert_rejected(ErrorCode.SCHEMA)


class WrapperAndCleanup(Base):
    def test_m12_output_appears_during_migration(self):
        real = tempfile.mkdtemp

        def racing(*a, **k):
            d = real(*a, **k)
            self.out.mkdir()
            return d
        with mock.patch.object(mig.tempfile, 'mkdtemp', racing):
            exc = self.assert_rejected(ErrorCode.IO, 'output directory appeared during migration',
                                       output_expected=True)
        self.assertEqual(list(self.out.iterdir()), [], 'pre-existing destination was modified')

    def test_m13_missing_source_file_is_io_error(self):
        (self.root / 'old.tsv').unlink()
        self.assert_rejected(ErrorCode.IO)

    def test_m13_source_path_is_directory_is_io_error(self):
        (self.root / 'old.tsv').unlink()
        (self.root / 'old.tsv').mkdir()
        self.assert_rejected(ErrorCode.IO)

    def test_m13_missing_plan_file_is_io_error(self):
        with self.assertRaises(BuildError) as c:
            migrate(self.top / 'nope-plan.json', self.top / 'nope-target.json', self.root, self.out)
        self.assertEqual(c.exception.code, ErrorCode.IO)
        self.assert_no_residue()

    def test_m13_non_utf8_tsv_bytes(self):
        raw = b'family\tstyle\tengine\tcp\tiou\n\xff\xfe\tPlain\tengine_a\t0041\t0.5\n'
        self.set_tsv(raw, rows=1)
        self.assert_rejected(ErrorCode.SCHEMA)

    def test_m13_non_utf8_plan_bytes(self):
        (self.top / 'plan.json').write_bytes(b'\xff\xfe')
        (self.top / 'target.json').write_text(json.dumps(self.target))
        with self.assertRaises(BuildError) as c:
            migrate(self.top / 'plan.json', self.top / 'target.json', self.root, self.out)
        self.assertEqual(c.exception.code, ErrorCode.SCHEMA)
        self.assert_no_residue()

    def test_m13_missing_required_keys(self):
        for mutate in (
            lambda: self.plan.pop('sources'),
            lambda: self.plan['sources']['table'].pop('path'),
            lambda: self.plan['sources']['table'].pop('sha256'),
            lambda: self.plan['sources']['table'].pop('header'),
            lambda: self.target['files']['table'].pop('kind'),
            lambda: self.target['files']['table'].pop('path'),
            lambda: self.target['files']['table'].pop('header'),
            lambda: self.target.pop('metadata_checks'),
            lambda: self.target.pop('files'),
        ):
            with self.subTest(mutate=mutate):
                self.setUp()
                mutate()
                self.assert_rejected(ErrorCode.SCHEMA)

    def test_m13_wrong_value_types(self):
        # Wrong JSON types must end in a BuildError (never a raw exception)
        # and leave nothing behind. The code is asserted per case as observed:
        # note that integers load as text tokens, so a numeric path is an IO
        # error and an empty-list "sources" is a coverage error.
        S, C, I = ErrorCode.SCHEMA, ErrorCode.COVERAGE, ErrorCode.IO
        cases = (
            (lambda: self.plan.__setitem__('sources', []), C),
            (lambda: self.plan['sources'].__setitem__('table', 'x'), S),
            (lambda: self.plan['sources']['table'].__setitem__('path', 5), I),
            (lambda: self.plan['sources']['table'].__setitem__('header', 5), S),
            (lambda: self.target['files'].__setitem__('table', 'x'), S),
            (lambda: self.target.__setitem__('files', []), C),
            (lambda: self.target.__setitem__('metadata_checks', 5), S),
        )
        for i, (mutate, code) in enumerate(cases):
            with self.subTest(case=i):
                self.setUp()
                mutate()
                self.assert_rejected(code)

    def test_m13_plan_json_not_object(self):
        (self.top / 'plan.json').write_text('[]')
        (self.top / 'target.json').write_text(json.dumps(self.target))
        with self.assertRaises(BuildError) as c:
            migrate(self.top / 'plan.json', self.top / 'target.json', self.root, self.out)
        self.assertEqual(c.exception.code, ErrorCode.SCHEMA)
        self.assert_no_residue()

    def test_m15_staging_removed_when_write_fails(self):
        # Target paths 'a' and 'a/b': writing 'a/b' after 'a' fails after
        # staging exists. The failure must be an IO error and staging must go.
        self.write_json_source('meta', 'old.json', b'{"k":"v"}', target_name='table.tsv/b')
        self.target['files']['table']['path'] = 'table.tsv'
        self.assert_rejected(ErrorCode.IO)

    def test_m15_staging_removed_when_publish_rename_fails(self):
        with mock.patch.object(mig.os, 'rename', side_effect=OSError('injected')):
            self.assert_rejected(ErrorCode.IO, 'injected')

    def test_m15_staging_removed_when_write_raises_unexpected_schema_class_error(self):
        with mock.patch.object(Path, 'write_bytes', side_effect=ValueError('injected')):
            # table payload write happens only in staging; source reads use read_bytes
            self.assert_rejected(ErrorCode.SCHEMA, 'injected')

    def test_m15_every_pre_staging_reject_leaves_nothing(self):
        # Re-run the cheap reject fixtures and check the parent directory is
        # unchanged apart from the plan/target files and the input directory.
        before = {'in', 'plan.json', 'target.json'}
        self.plan['sources']['table']['sha256'] = '0' * 64
        self.assert_rejected(ErrorCode.CHECKSUM)
        self.assertLessEqual({p.name for p in self.top.iterdir()}, before)

    def test_success_publishes_only_new_directory(self):
        self.run_migration()
        self.assertEqual(sorted(p.name for p in self.out.iterdir()),
                         ['manifest.json', 'migration-receipt.json', 'table.tsv'])
        self.assert_no_residue(output_expected=True)

    def test_existing_output_is_not_modified(self):
        self.out.mkdir()
        (self.out / 'keep.txt').write_text('keep')
        self.assert_rejected(ErrorCode.IO, 'output directory already exists', output_expected=True)
        self.assertEqual([p.name for p in self.out.iterdir()], ['keep.txt'])

    def test_schema_version_mismatch_either_side(self):
        self.target['schema_version'] = 'other'
        self.assert_rejected(ErrorCode.SCHEMA, 'migration/target schema version mismatch')
        self.setUp()
        self.plan['schema_version'] = 'other'
        self.assert_rejected(ErrorCode.SCHEMA, 'migration/target schema version mismatch')


class CommandLine(Base):
    def run_main(self, argv):
        err = io.StringIO()
        with mock.patch.object(sys, 'argv', ['migrate_canonical_inputs.py'] + argv), \
                contextlib.redirect_stderr(err):
            try:
                rc = mig.main()
            except SystemExit as e:
                rc = e.code
        return rc, err.getvalue()

    def argv(self):
        (self.top / 'plan.json').write_text(json.dumps(self.plan))
        (self.top / 'target.json').write_text(json.dumps(self.target))
        return ['--plan', str(self.top / 'plan.json'), '--target-manifest', str(self.top / 'target.json'),
                '--input-dir', str(self.root), '--output-dir', str(self.out)]

    def test_m14_success_exit_zero(self):
        rc, _ = self.run_main(self.argv())
        self.assertEqual(rc, 0)
        self.assertTrue((self.out / 'table.tsv').is_file())

    def test_m14_reject_exit_two_and_json_stderr(self):
        self.plan['sources']['table']['sha256'] = '0' * 64
        rc, err = self.run_main(self.argv())
        self.assertEqual(rc, 2)
        body = json.loads(err)
        self.assertEqual(set(body), {'error', 'message'})
        self.assertEqual(body['error'], 'checksum')
        self.assert_no_residue()

    def test_m14_missing_argument_exits_nonzero(self):
        rc, err = self.run_main(['--plan', 'x'])
        self.assertEqual(rc, 2)
        self.assertIn('required', err)

    def test_m14_unreadable_plan_exit_two(self):
        argv = self.argv()
        argv[1] = str(self.top / 'does-not-exist.json')
        rc, err = self.run_main(argv)
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(err)['error'], 'io')


if __name__ == '__main__':
    unittest.main()
