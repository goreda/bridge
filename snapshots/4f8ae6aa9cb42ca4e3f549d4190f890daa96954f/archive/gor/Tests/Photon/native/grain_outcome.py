#!/usr/bin/env python3
"""photon-grain OUTCOME test on rendered pixels (queue Q1, card 710 P2): grain size and strength match the source
resolution at 480/720/1080/2160, and at 2160 the effect stays visible. Real shader text from photon-grain.lua runs in
mpv's gpu path (vo=gpu, glsl-shaders, screenshot window) on a near-flat mid-grey field (120..136 ramp with deterministic +/-1 level detail: the shader gates exactly-flat areas to zero grain), compared with photon off.
Host values (size coefficient, render density) come from the real gr_refresh_adaptive and common.adaptive_strength_k (Lua 5.1). Engine controls come from the production control panel, not stale GLSL PARAM defaults. Renderer settings are explicitly pinned by sharp_outcome.render.
Label: native-render (mpv 0.34 vo=gpu, Mesa GL under Xvfb), not the owner's mpv 0.41/GPU, not owner eyes.

MARGINS, written before the first run, never tuned after (output = 1080 and 2160 window, source = 480/720/1080/2160):
  strength: added-grain std (levels) at a source <1080 must be <= 1.5x the 1080p-source value (no over-strong SD);
  visible:  added-grain std at the 2160 source >= 1.0 level and >= 0.5x the 1080p-source value;
  size:     grain correlation width in SOURCE pixels (autocorr falls below 0.5), each source within [0.5x, 2.0x] of the 1080p value.
Usage: grain_outcome.py OUT.tsv"""
import pathlib, re, sys, tempfile
import numpy as np
from PIL import Image
from lupa import lua51
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sharp_outcome as so

STRENGTH_REL_MAX, VIS_MIN_LEVELS, VIS_REL_MIN, SIZE_LO, SIZE_HI = 1.5, 1.0, 0.5, 0.5, 2.0
SC = so.SCRIPTS
GR = (SC / "photon-grain.lua").read_text(encoding="utf-8")
CM = (SC / "photon-common.lua").read_text(encoding="utf-8")
def engine_constant(name):
    return re.search(r"local " + name + r"\s*=\s*([0-9.]+)", GR).group(1)

ACCEPTED_STRENGTH = 6.25     # engine strength for clean content after the units fix (d107ce7a)

def host(src_h, out_h):
    lua = lua51.LuaRuntime()
    k = re.search(r"function M\.adaptive_strength_k\(h\).*?^end\n", CM, re.S | re.M).group(0).replace("function M.", "function ")
    lo = re.search(r"local ADAPTIVE_LOW_K = [^\n]*\n", CM).group(0)
    g = re.search(r"local gr_effective_h\n.*?^end\n", GR, re.S | re.M).group(0)
    lua.execute("local math_max, math_min = math.max, math.min\nS,O=0,0\ncommon={adaptive_strength_k=function(h) return ADAPTIVE_K(h) end, adaptive_rasters=function() return S,O,'t',S,S*16/9,O*16/9 end}\n"
                + lo + k.replace("function adaptive_strength_k", "function ADAPTIVE_K") + "\ngr_adaptive_mode=true\n" + g
                + "\nfunction run(s,o) S,O=s,o; gr_refresh_adaptive(); return gr_size_coefficient, gr_render_density end")
    c, d = lua.eval("run")(src_h, out_h); return c, d

def shader(coef, dens):
    a = GR.index("//!TEXTURE TEX_BLUENOISE"); b = GR.index("]]", a); s = GR[a:b]
    tex = re.search(r"//!TEXTURE TEX_BLUENOISE.*?\n\n", s, re.S)
    vals = {"GR_AMOUNT": "0.775", "GR_SIZE_COEFFICIENT": "%.6f" % coef, "GR_RENDER_DENSITY": "%.6f" % dens, "BASE_STRENGTH": "%.4f" % ACCEPTED_STRENGTH}
    # PARAM declarations include legacy defaults. Production gr_push_params uses
    # the engine control panel instead. Match that panel, not stale GLSL literals.
    control = {"GRAIN_SIZE":"GRAIN_SIZE", "GRAIN_SOFTNESS":"GRAIN_SOFTNESS",
               "CHROMA_SPLIT":"GRAIN_CHROMA_SPLIT", "DEVELOPMENT":"GRAIN_DEVELOPMENT",
               "FINE_WEIGHT":"GRAIN_FINE_WEIGHT", "CRYSTAL_WEIGHT":"GRAIN_CRYSTAL_WEIGHT",
               "CLOUD_WEIGHT":"GRAIN_CLOUD_WEIGHT", "FINE_SIZE_RATIO":"GRAIN_FINE_SIZE_RATIO",
               "CLOUD_SIZE_RATIO":"GRAIN_CLOUD_SIZE_RATIO", "SKEW_STRENGTH":"GRAIN_SKEW_STRENGTH",
               "GR_SHADOW_SENSITIVITY":"GRAIN_SHADOW_SENSITIVITY",
               "GR_MIDTONE_SENSITIVITY":"GRAIN_MIDTONE_SENSITIVITY",
               "GR_HIGHLIGHT_SENSITIVITY":"GRAIN_HIGHLIGHT_SENSITIVITY",
               "STOCK_PRESET":"GRAIN_STOCK_PRESET", "RES_ADAPT":"GRAIN_RES_ADAPT"}
    vals.update({key: engine_constant(value) for key,value in control.items()})
    defs = []
    def rep(m): defs.append("#define %s %s" % (m.group(1), vals.get(m.group(1), m.group(3).strip()))); return ""
    s = re.sub(r"//!PARAM (\w+)\n//!TYPE (?:DYNAMIC )?(\w+)(?: float)?\n([^\n]+)\n", rep, s)
    # mpv 0.34 wants the TEXTURE hex body on ONE line (0.41 accepts wrapped); same bytes, joined here.
    m = re.search(r"(//!BORDER REPEAT\n)([0-9a-fA-F\n]+)\n\n", s)
    if m: s = s[:m.start(2)] + m.group(2).replace("\n", "") + s[m.end(2):]
    # a TEXTURE body runs until the next //! directive and text before the first directive is not shader code:
    # defines go at the start of the hook body (right after its //! header lines)
    j = s.index("//!DESC", s.index("//!HOOK OUTPUT")); j = s.index("\n", j) + 1
    defs.append("#define TEX_BLUENOISE_tex(p) texture(TEX_BLUENOISE, p)  // mpv 0.34 binds user textures as bare samplers (0.41 defines NAME_tex)")
    return s[:j] + "\n".join(defs) + "\n" + s[j:]

def metrics(on, off, src_h, out_h):
    h, w = on.shape; sl = (slice(h // 4, 3 * h // 4), slice(w // 4, 3 * w // 4))
    d = (on - off)[sl]; d = d - d.mean(); std = float(d.std())
    row = d[d.shape[0] // 2 - 64: d.shape[0] // 2 + 64]; ac = []
    f = np.fft.rfft(row, axis=1); p = np.fft.irfft(f * np.conj(f), n=row.shape[1], axis=1).mean(axis=0); p = p / p[0]
    wid = next((i for i in range(1, 64) if p[i] < 0.5), 64)
    return std, wid * src_h / out_h

def fixture(src_h):
    """Near-flat with deterministic one-level detail; not a letterbox fixture."""
    w = int(round(src_h * 16 / 9))
    ramp = np.tile(np.linspace(120, 136, w), (src_h, 1))
    detail = np.random.RandomState(17).choice([-1, 1], size=(src_h, w))
    return Image.fromarray((ramp + detail).round().astype(np.uint8)).convert("RGB")

def main(tsv):
    tmp = pathlib.Path(tempfile.mkdtemp()); rows = []
    for src_h in (480, 720, 1080, 2160):
        # Do not measure scaler rounding on a mostly-exactly-flat quantized ramp.
        fixture(src_h).save(tmp / ("f%d.png" % src_h))
        for out_h in (1080, 2160):
            coef, dens = host(src_h, out_h); (tmp / "g.glsl").write_text(shader(coef, dens))
            off = so.render(tmp / ("f%d.png" % src_h), out_h, None, str(tmp / "off.png"), tmp)
            on = so.render(tmp / ("f%d.png" % src_h), out_h, str(tmp / "g.glsl"), str(tmp / "on.png"), tmp)
            std, wid = metrics(on, off, src_h, out_h); rows.append((src_h, out_h, round(coef, 4), round(dens, 3), round(std, 3), round(wid, 3)))
    with open(tsv, "w") as f:
        f.write("src\tout\tsize_coef\tdensity\tgrain_std_levels\tcorr_width_src_px\n")
        for r in rows: f.write("\t".join(map(str, r)) + "\n")
    by = {(r[0], r[1]): r for r in rows}; fails = []
    for out in (1080, 2160):
        ref = by[(1080, out)]
        for s in (480, 720):
            if by[(s, out)][4] > STRENGTH_REL_MAX * ref[4]: fails.append("strength out=%d src=%d std %.3f > %.1fx 1080p %.3f" % (out, s, by[(s, out)][4], STRENGTH_REL_MAX, ref[4]))
        v = by[(2160, out)][4]
        if v < VIS_MIN_LEVELS or v < VIS_REL_MIN * ref[4]: fails.append("visible out=%d 2160p std %.3f (min %.1f levels, %.1fx of 1080p %.3f)" % (out, v, VIS_MIN_LEVELS, VIS_REL_MIN, ref[4]))
        for s in (480, 720, 2160):
            r = by[(s, out)][5] / ref[5]
            if not SIZE_LO <= r <= SIZE_HI: fails.append("size out=%d src=%d width ratio %.2f outside [%.1f,%.1f]" % (out, s, r, SIZE_LO, SIZE_HI))
    print(open(tsv).read()); print("FAIL" if fails else "PASS"); [print(" -", x) for x in fails]; return 1 if fails else 0
if __name__ == "__main__": sys.exit(main(sys.argv[1]))
