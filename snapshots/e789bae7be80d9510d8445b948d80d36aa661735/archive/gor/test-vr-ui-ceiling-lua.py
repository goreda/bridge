#!/usr/bin/env python3
"""UI ceiling guard test: runs the shipped vr180-look.lua film_frame_snapshot
through an mp API double and checks the owner-ordered UI zoom ceiling.

Owner order (arch-195c follow-up, relayed by Delivery): in flat 2D->3D SBS, when
zoom changes (head motion or shortcut), UI elements must wait at the boundary of
their reserved zone instead of leaving the window or crossing the other eye's
zone. The film keeps its full zoom. Addendum: the guard must not change any
in-limit behavior, so at or below the ceiling the published frame must equal the
pre-guard formula exactly.

Checks (flat SBS branch of film_frame_snapshot, reserve=1 for 2D sources):
  rest / zoom-out / roll: published scale equals the pre-guard formula (unchanged)
  shortcut zoom-in / head dolly-in: published scale clamps at fit (the zone edge),
  pan uses the clamped scale, and the film uniforms keep the full zoom.
No shader pixels, no AppKit, no native input acceptance.
"""
from pathlib import Path
from lupa import LuaRuntime
import tempfile, math, sys

root = Path(__file__).resolve().parent
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''handlers={}; timers={}; props={}; clock=0; script=''; mp={msg={info=function()end,warn=function()end,error=function()end}}
mp.get_property=function(k) return props[k] end
mp.get_property_number=mp.get_property;mp.get_property_native=mp.get_property
mp.set_property=function(k,v) props[k]=v;return true end  -- real mpv returns success
mp.set_property_number=mp.set_property;mp.set_property_native=mp.set_property
mp.get_time=function() return clock end
mp.register_script_message=function(k,f) handlers[script..':'..k]=f end
mp.add_periodic_timer=function(t,f) local v={f=f,alive=true};v.kill=function(self)self.alive=false end;timers[#timers+1]=v;return v end
mp.add_hook=function()end;mp.observe_property=function()end;mp.register_event=function()end
mp.commandv=function(...)local a={...};if a[1]=='change-list' then props.opts=a[4];return true elseif a[1]=='script-message-to' then local f=handlers[a[2]..':'..a[3]];if f then f(table.unpack(a,4))end end return true end  -- real mpv returns success
function tick(dt) clock=clock+dt;for _,t in ipairs(timers)do if t.alive then t.f()end end end
''')
g = lua.globals(); p = g.props

W, H = 1400.0, 800.0
EYE_ASPECT = 16.0 / 9.0
FOV = 135.0  # resting fov: makes the distance factor exactly 1 at head_z=0
GAP = 0.0125  # VR_PHYSICAL_GAP_FRAC default in the shipped script

def pre_guard_frame(roll, manual_fov, head_z, head_x):
    """Independent python re-derivation of the flat SBS branch (gap=0.0125, reserve=1).

    Returns (fit, pre_scale, clamped_scale, leftX, leftY) with the UI ceiling and
    the window-containment pan clamp applied."""
    oa = W / H
    le = 0.5 - GAP * 0.25
    eye = oa * le
    aspect = EYE_ASPECT  # source_eye_crop 1:1
    cx, cy = 1.0, 1.0
    if aspect > eye: cy = eye / aspect
    else: cx = aspect / eye
    fw, fh = cx * eye, cy
    held = -roll  # viewer_cross_eye = 0
    delta = roll - held
    c, sn = math.cos(roll), math.sin(roll)
    spacing = max((0.5 + GAP * 0.25) * oa,
                  fw * abs(math.cos(delta)) + fh * abs(math.sin(delta)) + GAP * oa * 0.5)
    bw = spacing * abs(math.cos(held)) + fw * abs(c) + fh * abs(sn)
    bh = spacing * abs(math.sin(held)) + fh * abs(c) + fw * abs(sn)
    fit = min(1.0, oa / max(bw, 1e-6), 1.0 / max(bh, 1e-6))
    zoom = 2 ** (-manual_fov / 60.0)
    distance = max(0.1, 1 - head_z)  # tan(fov/2)/tan(135/2) == 1 at fov=135
    pre = fit * zoom / distance
    scale = min(pre, fit)
    hx = -head_x * 0.5
    margin = max(0.0, (1 - distance) * 0.5)
    ox = min(max((c * hx * aspect + sn * 0.0) / aspect, -margin), margin)
    oy = min(max(-sn * hx * aspect + c * 0.0, -margin), margin)
    px = (c * ox * aspect - sn * oy) / aspect
    py = sn * ox * aspect + c * oy
    panx = -px * cx * le * scale
    pany = -py * cy * scale
    dx = spacing * math.cos(held) * fit / oa
    dy = spacing * math.sin(held) * fit
    # Window containment clamp (same formula as the guard in the script).
    hwx = (cx * le * abs(c) + cy * abs(sn) / oa) * scale / 2
    hwy = (cx * oa * le * abs(sn) + cy * abs(c)) * scale / 2
    xlo, xhi = abs(dx) / 2 + hwx - 0.5, 0.5 - abs(dx) / 2 - hwx
    ylo, yhi = abs(dy) / 2 + hwy - 0.5, 0.5 - abs(dy) / 2 - hwy
    panx = 0.0 if xlo > xhi else min(max(panx, xlo), xhi)
    pany = 0.0 if ylo > yhi else min(max(pany, ylo), yhi)
    leftX = 0.5 - dx / 2 + panx
    leftY = 0.5 - dy / 2 + pany
    return fit, pre, scale, leftX, leftY

def pair_aabb(f):
    """Rotated AABB of the published chrome pair, normalized window units."""
    oa = W / H
    a = f['angle']
    c, sn = abs(math.cos(a)), abs(math.sin(a))
    hx = (f['frameW'] * c + f['frameH'] * sn / oa) * f['scale'] / 2
    hy = (f['frameW'] * oa * sn + f['frameH'] * c) * f['scale'] / 2
    x0 = min(f['leftX'], f['leftX'] + f['replicaX']) - hx
    x1 = max(f['leftX'], f['leftX'] + f['replicaX']) + hx
    y0 = min(f['leftY'], f['leftY'] + f['replicaY']) - hy
    y1 = max(f['leftY'], f['leftY'] + f['replicaY']) + hy
    return x0, y0, x1, y1

failures = []
def check(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok: failures.append(name)

with tempfile.TemporaryDirectory() as d:
    p['config-dir'] = d
    p['osd-width'] = W; p['osd-height'] = H
    p['keepaspect'] = True
    p['video-aspect-override'] = 'no'
    p['path'] = 'clip.mp4'
    for name in ('vr180-look', 'gor-fit'):
        g.script = name.replace('-', '_')
        lua.execute((root / 'Resources/vendor/mpv/scripts' / (name + '.lua')).read_text())
    def call(script, name, *args): g.handlers[script + ':' + name](*map(str, args))
    def orient(yaw=0, pitch=0, fov=FOV, roll=0, head_x=0, head_y=0, head_z=0):
        call('vr180_look', 'vr180-look-set-orientation', yaw, pitch, fov, roll, 0, head_x, head_y, head_z, 0, 'none', 0.1118, 0, 0)
    def frame():
        f = p['user-data/vr180-look/film-frame']
        assert f is not None and f is not False, 'no film frame published'
        return f
    def opts(): return {k.split('/')[-1]: float(v) for k, v in (x.split('=') for x in p.opts.split(','))}

    # Revision-gated routes: establish the store revision first, then route the
    # flat-2d3d (2D->3D SBS) projection as the store applier would.
    call('vr180_look', 'vr180-look-store-revision', 1, 'flat-2d3d', 'store-applier',
         'true', 0, 0, 'sbs', 'engine', 'gen', 'clip.mp4', 123)
    call('vr180_look', 'vr180-look-set-enabled', 'true', 1, 'store-applier')
    call('vr180_look', 'vr180-look-set-projection', 'flat-2d3d', EYE_ASPECT, 1, 'store-applier')

    last_seq = 0
    def fresh():
        f = frame()
        # Payload dedupe republishes only on uniform changes; a no-op stimulus
        # legitimately keeps the previous sequence. Stimulus-specific assertions
        # below would fail on a stale frame, so >= is safe here.
        assert f['sequence'] >= last_seq, 'sequence went backwards'
        return f

    # 1. Rest: scale sits exactly at the zone fit; pre-guard formula agrees (unchanged).
    orient(); f = fresh(); last_seq = f['sequence']
    fit, pre, scale, _, _ = pre_guard_frame(0, 0, 0, 0)
    check('rest-fit-matches-formula', abs(f['fit'] - fit) < 1e-9)
    check('rest-scale-unchanged', abs(pre - fit) < 1e-9 and abs(f['scale'] - fit) < 1e-9)

    # 2. Zoom out (shortcut): below the ceiling, published scale equals the pre-guard value.
    call('vr180_look', 'vr180-look-nudge', 0, 0, 6, 0)  # manual_fov=+6 -> zoom 2^-0.1 < 1
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, _, _ = pre_guard_frame(0, 6, 0, 0)
    check('zoom-out-below-ceiling', pre < fit - 1e-9)
    check('zoom-out-scale-unchanged', abs(f['scale'] - pre) < 1e-9)

    # 3. Zoom in (shortcut): pre-guard scale exceeds the zone; UI clamps at fit.
    call('vr180_look', 'vr180-look-nudge', 0, 0, -12, 0)  # manual_fov=-6 -> zoom 2^0.1 > 1
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, _, _ = pre_guard_frame(0, -6, 0, 0)
    check('zoom-in-would-overflow', pre > fit + 1e-9)
    check('zoom-in-scale-clamped-at-fit', abs(f['scale'] - fit) < 1e-9)
    check('zoom-in-film-keeps-full-zoom', abs(opts()['vr_manual_view'] - (-6)) < 1e-6)

    # 4. More zoom-in: the UI holds at the boundary instead of growing past it.
    for _ in range(4): call('vr180_look', 'vr180-look-nudge', 0, 0, -6, 0)  # manual_fov=-30
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, _, _ = pre_guard_frame(0, -30, 0, 0)
    check('deep-zoom-would-overflow', pre > fit * 1.2)
    check('deep-zoom-holds-at-ceiling', abs(f['scale'] - fit) < 1e-9)
    x0, y0, x1, y1 = pair_aabb(f)
    check('deep-zoom-pair-inside-window', x0 >= -1e-9 and x1 <= 1 + 1e-9 and y0 >= -1e-9 and y1 <= 1 + 1e-9)

    # 5. Head dolly-in with head_x offset: distance shrinks (head-motion zoom); UI scale
    #    clamps at fit and pan follows the film with the clamped scale, not the raw one.
    for _ in range(5): call('vr180_look', 'vr180-look-nudge', 0, 0, 6, 0)  # manual_fov back to 0
    orient(head_x=0.2, head_z=0.5)
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, leftX, leftY = pre_guard_frame(0, 0, 0.5, 0.2)
    check('dolly-would-overflow', pre > fit * 1.9)
    check('dolly-scale-clamped-at-fit', abs(f['scale'] - fit) < 1e-9)
    check('dolly-pan-uses-clamped-scale', abs(f['leftX'] - leftX) < 1e-9)
    check('dolly-panY-matches-formula', abs(f['leftY'] - leftY) < 1e-9)
    x0, y0, x1, y1 = pair_aabb(f)
    check('dolly-pair-inside-window', x0 >= -1e-9 and x1 <= 1 + 1e-9 and y0 >= -1e-9 and y1 <= 1 + 1e-9)
    check('dolly-film-keeps-head-z', abs(opts()['vr_head_z'] - 0.5) < 1e-6)

    # 5b. Roll + dolly + head_x: rotated pair must stay inside the window while
    #     clamped; leftX/leftY match the replicated formula exactly.
    orient(roll=0.3, head_x=0.2, head_z=0.5)
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, leftX, leftY = pre_guard_frame(0.3, 0, 0.5, 0.2)
    check('rolldolly-would-overflow', pre > fit + 1e-9)
    check('rolldolly-scale-clamped', abs(f['scale'] - fit) < 1e-9)
    check('rolldolly-leftX-matches-formula', abs(f['leftX'] - leftX) < 1e-9)
    check('rolldolly-leftY-matches-formula', abs(f['leftY'] - leftY) < 1e-9)
    x0, y0, x1, y1 = pair_aabb(f)
    check('rolldolly-pair-inside-window', x0 >= -1e-9 and x1 <= 1 + 1e-9 and y0 >= -1e-9 and y1 <= 1 + 1e-9)

    # 6. Roll at rest: fit itself changes with roll; the guard stays inactive (unchanged).
    orient(roll=0.3)
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, _, _ = pre_guard_frame(0.3, 0, 0, 0)
    check('roll-fit-matches-formula', abs(f['fit'] - fit) < 1e-9)
    check('roll-scale-unchanged', abs(pre - fit) < 1e-9 and abs(f['scale'] - fit) < 1e-9)

    # 7. Back to rest: no sticking; the guard releases.
    orient()
    f = fresh(); last_seq = f['sequence']
    fit, pre, scale, _, _ = pre_guard_frame(0, 0, 0, 0)
    check('recovery-scale-back-at-fit', abs(f['scale'] - fit) < 1e-9)

    print('UI ceiling guard tests only; no shader pixels, AppKit or native input acceptance.')

sys.exit(1 if failures else 0)
