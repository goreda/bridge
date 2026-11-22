#!/usr/bin/env python3
"""ThreeDPrepareSpawn / ShotSink: Python models of readyDocument() and merge() checked against prepare_film.write_render_ready / cache.merge, plus pins (Swift uncompiled)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys, tempfile, os
root = pathlib.Path(__file__).resolve().parents[2]
def sec(n):   # 195y: the satellite files are BEGIN/END relocated spans inside Sources/gor/gor/ThreeD.swift
    b = (_threed_split().path(root)).read_text()
    for tag in (' (195y owner-order 3D consolidation, behavior unchanged)', ' (195y G2, behavior unchanged)'):
        s = '// BEGIN relocated ' + n + '.swift' + tag + '\n'
        if s in b: return b[b.index(s) + len(s):b.index('// END relocated ' + n + '.swift\n')]
    raise KeyError(n)
sw = sec('ThreeDPrepareSpawn'); wi = sec('ThreeDWiring')
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def ready_doc(shots, existing, failures):
    rows = []
    for i, (s, e) in enumerate(shots):
        d = f'depth_shot_{i:05d}.dzc' in existing; sp = f'source_shot_{i:05d}.mp4' in existing; err = failures.get(i); ready = d and sp
        rows.append({'shot': i, 'start': s, 'end': e, 'depth_ready': d, 'source_ready': sp, 'ready': ready, 'failed': err is not None and not ready, 'error': None if ready else err})
    return {'shots': rows, 'n_shots': len(shots), 'n_ready': sum(r['ready'] for r in rows), 'n_failed': sum(r['failed'] for r in rows)}
shots = [[0, 29], [30, 59], [60, 89]]
# reference semantics copied from prepare_film.write_render_ready (contract s8); the module itself needs torch, so it is not imported here
ref_src = (root / 'tools/depth_analysis/prepare_film.py').read_text()
check('reference still says: ready = depth AND source, failed = error and not ready', 'ready = d and sp' in ref_src and '(err is not None) and not ready' in ref_src)
with tempfile.TemporaryDirectory() as d:
    for n in ('depth_shot_00000.dzc', 'source_shot_00000.mp4', 'depth_shot_00001.dzc'): open(os.path.join(d, n), 'w').close()
    mine = ready_doc(shots, set(os.listdir(d)), {1: 'boom', 2: 'x'})
    check('model: shot0 ready; shot1 depth only + error = failed; shot2 nothing + error = failed', mine['n_ready'] == 1 and mine['n_failed'] == 2 and mine['shots'][1]['depth_ready'] and not mine['shots'][1]['source_ready'] and mine['shots'][1]['failed'] and mine['shots'][0]['error'] is None)
def merge(ranges, r):
    out = []
    for x in sorted(ranges + [r]):
        if out and x[0] <= out[-1][1] + 1: out[-1][1] = max(out[-1][1], x[1])
        else: out.append(list(x))
    return out
check('model: progress merge joins adjacent and overlapping ranges', merge([[0, 29]], [30, 59]) == [[0, 59]] and merge([[0, 29]], [40, 59]) == [[0, 29], [40, 59]] and merge([[0, 59]], [10, 20]) == [[0, 59]])
check('Swift keys match contract s8 (shots rows, n_shots/n_ready/n_failed/updated_at, failed = error and not ready)', all(k in sw for k in ('"depth_ready"', '"source_ready"', '"ready"', '"failed"', '"error"', '"n_shots"', '"n_ready"', '"n_failed"', '"updated_at"')) and 'err != nil && !ready' in sw)
check('sidecar written before ready/progress; carries depth/source width/height and the runner extra', sw.index('writeAtomic(side, to: Self.sidecarURL') < sw.index('writeReady(); return true') and all(k in sw for k in ('"depth_width"', '"depth_height"', '"source_width"', '"source_height"')))
check('failed shot removes its files so it is never half-ready', 'func fail(shot i: Int' in sw and sw.count('removeItem(at: Self.depthURL(entry, i))') == 1)
check('atomic writes (tmp + replaceItemAt)', 'replaceItemAt(url, withItemAt: tmp)' in sw)
check('spawn: nil without a runner; stop sets the cancel flag; done(false) on throw or cancel', 'guard let runner else { return nil }' in sw and 'cancel.set = true' in sw and 'done(ok && !cancel.set)' in sw)
check('wiring passes the registry runner into the launcher', '{ ThreeDPrepareSpawn.make(runner: ThreeDRunnerRegistry.runner) }' in wi and 'late' in wi)
check('no player-socket words', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', sw, re.I))

check('native runner takes child path, no app-owned CoreML in the spawn', 'runner as? NativePrepareRunner' in sw and 'return PrepareWorker.spawn' in sw)
check('worker owns cache-root exclusive lock for entire prepare; process death releases it', 'flock(fd, LOCK_EX | LOCK_NB)' in sw and 'defer { flock(fd, LOCK_UN) }' in sw)
check('worker cancellation kills process group and result is failure, not automatic restart', 'kill(-p.processIdentifier, SIGKILL)' in sw and '6 * 3600' in sw and 'done(ok)' in sw)
native=sec('NativePrepareRunner'); encoder=sec('VTShotEncoder')
check('restart skips complete shots, resumes checkpoint, proxy temp replaced only on complete', 'let done = Set(shots.indices.filter(ready))' in native and 'ShotPrepare.runResumable' in native and 'shot_%05d.ck' in native and 'writer.status == .completed' in encoder and 'moveItem(at: tmp, to: dest)' in encoder)
# Real OS process/lock/cache contract test, not a Swift/CoreML runtime test.
import subprocess, time, signal, fcntl
with tempfile.TemporaryDirectory() as d:
    d=pathlib.Path(d)
    code = r"""
import fcntl,sys,time,pathlib
p=pathlib.Path(sys.argv[1]);f=open(p/'lock','a')
try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: sys.exit(75)
if sys.argv[2]=='stuck':
 (p/'shot0.ready').write_text('complete');(p/'shot1.ck').write_text('checkpoint');(p/'shot1.mp4.part').write_text('partial');print('ready',flush=True);time.sleep(30)
else:
 assert (p/'shot0.ready').read_text()=='complete'
 assert (p/'shot1.ck').read_text()=='checkpoint'
 (p/'shot1.mp4.part').unlink();(p/'shot1.ready').write_text('complete')
"""
    p=subprocess.Popen([sys.executable,'-c',code,str(d),'stuck'],stdout=subprocess.PIPE,text=True,start_new_session=True)
    check('fake stuck worker starts and writes partial cache/checkpoint',p.stdout.readline().strip()=='ready')
    q=subprocess.run([sys.executable,'-c',code,str(d),'restart'])
    check('second worker cannot steal cache/checkpoint ownership',q.returncode==75)
    t=time.monotonic();os.killpg(p.pid,signal.SIGKILL);p.wait(timeout=2)
    q=subprocess.run([sys.executable,'-c',code,str(d),'restart'])
    check('kill is bounded, lock released, explicit restart keeps complete shot and resumes partial ownership',time.monotonic()-t<2 and q.returncode==0 and (d/'shot1.ready').exists() and (d/'shot0.ready').read_text()=='complete')
sys.exit(1 if bad else 0)
