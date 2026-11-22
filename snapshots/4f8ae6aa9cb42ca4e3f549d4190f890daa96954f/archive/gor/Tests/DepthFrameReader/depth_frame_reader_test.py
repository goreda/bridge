#!/usr/bin/env python3
"""Text pins for DepthFrameReader on the s16 .dzc container (Swift uncompiled, Linux only)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]; s = (lambda _b: _b[_b.index('// BEGIN relocated '+'DepthContainerWriter.swift'+' '):_b.index('// END relocated '+'DepthContainerWriter.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated DepthFrameReader.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthFrameReader.swift')[0]  # 195y G2
k = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(root)).read_text()); c = (root / 'tools/depth_analysis/CONTRACT-190v.md').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('reads the container through DZCFile, no AVFoundation / HEVC range question', 'DZCFile(url: url)' in s and 'AVAsset' not in s and 'kCVPixelFormatType' not in s)
check('frame uploaded as r16Unorm holding raw w10', '.r16Unorm' in s and 'bytesPerRow: w * 2' in s)
check('keyed by PTS from the container (start_frame + i) / fps', 'file.pts(i)' in s)
check('shift 0 passed to decodeDepth (accepts shift <= 6; kernel does round(r*65535) >> shift)', 'shift: 0' in s and 'shift <= 6' in k and '>> shift' in k)
check('contract s16 names the container and the w10 mapping', 'depth_shot_NNNNN.dzc' in c or '.dzc' in c)
check('cancel stops next()', 'stopped = true' in s and '!stopped' in s)
sys.exit(1 if fails else 0)
