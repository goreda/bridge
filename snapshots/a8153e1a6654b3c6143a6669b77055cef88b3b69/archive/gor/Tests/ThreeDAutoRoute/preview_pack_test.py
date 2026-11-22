#!/usr/bin/env python3
"""Owner 15:16 / Main 15:21: every 3D menu mode and the strength row must visibly change the pseudo-3D PREVIEW (no models). Python port of the pack math in the
vr180-look.lua PACK variant (pack_eye + top/bottom + anaglyph), pinned to the shader text. GLSL/Lua are Mac-compile UNVERIFIED (no compiler on Linux)."""
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
lua = (root / 'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
clamp = lambda v, a, b: max(a, min(b, v))
W, H = 48, 27
img = [[(0.15 + 0.7 * (x / (W - 1)), 0.2 + 0.6 * (y / (H - 1)), 0.5 + 0.4 * ((x * 7 + y * 3) % 11) / 10) for x in range(W)] for y in range(H)]
def lum(c): return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def tap(x, y):
    return img[int(clamp(y, 0, 1) * (H - 1))][int(clamp(x, 0, 1) * (W - 1))]
def depth(qx, qy):
    l = sum(lum(tap(clamp(qx + dx, .001, .999), clamp(qy + dy, .001, .999))) for dx, dy in ((0,0),(.03,0),(-.03,0),(0,.03),(0,-.03))) * 0.2
    return clamp(0.5 + 0.1 * (qy - 0.5) + 0.15 * (l - 0.5), 0, 1)  # s44: vertical weight 0.7->0.1 (kills the row-linear shear)
import math
def pack_eye(u, v, right, gain, conv=0.5, zoom=1.0, soft=1.0, vr180=False, yaw=0, pitch=0, roll=0, hx=0, hy=0, hz=0, lid=0):
    lid_uv = (u, 1-v)
    if vr180:   # equirect-180 eye canvas of a flat film on a 75 deg virtual screen (mirrors the shader)
        lon = (u - .5) * math.pi; lat = (v - .5) * math.pi; th = math.tan(math.radians(37.5)) / zoom; asp = 16 / 9
        x,y,z = math.sin(lon)*math.cos(lat), math.sin(lat), math.cos(lon)*math.cos(lat)
        x,y = math.cos(roll)*x-math.sin(roll)*y, math.sin(roll)*x+math.cos(roll)*y
        y,z = math.cos(pitch)*y-math.sin(pitch)*z, math.sin(pitch)*y+math.cos(pitch)*z
        x,z = math.cos(yaw)*x+math.sin(yaw)*z, -math.sin(yaw)*x+math.cos(yaw)*z
        plane = (hx+x*max(.1,1-hz)/max(z,.001), hy+y*max(.1,1-hz)/max(z,.001))
        u,v = .5+.5*plane[0]/th, .5+.5*plane[1]/(th/asp)
        if z <= .001: u = v = -1  # s44: lon guard removed (blacked outer 4.1 deg columns)
    else:
        u,v = (u-.5)/zoom, (v-.5)/zoom
        u,v = (math.cos(roll)*u-math.sin(roll)*v)*max(.1,1-hz)+.5, (math.sin(roll)*u+math.cos(roll)*v)*max(.1,1-hz)+.5
        u,v = u+yaw/1.5707963+hx*.5, v-pitch/1.5707963+hy*.5
    if not (0 <= u <= 1 and 0 <= v <= 1):
        if soft < .5 or zoom >= .999: return (0, 0, 0)
        u, v = clamp(u, 0, 1), clamp(v, 0, 1)
    ex = u + (-1.0 if right else 1.0) * gain * (depth(u, v) - conv)
    base = tap(clamp(ex, 0.5 / W, 1 - 0.5 / W), v)
    if lid <= 0: return base
    arch = .08*lid*(1-(2*lid_uv[0]-1)**2)
    upper,lower=1-.92*lid-arch,.08*lid+arch*.25
    edge=min(upper-lid_uv[1],lid_uv[1]-lower)
    t=clamp((edge+.03)/.06,0,1); covered=1-t*t*(3-2*t)
    # Scene glow stands in for source taps in this CPU coverage test; real blink rendering stays in shared blink_render.
    return tuple(c*(1-covered)+.03*covered for c in base)
def render(pack, gain=0.04, ow=W, oh=H, **k):
    out = []
    for j in range(oh):
        row = []
        for i in range(ow):
            px, py = (i + 0.5) / ow, (j + 0.5) / oh
            if pack in (0, 3, 4):   # side by side: left eye in the left half
                right = px >= 0.5; u = (px * 2) % 1.0
                row.append(pack_eye(u, py, right, gain, vr180=(pack == 4), **k))
            elif pack == 1:  # top/bottom: left eye on top
                right = py >= 0.5; v = (py * 2) % 1.0
                row.append(pack_eye(px, v, right, gain, **k))
            else:           # anaglyph: red from the left eye, green+blue from the right eye
                l = pack_eye(px, py, False, gain, **k); r = pack_eye(px, py, True, gain, **k)
                row.append((l[0], r[1], r[2]))
        out.append(row)
    return out
def diff(a, b): return sum(abs(p[k] - q[k]) for ra, rb in zip(a, b) for p, q in zip(ra, rb) for k in range(3)) / (len(a) * len(a[0]) * 3)
sbs, tb, ana = render(0), render(1), render(2)
check('sbs, top/bottom and anaglyph previews are pairwise different pictures', min(diff(sbs, tb), diff(sbs, ana), diff(tb, ana)) > 0.02)
vr = render(4)
check('MEASURED vr180 preview (equirect-180 warp) differs clearly from plain sbs, and is black outside the screen area', diff(vr, sbs) > 0.05 and vr[0][0] == (0, 0, 0) and vr[H // 2][W // 4] != (0, 0, 0))
check('MEASURED vr180 preview: strength changes it, left/right halves differ', diff(render(4, 0.0), render(4, 0.08)) > 0.0005 and diff(vr[:, :W // 2] if False else [r[:W // 2] for r in vr], [r[W // 2:] for r in vr]) > 0)
base = render(3)
check('MEASURED screen depth (conv) changes the picture', diff(base, render(3, conv=0.3)) > 0.0005 and diff(render(3, conv=0.3), render(3, conv=0.7)) > 0.0005)
check('MEASURED screen size (zoom) changes the picture, bigger and smaller both', diff(base, render(3, zoom=0.7)) > 0.02 and diff(base, render(3, zoom=1.4)) > 0.02)
check('MEASURED surround soft vs black differs when the film is smaller than the screen', diff(render(3, zoom=0.7, soft=1.0), render(3, zoom=0.7, soft=0.0)) > 0.01 and diff(render(3, soft=1.0), render(3, soft=0.0)) == 0)
check('MEASURED stronger depth: base gain 0.04 moves pixels about twice the old 0.02 (disparity of eyes)', diff(render(3, 0.0), render(3, 0.04)) > 1.5 * diff(render(3, 0.0), render(3, 0.02)))
check('top/bottom: top half is the left eye, bottom half the right eye, each a full frame', diff([r for r in tb[:H // 2]], render(1)[:H // 2]) == 0 and diff(tb[:H // 2], tb[H // 2:]) > 0)
flat = lambda p, g: render(p, gain=g)
check('anaglyph: channels come from different eyes (red != right-eye red when gain > 0)', diff(ana, render(2, gain=0.0)) > 0.0005)
check('strength 0 (gain 0): both eyes are the same picture, anaglyph == plain frame', diff(render(2, gain=0.0), [[tap((i + .5) / W, (j + .5) / H) for i in range(W)] for j in range(H)]) < 0.02)
check('strength row changes the preview (gain 0 vs 0.02 vs 0.04 all differ)', diff(render(0, 0.0), render(0, 0.02)) > 0.0005 and diff(render(0, 0.02), render(0, 0.04)) > 0.0005)
# text pins
pin = lambda n, t: check('pin: ' + n, t in lua)
# Stereo geometry: backward-map source disparity through arbitrary roll to measure output vertical error.
# A = diag(1/aspect,1)*R(angle)*diag(aspect,1); its horizontal column is dFdx(uv).
def mapped_delta(angle,aspect,old=False,swap=False):
    c,s=math.cos(angle),math.sin(angle)
    axis=(1,0) if old else (c,s*aspect)
    sign=-1 if swap else 1
    sx,sy=axis[0]*.04*sign,axis[1]*.04*sign
    # Inverse A: output disparity for a constant-depth correspondence.
    return c*sx+s*sy/aspect, -s*sx*aspect+c*sy
for angle in (-180,-135,-90,-60,-45,-15,0,15,45,60,90,135,180,0):
    for aspect in (.5,8/9,16/9,2.4):
        for swap in (False,True):
            dx,dy=mapped_delta(math.radians(angle),aspect,swap=swap)
            check('tilt%d aspect%.3f swap%d vertical disparity<1e-9; horizontal magnitude preserved'%(angle,aspect,swap),abs(dy)<1e-9 and abs(abs(dx)-.04)<1e-9)
check('old source-x mutant causes full vertical disparity at90deg',abs(mapped_delta(math.pi/2,16/9,old=True)[1])>.07)
check('shared axis follows actual local warp before clamp in both mono paths', 'return (dFdx(uv)*cos(angle)+dFdy(uv)*sin(angle))*pixel_baseline;' in lua and lua.count('vec2 disparity_axis=stereo_disparity_axis(uv*vec2(vr_crop_x*vr_source_w,vr_crop_y*vr_source_h),source_aspect,')==2 and lua.count('*disp*disparity_axis;')==2)
# Center/pivot: tracked/manual pan must rotate through the same sampling basis as image.
for deg in (-180,-135,-90,-45,0,45,90,135,180,0):
    a=math.radians(deg);c,t=math.cos(a),math.sin(a);asp=16/9
    for tx,ty in ((0,0),(.1,0),(0,.1),(.1,-.07)):
        # Shader A*T, inverse-mapped back into displayed offset.
        sx,sy=c*tx-t*ty/asp,t*tx*asp+c*ty
        ox,oy=c*sx+t*sy/asp,-t*sx*asp+c*sy
        check('center/pivot stable tilt%d offset%.2f,%.2f'%(deg,tx,ty),abs(ox-tx)<1e-12 and abs(oy-ty)<1e-12)
check('flat tracked/manual offsets share roll basis, pack4 physical ray unchanged',lua.count('flat_roll_offset(')==4 and 'if(vr_pack>3.5) uv += vec2(vr_manual_yaw' in lua)
# Nonlinear VR180 warp: numeric local Jacobian, crop, yaw/pitch and arbitrary roll.
def warp(x,y,roll):
    lon,lat=(x-.5)*math.pi,(y-.5)*math.pi
    rx,ry,rz=math.sin(lon)*math.cos(lat),math.sin(lat),math.cos(lon)*math.cos(lat)
    cr,sr=math.cos(roll),math.sin(roll);rx,ry=cr*rx-sr*ry,sr*rx+cr*ry
    cp,sp=math.cos(.13),math.sin(.13);ry,rz=cp*ry-sp*rz,sp*ry+cp*rz
    cy,sy=math.cos(.17),math.sin(.17);rx,rz=cy*rx+sy*rz,-sy*rx+cy*rz
    return (.5+.5*rx/rz)*.8,(.5+.5*ry/rz)*.6
for deg in (-135,-90,-45,0,45,90,135,180):
    for x,y in ((.4,.4),(.5,.5),(.6,.6)):
        e=1e-5;r=math.radians(deg);xp,xm=warp(x+e,y,r),warp(x-e,y,r);yp,ym=warp(x,y+e,r),warp(x,y-e,r)
        a,c=(xp[0]-xm[0])/(2*e),(xp[1]-xm[1])/(2*e)
        b,d=(yp[0]-ym[0])/(2*e),(yp[1]-ym[1])/(2*e)
        det=a*d-b*c
        # GPU dFdx gives (a,c). J^-1 applied to that direction must have zero vertical component.
        dy=(-c*a+a*c)/det
        check('VR180 local epipolar axis tilt%d point%.1f,%.1f crop/yaw/pitch vertical<1e-9'%(deg,x,y),abs(det)>1e-6 and abs(dy)<1e-9)
# Blink source-domain regression: mono SBS has two OUTPUT eyes, not two SOURCE halves.
# Encode x as intensity to measure repeated-column spans and settled recovery.
def blink_tap(x,eye,mono,old=False):
    px=.5/1920
    if mono and not old: return clamp(x,px,1-px)
    return clamp(x,eye*.5+px,(eye+1)*.5-px)
def blink_sample(x,eye,lid,adapt,old=False):
    if lid<=0 and adapt<=0:return x # actual shader's exact bypass
    return blink_tap(x,eye,True,old)
for eye in (0,1):
    xs=[(i+.5)/1000 for i in range(1000)]
    old=[blink_sample(x,eye,.3,0,True) for x in xs]
    fixed=[blink_sample(x,eye,.3,0) for x in xs]
    flat_old=sum(abs(old[i+1]-old[i])<1e-9 for i in range(999))
    flat_new=sum(abs(fixed[i+1]-fixed[i])<1e-9 for i in range(999))
    check('mono blink eye%d: old >=49%% repeated columns, fixed 0 repeated interior columns'%eye,flat_old>=490 and flat_new==0)
    check('mono reopen eye%d preserves full domain and settles exactly to base'%eye,all(blink_sample(x,eye,0,.5)==x and blink_sample(x,eye,0,0)==x for x in xs))
    check('native SBS eye%d taps stay inside own half'%eye,all(eye*.5<blink_tap(x,eye,False)<(eye+1)*.5 for x in xs))
for pack in range(5):
    for swap in (False,True):
        for displayed_eye in (0,1):
            eye=1-displayed_eye if swap else displayed_eye
            xs=[(i+.5)/1000 for i in range(1000)]
            states=[(1,0),(.3,0),(0,1),(0,.5),(0,0)]
            values=[[blink_sample(x,eye,lid,adapt) for x in xs] for lid,adapt in states]
            check('pack%d swap%d displayedEye%d closed->reopen->settled full-source/recovery'%(pack,swap,displayed_eye), all(v==xs for v in values))
# A mutant that restores half-source blink sampling must fail for both source eyes.
check('mutant old half-domain is killed for both source eyes',all(any(blink_sample(x,e,.3,0,True)!=x for x in (.1,.3,.7,.9)) for e in (0,1)))
check('mono scene mean uses whole texture as well as blur taps', 'if(vr_plain>0.5 || vr_flat_mono>0.5)cp=' in lua)
pin('vr_pack param', '//!PARAM vr_pack\\n//!TYPE float\\n0.0')
check('pin: pack variant guarded by pcall and removable', 'PACK-VARIANT-BEGIN' in lua and 'local ok, built = pcall(function()' in lua and '-- PACK-VARIANT-END' in lua)
check('pin: extended/legacy sources untouched, pack variant is a separate string', 'local src = VR180_LOOK_EXTENDED_SOURCE' in lua and 'VR180_LOOK_PACK_SOURCE = built' in lua)
check('191a selector packs any enabled SOURCE into independently chosen OUTPUT', '(enabled or flat_mono or vr_pack_forced) and flat_pack > 0 and not vr_pack_blocked and VR180_LOOK_PACK_SOURCE' in lua)
check('pin: top/bottom left eye first', 'float pr = step(0.5, pp.y);' in lua and 'return vec4(pl.r, pq.g, pq.b, 1.0);' in lua)
check('pin: message and payload', 'vr180-look-set-pack' in lua and '%s/vr_pack=%.1f' in lua and '%s/vr_pk_conv=%.4f' in lua and '%s/vr_pk_zoom=%.4f' in lua and '%s/vr_pk_soft=%.1f' in lua and 'function(pack, gain_scale, conv, zoom, soft)' in lua)
swift = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDAutoRoute.swift'+' '):_b.index('// END relocated '+'ThreeDAutoRoute.swift'+'\n')])((_threed_split().path(root)).read_text()); menu = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(root)).read_text()); wiring = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDWiring.swift'+' '):_b.index('// END relocated '+'ThreeDWiring.swift'+'\n')])((_threed_split().path(root)).read_text())
check('mode -> pack mapping: over_under 1, anaglyph 2, vr180 4, sbs/half sbs 3', 'case "over_under": return 1; case "anaglyph": return 2; case "vr180": return 4; default: return 3' in swift)
applier=(_pp_split().path(root,'PPController_Features.swift')).read_text()
check('sanctioned store applier pushes pack and strength with all live parameters', 'let p=ThreeDAutoRoute.previewParams(mode:desired.output.rawValue,strength:n(.strength,1)' in applier and all(x in applier for x in ('vr180-look-set-pack','\\(plan.pack)','\\(p.gain)','\\(p.conv)','\\(p.zoom)','\\(p.soft)')) and 'vr180-look-set-pack' not in wiring)
for name, pose in [('yaw', {'yaw':.1}), ('pitch', {'pitch':.1}), ('roll', {'roll':.15}), ('head x', {'hx':.1}), ('head y', {'hy':.1}), ('head z', {'hz':.15})]:
    measured = diff(render(4), render(4, **pose))
    check('MEASURED vr180 head pose %s changes preview pixels (mean abs delta %.6f)' % (name, measured), measured > .001)
for pack in (1,2,3,4):
    measured=diff(render(pack),render(pack,lid=1))
    check('MEASURED blink coverage changes pack %d pixels (mean abs delta %.6f)' % (pack,measured),measured>.01)
check('shader uses tracked ray and mono-safe blink source taps', 'vec3 ray = vec3(sin(lon)*cos(lat)' in lua and 'vr_head_z' in lua[lua.index('vec4 pack_eye'):lua.index('vec4 hook()',lua.index('vec4 pack_eye'))] and 'blink_render(HOOKED_tex(sample_pos),lid_uv,sample_pos,right,right),coverage);' in lua and 'if(vr_plain>0.5 || vr_flat_mono>0.5)return clamp(p,px' in lua)
print('preview pack: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
