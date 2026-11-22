#!/usr/bin/env python3
"""DZCFile layout rules (Python model of the Swift isComplete/offsets logic) against the pinned golden .dzc, plus text pins. Swift uncompiled."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
s = (lambda _b: _b[_b.index('// BEGIN relocated '+'DepthContainerWriter.swift'+' '):_b.index('// END relocated '+'DepthContainerWriter.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated DepthContainerReader.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthContainerReader.swift')[0]  # 195y G2
g = root / 'Tests/DepthAnalysis/parity'
b = (g / 'dzc_golden.dzc').read_bytes(); meta = json.loads((g / 'dzc_golden.json').read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def u(b, o, n): return int.from_bytes(b[o:o + n], 'little')
def layout(b):  # DZCFile.layout
    if len(b) < 72 or b[:8] != b'GORDZ001' or u(b, 8, 2) != 1 or u(b, 10, 2) != 1: return None
    n = u(b, 52, 4)
    if n == 0: return None
    tail = n * 8 + 8
    if len(b) < 64 + tail or b[-8:] != b'GORDZEND': return None
    offs = [u(b, len(b) - tail + i * 8, 8) for i in range(n)]
    return n, offs if all(64 <= o and o + 8 <= len(b) - tail for o in offs) else None
r = layout(b)
check('golden container is complete and every offset lands on a record', r is not None and r[1] is not None)
n, offs = r
check('golden frame count matches its json', n == meta.get('n_frames', n))
check('records are contiguous: offset i + 8 + len == offset i+1 (last ends at the index)', all(offs[i] + 8 + u(b, offs[i], 4) == offs[i + 1] for i in range(n - 1)) and offs[-1] + 8 + u(b, offs[-1], 4) == len(b) - (n * 8 + 8))
check('truncated file (no index/trailer) is incomplete', layout(b[:offs[-1]]) is None and layout(b[:-1]) is None)
check('header-only file is incomplete', layout(b[:64]) is None)
check('Swift: trailer, size and offset-range checks', 'DZC.trailer' in s and 'd.count >= DZC.headerSize + tail' in s and 'allSatisfy' in s)
check('Swift: crc verified and any valid LZFSE accepted via injected codec', 'DZC.crc32(raw) == crc' in s and 'decompress: ([UInt8], Int) -> [UInt8]?' in s)
check('Swift: pts = (start_frame + i) / fps', 'Int(meta.startFrame) + i' in s and 'fpsNum' in s)
sys.exit(1 if fails else 0)
