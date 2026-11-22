#!/usr/bin/env python3
"""Owner VR report 03:19: stale auto crop video-crop=8000x722+0+1636 on an 8000x4000 SBS film plus eye aspect ~5.5 fed to vr180-look.
Pins Sources/gor/CropAcceptPolicy.swift and its three PPController call sites, and replays the incident timeline through a Python model of the
onResult gate (drop = nothing applied, no UI crop, no video-crop, no eye aspect)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
pol = (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated CropAcceptPolicy.swift (195y G2, behavior unchanged)\n',1)[1].split('// END relocated CropAcceptPolicy.swift',1)[0]; ppc = (_pp_split().path(root,'PPController.swift')).read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('policy constants', 'maxPlayheadDrift: Double = 60' in pol and 'minKeptFraction: Double = 0.55' in pol)
check('policy: stream drift rule exempts manual redetect', 'if rect != nil, stream, !manual, let s = startPlayhead, abs(nowPlayhead - s) > maxPlayheadDrift' in pol)
check('policy: stereo plausibility on both axes', 'Double(r.width) >= minKeptFraction && Double(r.height) >= minKeptFraction' in pol)
gate = ppc[ppc.index('cropDetector.onResult = {'):]; gate = gate[:gate.index('let early')]
check('onResult: policy gate precedes result handling; detector never overwrites source eye aspect', 'CropAcceptPolicy.accepts(' in gate and 'acceptSourceEyeAspect' not in ppc[ppc.index('cropDetector.onResult = {'):ppc.index('cropDetector.onStatus = {')])
check('onResult: stereo = decoded source or scanner measured per-eye halves', 'stereo: self.cropDetector.stereoSBS || self.cropDetector.perEyeAspect != nil' in gate and 'manual: self.manualRedetectInFlight' in gate and 'stream: CropDetector.isWTPlayback(self.currentFilePath)' in gate)
rr = ppc[ppc.index('private func requestRealCrop'):]; rr = rr[:rr.index('let w=cropDetector')]
check('requestRealCrop: pixel bounds validated and no detector eye-aspect feed', 'CropInvariant.fits(' in ppc[ppc.index('private func requestRealCrop'):ppc.index('private func sendOsdChainQuery')] and 'acceptSourceEyeAspect' not in ppc)
check('automatic scan start records the playhead', 'triggering"); CropScanGuard.shared.begin(playhead: currentTime)' in ppc)
def accepts(rect, stereo, start, now, stream, manual, drift=60.0, kept=0.55):
    if rect is not None and stream and not manual and start is not None and abs(now - start) > drift: return False
    if rect is not None and stereo and not (rect[0] >= kept and rect[1] >= kept): return False
    return True
def on_result(rect, **kw):   # returns actions taken
    if not accepts(rect, **kw): return []
    acts = ['revert'] if rect is None else ['ui_crop', 'video_crop']
    return acts
W, H = 8000, 4000; bad = (1.0, 722 / H)
inc = on_result(bad, stereo=True, start=244.0, now=1632.0, stream=True, manual=False)
check('incident (stream scan 244 s -> 1632 s, 8000x722 of 8000x4000): nothing applied', inc == [])
check('same rect without drift is still refused on a stereo film (keeps %.1f%% of height)' % (bad[1]*100), on_result(bad, stereo=True, start=1632.0, now=1640.0, stream=True, manual=False) == [])
check('same rect on a stereo film via a non-stream file: refused', on_result(bad, stereo=True, start=0.0, now=2000.0, stream=False, manual=False) == [])
check('recovery: rescan from the new playhead finds the full frame (no bars) -> accepted without source-aspect mutation', on_result(None, stereo=True, start=1632.0, now=1700.0, stream=True, manual=False) == ['revert'])
check('legit SBS letterbox (1920x800 of 1920x1080 per eye) is accepted', on_result((1.0, 800 / 1080), stereo=True, start=10.0, now=70.0, stream=True, manual=False) == ['ui_crop', 'video_crop'])
check('flat 2D film with a deep letterbox (2.76:1 in 16:9) is untouched by the stereo rule', on_result((1.0, 0.64), stereo=False, start=0.0, now=5.0, stream=False, manual=False) != [])
check('flat 2D stream, drift: dropped (samples are from another part of the film)', on_result((1.0, 0.8), stereo=False, start=0.0, now=500.0, stream=True, manual=False) == [])
check('manual redetect is exempt from drift (user asked at this playhead)', on_result((1.0, 0.8), stereo=False, start=0.0, now=500.0, stream=True, manual=True) != [])
check('"no bars" result is never dropped for drift', on_result(None, stereo=True, start=0.0, now=900.0, stream=True, manual=False) == ['revert'])
print('crop accept policy: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
