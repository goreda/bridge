#!/usr/bin/env python3
"""ThreeDModels: Python models of rows()/progressText() against the real models.lock.tsv + pins on the wiring, plus a real swiftc
driver for the request-aware verify gate (Delivery A-5). Nothing run on a Mac, no download done. SKIPPED compile without swiftc."""
import os, pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sw = (S / 'ThreeDModels.swift').read_text(); wi = (S / 'ThreeDWiring.swift').read_text(); sh = (root / 'tools/gor-fetch-models.sh').read_text(); lock = (root / 'models/models.lock.tsv').read_text()
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def rows(t):
    out = []
    for line in t.split('\n'):
        c = line.split('\t')
        if len(c) >= 7 and c[0] != 'id' and c[1] == 'usable' and c[2] in ('Apache-2.0', 'MIT'): out.append((c[0], c[3], c[5], c[6]))
    return out
R = rows(lock)
shell_ids = [l.split('\t')[0] for l in lock.split('\n')[1:] if l.split('\t')[1:2] == ['usable'] and l.split('\t')[2] in ('Apache-2.0', 'MIT')]
check('model: rows() takes exactly the usable Apache-2.0/MIT rows the fetch script would fetch, with 64-hex sha', [r[0] for r in R] == shell_ids and len(R) >= 1 and all(re.fullmatch(r'[0-9a-f]{64}', r[3]) for r in R))
check('model: lock columns used (repo=3, file=5, sha=6) match the script read order id status license repo rev file sha', 'IFS=$\'\\t\' read -r id status license repo rev file sha bytes use' in sh and 'Row(id: c[0], repo: c[3].hasPrefix("https://") ? String(c[3].dropFirst(8)) : c[3], file: c[5], sha: c[6])' in sw)
def progress(line, done, total):
    t = line.strip()
    if t.startswith('ok '): return f'3D: models {done}/{total} ready'
    if t.startswith('FAIL') or t.startswith('REFUSE'): return f'3D: model download failed ({t[:80]}), staying 2D'
    return None
check('model: progress lines', progress('ok   vda (cached)', 1, 3) == '3D: models 1/3 ready' and progress('skip x (unusable)', 1, 3) is None and 'failed' in progress('FAIL a: sha256 mismatch, file removed', 0, 3))
check('verified only by our own sha256 compare of every usable file (not by the script exit code alone)', 'func missing() -> [Row]' in sw and 'left.isEmpty && p.terminationStatus == 0' in sw and 'hasher.finalize()' in sw)
check('source dir baked as ~/Downloads/gor (GOR_SOURCE_DIR override), models dir = script default', '/Downloads/gor' in sw and 'GOR_SOURCE_DIR' in sw and 'gor/models' in sw and 'GOR_MODELS_DIR' in sw)
check('stays 2D until verified: wiring passes a reason to the launcher while models are unverified', 'ThreeDModels.shared.ensure(report: osd)' in wi and 'modelWait' in wi and 'models not verified yet' in wi)
check('only on 3D enable (mode not off, film open, preflight fine); nothing in build.sh', 'wantsModels = mode != "off" && film != nil && ThreeDPreflight.shared.reason == nil' in wi and 'gor-fetch-models' not in (root / 'build.sh').read_text())
check('plain failure lines say staying 2D; one fetch per launch (no retry loop)', sw.count('staying 2D') >= 5 and 'failedText != nil' in sw)
check('no player-socket words', not any(re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', t, re.I) for t in (sw, wi)))
check('model: the wiring gate follows the selected depth model (DAV2 verifies just its own rows)',
      'ensureDAV2(report: osd)' in wi and 'verifiedDAV2' in wi and 'verifiedDAV2' in sw and 'gatedRows(lock: text, dav2: dav2)' in sw and 'Self.onlyID(dav2: dav2)' in sw)
sw_ = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw_ and os.path.exists(sw_):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'tm'
    r = subprocess.run([sw_, '-O', str(S / 'ThreeDModels.swift'), str(S / 'KitCompiledCache.swift'), str(S / 'KitHash.swift'), str(S / 'PrepareSupport.swift'), str(S / 'ThreeDExperimentOptions.swift'), str(S / 'CoreMLDepthRunner.swift'), str(S / 'FovTrackBuilder.swift'), str(pathlib.Path(__file__).parent / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
    check('model-gate driver compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-1500:]); sys.exit(1)
    o = subprocess.run([str(exe), str(root / 'models/models.lock.tsv')], capture_output=True, text=True).stdout
    print(o)
    check('DAV2 gate = exactly the 3 pinned dav2 rows; kit gate unchanged; fetch filter follows the request',
          'dav2 gate is exactly the 3 pinned dav2 files true' in o and 'kit gate unchanged: only coreml-kit rows, never dav2 true' in o and 'fetch filter follows the request true' in o)
    check('a DAV2-only install satisfies the DAV2 gate and never needs the kit (Delivery A-5)',
          'DAV2-only install satisfies the DAV2 gate true' in o and 'same install is unmet under the kit gate (gate choice matters) true' in o and 'dav2 rows never require a kit install marker true' in o)
else:
    print('SKIPPED compile: no swiftc')
sys.exit(1 if bad else 0)
