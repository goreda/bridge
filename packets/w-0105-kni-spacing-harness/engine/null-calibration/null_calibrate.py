#!/usr/bin/env python3
"""Null-calibration harness for ablation thresholds.
Follows docs/research/null-calibration-harness-preregistration-proposal.md and docs/research/statistical-annex-proposal.md.
Endpoint: paired absolute-error difference d = |err_cand| - |err_base| per pair; NEGATIVE = candidate better. Statistic: equal-weight mean of per-family means.
Input ledger TSV columns: pair, family, partition, namespace, unit, plus EXACTLY ONE of (err_abs_base, err_abs_cand) absolute errors or (resid_base, resid_cand) signed predicted-observed residuals; for signed input the absolute value is taken explicitly and the form is recorded as error_form. Both or neither is refused.
  partition must be 'fit' or 'train' for the harness; any other value (heldout/eval/...) is REFUSED. One namespace and one unit per file. Non-finite, duplicate, empty family refused.
Subcommands:
 oc        : operating characteristics -> operating_characteristics.tsv, decision_input.json, replay_receipt.json. Never selects a setting (NO_SETTING_SELECTED).
 calibrate : freezes a threshold from the family sign-flip null on fit/train data (exact for k<=16), bound to the prereg hashes.
 decide    : single use on a family-disjoint decision file with the frozen sha.
Manifests (JSON, all numeric settings are named CONVENTION fields, none supplied here): procedure, selection-rule, transformation. Their sha256 go into every output row.
Feasibility (derived): one-sided level alpha is attainable only if alpha >= 2^-k (k independent families); otherwise INSUFFICIENT_POWER_ADOPTION_BLOCKED and numeric fields are blank with a reason.
Interval: one-sided family-cluster bootstrap upper bound at the manifest confidence level (NOT a two-sided CI). Resample counts are fixed counts from manifests ('fixed_counts' is the only supported precision rule)."""
import argparse, hashlib, json, os, random, sys, math, itertools
EXACT_K = 16

def sha(p): return hashlib.sha256(open(p, 'rb').read()).hexdigest()
def fnum(s, w):
    try: v = float(s)
    except ValueError: sys.exit('non-numeric %r at %s' % (s, w))
    if math.isnan(v) or math.isinf(v): sys.exit('nan/inf at %s' % w)
    return v

def load(p, allow):
    L = [l for l in open(p, newline='').read().replace('\r', '').split('\n') if l != '']
    H = L[0].split('\t'); need = {'pair', 'family', 'partition', 'namespace', 'unit'}
    if not need <= set(H): sys.exit('missing columns: %s' % sorted(need - set(H)))
    abscols = {'err_abs_base', 'err_abs_cand'}; signcols = {'resid_base', 'resid_cand'}
    present = set(H) & (abscols | signcols)
    if present not in (abscols, signcols): sys.exit('ERROR_FORM: exactly one complete error form required; partial or mixed columns refused')
    absf = abscols <= set(H); sgnf = signcols <= set(H)
    if absf == sgnf: sys.exit('ledger must have exactly one of (err_abs_base,err_abs_cand) absolute errors or (resid_base,resid_cand) signed residuals; no implicit conversion')
    ef = 'absolute' if absf else 'signed_residual_abs_taken_explicitly'
    cb, cc = ('err_abs_base', 'err_abs_cand') if absf else ('resid_base', 'resid_cand')
    global ERROR_FORM; ERROR_FORM = ef
    fam = {}; seen = set(); ns = set(); un = set()
    for i, l in enumerate(L[1:], 2):
        c = l.split('\t')
        if len(c) != len(H): sys.exit('row %d has %d fields, header %d' % (i, len(c), len(H)))
        r = dict(zip(H, c))
        if not r['pair'] or not r['family']: sys.exit('empty pair/family row %d' % i)
        if not r['namespace'].strip() or not r['unit'].strip(): sys.exit('EMPTY_CONTEXT: namespace and unit required, row %d' % i)
        if r['partition'] not in allow: sys.exit('partition %r not allowed here (row %d): REFUSED' % (r['partition'], i))
        if r['pair'] in seen: sys.exit('duplicate pair ' + r['pair'])
        seen.add(r['pair']); ns.add(r['namespace']); un.add(r['unit'])
        vb = fnum(r[cb], 'row %d' % i); vc = fnum(r[cc], 'row %d' % i)
        if absf and (vb < 0 or vc < 0): sys.exit('negative value in an absolute-error column, row %d' % i)
        if sgnf: vb, vc = abs(vb), abs(vc)
        fam.setdefault(r['family'], []).append(vc - vb)
    if len(ns) != 1 or len(un) != 1: sys.exit('mixed namespace/unit refused: %s %s' % (sorted(ns), sorted(un)))
    if len(fam) < 2: sys.exit('need >=2 families')
    return fam, ns.pop(), un.pop(), len(seen)

def fm(fam): return [sum(v) / len(v) for _, v in sorted(fam.items())]
def st(ms): return sum(ms) / len(ms)
def feasible(k, a): return a >= 2.0 ** (-k)

def null_signflip(ms, seed, n_mc):
    k = len(ms)
    if k <= EXACT_K: return sorted(sum(s * m for s, m in zip(g, ms)) / k for g in itertools.product((1, -1), repeat=k)), 'exact'
    r = random.Random(seed); return sorted(sum(m if r.random() < .5 else -m for m in ms) / k for _ in range(n_mc)), 'monte_carlo'

def lower_tail_crit(nd, a):
    """largest v in null support with P(null<=v) <= a (favourable = negative side); None if alpha below 1/len."""
    N = len(nd)
    if a < 1.0 / N - 1e-15: return None
    best = None; i = 0
    while i < N:
        j = i
        while j + 1 < N and nd[j + 1] == nd[i]: j += 1
        if (j + 1) <= a * N + 1e-9: best = nd[i]
        else: break
        i = j + 1
    return best

def boot_upper(ms, n, r, a):
    """one-sided family-cluster bootstrap upper bound of the mean at level 1-a."""
    k = len(ms); m = sorted(sum(ms[r.randrange(k)] for _ in range(k)) / k for _ in range(n))
    return m[min(n - 1, max(0, int(math.ceil((1 - a) * n)) - 1))]

def improves(ms, n_boot, r, a): return boot_upper(ms, n_boot, r, a) < 0

def wilson(x, n, z=1.96):
    if n == 0: return ('', '')
    p = x / n; d = 1 + z * z / n; c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)

def req(m, keys, nm):
    miss = [k for k in keys if m.get(k) in (None, '', [])]
    if miss: sys.exit('%s manifest missing %s' % (nm, miss))

def cmd_oc(a):
    allow = tuple(a.allow.split(',')); fam, ns, un, npair = load(a.ledger, allow); ms0 = fm(fam); K0 = len(ms0); k = a.k_draw
    wr = a.draw_mode == 'with_replacement'
    if k < 2 or (k > K0 and not wr): sys.exit('k_draw must satisfy 2 <= k_draw <= number of families (%d) unless --draw-mode with_replacement' % K0)
    draw = (lambda r, xs: [xs[r.randrange(len(xs))] for _ in range(k)]) if wr else (lambda r, xs: r.sample(xs, k))
    P = json.load(open(a.procedures)); S = json.load(open(a.selection)); T = json.load(open(a.transform))
    req(T, ['seed', 'n_rep', 'n_boot', 'effect_multipliers', 'noise_estimator_label', 'precision_rule', 'method_revision'], 'transformation')
    req(S, ['detection_power', 'detection_criterion_id', 'ordering', 'tie_rule', 'margin_rule', 'rule_id'], 'selection')
    if T['precision_rule'] != 'fixed_counts': sys.exit('only precision_rule=fixed_counts supported')
    if not isinstance(P.get('procedures'), list) or not P['procedures']: sys.exit('procedures list required')
    for q in P['procedures']:
        req(q, ['procedure_id', 'confidence_level', 'multiplicity_method', 'comparison_family'], 'procedure')
        if not (0 < q['confidence_level'] < 1): sys.exit('confidence_level in (0,1)')
    sig = sorted(abs(m) for m in ms0)
    nd, mode = null_signflip(ms0, T['seed'], T['n_rep'])
    noise = (sum(x * x for x in nd) / len(nd)) ** .5 * math.sqrt(K0 / k)      # CONVENTION estimator: null sd of family-signflip mean, scaled by sqrt(K0/k_draw)
    ih = '' ; fh = {'input_manifest_sha256': sha(a.ledger), 'selection_rule_sha256': sha(a.selection), 'transformation_manifest_sha256': sha(a.transform)}
    rows = []; excl = []
    for pi, q in enumerate(P['procedures']):
        al = 1 - q['confidence_level']; base = {**fh, 'procedure_id': q['procedure_id'], 'confidence_level': q['confidence_level'], 'multiplicity_method': q['multiplicity_method'], 'comparison_family': q['comparison_family']}
        feas = feasible(k, al)
        for tid in ('same_arm_placebo', 'label_permutation', 'family_cluster_resampling', 'effect_injection'):
            effs = [m * noise for m in T['effect_multipliers']] if tid == 'effect_injection' else [None]
            for e in effs:
                row = {c: '' for c in COLS}; row.update(base); row.update(transform_id=tid, family_count=k, paired_record_count=npair, effective_coverage='NOT_MEASURED',
                    noise_unit=un, noise_method_CONVENTION=T['noise_estimator_label'], noise_derivation='family sign-flip null sd on %d families (%s), scaled sqrt(K0/k_draw) to k_draw=%d (approximation)' % (K0, mode, k),
                    detection_criterion_id=S['detection_criterion_id'])
                if not feas:
                    row.update(feasibility_state='INSUFFICIENT_POWER_ADOPTION_BLOCKED', refusal_reason='alpha=%.6g < 2^-k=%.6g' % (al, 2.0 ** -k), selection_eligibility='NO')
                    rows.append(row); continue
                r = random.Random(T['seed'] * 1000003 + pi * 101 + len(rows)); hit = 0
                for _ in range(T['n_rep']):
                    if tid == 'same_arm_placebo': ms = [0.0] * k
                    elif tid == 'label_permutation': ms = [m if r.random() < .5 else -m for m in draw(r, ms0)]
                    elif tid == 'family_cluster_resampling':
                        sub = draw(r, ms0); c = st(sub); ms = [sub[r.randrange(k)] - c for _ in range(k)]
                    else:
                        sub = draw(r, ms0); c = st(sub); ms = [sub[r.randrange(k)] - c - e for _ in range(k)]
                    hit += improves(ms, T['n_boot'], r, al)
                lo, hi = wilson(hit, T['n_rep'])
                if tid == 'effect_injection':
                    row.update(injected_effect=e, detection_estimate=hit / T['n_rep'], detection_uncertainty='%.6g..%.6g (%s)' % (lo, hi, 'overlapping draws, too narrow' if not wr else 'conditional on observed means'))
                else:
                    row.update(false_positive_estimate=hit / T['n_rep'], estimate_uncertainty='%.6g..%.6g' % (lo, hi), uncertainty_method='wilson95_over_n_rep(CONVENTION z); ' + ('replicates overlap (draws without replacement from %d families, %d distinct subsets): interval treats replicates as independent and is too narrow' % (K0, math.comb(K0, k)) if not wr else 'draws with replacement from the empirical family means: interval is conditional on those %d observed means' % K0))
                    if tid == 'label_permutation': row['uncertainty_method'] += ';SANITY_ONLY: same null family as the critical value, not calibration evidence'
                    if tid == 'same_arm_placebo' and hit: excl.append('METHOD_FAILURE: same-arm placebo declared improvement for ' + q['procedure_id'])
                row.update(null_noise_estimate=noise, feasibility_state='FEASIBLE')
                rows.append(row)
        # per-procedure summaries
        pr = [x for x in rows if x['procedure_id'] == q['procedure_id']]
        if feas:
            inj = [x for x in pr if x['transform_id'] == 'effect_injection']
            ok = [x['injected_effect'] for x in inj if x['detection_estimate'] >= S['detection_power']]
            mde = min(ok) if ok else ''
            fpmax = max(x['false_positive_estimate'] for x in pr if x['transform_id'] != 'effect_injection')
            elig = 'YES' if (fpmax <= al + 1e-12 + 0) else 'NO'
            for x in pr:
                x['minimum_detectable_effect'] = mde if mde != '' else ''
                if mde == '': x['refusal_reason'] = 'NO_EFFECT_IN_GRID_REACHES_DETECTION_POWER'
                mm = S['margin_rule']
                if un == 'UNDEFINED' or mm.get('kind') != 'null_noise_multiple': x['proposed_noise_derived_margin'] = ''; x['refusal_reason'] = (x['refusal_reason'] + ';' if x['refusal_reason'] else '') + 'MARGIN_UNVERIFIABLE(no unit/gauge or rule)'
                else: x['proposed_noise_derived_margin'] = mm['multiplier'] * noise
                x['selection_eligibility'] = elig if mde != '' else 'NO'
    elig_rows = {}
    for x in rows:
        if x['selection_eligibility'] == 'YES' and x['transform_id'] == 'effect_injection': elig_rows.setdefault(x['procedure_id'], x['minimum_detectable_effect'])
    order = sorted(elig_rows, key=lambda p: (elig_rows[p], [q['procedure_id'] for q in P['procedures']].index(p)))
    for x in rows: x['preapproved_rule_rank'] = (order.index(x['procedure_id']) + 1) if x['procedure_id'] in order else ''
    def write(out):
        with open(out, 'w') as f:
            f.write('\t'.join(COLS) + '\n')
            for x in rows: f.write('\t'.join('' if x[c] == '' else (repr(x[c]) if isinstance(x[c], float) else str(x[c])) for c in COLS) + '\n')
    write(a.out); h1 = sha(a.out); write(a.out + '.rerun'); same = sha(a.out + '.rerun') == h1; os.remove(a.out + '.rerun')
    di = {**fh, 'selection': 'NO_SETTING_SELECTED', 'k_draw': k, 'draw_mode': a.draw_mode, 'distinct_subsets': (None if wr else math.comb(K0, k)), 'dev_families_available': K0, 'rule_tested': 'bootstrap one-sided upper bound < 0 only; the decide rule also needs mean < frozen critical value (stricter), so oc false-positive and detection are upper bounds for the combined rule', 'error_form': ERROR_FORM, 'rank_meaning': 'preapproved_rule_rank is the output of the preregistered ordering rule, not a selection; the decision belongs to independent review', 'rows': len(rows), 'all_rows_in': os.path.basename(a.out), 'method_failures': excl, 'families': k, 'null_mode': mode,
          'diagnostic_notes': ['label_permutation false-positive is derived from the same null as the critical value: sanity only', 'effect_injection uses dev family means resampled; minimum detectable effect depends on the fit/train family dispersion',
                               'same_arm_placebo is deterministic (zero difference) and replicated only through bootstrap seeds']}
    json.dump(di, open(a.decision_input, 'w'), indent=1, sort_keys=True)
    rr = {'draw_mode': a.draw_mode, 'k_draw': k, **fh, 'procedure_manifest_sha256': sha(a.procedures), 'operating_characteristics_sha256': h1, 'script_sha256': sha(__file__), 'seed': T['seed'], 'method_revision': T['method_revision'],
          'error_form': ERROR_FORM, 'invariants': {'self_rerun_identical_bytes': same, 'heldout_rows_present': False, 'namespace': ns, 'unit': un, 'same_arm_never_passes': not excl},
          'excluded_heldout_pins': 'refused at load (partition not fit/train)', 'independent_rerun': 'NOT_RUN'}
    json.dump(rr, open(a.replay, 'w'), indent=1, sort_keys=True); print('OC', a.out, h1, 'self_rerun_identical=%s' % same, 'method_failures=%d' % len(excl))

COLS = ['input_manifest_sha256', 'selection_rule_sha256', 'transformation_manifest_sha256', 'procedure_id', 'confidence_level', 'multiplicity_method', 'comparison_family', 'transform_id', 'family_count',
        'paired_record_count', 'effective_coverage', 'false_positive_estimate', 'estimate_uncertainty', 'uncertainty_method', 'null_noise_estimate', 'noise_unit', 'noise_method_CONVENTION', 'noise_derivation',
        'injected_effect', 'detection_estimate', 'detection_uncertainty', 'minimum_detectable_effect', 'detection_criterion_id', 'feasibility_state', 'refusal_reason', 'proposed_noise_derived_margin',
        'selection_eligibility', 'preapproved_rule_rank']

def cmd_cal(a):
    al = [float(x) for x in a.alphas.split(',')]
    for x in al:
        if not (0 < x < 1): sys.exit('alpha in (0,1)')
    if a.n_null <= 0: sys.exit('n_null positive')
    fam, ns, un, npair = load(a.dev, tuple(a.allow.split(','))); ms = fm(fam); k = len(ms); pr = json.load(open(a.prereg))
    keys = ['selection_rule_sha256', 'comparator', 'multiplicity', 'transform_manifest_sha256']; req(pr, keys, 'prereg')
    if a.k_decision < 2: sys.exit('k_decision must be >=2')
    scale = math.sqrt(k / a.k_decision)
    nd, mode = null_signflip(ms, a.seed, a.n_null); crit = {}; crit_un = {}; stat_ = {}; att = {}
    for x in al:
        if not feasible(k, x): stat_[str(x)] = 'INSUFFICIENT_POWER(alpha<2^-k,k=%d)' % k; continue
        c = lower_tail_crit(nd, x)
        if c is None: stat_[str(x)] = 'INSUFFICIENT_POWER(null support)'; continue
        crit_un[str(x)] = c; crit[str(x)] = c * scale; stat_[str(x)] = 'OK'; att[str(x)] = sum(1 for v in nd if v <= c) / len(nd)
    if a.n_spread <= 0: sys.exit('n_spread positive')
    spread = {}
    rs = random.Random(a.seed + 7)
    for x in al:
        if str(x) not in crit: continue
        vals = []
        for _ in range(a.n_spread):
            bm = [ms[rs.randrange(k)] for _ in range(k)]; nb, _m = null_signflip(bm, a.seed, a.n_null); cb = lower_tail_crit(nb, x)
            if cb is not None: vals.append(cb * scale)
        vals.sort(); q = lambda p: vals[min(len(vals) - 1, int(p * len(vals)))] if vals else None
        spread[str(x)] = {'n': len(vals), 'p05': q(.05), 'p50': q(.5), 'p95': q(.95), 'label': 'noise estimate from resampling the calibration fold families with replacement; no precision claim; decision rule unchanged'}
    if not crit: sys.exit('INSUFFICIENT_POWER: no declared alpha feasible with k=%d (2^-k=%.6g)' % (k, 2.0 ** -k))
    fr = {'kind': 'null_calibration_frozen_v3', 'dev_sha256': sha(a.dev), 'error_form': ERROR_FORM, 'dev_families': sorted(fam), 'namespace': ns, 'unit': un, 'seed': a.seed, 'null_mode': mode, 'n_null': a.n_null, 'n_boot': a.n_boot,
          'alphas': al, 'alpha_status': stat_, 'crit': crit, 'crit_unscaled': crit_un, 'k_decision': a.k_decision, 'k_calibration': k, 'scale_factor_sqrt_kcal_over_kdec': scale, 'scale_label_CONVENTION': 'critical value scaled by sqrt(k_cal/k_decision): assumes iid families with equal variance (approximation)', 'decision_fold_reachable': {str(x): feasible(a.k_decision, x) for x in al}, 'crit_spread_resampled': spread, 'attained_alpha': att, 'null_grid_step': 1.0 / len(nd), 'null_patterns': len(nd), 'families': k, 'statistic': 'equal-weight mean of per-family mean (cand-base); favourable = negative', 'prereg_file_sha256': sha(a.prereg),
          'prereg': {x: pr[x] for x in keys}, 'derivation': 'family sign-flip null on fit/train; crit = largest null value with lower-tail mass <= alpha; alpha feasible iff alpha >= 2^-k',
          'dev_observed_effect_UNUSED': st(ms)}
    open(a.out, 'w').write(json.dumps(fr, indent=1, sort_keys=True) + '\n'); print('FROZEN', a.out, sha(a.out), json.dumps(stat_))

def cmd_dec(a):
    if sha(a.frozen) != a.frozen_sha: sys.exit('FROZEN SHA MISMATCH')
    rc = a.frozen + '.decision-receipt.json'
    if os.path.exists(rc): sys.exit('DECISION ALREADY RUN (single use)')
    fr = json.load(open(a.frozen)); fam, ns, un, npair = load(a.decision, tuple(a.allow.split(',')))
    if (ns, un) != (fr['namespace'], fr['unit']): sys.exit('namespace/unit differ from frozen')
    if len(fam) != fr['k_decision']: sys.exit('decision fold has %d families, frozen k_decision=%d: REFUSED' % (len(fam), fr['k_decision']))
    if ERROR_FORM != fr['error_form']: sys.exit('error form differs from frozen')
    sh = sorted(set(fam) & set(fr['dev_families']))
    if sh: sys.exit('decision shares %d family id(s) with dev (first %s): REFUSED' % (len(sh), sh[0]))
    ms = fm(fam); m = st(ms); res = {}; r = random.Random(fr['seed'] + 1)
    for x in fr['alphas']:
        if str(x) not in fr['crit']: res[str(x)] = {'verdict': fr['alpha_status'][str(x)]}; continue
        up = boot_upper(ms, fr['n_boot'], r, x)
        res[str(x)] = {'mean_diff': m, 'frozen_crit': fr['crit'][str(x)], 'boot_upper_one_sided': up, 'verdict': 'PASS' if (m < fr['crit'][str(x)] and up < 0) else 'FAIL'}
    out = {'frozen_sha256': a.frozen_sha, 'selection_rule_sha256': fr['prereg']['selection_rule_sha256'], 'prereg_file_sha256': fr['prereg_file_sha256'], 'decision_sha256': sha(a.decision),
           'families': len(fam), 'results': res, 'margin': 'UNVERIFIABLE (no unit/gauge)' if un == 'UNDEFINED' else 'unit: ' + un, 'note': 'curve reported; no selection from this output', 'calibration_caveat': 'frozen critical values derive from the fit/train family dispersion; if the decision-fold dispersion differs they are NOT calibrated for it (dev-dispersion dependent)', 'family_disjointness': 'checked by exact string equality of family ids only; no instance/family mapping manifest is verified'}
    open(rc, 'w').write(json.dumps(out, indent=1, sort_keys=True) + '\n'); print(json.dumps(out, indent=1, sort_keys=True))

p = argparse.ArgumentParser(); s = p.add_subparsers(dest='c', required=True)
o = s.add_parser('oc'); [o.add_argument(x) for x in ('ledger', 'out', 'decision_input', 'replay')]
o.add_argument('--allow', required=True); o.add_argument('--k-draw', type=int, required=True); o.add_argument('--draw-mode', required=True, choices=['without_replacement', 'with_replacement'])
[o.add_argument('--' + x, required=True) for x in ('procedures', 'selection', 'transform')]
c = s.add_parser('calibrate'); c.add_argument('dev'); c.add_argument('out'); c.add_argument('--alphas', required=True)
c.add_argument('--n-null', type=int, required=True); c.add_argument('--n-boot', type=int, required=True); c.add_argument('--seed', type=int, required=True); c.add_argument('--prereg', required=True); c.add_argument('--allow', required=True); c.add_argument('--k-decision', type=int, required=True); c.add_argument('--n-spread', type=int, required=True)
d = s.add_parser('decide'); d.add_argument('decision'); d.add_argument('frozen'); d.add_argument('--frozen-sha', required=True); d.add_argument('--allow', required=True)
a = p.parse_args(); {'oc': cmd_oc, 'calibrate': cmd_cal, 'decide': cmd_dec}[a.c](a)
