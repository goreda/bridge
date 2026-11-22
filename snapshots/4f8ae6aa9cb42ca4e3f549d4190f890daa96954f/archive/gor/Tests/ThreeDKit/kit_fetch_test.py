#!/usr/bin/env python3
"""gor-fetch-models.sh kit rows, run for real against a local mirror (no network, no gh): sha gate, unpack, manifest presence, installed marker, cache hit, MoGe split."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import hashlib, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; sh = root / 'tools/gor-fetch-models.sh'
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def sha(p): return hashlib.sha256(open(p, 'rb').read()).hexdigest()
def run(t, lock, mirror=True):
    env = dict(os.environ, GOR_MODELS_LOCK=str(lock), GOR_MODELS_DIR=str(t / 'm'), GOR_MODELS_MIRROR=str(t / 'mir'))
    return subprocess.run(['/bin/bash', str(sh)], env=env, capture_output=True, text=True)
def mk_tar(t, name, pk, manifest_pk):
    d = t / 'src'; d.mkdir(exist_ok=True)
    for p in pk: (d / p).mkdir(exist_ok=True); (d / p / 'f').write_text(p)
    import json
    sys.path.insert(0, str(root / 'tools/depth_analysis')); import kit_hash
    (d / 'kit_manifest.json').write_text(json.dumps({'packages': {p: {'content_sha256': kit_hash.content_sha256(str(d / p)), 'size_bytes': kit_hash.package_size(str(d / p))} for p in manifest_pk}}))
    out = t / 'mir/github.com/goreda/gorav'; out.mkdir(parents=True, exist_ok=True)
    subprocess.run(['tar', '-cf', str(out / name), '-C', str(d)] + pk + ['kit_manifest.json'], check=True); return out / name
def lock(t, rows):
    p = t / 'lock.tsv'; p.write_text('id\tstatus\tlicense\trepo\trevision\tfile\tsha256\tbytes\tuse\n' + ''.join('\t'.join(r) + '\n' for r in rows)); return p
vda = ['encoder_fp16.mlpackage', 'bootstrap_fp16.mlpackage', 'stream_fp16.mlpackage']
with tempfile.TemporaryDirectory() as d:
    t = pathlib.Path(d); a = mk_tar(t, 'kit.tar', vda, vda + ['moge2_vits_518x294_fp16.mlpackage'])
    L = lock(t, [('vda-coreml-kit', 'usable', 'Apache-2.0', 'https://github.com/goreda/gorav', 'v1', 'kit.tar', sha(a), '1', 'x')])
    r = run(t, L); k = t / 'm/kit'
    check('good archive: rc 0, VDA packages unpacked, MoGe ones not expected from the VDA archive', r.returncode == 0 and all((k / p).is_dir() for p in vda))
    check('marker holds the archive sha', (k / '.installed-vda-coreml-kit').read_text() == sha(a))
    r2 = run(t, L); check('second run is a cache hit and stays ok', r2.returncode == 0 and 'cached' in r2.stdout)
    (k / 'encoder_fp16.mlpackage/f').write_text('corrupted')
    repair = run(t, L)
    check('valid marker but corrupt contents: names expected/actual sha+size and repairs from cached archive', repair.returncode == 0 and 'repair kit' in repair.stdout and 'expected_sha=' in repair.stdout and 'actual_sha=' in repair.stdout and (k / 'encoder_fp16.mlpackage/f').read_text() == 'encoder_fp16.mlpackage')
    (t / 'm/kit/stream_fp16.mlpackage').rename(t / 'gone'); (k / '.installed-vda-coreml-kit').unlink()
    r3 = run(t, L); check('lost marker re-installs from the cached archive', r3.returncode == 0 and (k / 'stream_fp16.mlpackage').is_dir())
with tempfile.TemporaryDirectory() as d:
    t = pathlib.Path(d); a = mk_tar(t, 'kit.tar', vda[:2], vda)           # archive lacks a package its manifest names
    L = lock(t, [('vda-coreml-kit', 'usable', 'Apache-2.0', 'https://github.com/goreda/gorav', 'v1', 'kit.tar', sha(a), '1', 'x')])
    r = run(t, L); check('manifest names a package the archive lacks: FAIL, rc 1, no marker', r.returncode == 1 and 'missing in archive' in r.stderr and not (t / 'm/kit/.installed-vda-coreml-kit').exists())
with tempfile.TemporaryDirectory() as d:
    t = pathlib.Path(d); a = mk_tar(t, 'kit.tar', vda, vda)
    L = lock(t, [('vda-coreml-kit', 'usable', 'Apache-2.0', 'https://github.com/goreda/gorav', 'v1', 'kit.tar', '0' * 64, '1', 'x')])
    r = run(t, L); check('wrong archive sha: file removed, nothing unpacked', r.returncode == 1 and not (t / 'm/kit').exists())
    L = lock(t, [('moge2-coreml-kit', 'blocked', 'MIT', 'https://github.com/goreda/gorav', 'v1', 'm.tar', sha(a), '1', 'x')])
    r = run(t, L); check('blocked MoGe row is skipped, never fetched', r.returncode == 0 and 'skip moge2-coreml-kit' in r.stdout)
# GOR_MODELS_ONLY and the gh diagnostics, run for real with a fake PATH (no gh / gh not signed in / no access)
def run_env(t, lock, extra):
    env = dict(os.environ, GOR_MODELS_LOCK=str(lock), GOR_MODELS_DIR=str(t / 'm'), **extra); return subprocess.run(['/bin/bash', str(sh)], env=env, capture_output=True, text=True)
def fake_gh(t, body):
    b = t / 'bin'; b.mkdir(exist_ok=True); g = b / 'gh'; g.write_text('#!/bin/sh\n' + body); g.chmod(0o755); (b / 'git').write_text('#!/bin/sh\nexit 1\n'); (b / 'git').chmod(0o755); return str(b)
with tempfile.TemporaryDirectory() as d:
    t = pathlib.Path(d); L = lock(t, [('vda-coreml-kit', 'usable', 'Apache-2.0', 'https://github.com/goreda/gorav', 'v1', 'kit.tar', '0' * 64, '1', 'x'), ('vda-small-pth', 'usable', 'Apache-2.0', 'x/y', 'r', 'w.pth', '0' * 64, '1', 'x')])
    nogh = str(t / 'empty'); (t / 'empty').mkdir()
    for n in ('mkdir', 'cat', 'rm', 'tr', 'sort', 'cut', 'grep', 'dirname', 'sha256sum', 'shasum', 'tar', 'cp', 'mv', 'printf'):
        w = subprocess.run(['which', n], capture_output=True, text=True).stdout.strip()
        if w: os.symlink(w, t / 'empty' / n)       # a PATH with the script's tools but no gh (the sandbox has one in /usr/bin)
    r = run_env(t, L, {'PATH': nogh, 'GOR_MODELS_ONLY': 'coreml-kit'})
    check('ONLY=coreml-kit: the weights row is neither fetched nor mentioned; missing gh is named', 'vda-small-pth' not in r.stdout + r.stderr and 'needs a GitHub sign-in' in r.stderr)
    p1 = fake_gh(t, 'case "$1" in auth) exit 1;; esac; exit 0')
    r = run_env(t, L, {'PATH': p1 + ':/usr/bin:/bin', 'GOR_MODELS_ONLY': 'coreml-kit'}); check('gh present but not signed in is named', 'needs a GitHub sign-in' in r.stderr)
    p2 = fake_gh(t, 'case "$1" in auth) exit 0;; api) exit 1;; esac; exit 0')
    r = run_env(t, L, {'PATH': p2 + ':/usr/bin:/bin', 'GOR_MODELS_ONLY': 'coreml-kit'}); check('signed in without access to goreda/gorav is named', 'needs a GitHub sign-in with access to goreda/gorav' in r.stderr)
    p3 = fake_gh(t, 'case "$1" in release) exit 1;; esac; exit 0')
    r = run_env(t, L, {'PATH': p3 + ':/usr/bin:/bin', 'GOR_MODELS_ONLY': 'coreml-kit'}); check('release download failure is named with tag and asset', 'needs a GitHub sign-in' in r.stderr)
sm = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDModels.swift'+' '):_b.index('// END relocated '+'ThreeDModels.swift'+'\n')])((_threed_split().path(root)).read_text())
check('Swift: only kit rows gate verified, passes GOR_MODELS_ONLY, logs every script line with a [GOR] 3d-fetch prefix', 'filter { Self.gated($0) }' in sm and 'env["GOR_MODELS_ONLY"] = Self.onlyID' in sm and '[GOR] 3d-fetch' in sm)
s = sh.read_text()
check('github: gh route plus git-credential release API fallback; token is not printed', 'release download' in s and 'git credential fill' in s and 'echo \"$tok\"' not in s)
sys.exit(1 if bad else 0)
