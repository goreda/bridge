#!/usr/bin/env python3
"""Lever gate runner (holdout protocol v3). Single runner: lever authors call it, never change it.
The gate NEVER computes IoU, nodes, C2, C7 or TDP. It consumes measurements emitted by the frozen,
hash-pinned evaluator on decoded integer CFF and does paired statistics, co-gates and hard gates only.
Everything is fail closed: unverifiable input is a failure, not a default."""
import argparse, json, sys, datetime
from pathlib import Path
import numpy as np
import manifest as mf
import stats
import derive_guard

OBJECT = 'decoded_integer_cff'
# Conventions (not derived from data): reported in every result, deviations flagged.
CONVENTIONS = {'min_families_for_interval': 10, 'interval_level': 0.95}


def _sha(path):
    return mf.sha256_file(path)


# ---------- final reserve look log (protocol 4a.2) ----------
def record_look(log_path, run_id, family, date=None):
    """Append one look at the reserve family. A second look is refused."""
    p = Path(log_path)
    log = json.loads(p.read_text()) if p.exists() else []
    if any(e['family'] == family for e in log):
        raise RuntimeError(f'reserve family {family} was already looked at: {log}')
    log.append({'run_id': run_id, 'family': family, 'date': date or datetime.date.today().isoformat()})
    p.write_text(json.dumps(log, indent=2) + '\n')
    return log


def reserve_count(log, family):
    return sum(1 for e in log if e.get('family') == family)


# ---------- helpers ----------
def _same_pin(a, b):
    return isinstance(a, dict) and a == b and all(a.get(k) for k in ('name', 'sha256'))


def _hard_pins(pr, meta_by_name, items_by_name, problems):
    pin = pr['frozen_evaluator_pin']
    for name, m in meta_by_name.items():
        if not _same_pin(m.get('evaluator_pin'), pin):
            problems.append(f'{name}: evaluator_pin differs from the pre-registered frozen pin')
        if m.get('frame') != pr['frame']:
            problems.append(f'{name}: frame differs from the pre-registered frame')
        if m.get('object') != OBJECT:
            problems.append(f'{name}: measurement object is {m.get("object")!r}, need {OBJECT!r}')
        for it in items_by_name[name].values():
            if 'evaluator_pin' in it and not _same_pin(it['evaluator_pin'], pin):
                problems.append(f'{name}: item {it.get("item_id")} carries a different evaluator pin')
                break


def _index(meas):
    out = {}
    for it in meas.get('items', []):
        out[it['item_id']] = it
    return out


def _unit_values(rows, key_val, pr, manifest_items):
    """rows: list of (item, improvement). Returns (values, unit_label, extra) per the preregistered unit."""
    fam = {}
    for it, v in rows:
        fam.setdefault(manifest_items[it['item_id']]['family_id'], []).append((it, v))
    if pr['unit'] == 'family':
        fv = stats.family_values({f: [v for _, v in lst] for f, lst in fam.items()})
        return list(fv.values()), 'family', {'per_family': fv}
    shapes = {}
    eff = {}
    for f, lst in fam.items():
        d, n = stats.dedupe_shapes([it for it, _ in lst])
        eff[f] = n
        keep = {r['item_id'] for r in d}
        shapes[f] = [v for it, v in lst if it['item_id'] in keep]
    vals = [v for lst in shapes.values() for v in lst]
    return vals, 'shape', {'effective_shapes_per_family': eff}


def _interval_rule(values, unit, pr, strict, precision=None, resamples=None):
    """strict=True: lower bound > 0 (gain). strict=False: lower bound >= 0 (no regression).
    Fewer units than min_families_for_interval: 'sign count only', no interval.
    precision (primary only): resamples double from pr['resamples'] up to pr['max_resamples'] until two seeds
    agree on both endpoints within precision; not converged means the interval does not pass."""
    n = len(values)
    out = {'n_units': n, 'unit': unit, 'method': None, 'pass': False}
    if n == 0:
        out['reason'] = 'no scored units'
        return out
    if n >= pr['min_families_for_interval']:
        res = resamples or pr['resamples']
        if precision is not None:
            ok = False
            while True:
                ok, _ = stats.seed_stable(values, pr['interval_level'], res, [pr['seed'], pr['seed'] + 1], precision)
                if ok or res * 2 > pr['max_resamples']:
                    break
                res *= 2
            out.update(precision=precision, seed_stable=ok)
        lo, hi, pt = stats.bootstrap_interval(values, pr['interval_level'], res, pr['seed'])
        out.update(method='percentile_bootstrap', lo=lo, hi=hi, point=pt, seed=pr['seed'], resamples=res, level=pr['interval_level'])
        out['pass'] = (lo > 0) if strict else (lo >= 0)
        if precision is not None and not out['seed_stable']:
            out['pass'] = False
            out['reason'] = 'two seeds did not agree within the precision up to max_resamples'
    else:
        beats = sum(1 for v in values if (v > 0 if strict else v >= 0))
        out.update(method='sign count only', beats=beats, of=n, point=float(np.median(values)),
                   note='fewer units than min_families_for_interval: no interval')
        out['pass'] = beats == n
    return out


# ---------- single run ----------
def _run_core(manifest, base, lever, run_cfg):
    """manifest: parsed fold manifest. base/lever: parsed measurement files.
    run_cfg: {name, phase('design'|'final'), reserve_log(list), derive_log(dict|None), listed_changes(dict), size_split}"""
    pr = manifest.get('preregistration') or {}
    res = {'lever': run_cfg['name'], 'mode': lever.get('mode'), 'hard_failures': [], 'cogates': {}, 'author_reported': True}
    hf = res['hard_failures']
    hf += [f'manifest: {x}' for x in mf.validate(manifest)]
    if hf:
        return _finish(res, pr, manifest)
    items = {it['item_id']: it for it in manifest['items']}
    bi, li = _index(base), _index(lever)
    _hard_pins(pr, {'base': base, 'lever': lever}, {'base': bi, 'lever': li}, hf)
    if base.get('path_label') != lever.get('path_label') or lever.get('path_label') != manifest['items'][0]['path_label']:
        hf.append('path label differs between base, lever and manifest: never pooled')
    # evaluator output header: names come from the header, manifest names must match it (fail closed)
    cm = pr['cogate_metrics']
    hb, hl = base.get('columns'), lever.get('columns')
    if not isinstance(hb, list) or not isinstance(hl, list) or not hb or hb != hl:
        hf.append('evaluator output header (columns) missing or different between base and lever')
    else:
        wanted = [cm['nodes'], pr['primary_metric']] + list(cm['c2']) + list(cm['c7']) + list(cm.get('tdp_components') or [])
        miss = [w for w in wanted if w not in hl]
        if miss:
            hf.append(f'RED: manifest column names not in evaluator header: {miss}')
        uncovered = [c for c in hl if (c.startswith('C2_') and c not in cm['c2']) or (c.startswith('C7_') and c not in cm['c7'])]
        if uncovered:
            hf.append(f'RED: evaluator header has C2/C7 columns the manifest does not gate: {uncovered}')
        res['header_columns'] = hl
        res['nd_columns_not_gated'] = [c for c in hl if c[:2] in ('C1', 'C3', 'C4')]
    res['conventions'] = {'min_families_for_interval': pr.get('min_families_for_interval'), 'interval_level': pr.get('interval_level'),
                          'convention_values': CONVENTIONS,
                          'deviates': {k: pr.get(k) for k, v in CONVENTIONS.items() if pr.get(k) != v}}
    # derive read-sha gate
    design = manifest['design_family']; reserve = manifest.get('reserve_family')
    phase = run_cfg['phase']
    if phase not in ('design', 'final'):
        hf.append('phase must be design or final')
    held = [it for it in manifest['items'] if it['family_id'] != design]
    in_scope = []
    for it in held:
        if it['family_id'] == reserve and phase != 'final':
            continue            # the reserve family is not looked at before the design is frozen
        in_scope.append(it)
    res['excluded_design_items'] = sum(1 for it in manifest['items'] if it['family_id'] == design)
    res['reserve_in_scope'] = any(it['family_id'] == reserve for it in in_scope)
    heldout_hashes = {it['file_sha256'] for it in held}
    dl = run_cfg.get('derive_log')
    if dl is None:
        if not lever.get('derives_nothing'):
            hf.append('derive read log missing and lever does not declare derives_nothing')
        res['derive_read_gate'] = {'checked': False, 'derives_nothing': bool(lever.get('derives_nothing'))}
    else:
        ok, bad = derive_guard.check_no_heldout_reads(dl, heldout_hashes)
        res['derive_read_gate'] = {'checked': True, 'reads': len(dl.get('reads', [])), 'pass': ok, 'offending': bad}
        if not ok:
            hf.append('derive read a held-out file: ' + ', '.join(b['path'] for b in bad))
    # reserve look rule
    if res['reserve_in_scope']:
        c = reserve_count(run_cfg['reserve_log'], reserve)
        res['reserve_looks'] = c
        if c != 1:
            hf.append(f'reserve family {reserve} must be looked at exactly once, log count {c}')
    # coverage
    need = {it['item_id'] for it in in_scope}
    for name, idx in (('base', bi), ('lever', li)):
        miss = sorted(need - set(idx))
        if miss:
            hf.append(f'{name} measurements miss {len(miss)} held-out items, e.g. {miss[:3]}')
    if hf:
        return _finish(res, pr, manifest)
    metric = pr['primary_metric']; direction = pr['direction']
    # abstain accounting and scored intersection
    ab = {}
    scored = []
    for it in in_scope:
        b, l = bi[it['item_id']], li[it['item_id']]
        f = it['family_id']
        a = ab.setdefault(f, {'base': 0, 'lever': 0, 'scored': 0, 'n': 0})
        a['n'] += 1
        a['base'] += bool(b.get('abstain')); a['lever'] += bool(l.get('abstain'))
        if not b.get('abstain') and not l.get('abstain'):
            a['scored'] += 1
            scored.append((it, b, l))
    res['abstain'] = ab
    tgt = [(it, b, l) for it, b, l in scored if l.get('target', True)]
    nontgt = [(it, b, l) for it, b, l in in_scope_pairs(in_scope, bi, li) if not l.get('target', True)]
    # primary
    rows = []
    for it, b, l in tgt:
        if metric not in b or metric not in l:
            hf.append(f'item {it["item_id"]} lacks primary metric {metric}')
            return _finish(res, pr, manifest)
        r = dict(l); r['item_id'] = it['item_id']; r['shape_key'] = l.get('shape_key') or b.get('shape_key')
        rows.append((r, stats.improvement(b[metric], l[metric], direction)))
    vals, unit, extra = _unit_values(rows, None, pr, items)
    steps = [r['pixel_iou_step'] for r, _ in rows if r.get('pixel_iou_step')]
    precision = min(steps) if steps else pr.get('interval_precision')
    if len(vals) >= pr['min_families_for_interval'] and not precision:
        hf.append('interval path needs a precision: evaluator pixel_iou_step per item or manifest interval_precision')
        return _finish(res, pr, manifest)
    res['primary'] = _interval_rule(vals, unit, pr, strict=True, precision=precision if len(vals) >= pr['min_families_for_interval'] else None)
    res['primary']['precision_source'] = 'item pixel_iou_step (min over styles)' if steps else ('manifest interval_precision' if precision else None)
    res['primary'].update(extra); res['primary']['metric'] = metric; res['primary']['direction'] = direction
    res['primary']['n_scored_target_items'] = len(rows)
    res['multiplicity_settings_tried'] = pr['settings_tried']
    # co-gate: nodes at equal fidelity. epsilon is per item (emitted by the evaluator, style pixel scale);
    # the manifest scalar is only a fallback. No epsilon at all: fail closed.
    fb = pr.get('equal_fidelity_epsilon')
    eps_used = {}
    eq = []; noeps = []
    for it, b, l in tgt:
        e = l.get('equal_fidelity_epsilon'); src = 'item'
        if e is None:
            e = fb; src = 'fallback'
        if e is None or not isinstance(e, (int, float)) or e < 0:
            noeps.append(it['item_id']); continue
        sty = items[it['item_id']]['style_id'] + '/' + items[it['item_id']]['family_id']
        d = eps_used.setdefault(sty, {'min': e, 'max': e, 'from_item': 0, 'from_fallback': 0})
        d['min'] = min(d['min'], e); d['max'] = max(d['max'], e); d['from_item' if src == 'item' else 'from_fallback'] += 1
        if abs(l[metric] - b[metric]) <= e:
            eq.append((it, b, l))
    if noeps:
        hf.append(f'no equal_fidelity_epsilon on item and no manifest fallback: {noeps[:5]}')
        return _finish(res, pr, manifest)
    nname = cm['nodes']
    node_rows = []
    for it, b, l in eq:
        if nname not in b or nname not in l:
            hf.append(f'item {it["item_id"]} lacks {nname}'); return _finish(res, pr, manifest)
        r = dict(l); r['item_id'] = it['item_id']; r['shape_key'] = l.get('shape_key') or b.get('shape_key')
        node_rows.append((r, stats.improvement(b[nname], l[nname], 'lower_better')))
    if node_rows:
        nv, nu, _ = _unit_values(node_rows, None, pr, items)
        g = _interval_rule(nv, nu, pr, strict=False, resamples=res['primary'].get('resamples'))
    else:
        g = {'pass': False, 'reason': 'no item at equal fidelity: no evidence'}
    g['equal_items'] = len(eq); g['unequal_items'] = len(tgt) - len(eq)
    g['epsilon_per_style_family'] = eps_used
    g['epsilon_is_window_not_threshold'] = True
    res['cogates']['nodes_at_equal_fidelity'] = g
    # co-gates C2: every named column must be exactly 0 on every lever item in scope
    for col in cm['c2']:
        bad2 = [it['item_id'] for it in in_scope if li[it['item_id']].get(col) != 0]
        res['cogates'][f'c2_zero:{col}'] = {'pass': not bad2, 'violations': bad2[:20], 'n_violations': len(bad2)}
    # co-gates C7 columns and TDP components: no regression, direction preregistered
    dirs = cm.get('directions', {})
    for m in cm['c7']:
        res['cogates'][f'c7:{m}'] = _noregress(tgt, items, pr, m, dirs, None, res['primary'].get('resamples'))
    for comp in (cm.get('tdp_components') or []):
        res['cogates'][f'tdp:{comp}'] = _noregress(tgt, items, pr, comp, dirs, 'tdp', res['primary'].get('resamples'))
    # co-gate: non-target byte identical or listed
    listed = run_cfg.get('listed_changes') or {}
    diffs = [it['item_id'] for it, b, l in nontgt if l.get('output_sha256') != b.get('output_sha256')]
    unl = [i for i in diffs if i not in listed]
    missing_hash = [it['item_id'] for it, b, l in nontgt if not l.get('output_sha256') or not b.get('output_sha256')]
    res['cogates']['non_target_byte_identical'] = {
        'pass': not unl and not missing_hash, 'non_target_items': len(nontgt), 'changed': len(diffs),
        'listed': sorted(set(diffs) & set(listed)), 'unlisted': unl[:20], 'missing_output_sha': missing_hash[:20]}
    # within the used budget (every lever item in scope)
    over = [it['item_id'] for it in in_scope if li[it['item_id']].get(cm['nodes']) is None or li[it['item_id']].get('budget_nodes') is None
            or li[it['item_id']][cm['nodes']] > li[it['item_id']]['budget_nodes']]
    res['cogates']['within_budget'] = {'pass': not over, 'over_or_missing': over[:20], 'n': len(over)}
    # equal-node comparison from the evaluator's IoU-vs-node curve: lever IoU at the node count of the base glyph
    eqn_rows = []; missing_pt = []; curves = {}
    for it, b, l in tgt:
        cv = l.get('curve'); nb = b.get(cm['nodes'])
        if cv is not None or b.get('curve') is not None:
            curves[it['item_id']] = {'base_nodes': nb, 'base_iou': b.get(metric), 'lever_curve': cv, 'base_curve': b.get('curve')}
        pt = [q for q in (cv or []) if len(q) == 2 and q[0] == nb]   # exact point only; best-prefix is forbidden
        if not pt:
            missing_pt.append(it['item_id']); continue
        r = dict(l); r['item_id'] = it['item_id']; r['shape_key'] = l.get('shape_key') or b.get('shape_key')
        eqn_rows.append((r, stats.improvement(b[metric], pt[0][1], direction)))
    if eqn_rows and not missing_pt:
        ev, eu, _ = _unit_values(eqn_rows, None, pr, items)
        pe = _interval_rule(ev, eu, pr, strict=True, resamples=res['primary'].get('resamples'))
    else:
        pe = {'pass': False, 'reason': 'no evidence: lever curve has no point at the base node count for ' + str(len(missing_pt)) + ' items'}
    pe['required_for_decision'] = pr['equal_node_gate']; pe['n_missing_points'] = len(missing_pt)
    res['primary_equal_node'] = pe
    res['curves'] = {k: curves[k] for k in sorted(curves)}
    nonmono = []
    for k in sorted(curves):
        cv = sorted(tuple(q) for q in (curves[k]['lever_curve'] or []))
        if any(cv[i + 1][1] < cv[i][1] for i in range(len(cv) - 1)):
            nonmono.append(k)
    res['monotonicity'] = {'curves_checked': sum(1 for k in curves if curves[k]['lever_curve']), 'non_monotone_items': nonmono,
                           'best_prefix_rule_applied': False,
                           'note': 'IoU should not fall as nodes are added; listed items are reported, the best-prefix rule is forbidden and never applied'}
    # size split (item 8): declared split on family glyph counts
    sz = manifest.get('family_sizes'); split = pr.get('size_split_glyphs')
    if sz and split:
        small = {f for f, n in sz.items() if n < split}
        sub = [(r, v) for r, v in rows if items[r['item_id']]['family_id'] in small]
        if sub:
            sv, su, _ = _unit_values(sub, None, pr, items)
            res['primary_small_families_only'] = _interval_rule(sv, su, pr, strict=True)
        res['size_split'] = {'glyphs': split, 'small_families': sorted(small)}
    else:
        res['size_split'] = 'not reported: family_sizes or size_split_glyphs missing'
    return _finish(res, pr, manifest, in_scope=in_scope, meta=(base, lever))


def _cap(base_item, name, pr, nodes_col):
    n = base_item.get(nodes_col)
    if not isinstance(n, int):
        return None
    if name == 'current':
        return n
    if name == 'plus10':
        import math
        v = n * (1 + pr['budget_plus_fraction'])
        return math.floor(v + 1e-9) if pr['budget_rounding'] == 'floor' else math.ceil(v - 1e-9)
    p = base_item.get('potrace_nodes')
    return p if isinstance(p, int) else None


def run_one(manifest, base, lever, run_cfg):
    """Runs the gate once per budget (current node count, plus fraction CONVENTION, glyph's own potrace count).
    Lever rows carry `budget` and `budget_nodes`; the gate recomputes each cap from the base item and fails on
    a mismatch. Each budget has its own decision; nothing is ranked."""
    pr = manifest.get('preregistration') or {}
    top = {'lever': run_cfg['name'], 'mode': lever.get('mode'), 'hard_failures': [], 'budgets': {}, 'author_reported': True,
           'tables_note': 'rows ordered by item_id, not by outcome; no best or most economical label is produced'}
    probs = mf.validate(manifest)
    if probs:
        top['hard_failures'] = [f'manifest: {x}' for x in probs]
        top.update(decision='NO_PORT', status='none', budget_decisions={})
        return top
    cm = pr['cogate_metrics']
    src = manifest['potrace_budget_source']
    if base.get('potrace_budget_source_sha256') != src['sha256']:
        top['hard_failures'].append('base measurement potrace_budget_source_sha256 differs from the manifest source pin')
    for nm, meas_ in (('base', base), ('lever', lever)):
        if meas_.get('c2_definition_sha256') != manifest['c2_definition_sha256']:
            top['hard_failures'].append(f'{nm} C2 measured with a definition other than the pinned c2_exact.py')
        if meas_.get('node_count_parser_pin') != src['parser_pin']:
            top['hard_failures'].append(f'{nm} node_count_parser_pin differs from the potrace budget source parser pin: budget and count must share one definition')
    bidx = {it['item_id']: it for it in base.get('items', [])}
    rows = {n: [] for n in mf.BUDGETS}
    for it in lever.get('items', []):
        if it.get('budget') not in rows:
            top['hard_failures'].append(f'lever row {it.get("item_id")} has budget {it.get("budget")!r}, need one of {list(mf.BUDGETS)}')
            continue
        rows[it['budget']].append(it)
    held = {it['item_id'] for it in manifest['items'] if it['family_id'] != manifest['design_family']}
    for name in mf.BUDGETS:
        mism = []
        ids = set()
        for it in rows[name]:
            ids.add(it['item_id'])
            b = bidx.get(it['item_id'])
            if b is None:
                continue
            cap = _cap(b, name, pr, cm['nodes'])
            if cap is None or it.get('budget_nodes') != cap:
                mism.append((it['item_id'], it.get('budget_nodes'), cap))
        if mism:
            top['hard_failures'].append(f'budget {name}: budget_nodes differs from the gate-computed cap (item, given, expected): {mism[:5]}')
        miss = sorted(held - ids)
        if miss and rows[name]:
            pass   # coverage is checked by the core run (reserve/design scope aware)
    for name in mf.BUDGETS:
        lv = dict(lever); lv['items'] = [{k: v for k, v in it.items() if k != 'budget'} for it in rows[name]]
        r = _run_core(manifest, base, lv, dict(run_cfg, name=f'{run_cfg["name"]}@{name}'))
        top['budgets'][name] = r
        top['hard_failures'] += [f'[{name}] {x}' for x in r['hard_failures']]
    dec = {n: r['decision'] for n, r in top['budgets'].items()}
    top['budget_decisions'] = dec
    top['decision'] = 'PORT' if (not [x for x in top['hard_failures'] if not x.startswith('[')] and all(v == 'PORT' for v in dec.values())) else 'NO_PORT'
    sts = [r.get('status') for r in top['budgets'].values()]
    top['status'] = 'none' if top['decision'] == 'NO_PORT' else ('adopted' if all(s == 'adopted' for s in sts) else 'candidate')
    top['author_reported'] = any(r.get('author_reported', True) for r in top['budgets'].values())
    top['decision_note'] = 'top-level PORT needs every budget to PORT; per-budget decisions are in budget_decisions'
    return top


def in_scope_pairs(in_scope, bi, li):
    return [(it, bi[it['item_id']], li[it['item_id']]) for it in in_scope
            if not bi[it['item_id']].get('abstain') and not li[it['item_id']].get('abstain')]


def _noregress(tgt, items, pr, name, dirs, group, resamples=None):
    if name not in dirs:
        return {'pass': False, 'reason': f'direction for {name} not preregistered'}
    rows = []
    for it, b, l in tgt:
        bv = (b.get(group) or {}).get(name) if group else b.get(name)
        lv = (l.get(group) or {}).get(name) if group else l.get(name)
        if bv is None or lv is None:
            return {'pass': False, 'reason': f'item {it["item_id"]} lacks {name}'}
        r = dict(l); r['item_id'] = it['item_id']; r['shape_key'] = l.get('shape_key') or b.get('shape_key')
        rows.append((r, stats.improvement(bv, lv, dirs[name])))
    if not rows:
        return {'pass': False, 'reason': 'no scored target items: no evidence'}
    v, u, _ = _unit_values(rows, None, pr, items)
    out = _interval_rule(v, u, pr, strict=False, resamples=resamples)
    out['direction'] = dirs[name]
    out['worse_items'] = sum(1 for _, x in rows if x < 0)
    return out


def _finish(res, pr, manifest, in_scope=None, meta=None):
    hard_ok = not res['hard_failures']
    primary_ok = bool(res.get('primary', {}).get('pass'))
    if pr.get('equal_node_gate') and hard_ok:
        primary_ok = primary_ok and bool(res.get('primary_equal_node', {}).get('pass'))
    co_ok = bool(res['cogates']) and all(g.get('pass') for g in res['cogates'].values())
    res['decision'] = 'PORT' if (hard_ok and primary_ok and co_ok) else 'NO_PORT'
    reasons = []
    if not hard_ok: reasons.append('hard gate failure')
    if not primary_ok: reasons.append('no gain above the interval rule (used budget or equal node)' if hard_ok else 'primary not evaluated')
    if hard_ok and not co_ok: reasons.append('co-gate failure: ' + ', '.join(k for k, g in res['cogates'].items() if not g.get('pass')))
    res['decision_reasons'] = reasons
    # status ladder
    status = 'none'
    if res['decision'] == 'PORT' and meta:
        families = {i['family_id'] for i in in_scope}
        nondesign = len(families)
        independent = bool(meta[1].get('run_by')) and meta[1].get('run_by') != meta[1].get('author')
        single_font = len({i['font_id'] for i in manifest['items']}) == 1
        why = []
        if single_font: why.append('single font, internal fold')
        if nondesign < 3: why.append(f'{nondesign} non-design families, need at least 3')
        if not res.get('reserve_in_scope'): why.append('final reserve not looked at in this run')
        if not independent: why.append('not independently run (author rerun)')
        status = 'adopted' if not why else 'candidate'
        res['status_blockers'] = why
        res['author_reported'] = not independent
    res['status'] = status
    return res


# ---------- composition modes ----------
def run_modes(manifest, base, singles, composed, run_cfgs):
    """singles: {name: measurement} (each mode alone_raw). composed: list of (order_tuple, measurement), each order is
    a separate mode (for example L7->L2->L1 and L2->L7->L1). Each mode decides on its own measurements.
    Additivity is reported, never assumed."""
    if isinstance(composed, tuple) and composed and isinstance(composed[0], tuple):
        composed = [composed]                  # single (order, measurement) pair kept for callers of r2
    out = {'modes': {}, 'additivity': {}}
    for name, m in singles.items():
        if m.get('mode') != 'alone_raw':
            out['modes'][name] = {'decision': 'NO_PORT', 'hard_failures': [f'{name}: measurement mode is {m.get("mode")!r}, need alone_raw']}
            continue
        out['modes'][name] = run_one(manifest, base, m, run_cfgs[name])
    labels = []
    for order, cm in composed:
        label = '->'.join(order); labels.append((label, order))
        if cm.get('mode') != 'composed' or tuple(cm.get('order') or ()) != tuple(order):
            out['modes'][label] = {'decision': 'NO_PORT', 'hard_failures': [f'{label}: measurement is not the sequential composition {order}']}
        elif set(order) - set(singles):
            out['modes'][label] = {'decision': 'NO_PORT', 'hard_failures': ['composition members have no single-lever run in this invocation']}
        else:
            out['modes'][label] = run_one(manifest, base, cm, run_cfgs[label])
    def pt(mode):
        r = out['modes'].get(mode, {}); bs = r.get('budgets') or {}
        return {n: b.get('primary', {}).get('point') for n, b in bs.items()}
    for label, order in labels:
        members = {k: pt(k) for k in order if k in singles}
        comp = pt(label)
        sums = {}
        for n in comp:
            vals = [members[k].get(n) for k in members]
            if isinstance(comp.get(n), float) and vals and all(isinstance(v, float) for v in vals):
                sums[n] = {'sum_of_singles': float(sum(vals)), 'composed': comp[n]}
        out['additivity'][label] = {'per_budget': sums, 'assumed_additive': False,
                                    'note': 'reported only; the composition decision uses its own measurements'}
    out['decision'] = {k: v['decision'] for k, v in out['modes'].items()}
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--base', required=True)
    ap.add_argument('--run', action='append', default=[], help='name=measurements.json (alone_raw)')
    ap.add_argument('--composed', action='append', default=[], help='A,B,C=measurements.json (sequential order), repeatable')
    ap.add_argument('--derive-log', action='append', default=[], help='name=read_log.json')
    ap.add_argument('--listed-changes', action='append', default=[], help='name=listed.json {item_id: reason}')
    ap.add_argument('--reserve-log', required=True)
    ap.add_argument('--phase', choices=('design', 'final'), required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    m = mf.load(a.manifest); base = json.loads(Path(a.base).read_text())
    rl = json.loads(Path(a.reserve_log).read_text()) if Path(a.reserve_log).exists() else []
    dl = {k: json.loads(Path(v).read_text()) for k, v in (x.split('=', 1) for x in a.derive_log)}
    lc = {k: json.loads(Path(v).read_text()) for k, v in (x.split('=', 1) for x in a.listed_changes)}
    singles = {k: json.loads(Path(v).read_text()) for k, v in (x.split('=', 1) for x in a.run)}
    cfgs = {k: {'name': k, 'phase': a.phase, 'reserve_log': rl, 'derive_log': dl.get(k), 'listed_changes': lc.get(k)} for k in singles}
    receipts = {'manifest': _sha(a.manifest), 'base': _sha(a.base), 'reserve_log': _sha(a.reserve_log) if Path(a.reserve_log).exists() else None}
    receipts.update({f'run:{x.split("=",1)[0]}': _sha(x.split('=', 1)[1]) for x in a.run})
    if a.composed:
        comps = []
        for spec in a.composed:
            names, path = spec.split('=', 1); order = tuple(names.split(',')); label = '->'.join(order)
            comps.append((order, json.loads(Path(path).read_text())))
            cfgs[label] = {'name': label, 'phase': a.phase, 'reserve_log': rl, 'derive_log': dl.get(label), 'listed_changes': lc.get(label)}
            receipts[f'composed:{label}'] = _sha(path)
        out = run_modes(m, base, singles, comps, cfgs)
    else:
        out = {'modes': {k: run_one(m, base, v, cfgs[k]) for k, v in singles.items()}}
        out['decision'] = {k: v['decision'] for k, v in out['modes'].items()}
    out['receipts'] = receipts
    Path(a.out).write_text(json.dumps(out, indent=2, sort_keys=True, default=float) + '\n')
    out['receipts']['result'] = _sha(a.out)
    print(json.dumps(out['decision'], sort_keys=True))
    return 0 if all(d == 'PORT' for d in out['decision'].values()) else 1


if __name__ == '__main__':
    sys.exit(main())
