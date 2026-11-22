#!/usr/bin/env python3
"""s37: Sources/gor/gor/ThreeD.swift (StereoSource.swift section) (pure, Linux-compiled) vs tools/depth_analysis/stereo_probe.py: filename hints, metadata verdicts, hp-NCC pixel confirm on
synthetic stereo (s36 fixture eyes) and 2D frames (sbs / vr180 / ou layouts, native size), routing incl. override. cv2 is absent here: a scipy/numpy shim reproduces
cvtColor(RGB2GRAY) fixed point and GaussianBlur(sigma 3, reflect-101). half_sbs/half_ou pixel confirm is NOT parity-tested (Swift runs on native halves, Python upsamples first)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, shutil, subprocess, sys, tempfile, types
import numpy as np
from scipy.ndimage import gaussian_filter
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools/depth_analysis'))
cv2 = types.ModuleType('cv2'); cv2.COLOR_RGB2GRAY = 7
def _gray(im, code):
    r, g, b = [im[..., i].astype(np.uint32) for i in range(3)]
    return ((r * 4899 + g * 9617 + b * 1868 + 8192) >> 14).astype(np.uint8)
cv2.cvtColor = _gray
cv2.GaussianBlur = lambda g, k, s: gaussian_filter(g.astype(np.float32), s, mode='mirror', truncate=3.0).astype(np.float32)
sys.modules['cv2'] = cv2
import output_modes as om, stereo_probe as sp
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift6/usr/bin/swiftc'
tmp = pathlib.Path(tempfile.mkdtemp()); exe = tmp/'ss'
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'StereoSource.swift')), str(root/'Tests/StereoSource/main.swift'), '-o', str(exe)], capture_output=True, text=True)
if r.returncode: print(r.stderr[-1500:]); sys.exit(1)
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def run(*a): return subprocess.run([str(exe), *map(str, a)], capture_output=True, text=True, check=True).stdout.strip()
def fmt(v): return 'none' if v == (None, False, None) else f'{v[0]} {v[1]} {v[2]}'
for nm in ('My.Movie.3D.SBS.1080p.mp4', 'holiday_vr180.mp4', 'plain_film.mp4', 'film.HSBS.mkv', 'x_half-ou_y.mp4', 'a.OU.mkv', 'tb.mkv', 'absolutely.mp4', 'sbsfoo.mp4', 'lr_3d.mp4', 'f-sbs.mp4', 'movie.top-bottom.mp4', 'abc_3d_180.mp4'):
    ref = sp.metadata_verdict('/x/' + nm, stream={"side_data_list": [], "profile": "", "codec_tag_string": ""})
    check(f'hint {nm}: {fmt(ref)}', run('hint', nm) == fmt(ref).replace(' False', ' false').replace(' True', ' true'))
for (typ, kind, inv, sph, prof, tag) in (('Stereo 3D', 'side by side', 0, '-', '-', '-'), ('Stereo 3D', 'side by side', 1, '-', '-', '-'), ('Stereo 3D', 'top_bottom', 0, '-', '-', '-'), ('Stereo 3D', 'bottom_top', 1, '-', '-', '-'),
                                         ('Spherical Mapping', '-', 0, 'left-right', '-', '-'), ('Spherical Mapping', '-', 0, 'right-left', '-', '-'), ('x', '-', 0, '-', 'Main Multiview', '-'), ('x', '-', 0, '-', '-', 'mv-hevc'), ('Stereo 3D', 'bogus', 0, '-', '-', '-')):
    sd = {"side_data_type": typ, "type": kind, "inverted": inv}
    if sph != '-': sd["stereo_mode"] = sph
    ref = sp.metadata_verdict('/x/plain.mp4', stream={"side_data_list": [sd], "profile": "" if prof == '-' else prof, "codec_tag_string": "" if tag == '-' else tag})
    check(f'meta {typ}/{kind}/{inv}/{sph}/{prof}/{tag}: {fmt(ref)}', run('meta', '/x/plain.mp4', typ, kind, inv, sph, prof, tag) == fmt(ref).replace(' False', ' false').replace(' True', ' true'))
fx = root/'tools/depth_analysis/golden/mode_fixture/'
rgb = np.load(fx/'rgb.npy'); z = np.load(fx/'z.npy'); th = 0.9075712110370514
L, R = om.render_eyes(rgb, z, th, projection='perspective')
rng = np.random.default_rng(3)
tex = (rng.random((54, 96, 3)) * 255).astype(np.uint8); tex2 = (rng.random((54, 96, 3)) * 255).astype(np.uint8)
frames = {'stereo sbs': ('sbs', np.concatenate([L, R], 1)), 'stereo vr180-pack': ('vr180', np.concatenate([L, R], 1)), 'stereo ou': ('ou', np.concatenate([L, R], 0)), 'swapped stereo sbs': ('sbs', np.concatenate([R, L], 1)),
          '2D noise sbs': ('sbs', np.concatenate([tex, tex2], 1)), '2D film halves sbs': ('sbs', np.concatenate([rgb, np.roll(rgb[::-1], 7, 1)], 1)), '2D noise ou': ('ou', np.concatenate([tex, tex2], 0))}
for name, (lay, fr) in frames.items():
    Lh, Rh = sp.split_eyes(fr, lay)
    ok, ncc_py, d_py, _ = sp.confirm_stereo(Lh, Rh)
    h, w = fr.shape[:2]; f = tmp/'f.rgb'; f.write_bytes(fr.tobytes())
    t = run('confirm', lay, w, h, f).split()
    check(f'confirm {name}: swift {t[0]} ncc {t[1]} shift {t[2]} vs python {ok} {ncc_py:.4f} {d_py}', (t[0] == 'true') == ok and abs(float(t[1]) - ncc_py) < 2e-3 and int(t[2]) == d_py)
import re
rt = re.sub(r'\b\w+\.StereoLayout\.', '', run().split('\n')[1])
check('half layouts are never sent to depth: playAsIs', run().split('\n')[0] == 'playAsIs playAsIs')
check('route: filename alone -> depth; confirmed filename -> passthrough sbs; override flat -> depth; override layout wins; mvhevc -> native note: ' + rt,
      rt == 'depth passthrough(sbs, swap: false) depth passthrough(ou, swap: true) nativeNote')
# ffprobe JSON -> verdict, same streams through stereo_probe.metadata_verdict
import json
for nm, st in (('mkv sbs inverted', {"side_data_list": [{"side_data_type": "Stereo 3D", "type": "side by side", "inverted": 1}], "profile": "Main", "codec_tag_string": "[0][0][0][0]"}),
               ('spherical', {"side_data_list": [{"side_data_type": "Spherical Mapping", "projection": "equirectangular", "stereo_mode": "left-right"}], "codec_tag_string": "hvc1"}),
               ('plain', {"side_data_list": [], "profile": "High", "codec_tag_string": "avc1"}), ('no side data key', {"profile": "Main"}), ('multiview', {"profile": "Main Multiview", "side_data_list": []})):
    f = tmp/'p.json'; f.write_text(json.dumps({"streams": [st]}))
    ref = sp.metadata_verdict('/x/plain.mp4', stream=st)
    check(f'ffprobe json {nm}: {fmt(ref)}', run('ffprobe', '/x/plain.mp4', f) == fmt(ref).replace(' False', ' false').replace(' True', ' true'))
# measure_disparity parity (eyes >= 256 px wide): textured scene, left = smooth noise, right = left shifted by a row-band disparity (3 / 9 / 14 px)
from scipy.ndimage import gaussian_filter as gf
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

rg = np.random.default_rng(11); base = gf(rg.random((200, 320 + 40, 3)), (1.2, 1.2, 0)); base = (255 * (base - base.min()) / (base.max() - base.min())).astype(np.uint8)
Ld = base[:, 20:340]; Rd = np.empty_like(Ld)
for y in range(200):
    d = 3 if y < 70 else (9 if y < 140 else 14)
    Rd[y] = base[y, 20 - d:340 - d]
fr = np.concatenate([Ld, Rd], 1); f = tmp/'d.rgb'; f.write_bytes(fr.tobytes())
m = sp.measure_disparity(Ld, Rd)
t = run('disp', fr.shape[1], fr.shape[0], f)
check('disparity: python result ' + str(None if m is None else {k: round(v, 3) for k, v in m.items() if k in ('px_p50', 'px_p99', 'coverage')}) + ' vs swift ' + t, (m is None) == (t == 'nil'))
if m is not None and t != 'nil':
    s = [float(x) for x in t.split()]
    check('disparity p50/p99 px and coverage match', abs(s[0] - m['px_p50']) < 0.51 and abs(s[1] - m['px_p99']) < 1.01 and abs(s[4] - m['coverage']) < 0.02 and abs(s[3] - m['over_budget_frac']) < 0.05)
    check('disparity tracks the analytic 3..14 px (p50 within 1 px of 9, p99 within 2 px of 14)', abs(s[0] - 9) <= 1.5 and abs(s[1] - 14) <= 2.5)
print('stereo_source: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
