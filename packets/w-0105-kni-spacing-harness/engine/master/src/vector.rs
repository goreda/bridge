//! Vector-path measurement for master mode: exact-geometry fidelity against
//! the source outline, exact axis-extrema coverage, and the input-path label.
//!
//! Scope: measurement only. The source outline arrives through the plain-text
//! fixture format (`fixture::parse`); no font reader lives in this crate. A
//! master that copies its source is a legal result and is reported as
//! `Verdict::Unchanged`.
//!
//! Frame: font units, y up, both outlines in the same coordinate frame (the
//! source outline's own frame). Tolerances come from the master drawing's own
//! coordinate pitch (`Params::grid`); no figure from any other glyph enters.
//!
//! Fill rules: the master is the union of its strokes (each stroke filled by
//! its own nonzero winding); the source is one outline set filled by the
//! summed nonzero winding (counters subtract), as in the silhouette gate.
//!
//! Exactness: curves are flattened by adaptive subdivision until the control
//! points lie within `grid` of the chord. The symmetric-difference area is
//! then exact for the flattened outlines (slab integration, edge crossings
//! included), so its error against the true curves is bounded by
//! `grid * perimeter` per outline; that bound is the reported area floor.
//!
//! Hausdorff distance and the p95 point distance are sampled: boundary
//! points (sub-edge ends and midpoints, each sub-edge at most one grid long)
//! are measured against the other outline, so they are not exact values.
//!
//! The literals 1e-18 and 1e-12 below are float-degeneracy guards
//! (CONVENTION), not geometric tolerances.

use crate::check::locate;
use crate::model::{MasterGlyph, Pt, SegKind, StrokeContour};
use crate::raster::polygons;
use crate::validate::{silhouette_gate, Gate, Params, ValidateError};

/// Resource limit on curve subdivision depth. A guard, not a measurement.
pub const MAX_FLATTEN_DEPTH: u32 = 24;
/// Resource limit on polygon edges in the slab integration (pairwise
/// crossing search). A guard, not a measurement.
pub const MAX_EDGES: usize = 4096;
/// Resource limit on boundary sub-edges in the distance search. A guard.
pub const MAX_SUBEDGES: usize = 16384;

/// How the master's contours are filled. Strokes that overlap freely are a
/// union (`UnionOfStrokes`); a master that copies an export-style outline
/// (counters as separate opposite-winding contours) is `Merged`, the same
/// summed-winding rule the source uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MasterFill {
    UnionOfStrokes,
    Merged,
}

/// Input path of a result. Every reported row carries one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PathLabel {
    /// Source outline read directly, exact geometry in font units.
    Vector,
    /// Source outline rasterised for a cross-check ("vector, rasterised").
    VectorRasterised,
    /// Image path (capture then fit). Declared for completeness; no vector
    /// measurement in this module produces it.
    Image,
}

impl PathLabel {
    pub fn as_str(self) -> &'static str {
        match self {
            PathLabel::Vector => "vector",
            PathLabel::VectorRasterised => "vector, rasterised",
            PathLabel::Image => "image",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum VectorError {
    Pitch(ValidateError),
    EdgeBudget { edges: usize, limit: usize },
    EmptyOutline,
}

impl From<ValidateError> for VectorError {
    fn from(e: ValidateError) -> Self {
        VectorError::Pitch(e)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Axis {
    X,
    Y,
}

/// An axis extremum strictly inside a curve segment with no on-curve node at
/// it (farther than `grid` from both segment ends).
#[derive(Debug, Clone, PartialEq)]
pub struct ExtremumGap {
    pub contour: usize,
    pub segment: usize,
    pub axis: Axis,
    pub t: f64,
    pub point: Pt,
}

/// A parameter where the curve speed (derivative magnitude over 3, the
/// Bernstein normalisation) is within `grid`: a candidate stationary
/// inflection or cusp. Reported separately, never gated.
#[derive(Debug, Clone, PartialEq)]
pub struct StationaryPoint {
    pub contour: usize,
    pub segment: usize,
    pub t: f64,
    pub point: Pt,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExtremaReport {
    pub curve_segments: usize,
    pub missing: Vec<ExtremumGap>,
    pub stationary: Vec<StationaryPoint>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// Geometry within the flattening floors and the same node and extrema
    /// counts as the source.
    Unchanged,
    /// Geometry within the floors (equal distance) and not worse in node
    /// count or missing extrema, with at least one strictly better.
    Improved,
    /// Anything else (geometry outside the floors, or worse counts). Reported
    /// as measured; not a failure by itself.
    Differs,
}

#[derive(Debug, Clone)]
pub struct Fidelity {
    pub label: PathLabel,
    /// Symmetric-difference area, font units^2.
    pub symdiff_area: f64,
    pub source_area: f64,
    /// symdiff_area / source_area (0 when the source area is 0).
    pub symdiff_fraction: f64,
    /// Sampled Hausdorff distance between the two outlines, font units.
    pub hausdorff: f64,
    /// 95th percentile (nearest rank) of boundary point distances, both
    /// directions pooled, font units.
    pub p95: f64,
    /// Flattening tolerance used (= the drawing's grid).
    pub flatten_tol: f64,
    /// Area equivalence floor: grid * (perimeter of both outlines).
    pub area_floor: f64,
    /// Sum of both flattened outline perimeters used to derive the area floor.
    pub perimeter_sum: f64,
    /// Distance equivalence floor: 2 * grid.
    pub distance_floor: f64,
    pub samples: usize,
}

#[derive(Debug, Clone)]
pub struct VectorReport {
    pub label: PathLabel,
    pub fidelity: Fidelity,
    pub nodes_master: usize,
    pub nodes_source: usize,
    pub extrema_master: ExtremaReport,
    pub extrema_source: ExtremaReport,
    pub verdict: Verdict,
}

impl VectorReport {
    /// Tab-separated rows, every one starting with the path label:
    /// `label  row  quantity  value  unit`.
    pub fn rows(&self) -> Vec<String> {
        let l = self.label.as_str();
        let f = &self.fidelity;
        vec![
            format!("{l}\tA4\tsymmetric_difference_area\t{}\tunit^2", f.symdiff_area),
            format!("{l}\tA4\tsymmetric_difference_fraction\t{}\tfraction_of_source_area", f.symdiff_fraction),
            format!("{l}\tA4\thausdorff\t{}\tunits", f.hausdorff),
            format!("{l}\tA4\tp95_point_distance\t{}\tunits", f.p95),
            format!("{l}\tA4\tarea_equivalence_floor\t{}\tunit^2", f.area_floor),
            format!("{l}\tA4\tdistance_equivalence_floor\t{}\tunits", f.distance_floor),
            format!("{l}\tA5\tmissing_extrema_master\t{}\tcount", self.extrema_master.missing.len()),
            format!("{l}\tA5\tmissing_extrema_source\t{}\tcount", self.extrema_source.missing.len()),
            format!("{l}\tA5\tstationary_points_master\t{}\tcount", self.extrema_master.stationary.len()),
            format!("{l}\tnodes\tmaster\t{}\tcount", self.nodes_master),
            format!("{l}\tnodes\tsource\t{}\tcount", self.nodes_source),
            format!("{l}\tverdict\tmaster_vs_source\t{:?}\t-", self.verdict),
        ]
    }
}

// ---------------------------------------------------------------- flattening

fn dist_to_chord(p: Pt, a: Pt, b: Pt) -> f64 {
    let (vx, vy) = (b.0 - a.0, b.1 - a.1);
    let len2 = vx * vx + vy * vy;
    if len2 <= 1e-18 {
        return (p.0 - a.0).hypot(p.1 - a.1);
    }
    ((p.0 - a.0) * vy - (p.1 - a.1) * vx).abs() / len2.sqrt()
}

fn mid(a: Pt, b: Pt) -> Pt {
    ((a.0 + b.0) * 0.5, (a.1 + b.1) * 0.5)
}

/// Push the interior flattened points of a cubic (excluding both ends).
fn flatten_cubic(p0: Pt, c1: Pt, c2: Pt, p1: Pt, tol: f64, depth: u32, out: &mut Vec<Pt>) {
    if depth >= MAX_FLATTEN_DEPTH || (dist_to_chord(c1, p0, p1) <= tol && dist_to_chord(c2, p0, p1) <= tol) {
        return;
    }
    let p01 = mid(p0, c1);
    let p12 = mid(c1, c2);
    let p23 = mid(c2, p1);
    let p012 = mid(p01, p12);
    let p123 = mid(p12, p23);
    let m = mid(p012, p123);
    flatten_cubic(p0, p01, p012, m, tol, depth + 1, out);
    out.push(m);
    flatten_cubic(m, p123, p23, p1, tol, depth + 1, out);
}

/// Closed polygon of one contour, curves flattened to `tol`.
pub fn outline_polygon(c: &StrokeContour, tol: f64) -> Vec<Pt> {
    let mut poly = Vec::new();
    for s in c.segments() {
        poly.push(s.p0);
        if s.kind == SegKind::Curve {
            if let (Some(c1), Some(c2)) = (s.c1, s.c2) {
                flatten_cubic(s.p0, c1, c2, s.p1, tol, 0, &mut poly);
            }
        }
    }
    poly
}

fn outline_polygons(g: &MasterGlyph, tol: f64) -> Vec<Vec<Pt>> {
    g.contours.iter().map(|c| outline_polygon(c, tol)).filter(|p| p.len() >= 3).collect()
}

fn perimeter(polys: &[Vec<Pt>]) -> f64 {
    let mut s = 0.0;
    for p in polys {
        for i in 0..p.len() {
            let (a, b) = (p[i], p[(i + 1) % p.len()]);
            s += (b.0 - a.0).hypot(b.1 - a.1);
        }
    }
    s
}

fn count_nodes(g: &MasterGlyph) -> usize {
    g.contours.iter().map(|c| c.nodes().len()).sum()
}

// ------------------------------------------------------- slab area integration

type Edge = (Pt, Pt);

fn edges_of(polys: &[Vec<Pt>]) -> Vec<Edge> {
    let mut e = Vec::new();
    for p in polys {
        for i in 0..p.len() {
            let (a, b) = (p[i], p[(i + 1) % p.len()]);
            if (a.0 - b.0).abs() > 0.0 || (a.1 - b.1).abs() > 0.0 {
                e.push((a, b));
            }
        }
    }
    e
}

/// y of the intersection of two segments, when they properly cross.
fn crossing_y(e1: Edge, e2: Edge) -> Option<f64> {
    let (p, r) = (e1.0, (e1.1 .0 - e1.0 .0, e1.1 .1 - e1.0 .1));
    let (q, s) = (e2.0, (e2.1 .0 - e2.0 .0, e2.1 .1 - e2.0 .1));
    let den = r.0 * s.1 - r.1 * s.0;
    if den.abs() < 1e-18 {
        return None;
    }
    let t = ((q.0 - p.0) * s.1 - (q.1 - p.1) * s.0) / den;
    let u = ((q.0 - p.0) * r.1 - (q.1 - p.1) * r.0) / den;
    if (0.0..=1.0).contains(&t) && (0.0..=1.0).contains(&u) {
        Some(p.1 + t * r.1)
    } else {
        None
    }
}

/// Sorted x crossings (x, winding direction) of a polygon set at height y.
fn crossings(polys: &[Vec<Pt>], y: f64) -> Vec<(f64, i32)> {
    let mut out = Vec::new();
    for p in polys {
        for i in 0..p.len() {
            let (a, b) = (p[i], p[(i + 1) % p.len()]);
            if (a.1 < y) != (b.1 < y) {
                let x = a.0 + (y - a.1) / (b.1 - a.1) * (b.0 - a.0);
                out.push((x, if b.1 > a.1 { 1 } else { -1 }));
            }
        }
    }
    out.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    out
}

/// Intervals where the running winding is nonzero.
fn nonzero_intervals(cr: &[(f64, i32)]) -> Vec<(f64, f64)> {
    let mut out = Vec::new();
    let mut w = 0;
    let mut start = 0.0;
    for &(x, d) in cr {
        let before = w;
        w += d;
        if before == 0 && w != 0 {
            start = x;
        } else if before != 0 && w == 0 {
            out.push((start, x));
        }
    }
    out
}

fn merge_intervals(mut v: Vec<(f64, f64)>) -> Vec<(f64, f64)> {
    v.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    let mut out: Vec<(f64, f64)> = Vec::new();
    for (a, b) in v {
        match out.last_mut() {
            Some(last) if a <= last.1 => {
                if b > last.1 {
                    last.1 = b;
                }
            }
            _ => out.push((a, b)),
        }
    }
    out
}

fn total_len(v: &[(f64, f64)]) -> f64 {
    v.iter().map(|(a, b)| b - a).sum()
}

fn overlap_len(a: &[(f64, f64)], b: &[(f64, f64)]) -> f64 {
    let (mut i, mut j, mut s) = (0, 0, 0.0);
    while i < a.len() && j < b.len() {
        let lo = a[i].0.max(b[j].0);
        let hi = a[i].1.min(b[j].1);
        if hi > lo {
            s += hi - lo;
        }
        if a[i].1 < b[j].1 {
            i += 1;
        } else {
            j += 1;
        }
    }
    s
}

/// (symmetric-difference area, source area). `master` polygons are filled as
/// a union of per-polygon nonzero fills; `source` polygons by summed winding.
/// Exact for the given polygons: between consecutive vertex heights and edge
/// crossing heights the xor length is linear in y.
fn slab_areas(master: &[Vec<Pt>], source: &[Vec<Pt>], fill: MasterFill) -> Result<(f64, f64), VectorError> {
    let mut edges = edges_of(master);
    edges.extend(edges_of(source));
    if edges.len() > MAX_EDGES {
        return Err(VectorError::EdgeBudget { edges: edges.len(), limit: MAX_EDGES });
    }
    let mut ys: Vec<f64> = Vec::new();
    for e in &edges {
        ys.push(e.0 .1);
        ys.push(e.1 .1);
    }
    for i in 0..edges.len() {
        for j in (i + 1)..edges.len() {
            if let Some(y) = crossing_y(edges[i], edges[j]) {
                ys.push(y);
            }
        }
    }
    ys.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    ys.dedup_by(|a, b| (*a - *b).abs() < 1e-12);
    let (mut sym, mut src) = (0.0, 0.0);
    for w in ys.windows(2) {
        let h = w[1] - w[0];
        if h <= 0.0 {
            continue;
        }
        let y = 0.5 * (w[0] + w[1]);
        let mi = match fill {
            MasterFill::UnionOfStrokes => {
                let mut v = Vec::new();
                for p in master {
                    v.extend(nonzero_intervals(&crossings(std::slice::from_ref(p), y)));
                }
                merge_intervals(v)
            }
            MasterFill::Merged => nonzero_intervals(&crossings(master, y)),
        };
        let si = nonzero_intervals(&crossings(source, y));
        let xor = total_len(&mi) + total_len(&si) - 2.0 * overlap_len(&mi, &si);
        sym += h * xor;
        src += h * total_len(&si);
    }
    Ok((sym, src))
}

// --------------------------------------------------------- boundary distances

fn seg_dist(p: Pt, a: Pt, b: Pt) -> f64 {
    let (vx, vy) = (b.0 - a.0, b.1 - a.1);
    let len2 = vx * vx + vy * vy;
    let t = if len2 > 1e-18 { (((p.0 - a.0) * vx + (p.1 - a.1) * vy) / len2).clamp(0.0, 1.0) } else { 0.0 };
    (p.0 - (a.0 + t * vx)).hypot(p.1 - (a.1 + t * vy))
}

/// Boundary sub-edges (each no longer than `step`). With `union_of_strokes`
/// a sub-edge whose midpoint lies strictly inside another polygon (farther
/// than `margin` from its edge) is interior to the union and dropped.
fn boundary_subedges(polys: &[Vec<Pt>], step: f64, union_of_strokes: bool, margin: f64) -> Vec<Edge> {
    let mut out = Vec::new();
    for (k, p) in polys.iter().enumerate() {
        for i in 0..p.len() {
            let (a, b) = (p[i], p[(i + 1) % p.len()]);
            let len = (b.0 - a.0).hypot(b.1 - a.1);
            if len <= 0.0 {
                continue;
            }
            let n = ((len / step).ceil() as usize).max(1);
            for s in 0..n {
                let (t0, t1) = (s as f64 / n as f64, (s + 1) as f64 / n as f64);
                let pa = (a.0 + t0 * (b.0 - a.0), a.1 + t0 * (b.1 - a.1));
                let pb = (a.0 + t1 * (b.0 - a.0), a.1 + t1 * (b.1 - a.1));
                if union_of_strokes {
                    let m = mid(pa, pb);
                    let buried = polys.iter().enumerate().any(|(j, q)| {
                        if j == k {
                            return false;
                        }
                        let (inside, d) = locate(m, q);
                        inside && d > margin
                    });
                    if buried {
                        continue;
                    }
                }
                out.push((pa, pb));
            }
        }
    }
    out
}

fn sample_points(e: &[Edge]) -> Vec<Pt> {
    let mut v = Vec::with_capacity(e.len() * 2);
    for &(a, b) in e {
        v.push(a);
        v.push(mid(a, b));
    }
    v
}

fn dists_to(points: &[Pt], edges: &[Edge]) -> Vec<f64> {
    points
        .iter()
        .map(|&p| edges.iter().map(|&(a, b)| seg_dist(p, a, b)).fold(f64::INFINITY, f64::min))
        .collect()
}

/// Nearest-rank percentile (convention) of an unsorted slice.
fn percentile(v: &mut [f64], q: f64) -> f64 {
    if v.is_empty() {
        return 0.0;
    }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let rank = ((q * v.len() as f64).ceil() as usize).clamp(1, v.len());
    v[rank - 1]
}

// ----------------------------------------------------------------- fidelity

/// Exact-geometry fidelity of `master` against `source` (path label "vector").
pub fn vector_fidelity(master: &MasterGlyph, source: &MasterGlyph, params: Params, fill: MasterFill) -> Result<Fidelity, VectorError> {
    let tol = params.grid;
    let mp = outline_polygons(master, tol);
    let sp = outline_polygons(source, tol);
    if mp.is_empty() || sp.is_empty() {
        return Err(VectorError::EmptyOutline);
    }
    let (symdiff, source_area) = slab_areas(&mp, &sp, fill)?;
    let mb = boundary_subedges(&mp, tol, fill == MasterFill::UnionOfStrokes, params.margin);
    let sb = boundary_subedges(&sp, tol, false, params.margin);
    if mb.len() + sb.len() > MAX_SUBEDGES {
        return Err(VectorError::EdgeBudget { edges: mb.len() + sb.len(), limit: MAX_SUBEDGES });
    }
    let mut d = dists_to(&sample_points(&mb), &sb);
    d.extend(dists_to(&sample_points(&sb), &mb));
    let hausdorff = d.iter().cloned().fold(0.0, f64::max);
    let samples = d.len();
    let p95 = percentile(&mut d, 0.95);
    Ok(Fidelity {
        label: PathLabel::Vector,
        symdiff_area: symdiff,
        source_area,
        symdiff_fraction: if source_area > 0.0 { symdiff / source_area } else { 0.0 },
        hausdorff,
        p95,
        flatten_tol: tol,
        area_floor: tol * (perimeter(&mp) + perimeter(&sp)),
        perimeter_sum: perimeter(&mp) + perimeter(&sp),
        distance_floor: 2.0 * tol,
        samples,
    })
}

// ------------------------------------------------------------ exact extrema

fn eval_cubic(p0: f64, p1: f64, p2: f64, p3: f64, t: f64) -> f64 {
    let m = 1.0 - t;
    m * m * m * p0 + 3.0 * m * m * t * p1 + 3.0 * m * t * t * p2 + t * t * t * p3
}

/// Real roots in (0,1) where the derivative of the cubic Bezier coordinate
/// changes sign (a double root is a stationary inflection, not an extremum).
fn extremum_params(a0: f64, a1: f64, a2: f64, a3: f64) -> Vec<f64> {
    let (d0, d1, d2) = (a1 - a0, a2 - a1, a3 - a2);
    let qa = d0 - 2.0 * d1 + d2;
    let qb = 2.0 * (d1 - d0);
    let qc = d0;
    let scale = d0.abs() + d1.abs() + d2.abs();
    let mut r = Vec::new();
    if scale == 0.0 {
        return r;
    }
    if qa.abs() <= 1e-12 * scale {
        if qb.abs() > 1e-12 * scale {
            r.push(-qc / qb);
        }
    } else {
        let disc = qb * qb - 4.0 * qa * qc;
        if disc > 0.0 {
            let s = disc.sqrt();
            // numerically stable pair
            let q = -0.5 * (qb + qb.signum() * s);
            r.push(q / qa);
            if q != 0.0 {
                r.push(qc / q);
            }
        }
    }
    r.into_iter().filter(|t| *t > 0.0 && *t < 1.0).collect()
}

fn derivative_speed(p: [Pt; 4], t: f64) -> f64 {
    let m = 1.0 - t;
    let d = |a: f64, b: f64, c: f64, e: f64| -> f64 {
        let (d0, d1, d2) = (b - a, c - b, e - c);
        d0 * m * m + 2.0 * d1 * m * t + d2 * t * t
    };
    d(p[0].0, p[1].0, p[2].0, p[3].0).hypot(d(p[0].1, p[1].1, p[2].1, p[3].1))
}

/// Exact axis-extrema coverage of a glyph's outlines: every interior zero of
/// dx/dt or dy/dt of a curve segment must have an on-curve node, i.e. lie
/// within `grid` of a segment end. The result is a geometric check on the
/// outline, not a label check.
pub fn exact_extrema(g: &MasterGlyph, params: Params) -> ExtremaReport {
    let tol = params.grid;
    let mut rep = ExtremaReport { curve_segments: 0, missing: Vec::new(), stationary: Vec::new() };
    for (ci, c) in g.contours.iter().enumerate() {
        for (si, s) in c.segments().iter().enumerate() {
            if s.kind != SegKind::Curve {
                continue;
            }
            let (c1, c2) = match (s.c1, s.c2) {
                (Some(a), Some(b)) => (a, b),
                _ => continue,
            };
            rep.curve_segments += 1;
            let pts = [s.p0, c1, c2, s.p1];
            for (axis, ts) in [
                (Axis::X, extremum_params(s.p0.0, c1.0, c2.0, s.p1.0)),
                (Axis::Y, extremum_params(s.p0.1, c1.1, c2.1, s.p1.1)),
            ] {
                for t in ts {
                    let pt = (
                        eval_cubic(s.p0.0, c1.0, c2.0, s.p1.0, t),
                        eval_cubic(s.p0.1, c1.1, c2.1, s.p1.1, t),
                    );
                    let near_end = (pt.0 - s.p0.0).hypot(pt.1 - s.p0.1) <= tol || (pt.0 - s.p1.0).hypot(pt.1 - s.p1.1) <= tol;
                    if !near_end {
                        rep.missing.push(ExtremumGap { contour: ci, segment: si, axis, t, point: pt });
                    }
                    if derivative_speed(pts, t) <= tol {
                        rep.stationary.push(StationaryPoint { contour: ci, segment: si, t, point: pt });
                    }
                }
            }
        }
    }
    rep
}

// ------------------------------------------------------------------- report

/// Full vector-path report of `master` against `source`.
pub fn analyse(master: &MasterGlyph, source: &MasterGlyph, fill: MasterFill) -> Result<VectorReport, VectorError> {
    let params = Params::derive(master)?;
    analyse_with(master, source, params, fill)
}

pub fn analyse_with(master: &MasterGlyph, source: &MasterGlyph, params: Params, fill: MasterFill) -> Result<VectorReport, VectorError> {
    let fidelity = vector_fidelity(master, source, params, fill)?;
    let extrema_master = exact_extrema(master, params);
    let extrema_source = exact_extrema(source, params);
    let (nm, ns) = (count_nodes(master), count_nodes(source));
    let within = fidelity.symdiff_area <= fidelity.area_floor && fidelity.hausdorff <= fidelity.distance_floor;
    let (em, es) = (extrema_master.missing.len(), extrema_source.missing.len());
    let verdict = if !within || nm > ns || em > es {
        Verdict::Differs
    } else if nm == ns && em == es {
        Verdict::Unchanged
    } else {
        Verdict::Improved
    };
    Ok(VectorReport {
        label: PathLabel::Vector,
        fidelity,
        nodes_master: nm,
        nodes_source: ns,
        extrema_master,
        extrema_source,
        verdict,
    })
}

/// Raster cross-check of the same pair, labelled "vector, rasterised". Never
/// compared with the exact-geometry rows.
pub fn rasterised_cross_check(master: &MasterGlyph, source: &MasterGlyph) -> Result<(PathLabel, Gate), ValidateError> {
    let expected = polygons(source);
    let gate = silhouette_gate(master, &expected)?;
    Ok((PathLabel::VectorRasterised, gate))
}
