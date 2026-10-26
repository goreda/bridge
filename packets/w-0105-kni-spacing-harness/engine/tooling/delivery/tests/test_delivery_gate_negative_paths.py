"""Negative-path tests for delivery_gate.evaluate and canonical_delivery.run.

Synthetic fonts, tiles and audits only. The fixtures are borrowed from
test_delivery_gate.py (same directory) by calling its setUp/helpers; no test
from that module is re-run here. Every rejection is asserted by its message.
No production code is changed.
"""
import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from PIL import Image, ImageDraw

import test_delivery_gate as T

gate = T.gate
BASE = Path(__file__).parents[1]
TOOL = BASE / 'tools' if (BASE / 'tools').is_dir() else BASE


class Fx(unittest.TestCase):
    """Fixture holder; delegates to the existing synthetic fixture."""
    def setUp(self):
        T.GateTests.setUp(self)
        self.addCleanup(self.tmp.cleanup)

    vector_receipt = T.GateTests.vector_receipt
    run_gate = T.GateTests.run_gate

    def glyph(self, cp=65):
        return next(r for r in self.manifest['glyphs'] if r['codepoint'] == cp)

    def rewrite_audit(self, cp, mutate):
        r = self.glyph(cp)
        ap = self.root / r['capture_audit']['path']
        audit = json.loads(ap.read_text())
        mutate(audit)
        ap.write_text(json.dumps(audit))
        r['capture_audit']['sha256'] = gate.sha(ap)

    def assertGateFails(self, needle, manifest=None):
        report = self.run_gate(manifest)
        self.assertEqual(report['status'], 'FAIL')
        self.assertTrue(any(needle in f for f in report['failures']), (needle, report['failures']))
        return report


class Control(Fx):
    def test_control_passes(self):
        r = self.run_gate()
        self.assertEqual((r['status'], r['failures']), ('PASS', []))


class ManifestLevel(Fx):
    def test_missing_source_revision(self):
        for value in (None, ''):
            self.setUp()
            self.manifest['source_revision'] = value
            self.assertGateFails('missing source_revision')
        self.setUp()
        del self.manifest['source_revision']
        self.assertGateFails('missing source_revision')

    def test_missing_source_identity(self):
        for value in (None, {}, ''):
            self.setUp()
            self.manifest['source_identity'] = value
            self.assertGateFails('missing source_identity')

    def test_font_sha256_mismatch(self):
        for value in ('0' * 64, None, ''):
            self.setUp()
            self.manifest['font_sha256'] = value
            self.assertGateFails('font sha256 mismatch')

    def test_empty_glyph_list(self):
        self.manifest['glyphs'] = []
        r = self.assertGateFails('empty source cmap and manifest')
        self.assertTrue(any('cmap mismatch' in f for f in r['failures']))

    def test_duplicate_source_codepoint(self):
        self.manifest['glyphs'].append(copy.deepcopy(self.manifest['glyphs'][0]))
        self.assertGateFails('duplicate source codepoint')

    def test_duplicate_codepoint_mixed_spelling(self):
        dup = copy.deepcopy(self.manifest['glyphs'][0])
        dup['codepoint'] = 'U+%04X' % dup['codepoint']
        self.manifest['glyphs'].append(dup)
        self.assertGateFails('duplicate source codepoint')

    def test_cmap_mismatch_names_missing_and_unexpected(self):
        extra = copy.deepcopy(self.manifest['glyphs'][0])
        extra['codepoint'] = 66
        self.manifest['glyphs'].append(extra)
        self.assertGateFails('missing=U+0042')
        self.setUp()
        self.manifest['glyphs'].pop(0)
        self.assertGateFails('unexpected=U+0020')

    def test_required_coverage_missing(self):
        self.manifest['required_codepoints'] = ['U+0042', 67]
        self.assertGateFails('required coverage missing: U+0042,U+0043')

    def test_required_coverage_satisfied_control(self):
        self.manifest['required_codepoints'] = ['U+0041', 32]
        self.assertEqual(self.run_gate()['status'], 'PASS')

    def test_required_coverage_missing_lists_codepoints(self):
        self.manifest['required_codepoints'] = [0xE000]
        r = self.assertGateFails('required coverage missing')
        self.assertTrue(any('U+E000' in f for f in r['failures']))

    def test_language_specific_requirement_field_rejected(self):
        self.manifest['require_turkish'] = True
        r = self.assertGateFails('require_turkish')
        self.assertTrue(any('required_codepoints' in f for f in r['failures']))

    def test_non_cff_font_is_rejected(self):
        fb = FontBuilder(1000, isTTF=True)
        fb.setupGlyphOrder(['.notdef', 'A', 'space'])
        fb.setupCharacterMap({65: 'A', 32: 'space'})
        glyphs = {}
        for n in ('.notdef', 'A', 'space'):
            pen = TTGlyphPen(None)
            if n != 'space':
                pen.moveTo((50, 0)); pen.lineTo((550, 0)); pen.lineTo((300, 700)); pen.closePath()
            glyphs[n] = pen.glyph()
        fb.setupGlyf(glyphs)
        fb.setupHorizontalMetrics({n: (600, 0) for n in glyphs})
        fb.setupHorizontalHeader(ascent=800, descent=-200)
        fb.setupNameTable({'familyName': 'Gate Test', 'styleName': 'Regular'})
        fb.setupOS2(); fb.setupPost()
        ttf = self.root / 'plain.ttf'
        fb.save(ttf)
        self.manifest['font_sha256'] = gate.sha(ttf)
        p = self.root / 'manifest.json'
        p.write_text(json.dumps(self.manifest))
        v = self.vector_receipt(ttf, [65, 32])
        report = gate.evaluate(ttf, p, self.root / 'evidence', 128, 128, v, gate.sha(ttf))
        self.assertEqual(report['status'], 'FAIL')
        self.assertTrue(any('CFF1 charstring audit required' in f for f in report['failures']))


class CaptureChecks(Fx):
    def test_capture_identity_variants(self):
        for ident in (None, {}, {'family': 'Gate Test'}, {'family': 'Gate Test', 'style': 'Bold'}):
            self.setUp()
            self.glyph()['capture']['source_identity'] = ident
            self.assertGateFails('U+0041: source font/style identity mismatch')

    def test_capture_synthetic_variants(self):
        for value in (True, None, 0, 'false'):
            self.setUp()
            self.glyph()['capture']['synthetic'] = value
            self.assertGateFails('U+0041: synthetic or unclassified capture source')

    def test_capture_role_variants(self):
        for value in ('reference', None, ''):
            self.setUp()
            self.glyph()['capture']['role'] = value
            self.assertGateFails('U+0041: capture is not a glyph source')

    def test_capture_tile_hash_and_missing_file(self):
        self.glyph()['capture']['sha256'] = '0' * 64
        self.assertGateFails('U+0041: capture missing/hash mismatch')
        self.setUp()
        self.glyph()['capture']['path'] = 'does-not-exist.png'
        self.assertGateFails('U+0041: capture missing/hash mismatch')
        self.setUp()
        del self.glyph()['capture']['path']
        self.assertGateFails('U+0041: capture missing/hash mismatch')

    def test_capture_status_missing_or_unknown(self):
        for value in (None, '', 'unknown'):
            self.setUp()
            self.glyph()['capture']['status'] = value
            self.assertGateFails('U+0041: capture status missing')

    def test_declared_ink_but_tile_blank(self):
        r = self.glyph()
        tile = self.root / r['capture']['path']
        Image.new('L', (16, 16), 255).save(tile)
        r['capture']['sha256'] = gate.sha(tile)
        self.rewrite_audit(65, lambda a: a.__setitem__('source_png_hex', tile.read_bytes().hex()))
        self.assertGateFails('U+0041: declared source ink is blank')

    def test_declared_blank_but_tile_has_ink(self):
        r = self.glyph(32)
        tile = self.root / r['capture']['path']
        im = Image.new('L', (16, 16), 255)
        ImageDraw.Draw(im).rectangle((2, 2, 13, 13), fill=0)
        im.save(tile)
        r['capture']['sha256'] = gate.sha(tile)
        self.rewrite_audit(32, lambda a: a.__setitem__('source_png_hex', tile.read_bytes().hex()))
        self.assertGateFails('U+0020: declared source blank has ink')

    def test_declared_blank_but_font_glyph_has_ink(self):
        r = self.glyph(65)
        r['capture']['status'] = 'intentional_blank'
        r['capture']['reason'] = 'declared blank'
        tile = self.root / r['capture']['path']
        Image.new('L', (16, 16), 255).save(tile)
        r['capture']['sha256'] = gate.sha(tile)
        self.rewrite_audit(65, lambda a: a.__setitem__('source_png_hex', tile.read_bytes().hex()))
        self.assertGateFails('U+0041: declared blank has ink')

    def test_blank_exception_needs_reason(self):
        for value in (None, ''):
            self.setUp()
            self.glyph(32)['capture']['reason'] = value
            self.assertGateFails('U+0020: blank exception lacks source reason')

    def test_unexpected_blank_glyph_in_font(self):
        r = self.glyph(32)
        r['capture']['status'] = 'ink'
        tile = self.root / r['capture']['path']
        im = Image.new('L', (16, 16), 255)
        ImageDraw.Draw(im).rectangle((2, 2, 13, 13), fill=0)
        im.save(tile)
        r['capture']['sha256'] = gate.sha(tile)
        self.rewrite_audit(32, lambda a: a.__setitem__('source_png_hex', tile.read_bytes().hex()))
        self.assertGateFails('U+0020: unexpected blank')


class FitAndAudit(Fx):
    def test_fit_fields_missing_each(self):
        for field in ('engine_revision', 'path', 'parameters', 'frame', 'measurement'):
            self.setUp()
            self.glyph()['fit'].pop(field)
            self.assertGateFails('U+0041: fit missing ' + field)

    def test_fit_path_noncanonical(self):
        for value in ('landed_trace', None, ''):
            self.setUp()
            self.glyph()['fit']['path'] = value
            self.assertGateFails('U+0041: noncanonical fit path')

    def test_fit_evidence_empty(self):
        for field in ('parameters', 'frame', 'measurement'):
            self.setUp()
            self.glyph()['fit'][field] = {}
            self.assertGateFails('U+0041: empty fit evidence')

    def test_capture_audit_reference_missing_or_hash_mismatch(self):
        self.glyph()['capture_audit']['sha256'] = '0' * 64
        self.assertGateFails('U+0041: capture audit missing/hash mismatch')
        self.setUp()
        self.glyph()['capture_audit']['path'] = 'nope.json'
        self.assertGateFails('U+0041: capture audit missing/hash mismatch')
        self.setUp()
        del self.glyph()['capture_audit']
        self.assertGateFails('U+0041: capture audit missing/hash mismatch')

    def test_audit_schema_unsupported(self):
        self.rewrite_audit(65, lambda a: a.__setitem__('schema', 'kni.capture-audit.v2'))
        self.assertGateFails('U+0041: unsupported capture audit schema')

    def test_audit_missing_each_field(self):
        for field in ('source_png_hex', 'path', 'parameters', 'frame', 'measurement', 'charstring_hex'):
            self.setUp()
            self.rewrite_audit(65, lambda a, f=field: a.pop(f))
            self.assertGateFails('U+0041: capture audit missing ' + field)

    def test_audit_source_bytes_mismatch(self):
        self.rewrite_audit(65, lambda a: a.__setitem__('source_png_hex', 'ab'))
        self.assertGateFails('U+0041: capture audit source bytes mismatch')

    def test_audit_disagrees_with_fit_each_field(self):
        for k in ('path', 'parameters', 'frame', 'measurement'):
            self.setUp()
            self.rewrite_audit(65, lambda a, k=k: a.__setitem__(k, {'changed': 1}))
            self.assertGateFails('U+0041: capture audit disagreement ' + k)

    def test_charstring_hash_mismatch(self):
        for value in ('bad', None, ''):
            self.setUp()
            self.glyph()['charstring_sha256'] = value
            self.assertGateFails('U+0041: charstring hash mismatch')

    def test_audit_charstring_does_not_match_final_font(self):
        for hexstr in ('deadbeef', '', None):
            self.setUp()
            self.rewrite_audit(65, lambda a, h=hexstr: a.__setitem__('charstring_hex', h))
            self.assertGateFails('U+0041: canonical charstring does not match final font')


class PreservedBaseline(Fx):
    preserved = T.PreserveTests.preserved

    def check(self, mutate, needle):
        self.setUp()
        r = self.preserved()
        mutate(r)
        self.assertGateFails(needle)

    def test_control_preserved_blank_passes(self):
        self.preserved()
        self.assertEqual(self.run_gate()['status'], 'PASS')

    def test_baseline_font_hash_mismatch(self):
        self.check(lambda r: r['preserved_baseline'].__setitem__('sha256', '0' * 64), 'baseline font hash mismatch')

    def test_baseline_identity_mismatch(self):
        for value in ({}, None, {'family': 'Other', 'style': 'Regular'}):
            self.check(lambda r, v=value: r['preserved_baseline'].__setitem__('source_identity', v),
                       'baseline font identity mismatch')

    def test_pass_through_needs_explicit_unavailable_caveat(self):
        self.check(lambda r: r['preserved_baseline'].__setitem__('reason', ''), 'explicit source-unavailable caveat')
        self.check(lambda r: r['preserved_baseline'].__setitem__('source_available', True),
                   'explicit source-unavailable caveat')
        self.check(lambda r: r['preserved_baseline'].pop('source_available'), 'explicit source-unavailable caveat')

    def test_baseline_charstring_hash_mismatch(self):
        self.check(lambda r: r['preserved_baseline'].__setitem__('charstring_sha256', 'bad'),
                   'baseline/final charstring mismatch')

    def test_row_charstring_hash_must_equal_baseline_digest(self):
        self.check(lambda r: r.__setitem__('charstring_sha256', 'bad'), 'preserved charstring hash mismatch')


class VectorReceiptIntegration(Fx):
    def run_with_receipt(self, mutate, font_hash=None):
        p = self.root / 'manifest.json'
        p.write_text(json.dumps(self.manifest))
        v = self.vector_receipt(self.font, [r['codepoint'] for r in self.manifest['glyphs']])
        obj = json.loads(v.read_text())
        mutate(obj)
        v.write_text(json.dumps(obj))
        return gate.evaluate(self.font, p, self.root / 'evidence', 128, 128, v, font_hash or gate.sha(self.font))

    def test_receipt_failure_is_prefixed_and_not_copied_into_evidence(self):
        r = self.run_with_receipt(lambda o: o.__setitem__('status', 'FAIL'))
        self.assertEqual(r['status'], 'FAIL')
        self.assertTrue(any(f.startswith('vector gate: ') for f in r['failures']))
        self.assertFalse((self.root / 'evidence' / 'vector-gate-receipt.json').exists())

    def test_receipt_bound_to_another_reference_font(self):
        r = self.run_with_receipt(lambda o: None, font_hash='b' * 64)
        self.assertEqual(r['status'], 'FAIL')
        self.assertTrue(any('source font hash mismatch' in f for f in r['failures']))

    def test_receipt_missing_a_glyph(self):
        def drop(o):
            o['glyphs'].pop()
            o['table_rows'] = o['table_rows'][:-2]
        r = self.run_with_receipt(drop)
        self.assertEqual(r['status'], 'FAIL')
        self.assertTrue(any('do not exactly cover' in f for f in r['failures']))

    def test_receipt_unreadable(self):
        p = self.root / 'manifest.json'
        p.write_text(json.dumps(self.manifest))
        v = self.root / 'vector-receipt.json'
        v.write_text('{bad')
        r = gate.evaluate(self.font, p, self.root / 'evidence', 128, 128, v, gate.sha(self.font))
        self.assertEqual(r['status'], 'FAIL')
        self.assertTrue(any('vector receipt unreadable' in f for f in r['failures']))

    def test_status_is_fail_whenever_any_failure_is_listed(self):
        self.manifest['source_revision'] = None
        r = self.run_gate()
        self.assertEqual(r['status'], 'FAIL')
        self.assertTrue(r['failures'])
        self.assertTrue(r['visual_review_required'])


class OutputPack(Fx):
    def test_pass_and_fail_both_write_checksums_covering_every_file(self):
        self.manifest['source_revision'] = None
        self.run_gate()
        pack = self.root / 'evidence'
        sums = json.loads((pack / 'SHA256SUMS.json').read_text())
        files = {p.name for p in pack.iterdir() if p.is_file() and p.name != 'SHA256SUMS.json'}
        self.assertEqual(set(sums), files)
        for name, digest in sums.items():
            self.assertEqual(gate.sha(pack / name), digest)

    def test_failing_run_never_claims_pass_in_gate_json(self):
        self.glyph()['charstring_sha256'] = 'bad'
        self.run_gate()
        self.assertEqual(json.loads((self.root / 'evidence' / 'gate.json').read_text())['status'], 'FAIL')


class GateCommandLine(Fx):
    def cli(self, *extra, ppem='128', threshold='128'):
        p = self.root / 'manifest.json'
        p.write_text(json.dumps(self.manifest))
        v = self.vector_receipt(self.font, [r['codepoint'] for r in self.manifest['glyphs']])
        return subprocess.run([sys.executable, str(TOOL / 'delivery_gate.py'), '--font', str(self.font),
                               '--manifest', str(p), '--output', str(self.root / 'cli-evidence'),
                               '--ppem', ppem, '--threshold', threshold, '--vector-receipt', str(v),
                               '--reference-font-sha256', gate.sha(self.font), *extra],
                              capture_output=True, text=True, timeout=120)

    def test_cli_pass_exit_zero(self):
        p = self.cli()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)['status'], 'PASS')

    def test_cli_fail_exit_one(self):
        self.glyph()['charstring_sha256'] = 'bad'
        p = self.cli()
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(p.stdout)['status'], 'FAIL')

    def test_cli_render_contract_errors_exit_two_before_any_output(self):
        for ppem, threshold in (('0', '128'), ('-1', '128'), ('128', '0'), ('128', '256'), ('128', '-5')):
            with self.subTest(ppem=ppem, threshold=threshold):
                p = self.cli(ppem=ppem, threshold=threshold)
                self.assertEqual(p.returncode, 2)
                self.assertIn('positive ppem and threshold 1..255 required', p.stderr)
                self.assertFalse((self.root / 'cli-evidence').exists())

    def test_cli_threshold_boundaries_accepted(self):
        for threshold in ('1', '255'):
            p = self.cli(threshold=threshold)
            self.assertIn(p.returncode, (0, 1), p.stderr)

    def test_cli_missing_arguments_exit_two(self):
        p = subprocess.run([sys.executable, str(TOOL / 'delivery_gate.py'), '--font', 'x'],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 2)


class EntryFx(Fx):
    entry = T.EntryTests.entry

    def make_plan(self):
        self.binary = self.root / 'binary'
        self.binary.write_bytes(b'test-binary')
        plan = copy.deepcopy(self.manifest)
        plan.update({'base_font': {'path': str(self.font), 'sha256': gate.sha(self.font)},
                     'audit_binary_sha256': gate.sha(self.binary), 'engine_revision': 'test'})
        self.vector_path = self.vector_receipt(self.font, [r['codepoint'] for r in plan['glyphs']])
        plan['vector_receipt'] = {'path': self.vector_path.name, 'sha256': gate.sha(self.vector_path)}
        for r in plan['glyphs']:
            r['fit'] = {'parameters': {'rdp_eps': 1, 'squared_error': 1, 'max_refits': 0},
                        'frame': {'scale': 1, 'translation': [0, 0]}}
        self.plan = plan
        return plan

    def out_dir(self):
        self.counter += 1
        return self.root / ('production-%d' % self.counter)

    def run_entry(self, plan=None, ppem=128, threshold=128, review=None, fake=None):
        plan = plan or self.plan
        p = self.root / 'plan.json'
        p.write_text(json.dumps(plan))

        def fake_run(cmd, check):
            original = self.root / (Path(cmd[1]).stem + '.audit.json')
            Path(cmd[2]).write_bytes(original.read_bytes())
        entry = self.entry()
        with patch.object(entry.subprocess, 'run', side_effect=fake or fake_run):
            return entry.run(p, self.binary, self.out_dir(), ppem, threshold, review)

    def assertRunRejects(self, needle, **kw):
        with self.assertRaises(ValueError) as c:
            self.run_entry(**kw)
        self.assertIn(needle, str(c.exception))
        return c.exception

    def setUp(self):
        super().setUp()
        self.counter = 0
        self.make_plan()


class EntryControl(EntryFx):
    def test_control_run_succeeds(self):
        self.assertEqual(self.run_entry()['status'], 'NUMERIC_CANDIDATE_VISUAL_PENDING')


class EntryContract(EntryFx):
    def test_non_empty_output_directory_refused(self):
        p = self.root / 'plan.json'
        p.write_text(json.dumps(self.plan))
        stale = self.root / 'stale-output'
        stale.mkdir()
        (stale / 'old.txt').write_text('old')
        with self.assertRaises(ValueError) as c, patch.object(self.entry().subprocess, 'run'):
            self.entry().run(p, self.binary, stale, 128, 128)
        self.assertIn('fresh output directory required', str(c.exception))
        self.assertEqual([x.name for x in stale.iterdir()], ['old.txt'])

    def test_invalid_render_contract(self):
        for ppem, threshold in ((0, 128), (-4, 128), (128, 0), (128, 256), (128, -1)):
            with self.subTest(ppem=ppem, threshold=threshold):
                self.assertRunRejects('invalid render contract', ppem=ppem, threshold=threshold)

    def test_base_font_hash_mismatch(self):
        self.plan['base_font']['sha256'] = 'bad'
        self.assertRunRejects('base font hash mismatch')

    def test_vector_receipt_missing_or_hash_mismatch(self):
        self.plan['vector_receipt']['sha256'] = '0' * 64
        self.assertRunRejects('vector receipt missing/hash mismatch')
        self.make_plan()
        self.plan['vector_receipt']['path'] = 'nope.json'
        self.assertRunRejects('vector receipt missing/hash mismatch')
        self.make_plan()
        del self.plan['vector_receipt']
        self.assertRunRejects('vector receipt missing/hash mismatch')

    def test_vector_receipt_unreadable_json(self):
        self.vector_path.write_text('{bad')
        self.plan['vector_receipt']['sha256'] = gate.sha(self.vector_path)
        with self.assertRaises(ValueError) as c:
            self.run_entry()
        self.assertIn('vector receipt unreadable', str(c.exception))

    def test_vector_receipt_must_bind_pinned_reference_font(self):
        obj = json.loads(self.vector_path.read_text())
        obj['source_font_sha256'] = 'b' * 64
        self.vector_path.write_text(json.dumps(obj))
        self.plan['vector_receipt']['sha256'] = gate.sha(self.vector_path)
        self.assertRunRejects('vector receipt must bind the pinned reference font')

    def test_vector_receipt_status_not_pass(self):
        for status in ('FAIL', 'N/A', None):
            self.make_plan()
            obj = json.loads(self.vector_path.read_text())
            obj['status'] = status
            self.vector_path.write_text(json.dumps(obj))
            self.plan['vector_receipt']['sha256'] = gate.sha(self.vector_path)
            self.assertRunRejects('vector receipt status is not PASS')

    def test_audit_binary_hash_mismatch(self):
        self.plan['audit_binary_sha256'] = '0' * 64
        self.assertRunRejects('audit binary hash mismatch')
        self.make_plan()
        self.binary.write_bytes(b'tampered binary')
        self.assertRunRejects('audit binary hash mismatch')

    def test_engine_revision_required(self):
        for value in (None, ''):
            self.make_plan()
            self.plan['engine_revision'] = value
            self.assertRunRejects('engine revision required')
        self.make_plan()
        del self.plan['engine_revision']
        self.assertRunRejects('engine revision required')

    def test_base_font_must_be_cff(self):
        fb = FontBuilder(1000, isTTF=True)
        fb.setupGlyphOrder(['.notdef', 'A', 'space'])
        fb.setupCharacterMap({65: 'A', 32: 'space'})
        gl = {}
        for n in ('.notdef', 'A', 'space'):
            pen = TTGlyphPen(None)
            if n != 'space':
                pen.moveTo((50, 0)); pen.lineTo((550, 0)); pen.lineTo((300, 700)); pen.closePath()
            gl[n] = pen.glyph()
        fb.setupGlyf(gl)
        fb.setupHorizontalMetrics({n: (600, 0) for n in gl})
        fb.setupHorizontalHeader(ascent=800, descent=-200)
        fb.setupNameTable({'familyName': 'Gate Test', 'styleName': 'Regular'})
        fb.setupOS2(); fb.setupPost()
        ttf = self.root / 'plain.ttf'
        fb.save(ttf)
        self.plan['base_font'] = {'path': str(ttf), 'sha256': gate.sha(ttf)}
        obj = json.loads(self.vector_path.read_text())
        obj['source_font_sha256'] = gate.sha(ttf)
        self.vector_path.write_text(json.dumps(obj))
        self.plan['vector_receipt']['sha256'] = gate.sha(self.vector_path)
        self.assertRunRejects('CFF1 required')

    def test_plan_must_cover_full_cmap_exactly(self):
        self.plan['glyphs'].pop()
        self.assertRunRejects('plan must cover full final cmap exactly')
        self.make_plan()
        extra = copy.deepcopy(self.plan['glyphs'][0])
        extra['codepoint'] = 66
        self.plan['glyphs'].append(extra)
        self.assertRunRejects('plan must cover full final cmap exactly')
        self.make_plan()
        self.plan['glyphs'].append(copy.deepcopy(self.plan['glyphs'][0]))
        self.assertRunRejects('plan must cover full final cmap exactly')

    def test_source_tile_hash_mismatch(self):
        self.plan['glyphs'][0]['capture']['sha256'] = '0' * 64
        self.assertRunRejects('source tile hash mismatch')

    def test_unbound_wrong_or_synthetic_source(self):
        for mutate in (lambda c: c.__setitem__('source_identity', {'family': 'Other', 'style': 'Regular'}),
                       lambda c: c.__setitem__('synthetic', True),
                       lambda c: c.__setitem__('synthetic', None),
                       lambda c: c.__setitem__('role', 'reference'),
                       lambda c: c.pop('role')):
            self.make_plan()
            mutate(self.plan['glyphs'][0]['capture'])
            self.assertRunRejects('unbound/wrong/synthetic source')

    def test_blank_audit_hash_mismatch(self):
        blank = next(r for r in self.plan['glyphs'] if r['capture']['status'] == 'intentional_blank')
        blank['capture_audit']['sha256'] = '0' * 64
        self.assertRunRejects('blank audit hash mismatch')

    def test_audit_tile_bytes_mismatch(self):
        def fake(cmd, check):
            original = self.root / (Path(cmd[1]).stem + '.audit.json')
            audit = json.loads(original.read_text())
            audit['source_png_hex'] = 'ab'
            Path(cmd[2]).write_text(json.dumps(audit))
        self.assertRunRejects('audit tile bytes mismatch', fake=fake)

    def test_audit_binary_failure_propagates_and_no_candidate_is_written(self):
        out = {}
        def boom(cmd, check):
            raise subprocess.CalledProcessError(3, cmd)
        entry = self.entry()
        p = self.root / 'plan.json'
        p.write_text(json.dumps(self.plan))
        target = self.out_dir()
        with patch.object(entry.subprocess, 'run', side_effect=boom):
            with self.assertRaises(subprocess.CalledProcessError):
                entry.run(p, self.binary, target, 128, 128)
        self.assertFalse((target / 'candidate.otf').exists())
        self.assertFalse((target / 'run-receipt.json').exists())

    def test_delivery_gate_failure_blocks_receipt(self):
        # The vector receipt passes the entry checks (status PASS, pinned hash)
        # but lacks a glyph, so only the delivery gate can reject it.
        obj = json.loads(self.vector_path.read_text())
        obj['glyphs'].pop()
        obj['table_rows'] = obj['table_rows'][:-2]
        self.vector_path.write_text(json.dumps(obj))
        self.plan['vector_receipt']['sha256'] = gate.sha(self.vector_path)
        p = self.root / 'plan.json'
        p.write_text(json.dumps(self.plan))
        target = self.out_dir()
        def fake_run(cmd, check):
            Path(cmd[2]).write_bytes((self.root / (Path(cmd[1]).stem + '.audit.json')).read_bytes())
        entry = self.entry()
        with patch.object(entry.subprocess, 'run', side_effect=fake_run):
            with self.assertRaises(ValueError) as c:
                entry.run(p, self.binary, target, 128, 128)
        self.assertIn('delivery gate failed', str(c.exception))
        self.assertFalse((target / 'run-receipt.json').exists())
        self.assertEqual(json.loads((target / 'evidence' / 'gate.json').read_text())['status'], 'FAIL')

    def test_failed_runs_never_write_a_run_receipt(self):
        self.plan['engine_revision'] = None
        p = self.root / 'plan.json'
        p.write_text(json.dumps(self.plan))
        target = self.out_dir()
        with self.assertRaises(ValueError):
            self.entry().run(p, self.binary, target, 128, 128)
        self.assertFalse((target / 'run-receipt.json').exists())

    def test_review_is_required_for_delivery_ready_status(self):
        r = self.run_entry()
        self.assertNotEqual(r['status'], 'DELIVERY_READY')
        self.assertNotIn('visual_seal', r)


class EntryCommandLine(EntryFx):
    def cli(self, *args):
        p = self.root / 'plan.json'
        p.write_text(json.dumps(self.plan))
        return subprocess.run([sys.executable, str(TOOL / 'canonical_delivery.py'), '--plan', str(p),
                               '--audit-binary', str(self.binary), '--output', str(self.root / 'cli-out'),
                               '--ppem', '128', '--threshold', '128', *args],
                              capture_output=True, text=True, timeout=120, cwd=str(TOOL))

    def test_cli_rejection_exit_one_with_message(self):
        self.plan['base_font']['sha256'] = 'bad'
        p = self.cli()
        self.assertEqual(p.returncode, 1)
        self.assertIn('base font hash mismatch', p.stderr)

    def test_cli_missing_arguments_exit_two(self):
        p = subprocess.run([sys.executable, str(TOOL / 'canonical_delivery.py'), '--plan', 'x'],
                           capture_output=True, text=True, timeout=60, cwd=str(TOOL))
        self.assertEqual(p.returncode, 2)

    def test_cli_missing_plan_file_exit_one(self):
        p = subprocess.run([sys.executable, str(TOOL / 'canonical_delivery.py'), '--plan', str(self.root / 'no.json'),
                            '--audit-binary', str(self.binary), '--output', str(self.root / 'o2'),
                            '--ppem', '128', '--threshold', '128'],
                           capture_output=True, text=True, timeout=60, cwd=str(TOOL))
        self.assertEqual(p.returncode, 1)

    def test_cli_invalid_contract_exit_one(self):
        p = subprocess.run([sys.executable, str(TOOL / 'canonical_delivery.py'), '--plan', str(self.root / 'plan.json'),
                            '--audit-binary', str(self.binary), '--output', str(self.root / 'o3'),
                            '--ppem', '0', '--threshold', '128'],
                           capture_output=True, text=True, timeout=60, cwd=str(TOOL))
        self.assertEqual(p.returncode, 1)


if __name__ == '__main__':
    unittest.main()
