#!/usr/bin/env python3
"""Source inventory only. arch196g retires count, named-hub and line caps.
State-owner contracts are reviewed in projects/gor/CONTRACT.md; inventory is not ownership proof.
"""
import argparse, json, subprocess, sys
from pathlib import Path

PREFIX = 'archive/gor/'
SOURCE = 'Sources/gor/'
NAMED = {'Sources/gor/' + n + '.swift' for n in ['AppDelegate', 'PPController', 'PPController_Features', 'ThreeDWiring']}
MAXLINES = 1500
BASELINE = 'architecture/freeze-195y.json'
# 195y-r4 (owner order 2026-11-14): the consolidated 3D file is exempt from the 1500-line ceiling.
OVERSIZE_OK = {'Sources/gor/gor/ThreeD.swift'}  # arch-199s: the file is now five stations under Sources/gor/ThreeD/, each under the 4000-line cap; entry kept for historical baselines


def failures(before, after):
    """before/after: path -> (lines, blob). Returns blocking violations."""
    return []  # Count/line/path-placement rules retired by owner-delivered arch196g.


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--ref')
    p.add_argument('--baseline-file', type=Path)
    a = p.parse_args()
    root = a.root.resolve()
    baseline = json.loads((a.baseline_file or root / BASELINE).read_text())
    assert baseline.get('rules') == '195y-r4', 'baseline is not an arch-195y r4 baseline'

    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), '-c', 'gc.auto=0', *args], stderr=subprocess.DEVNULL)

    top = git('rev-parse', '--show-toplevel').decode().strip() if a.ref else None

    def treegit(*args):
        return subprocess.check_output(['git', '-C', top, '-c', 'gc.auto=0', *args], stderr=subprocess.DEVNULL)

    def inventory(ref):
        out = {}
        for line in treegit('ls-tree', '-r', ref, '--', PREFIX + SOURCE).decode().splitlines():
            meta, path = line.split('\t', 1)
            blob = meta.split()[2]
            if path.endswith('.swift'):
                out[path[len(PREFIX):]] = (len(treegit('show', ref + ':' + path).splitlines()), blob)
        return out

    errors = []
    if a.ref:
        if treegit('merge-base', baseline['commit'], a.ref).decode().strip() != baseline['commit']:
            raise RuntimeError('freeze baseline is not an ancestor')
        revisions = treegit('rev-list', '--reverse', baseline['commit'] + '..' + a.ref).decode().splitlines()
        for rev in revisions:
            parent = treegit('rev-parse', rev + '^').decode().strip()
            for e in failures(inventory(parent), inventory(rev)):
                errors.append(rev[:10] + ' ' + e)
        current = inventory(a.ref)
        if not current:
            raise RuntimeError('empty committed source inventory')
    else:
        # working tree vs baseline: blob identity marks git mv, count drop marks absorption
        before = {p: (n, b) for p, (n, b) in baseline['files'].items()}
        after = {}
        for x in (root / SOURCE).rglob('*.swift'):
            if x.is_file():
                blob = git('hash-object', str(x)).decode().strip()
                after[x.relative_to(root).as_posix()] = (len(x.read_bytes().splitlines()), blob)
        errors.extend(failures(before, after))
        current = after
    for e in errors:
        print('BLOCK ' + e, file=sys.stderr)
    hubs = '/'.join(str(current.get('Sources/gor/' + n + '.swift', (0,))[0]) for n in ['AppDelegate', 'PPController', 'PPController_Features'])
    over = sum(1 for n, b in current.values() if n > MAXLINES)
    print('STRUCT descriptive inventory files=%d hubs=%s over1500=%d check=%s (not ownership proof)'  % (len(current), hubs, over, 'FAIL' if errors else 'PASS'))
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
