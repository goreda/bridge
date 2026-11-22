#!/usr/bin/env python3
"""photon-sharp OUTCOME test on rendered pixels (owner ruling 189p: P3 > 118g on conflict).

The real photon-sharp shader text (extracted from photon-sharp.lua) runs through mpv's gpu path
(--vo=gpu with --glsl-shaders; `screenshot-to-file window` captures the post-shader window), compared with the
same frame with photon off. Software VO paths are not used. Fixtures are generated here (no third-party clips).
Amount = base(scene mid) x ps_multiplier(src,out) exactly as the host computes it (real ps_refresh_adaptive, Lua 5.1).

MARGINS were written before the first run and are never tuned afterwards:
  P3 at 480p source: overshoot <= 5% of step; ringing lobes beyond the first <= 1; noise gain <= 1.15x;
     no metric worse than the 2160p-source value by more than 1.5x (floors: overshoot 1%, lobes 1, noise gain 1.0).
  118g as effect: sharpness gain (10-90% edge rise width off/on) at 480p >= 1.5x the 2160p gain,
     unless a P3 guard failed at that amount.
Needs: mpv (gpu path with glsl-shaders), Xvfb or a display, numpy, Pillow, lupa. Env: MPV=/path/to/mpv.
Usage: sharp_outcome.py OUT.tsv [--srcs 720,1080]  (R1: adds those source rows to the tsv and checks the mid-raster P3 margins; --mid re-checks an existing tsv)    [--scale480 S] [--kinds step,text,gradient,grain]  (--kinds none = verdict from an existing tsv; runs can be split)   (S scales the 480p amount; default 1.0 = current multiplier)
Labels: native-render = this script's mpv capture (Mesa GL under Xvfb unless run on a real GPU); not owner-eyes."""
import os, pathlib, re, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageFilter
from lupa import lua51

# ---- margins (fixed before first run) ----
P3_OVERSHOOT_MAX = 5.0      # % of step
P3_RING_MAX = 1             # lobes beyond the first
P3_NOISE_GAIN_MAX = 1.15
P3_REL_MAX = 1.5            # vs 2160p value
G118_RATIO_MIN = 1.5
BLUR_SIGMA_480 = 1.2        # source px at 480p; scales with height (fixture definition, not a margin)
FLOORS = dict(overshoot=1.0, ring=1.0, noise=1.0)

HERE = pathlib.Path(__file__).resolve()
SCRIPTS = HERE.parents[3] / "Resources/vendor/mpv/scripts"
SRC = (SCRIPTS / "photon-sharp.lua").read_text(encoding="utf-8")
if os.environ.get("MID_CAP"):   # sweep only: patch the mid-raster ceiling in memory, the file is untouched
    SRC = re.sub(r"(local PHOTON_SHARP_(?:720|1080)_M_MAX\s*= )[0-9.]+", lambda m: m.group(1) + os.environ["MID_CAP"], SRC)
MPV = os.environ.get("MPV", "mpv")

def lua_const(name):
    return float(re.search(r"local %s\s*=\s*(-?[0-9.]+)" % name, SRC).group(1))

def host_multiplier(src_h, out_h):
    m = re.search(r"local ps_adaptive_mode = .*?^end\n", SRC, re.S | re.M)
    lua = lua51.LuaRuntime()
    lua.execute('mp = { get_opt = function() return nil end }\nS, O = 0, 0\ncommon = { adaptive_rasters = function() return S, O, "t", O, 0, 0 end }\n'
                + m.group(0) + "\nfunction mult(s, o) S, O = s, o; ps_refresh_adaptive(); return ps_multiplier end")
    return lua.eval("mult")(src_h, out_h)

def base_amount(peak=0.5):
    lo, hi = lua_const("PHOTON_SHARP_BASE_AMOUNT_MIN"), lua_const("PHOTON_SHARP_BASE_AMOUNT_MAX")
    return lo + (hi - lo) * (1.0 - peak)

def shader_text(amount):
    a = SRC.index("PHOTON_SHARP_SHADER_SOURCE = [[") + len("PHOTON_SHARP_SHADER_SOURCE = [[")
    s = SRC[a:SRC.index("]]", a)]
    s = re.sub(r"#define PHOTON_SHARP_AMOUNT_CEIL\s+-?[\d.]+", "#define PHOTON_SHARP_AMOUNT_CEIL      %.2f" % lua_const("PHOTON_SHARP_AMOUNT_CLAMP_MAX"), s)
    vals = {"PHOTON_SHARP_AMOUNT": "%.6f" % amount, "PHOTON_SHARP_FACTOR_RENDERED": "%.4f" % lua_const("PHOTON_SHARP_FACTOR"),
            "PHOTON_SHARP_HALO_GUARD": "%.4f" % lua_const("PHOTON_SHARP_HALO_GUARD"),
            "PHOTON_SHARP_TEXTURE_BIAS": "%.4f" % lua_const("PHOTON_SHARP_TEXTURE_BIAS")}
    defs = []
    def rep(m):
        defs.append("#define %s %s" % (m.group(1), vals.get(m.group(1), m.group(3).strip()))); return ""
    s = re.sub(r"//!PARAM (\w+)\n//!TYPE (?:DYNAMIC )?(\w+)(?: float)?\n([^\n]+)\n", rep, s)  # PARAM -> #define (gpu vo has no //!PARAM)
    i = s.index("//!DESC"); j = s.index("\n", i) + 1
    return s[:j] + "\n".join(defs) + "\n" + s[j:]

# ---- fixtures (deterministic) ----
def fixture(kind, h):
    w = int(round(h * 16 / 9)); rng = np.random.RandomState(7)
    if kind == "step":
        a = np.full((h, w), 64.0); a[:, w // 2:] = 192.0
    elif kind == "text":   # fine grating, line width scales with source height (about 1px at 480p-equivalent)
        a = np.full((h, w), 200.0); period = max(2, int(round(h / 480 * 4)))
        for x in range(0, w, period * 2): a[:, x:x + period] = 60.0
    elif kind == "gradient":
        a = np.tile(np.linspace(40, 215, w), (h, 1))
    elif kind == "grain":
        a = 128.0 + rng.normal(0, 4.0, (h, w))
    else: raise ValueError(kind)
    img = Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8)).convert("RGB")
    if kind in ("step", "text"):
        # Soft edges: the same scene at each resolution (blur sigma scales with height). A 1px hard step
        # cannot be steepened by a sharpener, so rise-width gain would be degenerate (1.00); the first
        # run with hard edges is kept in the report for that reason. Margins were NOT changed.
        img = img.filter(ImageFilter.GaussianBlur(radius=BLUR_SIGMA_480 * h / 480.0))
    return img

CAP = 'local out = mp.get_opt("cap-out")\nmp.register_event("playback-restart", function() mp.add_timeout(1.5, function() mp.commandv("screenshot-to-file", out, "window") mp.add_timeout(0.5, function() mp.commandv("quit") end) end) end)\n'

def render(img_path, out_h, shader, out_png, tmp):
    w = int(round(out_h * 16 / 9)); cap = tmp / "cap.lua"; cap.write_text(CAP)
    cmd = [MPV, "--no-config", "--vo=gpu", "--gpu-context=x11egl", "--geometry=%dx%d" % (w, out_h), "--no-border", "--force-window=yes",
           "--keep-open=yes", "--image-display-duration=inf", "--script=%s" % cap, "--script-opts=cap-out=%s" % out_png, "--no-osc", "--osd-level=0",
           # --no-config does not freeze mpv's evolving renderer defaults. These
           # are the mpv0.34 settings under which the original margins were measured.
           "--scale=bilinear", "--cscale=bilinear", "--dscale=bilinear",
           "--correct-downscaling=no", "--linear-downscaling=no", "--sigmoid-upscaling=no", "--dither-depth=no"]
    if shader: cmd.append("--glsl-shaders=%s" % shader)
    cmd.append(str(img_path))
    if not os.environ.get("DISPLAY"): cmd = ["xvfb-run", "-a", "-s", "-screen 0 3840x2160x24"] + cmd
    subprocess.run(cmd, check=False, capture_output=True, timeout=120)
    img = Image.open(out_png).convert("L"); assert img.size == (w, out_h), (img.size, w, out_h)
    return np.asarray(img, dtype=np.float64)

# ---- metrics ----
def profile(img): h, w = img.shape; return img[h // 4: 3 * h // 4].mean(axis=0)
def levels(p):
    w = len(p); return p[int(w * .25):int(w * .40)].mean(), p[int(w * .60):int(w * .75)].mean()
def rise(p):
    lo, hi = levels(p); w = len(p); c = w // 2; seg = p[c - int(w * .08): c + int(w * .08)]
    def cross(frac):
        t = lo + frac * (hi - lo)
        for i in range(1, len(seg)):
            if seg[i - 1] < t <= seg[i]: return i - 1 + (t - seg[i - 1]) / (seg[i] - seg[i - 1])
        return None
    a, b = cross(.1), cross(.9)
    return None if a is None or b is None else b - a
def edge_metrics(p):
    lo, hi = levels(p); step = hi - lo; w = len(p); c = w // 2
    thr = 0.01 * step
    right = p[c + int(w * .02): c + int(w * .20)] - hi
    left = p[c - int(w * .20): c - int(w * .02)] - lo
    over = max(right.max(), -left.min(), 0.0) / step * 100.0
    def lobes(d):
        runs, on = 0, False
        for v in d:
            a = abs(v) > thr
            if a and not on: runs += 1
            on = a
        return max(runs - 1, 0)
    return over, max(lobes(right), lobes(left)), rise(p)

COLS = ["kind", "src", "out", "amount", "overshoot", "ring", "rise_gain", "noise_gain", "contrast_gain", "max_dev", "noise_gain_at_118g"]
def load(tsv_path):
    rows = []
    if os.path.exists(tsv_path):
        for ln in open(tsv_path).read().splitlines()[1:]:
            v = ln.split("\t"); r = dict(zip(COLS, v))
            for k in ("src", "out"): r[k] = int(r[k])
            for k in ("amount", "overshoot", "rise_gain", "noise_gain", "contrast_gain", "max_dev", "noise_gain_at_118g"):
                r[k] = float(r[k]) if r[k] != "" else ""
            r["ring"] = int(r["ring"]) if r["ring"] != "" else ""
            rows.append(r)
    return rows

def excursion(on, off, sl):
    """Overshoot for fixtures without a single edge: max excursion of the photon-on image beyond the
    photon-off extremes, as % of the off range (the same 'beyond local min/max' definition)."""
    rng = off[sl].max() - off[sl].min()
    return float(max(on[sl].max() - off[sl].max(), off[sl].min() - on[sl].min(), 0.0) / rng * 100.0)
def hf_gain(on, off, sl, floor=0.5):
    """Noise gain on a smooth field: std of the 5x5 high-pass residual, on/off, off floored at 0.5 level."""
    def resid(x):
        k = 5; p = np.pad(x, k // 2, mode="edge"); acc = np.zeros_like(x)
        for dy in range(k):
            for dx in range(k): acc += p[dy:dy + x.shape[0], dx:dx + x.shape[1]]
        return (x - acc / (k * k))[sl].std()
    return float(max(resid(on), floor) / max(resid(off), floor))

def run(tsv_path, scale480, kinds, srcs=(480, 2160)):
    rows, tmp = [r for r in load(tsv_path) if not (r["kind"] in kinds and r["src"] in srcs)], pathlib.Path(tempfile.mkdtemp())
    for kind in kinds:
        for src_h in srcs:
            ip = tmp / ("%s_%d.png" % (kind, src_h)); fixture(kind, src_h).save(ip)
            for out_h in (1080, 2160):
                amt = base_amount() * host_multiplier(src_h, out_h) * (scale480 if src_h == 480 else 1.0)
                sp = tmp / "ps.glsl"; sp.write_text(shader_text(amt))
                off = render(ip, out_h, None, str(tmp / "off.png"), tmp); on = render(ip, out_h, str(sp), str(tmp / "on.png"), tmp)
                r = dict(kind=kind, src=src_h, out=out_h, amount=round(amt, 4), overshoot="", ring="", rise_gain="", noise_gain="", contrast_gain="", max_dev="", noise_gain_at_118g="")
                if kind == "step":
                    po, pf = profile(on), profile(off); ov, rg, ron = edge_metrics(po); _, _, rof = edge_metrics(pf)[0:3]
                    r.update(overshoot=round(ov, 2), ring=rg, rise_gain=round(rof / ron, 3) if ron and rof else "")
                elif kind == "grain":
                    h, w = on.shape; sl = (slice(h // 4, 3 * h // 4), slice(w // 4, 3 * w // 4))
                    r.update(noise_gain=round(float(on[sl].std() / off[sl].std()), 3))
                    if src_h == 480:   # the guard evidence for the 118g waiver: same field at the uncapped 118g amount
                        a118 = base_amount() * max(0.5, min(2.0, (out_h / src_h) ** 0.5)) * scale480
                        sp.write_text(shader_text(a118)); on118 = render(ip, out_h, str(sp), str(tmp / "on118.png"), tmp)
                        r.update(noise_gain_at_118g=round(float(on118[sl].std() / off[sl].std()), 3))
                elif kind == "text":
                    h, w = on.shape; sl = (slice(h // 4, 3 * h // 4), slice(w // 4, 3 * w // 4))
                    pk = lambda x: float(np.percentile(x[sl], 99) - np.percentile(x[sl], 1))
                    r.update(contrast_gain=round(pk(on) / pk(off), 3), overshoot=round(excursion(on, off, sl), 2))
                else:
                    h, w = on.shape; sl = (slice(h // 4, 3 * h // 4), slice(w // 4, 3 * w // 4))
                    r.update(max_dev=round(float(np.abs(on - off).max()), 2), overshoot=round(excursion(on, off, sl), 2),
                             noise_gain=round(hf_gain(on, off, sl), 3))
                rows.append(r)
    cols = COLS
    with open(tsv_path, "w") as f:
        f.write("\t".join(cols) + "\n")
        for r in rows: f.write("\t".join(str(r[c]) for c in cols) + "\n")
    return rows

MID_SRCS = (720, 1080)   # R1 (queue): P3 margins at the middle raster classes, same absolute and relative limits as 480p
def verdict_mid(rows):
    by = {(r["kind"], r["src"], r["out"]): r for r in rows}; fails, notes = [], []
    for src in MID_SRCS:
        for out in (1080, 2160):
            for kind, key, mx, floor in (("step", "overshoot", P3_OVERSHOOT_MAX, FLOORS["overshoot"]), ("step", "ring", P3_RING_MAX, FLOORS["ring"]),
                                         ("text", "overshoot", P3_OVERSHOOT_MAX, FLOORS["overshoot"]),
                                         ("gradient", "overshoot", P3_OVERSHOOT_MAX, FLOORS["overshoot"]), ("gradient", "noise_gain", P3_NOISE_GAIN_MAX, FLOORS["noise"]),
                                         ("grain", "noise_gain", P3_NOISE_GAIN_MAX, FLOORS["noise"])):
                a, b = by[(kind, src, out)][key], by[(kind, 2160, out)][key]
                if a > mx: fails.append("P3 src=%d out=%d %s %s=%s > %s" % (src, out, kind, key, a, mx))
                if a > P3_REL_MAX * max(b, floor): fails.append("P3 src=%d out=%d %s %s=%s > %.1fx 2160p(%s)" % (src, out, kind, key, a, P3_REL_MAX, b))
            notes.append("src=%d out=%d amount=%s step rise_gain=%s text contrast_gain=%s" % (src, out, by[("step", src, out)]["amount"], by[("step", src, out)]["rise_gain"], by[("text", src, out)]["contrast_gain"]))
    return fails, notes

def verdict(rows):
    by = {(r["kind"], r["src"], r["out"]): r for r in rows}; fails, notes = [], []
    p3_failed = {}
    for out in (1080, 2160):
        # Applicable metric per fixture: step edge: overshoot+ringing; fine text: overshoot; gradient: overshoot+noise gain; flat grain: noise gain.
        for kind, key, mx, floor in (("step", "overshoot", P3_OVERSHOOT_MAX, FLOORS["overshoot"]), ("step", "ring", P3_RING_MAX, FLOORS["ring"]),
                                     ("text", "overshoot", P3_OVERSHOOT_MAX, FLOORS["overshoot"]),
                                     ("gradient", "overshoot", P3_OVERSHOOT_MAX, FLOORS["overshoot"]), ("gradient", "noise_gain", P3_NOISE_GAIN_MAX, FLOORS["noise"]),
                                     ("grain", "noise_gain", P3_NOISE_GAIN_MAX, FLOORS["noise"])):
            a, b = by[(kind, 480, out)][key], by[(kind, 2160, out)][key]
            bad = []
            if a > mx: bad.append("abs %s=%s > %s" % (key, a, mx))
            if a > P3_REL_MAX * max(b, floor): bad.append("rel %s=%s > %.1fx 2160p(%s)" % (key, a, P3_REL_MAX, b))
            if bad: p3_failed[out] = True; fails.append("P3 out=%d: %s" % (out, "; ".join(bad)))
        g480, g2160 = by[("step", 480, out)]["rise_gain"], by[("step", 2160, out)]["rise_gain"]
        if g480 != "" and g2160 != "":
            ok = g480 >= G118_RATIO_MIN * g2160
            ng118 = by[("grain", 480, out)]["noise_gain_at_118g"]
            if not ok and not p3_failed.get(out) and ng118 != "" and ng118 > P3_NOISE_GAIN_MAX:
                notes.append("118g out=%d: waived, guard cited: noise gain %.3f > %.2f at the 118g amount" % (out, ng118, P3_NOISE_GAIN_MAX)); continue
            notes.append("118g out=%d: rise gain 480p=%s 2160p=%s ratio=%.2f -> %s" % (out, g480, g2160, g480 / g2160, "met" if ok else ("not met, P3 failed so P3 wins" if p3_failed.get(out) else "NOT met with P3 passing")))
            if not ok and not p3_failed.get(out): fails.append("118g out=%d not met although P3 passes" % out)
    return fails, notes

if __name__ == "__main__":
    scale = float(sys.argv[sys.argv.index("--scale480") + 1]) if "--scale480" in sys.argv else 1.0
    kinds = sys.argv[sys.argv.index("--kinds") + 1].split(",") if "--kinds" in sys.argv else ["step", "text", "gradient", "grain"]
    srcs = tuple(int(x) for x in sys.argv[sys.argv.index("--srcs") + 1].split(",")) if "--srcs" in sys.argv else (480, 2160)
    rows = run(sys.argv[1], scale, kinds, srcs) if kinds != ["none"] else load(sys.argv[1])
    if set(srcs) == set(MID_SRCS) or "--mid" in sys.argv:
        mf, mn = verdict_mid(rows); print(open(sys.argv[1]).read()); [print(n) for n in mn]
        print("FAIL" if mf else "PASS (R1 mid-raster margins)"); [print(" -", f) for f in mf]; sys.exit(1 if mf else 0)
    need = {"step", "text", "gradient", "grain"}
    if not need <= {r["kind"] for r in rows}: print("partial: have", sorted({r["kind"] for r in rows})); sys.exit(2)
    fails, notes = verdict(rows)
    print(open(sys.argv[1]).read()); [print(n) for n in notes]
    print("FAIL" if fails else "PASS"); [print(" -", f) for f in fails]
    sys.exit(1 if fails else 0)
