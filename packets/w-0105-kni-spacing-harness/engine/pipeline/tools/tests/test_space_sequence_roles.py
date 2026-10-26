"""Bounded synthetic ledger regressions. No collection files are changed."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

if len(sys.argv) < 2 or sys.argv[1].startswith('-'):
    raise SystemExit('UsageError: expected MODULE.py as the first argument; usage: python3 test_space_sequence_roles.py ../space_sequence_roles.py [unittest options]')
MODULE_PATH = Path(sys.argv.pop(1))
if MODULE_PATH.suffix != '.py' or not MODULE_PATH.is_file():
    raise SystemExit('UsageError: MODULE.py must be an existing Python source file')
spec = importlib.util.spec_from_file_location('space_sequence_roles', MODULE_PATH)
rolesmod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rolesmod)

class RolesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'Style/sidebearing').mkdir(parents=True)
        self.data = b'same-bytes'
        (self.root / 'Style/sidebearing/a.png').write_bytes(self.data)
        self.sha = hashlib.sha256(self.data).hexdigest()

    def events(self, ident, count, gid='glyph', path='Style/sidebearing/a.png', sha=None):
        sid = hashlib.md5(ident.encode()).hexdigest()
        return [dict(kind='send_intent', id=ident, send_id=sid,
                     controls_sanitized=[['text', 'H' + ' ' * count + 'H'], ['letter_spacing', 0], ['font_size', 100]],
                     controls_semantic_sha256='a' * 64),
                dict(kind='response', id=ident, send_id=sid, ok=True,
                     asset=dict(path=path, sha256=sha or self.sha), style_glyph_identity=gid)]

    def run_roles(self, rows, **limits):
        ledger = self.root / 'ledger.jsonl'
        ledger.write_text('\n'.join(json.dumps(row) for row in rows))
        return rolesmod.roles(str(self.root), 'Style', [str(ledger)],
                              limits.get('max_input_bytes', 4096), limits.get('max_working_bytes', 32768))

    def test_same_bytes_different_counts_refuse_both_orders(self):
        a, b = self.events('one', 1), self.events('two', 2)
        for rows in (a+b, b+a):
            with self.subTest(order=rows[0]['id']), self.assertRaisesRegex(SystemExit, 'ALIASED_TILES'):
                self.run_roles(rows)

    def test_gid_conflict_refuses_both_orders(self):
        a, b = self.events('one', 1, 'gid-one'), self.events('two', 1, 'gid-two')
        for rows in (a+b, b+a):
            with self.subTest(order=rows[0]['id']), self.assertRaisesRegex(SystemExit, 'AmbiguousGlyphIdentity'):
                self.run_roles(rows)

    def test_same_count_same_bytes_collapses_and_is_order_independent(self):
        a, b = self.events('one', 1), self.events('two', 1)
        first, second = self.run_roles(a+b), self.run_roles(b+a)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 1)
        self.assertEqual(first[0][6:8], ('one,two', 'glyph'))
        self.assertRegex(first[0][8], r'^[0-9a-f]{64}$')

    def test_missing_and_malformed_semantic_sha_are_typed(self):
        for value in (None, '', [], {}, 0, 'f'*63, 'G'*64):
            rows = self.events('one', 1)
            rows[0]['controls_semantic_sha256'] = value
            with self.subTest(value=value), self.assertRaisesRegex(SystemExit, 'InvalidSemanticSha256'):
                self.run_roles(rows)
        rows = self.events('one', 1)
        del rows[0]['controls_semantic_sha256']
        with self.assertRaisesRegex(SystemExit, 'InvalidSemanticSha256'):
            self.run_roles(rows)

    def test_distinct_counts_with_distinct_bytes_still_work(self):
        data = b'other-bytes'
        (self.root / 'Style/sidebearing/b.png').write_bytes(data)
        rows = self.events('one', 1) + self.events('two', 2, path='Style/sidebearing/b.png', sha=hashlib.sha256(data).hexdigest())
        self.assertEqual([row[0] for row in self.run_roles(rows)], [1, 2])

    def test_same_count_different_tiles_still_refuses(self):
        data = b'other-bytes'
        (self.root / 'Style/sidebearing/b.png').write_bytes(data)
        rows = self.events('one', 1) + self.events('two', 1, path='Style/sidebearing/b.png', sha=hashlib.sha256(data).hexdigest())
        with self.assertRaisesRegex(SystemExit, 'two different tiles for the same space count'):
            self.run_roles(rows)

    def test_budget_still_refuses_before_overread(self):
        with self.assertRaisesRegex(SystemExit, 'ResourceLimit'):
            self.run_roles(self.events('one', 1), max_input_bytes=len(self.data)-1)

    def test_sha_mismatch_still_refuses(self):
        with self.assertRaisesRegex(SystemExit, '!= ledger asset sha'):
            self.run_roles(self.events('one', 1, sha='0'*64))

    def test_send_id_mismatch_still_refuses(self):
        rows = self.events('one', 1)
        rows[1]['send_id'] = 'b'*32
        with self.assertRaisesRegex(SystemExit, 'no send_intent with the same id AND send_id'):
            self.run_roles(rows)

    def test_style_escape_still_refuses_before_ledger_read(self):
        with self.assertRaisesRegex(SystemExit, 'style_rel'):
            rolesmod.roles(str(self.root), '../escape', ['nonexistent'], 4096, 32768)

class BindingTests(unittest.TestCase):
    setUp = RolesTests.setUp
    events = RolesTests.events
    run_roles = RolesTests.run_roles
    def test_non_object_ledger_rows_are_typed(self):
        for value in (None, [], 'row', 7, True):
            with self.subTest(value=value), self.assertRaisesRegex(SystemExit, 'InvalidLedgerRow'):
                self.run_roles([value])

    def test_non_string_text_is_typed(self):
        for value in (None, [], {}, 7, True):
            rows = self.events('one', 1)
            rows[0]['controls_sanitized'][0][1] = value
            with self.subTest(value=value), self.assertRaisesRegex(SystemExit, 'ControlsConflict: text must be a string'):
                self.run_roles(rows)

    def test_cross_count_control_mutation_refuses(self):
        data = b'other-bytes'
        (self.root / 'Style/sidebearing/b.png').write_bytes(data)
        a = self.events('one', 1)
        b = self.events('two', 2, path='Style/sidebearing/b.png', sha=hashlib.sha256(data).hexdigest())
        b[0]['controls_sanitized'][1][1] = 3
        with self.assertRaisesRegex(SystemExit, 'ControlsConflict'):
            self.run_roles(a+b)

    def test_cross_count_gid_mutation_refuses(self):
        data = b'other-bytes'
        (self.root / 'Style/sidebearing/b.png').write_bytes(data)
        a = self.events('one', 1)
        b = self.events('two', 2, gid='other', path='Style/sidebearing/b.png', sha=hashlib.sha256(data).hexdigest())
        with self.assertRaisesRegex(SystemExit, 'ControlsConflict'):
            self.run_roles(a+b)

    def test_role_semantic_mutation_refuses(self):
        a, b = self.events('one', 1), self.events('two', 1)
        b[0]['controls_semantic_sha256'] = 'b'*64
        with self.assertRaisesRegex(SystemExit, 'ControlsConflict'):
            self.run_roles(a+b)

    def test_canonical_hash_matches_and_ignores_pair_order(self):
        a = self.events('one', 1)
        first = self.run_roles(a)
        controls = dict(a[0]['controls_sanitized'])
        canonical = json.dumps(controls, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)
        self.assertEqual(first[0][8], hashlib.sha256(canonical.encode()+self.sha.encode()).hexdigest())
        a[0]['controls_sanitized'].reverse()
        self.assertEqual(self.run_roles(a), first)

    def test_cross_count_semantic_hashes_may_differ(self):
        data = b'other-bytes'
        (self.root / 'Style/sidebearing/b.png').write_bytes(data)
        a = self.events('one', 1)
        b = self.events('two', 2, path='Style/sidebearing/b.png', sha=hashlib.sha256(data).hexdigest())
        b[0]['controls_semantic_sha256'] = 'b'*64
        self.assertEqual(len(self.run_roles(a+b)), 2)

if __name__ == '__main__':
    unittest.main(verbosity=2)
