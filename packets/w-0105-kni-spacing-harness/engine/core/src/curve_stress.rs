//! curve_stress: curve-quality stress harness + node-economy baseline corpus.
//!
//! Measurement-only. Nothing in the ship path calls this module: it reads
//! fitted rings and the capture contour they were fitted to, then reports
//! node economy, curvature breaks and fit deviation, and renders
//! nonzero-winding PNG proof sheets for human review. With the module
//! unused the engine's emitted bytes are unchanged (no existing file is
//! modified beyond the one-line `pub mod` export).
//!
//! Per glyph it measures:
//!   - node economy: total nodes (span ends), cubic/line split, ring count;
//!   - joints: corner / smooth / curvature-break / unavailable, with a
//!     per-joint ledger (severity vs derived floor);
//!   - deviation: symmetric nearest-segment distance between the flattened
//!     fitted outline and the capture contour the fitter targeted, in font
//!     units (max + mean, pooled over both directions);
//!   - tile-IoU: nonzero-winding fill of the flattened fitted outline vs the
//!     source tile's ink mask, counted on the tile's own pixel canvas
//!     (intersection / union, with the pixel counts on the record);
//!   - proof PNGs: fitted fill (nonzero winding) and an overlay (dimmed
//!     source ink + fitted outline + node/handle markers), aligned to the
//!     source tile's canvas.
//!
//! Numeric derivations (no hardcoded quality thresholds):
//!   - HALF_COORD = 0.5: the max rounding error of one emitted coordinate on
//!     the integer emission grid (round_and_clean_ring grid 1.0). HALF_DIAG =
//!     HALF_COORD*sqrt(2): the max 2D displacement of one emitted point. Same
//!     integer-grid derivation as the node_objective corner guard.
//!   - Corner test: sin(angle between the incoming/outgoing handle vectors)
//!     vs HALF_DIAG*(1/|h_in| + 1/|h_out|): the same formula family as the
//!     node_objective corner guard, applied to each span's raw handle vector
//!     (line: its chord; cubic: its end handle).
//!   - Curvature floor: exhaustive worst case of the integer-rounding domain
//!     (each coordinate of the three points entering the end curvature moves
//!     by +/-HALF_COORD; 2^6 box corners per side). A joint is a curvature
//!     break only when the tangent is continuous (not a corner) AND the
//!     dimensionless severity |kappa_in - kappa_out| * min(chord_in,
//!     chord_out) exceeds the summed floor scaled by the same chord.
//!   - Flatten tolerance = scale/2 font units: the half-source-pixel band,
//!     the same derivation as run_config's DerivedSourceQuantization
//!     (units_per_px/2)^2 fit tolerance and node_objective's half-pixel
//!     boundary band.
//!   - derive_max_refits: each refit consumes one split sample, so more
//!     refits than captured samples cannot change the outcome; the cap is
//!     the largest captured ring's point count.
//!
//! Corpus generation: core/examples/curve_stress_run.rs. Style folders come
//! from --fixtures-root or the KNI_CURVE_STRESS_FIXTURES env var; no fixture
//! path is baked into the library. The committed gate baseline lives at
//! core/tests/fixtures/curve_stress/baseline-v1.tsv; the regeneration
//! command is recorded in that file's header and in core/tests/curve_stress.rs.

use crate::capture::MeasuredContour;
use crate::reference_slice::{Point, ReferenceRing, Span};

/// Harness identity, recorded in corpus headers.
pub const CURVE_STRESS_VERSION: &str = "curve_stress.v2";
/// Versioned TSV row tag; bump with CURVE_STRESS_VERSION when any measured
/// value's definition changes, then regenerate baselines.
pub const ROW_FORMAT_TAG: &str = "curve_stress_rows_v2";
/// Env var naming the fixtures root (one immediate subdirectory per style).
pub const ENV_FIXTURES: &str = "KNI_CURVE_STRESS_FIXTURES";

/// Max rounding error of one emitted coordinate (integer emission grid).
const HALF_COORD: f64 = 0.5;

/// Ink-strength iso level traced by the capture (capture.rs traces the 0.5
/// iso contour of the interpolated ink-strength field). The tile-IoU ink
/// mask uses the same level: a pixel is source ink exactly when its ink
/// strength (255 - gray)/255 is >= ISO_INK_LEVEL, i.e. gray <= 127 on the
/// 8-bit ramp. No tuned threshold: the level is the capture's own iso.
pub const ISO_INK_LEVEL: f64 = 0.5;

/// Source-ink predicate for the tile-IoU mask; derivation documented at
/// ISO_INK_LEVEL.
pub fn is_source_ink(gray: u8) -> bool {
    (255.0 - gray as f64) / 255.0 >= ISO_INK_LEVEL
}

// ---------- small vector helpers ----------

fn sub(a: Point, b: Point) -> Point { Point { x: a.x - b.x, y: a.y - b.y } }
fn add(a: Point, b: Point) -> Point { Point { x: a.x + b.x, y: a.y + b.y } }
fn mul(a: Point, k: f64) -> Point { Point { x: a.x * k, y: a.y * k } }
fn cross(a: Point, b: Point) -> f64 { a.x * b.y - a.y * b.x }
fn norm(a: Point) -> f64 { (a.x * a.x + a.y * a.y).sqrt() }
fn dist(a: Point, b: Point) -> f64 { norm(sub(a, b)) }
fn finite(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }

fn span_end(s: &Span) -> Point {
    match s { Span::Line { end } | Span::Cubic { end, .. } => *end }
}
fn ring_span_start(ring: &ReferenceRing, i: usize) -> Point {
    if i == 0 { ring.start } else { span_end(&ring.spans[i - 1]) }
}

// ---------- curvature ----------

/// Curvature of cubic p0..p3 at t=0 (start=true) or t=1 (start=false).
/// None when the end derivative vanishes (curvature undefined there).
fn cubic_curvature(p0: Point, p1: Point, p2: Point, p3: Point, start: bool) -> Option<f64> {
    let (d1, d2) = if start {
        // B'(0) = 3(P1-P0); B''(0) = 6(P0 - 2P1 + P2)
        (mul(sub(p1, p0), 3.0), mul(sub(add(p0, p2), mul(p1, 2.0)), 6.0))
    } else {
        // B'(1) = 3(P3-P2); B''(1) = 6(P1 - 2P2 + P3)
        (mul(sub(p3, p2), 3.0), mul(sub(add(p1, p3), mul(p2, 2.0)), 6.0))
    };
    let n = norm(d1);
    if n == 0.0 || !n.is_finite() { return None; }
    let k = cross(d1, d2) / (n * n * n);
    if k.is_finite() { Some(k) } else { None }
}

/// Worst-case |kappa_perturbed - kappa_base| over the integer-rounding box:
/// the three points entering the end curvature each move by +/-HALF_COORD
/// per coordinate (2^6 corners). Combos whose perturbed end derivative
/// vanishes are skipped: curvature is undefined there, so they cannot bound
/// the error of a defined curvature. Deterministic.
fn curvature_floor(p0: Point, p1: Point, p2: Point, p3: Point, start: bool, base: f64, half: f64) -> f64 {
    let idx: [usize; 3] = if start { [0, 1, 2] } else { [1, 2, 3] };
    let pts = [p0, p1, p2, p3];
    let mut floor = 0.0f64;
    for mask in 0..64u32 {
        let mut q = pts;
        for (bit, &pi) in idx.iter().enumerate() {
            let sx = if mask & (1 << (2 * bit)) != 0 { half } else { -half };
            let sy = if mask & (1 << (2 * bit + 1)) != 0 { half } else { -half };
            q[pi] = Point { x: q[pi].x + sx, y: q[pi].y + sy };
        }
        if let Some(k) = cubic_curvature(q[0], q[1], q[2], q[3], start) {
            floor = floor.max((k - base).abs());
        }
    }
    floor
}

// ---------- joint analysis ----------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JointKind { Corner, Smooth, CurvatureBreak, Unavailable }

impl JointKind {
    pub fn tag(self) -> &'static str {
        match self {
            JointKind::Corner => "corner",
            JointKind::Smooth => "smooth",
            JointKind::CurvatureBreak => "curvature_break",
            JointKind::Unavailable => "unavailable",
        }
    }
}

// ---------- chain-level source verdict ----------

/// Chain-level verdict for the SOURCE contour under a run of consecutive
/// Line spans: is the source edge straight, oscillating ("wavy"), or a
/// one-sided smooth arc? Window-level arc tests cannot separate a zigzag
/// comb from a real arc (a short window inside a zigzag looks one-sided);
/// the chain as a whole can. Median chord-crossing count on Marq Standard
/// comb teeth is 15 (min 2, max 42 over 89 chains) vs 0-1 on real arcs in
/// Mona/Jean; |mean signed deviation| over the oscillation's support is
/// ~0 relative to its amplitude (B's "sag~0"), vs >= half the peak for a
/// one-sided unimodal bump (triangle-wave bound) - reported as evidence
/// columns, not used as rule inputs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChainVerdict { SourceStraight, SourceWavy, SourceSmoothArc }

impl ChainVerdict {
    pub fn tag(self) -> &'static str {
        match self {
            ChainVerdict::SourceStraight => "source-straight",
            ChainVerdict::SourceWavy => "source-wavy",
            ChainVerdict::SourceSmoothArc => "source-smooth-arc",
        }
    }
}

/// Classify one chain from the source contour under it. Tile px.
///   sag_px     max |signed distance to the chain chord| over the region
///   crossings  chord crossings of the signed signal outside `iso_px`
///   iso_px     iso-contour edge localization, half a pixel: an
///              anti-aliased edge is a linear ink ramp, and the 0.5-level
///              iso contour of a ramp sits within half a pixel of the true
///              edge (capture.rs traces iso 0.5 of the ink field)
///
/// Both thresholds are derived, none tuned:
///  - straight when sag <= 2*iso: total excursion inside the capture
///    resolution is indistinguishable from straight.
///  - wavy when crossings > 1: a cubic Bezier has at most one inflection,
///    so a contour crossing its chord twice or more is oscillation no
///    single cubic can draw - real texture (lines track it correctly) or
///    at minimum multi-cubic material, never one smooth arc.
///  - otherwise (real excursion, at most one crossing): a one-sided arc
///    or a single S, both one-cubic territory -> smooth-arc.
pub fn classify_chain(sag_px: f64, crossings: usize, iso_px: f64) -> ChainVerdict {
    if sag_px <= 2.0 * iso_px {
        ChainVerdict::SourceStraight
    } else if crossings > 1 {
        ChainVerdict::SourceWavy
    } else {
        ChainVerdict::SourceSmoothArc
    }
}

#[derive(Clone, Debug)]
pub struct JointReport {
    pub ring: usize,
    /// Node index = index of the span whose end is the joint node.
    pub node: usize,
    pub kind: JointKind,
    /// |kappa_in - kappa_out| * min(chord_in, chord_out); 0 for corners and
    /// unavailable joints.
    pub severity: f64,
    /// Derived rounding floor at the same scale as severity.
    pub floor: f64,
}

/// One side of a joint: raw handle vector (line chord or cubic end handle),
/// end curvature and its rounding floor.
struct Side {
    handle: Point,
    kappa: f64,
    floor: f64,
    defined: bool,
}

fn span_start_side(p0: Point, s: &Span, half: f64) -> Side {
    match s {
        Span::Line { end } => Side { handle: sub(*end, p0), kappa: 0.0, floor: 0.0, defined: true },
        Span::Cubic { control_one, control_two, end } => {
            let h = sub(*control_one, p0);
            match cubic_curvature(p0, *control_one, *control_two, *end, true) {
                Some(kappa) => Side {
                    handle: h,
                    kappa,
                    floor: curvature_floor(p0, *control_one, *control_two, *end, true, kappa, half),
                    defined: true,
                },
                None => Side { handle: h, kappa: 0.0, floor: 0.0, defined: false },
            }
        }
    }
}

fn span_end_side(p0: Point, s: &Span, half: f64) -> Side {
    match s {
        Span::Line { end } => Side { handle: sub(*end, p0), kappa: 0.0, floor: 0.0, defined: true },
        Span::Cubic { control_one, control_two, end } => {
            let h = sub(*end, *control_two);
            match cubic_curvature(p0, *control_one, *control_two, *end, false) {
                Some(kappa) => Side {
                    handle: h,
                    kappa,
                    floor: curvature_floor(p0, *control_one, *control_two, *end, false, kappa, half),
                    defined: true,
                },
                None => Side { handle: h, kappa: 0.0, floor: 0.0, defined: false },
            }
        }
    }
}

fn classify_joint(ring: usize, node: usize, prev: &Side, next: &Side, chord_prev: f64, chord_next: f64, half: f64) -> JointReport {
    let report = |kind: JointKind, severity: f64, floor: f64| JointReport { ring, node, kind, severity, floor };
    let hn = norm(prev.handle);
    let ho = norm(next.handle);
    if hn == 0.0 || ho == 0.0 || !prev.defined || !next.defined {
        return report(JointKind::Unavailable, 0.0, 0.0);
    }
    let sin_angle = cross(prev.handle, next.handle).abs() / (hn * ho);
    // Same integer-grid corner guard as node_objective: a tangent change is
    // a real corner only when its sine exceeds the rounding error of both
    // handle end points.
    let corner_limit = half * std::f64::consts::SQRT_2 * (1.0 / hn + 1.0 / ho);
    if sin_angle > corner_limit {
        return report(JointKind::Corner, 0.0, 0.0);
    }
    let l = chord_prev.min(chord_next);
    let severity = (prev.kappa - next.kappa).abs() * l;
    let floor = (prev.floor + next.floor) * l;
    if severity > floor {
        report(JointKind::CurvatureBreak, severity, floor)
    } else {
        report(JointKind::Smooth, severity, floor)
    }
}

// ---------- flattening + deviation ----------

fn dist_to_line(p: Point, a: Point, b: Point) -> f64 {
    let ab = sub(b, a);
    let n = norm(ab);
    if n == 0.0 { return dist(p, a); }
    cross(ab, sub(p, a)).abs() / n
}

/// de Casteljau flattening of one cubic; pushes the piece end points (not
/// p0). Depth cap 53: each level halves the parameter interval, and beyond
/// 53 halvings t is indistinguishable in binary64, so deeper recursion
/// cannot change any coordinate.
fn flatten_cubic_into(p0: Point, p1: Point, p2: Point, p3: Point, tol: f64, depth: u32, out: &mut Vec<Point>) {
    let flat = dist_to_line(p1, p0, p3) <= tol && dist_to_line(p2, p0, p3) <= tol;
    if flat || depth >= 53 {
        out.push(p3);
        return;
    }
    let q0 = mul(add(p0, p1), 0.5);
    let q1 = mul(add(p1, p2), 0.5);
    let q2 = mul(add(p2, p3), 0.5);
    let r0 = mul(add(q0, q1), 0.5);
    let r1 = mul(add(q1, q2), 0.5);
    let s = mul(add(r0, r1), 0.5);
    flatten_cubic_into(p0, q0, r0, s, tol, depth + 1, out);
    flatten_cubic_into(s, r1, q2, p3, tol, depth + 1, out);
}

/// Closed flattened polyline of one ring (no duplicated closure point).
pub fn flatten_ring(ring: &ReferenceRing, tol: f64) -> Vec<Point> {
    let mut out = vec![ring.start];
    for (i, s) in ring.spans.iter().enumerate() {
        let p0 = ring_span_start(ring, i);
        match s {
            Span::Line { end } => out.push(*end),
            Span::Cubic { control_one, control_two, end } => {
                flatten_cubic_into(p0, *control_one, *control_two, *end, tol, 0, &mut out);
            }
        }
    }
    if out.len() > 1 && out.last() == Some(&ring.start) {
        out.pop();
    }
    out
}

fn dist_point_segment(p: Point, a: Point, b: Point) -> f64 {
    let ab = sub(b, a);
    let len2 = ab.x * ab.x + ab.y * ab.y;
    if len2 == 0.0 { return dist(p, a); }
    let ap = sub(p, a);
    let t = ((ap.x * ab.x + ap.y * ab.y) / len2).clamp(0.0, 1.0);
    dist(p, add(a, mul(ab, t)))
}

#[derive(Clone, Copy, Debug)]
pub struct Deviation {
    /// ALL view: every captured source ring is scored, including rings the
    /// fit deliberately dropped under capture::is_degenerate_ring. This is
    /// the honest number - a dropped feature shows up here, never hidden.
    pub max: f64,
    pub mean: f64,
    pub samples: usize,
    /// KEPT view: degenerate (sub-pixel, undrawable) source rings exempted
    /// by the same rule the fit applies. Fit quality on drawable geometry.
    pub max_kept: f64,
    pub mean_kept: f64,
    pub samples_kept: usize,
    /// Source rings exempted from the kept view (count + total capture-space
    /// area in px^2): what the fit was allowed to drop, on the record.
    pub dropped_rings: usize,
    pub dropped_area_px2: f64,
}

/// Symmetric nearest-segment distance between two polyline families. Every
/// polyline is treated as closed (closing segment last->first included).
/// Distances pool both directions: each fitted vertex to the source
/// segments, each source vertex to the fitted segments. None when either
/// family has no measurable segment.
#[derive(Clone, Copy, Debug)]
pub struct RawDeviation {
    pub max: f64,
    pub mean: f64,
    pub samples: usize,
}

/// Fused two-view deviation: ONE pass over both directions, two
/// accumulators. `source_kept` marks per source ring whether it survives
/// capture::is_degenerate_ring. ALL scores every sample (a dropped speck
/// still costs its true distance - the honest number, bit-identical to
/// symmetric_deviation's output on the same input); KEPT samples only
/// kept source rings (src->fit) and measures fitted points against kept
/// source segments only (fit->src). Returns None when there is no
/// measurable geometry in either view (empty fitted, empty source, or no
/// kept source segments).
pub fn symmetric_deviation_two_view(
    fitted: &[Vec<Point>], source: &[Vec<Point>], source_kept: &[bool],
) -> Option<(RawDeviation, RawDeviation)> {
    struct Seg { a: Point, b: Point, kept: bool }
    fn segs_of(polys: &[Vec<Point>], kept: Option<&[bool]>) -> Vec<Seg> {
        let mut out = Vec::new();
        for (ri, p) in polys.iter().enumerate() {
            if p.len() >= 2 {
                let k = kept.map(|f| f[ri]).unwrap_or(true);
                for i in 0..p.len() {
                    out.push(Seg { a: p[i], b: p[(i + 1) % p.len()], kept: k });
                }
            }
        }
        out
    }
    if source_kept.len() != source.len() { return None; }
    let fs = segs_of(fitted, None);
    let ss = segs_of(source, Some(source_kept));
    if fs.is_empty() || ss.is_empty() { return None; }
    if !ss.iter().any(|s| s.kept) { return None; }
    let (mut max_a, mut sum_a, mut n_a) = (0.0f64, 0.0f64, 0usize);
    let (mut max_k, mut sum_k, mut n_k) = (0.0f64, 0.0f64, 0usize);
    // fit->src: every fitted point, nearest over all source segs AND over
    // kept source segs in the same loop.
    for poly in fitted {
        for &p in poly {
            let mut da = f64::INFINITY;
            let mut dk = f64::INFINITY;
            for s in &ss {
                let d = dist_point_segment(p, s.a, s.b);
                if d < da { da = d; }
                if s.kept && d < dk { dk = d; }
            }
            if da > max_a { max_a = da; }
            sum_a += da; n_a += 1;
            if dk > max_k { max_k = dk; }
            sum_k += dk; n_k += 1;
        }
    }
    // src->fit: every source point, one nearest search; the sample lands in
    // the ALL accumulator always and in KEPT when its ring survives.
    for (ri, poly) in source.iter().enumerate() {
        let k = source_kept[ri];
        for &p in poly {
            let d = fs.iter().map(|s| dist_point_segment(p, s.a, s.b)).fold(f64::INFINITY, f64::min);
            if d > max_a { max_a = d; }
            sum_a += d; n_a += 1;
            if k {
                if d > max_k { max_k = d; }
                sum_k += d; n_k += 1;
            }
        }
    }
    if n_a == 0 || n_k == 0 { return None; }
    Some((
        RawDeviation { max: max_a, mean: sum_a / n_a as f64, samples: n_a },
        RawDeviation { max: max_k, mean: sum_k / n_k as f64, samples: n_k },
    ))
}

pub fn symmetric_deviation(fitted: &[Vec<Point>], source: &[Vec<Point>]) -> Option<RawDeviation> {
    let kept = vec![true; source.len()];
    symmetric_deviation_two_view(fitted, source, &kept).map(|(all, _)| all)
}

// ---------- per-glyph measurement ----------

#[derive(Clone, Debug)]
pub struct GlyphStress {
    pub nodes: usize,
    pub cubics: usize,
    pub lines: usize,
    pub rings: usize,
    pub corners: usize,
    pub curvature_breaks: usize,
    pub unavailable_joints: usize,
    /// Largest break severity (0 when no break).
    pub max_break_severity: f64,
    /// Present only from measure_glyph (analyze_rings leaves it None).
    pub deviation: Option<Deviation>,
    /// Present only from run_glyph, where the fill raster and the source
    /// gray exist side by side; None when the union is empty.
    pub tile_iou: Option<TileIou>,
    pub joints: Vec<JointReport>,
}

/// Joint and node-economy analysis of fitted rings. Pure vector geometry:
/// no raster input, no capture dependency.
pub fn analyze_rings(rings: &[ReferenceRing]) -> Result<GlyphStress, String> {
    analyze_rings_with_grid(rings, HALF_COORD)
}

/// analyze_rings on an explicit emission grid: `half_coord` is the maximum
/// rounding error of one emitted coordinate in the outline's own coordinate
/// space (integer font units: 0.5; an SVG tracer's path space: half the
/// file's decimal step). Severity and floor scale identically under any
/// uniform user-unit transform, so the break verdict is space-invariant.
pub fn analyze_rings_with_grid(rings: &[ReferenceRing], half_coord: f64) -> Result<GlyphStress, String> {
    if rings.is_empty() { return Err("no rings".into()); }
    if !half_coord.is_finite() || half_coord <= 0.0 { return Err("invalid half_coord".into()); }
    for r in rings {
        if !finite(r.start) { return Err("non-finite ring start".into()); }
        for s in &r.spans {
            match s {
                Span::Line { end } => if !finite(*end) { return Err("non-finite line end".into()); },
                Span::Cubic { control_one, control_two, end } => {
                    if !finite(*control_one) || !finite(*control_two) || !finite(*end) {
                        return Err("non-finite cubic point".into());
                    }
                }
            }
        }
    }
    let mut nodes = 0usize;
    let mut cubics = 0usize;
    let mut lines = 0usize;
    let mut joints = Vec::new();
    for (ri, ring) in rings.iter().enumerate() {
        nodes += ring.spans.len();
        cubics += ring.spans.iter().filter(|s| matches!(s, Span::Cubic { .. })).count();
        lines += ring.spans.iter().filter(|s| matches!(s, Span::Line { .. })).count();
        let n = ring.spans.len();
        if n == 0 { continue; }
        let closed = span_end(&ring.spans[n - 1]) == ring.start;
        let joint_count = if closed { n } else { n.saturating_sub(1) };
        for node in 0..joint_count {
            let prev_span = &ring.spans[node];
            let next_span = &ring.spans[(node + 1) % n];
            let prev_start = ring_span_start(ring, node);
            let next_start = span_end(prev_span);
            let prev = span_end_side(prev_start, prev_span, half_coord);
            let next = span_start_side(next_start, next_span, half_coord);
            let chord_prev = dist(prev_start, span_end(prev_span));
            let chord_next = dist(next_start, span_end(next_span));
            joints.push(classify_joint(ri, node, &prev, &next, chord_prev, chord_next, half_coord));
        }
    }
    let corners = joints.iter().filter(|j| j.kind == JointKind::Corner).count();
    let curvature_breaks = joints.iter().filter(|j| j.kind == JointKind::CurvatureBreak).count();
    let unavailable_joints = joints.iter().filter(|j| j.kind == JointKind::Unavailable).count();
    let max_break_severity = joints.iter()
        .filter(|j| j.kind == JointKind::CurvatureBreak)
        .map(|j| j.severity).fold(0.0f64, f64::max);
    Ok(GlyphStress {
        nodes, cubics, lines, rings: rings.len(), corners, curvature_breaks,
        unavailable_joints, max_break_severity, deviation: None, tile_iou: None, joints,
    })
}

/// Measure the fitted rings against the capture contour they were fitted
/// to: analyze_rings plus the deviation of the flattened outline against
/// the source contour. `scale` is the fit's units-per-pixel: source contour
/// points map to font units exactly as fit_from_source_frame does (x *
/// scale, y * scale plus the origin_y translation).
pub fn measure_glyph(rings: &[ReferenceRing], source: &MeasuredContour, scale: f64) -> Result<GlyphStress, String> {
    if !scale.is_finite() || scale <= 0.0 { return Err("invalid scale".into()); }
    let mut g = analyze_rings(rings)?;
    let flatten_tol = scale / 2.0; // half source pixel, see module docs
    let fitted: Vec<Vec<Point>> = rings.iter().map(|r| flatten_ring(r, flatten_tol)).collect();
    let dy = source.origin_y * scale;
    let to_fu = |r: &crate::capture::CapturedRing| -> Vec<Point> {
        r.points.iter().map(|p| Point { x: p.x * scale, y: p.y * scale + dy }).collect()
    };
    // Two views, one rule (capture::is_degenerate_ring, shared with the
    // fit's drop site): ALL scores everything the capture saw - a dropped
    // speck still costs its true distance to the fitted outline, so the
    // drop stays visible in the numbers; KEPT scores only drawable
    // geometry. Marq Standard carries real sub-pixel ink specks (311 on
    // the g tile, 69 on R): they are dropped by design, and both the drop
    // and its effect stay on the record.
    let source_polys: Vec<Vec<Point>> = source.rings.iter().map(|r| to_fu(r)).collect();
    let kept_flags: Vec<bool> = source.rings.iter()
        .map(|r| !crate::capture::is_degenerate_ring(&r.points)).collect();
    // One fused pass, two accumulators (owner rule: produce + flag, no
    // hiding, and no double-cost measurement).
    let (all, kept) = symmetric_deviation_two_view(&fitted, &source_polys, &kept_flags)
        .ok_or_else(|| "no measurable deviation (empty fitted, source, or kept geometry)".to_string())?;
    let dropped_rings = kept_flags.iter().filter(|&&k| !k).count();
    let dropped_area_px2: f64 = source.rings.iter()
        .filter(|r| crate::capture::is_degenerate_ring(&r.points))
        .map(|r| crate::capture::ring_area2(&r.points).abs() / 2.0).sum();
    g.deviation = Some(Deviation {
        max: all.max, mean: all.mean, samples: all.samples,
        max_kept: kept.max, mean_kept: kept.mean, samples_kept: kept.samples,
        dropped_rings, dropped_area_px2,
    });
    Ok(g)
}

/// max_refits derivation: one refit consumes one split sample, so refits
/// beyond the largest captured ring's point count cannot change the outcome.
pub fn derive_max_refits(c: &MeasuredContour) -> usize {
    c.rings.iter().map(|r| r.points.len()).max().unwrap_or(0)
}

// ---------- nonzero-winding rasterizer + proof rendering ----------

/// Fitted-ring coordinates (font units) to source-image canvas space
/// (x right, y up, origin at the canvas bottom-left): the inverse of the
/// fit frame mapping. x picks up the content bbox origin. y: capture's
/// y-up pixel space is the negated row index (capture.rs flips y = -row),
/// and fit_from_source_frame translates by origin_y*scale, so dividing by
/// scale lands on capture y-up and adding height-1 lands on canvas y-up.
pub fn fitted_to_image(p: Point, source: &MeasuredContour, scale: f64) -> (f64, f64) {
    (p.x / scale + source.origin_x, (source.height as f64 - 1.0) + p.y / scale)
}

/// Filled raster of closed polylines under the nonzero winding rule.
/// Polylines are in image space (x right, y up, canvas [0,w]x[0,h]).
/// Returns row-major top-down gray: 0 ink, 255 paper. A pixel is ink when
/// the winding number at its center is nonzero; a crossing exactly at a
/// pixel center leaves that pixel outside (deterministic measure-zero rule).
pub fn rasterize_nonzero(width: usize, height: usize, polylines: &[Vec<(f64, f64)>]) -> Vec<u8> {
    let mut out = vec![255u8; width.saturating_mul(height)];
    if width == 0 || height == 0 { return out; }
    for j_up in 0..height {
        let y = j_up as f64 + 0.5;
        let mut crossings: Vec<(f64, i32)> = Vec::new();
        for poly in polylines {
            if poly.len() < 2 { continue; }
            for i in 0..poly.len() {
                let (x1, y1) = poly[i];
                let (x2, y2) = poly[(i + 1) % poly.len()];
                let upward = y1 <= y && y < y2;
                let downward = y2 <= y && y < y1;
                if upward || downward {
                    let t = (y - y1) / (y2 - y1);
                    let xc = x1 + t * (x2 - x1);
                    crossings.push((xc, if upward { 1 } else { -1 }));
                }
            }
        }
        crossings.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        let row = height - 1 - j_up;
        let mut ci = 0usize;
        let mut wind: i32 = 0;
        for px in 0..width {
            let center = px as f64 + 0.5;
            while ci < crossings.len() && crossings[ci].0 < center {
                wind += crossings[ci].1;
                ci += 1;
            }
            if wind != 0 {
                out[row * width + px] = 0;
            }
        }
    }
    out
}

// ---------- tile-IoU ----------

/// Tile-canvas IoU counts: the fitted fill raster (0 = ink, from
/// rasterize_nonzero) against the source gray ink mask (is_source_ink),
/// pixel-exact on the source tile's own canvas. Same intersection/union
/// semantics as iou_report::GlyphIou::from_counts, kept dependency-free so
/// the harness never reaches into the report lane.
#[derive(Clone, Copy, Debug)]
pub struct TileIou {
    pub intersection: u64,
    pub union: u64,
    pub source_ink: u64,
    pub outline_ink: u64,
    pub iou: f64,
}

/// Count the tile-IoU of a fitted fill raster against the source gray.
/// Returns None when the union is empty (both masks blank, e.g. a space
/// tile): the ratio is undefined there and the row records `na`, never a
/// silently invented number.
pub fn tile_iou(fill: &[u8], source_gray: &[u8]) -> Option<TileIou> {
    if fill.len() != source_gray.len() { return None; }
    let (mut inter, mut src, mut out) = (0u64, 0u64, 0u64);
    for (&f, &g) in fill.iter().zip(source_gray.iter()) {
        let s = is_source_ink(g);
        let o = f == 0;
        if s { src += 1; }
        if o { out += 1; }
        if s && o { inter += 1; }
    }
    let union = src + out - inter;
    if union == 0 { return None; }
    Some(TileIou { intersection: inter, union, source_ink: src, outline_ink: out, iou: inter as f64 / union as f64 })
}

/// Polyline stroke onto a gray canvas (y-up coordinates), sampling each
/// segment at unit pixel steps along its major axis.
pub fn draw_polyline(canvas: &mut [u8], width: usize, height: usize, pts: &[(f64, f64)], close: bool, value: u8) {
    if pts.len() < 2 { return; }
    let segs = pts.len() - 1 + if close { 1 } else { 0 };
    for i in 0..segs {
        let (x1, y1) = pts[i];
        let (x2, y2) = pts[(i + 1) % pts.len()];
        let steps = ((x2 - x1).abs().max((y2 - y1).abs()).ceil() as i64).max(1);
        for s in 0..=steps {
            let t = s as f64 / steps as f64;
            let x = (x1 + t * (x2 - x1)).round() as i64;
            let y_up = (y1 + t * (y2 - y1)).round() as i64;
            if x >= 0 && (x as usize) < width && y_up >= 0 && (y_up as usize) < height {
                let row = height - 1 - y_up as usize;
                canvas[row * width + x as usize] = value;
            }
        }
    }
}

/// Filled square marker of half-extent `radius` at a y-up point.
pub fn draw_marker(canvas: &mut [u8], width: usize, height: usize, p: (f64, f64), radius: usize, value: u8) {
    let cx = p.0.round() as i64;
    let cy = p.1.round() as i64;
    for dy in -(radius as i64)..=(radius as i64) {
        for dx in -(radius as i64)..=(radius as i64) {
            let x = cx + dx;
            let y_up = cy + dy;
            if x >= 0 && (x as usize) < width && y_up >= 0 && (y_up as usize) < height {
                let row = height - 1 - y_up as usize;
                canvas[row * width + x as usize] = value;
            }
        }
    }
}

/// Proof-sheet values. The source gray is dimmed toward paper by adding
/// half its distance to 255, so source ink lands at gray 128 and stays
/// distinguishable from the fitted outline (0) and handle marks (96).
pub const OVERLAY_OUTLINE: u8 = 0;
pub const OVERLAY_HANDLE: u8 = 96;
pub const OVERLAY_DIM_BASE: u16 = 128;

/// Render the two proof PNG rasters for one glyph on the source tile's
/// canvas: (filled fitted outline, overlay). Both are aligned with the
/// source tile pixel grid; the overlay marks on-curve nodes with a 5x5
/// square (half-extent 2, the smallest marker that survives at capture
/// resolution around a 1px-wide stroke) and handle lines/control points in
/// OVERLAY_HANDLE.
pub fn render_proofs(
    rings: &[ReferenceRing],
    source: &MeasuredContour,
    source_gray: &[u8],
    scale: f64,
) -> Result<(Vec<u8>, Vec<u8>), String> {
    let width = source.width;
    let height = source.height;
    if width.checked_mul(height) != Some(source_gray.len()) {
        return Err("source gray size mismatch".into());
    }
    let tol = scale / 2.0;
    let flat: Vec<Vec<(f64, f64)>> = rings.iter().map(|r| {
        flatten_ring(r, tol).iter().map(|&p| fitted_to_image(p, source, scale)).collect()
    }).collect();
    let fill = rasterize_nonzero(width, height, &flat);
    let mut overlay: Vec<u8> = source_gray.iter()
        .map(|&v| (OVERLAY_DIM_BASE + (v as u16) / 2) as u8)
        .collect();
    for poly in &flat {
        draw_polyline(&mut overlay, width, height, poly, true, OVERLAY_OUTLINE);
    }
    for ring in rings {
        let mut prev = fitted_to_image(ring.start, source, scale);
        draw_marker(&mut overlay, width, height, prev, 2, OVERLAY_OUTLINE);
        for s in &ring.spans {
            match s {
                Span::Line { end } => {
                    let e = fitted_to_image(*end, source, scale);
                    draw_marker(&mut overlay, width, height, e, 2, OVERLAY_OUTLINE);
                    prev = e;
                }
                Span::Cubic { control_one, control_two, end } => {
                    let c1 = fitted_to_image(*control_one, source, scale);
                    let c2 = fitted_to_image(*control_two, source, scale);
                    let e = fitted_to_image(*end, source, scale);
                    draw_polyline(&mut overlay, width, height, &[prev, c1], false, OVERLAY_HANDLE);
                    draw_polyline(&mut overlay, width, height, &[e, c2], false, OVERLAY_HANDLE);
                    draw_marker(&mut overlay, width, height, c1, 1, OVERLAY_HANDLE);
                    draw_marker(&mut overlay, width, height, c2, 1, OVERLAY_HANDLE);
                    draw_marker(&mut overlay, width, height, e, 2, OVERLAY_OUTLINE);
                    prev = e;
                }
            }
        }
    }
    Ok((fill, overlay))
}

// ---------- PNG encoding (zero-dependency, deterministic) ----------

fn crc32(data: &[u8]) -> u32 {
    let mut table = [0u32; 256];
    for (i, e) in table.iter_mut().enumerate() {
        let mut c = i as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xEDB88320 ^ (c >> 1) } else { c >> 1 };
        }
        *e = c;
    }
    let mut c = 0xFFFFFFFFu32;
    for &b in data {
        c = table[((c ^ b as u32) & 0xFF) as usize] ^ (c >> 8);
    }
    c ^ 0xFFFFFFFF
}

fn adler32(data: &[u8]) -> u32 {
    const MOD: u32 = 65521;
    let mut a = 1u32;
    let mut b = 0u32;
    for &x in data {
        a = (a + x as u32) % MOD;
        b = (b + a) % MOD;
    }
    (b << 16) | a
}

struct BitWriter { out: Vec<u8>, acc: u32, nbits: u32 }

impl BitWriter {
    fn new() -> Self { BitWriter { out: Vec::new(), acc: 0, nbits: 0 } }
    /// Raw bits, LSB first (deflate extra-bit fields).
    fn push_bits(&mut self, val: u32, n: u32) {
        self.acc |= val << self.nbits;
        self.nbits += n;
        while self.nbits >= 8 {
            self.out.push((self.acc & 0xFF) as u8);
            self.acc >>= 8;
            self.nbits -= 8;
        }
    }
    /// Huffman code, emitted MSB of the code first (deflate code order).
    fn push_code(&mut self, code: u32, n: u32) {
        let mut rev = 0u32;
        for i in 0..n {
            rev |= ((code >> i) & 1) << (n - 1 - i);
        }
        self.push_bits(rev, n);
    }
    /// RFC 1951 fixed literal/length code for symbol 0..=287.
    fn push_fixed_symbol(&mut self, sym: usize) {
        if sym < 144 {
            self.push_code(0x30 + sym as u32, 8);
        } else if sym < 256 {
            self.push_code(0x190 + (sym as u32 - 144), 9);
        } else if sym < 280 {
            self.push_code(sym as u32 - 256, 7);
        } else {
            self.push_code(0xC0 + (sym as u32 - 280), 8);
        }
    }
    fn finish(mut self) -> Vec<u8> {
        if self.nbits > 0 {
            self.out.push((self.acc & 0xFF) as u8);
        }
        self.out
    }
}

const LEN_BASE: [u16; 29] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const LEN_EXTRA: [u8; 29] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];

/// deflate stream, single fixed-Huffman block. The only LZ77 matches
/// emitted are distance-1 runs (one repeated byte), which is what bilevel
/// and dimmed glyph rasters are made of; everything else goes out as
/// literals. Deterministic.
fn deflate_fixed(data: &[u8]) -> Vec<u8> {
    let mut w = BitWriter::new();
    w.push_bits(1, 1); // BFINAL
    w.push_bits(1, 2); // BTYPE = 01 (fixed Huffman)
    let mut i = 0usize;
    while i < data.len() {
        let mut run = 0usize;
        if i > 0 {
            let b = data[i - 1];
            while i + run < data.len() && data[i + run] == b && run < 258 {
                run += 1;
            }
        }
        if run >= 3 {
            let idx = LEN_BASE.iter().rposition(|&base| base as usize <= run).unwrap();
            w.push_fixed_symbol(257 + idx);
            let extra = run - LEN_BASE[idx] as usize;
            if LEN_EXTRA[idx] > 0 {
                w.push_bits(extra as u32, LEN_EXTRA[idx] as u32);
            }
            w.push_code(0, 5); // distance code 0 = distance 1
            i += run;
        } else {
            w.push_fixed_symbol(data[i] as usize);
            i += 1;
        }
    }
    w.push_fixed_symbol(256); // end of block
    w.finish()
}

fn png_chunk(tag: &[u8; 4], data: &[u8], out: &mut Vec<u8>) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(tag);
    out.extend_from_slice(data);
    let mut crc_in = Vec::with_capacity(4 + data.len());
    crc_in.extend_from_slice(tag);
    crc_in.extend_from_slice(data);
    out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
}

/// 8-bit grayscale PNG (bit depth 8, color type 0, no interlace), one
/// filter-0 row per image row.
pub fn encode_png_gray(width: usize, height: usize, gray: &[u8]) -> Result<Vec<u8>, String> {
    if width == 0 || height == 0 { return Err("empty canvas".into()); }
    if width.checked_mul(height) != Some(gray.len()) { return Err("gray buffer size mismatch".into()); }
    if width > u32::MAX as usize || height > u32::MAX as usize { return Err("canvas too large".into()); }
    let mut raw = Vec::with_capacity(gray.len() + height);
    for row in 0..height {
        raw.push(0u8); // filter: none
        raw.extend_from_slice(&gray[row * width..(row + 1) * width]);
    }
    let mut z = Vec::new();
    z.extend_from_slice(&[0x78, 0x01]); // zlib header: deflate, 32K window, valid check bits
    z.extend_from_slice(&deflate_fixed(&raw));
    z.extend_from_slice(&adler32(&raw).to_be_bytes());
    let mut out = Vec::new();
    out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&(width as u32).to_be_bytes());
    ihdr.extend_from_slice(&(height as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
    png_chunk(b"IHDR", &ihdr, &mut out);
    png_chunk(b"IDAT", &z, &mut out);
    png_chunk(b"IEND", &[], &mut out);
    Ok(out)
}

// ---------- node-economy baseline corpus (TSV) ----------

#[derive(Clone, Debug)]
pub struct CorpusRow {
    pub style: String,
    pub glyph: String,
    pub metrics: GlyphStress,
    pub fit_png_sha256: String,
    pub overlay_png_sha256: String,
}

/// Corpus column layout (the header line is part of the versioned format).
pub const CORPUS_COLUMNS: &str = "style\tglyph\tnodes\tcubics\tlines\trings\tcorners\tcurvature_breaks\tunavailable_joints\tmax_break_severity\tdev_max_all_fu\tdev_mean_all_fu\tdev_samples_all\tdev_max_kept_fu\tdev_mean_kept_fu\tdev_samples_kept\tdropped_specks\tdropped_area_px2\ttile_iou\tiou_intersection\tiou_union\tiou_source_ink\tiou_outline_ink\tfit_png_sha256\toverlay_png_sha256";

fn fmt_f(v: f64) -> String {
    // Rust's Display for f64 prints the shortest string that parses back to
    // the identical binary64 value, so corpus round-trips are bit-exact.
    format!("{v}")
}

fn fmt_row(r: &CorpusRow) -> String {
    let m = &r.metrics;
    let d = m.deviation.expect("corpus rows require measure_glyph deviation");
    let (iou_s, inter_s, union_s, src_s, out_s) = match &m.tile_iou {
        Some(t) => (fmt_f(t.iou), t.intersection.to_string(), t.union.to_string(), t.source_ink.to_string(), t.outline_ink.to_string()),
        None => ("na".to_string(), "na".to_string(), "na".to_string(), "na".to_string(), "na".to_string()),
    };
    format!(
        "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        r.style, r.glyph, m.nodes, m.cubics, m.lines, m.rings, m.corners,
        m.curvature_breaks, m.unavailable_joints, fmt_f(m.max_break_severity),
        fmt_f(d.max), fmt_f(d.mean), d.samples,
        fmt_f(d.max_kept), fmt_f(d.mean_kept), d.samples_kept,
        d.dropped_rings, fmt_f(d.dropped_area_px2),
        iou_s, inter_s, union_s, src_s, out_s,
        r.fit_png_sha256, r.overlay_png_sha256
    )
}

/// Style summary: glyph count, node totals/means, worst break count, worst
/// and mean deviations. All values are aggregates of the style's own rows.
fn fmt_summary(style: &str, rows: &[CorpusRow]) -> String {
    let n = rows.len();
    let total_nodes: usize = rows.iter().map(|r| r.metrics.nodes).sum();
    let mean_nodes = if n == 0 { 0.0 } else { total_nodes as f64 / n as f64 };
    let max_breaks: usize = rows.iter().map(|r| r.metrics.curvature_breaks).max().unwrap_or(0);
    let total_breaks: usize = rows.iter().map(|r| r.metrics.curvature_breaks).sum();
    let max_dev = rows.iter().filter_map(|r| r.metrics.deviation).map(|d| d.max).fold(0.0f64, f64::max);
    let mean_dev = if n == 0 { 0.0 } else { rows.iter().filter_map(|r| r.metrics.deviation).map(|d| d.mean).sum::<f64>() / n as f64 };
    let max_dev_kept = rows.iter().filter_map(|r| r.metrics.deviation).map(|d| d.max_kept).fold(0.0f64, f64::max);
    let mean_dev_kept = if n == 0 { 0.0 } else { rows.iter().filter_map(|r| r.metrics.deviation).map(|d| d.mean_kept).sum::<f64>() / n as f64 };
    let dropped: usize = rows.iter().filter_map(|r| r.metrics.deviation).map(|d| d.dropped_rings).sum();
    let dropped_area: f64 = rows.iter().filter_map(|r| r.metrics.deviation).map(|d| d.dropped_area_px2).sum();
    let ious: Vec<f64> = rows.iter().filter_map(|r| r.metrics.tile_iou.map(|t| t.iou)).collect();
    let (mean_iou, min_iou) = if ious.is_empty() {
        ("na".to_string(), "na".to_string())
    } else {
        (fmt_f(ious.iter().sum::<f64>() / ious.len() as f64), fmt_f(ious.iter().cloned().fold(f64::INFINITY, f64::min)))
    };
    format!(
        "S\t{}\tglyphs={}\ttotal_nodes={}\tmean_nodes={}\ttotal_curvature_breaks={}\tmax_glyph_curvature_breaks={}\tmax_dev_max_all_fu={}\tmean_dev_mean_all_fu={}\tmax_dev_max_kept_fu={}\tmean_dev_mean_kept_fu={}\tdropped_specks={}\tdropped_area_px2={}\tmean_tile_iou={}\tmin_tile_iou={}",
        style, n, total_nodes, fmt_f(mean_nodes), total_breaks, max_breaks,
        fmt_f(max_dev), fmt_f(mean_dev), fmt_f(max_dev_kept), fmt_f(mean_dev_kept), dropped, fmt_f(dropped_area),
        mean_iou, min_iou
    )
}

/// Full corpus document for one style: header comments (version, row tag,
/// caller-supplied config note and regeneration note), the column line, one
/// row per glyph (sorted by glyph id for byte-stable output) and the style
/// summary. `config_note` and `regen_note` must be single-line.
pub fn corpus_document(style: &str, config_note: &str, regen_note: &str, rows: &[CorpusRow]) -> Result<String, String> {
    if style.contains(['\t', '\n']) || config_note.contains('\n') || regen_note.contains('\n') {
        return Err("corpus fields must be single-line and tab-free".into());
    }
    for r in rows {
        if r.glyph.contains(['\t', '\n']) { return Err("glyph id must be single-line and tab-free".into()); }
    }
    let mut rows_sorted: Vec<&CorpusRow> = rows.iter().collect();
    rows_sorted.sort_by(|a, b| a.glyph.cmp(&b.glyph));
    let mut out = String::new();
    out.push_str("# curve_stress node-economy baseline corpus\n");
    out.push_str(&format!("# version\t{CURVE_STRESS_VERSION}\n"));
    out.push_str(&format!("# rows\t{ROW_FORMAT_TAG}\n"));
    out.push_str(&format!("# config\t{config_note}\n"));
    out.push_str(&format!("# regenerate\t{regen_note}\n"));
    out.push_str(CORPUS_COLUMNS);
    out.push('\n');
    for r in &rows_sorted {
        out.push_str(&fmt_row(r));
        out.push('\n');
    }
    out.push_str(&fmt_summary(style, &rows_sorted.iter().map(|r| (*r).clone()).collect::<Vec<_>>()));
    out.push('\n');
    Ok(out)
}

// ---------- capture + fit runner (shared by the example tool and the gate test) ----------

/// PNG probe budgets: caller-declared resource caps (not quality
/// thresholds), mirroring the pipeline's own decode hub budgets
/// (pipeline/src/main.rs PNG_DECODE_LIMITS).
pub const PROBE_PNG_LIMITS: crate::capture::DecodeLimits = crate::capture::DecodeLimits {
    max_input_bytes: 32 * 1024 * 1024,
    max_pixels: 4_194_304,
    max_working_bytes: 64 * 1024 * 1024,
};
/// JPEG probe budgets: caller-declared resource caps, mirroring the
/// pipeline's own limits (pipeline/src/main.rs process_glyph).
pub const PROBE_JPEG_LIMITS: crate::jpeg_source::Limits = crate::jpeg_source::Limits {
    max_input_bytes: 1 << 24,
    max_pixels: 1 << 24,
    max_working_bytes: 1 << 26,
};

#[derive(Clone, Copy, Debug)]
pub enum ScaleSpec {
    /// Explicit units-per-pixel, taken from the style's declared data.
    UnitsPerPx(f64),
    /// Derived: the tile's full height maps to 1000 units (mirrors UPM
    /// 1000). Used by the committed gate fixtures, whose declared style
    /// scale is not part of the engine tree.
    TileHeight1000,
}

#[derive(Clone, Copy, Debug)]
pub enum FitSeSpec {
    Value(f64),
    /// (units_per_px/2)^2, the run_config DerivedSourceQuantization value.
    DerivedSourceQuantization,
}

#[derive(Clone, Copy, Debug)]
pub enum RefitSpec {
    Count(usize),
    /// derive_max_refits: one refit consumes one split sample.
    Derived,
}

#[derive(Clone, Copy, Debug)]
pub struct GlyphRunConfig {
    pub scale: ScaleSpec,
    pub rdp_eps_px: f64,
    pub fit_se: FitSeSpec,
    pub max_refits: RefitSpec,
}

/// Single-line config description recorded in corpus headers.
pub fn config_note(cfg: &GlyphRunConfig) -> String {
    let scale = match cfg.scale {
        ScaleSpec::UnitsPerPx(v) => format!("scale={v}"),
        ScaleSpec::TileHeight1000 => "scale=tile-height-1000-derived".to_string(),
    };
    let se = match cfg.fit_se {
        FitSeSpec::Value(v) => format!("fit_squared_error={v}"),
        FitSeSpec::DerivedSourceQuantization => "fit_squared_error=(scale/2)^2-derived".to_string(),
    };
    let mr = match cfg.max_refits {
        RefitSpec::Count(v) => format!("max_refits={v}"),
        RefitSpec::Derived => "max_refits=derived-per-glyph".to_string(),
    };
    format!("{scale} rdp_eps_px={} {se} {mr}", cfg.rdp_eps_px)
}

pub struct GlyphRun {
    pub row: CorpusRow,
    pub fit_png: Vec<u8>,
    pub overlay_png: Vec<u8>,
}

/// Full probe of one tile image: decode + capture (PNG or JPEG via the
/// dispatch path), production fit (fit_from_source_frame), measurement,
/// proof rendering. Deterministic; resource caps are the declared probe
/// budgets above.
pub fn run_glyph(style: &str, glyph: &str, bytes: &[u8], cfg: &GlyphRunConfig) -> Result<GlyphRun, String> {
    let src = crate::capture_dispatch::capture_source(bytes, cfg.rdp_eps_px, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS)
        .map_err(|e| format!("capture failed: {e:?}"))?;
    let scale = match cfg.scale {
        ScaleSpec::UnitsPerPx(v) => v,
        ScaleSpec::TileHeight1000 => 1000.0 / src.contour.height as f64,
    };
    if !scale.is_finite() || scale <= 0.0 { return Err("derived scale invalid".into()); }
    let squared_error = match cfg.fit_se {
        FitSeSpec::Value(v) => v,
        FitSeSpec::DerivedSourceQuantization => (scale / 2.0) * (scale / 2.0),
    };
    let max_refits = match cfg.max_refits {
        RefitSpec::Count(v) => v,
        RefitSpec::Derived => derive_max_refits(&src.contour),
    };
    let policy = crate::cubic_fit::FitPolicy { squared_error, max_refits };
    let drawing = crate::generated_draw_frame::fit_from_source_frame(&src.contour, &src.gray, scale, &policy)
        .map_err(|e| format!("fit failed: {e:?}"))?;
    let mut metrics = measure_glyph(&drawing.rings, &src.contour, scale)?;
    let (fill, overlay) = render_proofs(&drawing.rings, &src.contour, &src.gray, scale)?;
    metrics.tile_iou = tile_iou(&fill, &src.gray);
    let fit_png = encode_png_gray(src.contour.width, src.contour.height, &fill)?;
    let overlay_png = encode_png_gray(src.contour.width, src.contour.height, &overlay)?;
    let row = CorpusRow {
        style: style.to_string(),
        glyph: glyph.to_string(),
        metrics,
        fit_png_sha256: crate::cff_reader::sha256_hex(&fit_png),
        overlay_png_sha256: crate::cff_reader::sha256_hex(&overlay_png),
    };
    Ok(GlyphRun { row, fit_png, overlay_png })
}

// ---------- SVG outline import (tracer comparison) ----------

/// Affine 2D matrix [a b c d e f]: x' = a*x + c*y + e, y' = b*x + d*y + f.
pub type Affine = [f64; 6];
pub const AFFINE_IDENTITY: Affine = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];

/// m*n (apply n first). SVG transform lists compose left to right.
pub fn affine_mul(m: &Affine, n: &Affine) -> Affine {
    [
        m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
        m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
        m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
    ]
}
pub fn affine_apply(m: &Affine, p: Point) -> Point {
    Point { x: m[0] * p.x + m[2] * p.y + m[4], y: m[1] * p.x + m[3] * p.y + m[5] }
}

/// Parse an SVG transform list: translate / scale / matrix only (what the
/// tracers emit); unsupported ops are an error, never silently dropped.
pub fn parse_transform(s: &str) -> Result<Affine, String> {
    let mut m = AFFINE_IDENTITY;
    let mut rest = s.trim();
    while !rest.is_empty() {
        let open = rest.find('(').ok_or("transform: missing (")?;
        let close = rest[open..].find(')').ok_or("transform: missing )")? + open;
        let name = rest[..open].trim();
        let args: Vec<f64> = rest[open + 1..close]
            .split([',', ' '])
            .filter(|t| !t.is_empty())
            .map(|t| t.parse::<f64>().map_err(|_| format!("transform: bad number {t}")))
            .collect::<Result<_, _>>()?;
        let op: Affine = match name {
            "translate" => {
                let ty = if args.len() > 1 { args[1] } else { 0.0 };
                if args.is_empty() || args.len() > 2 { return Err("translate arity".into()); }
                [1.0, 0.0, 0.0, 1.0, args[0], ty]
            }
            "scale" => {
                let sy = if args.len() > 1 { args[1] } else { args[0] };
                if args.is_empty() || args.len() > 2 { return Err("scale arity".into()); }
                [args[0], 0.0, 0.0, sy, 0.0, 0.0]
            }
            "matrix" => {
                if args.len() != 6 { return Err("matrix arity".into()); }
                [args[0], args[1], args[2], args[3], args[4], args[5]]
            }
            other => return Err(format!("unsupported transform op {other}")),
        };
        m = affine_mul(&m, &op);
        rest = rest[close + 1..].trim();
    }
    Ok(m)
}

fn xml_attr(tag: &str, name: &str) -> Option<String> {
    for quote in ['"', '\''] {
        let key = format!("{name}={quote}");
        if let Some(i) = tag.find(&key) {
            let rest = &tag[i + key.len()..];
            if let Some(j) = rest.find(quote) {
                return Some(rest[..j].to_string());
            }
        }
    }
    None
}

pub fn is_white_fill(fill: &str) -> bool {
    let f = fill.trim().to_ascii_lowercase().replace(' ', "");
    matches!(f.as_str(), "#fff" | "#ffffff" | "white" | "rgb(255,255,255)")
}

/// Decimal quantization of a path-data string: 10^-k where k is the largest
/// decimal count used by any coordinate (capped at 6); 1.0 for all-integer
/// data. The rounding floor of the emitted outline is half this step.
fn path_data_step(d: &str) -> f64 {
    let mut max_dec = 0usize;
    let bytes = d.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i] as char;
        if c.is_ascii_digit() || c == '.' || c == '-' || c == '+' {
            let start = i;
            while i < bytes.len() && (b"0123456789.-+eE".contains(&bytes[i])) { i += 1; }
            let tok = &d[start..i];
            if let Some(dot) = tok.find('.') {
                let dec = tok[dot + 1..].chars().take_while(|c| c.is_ascii_digit()).count();
                if dec > max_dec { max_dec = dec.min(6); }
            }
        } else {
            i += 1;
        }
    }
    10f64.powi(-(max_dec as i32))
}

/// One parsed SVG: dark-ink outline rings in raw path coordinates, the
/// derived emission-grid half unit, canvas metadata and the first enclosing
/// group transform. White-filled paths (backgrounds and cutout layers) are
/// skipped and counted; the tracers' own dark layering is kept as emitted.
pub struct SvgOutline {
    pub rings: Vec<ReferenceRing>,
    pub dark_paths: usize,
    pub white_paths_skipped: usize,
    /// Max rounding error of one emitted coordinate in path space: half the
    /// path data's decimal step (integer data: 0.5).
    pub half_coord: f64,
    pub view_box: Option<[f64; 4]>,
    pub width: Option<f64>,
    pub height: Option<f64>,
    pub group_transform: Affine,
}

/// Path-data to rings. Supports M/L/H/V/C/Z absolute and relative (the full
/// command set the three benchmarked tracers emit); any other command is an
/// error naming the command, so nothing is ever silently misread.
pub fn parse_path_data(d: &str) -> Result<Vec<ReferenceRing>, String> {
    #[derive(Clone, Copy, PartialEq, Debug)]
    enum Cmd { M, L, H, V, C, Z }
    #[derive(Clone, Copy, Debug)]
    enum Tok { Cmd(Cmd, bool), Num(f64) }
    let mut toks: Vec<Tok> = Vec::new();
    let bytes = d.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i] as char;
        let cmd = match c {
            'M' => Some((Cmd::M, false)), 'm' => Some((Cmd::M, true)),
            'L' => Some((Cmd::L, false)), 'l' => Some((Cmd::L, true)),
            'H' => Some((Cmd::H, false)), 'h' => Some((Cmd::H, true)),
            'V' => Some((Cmd::V, false)), 'v' => Some((Cmd::V, true)),
            'C' => Some((Cmd::C, false)), 'c' => Some((Cmd::C, true)),
            'Z' => Some((Cmd::Z, false)), 'z' => Some((Cmd::Z, true)),
            'S' | 's' | 'Q' | 'q' | 'T' | 't' | 'A' | 'a' => {
                return Err(format!("unsupported path command {c}"));
            }
            _ => None,
        };
        if let Some((k, rel)) = cmd {
            toks.push(Tok::Cmd(k, rel));
            i += 1;
        } else if c.is_ascii_digit() || c == '-' || c == '+' || c == '.' {
            let s0 = i;
            while i < bytes.len() && (b"0123456789.-+eE".contains(&bytes[i])) { i += 1; }
            let v: f64 = d[s0..i].parse().map_err(|_| format!("bad number in path: {}", &d[s0..i]))?;
            toks.push(Tok::Num(v));
        } else {
            i += 1; // separators: space, comma, newline
        }
    }
    let mut pos = 0usize;
    // Number cursor for the documented path-data parser; errors stay typed as expected-number failures.
    #[allow(unused_mut)]
    let mut num = |toks: &[Tok], pos: &mut usize| -> Result<f64, String> {
        match toks.get(*pos) {
            Some(Tok::Num(v)) => { *pos += 1; Ok(*v) }
            _ => Err("expected number in path data".into()),
        }
    };
    let mut rings: Vec<ReferenceRing> = Vec::new();
    let mut spans: Vec<Span> = Vec::new();
    let mut cur = Point { x: 0.0, y: 0.0 };
    let mut start = cur;
    let mut open = false;
    let mut pending: Option<(Cmd, bool)> = None;
    let mut first_pair_after_m = false;
    while pos < toks.len() {
        if let Some(Tok::Cmd(k, rel)) = toks.get(pos).copied() {
            pos += 1;
            if k == Cmd::Z {
                if open && (cur.x != start.x || cur.y != start.y) {
                    spans.push(Span::Line { end: start });
                }
                cur = start;
                if open {
                    rings.push(ReferenceRing { start, spans: std::mem::take(&mut spans) });
                    open = false;
                }
                pending = None;
                continue;
            }
            pending = Some((k, rel));
            first_pair_after_m = k == Cmd::M;
            if k == Cmd::M && open {
                rings.push(ReferenceRing { start, spans: std::mem::take(&mut spans) });
                open = false;
            }
            continue;
        }
        let (k, rel) = pending.ok_or("path data starts without a command")?;
        let abs = |v: f64, base: f64| if rel { base + v } else { v };
        match k {
            Cmd::M | Cmd::L => {
                let x = num(&toks, &mut pos)?;
                let y = num(&toks, &mut pos)?;
                let p = Point { x: abs(x, cur.x), y: abs(y, cur.y) };
                if k == Cmd::M && first_pair_after_m {
                    cur = p; start = p; open = true; first_pair_after_m = false;
                    pending = Some((Cmd::L, rel)); // implicit lineto pairs
                } else {
                    spans.push(Span::Line { end: p });
                    cur = p;
                }
            }
            Cmd::H => {
                let x = num(&toks, &mut pos)?;
                let p = Point { x: abs(x, cur.x), y: cur.y };
                spans.push(Span::Line { end: p });
                cur = p;
            }
            Cmd::V => {
                let y = num(&toks, &mut pos)?;
                let p = Point { x: cur.x, y: abs(y, cur.y) };
                spans.push(Span::Line { end: p });
                cur = p;
            }
            Cmd::C => {
                let x1 = num(&toks, &mut pos)?; let y1 = num(&toks, &mut pos)?;
                let x2 = num(&toks, &mut pos)?; let y2 = num(&toks, &mut pos)?;
                let x3 = num(&toks, &mut pos)?; let y3 = num(&toks, &mut pos)?;
                let c1 = Point { x: abs(x1, cur.x), y: abs(y1, cur.y) };
                let c2 = Point { x: abs(x2, cur.x), y: abs(y2, cur.y) };
                let e = Point { x: abs(x3, cur.x), y: abs(y3, cur.y) };
                spans.push(Span::Cubic { control_one: c1, control_two: c2, end: e });
                cur = e;
            }
            Cmd::Z => unreachable!("Z handled at command dispatch"),
        }
    }
    if open {
        rings.push(ReferenceRing { start, spans });
    }
    if rings.is_empty() { return Err("no rings in path data".into()); }
    Ok(rings)
}

/// Whole-SVG import: dark-filled <path> elements become rings; white-filled
/// ones are skipped and counted. Canvas metadata and the first enclosing
/// group transform are carried for callers that map back to tile pixels.
pub fn parse_svg_outline(xml: &str) -> Result<SvgOutline, String> {
    let svg_open = xml.find("<svg").ok_or("no <svg> element")?;
    let svg_tag_end = xml[svg_open..].find('>').ok_or("unterminated <svg>")? + svg_open;
    let svg_tag = &xml[svg_open..svg_tag_end];
    let num_attr = |name: &str| -> Option<f64> {
        xml_attr(svg_tag, name).and_then(|v| v.trim_end_matches("pt").trim().parse().ok())
    };
    let view_box = xml_attr(svg_tag, "viewBox").and_then(|v| {
        let parts: Vec<f64> = v.split([',', ' ']).filter(|t| !t.is_empty())
            .filter_map(|t| t.parse().ok()).collect();
        if parts.len() == 4 { Some([parts[0], parts[1], parts[2], parts[3]]) } else { None }
    });
    let (mut group_transform, mut group_fill) = (AFFINE_IDENTITY, None);
    if let Some(g_at) = xml.find("<g ") {
        let g_end = xml[g_at..].find('>').ok_or("unterminated <g>")? + g_at;
        let g_tag = &xml[g_at..g_end];
        if let Some(t) = xml_attr(g_tag, "transform") {
            group_transform = parse_transform(&t)?;
        }
        group_fill = xml_attr(g_tag, "fill");
    }
    let mut rings = Vec::new();
    let (mut dark, mut white) = (0usize, 0usize);
    let mut step = 1.0f64;
    let mut at = 0usize;
    while let Some(p_at) = xml[at..].find("<path") {
        let p_at = p_at + at;
        let p_end = xml[p_at..].find('>').ok_or("unterminated <path>")? + p_at;
        at = p_end + 1;
        let tag = &xml[p_at..p_end];
        let d = match xml_attr(tag, "d") { Some(d) => d, None => continue };
        let fill = xml_attr(tag, "fill")
            .or_else(|| xml_attr(tag, "style").and_then(|s| {
                s.split(';').find_map(|kv| {
                    let mut it = kv.splitn(2, ':');
                    match (it.next(), it.next()) {
                        (Some(k), Some(v)) if k.trim() == "fill" => Some(v.trim().to_string()),
                        _ => None,
                    }
                })
            }))
            .or_else(|| group_fill.clone())
            .unwrap_or_else(|| "#000000".to_string());
        if is_white_fill(&fill) { white += 1; continue; }
        let mut part = parse_path_data(&d)?;
        if let Some(t) = xml_attr(tag, "transform") {
            let m = affine_mul(&group_transform, &parse_transform(&t)?);
            for r in &mut part {
                r.start = affine_apply(&m, r.start);
                for s in &mut r.spans {
                    match s {
                        Span::Line { end } => *end = affine_apply(&m, *end),
                        Span::Cubic { control_one, control_two, end } => {
                            *control_one = affine_apply(&m, *control_one);
                            *control_two = affine_apply(&m, *control_two);
                            *end = affine_apply(&m, *end);
                        }
                    }
                }
            }
            // A path-level transform rescales coordinates; the ring geometry
            // was moved into group space, so the path-space decimal step no
            // longer describes the emission grid exactly. Keep the smaller
            // (more conservative) of the two steps.
            step = step.min(path_data_step(&d));
        } else {
            step = step.min(path_data_step(&d));
        }
        rings.append(&mut part);
        dark += 1;
    }
    if dark == 0 { return Err("no dark paths".into()); }
    Ok(SvgOutline {
        rings, dark_paths: dark, white_paths_skipped: white,
        half_coord: 0.5 * step, view_box,
        width: num_attr("width"), height: num_attr("height"),
        group_transform,
    })
}
