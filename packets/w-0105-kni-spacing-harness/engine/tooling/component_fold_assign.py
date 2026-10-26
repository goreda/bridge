#!/usr/bin/env python3
"""Deterministic component-level fold assignment. Components are never split.
Input TSV (explicit path): columns component_id, size (positive integer weight, e.g. pair or family count). One row per component; duplicate ids refused.
Parameters (ALL required, no defaults): --ratios name=value,... (fold names and relative shares, e.g. dev=..,calibration=..,decision=..,reserve=..), --seed (integer).
Method: order components by sha256(seed || '|' || component_id) (independent of input row order), then assign each in turn to the fold with the largest remaining deficit
 (target_share*total_size - assigned_size); ties go to the fold listed first in --ratios. No random generator state is used.
Feasibility (derived): every fold with a positive ratio must receive >=1 component, otherwise INSUFFICIENT_COMPONENTS and no manifest is written.
Outputs: fold manifest TSV (component_id, size, fold) and a receipt JSON (input sha256, parameters, script sha256, per-fold component count, size, target share, achieved share, manifest sha256). The seed is a preregistered convention. Existing outputs are refused unless --overwrite is explicit."""
import argparse, hashlib, json, sys, math, os

def sha(p): return hashlib.sha256(open(p, 'rb').read()).hexdigest()
p = argparse.ArgumentParser(); p.add_argument('components'); p.add_argument('manifest'); p.add_argument('receipt')
p.add_argument('--ratios', required=True); p.add_argument('--seed', type=int, required=True)
p.add_argument('--overwrite', action='store_true', help='explicitly allow replacing existing output files')
a = p.parse_args()
if os.path.abspath(a.manifest) == os.path.abspath(a.receipt): sys.exit('OUTPUT_CONFLICT: manifest and receipt must be distinct')
if any(os.path.abspath(x) == os.path.abspath(a.components) for x in (a.manifest, a.receipt)): sys.exit('OUTPUT_CONFLICT: outputs must not replace input')
if not a.overwrite:
    for output in (a.manifest, a.receipt):
        if os.path.lexists(output): sys.exit('OUTPUT_EXISTS: refusing replacement without --overwrite: ' + output)
names = []; rat = {}
for kv in a.ratios.split(','):
    if '=' not in kv: sys.exit('ratio must be name=value: %r' % kv)
    n, v = kv.split('=', 1)
    try: v = float(v)
    except ValueError: sys.exit('bad ratio value %r' % kv)
    if n in rat or not n: sys.exit('empty or duplicate fold name %r' % n)
    if not (math.isfinite(v) and v >= 0): sys.exit('ratio must be finite and >=0: %r' % kv)
    names.append(n); rat[n] = v
tot_r = sum(rat.values())
if tot_r <= 0: sys.exit('ratios sum to zero')
L = [l for l in open(a.components, newline='').read().replace('\r', '').split('\n') if l != '']
H = L[0].split('\t')
if H[:2] != ['component_id', 'size'] and not {'component_id', 'size'} <= set(H): sys.exit('columns component_id and size required')
rows = {}
for i, l in enumerate(L[1:], 2):
    c = l.split('\t')
    if len(c) != len(H): sys.exit('row %d field count mismatch' % i)
    r = dict(zip(H, c)); cid = r['component_id']
    if not cid: sys.exit('empty component_id row %d' % i)
    if cid in rows: sys.exit('duplicate component ' + cid)
    try: sz = int(r['size'])
    except ValueError: sys.exit('size must be an integer, row %d' % i)
    if sz <= 0: sys.exit('size must be positive, row %d' % i)
    rows[cid] = sz
if not rows: sys.exit('no components')
total = sum(rows.values())
order = sorted(rows, key=lambda c: hashlib.sha256(('%d|%s' % (a.seed, c)).encode()).hexdigest())
got = {n: 0 for n in names}; cnt = {n: 0 for n in names}; asg = {}
for c in order:
    best = max(names, key=lambda n: (rat[n] / tot_r * total - got[n], -names.index(n)))
    asg[c] = best; got[best] += rows[c]; cnt[best] += 1
empty = [n for n in names if rat[n] > 0 and cnt[n] == 0]
if empty: sys.exit('INSUFFICIENT_COMPONENTS: folds with positive ratio got no component: %s (components=%d)' % (empty, len(rows)))
try:
    manifest_file = open(a.manifest, 'w' if a.overwrite else 'x')
except FileExistsError: sys.exit('OUTPUT_EXISTS: manifest appeared before write: ' + a.manifest)
with manifest_file as f:
    f.write('component_id\tsize\tfold\n')
    for c in sorted(rows): f.write('%s\t%d\t%s\n' % (c, rows[c], asg[c]))
rc = {'input_sha256': sha(a.components), 'ratios': {n: rat[n] for n in names}, 'seed': a.seed, 'script_sha256': sha(__file__), 'total_size': total, 'components': len(rows),
      'folds': {n: {'components': cnt[n], 'size': got[n], 'target_share': rat[n] / tot_r, 'achieved_share': got[n] / total} for n in names}, 'manifest_sha256': sha(a.manifest),
      'method': 'sha256(seed|id) order, largest-deficit greedy, ties to first-listed fold'}
try:
    receipt_file = open(a.receipt, 'w' if a.overwrite else 'x')
except FileExistsError: sys.exit('OUTPUT_EXISTS: receipt appeared before write: ' + a.receipt)
with receipt_file as f: json.dump(rc, f, indent=1, sort_keys=True)
print('MANIFEST', a.manifest, rc['manifest_sha256']); print(json.dumps(rc['folds'], sort_keys=True))
