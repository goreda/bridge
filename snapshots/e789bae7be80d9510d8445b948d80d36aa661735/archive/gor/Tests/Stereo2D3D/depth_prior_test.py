#!/usr/bin/env python3
"""PARTIAL feature: synthetic 2D->stereo from a depth PRIOR (not true depth). Python port of d3_depth + the eye displacement in
vr180-look.lua (flat-2d3d), pinned to the shader text. Swift/GLSL compile only on gor-ci; Mac look and heat are unverified."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, random, re, sys, math
root = pathlib.Path(__file__).resolve().parents[2]
lua = (root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
feat = (_pp_split().path(root,'PPController_Features.swift')).read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
clamp = lambda v, a, b: max(a, min(b, v))
GAIN = 0.02
def depth(img, qx, qy, w=0.1):
    # Texture is not geometry: the fallback keeps only a positional plane.
    return clamp(0.5 + w*(qy-0.5),0,1)

def eye_x(img, ux, uy, right, gain=GAIN, w=0.1):
    disp = gain*(depth(img, ux, uy, w) - 0.5)
    return ux + (-1.0 if right else 1.0)*disp
def flat(v, n=64): return [[v]*n for _ in range(n)]
grey = flat(0.5)
# bounds, symmetry, identity
worst = 0
for img in (flat(0.0), flat(1.0), grey):
    for ux in (0.1, 0.5, 0.9):
        for uy in (0.0, 0.25, 0.5, 0.75, 1.0):
            l, r = eye_x(img, ux, uy, False), eye_x(img, ux, uy, True)
            worst = max(worst, abs(l-ux), abs(r-ux))
            assert abs((l-ux)+(r-ux)) < 1e-12
check('per-eye shift bounded by GAIN/2 of frame width', worst <= GAIN/2 + 1e-12)
check('eyes shift symmetrically (equal and opposite)', True)
check('gain 0 == identity (both eyes sample the film unshifted)', all(eye_x(grey, x, y, r, gain=0.0) == x for x in (.2,.8) for y in (.1,.9) for r in (False, True)))
check('screen plane: depth 0.5 gives zero shift', abs(eye_x(flat(0.5), 0.5, 0.5, False, w=0.1) - 0.5) < 1e-12)
check('nearer (lower image) shifts more than farther (upper), left eye moves right for near', eye_x(grey, .5, .9, False) > eye_x(grey, .5, .1, False))
# no out-of-frame: clamp keeps sampling inside
px = 0.5/1920
ok = all(px <= clamp(eye_x(grey, x, .5, r), px, 1-px) <= 1-px for x in (0.0, 0.001, 0.999, 1.0) for r in (False, True))
check('sample position clamped inside the frame', ok)
# temporal stability: grain noise on luma must move depth by far less than a visible amount
rnd = random.Random(1); base = [[0.4 + 0.2*(x/63) for x in range(64)] for _ in range(64)]
dmax = 0
for _ in range(50):
    noisy = [[clamp(v + rnd.uniform(-0.08, 0.08), 0, 1) for v in row] for row in base]
    dmax = max(dmax, abs(eye_x(noisy, .5, .5, False) - eye_x(base, .5, .5, False)))
check('grain (+-8%% luma) moves the disparity by < 0.1%% of frame width (got %.5f)' % dmax, dmax < 0.001)
# smoothness across space: neighbouring pixels differ by a tiny shift (no tearing)
check('disparity varies slowly across x (tear-free)', max(abs(eye_x(base, x/100, .5, False) - x/100 - (eye_x(base, (x+1)/100, .5, False) - (x+1)/100)) for x in range(99)) < 0.002)
# s44 shear metric (owner screenshot 17:03: opposite per-eye shear ~30 px top vs bottom):
# the disparity ramp across rows on a FLAT frame, in px at 1920 wide, must stay small.
shear = abs(eye_x(grey, .5, 0.0, False, gain=0.04) - eye_x(grey, .5, 1.0, False, gain=0.04)) * 1920
check('top-vs-bottom shear on a flat frame <= 12 px at 1920, gain 0.04 (was ~54 px at w=0.7, got %.1f)' % shear, shear <= 12.0)
check('mutant w=0.7 violates the shear budget (caught)', abs(eye_x(grey, .5, 0.0, False, gain=0.04, w=0.7) - eye_x(grey, .5, 1.0, False, gain=0.04, w=0.7)) * 1920 > 12.0)
# s45 ghost metric (owner 20:28, multi-ghosted text): white strokes on black; disparity spread across the stroke pixels (px at 1920, gain 0.04)
txt = [[1.0 if (12 <= y <= 20 and x % 6 < 3 and 8 <= x <= 56) else 0.0 for x in range(64)] for y in range(64)]
xs_ = [eye_x(txt, (x+.5)/64, (y+.5)/64, False, gain=0.04) - (x+.5)/64 for y in range(12, 21) for x in range(8, 57) if txt[y][x] > 0.5]
spread = (max(xs_) - min(xs_)) * 1920
check('text-stroke disparity spread <= 12 px at 1920, gain 0.04 (was ~35+ at luma weight 0.9, got %.1f)' % spread, spread <= 12.0)
def depth_old(img, qx, qy):
    l = sum(img[int(clamp(qy+dy,.001,.999)*63)][int(clamp(qx+dx,.001,.999)*63)] for dx, dy in ((0,0),(.03,0),(-.03,0),(0,.03),(0,-.03)))*0.2
    return clamp(0.1*qy + 0.9*l, 0, 1)
xo = [0.04*(depth_old(txt, (x+.5)/64, (y+.5)/64)-0.5) for y in range(12, 21) for x in range(8, 57) if txt[y][x] > 0.5]
check('mutant luma weight 0.9 violates the text-spread budget (caught, %.1f px)' % ((max(xo)-min(xo))*1920), (max(xo)-min(xo))*1920 > 12.0)
# mutants
def mut_big(): return max(abs(eye_x(grey, .5, y, False, gain=0.3) - .5) for y in (0, 1)) > GAIN/2
check('mutant gain 0.3 breaks the bound (caught)', mut_big())
# pins
pin = lambda n, t, src=lua: check('pin: ' + n, t in src)
pin('kind in set-projection', 'kind == "flat-2d3d"')
pin('mono flag', 'flat_mono = kind == "flat-2d3d"')
pin('gain constant 0.02', 'local D3_GAIN = 0.02')
pin('shader param', '//!PARAM vr_d3_gain\n//!TYPE float\n0.02')
pin('brightness-neutral positional fallback', 'float prior=clamp(0.5+0.1*(q.y-0.5),0.0,1.0);')
check('flat texture inversion cannot change fallback depth', depth(flat(0),.5,.5)==depth(flat(1),.5,.5))
pin('opposite eye shift along the screen-horizontal axis', 'vec2 displaced=uv+(right>0.5 ? -1.0 : 1.0)*disp*disparity_axis;')
pin('192c shared source crop, no edge extension', 'if(vr_flat_mono>0.5)uv=d3_common_uv(uv,disparity_axis,0.5,total_shift);')
pin('default OFF: only flat-2d3d sets the flag', 'local flat_mono = false')
pin('full-frame eye aspect for 2D', 'if kind == "flat-2d3d" {return width*latestPixelAspect/height}', feat)
pin('remembered per file', 'projectionKind = kind', feat)
pin('sbs path unchanged when flag 0', 'if(blink_top_bottom>0.5) sample_pos=vec2(uv.x,(uv.y+src_eye)*0.5);')
check('pin: s44 black-wedge guard removed (no abs(lon) canvas clip)', 'abs(lon) > 1.5' not in lua)
pin('legacy shader strip keeps param inside the removed span', '//!PARAM vr_flat_sbs\n//!TYPE float\n0.0\n\n//!PARAM vr_flat_mono')
print('stereo 2d3d prior: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
