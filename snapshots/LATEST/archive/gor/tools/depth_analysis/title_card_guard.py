"""s46: title-card plane guard for the flat-2d3d FALLBACK depth (owner 20:28, multi-ghosted text).
Python reference the shader mirrors (vr180-look.lua d3_depth). Any luma-driven prior tears high-contrast glyph edges, so a frame that is a
sparse title card (nearly all dark achromatic) gets ONE coherent depth plane (zero internal disparity) while normal scenes keep full depth.

Detector (no temporal state, 25 coarse taps at ((i+.5)/5, (j+.5)/5), the same grid the scene-mean uses):
  dark(tap)  = luma < DARK_LUMA and (max(rgb) - min(rgb)) < DARK_CHROMA
  frac       = mean(dark over 25 taps)
  t          = clamp((frac - T_LO) / (T_HI - T_LO), 0, 1)     soft ramp = the hysteresis-free blend: fades move t smoothly, no flicker
Depth:  d = mix(prior(q), plane, t), plane = the convergence value (0.5, or vr_pk_conv in the pack path), so a title sits at the screen plane.
"""
DARK_LUMA = 0.08
DARK_CHROMA = 0.06
T_LO, T_HI = 0.60, 0.80


def clamp(v, a, b):
    return max(a, min(b, v))


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def grid_dark_fraction(tapfn, dark_luma=DARK_LUMA, dark_chroma=DARK_CHROMA):
    """tapfn(x, y) -> (r, g, b) in 0..1; returns the dark achromatic fraction over the 5x5 grid."""
    n = 0
    for j in range(5):
        for i in range(5):
            c = tapfn((i + 0.5) / 5.0, (j + 0.5) / 5.0)
            if lum(c) < dark_luma and (max(c) - min(c)) < dark_chroma:
                n += 1
    return n / 25.0


def guard_weight(frac, lo=T_LO, hi=T_HI):
    return clamp((frac - lo) / (hi - lo), 0.0, 1.0)


def guarded_depth(prior, t, plane=0.5):
    return prior + (plane - prior) * t
