//! L4: per-glyph capture tolerance derived from the glyph's own measured edge evidence.
//!
//! Read-only policy: this module only MEASURES and returns a `DerivedTolerance`. It does not call
//! capture or fit. Callers pass the struct as an explicit argument (capture binding is done at
//! landing). Pure and deterministic: same bytes -> same struct; no env, no globals.
//!
//! Derivation (all quantities per glyph, from the same ink-strength field capture traces at
//! iso 0.5, ink = 1 - gray/255):
//!
//! 1. Every iso crossing lies between two 4-neighbour pixels with ink strengths a, b on opposite
//!    sides of the iso level. Its sub-pixel position along the pixel edge is t = (iso-a)/(b-a).
//! 2. Position uncertainty of that crossing, half-range u (px):
//!    - step edge (|b-a| >= 1 - 1 LSB): the edge position is only known to the pixel cell,
//!      u = 1/2 px (pixel cell half-width; geometry of the raster).
//!    - antialiased edge: gray is quantised to 8 bits, half an LSB of gray moves t by
//!      du = (1/2 LSB)/|b-a|, with LSB = 1/255 of the ink range; u = min(du, 1/2).
//! 3. rdp_eps_px = RMS(u) over all crossings of the glyph. Fully binary scans give exactly
//!    1/2 px (the former fixed default); antialiased scans, whose edges are located better, give
//!    less. This is the amplitude of staircase noise the simplifier must not mistake for shape.
//! 4. The uncertainty is uniform over [-u, u], so its variance is u^2/3. fit variance (px^2) =
//!    mean(u^2)/3; the squared fit tolerance in scaled units is that variance times scale^2.
//! 5. t_line_px = rdp_eps_px + 1/2 px pixel quantisation, the same chain capture_fit documents.
//!
//! Open (needs corpus measurement, not claimed here): whether feature size (stem width) should
//! cap eps for very small glyphs; the gate compares this struct against the legacy values.

use crate::capture::{decode_png_gray, trace_field};

/// Derived tolerance for one glyph. Everything needed to reproduce it is in the struct.
#[derive(Clone, Debug, PartialEq)]
pub struct DerivedTolerance {
    /// RDP / dedup tolerance in source pixels: max(gray-quantisation term, stair term).
    pub rdp_eps_px: f64,
    /// Fit variance in px^2 (before scaling).
    pub fit_variance_px2: f64,
    /// t_line in source pixels (rdp_eps + pixel quantisation half-cell).
    pub t_line_px: f64,
    /// RMS edge roughness of the raw iso chain (px): mid-point distance to the chord of its two
    /// neighbours, over every vertex of every traced loop (0 if none).
    pub stair_rms_px: f64,
    /// Number of iso crossings measured (0 for the legacy arm).
    pub crossings: usize,
    /// Fraction of crossings that were step edges.
    pub step_fraction: f64,
    /// Where the numbers came from: "derived" or "legacy-fixed (comparison arm)".
    pub provenance: &'static str,
}

impl DerivedTolerance {
    /// Squared fit tolerance in scaled (font) units for a capture scale factor.
    pub fn fit_se_scaled(&self, scale: f64) -> f64 {
        self.fit_variance_px2 * scale * scale
    }
    /// rdp eps expressed in scaled (font) units.
    pub fn rdp_eps_scaled(&self, scale: f64) -> f64 {
        self.rdp_eps_px * scale
    }
    /// The pre-L4 fixed values, for the labelled comparison arm of the gate only.
    /// LEGACY: eps 0.5 px, se 0.1 scaled units (set directly as variance at scale 1 is NOT
    /// equivalent for other scales; `legacy_se_scaled` is exposed for exact reproduction).
    pub fn legacy() -> LegacyTolerance {
        LegacyTolerance { rdp_eps_px: LEGACY_RDP_EPS_PX, se_scaled: LEGACY_FIT_SE_SCALED }
    }
}

/// The old fixed pair, as one comparison arm. se is already in scaled units.
#[derive(Clone, Debug, PartialEq)]
pub struct LegacyTolerance {
    pub rdp_eps_px: f64,
    pub se_scaled: f64,
}
// LEGACY comparison arm only (inventory status LEGACY): the fixed pre-L4 capture eps (px).
pub const LEGACY_RDP_EPS_PX: f64 = 0.5;
// LEGACY comparison arm only: the fixed pre-L4 fit squared error (scaled units).
pub const LEGACY_FIT_SE_SCALED: f64 = 0.1;

/// Half-width of the pixel cell in px: raster geometry, not a tuned value.
const PIXEL_HALF: f64 = 0.5;
/// Iso level of the ink-strength field (same as capture).
const ISO: f64 = 0.5;
/// Gray quantisation: 8-bit, ink range 1.0 split into 255 steps.
const GRAY_LEVELS: f64 = 255.0;

/// Measure the tolerance from a decoded gray raster (row-major, 8-bit, 255 = white paper).
pub fn derive_from_gray(w: usize, h: usize, gray: &[u8]) -> Result<DerivedTolerance, String> {
    if gray.len() != w * h || w == 0 || h == 0 {
        return Err("gray raster size mismatch".into());
    }
    let ink = |i: usize| 1.0 - (gray[i] as f64) / GRAY_LEVELS;
    let (mut n, mut steps, mut sum_u2) = (0usize, 0usize, 0.0f64);
    let mut visit = |a: f64, b: f64| {
        if (a > ISO) == (b > ISO) {
            return;
        }
        let d = (b - a).abs();
        if d <= 0.0 {
            return;
        }
        let step = d >= 1.0 - 1.0 / GRAY_LEVELS;
        let u = if step { PIXEL_HALF } else { ((0.5 / GRAY_LEVELS) / d).min(PIXEL_HALF) };
        n += 1;
        if step {
            steps += 1;
        }
                sum_u2 += u * u;
    };
    for y in 0..h {
        for x in 0..w {
            let i = y * w + x;
            if x + 1 < w {
                visit(ink(i), ink(i + 1));
            }
            if y + 1 < h {
                visit(ink(i), ink(i + w));
            }
        }
    }
    if n == 0 {
        return Err("no iso crossings: blank or uniform raster".into());
    }
    let nf = n as f64;
    let eps_quant = (sum_u2 / nf).sqrt();
    // Edge roughness: the traced chain's own vertex-to-neighbour-chord deviation. A straight edge
    // has none beyond its stair/ripple amplitude; a smooth curve at ~1 px vertex spacing has only
    // a sagitta far below it. 3 points = the minimum that defines a chord residual (structure).
    let loops = trace_field(w, h, &|r, c| {
        if r >= 0 && (r as usize) < h && c >= 0 && (c as usize) < w { ink(r as usize * w + c as usize) } else { 0.0 }
    }, ISO);
    let (mut dn, mut d2) = (0usize, 0.0f64);
    for lp in &loops {
        let m = lp.len();
        if m < 4 { continue; }
        for i in 0..m {
            let (a, b, c) = (lp[(i + m - 1) % m], lp[i], lp[(i + 1) % m]);
            let (vx, vy) = (c.x - a.x, c.y - a.y);
            let l = vx.hypot(vy);
            if l == 0.0 { continue; }
            let d = ((b.x - a.x) * vy - (b.y - a.y) * vx).abs() / l;
            d2 += d * d; dn += 1;
        }
    }
    let stair = if dn > 0 { (d2 / dn as f64).sqrt() } else { 0.0 };
    let eps = eps_quant.max(stair);
    Ok(DerivedTolerance {
        rdp_eps_px: eps,
        fit_variance_px2: (sum_u2 / nf / 3.0).max(stair * stair / 3.0),
        stair_rms_px: stair,
        t_line_px: eps + PIXEL_HALF,
        crossings: n,
        step_fraction: steps as f64 / nf,
        provenance: "derived",
    })
}

/// Convenience for PNG bytes (gray, RGB or RGBA as capture decodes).
pub fn derive_from_png(png: &[u8]) -> Result<DerivedTolerance, String> {
    let (w, h, g) = decode_png_gray(png)?;
    derive_from_gray(w, h, &g)
}
