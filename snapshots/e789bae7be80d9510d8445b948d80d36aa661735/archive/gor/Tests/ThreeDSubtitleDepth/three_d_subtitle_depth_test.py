#!/usr/bin/env python3
"""ThreeDSubtitleDepth + ThreeDFilmInfo: Python model of the metres->dial mapping and text pins (Swift uncompiled, nothing run on a Mac)."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import math, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sd = (S / 'ThreeDSubtitleDepth.swift').read_text(); pp = (_pp_split().dpath(S,'PPController.swift')).read_text(); co = (S / 'ThreeDRenderCoordinator.swift').read_text(); wi = (S / 'ThreeDWiring.swift').read_text()
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def frac(z, ipd, conv, th):
    if not (z > 0 and ipd > 0 and 0 < th < math.pi): return 0.0
    scr = 2 * math.atan2(ipd / 2, conv) if conv and conv > 0 else 0.0
    return (2 * math.atan2(ipd / 2, z) - scr) / (2 * math.tan(th / 2))
def factor(z, ipd, conv, th): return max(0.0, min(8.0, frac(z, ipd, conv, th) / 0.004))
th = math.radians(75)
check('model: nearer subtitle = larger factor, at the screen distance = 0, beyond = clamped to 0', factor(1.0, .063, 2.0, th) > factor(1.5, .063, 2.0, th) > 0 and abs(factor(2.0, .063, 2.0, th)) < 1e-9 and factor(5.0, .063, 2.0, th) == 0)
check('model: no convergence (screen at infinity) gives a crossed value for Z=2m, inside the dial range 0..8', 0 < factor(2.0, .063, None, th) < 8)
check('model: bigger screen (wider thetaH) = smaller factor for the same Z (fraction of a wider picture)', factor(2.0, .063, None, math.radians(110)) < factor(2.0, .063, None, math.radians(50)))
check('model: ipd scales the factor linearly (small angle) and zero ipd or bad thetaH gives 0', abs(factor(3, .126, None, th) / factor(3, .063, None, th) - 2) < 0.02 and factor(2, 0, None, th) == 0 and factor(2, .063, None, 0) == 0)
check('Swift mirrors the model: atan2(ipd/2, z) pair, screen angle from convergence, / (2 tan(thetaH/2)), clamp 0...8', 'atan2(ipd / 2, z)' in sd and 'atan2(ipd / 2, convergence!)' in sd and '2 * tan(thetaH / 2)' in sd and 'max(0, min(dialLimit' in sd and 'dialLimit = 8.0' in sd)
check('uses SubtitleDepth.placement over band samples, lossless container w10 (no shift), per shot', 'SubtitleDepth.placement(w10:' in sd and 'DZCFile(url: url)' in sd and 'atOrAfter' in sd and '>> 6' not in sd)
check('all four dial readers go through ThreeDSubtitleDepth.dial (override only while 3D plays, else base)', pp.count('ThreeDSubtitleDepth.dial(') == 4 and 'shared.factor ?? base' in sd)
check('PPController stays at its 6234-line ceiling', len(pp.split('\n')) - 1 <= 6234)
check('coordinator begins on switch to the render file and ends on back-to-2D', 'ThreeDSubtitleDepth.shared.begin(depth: dz' in co and 'ThreeDSubtitleDepth.shared.end()' in co)
check('wiring: changed -> applySubtitleDepthOffset', 'ThreeDSubtitleDepth.shared.changed' in wi and 'applySubtitleDepthOffset()' in wi)
check('film info fed from container-fps / estimated-frame-count on existing lines, keyed by path', '129: "container-fps", 130: "estimated-frame-count"' in pp and 'ThreeDFilmInfo.shared.set(path: path' in pp and 'info(for film: URL)' in sd)
check('launcher instantiated with the registry runner (nil until E-G registers), 3 s timer, reports via show-text', 'ThreeDPrepareLauncher(spawn: { ThreeDPrepareSpawn.make(runner: ThreeDRunnerRegistry.runner) }' in wi and 'withTimeInterval: 3.0' in wi and 'ThreeDFilmInfo.shared.info(for:' in wi)
check('no player-socket words in new code', not any(re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', t, re.I) for t in (sd, wi, co)))
# --- comfort alignment (s25/s27): the dial follows the SAME per-shot values the render used ---
sys.path.insert(0, str(root / 'tools/depth_analysis')); import comfort; import numpy as np
cf = comfort.shot_comfort([np.full((8, 8), 3.0)]); zc, zn, ds = cf['convergence_m'], cf['z_near'], cf['depth_scale']
ipd_eff = 0.063 * ds
def seen(z, zn): return max(z, zn) if zn else z
check('model (comfort.py): a subtitle at the shot median depth z_c sits at the screen (factor 0), nearer content is held to z_near so the dial never exceeds the 2 deg crossed budget', abs(factor(zc, ipd_eff, zc, th)) < 1e-9 and factor(seen(0.2, zn), ipd_eff, zc, th) == factor(zn, ipd_eff, zc, th) and frac(zn, ipd_eff, zc, th) > 0)
fx = factor(0.2, 0.063, None, th); fc = factor(seen(0.2, zn), ipd_eff, zc, th)
check('model: the old fixed-parameter dial (full ipd, no convergence, no clamp) differs from the comfort dial for the same band depth', abs(fx - fc) > 1e-6)
check('Swift: params() returns the render arguments (comfort: comfortIPD/z_c/zNear, else effectiveIPD/convergenceM/nil) and seenZ clamps to z_near', 'func params(' in sd and 'convergence: c.convergenceM, zNear: c.zNear' in sd and 'convergence: convergenceM, zNear: nil' in sd and 'zNear.map { max(z, $0) } ?? z' in sd and 'Self.seenZ(z, zNear: r.zNear)' in sd)
check('coordinator feeds the subtitle the SAME ShotComfortShot.compute / comfortIPD / convergence / zNear expressions as RenderShotWriter.write', 'let cf = prefs.comfortActive ? ShotComfortShot.compute(depth: dz, ipd: prefs.ipdM).map { c -> ShotComfort in var r = c; r.zNear = prefs.comfortZNear(c); return r } : nil' in co and 'comfortIPD: cf.map { prefs.comfortIPD($0) }' in co and 'ipd: cf.map { prefs.comfortIPD($0) } ?? prefs.effectiveIPD' in co and 'convergence: cf?.convergenceM ?? prefs.convergenceM' in co and 'zNear: cf.map { prefs.comfortZNear($0) }' in co)
check('the comfort median is read on the utility queue, not the main thread (render closure runs inside queue.async)', 'let r = render()' in sd and sd.index('queue.async') < sd.index('let r = render()'))
sys.exit(1 if bad else 0)
