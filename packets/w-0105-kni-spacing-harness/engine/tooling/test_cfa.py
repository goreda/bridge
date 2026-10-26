import subprocess, os, tempfile, json, random
T = tempfile.mkdtemp(); S = os.path.abspath('component_fold_assign.py')
def run(*a): return subprocess.run(['python3', S, *a], capture_output=True, text=True)
def mk(n, seed=1, name='c.tsv'):
    r = random.Random(seed); p = os.path.join(T, name)
    rows = [(f'comp{i}', r.randint(1, 20)) for i in range(n)]
    open(p, 'w').write('component_id\tsize\n' + ''.join(f'{c}\t{s}\n' for c, s in rows)); return p, rows
p, rows = mk(40); m1 = os.path.join(T, 'm1.tsv'); r1 = os.path.join(T, 'r1.json')
R = '--ratios'; RV = 'dev=0.5,calibration=0.2,decision=0.2,reserve=0.1'
x = run(p, m1, r1, R, RV, '--seed', '9'); assert x.returncode == 0, x.stderr
M = [l.split('\t') for l in open(m1).read().split('\n')[1:] if l]; assert len(M) == 40 and len({a[0] for a in M}) == 40  # each component once
assert {a[2] for a in M} == {'dev', 'calibration', 'decision', 'reserve'}
j = json.load(open(r1)); assert all(abs(f['achieved_share'] - f['target_share']) < 0.1 for f in j['folds'].values()), j['folds']
# order independence + determinism
q = os.path.join(T, 'shuf.tsv'); L = open(p).read().split('\n'); h, b = L[0], [l for l in L[1:] if l]; random.Random(3).shuffle(b); open(q, 'w').write(h + '\n' + '\n'.join(b) + '\n')
m2 = os.path.join(T, 'm2.tsv'); assert run(q, m2, os.path.join(T, 'r2.json'), R, RV, '--seed', '9').returncode == 0 and open(m1).read() == open(m2).read()
m3 = os.path.join(T, 'm3.tsv'); run(p, m3, os.path.join(T, 'r3.json'), R, RV, '--seed', '10'); assert open(m1).read() != open(m3).read()
# no defaults
assert run(p, m1, r1, R, RV).returncode != 0 and run(p, m1, r1, '--seed', '1').returncode != 0
# infeasible: 3 components, 4 folds with positive ratio
p3, _ = mk(3, name='c3.tsv'); y = run(p3, m1, r1, R, RV, '--seed', '1'); assert y.returncode != 0 and 'INSUFFICIENT_COMPONENTS' in y.stderr
# zero-ratio fold allowed with no components
assert run(p3, m1, r1, R, 'dev=1,calibration=1,decision=1,reserve=0', '--seed', '1').returncode == 0
# validation
bad = os.path.join(T, 'bad.tsv'); open(bad, 'w').write('component_id\tsize\na\t1\na\t2\n'); assert run(bad, m1, r1, R, 'dev=1,reserve=1', '--seed', '1').returncode != 0
bad2 = os.path.join(T, 'bad2.tsv'); open(bad2, 'w').write('component_id\tsize\na\t0\n'); assert run(bad2, m1, r1, R, 'dev=1', '--seed', '1').returncode != 0
assert run(p, m1, r1, R, 'dev=-1,reserve=2', '--seed', '1').returncode != 0 and run(p, m1, r1, R, 'dev=nan', '--seed', '1').returncode != 0
print('ALL PASS')
