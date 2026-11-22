#!/usr/bin/env python3
"""Source-pinned analytic R2/R4 regression, not a GPU or mpv render.

Tests 3x3 interior markers, native disparities -2%/0/+2%, roll angles
-30/-15/-5/0/5/15/30 degrees and crossed-eye +/-15 degrees. Preview and
zero-disparity cells use a1px vertical-error bound. Native baked-disparity
cells use d_screen*abs(sin(theta))+1px, plus a two-sided nonzero-residual
check. This is an analytic model of the default interior affine chain,
not a parser-derived shader interpreter or exhaustive layout acceptance.

The candidate source SHA must match before a run can pass. Use
--variant current --source BASE_FILE to reproduce numeric baseline failures.
NumPy is required. --gain accepts the startup0.02 or menu-scale1 value0.04.
"""
import math, sys
import numpy as np

OUT_W, OUT_H = 2560.0, 1600.0          # fixture output raster
SRC_W, SRC_H = 2560.0, 720.0           # packed SBS source (per-eye 1280x720)
FOV = math.radians(135.0)
GAP = 0.0125                           # vr_gap_frac default (PHYSICAL_GAP_FRAC)
ZOOM_REF = math.radians(90.0)
PAR_STR, PAR_DISP = 0.4, -0.4          # PARALLAX_CORRECTION_STRENGTH/DISPARITY defaults
D3_GAIN = float(sys.argv[sys.argv.index('--gain') + 1]) if '--gain' in sys.argv else 0.04
THETAS = [-30, -15, -5, 0, 5, 15, 30]
DISPARITIES = [-0.02, 0.0, 0.02]       # fraction of eye width
GRID = [0.2, 0.5, 0.8]

def M_rot(c, s):  # GLSL mat2(c,s,-s,c): (x,y)->(c*x-s*y, s*x+c*y)
    return np.array([[c, -s], [s, c]])

class Chain:
    """y = J x + t composed step by step; J = d(y)/d(pos), pos in [0,1]^2."""
    def __init__(self):
        self.J = np.eye(2); self.t = np.zeros(2)
    def apply(self, A, b):
        self.t = A @ self.t + b; self.J = A @ self.J
    def fwd(self, p): return self.J @ p + self.t
    def inv(self, q): return np.linalg.solve(self.J, q - self.t)

def total_shift():
    ref = math.tan(ZOOM_REF * 0.5) / math.tan(FOV * 0.5)
    return max(-0.8, min(0.8, PAR_DISP * (ref - 1.0) * PAR_STR + 0.0 + 0.0))

def stereo_partition(pos, aspect, vr_roll, cross):
    angle = -vr_roll * (1.0 if cross else -1.0)
    q = (pos - 0.5) * np.array([aspect, 1.0])
    c, s = math.cos(angle), math.sin(angle)
    # GLSL mat2(c,s,-s,c)*q: first column (c,s) -> rotation by +angle
    q = np.array([c * q[0] - s * q[1], s * q[0] + c * q[1]])
    return q / np.array([aspect, 1.0]) + 0.5

def build_flat_chain(variant, theta_deg, right, mono, tb, cross=False, src_w=SRC_W, src_h=SRC_H, eye_aspect=None):
    """Backward map screen pos -> packed source uv, as affine Chain,
    for one eye. Returns (chain, info) with gap/ownership checkers.
    variant: old = pre-191c @0d0f37b9; current = shipped @7c771b2/29db62bb;
    fixA = eye-uv from split_pos, pair_uv unchanged (losing candidate: double
    compensation, kept as evidence);
    patched = the R2 fix delivered in vr_patched.lua: eye-uv from split_pos
    (rotated eye frame), pair_uv centre shift horizontal in the rotated frame
    (centre_angle=0), with picture rotation +held_angle to cancel the partition
    in both parallel and crossed modes. Fit/bounds/axis/convergence are unchanged.
    The port MUST stay in lockstep with the source; structural checks in main()
    tie them. World-horizon orientation is tested separately by the generated-
    source angle regression, since interocular R4 alone misses common rotation."""
    th = math.radians(theta_deg)
    vr_roll, vr_head_roll = th, th
    sign = 1.0 if cross else -1.0
    angle = vr_head_roll * sign          # pair/axis angle used by the code
    half_gap = GAP * 0.25
    le, rs = 0.5 - half_gap, 0.5 + half_gap
    oa = OUT_W / OUT_H
    viewport_aspect = OUT_W * le / OUT_H
    # source_aspect: default branch (no overrides, crop 1, source window full)
    # The main fixtures send a positive vr_eye_aspect, like the host. In
    # particular half-SBS restores horizontal squeeze and TB doubles packed H.
    # Keep the shader fallback only for callers explicitly testing no override.
    src_aspect = eye_aspect if eye_aspect is not None else (src_w * (1.0 if mono else 0.5)) / src_h
    content = np.array([1.0, 1.0])
    if src_aspect > viewport_aspect: content[1] = viewport_aspect / src_aspect
    else: content[0] = src_aspect / viewport_aspect
    ts = total_shift()
    ch = Chain()
    side = right - 0.5
    # b0 (fix variants): express the pixel in the rotated eye frame first -
    # stereo_partition(pos) itself, so the eye viewport is axis-aligned there.
    if variant in ("fixA", "patched"):
        pa = -vr_roll * sign   # stereo_partition's angle argument
        c, s = math.cos(pa), math.sin(pa)
        A = np.diag([1.0 / oa, 1.0]) @ np.array([[c, -s], [s, c]]) @ np.diag([oa, 1.0])
        ch.apply(A, np.array([0.5, 0.5]) - A @ np.array([0.5, 0.5]))
    # b1: eye-normalize (both variants identical for interior points)
    if right > 0.5: ch.apply(np.diag([1.0 / (1.0 - rs), 1.0]), np.array([-rs / (1.0 - rs), 0.0]))
    else: ch.apply(np.diag([1.0 / le, 1.0]), np.zeros(2))
    # b2: surface_uv identity (no surface override)
    if variant in ("current", "fixA", "patched"):
        # b3: stereo_pair_uv (roll-compensated centres + fit)
        separation = 0.5 + GAP * 0.25
        held = vr_roll * sign
        cr, sr = abs(math.cos(vr_roll)), abs(math.sin(vr_roll))
        fw, fh = content[0] * viewport_aspect, content[1]
        delta = vr_roll - held
        spacing = max(separation * oa,
                      fw * abs(math.cos(delta)) + fh * abs(math.sin(delta)) + GAP * oa * 0.5)
        bound_w = spacing * abs(math.cos(held)) + fw * cr + fh * sr
        bound_h = spacing * abs(math.sin(held)) + fh * cr + fw * sr
        fit = min(1.0, min(oa / max(bound_w, 1e-6), 1.0 / max(bound_h, 1e-6)))
        shift_angle = angle if variant in ("current", "fixA") else 0.0
        shx = side * (spacing * math.cos(shift_angle) * fit - separation * oa) / viewport_aspect
        shy = side * spacing * math.sin(shift_angle) * fit
        ch.apply(np.eye(2), -np.array([shx, shy]))
        ch.apply(np.eye(2) / fit, np.array([0.5, 0.5]) - np.array([0.5, 0.5]) / fit)
    else:
        # o3: old centre handling: content shrink + horizontal shift only
        pass
    # content scale + zoom (zoom=1)
    cont = content.copy()
    if variant == "old" or not mono:
        cont = cont * (1.0 - abs(ts) * 0.5)
    if variant == "old":
        sx = 1.0 / cont[0]; sy = 1.0 / cont[1]
        # uv.x -= (right?1:-1)*ts*0.25 happens BEFORE the (uv-0.5)/cont scale
        ch.apply(np.eye(2), -np.array([(1.0 if right > 0.5 else -1.0) * ts * 0.25, 0.0]))
        ch.apply(np.diag([sx, sy]), -np.array([0.5 * sx, 0.5 * sy]))
    else:
        ch.apply(np.diag([1.0 / cont[0], 1.0 / cont[1]]),
                 -np.array([0.5 / cont[0], 0.5 / cont[1]]))
    # roll about origin in aspect space (picture orientation, both variants)
    # Partition is -held_angle. Picture rotation is its inverse in both modes.
    picture_angle = vr_roll * sign if variant == 'patched' else -vr_roll
    crr, srr = math.cos(picture_angle), math.sin(picture_angle)
    R = np.diag([1.0 / src_aspect, 1.0]) @ M_rot(crr, srr) @ np.diag([src_aspect, 1.0])
    ch.apply(R, np.zeros(2))
    # distance/fov scale = 1 at defaults; +0.5
    ch.apply(np.eye(2), np.array([0.5, 0.5]))
    # disparity axis at this point (J so far, per-pixel derivatives)
    Jpx = ch.J @ np.diag([1.0 / OUT_W, 1.0 / OUT_H])   # d(uv)/d(pixel)
    dFdx, dFdy = Jpx[:, 0], Jpx[:, 1]
    if variant in ("current", "fixA", "patched"):
        pixel_baseline = viewport_aspect * OUT_H        # eye width in px
        axis = (dFdx * math.cos(angle) + dFdy * math.sin(angle)) * pixel_baseline
    else:
        axis = dFdx
        metric = math.hypot(axis[0] * max(src_aspect, 0.001), axis[1])
        axis = axis * (max(src_aspect, 0.001) / metric) if metric > 1e-7 else np.zeros(2)
    # mono: common interior window before depth displacement
    # (d3_common_uv: support=(|gain|*(0.05+|0.5-plane|)+|conv|*0.25)*|axis|, plane=0.5)
    if mono and variant in ("current", "fixA", "patched"):
        sup = (abs(D3_GAIN) * 0.05 + abs(ts) * 0.25) * np.abs(axis)
        margin = min(0.49, max(sup[0], sup[1]))
        ch.apply(np.eye(2) * (1.0 - 2.0 * margin), np.array([0.5, 0.5]) * (2.0 * margin))
    # convergence along the axis (the post-191c code applies it to SBS and mono
    # alike; the old variant already shifted horizontally at o3)
    if variant in ("current", "fixA", "patched"):
        ch.apply(np.eye(2), (-1.0 if right > 0.5 else 1.0) * ts * 0.25 * axis)
    # crop (1,1) + source window (0,0,1,1): identity
    # depth displacement for the pseudo-3D preview, per sampled point:
    info = {"le": le, "rs": rs, "aspect": oa, "angle": angle, "vr_roll": vr_roll,
            "axis": axis, "total_shift": ts, "tb": tb, "mono": mono}
    return ch, info

def packed_from_eye(m, eye, tb):
    return (m[0], (m[1] + eye) * 0.5) if tb else ((m[0] + eye) * 0.5, m[1])

def screen_pos_of_source(chain, info, right, q_packed):
    eye_uv = (q_packed[0], q_packed[1] * 2.0 - (1.0 if right > 0.5 else 0.0)) if info["tb"] \
        else (q_packed[0] * 2.0 - (1.0 if right > 0.5 else 0.0), q_packed[1])
    p = chain.inv(np.array(eye_uv))
    return p

def measure(variant, mono, tb, theta, cross=False, markers=GRID, disparities=DISPARITIES, src=(SRC_W, SRC_H), eye_aspect=None):
    th = math.radians(theta)
    sign = 1.0 if cross else -1.0
    a = np.array([math.cos(th * sign), math.sin(th * sign)])
    a_perp = np.array([-a[1], a[0]])
    out = []
    chL, iL = build_flat_chain(variant, theta, 0.0, mono, tb, cross, *src, eye_aspect=eye_aspect)
    chR, iR = build_flat_chain(variant, theta, 1.0, mono, tb, cross, *src, eye_aspect=eye_aspect)
    for my in markers:
        for mx in markers:
            for d in (disparities if not mono else [0.0]):
                if mono:
                    q = (mx, my)
                    local_y = q[1]
                    depth = min(1.0, max(0.0, 0.5 + 0.1 * (local_y - 0.5)))
                    disp = D3_GAIN * (depth - 0.5)
                    qL = np.array(q) - disp * iL["axis"]   # backward: displaced=uv+side*disp*axis
                    qR = np.array(q) + disp * iR["axis"]
                    pL = chL.inv(qL); pR = chR.inv(qR)
                else:
                    pL = screen_pos_of_source(chL, iL, 0.0, packed_from_eye((mx, my), 0.0, tb))
                    pR = screen_pos_of_source(chR, iR, 1.0, packed_from_eye((mx + d, my), 1.0, tb))
                # ownership/gap sanity on the ROTATED partition (current) or plain split (old)
                for p, ch, ii in ((pL, chL, iL), (pR, chR, iR)):
                    sp = stereo_partition(p, ii["aspect"], ii["vr_roll"], cross) if variant in ("current", "fixA", "patched") else p
                    in_gap = ii["le"] <= sp[0] < ii["rs"]
                    out.append({"theta": theta, "cross": cross, "mx": mx, "my": my, "d": d,
                                "p": p, "eye": "R" if p is pR else "L", "gap": in_gap})
                dp = (pR - pL) * np.array([OUT_W, OUT_H])
                out.append({"theta": theta, "cross": cross, "mx": mx, "my": my, "d": d,
                            "e_v": float(dp @ a_perp)})
    return out

from pathlib import Path

SOURCE = Path(sys.argv[sys.argv.index('--source') + 1]) if '--source' in sys.argv else Path(__file__).resolve().parents[2] / 'Resources/vendor/mpv/scripts/vr180-look.lua'
BASE_SHA = 'c455d945818a23ed7ddcb77a22002d12873430e53198b0ef253a673d7ccbeffc'
CANDIDATE_SHA = 'be74e78f7b9f9819fe62ea5bdb89d9b601ed3e2d76c42abdb0edf36afaba3bcc'

def structural_ties(variant):
    import hashlib
    source = SOURCE.read_text(encoding='utf-8')
    expected = CANDIDATE_SHA if variant == 'patched' else BASE_SHA
    actual = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    ok = actual == expected
    print(('ok  ' if ok else 'FAIL') + ' source binding: ' + actual)
    if variant == 'patched':
        checks = [
            'split_pos.x-rs)/(1.0-rs) : split_pos.x/le, split_pos.y',
            'float centre_angle)',
            'spacing*cos(centre_angle)*fit',
            'float eye_roll=vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);',
            'float cr=cos(eye_roll),sr=sin(eye_roll);',
            'stereo_pair_uv(uv,right,viewport_aspect,content,0.0)',
            'content,vr_head_roll*(vr_cross_eye>0.5 ? 1.0:-1.0))',
            'dFdx(uv)*cos(angle)+dFdy(uv)*sin(angle)',
        ]
        ok = ok and all(item in source for item in checks)
    return ok

def main():
    variant = "patched"
    if "--variant" in sys.argv: variant = sys.argv[sys.argv.index("--variant") + 1]
    fails = []
    if not structural_ties(variant): fails.append("structural ties")
    def check(name, cond, extra=""):
        print(("ok  " if cond else "FAIL") + " " + name + (" | " + extra if extra and not cond else ""))
        if not cond: fails.append(name)

    # (name, mono, TB, packed width/height, explicit per-eye display aspect).
    # Mirrors knownEyeAspect's full-SBS / half_sbs / flat-tb / mono contracts.
    modes = [("sbs", False, False, 2560.0, 720.0, 1280.0 / 720.0),
             ("half", False, False, 1280.0, 720.0, 1280.0 / 720.0),
             ("tb", False, True, 1280.0, 1440.0, 1280.0 / 720.0),
             ("mono", True, False, 1280.0, 720.0, 1280.0 / 720.0)]
    worst = {}
    for name, mono, tb, sw, sh, aspect in modes:
        res = []
        for th in THETAS:
            res += measure(variant, mono, tb, th, src=(sw, sh), eye_aspect=aspect)
        # cross-eye sign convention runs
        res += measure(variant, mono, tb, 15, cross=True, src=(sw, sh), eye_aspect=aspect)
        res += measure(variant, mono, tb, -15, cross=True, src=(sw, sh), eye_aspect=aspect)
        ev = [r for r in res if "e_v" in r]
        mx_ev = max(abs(r["e_v"]) for r in ev)
        worst[name] = mx_ev
        gaps = [r for r in res if r.get("gap")]
        check(f"{name}: marker clear of gap band", len(gaps) == 0, str(len(gaps)))
        # Plan-doc R4 bounds (docs/plan/191c-quality-tiers-stereo-fusion.md):
        # preview/mono <= 1 px; native SBS/half/TB <= d_screen*|sin(theta-phi)|+1px,
        # d_screen = that marker's screen disparity at theta=0 (self-calibrated;
        # ~= 2% of the 1272px eye viewport = 25.4px for the +/-2% markers).
        # Native content disparity is tested separately from geometric alignment.
        # Zero-disparity markers retain the strict1px bound.
        res0 = measure(variant, mono, tb, 0, src=(sw, sh), eye_aspect=aspect)
        pos0 = {}
        for r in res0:
            if "p" in r: pos0[(r["mx"], r["my"], r["d"], r["eye"])] = r["p"]
        worst_ratio, worst_blanket = 0.0, 0.0
        for r in ev:
            if mono or abs(r["d"]) < 1e-9:
                bound = 1.0
            else:
                k0 = (r["mx"], r["my"], 0.0, "R"); kd = (r["mx"], r["my"], r["d"], "R")
                ds = float(np.linalg.norm((pos0[kd] - pos0[k0]) * np.array([OUT_W, OUT_H]))) \
                    if k0 in pos0 and kd in pos0 else 0.02 * 0.5 * OUT_W
                bound = ds * abs(math.sin(math.radians(r["theta"]))) + 1.0
            worst_ratio = max(worst_ratio, abs(r["e_v"]) / bound)
            worst_blanket = max(worst_blanket, abs(r["e_v"]))
        check(f"{name}: |e_v| within plan R4 bound (worst {worst_ratio:.4f}x)", worst_ratio <= 1.0,
              f"worst={worst_ratio:.4f}x bound (blanket-1px max={worst_blanket:.4f}px)")
        # G2 adjust (2026-11-21): the strict 1 px assert applies to d=0 markers
        # only (already the bound above). The +/-2% residual is EXPECTED
        # geometry (baked disparity projection d*|sin(theta-phi)|), recorded
        # here and pinned from BOTH sides so the test cannot pass vacuously
        # with the disparity silently unapplied.
        if not mono:
            pred = {}
            for r in ev:
                if abs(r["d"]) > 1e-9 and abs(r["theta"]) == 30 and not r["cross"]:
                    k0 = (r["mx"], r["my"], 0.0, "R"); kd = (r["mx"], r["my"], r["d"], "R")
                    if k0 in pos0 and kd in pos0:
                        ds = float(np.linalg.norm((pos0[kd] - pos0[k0]) * np.array([OUT_W, OUT_H])))
                        pred.setdefault("m", []).append((abs(r["e_v"]), ds * 0.5))  # sin(30)=0.5
            if pred:
                meas = max(x[0] for x in pred["m"]); ex = max(x[1] for x in pred["m"])
                # Two-sided pin: upper = plan R4 slack; lower guards against a
                # vacuous pass with disparity silently unapplied. Lower factor
                # 0.4 accommodates the aspect-space anisotropy between the
                # partition rotation (out aspect) and the picture roll (source
                # aspect): the baked-disparity direction on screen is h', not
                # exactly screen-x, so the residual is d*|sin(delta)| with
                # delta != theta (measured ratios 0.57-0.84 of d*sin30).
                ok_res = 0.4 * ex <= meas <= ex + 1.0
                check(f"{name}: +/-2% residual recorded as expected (measured {meas:.3f} px vs d*sin30={ex:.3f} px at 30 deg)",
                      ok_res, f"measured={meas:.3f} predicted_naive={ex:.3f}")
        per_t = {}
        for r in ev: per_t[r["theta"]] = max(per_t.get(r["theta"], 0.0), abs(r["e_v"]))
        print("     per-theta max|e_v| px: " + " ".join(f"{t}:{v:.3f}" for t, v in sorted(per_t.items())))

    # t=0 identity current vs pre-191c (SBS/TB chain; the partition claim)
    if variant in ("current", "patched"):
        worst_id = 0.0
        for tb in (False, True):
            for right in (0.0, 1.0):
                c_new, _ = build_flat_chain(variant, 0, right, False, tb)
                c_old, _ = build_flat_chain("old", 0, right, False, tb)
                for gy in np.linspace(0.05, 0.95, 10):
                    for gx in np.linspace(0.05, 0.95, 10):
                        p = np.array([gx * (0.5 - GAP * 0.25) + (0.5 + GAP * 0.25) * right, gy])
                        d = np.linalg.norm(c_new.fwd(p) - c_old.fwd(p))
                        worst_id = max(worst_id, d)
        check("theta=0 SBS/TB identical to pre-191c (max duv %.2e)" % worst_id, worst_id <= 1e-9)
        # mono t=0 delta: report only (history: shipped R3 changed the mono window math)
        c_new, _ = build_flat_chain("current", 0, 0.0, True, False)
        c_old, _ = build_flat_chain("old", 0, 0.0, True, False)
        dm = max(np.linalg.norm(c_new.fwd(np.array([x, y])) - c_old.fwd(np.array([x, y])))
                 for x in np.linspace(0.05, 0.45, 5) for y in np.linspace(0.05, 0.95, 5))
        print(f"     note: mono preview t=0 delta vs pre-191c = {dm:.6f} source-uv (shipped history, informational)")

    print()
    if fails:
        print(f"FAILURES={len(fails)} variant={variant}")
        sys.exit(1)
    print(f"ALL_CHECKS_PASS variant={variant}")

if __name__ == "__main__":
    main()
