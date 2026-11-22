#!/usr/bin/env python3
"""190t native prepare runner math (Sources/gor/gor/ThreeD.swift (DepthPrepareMath.swift section)). The Swift file is pure Foundation, so this test COMPILES AND RUNS IT here
(swiftc from $SWIFTC / PATH) and checks it against the Python references: tools/depth_analysis/align.py (ShotAligner), synthetic pinhole ground truth for the MoGe focal/shift recovery
(same 64x64 nearest downsample; upstream scipy shown for information) and prepare_film's quantiser. CoreML/Metal are NOT exercised here (Mac only).
If no swiftc is found the numeric checks are reported SKIPPED (not passed)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, shutil, subprocess, sys, tempfile
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'tools/depth_analysis'))
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'tools/depth_analysis'))
from align import ShotAligner
fails = []; skipped = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
src = (lambda _b: _b[_b.index('// BEGIN relocated '+'DepthPrepareMath.swift'+' '):_b.index('// END relocated '+'DepthPrepareMath.swift'+'\n')])((_threed_split().path(root)).read_text())
check('text pins: min pairs 16, rint half-even, 64x64 nearest, +inf mask', all(p in src for p in ('static let minPairs = 16', '.rounded(.toNearestOrEven)', 'down: (h: Int, w: Int) = (64, 64)', 'Float.infinity')))
vda = (lambda _b: _b[_b.index('// BEGIN relocated '+'VDAStreamRunner.swift'+' '):_b.index('// END relocated '+'VDAStreamRunner.swift'+'\n')])((_threed_split().path(root)).read_text())
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swiftc or not os.path.exists(swiftc):
    print('SKIPPED numeric checks: no swiftc'); skipped.append('numeric')
    check('(review) VDA output floats() honours MLMultiArray strides (padded outputs fall back to logical-index reads)', 'if !packed { return (0..<n).map { a[$0].floatValue } }' in vda and 'a.strides.map { $0.intValue }' in vda)
    print('depth prepare math: %d failure(s), numeric SKIPPED' % len(fails)); sys.exit(1 if fails else 0)
tmp = pathlib.Path(tempfile.mkdtemp()); exe = tmp / 'dpm'
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text('import Foundation\n' + b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])   # some sections carry no import line of their own
    return p
# PrepareSupport.swift nests PrepareWorkerJob.swift, whose `request` names ThreeDPrepareLauncher.Request: pull the launcher and its
# deps in too (same Linux shim shape as Tests/DarwinTypecheck LIN for corelibs' missing ProcessInfo.thermalState).
lin = tmp / 'lin.swift'
lin.write_text('import Foundation\n'
               'extension ProcessInfo { enum ThermalState: Int { case nominal, fair, serious, critical }; var thermalState: ThermalState { .nominal }\n'
               '  static let thermalStateDidChangeNotification = Notification.Name("x") }\n')
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'DepthPrepareMath.swift')), str(_sec_file(root,'DepthGuards.swift')), str(_sec_file(root,'ShotComfort.swift')), str(_sec_file(root,'FovTrackBuilder.swift')), str(_sec_file(root,'MoGeKeyframeRunner.swift')), str(_sec_file(root,'DepthContainerWriter.swift')), str(_sec_file(root,'VDAStreamRunner.swift')), str(_sec_file(root,'ShotPrepareAssembly.swift')), str(_sec_file(root,'SourceFormat.swift')), str(root / 'Tests/DepthPrepareMath/DegradeStub.swift'), str(_sec_file(root,'PrepareSupport.swift')), str(_sec_file(root,'ThreeDExperimentOptions.swift')), str(_sec_file(root,'CoreMLDepthRunner.swift')), str(_sec_file(root,'KitCompiledCache.swift')), str(_sec_file(root,'PrepareTelemetry.swift')), str(_sec_file(root,'ThreeDSelfTest.swift')), str(_sec_file(root,'ThreeDThermalGate.swift')), str(_sec_file(root,'ThreeDStageLog.swift')), str(_sec_file(root,'FilmPrepareStatus.swift')), str(_sec_file(root,'DepthCacheBudget.swift')), str(_sec_file(root,'PrepareProcessLifetime.swift')), str(_sec_file(root,'ThreeDPrepareSpawn.swift')), str(_sec_file(root,'ThreeDPrepareLauncher.swift')), str(lin), str(root / 'Tests/DepthPrepareMath/main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('Swift file compiles (Linux, Foundation only)', r.returncode == 0)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
def run(*a): return subprocess.run([str(exe), *map(str, a)], capture_output=True, text=True, check=True).stdout.split('\n')
rng = np.random.default_rng(3)
# --- quantiser (prepare_film.write_depth_hevc formula, float32, np.rint)
z = np.concatenate([[0.0, 1e-3, 0.0011, 0.25, 0.2501, 0.5, 1.0, 2.5, 100.0, 5000.0, np.inf, np.nan, -3.0], rng.uniform(0.3, 60, 500)]).astype(np.float32)
def q_ref(z):
    ok = np.isfinite(z) & (z > 1e-3); inv = np.where(ok, 256.0 / np.maximum(np.where(ok, z, 1.0), 1e-3), 0.0).astype(np.float32)
    return np.clip(np.rint(inv / np.float32(1024.0) * np.float32(1023.0)), 0, 1023).astype(np.uint16)
z.tofile(tmp / 'z.f32'); got = np.array([int(x) for x in run('quant', tmp / 'z.f32') if x], np.uint16)
check('quantiser equals prepare_film formula on %d values (incl. 0/inf/nan/negative)' % z.size, (got == q_ref(z)).all())
check('Z=0.25 m -> 1023, masked -> 0', got[3] == 1023 and got[0] == 0 and got[10] == 0 and got[11] == 0)
# --- shot aligner vs align.ShotAligner (with +inf sky, a too-few-pairs frame, EMA)
T, N = 14, 900
vda = rng.uniform(0, 1, (T, N)).astype(np.float32); moge = (vda * 6.0 + 2.0 + rng.normal(0, 0.05, (T, N))).astype(np.float32)
moge[3, :200] = np.inf; moge[5, :] = np.nan; moge[6, 10:] = np.inf       # sky inf, an all-nan frame, a frame with only 10 finite pairs
vda.tofile(tmp / 'v.f32'); moge.tofile(tmp / 'm.f32')
rows = [list(map(float, l.split())) for l in run('align', T, N, tmp / 'v.f32', tmp / 'm.f32') if l]
al = ShotAligner(ema=0.9); ok = True; worst = 0.0
for i in range(T):
    al.update(vda[i], moge[i]); s, b, sk = rows[i]
    if i == 0 and al.scale is None: ok &= np.isnan(s)
    else: worst = max(worst, abs(s - al.scale), abs(b - al.shift)); ok &= int(sk) == al.skipped
check('aligner: scale/shift per frame match align.py to %.1e, skip counts equal (%d skipped)' % (worst, al.skipped), ok and worst < 1e-5 and al.skipped == 2)
# --- s30 eased per-keyframe application vs align.apply_align_track (scale and shift separately, None entries, causality = seek rule)
from align import apply_align_track
def track_case(T, kfs, dflt):
    args = ['nil' if x is None else repr(x) for x in ()]
    rows = [list(map(float, l.split())) for l in run('track', T, repr(dflt[0]), repr(dflt[1]), *['%d:%s:%s' % (k, 'nan' if sc is None else repr(sc), 'nan' if sh is None else repr(sh)) for k, sc, sh in kfs]) if l]
    return np.array(rows)
worst = 0.0; okt = True; okc = True
for case in range(6):
    T = int(rng.integers(30, 90)); ks = [0] + sorted(rng.choice(np.arange(1, T), size=int(rng.integers(0, 5)), replace=False).tolist() if T > 6 else [])
    kfs = [(k, float(rng.uniform(0.5, 5)), float(rng.uniform(-2, 2))) for k in ks]
    if case == 4: kfs[0] = (0, None, None)
    if case == 5: kfs = []
    dflt = (1.7, 0.3)
    got = track_case(T, kfs, dflt) if True else None
    sc = apply_align_track(np.ones((T, 1, 1)), kfs, default=dflt)[:, 0, 0]; sh = apply_align_track(np.zeros((T, 1, 1)), kfs, default=dflt)[:, 0, 0]
    want_s, want_b = sc - sh, sh
    worst = max(worst, np.abs(got[:, 0] - want_s).max(), np.abs(got[:, 1] - want_b).max())
    # causal / seek: params at frame f from the track truncated to keyframes <= f equal the full-track params
    for f in range(0, T, 7):
        part = [e for e in kfs if e[0] <= f]
        if part: okc &= np.allclose(track_case(f + 1, part, dflt)[f], got[f], atol=1e-12)
check('s30 eased align track equals align.apply_align_track (6 random tracks incl. None entries and empty), max dev %.1e' % worst, worst < 1e-12)
check('s30 seek rule: params at frame f depend only on keyframes <= f (truncated track reproduces them)', okc)
# --- s31 real-time budget notes from measured stage totals
bud = {l.split(' ', 1)[0]: l.split(' ', 1)[1] for l in run('budget', 36, 14.0, 30.0, 3) if l}
check('s31 budget notes from stage totals: VDA 14.00/frame, MoGe 40.00/kf (max 60.00), amortised 3.33, model pair 17.33 -> 24/30 fit, 60 fps BREAKS (16.67), burst > a 60 fps frame',
      bud['rt_vda_ms_per_frame'].startswith('14.00') and bud['rt_moge_ms_per_keyframe'].startswith('40.00 max 60.00') and bud['rt_moge_ms_amortized'].startswith('3.33') and bud['rt_model_ms_per_frame'].startswith('17.33')
      and 'fits' in bud['rt_budget_24fps'] and 'fits' in bud['rt_budget_30fps'] and 'BREAKS' in bud['rt_budget_60fps'] and 'exceeds' in bud['rt_keyframe_burst_vs_frame_60fps'])
# --- s32 rtstage/rt_config lines: the Swift emitter's output is parsed and judged by A-D's selftest_check (the real comparator)
sys.path.insert(0, str(root / 'tools/depth_analysis')); import selftest_check as sc
probe_src = (root / 'Sources/gor/Stereo/RealtimeProbe.swift').read_text(); import re as _re
cfg = _re.search(r'tel\.note\("rt_config", "([^"]+)"\)', probe_src).group(1)
def rt_judge(means):
    lines = [l for l in run('rtlines', cfg, *means) if l]; runs = sc.parse_runs(lines); r = runs[-1] if isinstance(runs, list) else runs
    return lines, sc.check_rt(r)
lines, (tbl, fl) = rt_judge(['9.5', '31.0', '0.004', '0.41', '0.012', '1.3', '1.1'])
check('s32: Swift rtstage lines (all 7 stages + rt_config "%s") parse in selftest_check with 0 failures; stages in emit order' % cfg, not fl and [l.split('rtstage name=')[1].split()[0] for l in lines if 'rtstage ' in l] == ['vda', 'moge', 'upsample', 'surround', 'render', 'vt_decode', 'vt_encode'])
lines, (tbl, fl) = rt_judge(['9.5', '31.0', '0.004', '-', '0.012', '1.3', '1.1'])
check('s32: a missing stage (surround) FAILS loudly in the comparator', any('surround' in f and 'MISSING' in f for f in fl))
# --- MoGe focal/shift recovery vs scipy reference and ground truth
from scipy.optimize import least_squares
def ref_solve(uv, xyz):
    uv, xy, zz = uv.reshape(-1, 2), xyz[..., :2].reshape(-1, 2), xyz[..., 2].reshape(-1)
    def fn(s):
        p = xy / (zz + s)[:, None]; f = (p * uv).sum() / (p * p).sum(); return (f * p - uv).ravel()
    sol = least_squares(fn, x0=0, ftol=1e-3, method='lm'); s = float(np.squeeze(sol['x'])); p = xy / (zz + s)[:, None]
    return s, float((p * uv).sum() / (p * p).sum())
def uv_grid(w, h):
    a = w / h; sx, sy = a / (1 + a * a) ** .5, 1 / (1 + a * a) ** .5
    u = np.linspace(-sx * (w - 1) / w, sx * (w - 1) / w, w); v = np.linspace(-sy * (h - 1) / h, sy * (h - 1) / h, h)
    return np.stack(np.meshgrid(u, v, indexing='xy'), -1)
def hfov_of(f, w, h):
    a = w / h; fx = f / 2 * (1 + a * a) ** .5 / a; return float(np.degrees(2 * np.arctan(0.5 / fx)))
for (h, w, fov, shift) in ((72, 128, 60.0, 1.3), (96, 96, 90.0, 0.4), (80, 192, 38.0, 2.5)):
    a = w / h; fx = 0.5 / np.tan(np.radians(fov) / 2); focal = fx * 2 * a / (1 + a * a) ** .5
    Z = (3.0 + 2.0 * np.sin(np.linspace(0, 6, w))[None, :] + 1.0 * np.cos(np.linspace(0, 4, h))[:, None]).astype(np.float64)
    uv = uv_grid(w, h); xy = uv * Z[..., None] / focal; pts = np.concatenate([xy, (Z - shift)[..., None]], -1).astype(np.float32)
    pts.tofile(tmp / 'p.f32'); f_s, s_s, fov_s = map(float, run('focal', h, w, tmp / 'p.f32')[0].split())
    iy = np.minimum(h - 1, np.arange(64) * h // 64); ix = np.minimum(w - 1, np.arange(64) * w // 64)
    s_r, f_r = ref_solve(uv_grid(w, h)[iy][:, ix], pts[iy][:, ix].astype(np.float64))
    check('%dx%d fov %.0f shift %.1f: Swift shift %.4f focal-> hfov %.3f (truth %.1f; upstream scipy ftol=1e-3 gives shift %.3f, info only, hfov %.1f)' % (h, w, fov, shift, s_s, fov_s, fov, s_r, hfov_of(f_r, w, h)),
          abs(s_s - shift) < 2e-3 and abs(fov_s - fov) < 0.1)
    # scipy 'lm' with ftol=1e-3 from x0=0 (what upstream calls) stalls at ~0 on these exact-geometry scenes; the Swift solver converges to the truth, so truth is the criterion
# masked (sky) recovery: 30% of the points are garbage and masked out
h, w, fov, shift = 72, 128, 60.0, 1.3; a = w / h; fx = 0.5 / np.tan(np.radians(fov) / 2); focal = fx * 2 * a / (1 + a * a) ** .5
Z = (3.0 + 2.0 * np.sin(np.linspace(0, 6, w))[None, :] + np.cos(np.linspace(0, 4, h))[:, None]); uv = uv_grid(w, h)
pts = np.concatenate([uv * Z[..., None] / focal, (Z - shift)[..., None]], -1).astype(np.float32); mask = np.ones((h, w), np.float32); mask[:22] = 0; pts[:22] = 1e4
pts.tofile(tmp / 'p.f32'); mask.tofile(tmp / 'k.f32'); f_s, s_s, fov_s = map(float, run('focal', h, w, tmp / 'p.f32', tmp / 'k.f32')[0].split())
check('masked 30%% garbage rows: shift %.4f hfov %.3f (truth 1.3 / 60)' % (s_s, fov_s), abs(s_s - 1.3) < 5e-3 and abs(fov_s - 60) < 0.1)
# --- FoV track entry vs prepare_film._analyze_shot rules
for kfs in ([(0, 51.0), (12, 49.0), (24, 55.0), (36, 44.0)], [(0, 60.0)], [], [(0, 50.0), (12, 80.0)], [(0, 50.0), (12, float('nan')), (24, 52.0)]):
    out = run('fov', 24, 230, 24.0, *['%d:%r' % k for k in kfs]); p = out[0].split()
    good = [f for _, f in kfs if np.isfinite(f)]
    exp_conf = (1.0 - min(1.0, float(np.std(good)) / 15.0)) if len(good) >= 2 else 0.0
    exp_h = float(np.median(good)) if len(good) >= 2 else (good[0] if good else None)
    ok = abs(float(p[3]) - exp_conf) < 1e-12 and ((exp_h is None and p[2] == 'nil') or (exp_h is not None and abs(float(p[2]) - exp_h) < 1e-12))
    check('fov entry %s -> hfov %s conf %.4f' % (kfs, p[2], float(p[3])), ok and abs(float(p[0]) - 1.0) < 1e-12 and abs(float(p[1]) - 230 / 24.0) < 1e-12)
check('keyframe indices stride 12 (207 frames -> 18 keyframes)', run('fov', 0, 206, 24.0, '0:50')[1].split(',') == [str(i) for i in range(0, 207, 12)])
# --- MoGe input normalisation (ImageNet mean/std, CHW) against numpy
n = 518 * 518; i = np.arange(n); px = np.zeros((n, 3), np.float64); px[:, 0] = i % 256; px[:, 1] = (i // 7) % 256; px[:, 2] = (i // 13) % 256
mean = np.array([0.485, 0.456, 0.406]); sd = np.array([0.229, 0.224, 0.225]); ref = (px / 255.0 - mean) / sd
rows = [list(map(float, l.split())) for l in run('chw') if l]
check('MoGe input CHW normalisation equals numpy (4 probe pixels x 3 channels)', all(np.allclose(r, ref[j], atol=1e-5) for r, j in zip(rows, (0, 1, 777, 268323))))
check('keyframe runner pins: fp32 fallback, 518 input, enumerated-shape picker', all(p in (lambda _b: _b[_b.index('// BEGIN relocated '+'MoGeKeyframeRunner.swift'+' '):_b.index('// END relocated '+'MoGeKeyframeRunner.swift'+'\n')])((_threed_split().path(root)).read_text()) for p in ('fp32', 'static let size = 518', 'validFraction >= 0.02', 'struct Package', 'MoGeInput.pick')))
# --- shape picker: aspect-aware, square package never chosen for a film frame unless the frame is square
for (sw, sh_, want) in ((1920, 1080, '518 294'), (3840, 1608, '518 294'), (1440, 1080, '518 364'), (1080, 1920, '392 518'), (4096, 4096, '518 518'), (1920, 800, '518 294')):
    got = run('pick', sw, sh_)[0]
    check('shape for %dx%d (aspect %.2f) -> %s' % (sw, sh_, sw / sh_, got), got == want)
# --- multistart: A-D parity fixture (contract s15), regenerated from (h, w, hfov, shift)
import json
fx = json.loads((root / 'Tests/DepthAnalysis/parity/moge_recovery.json').read_text()); print('recovery fixture keys:', [k for k in fx if k not in ('spec',)][:6])
# --- .dzc: Swift layout vs depth_container.py, byte for byte, with the reference LZFSE payloads
try:
    import types; _pf = types.ModuleType('prepare_film'); _pf.D_SCALE = 256.0; _pf.V_INV_MAX = 1024.0; sys.modules.setdefault('prepare_film', _pf)   # depth_container only needs these two constants (the real module pulls in torch)
    import lzfse, depth_container as dc
    have = True
except Exception as e:
    have = False; print('SKIPPED dzc byte-identity: python lzfse/depth_container unavailable (%s)' % e)
if have:
    for (dh, dw, nfr, fps, start) in ((5, 7, 4, 24.0, 96), (6, 8, 3, 23.976, 0)):
        zs = rng.uniform(0.2, 80, (nfr, dh, dw)).astype(np.float32); zs[0, 0, 0] = np.inf; zs[1, 1, 1] = 0.0
        pdz = tmp / ('ref%d.dzc' % dh); dc.write(str(pdz), zs, 2, fps, start)
        planes = [dc.quantise(zs[i]) for i in range(nfr)]; blobs = [lzfse.compress(p.astype('<u2').tobytes()) for p in planes]
        (tmp / 'z.f32').write_bytes(zs.tobytes()); (tmp / 'blobs.bin').write_bytes(b''.join(blobs)); (tmp / 'lens.txt').write_text(' '.join(str(len(b)) for b in blobs))
        fn, fd = dc._fps_pair(fps); out = tmp / ('swift%d.dzc' % dh)
        res = run('dzc-assemble', out, 2, fn, fd, start, dh, dw, nfr, tmp / 'z.f32', tmp / 'blobs.bin', tmp / 'lens.txt')[0]
        check('dzc %dx%d x%d fps %.3f: Swift writer bytes == depth_container.write bytes (%d B)' % (dh, dw, nfr, fps, pdz.stat().st_size), res == 'true' and out.read_bytes() == pdz.read_bytes())
        inv, meta, pts0 = dc.read(str(out)); check('dzc read back by the Python reader: lossless w10, pts base %.4f' % pts0, np.allclose(inv, np.stack([dc.dequantise(p)[:dh, :dw] for p in planes])) and meta['start_frame'] == start)
    z1 = rng.uniform(0.2, 80, (5, 7)).astype(np.float32); (tmp / 'z1.f32').write_bytes(z1.tobytes()); run('dzc-quant', tmp / 'z1.f32', 5, 7, tmp / 'q.u16')
    check('Swift quantise (odd HxW edge pad) == depth_container.quantise', (tmp / 'q.u16').read_bytes() == dc.quantise(z1).astype('<u2').tobytes())
    g = pathlib.Path(root / 'Tests/DepthAnalysis/parity/dzc_golden.dzc').read_bytes()
    gj = json.loads((root / 'Tests/DepthAnalysis/parity/dzc_golden.json').read_text())
    check('golden .dzc: python crc list matches header record count', len(gj['frame_crc32']) == gj['n_frames'])
so = run('dzc-selftest', tmp / 'self.dzc')
check('resume: partial record cut, valid prefix kept (2), then finished with index + trailer: %s' % so[:3], so[0] == 'resumed 2' and so[1] == 'finished true' and so[2].startswith('frames 5 tail true trailerAt true'))
check('LZFSE via Compression framework is the default codec (Mac only, unrun here)', 'COMPRESSION_LZFSE' in (lambda _b: _b[_b.index('// BEGIN relocated '+'DepthContainerWriter.swift'+' '):_b.index('// END relocated '+'DepthContainerWriter.swift'+'\n')])((_threed_split().path(root)).read_text()))
# --- VDA window state vs vda_stream_common.WindowState (upstream frame_cache_list logic), 100 frames
import types
_cv = types.ModuleType('cv2'); sys.modules.setdefault('cv2', _cv)
import vda_stream_common as vsc; vsc.cv2 = _cv
ws = vsc.WindowState(lambda xs, axis: np.concatenate(xs, axis=axis)); exp = []
for k in range(100):
    bun = [np.full((2, 1, 3), k, np.float32), np.full((1, 1, 2), k, np.float32)]
    if ws.is_first(): ws.start(bun); exp.append('%d first' % k)
    else:
        cur = ws.build_cur_cache()[0]; ids = ','.join(str(int(v)) for v in cur[0, :, 0]); exp.append('%d %s tok1same' % (k, ids)); ws.advance(bun)
got = [x for x in run('vdawin', 100) if x]
check('VDA window state: 100-frame anchor+rolling cache order identical to vda_stream_common (frame ids on the T axis)', got == exp)
c = run('vdachw', 255, 0, 0, 255, 0, 0, 255, 255)[0].split()
mean, sd = vsc._MEAN, vsc._STD; want = [(1 - mean[0]) / sd[0], (0 - mean[0]) / sd[0], (0 - mean[1]) / sd[1], (0 - mean[1]) / sd[1], (0 - mean[2]) / sd[2], (1 - mean[2]) / sd[2]]
check('VDA ImageNet CHW normalisation equals vda_stream_common', np.allclose([float(x) for x in c], want, atol=1e-6))
# --- per-shot assembly (s19): unsuspended vs suspended+resumed through serialised checkpoints must be bit-identical
def shotprep(name, n, sus):
    d = tmp / name; d.mkdir(exist_ok=True)
    out = [x for x in run('shotprep', d, n, sus) if x]
    return out, (d / 's.dzc').read_bytes(), (d / 's.spool').exists()
n_fr = 30
o1, b1, sp1 = shotprep('plain', n_fr, '-')
o2, b2, sp2 = shotprep('susp', n_fr, '4,12,13,25')
check('shot prepare: 4 suspend/resume cycles through encode/decode checkpoint (fresh backend each time): .dzc bytes identical to the unsuspended run (%d B)' % len(b1), b1 == b2 and 'suspends 4' in o2[0] and 'suspends 0' in o1[0])
check('shot prepare: spool removed after the container is finished', not sp1 and not sp2)
tok = o1[0].split(); sc, sh = float(tok[tok.index('scale') + 1]), float(tok[tok.index('shift') + 1])
check('shot prepare: per-shot scale/shift recovered through MoGe 37x21 -> VDA 266x154 resampling with masked inf (scale %.4f shift %.4f, truth 2/0.5)' % (sc, sh), abs(sc - 2) < 0.03 and abs(sh - 0.5) < 0.06 and 'kf 3' in o1[0])
f = o1[1].split(); check('shot prepare: fov entry median %s over %s keyframes, pts %s..%s' % (f[1], f[3], f[4], f[5]), abs(float(f[1]) - 61.2) < 1e-6 and f[3] == '3' and abs(float(f[4]) - 100 / 24) < 1e-9)
# ShotSink contract: boundary before the shot + every frame boundary, model lane around every model call, cancel -> persisted checkpoint -> fresh-process resume
dk = tmp / 'kill'; dk.mkdir(exist_ok=True)
ok_ = [x for x in run('shotkill', dk, n_fr, 12) if x]
check('ShotSink wiring: boundary before the shot + each frame boundary, model lane around every model call, cancel at #12 ran the checkpoint closure and left a checkpoint file (%s)' % ok_[0], ok_[0] == 'first true boundaries 12 lane 12 cp 1 ckfile true')
check('ShotSink wiring: fresh process resumes from the persisted checkpoint (%s) and its .dzc is byte-identical to the unsuspended run' % ok_[1], ok_[1].startswith('resumed done') and ok_[1].endswith('ckfile false') and (dk / 's.dzc').read_bytes() == b1)
# --- s35 guards wired through ShotPrepare.run (GuardFake: luma stream + MoGe +inf sky rows + static overlay block); weighted fit off so the unguarded pixels stay comparable
def guardprep(flags):
    d = tmp / ('guard' + flags); d.mkdir(exist_ok=True)
    out = [x for x in run('guardprep', d, 48, flags) if x]
    fr = np.array([[float(v) for v in l.split()[2:]] for l in out if l.startswith('f ')]); return out, fr
go, g_off = guardprep('000'); _, g_sky = guardprep('010'); _, g_ov = guardprep('001'); go_all, g_all = guardprep('011'); go_full, g_full = guardprep('111')
check('s35 guards: 48-frame fake shot ran with guards off/sky/overlay/both/all-three (%d frames each)' % len(g_off), all(len(g) == 48 for g in (g_off, g_sky, g_ov, g_all, g_full)))
check('s35 sky clamp: the MoGe-invalid flat top pixel moves to the far plane in every frame (%.3f -> %.3f at f0) and no other probed pixel changes' % (g_off[0, 0], g_sky[0, 0]), np.all(g_sky[:, 0] > g_off[:, 0] + 0.05) and np.array_equal(g_sky[:, 1:], g_off[:, 1:]))
check('s35 overlay flatten: the static block lands on ONE screen-plane depth in every frame (%.3f, was %.3f..%.3f) and the rest of the picture is unchanged' % (g_ov[0, 1], g_off[:, 1].min(), g_off[:, 1].max()),
      np.ptp(g_ov[:, 1]) == 0 and np.ptp(g_off[:, 1]) > 0.1 and np.allclose(g_ov[:, [0, 2, 3]], g_off[:, [0, 2, 3]], atol=1e-3) and 3.0 < g_ov[0, 1] < 3.8)
check('s35 guards combined: sky clamp and overlay flatten both active, ground probes unchanged', np.all(g_all[:, 0] > g_off[:, 0] + 0.05) and np.ptp(g_all[:, 1]) == 0 and np.allclose(g_all[:, 2:], g_off[:, 2:], atol=1e-3))
check('s35 all guards (incl. texture-weighted fit): finite output, scale/shift still near truth (%s)' % go_full[0], np.isfinite(g_full).all() and abs(float(go_full[0].split()[1]) - 2) < 0.1)
# decode the identity-coded container and compare plane 0 with depth_container.quantise of the true metres
import struct
hdr = b1[:64]; plane_bytes = struct.unpack_from('<I', hdr, 60)[0]; w_, h_ = struct.unpack_from('<II', hdr, 32)[0:2]
ln, crc = struct.unpack_from('<II', b1, 64); pl = np.frombuffer(b1[72:72 + ln], '<u2')
zt = np.fromfunction(lambda y, x: 3 + 0.4 * (x + .5) / 266 + 0.3 * (y + .5) / 154, (154, 266)).astype(np.float32)
import zlib
check('shot prepare: plane 0 crc ok and within 3 w10 codes of quantise(true metres) (max dev %d)' % np.abs(pl.astype(int) - dc.quantise(zt).astype(int).ravel()).max(), zlib.crc32(pl.tobytes()) == crc and np.abs(pl.astype(int) - dc.quantise(zt).astype(int).ravel()).max() <= 3) if have else None
check('thermal gate: suspend at fair, hold until 60 s AND 30 s cool dwell, flap resets the dwell', run('gate', '0,0', '1,10', '0,20', '0,50', '0,69', '0,71', '1,80', '0,90', '0,119', '0,121', '0,125', '0,150', '0,155')[0] == 'run hold hold hold hold run hold hold hold hold hold run run')
# --- s18 cuts: A-D parity fixture + the scdet score against ffmpeg itself
cj = json.loads((root / 'Tests/DepthAnalysis/parity/cut_detect.json').read_text()); cc = cj['case']
o = run('cuts', cc['fps'], cc['n_frames'], *cc['times_s'])[0].split(' ')
check('cuts: fixture case frames %s and ranges equal cut_detect.json' % o[0], o[0] == ','.join(map(str, cc['expect_cut_frames'])) and o[1] == ','.join('%d-%d' % tuple(r) for r in cc['expect_ranges']))
for e in cj['edge_cases']:
    o = run('cuts', e['fps'], e['n_frames'], *e['times_s'])[0].split(' ')
    check('cuts: edge case times %s -> ranges %s' % (e['times_s'], e['expect_ranges']), o[1] == ','.join('%d-%d' % tuple(r) for r in e['expect_ranges']))
if shutil.which('ffmpeg'):
    cd = tmp / 'scd'; cd.mkdir(exist_ok=True); W_, H_ = 64, 48
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=64x48:rate=24:duration=1', '-f', 'lavfi', '-i', 'mandelbrot=size=64x48:rate=24', '-f', 'lavfi', '-i', 'smptebars=size=64x48:rate=24',
                    '-filter_complex', '[0:v]trim=duration=1,setpts=PTS-STARTPTS[a];[1:v]trim=duration=1,setpts=PTS-STARTPTS[b];[2:v]trim=duration=1,setpts=PTS-STARTPTS[c];[a][b][c]concat=n=3:v=1,format=yuv420p', '-r', '24', '-pix_fmt', 'yuv420p', str(cd / 'clip.mp4')], check=True)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(cd / 'clip.mp4'), '-f', 'rawvideo', '-pix_fmt', 'yuv420p', str(cd / 'raw.yuv')], check=True)
    subprocess.run(['ffmpeg', '-v', 'error', '-i', str(cd / 'clip.mp4'), '-vf', 'scdet=threshold=12,metadata=print:file=' + str(cd / 'meta.txt'), '-f', 'null', '-'], check=True)
    import re
    meta = (cd / 'meta.txt').read_text(); fm = [float(x) for x in re.findall(r'scd.mafd=([\d.]+)', meta)]; fs_ = [float(x) for x in re.findall(r'scd.score=([\d.]+)', meta)]
    ft = [float(x) for x in re.findall(r'lavfi.scd.time: ([0-9.]+)', subprocess.run(['ffmpeg', '-hide_banner', '-i', str(cd / 'clip.mp4'), '-vf', 'scdet=threshold=12', '-f', 'null', '-'], capture_output=True, text=True).stderr)]
    so = [x for x in run('scd', cd / 'raw.yuv', W_, H_) if x]; sw = [tuple(map(float, x.split())) for x in so[:-1]]
    dm = max(abs(a_[0] - b_) for a_, b_ in zip(sw, fm)); ds = max(abs(a_[1] - b_) for a_, b_ in zip(sw, fs_))
    check('scdet port: %d frames, luma mafd/score within %.4f/%.4f of ffmpeg lavfi.scd.mafd/score (printed to 3 decimals)' % (len(sw), dm, ds), len(sw) == len(fm) and dm < 1e-3 and ds < 1e-3)
    nat = so[-1].split()[1]; check('scdet port: detected cut frames %s == ffmpeg scdet times %s via cuts.py rounding' % (nat, ft), nat == ','.join(map(str, sorted({int(t * 24 + .5) for t in ft}))))
else:
    print('SKIPPED scdet comparison: ffmpeg unavailable')
# --- PrepareSupport: cache_key, order, entry files vs the Python they mirror
import hashlib, importlib.util
_sp2 = importlib.util.spec_from_file_location('cache_mod', str(root / 'tools/depth_analysis/cache.py')); cache_mod = importlib.util.module_from_spec(_sp2); _sp2.loader.exec_module(cache_mod)
for size in (0, 1000, 3 * 1024 * 1024 + 17):
    fp_ = tmp / ('k%d.bin' % size); fp_.write_bytes(os.urandom(size)); os.utime(fp_, ns=(1700000000123456789, 1700000000123456789))
    check('cache_key %d B (mtime_ns kept, last-MiB branch %s): Swift == cache.cache_key' % (size, size > 2 * 1024 * 1024), run('ckey', fp_)[0] == cache_mod.cache_key(str(fp_)))
bf = tmp / 'sha.bin'; bf.write_bytes(os.urandom(200003)); check('pure SHA-256 == hashlib on 200003 B', run('sha', bf)[0] == hashlib.sha256(bf.read_bytes()).hexdigest())
shots_ = [(0, 23), (24, 47), (48, 95), (96, 119), (120, 130)]
def py_order(ph, done):
    pend = [i for i in range(len(shots_)) if i not in done]
    if ph is not None: pend.sort(key=lambda i: (0 if shots_[i][0] <= ph <= shots_[i][1] else min(abs(ph - shots_[i][0]), abs(ph - shots_[i][1])), i))
    return ','.join(map(str, pend))
ss = ','.join('%d-%d' % x for x in shots_)
check('pending order (nearest playhead first, ties to the lower index) == work_chunk rule for 5 playheads', all(run('order', p if p is not None else '-', ss, ','.join(map(str, d)) if d else '-')[0] == py_order(p, set(d)) for p, d in ((None, []), (60, []), (24, [1]), (118, [3]), (47, [0, 4]))))
fd = tmp / 'entry'; fd.mkdir(exist_ok=True); run('fovfile', fd)
ft = json.loads((fd / 'fov_track.json').read_text()); cu = json.loads((fd / 'cuts.json').read_text())
check('fov_track.json {fps, shots[]} (null-padded, either write order) and cuts.json {cuts, shots} have the Python shape', ft['fps'] == 24 and len(ft['shots']) == 2 and ft['shots'][0]['hfov_deg'] == 51.0 and ft['shots'][1]['hfov_deg'] is None and cu == {'cuts': [24], 'shots': [[0, 23], [24, 47]]})
kd = tmp / 'kit'; kd.mkdir(exist_ok=True); (kd / 'kit_manifest.json').write_bytes(b'{"x": 1}')
o = run('kcc', kd, tmp / 'models')[0].split()
check('KitCompiledCache: key = sha256(kit_manifest.json), dir kit-compiled/<sha>, <package>.mlmodelc, prune keeps only the current version', o[0] == hashlib.sha256(b'{"x": 1}').hexdigest() and o[1] == str(tmp / 'models/kit-compiled' / o[0]) and o[2] == 'moge2_vits_518x294_fp16.mlmodelc' and o[3] == 'a,b')
tl = run('tele')
loglines = [l for l in tl if 'gor3d-selftest' in l]
check('telemetry log: begin / stage / thermal / thermal_peak / depth / note / error / end lines, one per fact, noise lines ignored by the parser', len(loglines) == 1 + 2 + 3 + 1 + 1 + 2 + 2 + 1 and loglines[0].startswith('gor3d-selftest v1 begin ') and loglines[-1].startswith('gor3d-selftest v1 end errors=2'))
pl = [l for l in tl if l.startswith('PARSED')][0]
check('telemetry parse round-trips: decode ms 4 n 2 max 2.5, thermal [0,2,1] peak 2 transitions 2, depth min 0.25 max 9 nan 2 inf 1 count 7, notes and 2 errors, ended', pl == 'PARSED 3D self-test finished 4.0 2 2.5 [0, 2, 1] 2 2 0.25 9.0 2 1 7 fp16_used=3 fp16_rejected=1 fp32_used=1 plan ops ane=10 gpu=2 2 true')
check('telemetry error text survives newline, backslash, "=" and spaces verbatim', [l for l in tl if l.startswith('ERR0')][0] == 'ERR0 shot 0 depth: bad<NL>thing \\ with = and spaces')
_o = run('stpure'); sp = _o[0].split() + _o[1].split()
check('self-test policy: marker per (manifest sha12, build), runs once, only with 3D on + kit present + no film preparing; synthetic clip pattern is deterministic (%s)' % sp[-1][:12], sp[0] == 'selftest-abcdef012345-r27_build_1.2.done' and sp[1:5] == ['true', 'false', 'false', 'false'] and sp[5] == str(640 * 360 * 4) and sp[6] == 'true' and sp[7] == 'true')
# --- s22 letterbox vs vda_stream_common.preprocess_aspect (cv2 stubbed: a constant picture resizes to a constant, so only box geometry and normalisation are exercised)
import types
_cv = types.ModuleType('cv2'); _cv.INTER_CUBIC = 2
_cv.resize = lambda img, size, interpolation=None: np.full((size[1], size[0], 3), img.reshape(-1, 3)[0], img.dtype)
sys.modules['cv2'] = _cv; sys.path.insert(0, str(root / 'tools/depth_analysis'))
import vda_stream_common as vsc; vsc.cv2 = _cv
ok_box = ok_px = True; bad = []
for (sw, sh) in ((1920, 1080), (640, 360), (1080, 1080), (4096, 4096), (3840, 1608), (1920, 800), (1440, 1080), (1080, 1920), (720, 480), (1001, 777), (2048, 858), (7, 5)):
    ref = vsc.preprocess_aspect(np.full((sh, sw, 3), 255, np.uint8))[0]
    white = (1.0 - vsc._MEAN) / vsc._STD; mask = np.isclose(ref, white[:, None, None], atol=1e-6).all(0)
    ys, xs = np.where(mask); o = run('lbox', sw, sh, tmp / 'lb.f32'); b = [int(v) for v in o[0].split()]
    if (b[0], b[1], b[2], b[3]) != (xs.max() - xs.min() + 1, ys.max() - ys.min() + 1, xs.min(), ys.min()): ok_box = False; bad.append((sw, sh, b))
    got = np.fromfile(tmp / 'lb.f32', np.float32).reshape(3, 154, 266)
    if not np.allclose(got, ref, atol=1e-6): ok_px = False; bad.append(('px', sw, sh, float(np.abs(got - ref).max())))
    cd = o[1].split(); nw, nh, x0, y0 = b
    if int(cd[0]) != nw * nh or float(cd[1]) != y0 * 266 + x0 or float(cd[2]) != (y0 + nh - 1) * 266 + x0 + nw - 1: ok_px = False; bad.append(('crop', sw, sh, cd))
check('s22 letterbox: box (nw, nh, x0, y0) equals preprocess_aspect on 12 source shapes (incl. 16:9 -> 266x150 with 2 px bars, square, 2.39, portrait, odd sizes)' + str(bad[:2] if bad else ''), ok_box)
check('s22 letterbox: canvas (black bars normalised like pixels) equals preprocess_aspect to 1e-6 and cropDepth returns exactly the picture area', ok_px)
print('depth prepare math: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
