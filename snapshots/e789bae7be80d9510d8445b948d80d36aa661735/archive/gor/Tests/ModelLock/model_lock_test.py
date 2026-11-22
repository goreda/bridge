#!/usr/bin/env python3
"""Model lock + fetch script (190t part K). Linux only; uses a local mirror, no network."""
import csv, hashlib, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
lock = root / 'models/models.lock.tsv'; script = root / 'tools/gor-fetch-models.sh'
fails = []
def check(n, c):
    print(('PASS ' if c else 'FAIL ') + n)
    if not c: fails.append(n)
rows = list(csv.DictReader(lock.open(), delimiter='\t'))
use = [r for r in rows if r['status'] == 'usable']; blk = [r for r in rows if r['status'] != 'usable']
hexs = lambda s, n: len(s) == n and all(c in '0123456789abcdef' for c in s)
check('lock has usable and blocked rows', len(use) >= 4 and len(blk) >= 4)
check('usable sha256 64 hex', all(hexs(r['sha256'], 64) for r in use))
check('usable revision 40 hex or gh release tag', all(hexs(r['revision'], 40) or r['repo'].startswith('https://github.com/') for r in use))  # github.com rows are release downloads; revision = tag (gor-fetch-models.sh)
check('only Apache-2.0/MIT usable', all(r['license'] in ('Apache-2.0', 'MIT') for r in use))
check('blocked rows have no revision/sha/file', all(r['revision'] == '-' and r['sha256'] == '-' and r['file'] == '-' for r in blk) or all(not hexs(r['sha256'], 64) for r in blk))
check('NC and unverified weights blocked', all(r['status'] != 'usable' for r in rows if 'NC' in r['license'] or r['license'] in ('unverified', 'n/a')))
check('script is executable and has no download for blocked rows', os.access(script, os.X_OK) and '[ "$status" = usable ]' in script.read_text())
def run(lockfile, mirror, dest):
    env = dict(os.environ, GOR_MODELS_LOCK=str(lockfile), GOR_MODELS_MIRROR=str(mirror), GOR_MODELS_DIR=str(dest))
    return subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
with tempfile.TemporaryDirectory() as t:
    t = pathlib.Path(t); mir = t / 'mir'; small = t / 'small.tsv'
    data = b'weights-bytes'; sha = hashlib.sha256(data).hexdigest()
    (mir / 'o/r').mkdir(parents=True); (mir / 'o/r/w.bin').write_bytes(data)
    hdr = '\t'.join(['id', 'status', 'license', 'repo', 'revision', 'file', 'sha256', 'bytes', 'use'])
    def lk(sha_, lic='MIT', st='usable'):
        return hdr + '\n' + '\t'.join(['a', st, lic, 'o/r', 'a' * 40, 'w.bin', sha_, '13', 'x']) + '\n' + '\t'.join(['b', 'blocked', 'CC-BY-NC-4.0', '-', '-', '-', '-', '-', 'x']) + '\n'
    small.write_text(lk(sha)); d1 = t / 'd1'; r = run(small, mir, d1)
    check('ok case: exit 0, file kept, blocked row skipped', r.returncode == 0 and (d1 / 'o/r/w.bin').read_bytes() == data and 'skip b' in r.stdout)
    r = run(small, mir, d1); check('second run uses cache', r.returncode == 0 and 'cached' in r.stdout)
    small.write_text(lk('0' * 64)); d2 = t / 'd2'; r = run(small, mir, d2)
    check('wrong sha: exit 1, file removed', r.returncode == 1 and not (d2 / 'o/r/w.bin').exists() and not (d2 / 'o/r/w.bin.part').exists())
    small.write_text(lk(sha, lic='CC-BY-NC-4.0')); d3 = t / 'd3'; r = run(small, mir, d3)
    check('non-allowed licence on a usable row refused', r.returncode == 1 and not (d3 / 'o/r/w.bin').exists())
    small.write_text(lk(sha, st='blocked')); d4 = t / 'd4'; r = run(small, mir, d4)
    check('blocked row never fetched', r.returncode == 0 and not (d4 / 'o/r/w.bin').exists())
n = (root / 'NOTICE-models.md').read_text()
check('NOTICE names every usable repo', all(r['repo'].split('/')[-1] in n or r['repo'] in n for r in use))
sys.exit(1 if fails else 0)
