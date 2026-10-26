//! Line-span source-evidence audit (fake-line hunt), detection-only.
//!
//! Owns the fake-line audit so `generated_native` stays untouched: shipped
//! Line spans are compared against the captured source contour they were
//! fitted from, and spans whose covered source arc measurably curves are
//! reported. Pure measurement, no behavior change, no new thresholds.

use crate::reference_slice::{Point, ReferenceRing, Span};

// ---------- line-span source-evidence audit (fake-line hunt) ----------
/// Audit of shipped Line spans against the captured source contour they were
/// fitted from. A Line span is SUSPICIOUS when the source contour arc it
/// covers deviates from the span's chord by more than the capture's own
/// declared simplification tolerance (the run's rdp_epsilon): the pixel
/// curvature was measurable at capture fidelity yet the span absorbed it
/// into a straight line. No new thresholds are invented: the anchor
/// tolerance is the contour ring's own median sample step plus the capture
/// tolerance, and the suspicion bar is the run's declared rdp_epsilon.
/// Detection only: this module never mutates drawing geometry.

/// One audited Line span. All measurements are in capture pixel units.
#[derive(Clone, Debug)]
pub struct LineSpanAudit {
    pub ring: usize,
    pub span: usize,
    pub start: Point,
    pub end: Point,
    /// Chord length (px).
    pub chord_px: f64,
    /// Worst endpoint-to-contour anchoring distance of the chosen arc (px).
    pub anchor_px: f64,
    /// Length of the covered source arc (px).
    pub arc_len_px: f64,
    /// Max perpendicular deviation of the covered arc from the chord (px).
    pub max_dev_px: f64,
    /// Intermediate contour samples measured along the covered arc.
    pub samples: usize,
    /// False when no contour arc accepted both endpoints (or degenerate span).
    pub anchored: bool,
    /// anchored && max_dev_px > the run's declared rdp_epsilon.
    pub suspicious: bool,
}

fn audit_dist(a: Point, b: Point) -> f64 { (b.x - a.x).hypot(b.y - a.y) }

/// Perpendicular distance from p to the line through a,b (a != b).
fn audit_perp(a: Point, b: Point, p: Point) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    (dx * (a.y - p.y) - (a.x - p.x) * dy).abs() / dx.hypot(dy)
}

/// Median consecutive-sample step of a contour ring: the ring's own
/// sampling resolution. Even count averages the two middle steps.
fn audit_median_step(ring: &[Point]) -> f64 {
    if ring.len() < 2 { return 0.0; }
    let mut steps: Vec<f64> = (0..ring.len()).map(|i| audit_dist(ring[i], ring[(i + 1) % ring.len()])).collect();
    steps.sort_by(|x, y| x.partial_cmp(y).unwrap_or(std::cmp::Ordering::Equal));
    let n = steps.len();
    if n % 2 == 1 { steps[n / 2] } else { (steps[n / 2 - 1] + steps[n / 2]) / 2.0 }
}

/// Walk the ring from i0 toward i1 in direction `dir` (+1/-1) and measure
/// every sample on that arc. Returns (max perpendicular deviation from the
/// chord, walked arc length, measured samples).
fn audit_arc_measure(ring: &[Point], i0: usize, i1: usize, dir: isize, a: Point, b: Point) -> (f64, f64, usize) {
    let n = ring.len() as isize;
    let mut max_dev = 0.0f64;
    let mut arc_len = 0.0f64;
    let mut samples = 0usize;
    let mut prev = ring[i0 as usize];
    let mut i = (i0 as isize + dir).rem_euclid(n);
    while i != i1 as isize {
        let p = ring[i as usize];
        let d = audit_perp(a, b, p);
        if d > max_dev { max_dev = d; }
        arc_len += audit_dist(prev, p);
        prev = p;
        samples += 1;
        i = (i + dir).rem_euclid(n);
    }
    arc_len += audit_dist(prev, ring[i as usize]);
    (max_dev, arc_len, samples)
}

/// Audit every Line span of `rings` against `contour` (absolute capture-px,
/// y-up rings; the caller adds the measured origin to the bbox-relative
/// capture points). `origin_x`/`scale` map drawing units back to capture px:
/// px = x/scale + origin_x, py = y/scale (the exact inverse of the source
/// frame the fit consumed). `rdp_eps_px` is the run's declared capture
/// tolerance: the measurability bar for source curvature.
pub fn audit_line_spans(
    rings: &[ReferenceRing],
    contour: &[Vec<Point>],
    origin_x: f64,
    scale: f64,
    rdp_eps_px: f64,
) -> Vec<LineSpanAudit> {
    let mut out = Vec::new();
    if !scale.is_finite() || scale <= 0.0 || !rdp_eps_px.is_finite() || rdp_eps_px < 0.0 { return out; }
    let to_px = |p: Point| Point { x: p.x / scale + origin_x, y: p.y / scale };
    // Per-ring anchor tolerance: the ring's own median sample step plus the
    // capture tolerance (both derived, nothing invented).
    let ring_tol: Vec<f64> = contour.iter().map(|r| audit_median_step(r) + rdp_eps_px).collect();
    for (ri, ring) in rings.iter().enumerate() {
        let mut p0 = ring.start;
        for (si, span) in ring.spans.iter().enumerate() {
            let end = match span { Span::Line { end } => *end, Span::Cubic { .. } => continue };
            let start = p0;
            let (a, b) = (to_px(start), to_px(end));
            p0 = end;
            let chord = audit_dist(a, b);
            if chord == 0.0 {
                out.push(LineSpanAudit { ring: ri, span: si, start, end, chord_px: 0.0, anchor_px: f64::NAN, arc_len_px: 0.0, max_dev_px: f64::NAN, samples: 0, anchored: false, suspicious: false });
                continue;
            }
            // Candidate arcs: every contour ring, nearest sample to each
            // endpoint, both walk directions. Accepted only when both
            // endpoint anchors land within the ring's own tolerance.
            let mut best: Option<(f64, f64, usize, f64)> = None; // (max_dev, arc_len, samples, anchor)
            for (cr, tol) in contour.iter().zip(&ring_tol) {
                if cr.len() < 2 { continue; }
                let mut i0 = 0; let mut d0 = f64::INFINITY;
                let mut i1 = 0; let mut d1 = f64::INFINITY;
                for (i, &p) in cr.iter().enumerate() {
                    let da = audit_dist(a, p);
                    if da < d0 { d0 = da; i0 = i; }
                    let db = audit_dist(b, p);
                    if db < d1 { d1 = db; i1 = i; }
                }
                let anchor = d0.max(d1);
                if !anchor.is_finite() || anchor > *tol { continue; }
                let step = audit_median_step(cr);
                // Below the contour's own sampling resolution the coverage is
                // not resolvable: no measurable curvature, never suspicious.
                // Same for both endpoints anchoring to the same sample (the
                // walk would wrap the whole ring).
                if i0 == i1 || chord < step {
                    let cand = (0.0, 0.0, 0usize, anchor);
                    if best.as_ref().map_or(true, |b0| cand.0 < b0.0) { best = Some(cand); }
                    continue;
                }
                for dir in [1isize, -1] {
                    let (dev, len, samples) = audit_arc_measure(cr, i0, i1, dir, a, b);
                    // Coverage first: the arc that explains more source
                    // samples is the span's coverage; deviation decides ties.
                    // Suspicion must be conservative: flag only when even the
                    // best-matching anchored source arc deviates above the
                    // capture tolerance. So the candidate with the SMALLEST
                    // max deviation wins; ties break toward more coverage.
                    let cand = (dev, len, samples, anchor);
                    if best.as_ref().map_or(true, |b0| cand.0 < b0.0 || (cand.0 == b0.0 && cand.2 > b0.2)) { best = Some(cand); }
                }
            }
            match best {
                Some((dev, len, samples, anchor)) => out.push(LineSpanAudit {
                    ring: ri, span: si, start, end, chord_px: chord, anchor_px: anchor, arc_len_px: len,
                    max_dev_px: dev, samples, anchored: true, suspicious: dev > rdp_eps_px }),
                None => out.push(LineSpanAudit {
                    ring: ri, span: si, start, end, chord_px: chord, anchor_px: f64::NAN, arc_len_px: 0.0,
                    max_dev_px: f64::NAN, samples: 0, anchored: false, suspicious: false }),
            }
        }
    }
    out
}

/// TSV row (no header) for one audit; NaN fields render as `na`.
pub fn line_span_audit_tsv(glyph: &str, a: &LineSpanAudit) -> String {
    let f = |v: f64| if v.is_nan() { "na".to_string() } else { format!("{v:.6}") };
    let note = if !a.anchored { if a.chord_px == 0.0 { "degenerate" } else { "unanchored" } } else { "anchored" };
    format!(
        "{glyph}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{note}\n",
        a.ring, a.span, f(a.start.x), f(a.start.y), f(a.end.x), f(a.end.y),
        f(a.chord_px), f(a.anchor_px), f(a.arc_len_px), a.samples, f(a.max_dev_px),
        if a.suspicious { 1 } else { 0 })
}
