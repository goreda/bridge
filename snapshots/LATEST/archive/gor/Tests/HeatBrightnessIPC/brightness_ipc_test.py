#!/usr/bin/env python3
"""Owner log 02:50-02:57 (real gor 2.2.22): (1) 63 DisplayServicesGetBrightness calls/s on the main thread
(278/442 timer samples); (2) mpv 100% CPU with no video, ipc/ipc thread in ipc_write_str->sendto 1502/1527 samples.
Model + source pins. Swift is not compiled here; the call-rate model is not a measurement on a Mac."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import pathlib, sys, re
root = pathlib.Path(__file__).resolve().parents[2]
src = root/'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)

def sim(ttl, hz=120, secs=10.0, reads_per_tick=2):
    """Actuator tick: reads current, writes next (write refreshes cache), reads again."""
    cache_at = None; hw = 0; t = 0.0; dt = 1.0/hz
    def read():
        nonlocal cache_at, hw
        if ttl > 0 and cache_at is not None and 0 <= t-cache_at < ttl: return
        hw += 1; cache_at = t
    while t < secs:
        read()
        # setBrightness stores the written value but keeps the read timestamp (resync every TTL)
        for _ in range(reads_per_tick-1): read()
        t += dt
    return hw/secs
old, new = sim(0), sim(0.25)
print('hardware reads/s: old %.0f new %.1f' % (old, new))
check('old model reproduces the owner order of magnitude (>=60/s)', old >= 60)
check('cached read rate is at most 4/s (1/TTL)', new <= 4.0)
check('hardware is still re-read (resync, not frozen)', new >= 3.0)

pp = _pp_split().text(root,'PPController.swift'); bc = _pp_split().part_text(root,'BrightnessReadCache.swift')
check('getCurrentBrightness serves the cache first', 'if let v = readCache.fresh(CACurrentMediaTime()) { return v }' in pp)
check('TTL is 0.25 s', 'ttl: TimeInterval = 0.25' in bc)
check('writes keep the read timestamp (resync every TTL)', 'entry = (value, entry?.at ?? now)' in bc and 'readCache.wrote(clamped' in pp)
check('hardware read stamps the cache and is counted', 'hardwareReads += 1; entry = (value, now)' in bc and 'readCache.hardwareRead(v' in pp)
check('PPController.swift net 0 lines vs ceiling 6234', len(pp.splitlines()) <= 6234)

q = _s3read(src/'QuitChildKiller.swift')
check('lifeline parent end has a drain read source', 'makeReadSource(fileDescriptor: fd' in q and 'static func makeDrain' in q)
check('drain is resumed after the entry is stored', q.index('entries[key] = Entry(') < q.index('drain.resume()'))
check('fd closes only from the cancel handler', 'setCancelHandler { try? parent.close() }' in q and q.count('try? entry.parentEnd.close()') == 0 and q.count('try? entry?.parentEnd.close()') == 0)
check('EOF lifeline still closes the parent end on stop and on signal', q.count('release(entry)') >= 2)
check('mpv launch args unchanged', '--input-ipc-client=fd://0' in q and '--no-input-terminal' in q)
sys.exit(1 if fails else 0)
