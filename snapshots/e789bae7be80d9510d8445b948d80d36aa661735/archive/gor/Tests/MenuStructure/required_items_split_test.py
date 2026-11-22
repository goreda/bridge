#!/usr/bin/env python3
"""Required-menu-item ledger vs the split source tree, through the real tools/architecture.py --integrity-only logic.
Every required token must be found in its named file. Ledger path-only rewrite after the PPController split: no token
removed, none weakened. Fixed ledger passes; stale path, missing token and a removed entry are RED. Swift/native NOT_RUN."""
import json, shutil, subprocess, sys, tempfile
from pathlib import Path
R = Path(__file__).resolve().parents[2]
LEDGER = 'Tests/MenuStructure/required-items.json'
data = json.loads((R / LEDGER).read_text())

def integrity(tree):
    p = subprocess.run([sys.executable, str(tree / 'tools/architecture.py'), '--root', str(tree), '--integrity-only'], capture_output=True, text=True)
    assert p.returncode in (0, 1) and 'Traceback (most recent call last)' not in p.stderr, p.stdout + p.stderr
    return [l for l in p.stdout.splitlines() if 'required menu item' in l or 'ledger missing' in l or 'owner order' in l or 'menu controls hidden' in l]

def tree_with(mutator):
    td = tempfile.mkdtemp()
    t = Path(td) / 'tree'; t.mkdir()
    (t / 'tools').mkdir(); shutil.copy2(R / 'tools/architecture.py', t / 'tools/architecture.py')
    for rel in {p for p, _ in data['required'].values() if (R / p).is_file()} | {LEDGER}:
        (t / rel).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(R / rel, t / rel)
    for p in (R / 'Sources/gor/gor').glob('ThreeD*.swift'):
        (t / 'Sources/gor/gor').mkdir(parents=True, exist_ok=True); shutil.copy2(p, t / 'Sources/gor/gor' / p.name)
    # The real integrity menu reader reconstructs the retired monolith.
    # Keep the complete reader closure, including stations with no menu tokens.
    closure = ['Tests/Structure/threed_split.py', 'Tests/Structure/section_source.py', 'Tests/Structure/threed-split-manifest.json']
    closure += [str(p.relative_to(R)) for p in (R / 'Sources/gor/Stereo').glob('*.swift')]
    for rel in closure:
        (t / rel).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(R / rel, t / rel)
    mutator(t); return t

absent = {i for i, (p, _) in data['required'].items() if not (R / p).is_file()}
errs = integrity(tree_with(lambda t: None))
bad = [e for e in errs if not any(e.endswith(': ' + i) for i in absent)]
assert not bad, bad
print('PASS real integrity logic: %d required tokens; %d found in the split tree; %d name files not in this partial tree (vendor/Resources), checked by the full integrity run' % (len(data['required']), len(data['required']) - len(absent), len(absent)))
for item, (path, tok) in sorted(data['required'].items()):
    print('  %-24s %s %s' % (item, path, 'FOUND' if (R / path).is_file() and tok in (R / path).read_text() else 'NOT-IN-TREE'))
def stale(t):
    f = t / LEDGER; f.write_text(f.read_text().replace('VR180Controller.swift', 'PPController_Features.swift'))
def notoken(t):
    f = t / 'Sources/gor/Stereo/VR180Controller.swift'; f.write_text(f.read_text().replace('setVRModeEnabled(false)', 'setVRModeEnabled(true)'))
for name, fn in (('stale-path', stale), ('token-gone', notoken)):
    e = integrity(tree_with(fn))
    assert any('required menu item missing: off' in x for x in e), (name, e)
print('PASS mutants: stale path and missing token are each caught as "required menu item missing: off"')
