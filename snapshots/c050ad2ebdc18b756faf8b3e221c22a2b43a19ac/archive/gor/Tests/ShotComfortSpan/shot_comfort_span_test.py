#!/usr/bin/env python3
"""F3: scale-invariant comfort gain from the shot's disparity quantiles. SYNTHETIC shots only; no owner baseline, not wired into the renderer."""
import os, pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sys.path.insert(0, str(root / 'tools/depth_analysis'))
import comfort
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw and os.path.exists(sw):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'sc'
    # 195y G2: ShotComfortSpan/ShotCuts/ShotComfortShot folded into ShotComfort.swift; strip the ShotComfortShot span (needs DZCFile, out of scope here; text-checked below)
    sc = (S / 'ShotComfort.swift').read_text()
    sc = sc[:sc.index('// BEGIN relocated ShotComfortShot.swift (195y G2, behavior unchanged)')] + sc[sc.index('// END relocated ShotComfortShot.swift'):]
    tmp_sc = pathlib.Path(tempfile.mkdtemp()) / 'ShotComfort.swift'; tmp_sc.write_text(sc)
    r = subprocess.run([sw, '-O', str(tmp_sc), str(root / 'Tests/ShotComfortSpan/main.swift'), '-o', str(exe)], capture_output=True, text=True)
    check('ShotComfortSpan compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-500:]); sys.exit(1)
    o = subprocess.run([str(exe)], capture_output=True, text=True).stdout.split('\n')
    rows = {}
    for l in o[:5]:
        m = re.match(r'(.+?) gain=(\S+) near=(\S+) far=(\S+) span=(\S+) before=(\S+) clamped=(\S+)', l); rows[m.group(1)] = [float(x) for x in m.groups()[1:6]] + [m.group(7)]
    for n, (g, near, far, span, before, cl) in rows.items():
        check('SYNTHETIC %-12s gain %.2f, span %.3f -> %.3f deg (baseline -> new); near %.2f <= 2, far %.2f >= -1' % (n, g, before, span, near, far), near <= 2.0 + 1e-9 and far >= -1.0 - 1e-9)
    check('flat distant shot gains depth (span grows, gain > 1) without breaking either ceiling', rows['flat distant'][0] > 1 and rows['flat distant'][3] > rows['flat distant'][4])
    check('close deep shot is held to the budget (gain <= 1, span never beyond 3 deg)', rows['close deep'][0] <= 1.0 + 1e-9 and rows['close deep'][3] <= 3.0 + 1e-9)
    check('gain clamps at [0.25, 3] and says so', rows['tiny range'][0] == 3.0 and rows['tiny range'][5] == 'true')
    # Python mirror of the same formula (comfort.disp_deg) agrees on the chosen gain
    g, near, far = rows['mid'][0], rows['mid'][1], rows['mid'][2]
    check('python comfort.disp_deg agrees with the Swift quantile disparities (mid shot)', abs(comfort.disp_deg(2.0, 4.0, 0.063 * g) - near) < 1e-6 and abs(comfort.disp_deg(8.0, 4.0, 0.063 * g) - far) < 1e-6)
    check('invalid input -> nil; quantile helper ignores nan/<=0', o[5] == 'invalid true true' and o[6] == 'q 3.0 1.2 true')
else: print('SKIPPED numeric (no swiftc)')
# Renderer wiring pins and independent histogram interpolation model.
import numpy as np
ss = (S / 'ShotComfort.swift').read_text().split('// BEGIN relocated ShotComfortShot.swift (195y G2, behavior unchanged)')[1].split('// END relocated ShotComfortShot.swift')[0]; co = (S / 'ThreeDRenderCoordinator.swift').read_text(); rp = (S / 'RenderPrefsReader.swift').read_text()
check('span is derived from the actual container p5/median/p95, not the old median baseline', 'h.quantile(0.05)' in ss and 'h.quantile(0.95)' in ss and 'depthScale: span.gain' in ss and 'zNear: span.nearClampM' in ss)
check('render key v5 invalidates median-only renders; actual depth stamp fixes shot content', 'v5|span-p5p95|' in co and 'Self.depthStamp(mp4)' in co)
check('strength multiplies the span gain; final near clamp goes to the renderer', 'ipdM * c.depthScale * ShotComfort.strengthFactor' in rp and 'ipd: comfortIPD(c)' in rp and 'zNear: cf.map { prefs.comfortZNear($0) }' in co)
check('subtitle geometry uses the same strength-adjusted near clamp', 'r.zNear = prefs.comfortZNear(c)' in co)
for a,b,c in [(7.5,9.,8.),(2.,8.,4.),(.8,12.,2.5)]:
    v = comfort.shot_comfort_span_values(a,b,c)
    check('python near_clamp_m exact crossed budget zc=%s' % c, abs(float(comfort.disp_deg(v['near_clamp_m'],c,v['ipd_eff'])) - 2.) < 1e-10)
rng=np.random.default_rng(14)
for q in (.05,.5,.95):
    w=rng.integers(1,1024,211); z=256/(w/1023*1024); counts=np.bincount(w,minlength=1024)
    pos=q*(len(w)-1); i=int(np.floor(pos)); j=min(i+1,len(w)-1)
    def at(rank):
        seen=0
        for k in range(1023,0,-1):
            seen+=int(counts[k])
            if rank<seen:return 256/(k/1023*1024)
    got=at(i)+(at(j)-at(i))*(pos-i)
    check('streaming histogram q=%s matches numpy dequantised depth' % q, abs(got-np.quantile(z,q))<1e-12)
print('shot comfort span: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
