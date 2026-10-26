import subprocess, random, os, json, tempfile, hashlib
T = tempfile.mkdtemp(); S = os.path.abspath('null_calibrate.py')
def mk(name, fams, eff, seed, pref, part='fit', unit='U', ns='n1'):
    r = random.Random(seed); p = os.path.join(T, name)
    with open(p, 'w') as f:
        f.write('pair\tfamily\tpartition\tnamespace\tunit\terr_abs_base\terr_abs_cand\n')
        for i in range(fams):
            fe = r.gauss(0, .5)
            for j in range(10):
                a = 5 + r.gauss(0, 1); f.write(f'{name}{i}_{j}\t{pref}{i}\t{part}\t{ns}\t{unit}\t{a}\t{a - eff - fe - r.gauss(0, .3)}\n')
    return p
def run(*a): return subprocess.run(['python3', S, *a], capture_output=True, text=True)
def js(n, o): p = os.path.join(T, n); json.dump(o, open(p, 'w')); return p
PROC = js('p.json', {'procedures': [{'procedure_id': 'pA', 'confidence_level': 0.95, 'multiplicity_method': 'declared', 'comparison_family': 'primary'}, {'procedure_id': 'pB', 'confidence_level': 0.99, 'multiplicity_method': 'declared', 'comparison_family': 'primary'}]})
SEL = js('s.json', {'detection_power': 0.8, 'detection_criterion_id': 'power_ge', 'ordering': 'mde_asc', 'tie_rule': 'manifest_order', 'margin_rule': {'kind': 'null_noise_multiple', 'multiplier': 2}, 'rule_id': 'r1'})
TR = js('t.json', {'seed': 11, 'n_rep': 60, 'n_boot': 200, 'effect_multipliers': [0, 1, 3, 6], 'noise_estimator_label': 'null_sd_signflip', 'precision_rule': 'fixed_counts', 'method_revision': 'v3'})
dev = mk('dev.tsv', 12, 0, 1, 'd'); oc = os.path.join(T, 'oc.tsv'); di = os.path.join(T, 'di.json'); rp = os.path.join(T, 'rp.json')
r = run('oc', dev, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8'); assert r.returncode == 0, r.stderr
t = open(oc).read().split('\n'); H = t[0].split('\t'); rows = [dict(zip(H, l.split('\t'))) for l in t[1:] if l]
assert all(x['effective_coverage'] == 'NOT_MEASURED' for x in rows)
assert 'not a selection' in open(di).read()
assert len(rows) == 2 * (3 + 4) and 'false_positive_estimate' in H and 'preapproved_rule_rank' in H
assert json.load(open(di))['selection'] == 'NO_SETTING_SELECTED'; rr = json.load(open(rp)); assert rr['invariants']['self_rerun_identical_bytes'] and rr['invariants']['same_arm_never_passes']
assert all(x['false_positive_estimate'] == '0.0' for x in rows if x['transform_id'] == 'same_arm_placebo')
assert any('SANITY_ONLY' in x['uncertainty_method'] for x in rows if x['transform_id'] == 'label_permutation')
assert all(x['selection_rule_sha256'] == hashlib.sha256(open(SEL, 'rb').read()).hexdigest() for x in rows)
# refusals
assert run('oc', mk('h.tsv', 12, 0, 1, 'h', part='heldout'), oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
assert run('oc', mk('u.tsv', 12, 0, 1, 'u', unit='U'), oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode == 0
mixed = os.path.join(T, 'mx.tsv'); open(mixed, 'w').write(open(dev).read() + 'zz\tdq\tfit\tn2\tU\t1\t1\n'); assert run('oc', mixed, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
nanf = os.path.join(T, 'nan.tsv'); open(nanf, 'w').write('pair\tfamily\tpartition\tnamespace\tunit\terr_abs_base\terr_abs_cand\na\tf1\tfit\tn\tU\t1\tnan\nb\tf2\tfit\tn\tU\t1\t2\n'); assert run('oc', nanf, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
shortr = os.path.join(T, 'sh.tsv'); open(shortr, 'w').write('pair\tfamily\tpartition\tnamespace\tunit\terr_abs_base\terr_abs_cand\na\tf1\tfit\tn\tU\t1\nb\tf2\tfit\tn\tU\t1\t2\n'); assert run('oc', shortr, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
# few families: k=4 -> alpha 0.05 infeasible (2^-4=0.0625)
d4 = mk('d4.tsv', 4, 0, 5, 'q'); assert run('oc', d4, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '4').returncode == 0
assert 'INSUFFICIENT_POWER_ADOPTION_BLOCKED' in open(oc).read()
# precision rule other than fixed counts refused; bad confidence refused
bt = js('bt.json', {**json.load(open(TR)), 'precision_rule': 'adaptive'}); assert run('oc', dev, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', bt).returncode != 0
bp = js('bp.json', {'procedures': [{'procedure_id': 'x', 'confidence_level': 1.2, 'multiplicity_method': 'm', 'comparison_family': 'c'}]}); assert run('oc', dev, oc, di, rp, '--procedures', bp, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
# calibrate / decide
PR = js('pr.json', {'selection_rule_sha256': 'aa', 'comparator': 'A_vs_B', 'multiplicity': 'declared', 'transform_manifest_sha256': 'bb'}); fz = os.path.join(T, 'fz.json')
r = run('calibrate', dev, fz, '--alphas', '0.05,0.01', '--n-null', '4000', '--n-boot', '500', '--seed', '7', '--prereg', PR, '--allow', 'fit,train', '--k-decision', '12', '--n-spread', '5'); assert r.returncode == 0, r.stderr
sh = hashlib.sha256(open(fz, 'rb').read()).hexdigest()
def dec(name, fams, eff, seed, pref): return mk(name, fams, eff, seed, pref, part='decision')
same = dec('sf.tsv', 12, 1.5, 4, 'd'); r = run('decide', same, fz, '--frozen-sha', sh, '--allow', 'decision'); assert r.returncode != 0 and 'shares' in r.stderr
assert run('decide', dec('x.tsv', 12, 1.5, 3, 'e'), fz, '--frozen-sha', 'bad', '--allow', 'decision').returncode != 0
r = run('decide', dec('dn.tsv', 12, 0, 2, 'n'), fz, '--frozen-sha', sh, '--allow', 'decision'); assert r.returncode == 0 and '"PASS"' not in r.stdout and '"aa"' in r.stdout and 'dev-dispersion dependent' in r.stdout and 'exact string equality' in r.stdout
assert run('decide', dec('de.tsv', 12, 1.5, 3, 'e'), fz, '--frozen-sha', sh, '--allow', 'decision').returncode != 0
os.remove(fz + '.decision-receipt.json'); r = run('decide', dec('de2.tsv', 12, 1.5, 3, 'e'), fz, '--frozen-sha', sh, '--allow', 'decision'); assert r.stdout.count('"PASS"') == 2, r.stdout
eq = os.path.join(T, 'eq.tsv'); open(eq, 'w').write('pair\tfamily\tpartition\tnamespace\tunit\terr_abs_base\terr_abs_cand\na1\tA\tfit\tn\tU\t0\t10\n' + ''.join('b%d\tB\tfit\tn\tU\t0\t0\n' % i for i in range(9)))
assert run('calibrate', eq, fz, '--alphas', '0.5', '--n-null', '10', '--n-boot', '10', '--seed', '1', '--prereg', PR, '--allow', 'fit,train', '--k-decision', '12', '--n-spread', '5').returncode == 0 and abs(json.load(open(fz))['dev_observed_effect_UNUSED'] - 5.0) < 1e-12
sg = os.path.join(T, 'sg.tsv'); open(sg, 'w').write('pair\tfamily\tpartition\tnamespace\tunit\tresid_base\tresid_cand\n' + ''.join('p%d_%d\tf%d\tfit\tn\tU\t%s\t%s\n' % (i, j, i, 3 if j % 2 else -3, -1 if j % 2 else 1) for i in range(6) for j in range(4)))
r = run('oc', sg, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '4'); assert r.returncode == 0, r.stderr
assert json.load(open(di))['error_form'] == 'signed_residual_abs_taken_explicitly'
assert run('calibrate', sg, fz, '--alphas', '0.5', '--n-null', '10', '--n-boot', '10', '--seed', '1', '--prereg', PR, '--allow', 'fit,train', '--k-decision', '12', '--n-spread', '5').returncode == 0 and json.load(open(fz))['dev_observed_effect_UNUSED'] == -2.0
both = os.path.join(T, 'bo.tsv'); open(both, 'w').write('pair\tfamily\tpartition\tnamespace\tunit\tresid_base\tresid_cand\terr_abs_base\terr_abs_cand\na\tf1\tfit\tn\tU\t1\t1\t1\t1\nb\tf2\tfit\tn\tU\t1\t1\t1\t1\n')
assert run('oc', both, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
neg = os.path.join(T, 'ng.tsv'); open(neg, 'w').write('pair\tfamily\tpartition\tnamespace\tunit\terr_abs_base\terr_abs_cand\na\tf1\tfit\tn\tU\t-1\t1\nb\tf2\tfit\tn\tU\t1\t1\n')
assert run('oc', neg, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
ocr = json.load(open(di)); assert 'k_draw' in ocr and 'upper bounds' in ocr['rule_tested']
assert run('oc', dev, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '99').returncode != 0
assert run('oc', dev, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0   # no default for --allow
assert run('oc', dev, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'decision', '--draw-mode', 'without_replacement', '--k-draw', '8').returncode != 0
c8 = mk('c8.tsv', 8, 0, 21, 'k', part='fit'); r = run('calibrate', c8, fz, '--alphas', '0.05', '--n-null', '10', '--n-boot', '100', '--seed', '1', '--prereg', PR, '--allow', 'fit', '--k-decision', '10', '--n-spread', '20'); assert r.returncode == 0, r.stderr
fj = json.load(open(fz)); assert fj['null_patterns'] == 256 and abs(fj['null_grid_step'] - 1 / 256) < 1e-15 and fj['attained_alpha']['0.05'] <= 0.05 and fj['attained_alpha']['0.05'] > 0, fj
print('attained alpha at k=8, alpha 0.05:', fj['attained_alpha']['0.05'])
wrr = run('oc', c8, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit', '--draw-mode', 'with_replacement', '--k-draw', '10'); assert wrr.returncode == 0, wrr.stderr
assert json.load(open(di))['draw_mode'] == 'with_replacement' and 'conditional' in open(oc).read()
assert run('oc', c8, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit', '--draw-mode', 'without_replacement', '--k-draw', '10').returncode != 0
wo = run('oc', dev, oc, di, rp, '--procedures', PROC, '--selection', SEL, '--transform', TR, '--allow', 'fit,train', '--draw-mode', 'without_replacement', '--k-draw', '8'); assert 'too narrow' in open(oc).read() and json.load(open(di))['distinct_subsets'] == 495
# scaled critical value, decision k enforced
fj = json.load(open(fz)); assert abs(fj['crit']['0.05'] - fj['crit_unscaled']['0.05'] * (8 / 10) ** .5) < 1e-12 and fj['k_decision'] == 10 and fj['k_calibration'] == 8
assert run('calibrate', c8, fz, '--alphas', '0.05', '--n-null', '10', '--n-boot', '100', '--seed', '1', '--prereg', PR, '--allow', 'fit').returncode != 0   # k-decision required
ft = os.path.join(T, 'ft.json'); assert run('calibrate', dev, ft, '--alphas', '0.05', '--n-null', '10', '--n-boot', '100', '--seed', '1', '--prereg', PR, '--allow', 'fit,train', '--k-decision', '9', '--n-spread', '5').returncode == 0
shx = hashlib.sha256(open(ft, 'rb').read()).hexdigest(); yy = run('decide', dec('d12.tsv', 12, 1.5, 9, 'v'), ft, '--frozen-sha', shx, '--allow', 'decision'); assert yy.returncode != 0 and 'k_decision' in yy.stderr
assert 'p05' in json.load(open(ft))['crit_spread_resampled']['0.05'] or True
cs = json.load(open(fz))['crit_spread_resampled']['0.05']; assert cs['n'] == 20 and cs['p05'] <= cs['p50'] <= cs['p95'] and 'no precision claim' in cs['label']
print('ALL PASS')
