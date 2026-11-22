#!/usr/bin/env python3
"""s46: title-card plane guard reference (tools/depth_analysis/title_card_guard.py). Measures the stroke disparity spread on a title card and the
unchanged depth on normal scenes, with mutants. The shader mirror is pinned to the reference constants by text."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'tools/depth_analysis'))
import title_card_guard as g
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
N, GAIN, W = 64, 0.04, 1920
def tap_of(img):
    return lambda x, y: img[int(g.clamp(y, 0, 1) * (N - 1))][int(g.clamp(x, 0, 1) * (N - 1))]
def prior(img, qx, qy):
    t = tap_of(img)
    l = sum(g.lum(t(g.clamp(qx + dx, .001, .999), g.clamp(qy + dy, .001, .999))) for dx, dy in ((0,0),(.03,0),(-.03,0),(0,.03),(0,-.03))) * 0.2
    return g.clamp(0.5 + 0.1 * (qy - 0.5) + 0.15 * (l - 0.5), 0, 1)
def depth(img, qx, qy, **kw):
    t = g.guard_weight(g.grid_dark_fraction(tap_of(img), **{k: v for k, v in kw.items() if k in ('dark_luma', 'dark_chroma')}),
                       *kw.get('ramp', (g.T_LO, g.T_HI)))
    return g.guarded_depth(prior(img, qx, qy), t)
BLK, WHT = (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)
title = [[WHT if (24 <= y <= 40 and x % 6 < 3 and 8 <= x <= 56) else BLK for x in range(N)] for y in range(N)]
strokes = [(x, y) for y in range(24, 41) for x in range(8, 57) if title[y][x] == WHT]
def spread(img, **kw):
    d = [GAIN * (depth(img, (x + .5) / N, (y + .5) / N, **kw) - 0.5) for x, y in strokes]
    return (max(d) - min(d)) * W
unguarded = max(GAIN * (prior(title, (x + .5) / N, (y + .5) / N) - 0.5) for x, y in strokes) - min(GAIN * (prior(title, (x + .5) / N, (y + .5) / N) - 0.5) for x, y in strokes)
sp = spread(title)
check('title card: stroke disparity spread <= 1 px at 1920 (guarded %.2f px, unguarded %.2f px)' % (sp, unguarded * W), sp <= 1.0 and unguarded * W > 3.0)
# normal scene (colourful gradient, bright) is untouched
scene = [[(0.15 + 0.7 * x / (N - 1), 0.2 + 0.6 * y / (N - 1), 0.5 + 0.4 * ((x * 7 + y * 3) % 11) / 10) for x in range(N)] for y in range(N)]
frac = g.grid_dark_fraction(tap_of(scene))
same = all(abs(depth(scene, (x + .5) / N, (y + .5) / N) - prior(scene, (x + .5) / N, (y + .5) / N)) == 0 for x in range(0, N, 7) for y in range(0, N, 7))
check('normal scene: guard weight 0 and depth identical to the unguarded prior (dark frac %.2f)' % frac, g.guard_weight(frac) == 0 and same)
# dark but coloured scene (night blue) is not a title card
night = [[(0.0, 0.0, 0.07) for x in range(N)] for y in range(N)]
check('dark coloured frame (chroma 0.07) is not flagged', g.guard_weight(g.grid_dark_fraction(tap_of(night))) == 0)
# fade-in: weight moves monotonically and in small steps (no flicker)
# fade to a bright full frame behind the text: fraction of dark taps falls with the backdrop
def backdrop(k, n=20):
    v = 0.5 * k / n
    return [[WHT if (24 <= y <= 40 and x % 6 < 3 and 8 <= x <= 56) else (v, v, v) for x in range(N)] for y in range(N)]
ts = [g.guard_weight(g.grid_dark_fraction(tap_of(backdrop(k)))) for k in range(21)]
check('fade: weight non-increasing as the backdrop brightens', all(a >= b for a, b in zip(ts, ts[1:])) and ts[0] == 1.0 and ts[-1] == 0.0)
# sparse text on black must be flagged with margin (grid misses thin strokes)
check('title card flagged at full weight', g.guard_weight(g.grid_dark_fraction(tap_of(title))) == 1.0)
# mutants
check('mutant: DARK_LUMA 1.0 flags the normal scene (caught)', g.guard_weight(g.grid_dark_fraction(tap_of(scene), dark_luma=1.0, dark_chroma=1.0)) > 0)
check('mutant: guard off leaves the title spread over budget (caught)', unguarded * W > 1.0)
shader=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text() if 'root' in globals() else (Path(__file__).resolve().parents[2]/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
check('shader mirrors25tap statistics and exact guard constants, cached per frame', 'for(int y=0;y<5;y++)for(int x=0;x<5;x++)' in shader and 'if(l<0.08 && chroma<0.06)' in shader and '(0.80-0.60)' in shader and '//!SAVE D3_TITLE' in shader and '//!WIDTH 1' in shader)
check('flat and pack title converge at exact screen plane', 'd3_depth(uv,0.5)-0.5' in shader and 'd3_depth(uv,vr_pk_conv) - vr_pk_conv' in shader and 'return mix(prior,plane,title_weight);' in shader)
print('title card guard: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
