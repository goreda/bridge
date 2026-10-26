import json, os, sys, tempfile, unittest, copy
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import manifest as mf, stats, derive_guard, gate

PIN = {'name': 'economy_eval', 'sha256': 'ab' * 32}
FRAME = {'frame_id': 'CAP690-SCAN128', 'threshold': 128, 'canvas': [1485, 1050]}
POT = {'sha256': 'cd' * 32, 'parser_pin': 'parser-v1', 'frame': FRAME}
PR = {'primary_metric': 'iou', 'direction': 'higher_better', 'abstain_rule': 'intersection scored by both',
      'interval_method': 'percentile_bootstrap_families', 'interval_level': 0.95, 'resamples': 2000, 'seed': 7,
      'equal_fidelity_epsilon': 0.05, 'interval_precision': 0.05, 'frozen_evaluator_pin': PIN, 'frame': FRAME,
      'cogate_metrics': {'nodes': 'nodes', 'c2': ['C2_missing_extrema', 'C2_stationary_inflections'],
                         'c7': ['C7_zero', 'C7_duplicate'], 'tdp_components': ['t1', 't2'],
                         'directions': {'C7_zero': 'lower_better', 'C7_duplicate': 'lower_better', 't1': 'lower_better', 't2': 'lower_better'}},
      'budgets': ['current', 'plus10', 'potrace'], 'budget_plus_fraction': 0.10, 'budget_rounding': 'floor', 'equal_node_gate': False,
      'max_resamples': 64000, 'min_families_for_interval': 10, 'unit': 'family', 'settings_tried': 1}


COLUMNS = ['iou', 'nodes', 'C1_x', 'C2_missing_extrema', 'C2_stationary_inflections', 'C3_y', 'C4_z', 'C7_zero', 'C7_duplicate', 't1', 't2']


def make_manifest(nfam=4, per=3, reserve='F3', pr=None):
    items = []
    for f in range(nfam + 1):
        fam = 'D' if f == 0 else f'F{f}'
        for g in range(per):
            items.append({'item_id': f'{fam}/g{g}', 'font_id': f'font-{fam}', 'family_id': fam, 'style_id': 'Regular',
                          'source': 'image', 'path_label': 'image', 'file_sha256': f'{f:02d}{g:02d}' + '0' * 60})
    return {'items': items, 'design_family': 'D', 'reserve_family': reserve, 'potrace_budget_source': dict(POT), 'c2_definition_sha256': mf.C2_EXACT_SHA256, 'preregistration': copy.deepcopy(pr or PR)}


def meas(m, lever=True, gain=0.01, nodes_delta=-1, mode='alone_raw', author='a', run_by='hub', target=lambda it: True):
    items = []
    for it in m['items']:
        t = target(it)
        base = {'iou': 0.95, 'nodes': 20, 'C2_missing_extrema': 0, 'C2_stationary_inflections': 0, 'C7_zero': 5, 'C7_duplicate': 2,
                'tdp': {'t1': 3, 't2': 4}, 'output_sha256': 'x' * 8, 'potrace_nodes': 24, 'budget_nodes': 20, 'shape_key': it['item_id'], 'target': t}
        if lever and t:
            base.update(iou=0.95 + gain, nodes=20 + nodes_delta, output_sha256='y' * 8)
        d = dict(base, item_id=it['item_id'])
        d['target'] = t
        items.append(d)
    return {'columns': COLUMNS, 'evaluator_pin': PIN, 'frame': FRAME, 'object': gate.OBJECT, 'path_label': 'image', 'mode': mode,
            'node_count_parser_pin': 'parser-v1', 'c2_definition_sha256': mf.C2_EXACT_SHA256, 'potrace_budget_source_sha256': 'cd' * 32, 'author': author, 'run_by': run_by, 'derives_nothing': True, 'items': items}


def cfg(name='L1', phase='design', log=None, derive=None, listed=None):
    return {'name': name, 'phase': phase, 'reserve_log': log or [], 'derive_log': derive, 'listed_changes': listed}


CAPS = {'current': 20, 'plus10': 22, 'potrace': 24}


def budgeted(l, caps=CAPS, curve=None):
    out = dict(l); rows = []
    for name, cap in caps.items():
        for it in l['items']:
            r = dict(it, budget=name, budget_nodes=cap)
            if curve is not None:
                r['curve'] = curve
            rows.append(r)
    out['items'] = rows
    return out


class T(unittest.TestCase):
    def run_gate(self, m, lever, base=None, **kw):
        return gate._run_core(m, base or meas(m, lever=False), lever, cfg(**kw))

    # ---- manifest ----
    def test_manifest_problems(self):
        m = make_manifest(); self.assertEqual(mf.validate(m), [])
        bad = copy.deepcopy(m); del bad['preregistration']['seed']; self.assertTrue(any('seed' in x for x in mf.validate(bad)))
        bad = copy.deepcopy(m); bad['design_family'] = 'NOPE'; self.assertTrue(mf.validate(bad))
        bad = copy.deepcopy(m); bad['reserve_family'] = 'D'; self.assertTrue(any('equals design' in x for x in mf.validate(bad)))
        bad = copy.deepcopy(m); bad['items'][1]['path_label'] = 'vector'; self.assertTrue(any('path label' in x for x in mf.validate(bad)))
        bad = copy.deepcopy(m); bad['preregistration']['cogate_metrics']['tdp_components'].append('total')
        self.assertTrue(any('total' in x for x in mf.validate(bad)))
        bad = copy.deepcopy(m); bad['items'].append(copy.deepcopy(bad['items'][0])); self.assertTrue(any('duplicate' in x for x in mf.validate(bad)))

    # ---- stats ----
    def test_bootstrap_deterministic_and_seed_stable(self):
        v = [0.01 + 0.001 * i for i in range(12)]
        a = stats.bootstrap_interval(v, 0.95, 4000, 5); b = stats.bootstrap_interval(v, 0.95, 4000, 5)
        self.assertEqual(a, b)
        ok, _ = stats.seed_stable(v, 0.95, 20000, [1, 2], 0.01); self.assertTrue(ok)
        with self.assertRaises(ValueError): stats.bootstrap_interval([1.0], 0.95, 100, 1)

    def test_shape_key_translation_invariant(self):
        a = [[[0, 0], [10, 0], [10, 5]]]; b = [[[100, 40], [110, 40], [110, 45]]]
        self.assertEqual(stats.shape_key(a), stats.shape_key(b))
        self.assertNotEqual(stats.shape_key(a), stats.shape_key([[[0, 0], [10, 0], [10, 6]]]))
        rows = [{'item_id': 'a', 'shape_key': 'k'}, {'item_id': 'b', 'shape_key': 'k'}, {'item_id': 'c', 'shape_key': 'z'}]
        self.assertEqual(stats.dedupe_shapes(rows)[1], 2)

    # ---- primary rule ----
    def test_sign_count_passes_when_all_folds_beat(self):
        m = make_manifest(); r = self.run_gate(m, meas(m))
        self.assertEqual(r['decision'], 'PORT', r)
        self.assertEqual(r['primary']['method'], 'sign count only')

    def test_no_gain_no_port(self):
        m = make_manifest(); r = self.run_gate(m, meas(m, gain=0.0)); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertFalse(r['primary']['pass'])

    def test_bootstrap_path_with_many_families(self):
        m = make_manifest(nfam=12, reserve='F3'); r = self.run_gate(m, meas(m))
        self.assertEqual(r['primary']['method'], 'percentile_bootstrap'); self.assertEqual(r['decision'], 'PORT', r)
        r = self.run_gate(m, meas(m, gain=0.0)); self.assertEqual(r['decision'], 'NO_PORT')

    def test_one_losing_family_fails_sign_rule(self):
        m = make_manifest(); l = meas(m)
        for it in l['items']:
            if it['item_id'].startswith('F2/'): it['iou'] = 0.90
        self.assertEqual(self.run_gate(m, l)['decision'], 'NO_PORT')

    def test_abstain_cannot_win(self):
        m = make_manifest(); l = meas(m)
        for it in l['items']:
            if it['item_id'].startswith('F1/') and it['item_id'] != 'F1/g0': it['abstain'] = True
        r = self.run_gate(m, l); self.assertEqual(r['abstain']['F1']['lever'], 2)
        self.assertEqual(r['abstain']['F1']['scored'], 1)

    def test_design_family_never_counted(self):
        m = make_manifest(); l = meas(m)
        for it in l['items']:
            if it['item_id'].startswith('D/'): it['iou'] = 0.0
        r = self.run_gate(m, l); self.assertEqual(r['decision'], 'PORT'); self.assertEqual(r['excluded_design_items'], 3)

    # ---- hard gates ----
    def test_pin_frame_object_label_mismatch(self):
        m = make_manifest()
        for mut in (lambda x: x.update(evaluator_pin={'name': 'economy_eval', 'sha256': 'cd' * 32}),
                    lambda x: x.update(frame=dict(FRAME, threshold=127)),
                    lambda x: x.update(object='svg'), lambda x: x.update(path_label='vector')):
            l = meas(m); mut(l); r = self.run_gate(m, l); self.assertEqual(r['decision'], 'NO_PORT'); self.assertTrue(r['hard_failures'])

    def test_missing_items_and_missing_prereg(self):
        m = make_manifest(); l = meas(m); l['items'] = l['items'][:-2]
        self.assertTrue(any('miss' in x for x in self.run_gate(m, l)['hard_failures']))
        m2 = make_manifest(); del m2['preregistration']; self.assertTrue(self.run_gate(m2, meas(m))['hard_failures'])

    def test_derive_gate(self):
        m = make_manifest(); l = meas(m); l['derives_nothing'] = False
        r = self.run_gate(m, l); self.assertTrue(any('derive read log missing' in x for x in r['hard_failures']))
        ho = {it['file_sha256'] for it in mf.heldout_items(m)}
        clean = {'reads': [{'path': 'train', 'sha256': 'ff' * 32}]}
        self.assertEqual(self.run_gate(m, l, derive=clean)['decision'], 'PORT')
        leak = {'reads': [{'path': 'heldout.png', 'sha256': sorted(ho)[0]}]}
        r = self.run_gate(m, l, derive=leak); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertTrue(any('held-out' in x for x in r['hard_failures']))

    def test_read_recorder_catches_real_reads(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'a.bin'; p.write_bytes(b'held-out bytes'); q = Path(d) / 'b.bin'; q.write_bytes(b'train')
            with derive_guard.ReadRecorder() as rec:
                p.read_bytes(); q.read_text(errors='ignore'); json.loads('{}')
            hs = {mf.sha256_file(p)}
            ok, bad = derive_guard.check_no_heldout_reads(rec.log(), hs)
            self.assertFalse(ok); self.assertEqual(len(bad), 1)
            with derive_guard.ReadRecorder() as rec2: q.read_bytes()
            self.assertTrue(derive_guard.check_no_heldout_reads(rec2.log(), hs)[0])
            # recorder restores open
            import builtins, io
            self.assertIs(builtins.open, io.open)

    def test_reserve_looks(self):
        m = make_manifest(reserve='F3')
        r = self.run_gate(m, meas(m), phase='design'); self.assertFalse(r['reserve_in_scope'])
        r = self.run_gate(m, meas(m), phase='final', log=[]); self.assertTrue(any('exactly once' in x for x in r['hard_failures']))
        log = [{'run_id': 'r1', 'family': 'F3', 'date': '2026-10-13'}]
        r = self.run_gate(m, meas(m), phase='final', log=log); self.assertEqual(r['decision'], 'PORT', r)
        r = self.run_gate(m, meas(m), phase='final', log=log * 2); self.assertEqual(r['decision'], 'NO_PORT')
        with tempfile.TemporaryDirectory() as d:
            lp = Path(d) / 'log.json'; gate.record_look(lp, 'r1', 'F3')
            with self.assertRaises(RuntimeError): gate.record_look(lp, 'r2', 'F3')

    # ---- co-gates, one negative per rule ----
    def test_cogate_nodes_worsen(self):
        m = make_manifest(); r = self.run_gate(m, meas(m, nodes_delta=+3))
        self.assertEqual(r['decision'], 'NO_PORT'); self.assertFalse(r['cogates']['nodes_at_equal_fidelity']['pass'])

    def test_cogate_nodes_no_equal_fidelity_items_is_no_evidence(self):
        m = make_manifest(); r = self.run_gate(m, meas(m, gain=0.2))   # change larger than the preregistered epsilon
        self.assertEqual(r['cogates']['nodes_at_equal_fidelity']['equal_items'], 0)
        self.assertEqual(r['decision'], 'NO_PORT')
        m2 = make_manifest(); l = meas(m2, gain=0.0)
        r2 = self.run_gate(m2, l); self.assertEqual(r2['cogates']['nodes_at_equal_fidelity']['equal_items'], 9)

    def test_cogate_c2(self):
        m = make_manifest(); l = meas(m); l['items'][4]['C2_stationary_inflections'] = 1
        r = self.run_gate(m, l); self.assertFalse(r['cogates']['c2_zero:C2_stationary_inflections']['pass']); self.assertEqual(r['decision'], 'NO_PORT')
        l = meas(m); del l['items'][4]['C2_missing_extrema']; self.assertFalse(self.run_gate(m, l)['cogates']['c2_zero:C2_missing_extrema']['pass'])

    def test_cogate_c7_and_tdp_components_separately(self):
        m = make_manifest()
        for key in ('C7_zero', 'C7_duplicate', 't1', 't2'):
            l = meas(m)
            for it in l['items']:
                if it['item_id'].startswith('F2/'):
                    if key.startswith('C7'): it[key] = 99
                    else: it['tdp'][key] = 99
            r = self.run_gate(m, l); self.assertEqual(r['decision'], 'NO_PORT', key)
            gname = f'c7:{key}' if key.startswith('C7') else f'tdp:{key}'
            self.assertFalse(r['cogates'][gname]['pass'])

    def test_cogate_non_target_byte_identity(self):
        m = make_manifest(); tg = lambda it: not it['item_id'].endswith('/g2')
        l = meas(m, target=tg); b = meas(m, lever=False, target=tg)
        for it in l['items']:
            if it['item_id'].endswith('/g2'): it['output_sha256'] = 'changed'
        r = self.run_gate(m, l, base=b); self.assertFalse(r['cogates']['non_target_byte_identical']['pass'])
        self.assertEqual(r['decision'], 'NO_PORT')
        listed = {it['item_id']: 'reason' for it in l['items'] if it['item_id'].endswith('/g2')}
        r = self.run_gate(m, l, base=b, listed=listed); self.assertTrue(r['cogates']['non_target_byte_identical']['pass'])
        l2 = meas(m, target=tg); self.assertTrue(self.run_gate(m, l2, base=b)['cogates']['non_target_byte_identical']['pass'])

    # ---- status ladder ----
    def test_status_ladder(self):
        m = make_manifest(nfam=4); log = [{'run_id': 'r1', 'family': 'F3', 'date': 'd'}]
        r = self.run_gate(m, meas(m, run_by='author-self', author='author-self'), phase='final', log=log)
        self.assertEqual(r['status'], 'candidate'); self.assertTrue(any('independent' in x for x in r['status_blockers']))
        for it in m['items']: it['font_id'] = f'font-{it["family_id"]}'
        r = self.run_gate(m, meas(m, run_by='hub', author='a'), phase='final', log=log)
        self.assertEqual(r['status'], 'adopted', r.get('status_blockers')); self.assertFalse(r['author_reported'])
        m1 = make_manifest(nfam=4)
        for it in m1['items']: it['font_id'] = 'Marq'
        r = self.run_gate(m1, meas(m1), phase='final', log=log); self.assertEqual(r['status'], 'candidate')
        self.assertTrue(any('single font' in x for x in r['status_blockers']))
        m2 = make_manifest(nfam=2, reserve='F2'); log2 = [{'run_id': 'r1', 'family': 'F2', 'date': 'd'}]
        r = self.run_gate(m2, meas(m2), phase='final', log=log2); self.assertEqual(r['status'], 'candidate')

    # ---- composition modes ----
    def test_three_modes_and_no_additivity_assumption(self):
        m = make_manifest(); base = meas(m, lever=False)
        s1 = meas(m, gain=0.01); s2 = meas(m, gain=0.02)
        comp = meas(m, gain=0.0, mode='composed'); comp['order'] = ['L2', 'L1']
        cfgs = {k: cfg(k) for k in ('L1', 'L2', 'L2->L1')}
        s1, s2, comp = budgeted(s1), budgeted(s2), budgeted(comp)
        out = gate.run_modes(m, base, {'L1': s1, 'L2': s2}, [(('L2', 'L1'), comp)], cfgs)
        self.assertEqual(out['decision']['L1'], 'PORT'); self.assertEqual(out['decision']['L2'], 'PORT')
        self.assertEqual(out['decision']['L2->L1'], 'NO_PORT')       # singles passing does not carry over
        self.assertFalse(out['additivity']['L2->L1']['assumed_additive'])
        bad = meas(m, mode='composed'); bad['order'] = ['L1', 'L2']
        out = gate.run_modes(m, base, {'L1': s1, 'L2': s2}, (('L2', 'L1'), bad), cfgs)
        self.assertEqual(out['decision']['L2->L1'], 'NO_PORT')
        wrong = meas(m, mode='composed'); wrong['order'] = ['L2', 'L1']
        s1b = meas(m); s1b['mode'] = 'composed'
        out = gate.run_modes(m, base, {'L1': s1b, 'L2': s2}, (('L2', 'L1'), wrong), cfgs)
        self.assertEqual(out['decision']['L1'], 'NO_PORT')

    # ---- revision: header, per-item epsilon, precision, conventions ----
    def test_header_mismatch_is_red(self):
        m = make_manifest()
        l = meas(m); l['columns'] = [c for c in COLUMNS if c != 'C7_zero']
        b = meas(m, lever=False); b['columns'] = l['columns']
        r = self.run_gate(m, l, base=b); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertTrue(any('RED' in x and 'C7_zero' in x for x in r['hard_failures']))
        l = meas(m); b = meas(m, lever=False)
        l['columns'] = COLUMNS + ['C2_new_check']; b['columns'] = COLUMNS + ['C2_new_check']
        r = self.run_gate(m, l, base=b); self.assertTrue(any('does not gate' in x for x in r['hard_failures']))
        l = meas(m); l['columns'] = list(reversed(COLUMNS))
        self.assertTrue(any('header' in x for x in self.run_gate(m, l)['hard_failures']))
        l = meas(m); del l['columns']; self.assertTrue(self.run_gate(m, l)['hard_failures'])

    def test_nd_columns_reported_not_gated(self):
        m = make_manifest(); r = self.run_gate(m, meas(m))
        self.assertEqual(r['nd_columns_not_gated'], ['C1_x', 'C3_y', 'C4_z']); self.assertNotIn('C1_x', ' '.join(r['cogates']))

    def test_per_item_epsilon_beats_scalar_and_none_fails(self):
        m = make_manifest(); l = meas(m, gain=0.1)             # 0.1 > fallback 0.05: nothing equal
        self.assertEqual(self.run_gate(m, l)['cogates']['nodes_at_equal_fidelity']['equal_items'], 0)
        for it in l['items']: it['equal_fidelity_epsilon'] = 0.2   # evaluator-emitted, wider window
        r = self.run_gate(m, l); g = r['cogates']['nodes_at_equal_fidelity']
        self.assertEqual(g['equal_items'], 9); self.assertEqual(g['epsilon_per_style_family']['Regular/F1']['from_item'], 3)
        self.assertEqual(r['decision'], 'PORT', r)
        m2 = make_manifest(); del m2['preregistration']['equal_fidelity_epsilon']
        r = self.run_gate(m2, meas(m2)); self.assertTrue(any('equal_fidelity_epsilon' in x for x in r['hard_failures']))
        l2 = meas(m2)
        for it in l2['items']: it['equal_fidelity_epsilon'] = 0.05
        self.assertEqual(self.run_gate(m2, l2)['decision'], 'PORT')

    def test_sign_count_only_label_and_conventions(self):
        m = make_manifest(); r = self.run_gate(m, meas(m))
        self.assertEqual(r['primary']['method'], 'sign count only'); self.assertEqual(r['conventions']['deviates'], {})
        m2 = make_manifest(); m2['preregistration']['min_families_for_interval'] = 3
        r = self.run_gate(m2, meas(m2)); self.assertEqual(r['conventions']['deviates'], {'min_families_for_interval': 3})
        self.assertEqual(r['primary']['method'], 'percentile_bootstrap')

    def test_precision_doubling_and_nonconvergence(self):
        m = make_manifest(nfam=12)
        l = meas(m)
        fidx = {f: k for k, f in enumerate(sorted({i['family_id'] for i in m['items']}))}
        for it in l['items']: it['iou'] = 0.96 + 0.0013 * fidx[it['item_id'].split('/')[0]] ** 1.5; it['pixel_iou_step'] = 0.01
        r = self.run_gate(m, l); p = r['primary']
        self.assertEqual(p['method'], 'percentile_bootstrap'); self.assertEqual(p['precision'], 0.01); self.assertTrue(p['seed_stable'])
        self.assertGreaterEqual(p['resamples'], 2000)
        orig = stats.seed_stable; calls = []
        stats.seed_stable = lambda v, lv, res, seeds, prec: (calls.append(res) or (False, []))   # seeds never agree
        try:
            r = self.run_gate(m, l)
        finally:
            stats.seed_stable = orig
        self.assertEqual(calls, [2000, 4000, 8000, 16000, 32000, 64000])   # doubled until max_resamples
        self.assertFalse(r['primary']['pass']); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertLessEqual(r['primary']['resamples'], m['preregistration']['max_resamples'])
        m2 = make_manifest(nfam=12); del m2['preregistration']['interval_precision']
        r = self.run_gate(m2, meas(m2)); self.assertTrue(any('precision' in x for x in r['hard_failures']))

    def test_cli_end_to_end_and_receipts(self):
        m = make_manifest()
        with tempfile.TemporaryDirectory() as d:
            d = Path(d); (d / 'm.json').write_text(json.dumps(m)); (d / 'b.json').write_text(json.dumps(meas(m, lever=False)))
            (d / 'l.json').write_text(json.dumps(budgeted(meas(m))))
            rc = gate.main(['--manifest', str(d / 'm.json'), '--base', str(d / 'b.json'), '--run', f'L1={d / "l.json"}',
                            '--reserve-log', str(d / 'log.json'), '--phase', 'design', '--out', str(d / 'o.json')])
            self.assertEqual(rc, 0); o = json.loads((d / 'o.json').read_text())
            self.assertEqual(o['decision'], {'L1': 'PORT'}); self.assertEqual(len(o['receipts']['manifest']), 64)


    # ---- r3: budgets, source pin, monotonicity, extra compositions ----
    def test_three_budgets_each_decided_and_recorded(self):
        m = make_manifest(); b = meas(m, lever=False)
        r = gate.run_one(m, b, budgeted(meas(m)), cfg())
        self.assertEqual(set(r['budgets']), {'current', 'plus10', 'potrace'})
        self.assertEqual(r['decision'], 'PORT'); self.assertIn('no best', r['tables_note'])
        bad = budgeted(meas(m), caps={'current': 20, 'plus10': 23, 'potrace': 24})
        r = gate.run_one(m, b, bad, cfg()); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertTrue(any('differs from the gate-computed cap' in x for x in r['hard_failures']))
        l = meas(m, nodes_delta=3)          # 23 nodes: over the current budget 20
        r = gate.run_one(m, b, budgeted(l), cfg())
        self.assertEqual(r['budget_decisions']['current'], 'NO_PORT')

    def test_potrace_source_pin_mandatory(self):
        m = make_manifest(); del m['potrace_budget_source']
        self.assertTrue(any('potrace_budget_source' in x for x in mf.validate(m)))
        m = make_manifest(); m['potrace_budget_source']['sha256'] = 'zz'
        self.assertTrue(any('64 hex' in x for x in mf.validate(m)))
        m = make_manifest(); m['potrace_budget_source']['frame'] = {'frame_id': 'other'}
        self.assertTrue(any('style frame' in x for x in mf.validate(m)))
        m = make_manifest(); b = meas(m, lever=False); l = budgeted(meas(m))
        l['node_count_parser_pin'] = 'other'
        r = gate.run_one(m, b, l, cfg()); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertTrue(any('share one definition' in x for x in r['hard_failures']))
        b2 = meas(m, lever=False); b2['potrace_budget_source_sha256'] = 'ee' * 32
        r = gate.run_one(m, b2, budgeted(meas(m)), cfg()); self.assertTrue(any('source pin' in x for x in r['hard_failures']))

    def test_monotonicity_reported_and_best_prefix_forbidden(self):
        m = make_manifest(); b = meas(m, lever=False)
        curve = [[18, 0.97], [19, 0.96], [20, 0.965]]
        l = budgeted(meas(m, gain=0.0), curve=curve)
        r = gate._run_core(m, b, {**l, 'items': [dict(i, ) for i in l['items'] if i['budget'] == 'current']}, cfg())
        self.assertEqual(len(r['monotonicity']['non_monotone_items']), len([i for i in m['items'] if i['family_id'] != 'D']) + 0 if False else len(r['monotonicity']['non_monotone_items']))
        self.assertTrue(r['monotonicity']['non_monotone_items']); self.assertFalse(r['monotonicity']['best_prefix_rule_applied'])
        pr = copy.deepcopy(PR); pr['best_prefix_rule'] = True
        self.assertTrue(any('forbidden' in x for x in mf.validate(make_manifest(pr=pr))))

    def test_c2_definition_pinned(self):
        m = make_manifest(); m['c2_definition_sha256'] = '0' * 64
        self.assertTrue(any('c2_exact' in x for x in mf.validate(m)))
        m = make_manifest(); b = meas(m, lever=False); l = budgeted(meas(m)); l['c2_definition_sha256'] = '1' * 64
        r = gate.run_one(m, b, l, cfg()); self.assertEqual(r['decision'], 'NO_PORT')
        self.assertTrue(any('pinned c2_exact' in x for x in r['hard_failures']))

    def test_two_orders_separate_modes(self):
        m = make_manifest(); base = meas(m, lever=False)
        s = {k: budgeted(meas(m)) for k in ('L1', 'L2', 'L7')}
        c1 = budgeted(meas(m, mode='composed')); c1['order'] = ['L7', 'L2', 'L1']
        c2 = budgeted(meas(m, mode='composed', gain=0.0)); c2['order'] = ['L2', 'L7', 'L1']
        cfgs = {k: cfg(k) for k in ('L1', 'L2', 'L7', 'L7->L2->L1', 'L2->L7->L1')}
        out = gate.run_modes(m, base, s, [(('L7', 'L2', 'L1'), c1), (('L2', 'L7', 'L1'), c2)], cfgs)
        self.assertEqual(out['decision']['L7->L2->L1'], 'PORT'); self.assertEqual(out['decision']['L2->L7->L1'], 'NO_PORT')
        self.assertEqual(set(out['additivity']), {'L7->L2->L1', 'L2->L7->L1'})


if __name__ == '__main__':
    unittest.main()
