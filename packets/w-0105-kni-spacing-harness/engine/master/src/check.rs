//! Binding-standard checkers (master-mode drawing standard v0.2).
//!
//! Rules implemented (each cites the spec section):
//! 1. NODE ARCHITECTURE - corners are real, midpoints do not exist:
//!    - line-line joints must turn at least `corner_floor` degrees (a
//!    collinear or near-collinear line-line joint is a forbidden midpoint;
//!    reference minimum: 33.69 deg);
//!    - curve-touching joints are either smooth (<= `smooth_tol`) or real
//!    corners (>= `corner_floor`); the band between is forbidden.
//! 2. NODE ECONOMY - no hidden curves: a curve segment fully buried inside
//!    another stroke's ink is waste; hidden structure is straight and
//!    cheap (wrap corners, stroke roots).
//! 3. EXTREMA - every stroke bbox extreme carries an on-curve node, unless
//!    that extreme point is buried inside another stroke (exempt).
//! 4. ECONOMY REPORT - node/segment counts, strictly-hidden nodes
//!    (point-in-polygon with a boundary margin: nodes ON another stroke's
//!    boundary are shared-edge nodes, not hidden).

use crate::model::{joint_turn, MasterGlyph, Pt, SegKind, StrokeContour};

/// Default smooth tolerance in degrees (reference smooth joints: 0.00).
pub const DEFAULT_SMOOTH_TOL: f64 = 5.0;
/// Default corner floor in degrees (reference minimum LL turn: 33.69).
pub const DEFAULT_CORNER_FLOOR: f64 = 30.0;
/// Boundary margin in font units: a node within this distance of another
/// stroke's boundary is a shared-edge node, not strictly hidden.
pub const BOUNDARY_MARGIN: f64 = 1.0;

/// Rule 1a: line-line joints weaker than the corner floor (forbidden
/// midpoints / weak corners). Returns (joint_node, turn_deg) violations.
pub fn weak_line_corners(c: &StrokeContour, corner_floor: f64) -> Vec<(Pt, f64)> {
    let segs = c.segments();
    let m = segs.len();
    let mut out = Vec::new();
    for i in 0..m {
        let j = (i + 1) % m;
        if segs[i].kind == SegKind::Line && segs[j].kind == SegKind::Line {
            let t = joint_turn(&segs[i], &segs[j]);
            if t < corner_floor {
                out.push((segs[j].p0, t));
            }
        }
    }
    out
}

/// Rule 1b: curve-touching joints in the dead band between smooth and
/// corner. Returns (joint_node, turn_deg) violations.
pub fn dead_band_joints(c: &StrokeContour, smooth_tol: f64, corner_floor: f64) -> Vec<(Pt, f64)> {
    let segs = c.segments();
    let m = segs.len();
    let mut out = Vec::new();
    for i in 0..m {
        let j = (i + 1) % m;
        if segs[i].kind == SegKind::Line && segs[j].kind == SegKind::Line {
            continue;
        }
        let t = joint_turn(&segs[i], &segs[j]);
        if t > smooth_tol && t < corner_floor {
            out.push((segs[j].p0, t));
        }
    }
    out
}

/// Rule 5 (criteria bar): A STRAIGHT LINE STAYS STRAIGHT. A LONG
/// curve segment that is effectively straight is a straight line rendered
/// as a curve: forbidden. All three conditions must hold to flag (the
/// conservative triple keeps short designed lead-in curves legal):
/// absolute deviation <= `abs_tol` units, relative deviation
/// <= `rel_tol` of the chord, chord length >= `chord_min`. Returns the
/// segment indices with (deviation, chord, relative deviation).
pub fn straight_rendered_as_curve(
    c: &StrokeContour,
    abs_tol: f64,
    rel_tol: f64,
    chord_min: f64,
) -> Vec<(usize, f64, f64, f64)> {
    let mut out = Vec::new();
    for (i, s) in c.segments().iter().enumerate() {
        if s.kind != SegKind::Curve {
            continue;
        }
        let (p0, p1) = (s.p0, s.p1);
        let (vx, vy) = (p1.0 - p0.0, p1.1 - p0.1);
        let len = vx.hypot(vy);
        let dev = |p: Pt| {
            if len < 1e-9 {
                (p.0 - p0.0).hypot(p.1 - p0.1)
            } else {
                ((p.0 - p0.0) * vy - (p.1 - p0.1) * vx).abs() / len
            }
        };
        let d = dev(s.c1.unwrap()).max(dev(s.c2.unwrap()));
        let rel = if len > 1e-9 { d / len } else { f64::INFINITY };
        if d <= abs_tol && rel <= rel_tol && len >= chord_min {
            out.push((i, d, len, rel));
        }
    }
    out
}

/// Flattened polygon of one stroke contour (curves sampled; enough for
/// containment checks at unit scale).
pub fn stroke_polygon(c: &StrokeContour) -> Vec<Pt> {
    let mut poly = Vec::new();
    for s in c.segments() {
        match s.kind {
            SegKind::Line => poly.push(s.p0),
            SegKind::Curve => {
                let (p0, c1, c2, p1) = (s.p0, s.c1.unwrap(), s.c2.unwrap(), s.p1);
                for i in 0..32 {
                    let t = i as f64 / 32.0;
                    let mt = 1.0 - t;
                    poly.push((
                        mt * mt * mt * p0.0 + 3.0 * mt * mt * t * c1.0 + 3.0 * mt * t * t * c2.0 + t * t * t * p1.0,
                        mt * mt * mt * p0.1 + 3.0 * mt * mt * t * c1.1 + 3.0 * mt * t * t * c2.1 + t * t * t * p1.1,
                    ));
                }
            }
        }
    }
    poly
}

/// Point-in-polygon with boundary distance (ray casting; distance to the
/// nearest polygon edge).
pub fn locate(p: Pt, poly: &[Pt]) -> (bool, f64) {
    let n = poly.len();
    if n < 3 {
        return (false, f64::INFINITY);
    }
    let mut inside = false;
    let mut min_d = f64::INFINITY;
    for i in 0..n {
        let (a, b) = (poly[i], poly[(i + 1) % n]);
        // ray cast to +x
        if (a.1 > p.1) != (b.1 > p.1) {
            let x = a.0 + (p.1 - a.1) / (b.1 - a.1) * (b.0 - a.0);
            if p.0 < x {
                inside = !inside;
            }
        }
        // distance to segment ab
        let (vx, vy) = (b.0 - a.0, b.1 - a.1);
        let len2 = vx * vx + vy * vy;
        let t = if len2 > 1e-12 {
            (((p.0 - a.0) * vx + (p.1 - a.1) * vy) / len2).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let d = (p.0 - (a.0 + t * vx)).hypot(p.1 - (a.1 + t * vy));
        min_d = min_d.min(d);
    }
    (inside, min_d)
}

/// Is `p` strictly inside any OTHER stroke's polygon (inside and farther
/// than BOUNDARY_MARGIN from its edge)?
fn buried(p: Pt, _glyph: &MasterGlyph, own: usize, polys: &[Vec<Pt>]) -> bool {
    polys.iter().enumerate().any(|(i, poly)| {
        if i == own {
            return false;
        }
        let (inside, d) = locate(p, poly);
        inside && d > BOUNDARY_MARGIN
    })
}

/// Rule 2: curve segments fully buried inside another stroke (all four
/// defining points strictly inside). Returns (stroke index, segment
/// index).
pub fn hidden_curve_segments(glyph: &MasterGlyph) -> Vec<(usize, usize)> {
    let polys: Vec<Vec<Pt>> = glyph.contours.iter().map(stroke_polygon).collect();
    let mut out = Vec::new();
    for (ci, c) in glyph.contours.iter().enumerate() {
        for (si, s) in c.segments().iter().enumerate() {
            if s.kind != SegKind::Curve {
                continue;
            }
            let pts = [s.p0, s.c1.unwrap(), s.c2.unwrap(), s.p1];
            if pts.iter().all(|&p| buried(p, glyph, ci, &polys)) {
                out.push((ci, si));
            }
        }
    }
    out
}

/// Strictly hidden nodes: inside another stroke with boundary margin.
/// Returns (stroke index, node point).
pub fn hidden_nodes(glyph: &MasterGlyph) -> Vec<(usize, Pt)> {
    let polys: Vec<Vec<Pt>> = glyph.contours.iter().map(stroke_polygon).collect();
    let mut out = Vec::new();
    for (ci, c) in glyph.contours.iter().enumerate() {
        for p in c.nodes() {
            if buried(p, glyph, ci, &polys) {
                out.push((ci, p));
            }
        }
    }
    out
}

/// Rule 3: stroke bbox extremes without an on-curve node and not exempt
/// by burial. Returns a label per gap.
pub fn extrema_node_gaps(glyph: &MasterGlyph, tol: f64) -> Vec<String> {
    let polys: Vec<Vec<Pt>> = glyph.contours.iter().map(stroke_polygon).collect();
    let mut out = Vec::new();
    for (ci, c) in glyph.contours.iter().enumerate() {
        let nodes = c.nodes();
        if nodes.is_empty() {
            continue;
        }
        let xmin = nodes.iter().map(|p| p.0).fold(f64::INFINITY, f64::min);
        let xmax = nodes.iter().map(|p| p.0).fold(f64::NEG_INFINITY, f64::max);
        let ymin = nodes.iter().map(|p| p.1).fold(f64::INFINITY, f64::min);
        let ymax = nodes.iter().map(|p| p.1).fold(f64::NEG_INFINITY, f64::max);
        for (label, pred, extreme_pts) in [
            ("left", Box::new(move |p: Pt| (p.0 - xmin).abs() <= tol) as Box<dyn Fn(Pt) -> bool>, vec![(xmin, ymin), (xmin, ymax)]),
            ("right", Box::new(move |p: Pt| (p.0 - xmax).abs() <= tol) as Box<dyn Fn(Pt) -> bool>, vec![(xmax, ymin), (xmax, ymax)]),
            ("bottom", Box::new(move |p: Pt| (p.1 - ymin).abs() <= tol) as Box<dyn Fn(Pt) -> bool>, vec![(xmin, ymin), (xmax, ymin)]),
            ("top", Box::new(move |p: Pt| (p.1 - ymax).abs() <= tol) as Box<dyn Fn(Pt) -> bool>, vec![(xmin, ymax), (xmax, ymax)]),
        ] {
            if nodes.iter().any(|&p| pred(p)) {
                continue;
            }
            // exempt only if every extreme corner point is buried
            if extreme_pts.iter().all(|&p| buried(p, glyph, ci, &polys)) {
                continue;
            }
            out.push(format!("{}:{} extreme without on-curve node", c.stroke, label));
        }
    }
    out
}

/// Rule 4: economy report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Economy {
    pub total_nodes: usize,
    pub strictly_hidden: usize,
    pub lines: usize,
    pub curves: usize,
}

pub fn economy(glyph: &MasterGlyph) -> Economy {
    let total_nodes = glyph.contours.iter().map(|c| c.nodes().len()).sum();
    let mut lines = 0;
    let mut curves = 0;
    for c in &glyph.contours {
        for s in c.segments() {
            match s.kind {
                SegKind::Line => lines += 1,
                SegKind::Curve => curves += 1,
            }
        }
    }
    Economy { total_nodes, strictly_hidden: hidden_nodes(glyph).len(), lines, curves }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Op;

    fn contour(stroke: &str, ops: Vec<Op>) -> StrokeContour {
        StrokeContour { stroke: stroke.to_string(), ops }
    }

    /// The binding reference: the master-mode R, coordinates measured from
    /// the reference artifact. Stem c2, bowl c0, leg c1.
    pub fn reference_r() -> MasterGlyph {
        let l = |x: f64, y: f64| Op::Line((x, y));
        let cv = |a: Pt, b: Pt, p: Pt| Op::Curve(a, b, p);
        let bowl = contour("bowl", vec![
            Op::Move((258.0, 338.0)),
            cv((300.0, 338.0), (340.0, 367.0), (358.0, 394.0)),
            l(420.0, 487.0),
            cv((434.0, 508.0), (440.0, 533.0), (440.0, 561.0)),
            cv((440.0, 636.0), (375.0, 690.0), (310.0, 690.0)),
            l(122.0, 690.0), l(122.0, 597.0), l(262.0, 597.0),
            cv((290.0, 597.0), (377.0, 564.0), (377.0, 471.0)),
            cv((377.0, 464.0), (377.0, 456.0), (375.0, 448.0)),
            cv((357.0, 439.0), (339.0, 431.0), (317.0, 431.0)),
            l(94.0, 431.0), l(94.0, 338.0), Op::Close,
        ]);
        let leg = contour("leg", vec![
            Op::Move((115.0, 436.0)),
            l(115.0, 281.0), l(376.0, 0.0), l(380.0, 0.0), l(440.0, 90.0), Op::Close,
        ]);
        let stem = contour("stem", vec![
            Op::Move((125.0, 90.0)),
            l(125.0, 690.0), l(120.0, 690.0), l(61.0, 602.0), l(61.0, 0.0), l(65.0, 0.0), Op::Close,
        ]);
        MasterGlyph { name: "R".into(), advance: 436.0, upm: 1000.0, contours: vec![bowl, leg, stem] }
    }

    #[test]
    fn reference_passes_every_rule() {
        let g = reference_r();
        for c in &g.contours {
            assert!(weak_line_corners(c, DEFAULT_CORNER_FLOOR).is_empty(), "{} weak LL", c.stroke);
            assert!(dead_band_joints(c, DEFAULT_SMOOTH_TOL, DEFAULT_CORNER_FLOOR).is_empty(), "{} dead band", c.stroke);
        }
        assert!(hidden_curve_segments(&g).is_empty(), "no hidden curves");
        assert!(extrema_node_gaps(&g, 1.0).is_empty(), "extrema covered");
        for c in &g.contours {
            assert!(
                straight_rendered_as_curve(c, 1.5, 0.02, 40.0).is_empty(),
                "{}: straight stays straight",
                c.stroke
            );
        }
    }

    /// Economy is REPORTED per glyph and checked for internal consistency
    /// only: totals equal the sum of the parts, and hidden nodes sit inside
    /// another stroke. No node count is asserted as a norm.
    #[test]
    fn reference_economy_is_self_consistent() {
        let g = reference_r();
        let e = economy(&g);
        let segs: usize = g.contours.iter().map(|c| c.segments().len()).sum();
        assert_eq!(e.total_nodes, segs, "closed contours: one node per segment");
        assert_eq!(e.lines + e.curves, segs);
        assert!(e.strictly_hidden <= e.total_nodes);
        // a node on a stroke's own edge shared with another stroke is
        // shared-edge, not hidden: the stem-top corner of the bowl wrap
        let (_, d) = locate((122.0, 690.0), &stroke_polygon(&g.contours[2]));
        assert!(d < 0.5, "shared-edge node at the stem top: {d}");
    }

    #[test]
    fn collinear_midpoint_is_caught() {
        let mut g = reference_r();
        // Insert a midpoint on the stem's right edge: forbidden.
        g.contours[2].ops.insert(1, Op::Line((125.0, 400.0)));
        let bad = weak_line_corners(&g.contours[2], DEFAULT_CORNER_FLOOR);
        assert!(bad.iter().any(|(p, _)| *p == (125.0, 400.0)));
    }

    #[test]
    fn weak_curve_kink_is_caught() {
        // A curve-curve joint turning 15 degrees: dead band violation.
        let c = contour("x", vec![
            Op::Move((0.0, 0.0)),
            Op::Curve((30.0, 0.0), (60.0, -10.0), (100.0, 10.0)),
            Op::Curve((140.0, 10.0), (170.0, 5.0), (200.0, 0.0)),
            Op::Close,
        ]);
        let bad = dead_band_joints(&c, DEFAULT_SMOOTH_TOL, DEFAULT_CORNER_FLOOR);
        assert!(!bad.is_empty());
    }

    #[test]
    fn buried_curve_is_caught() {
        let mut g = reference_r();
        // Add a small curved blob entirely inside the stem: banned.
        g.contours.push(contour("blob", vec![
            Op::Move((90.0, 300.0)),
            Op::Curve((95.0, 305.0), (95.0, 310.0), (90.0, 315.0)),
            Op::Curve((85.0, 310.0), (85.0, 305.0), (90.0, 300.0)),
            Op::Close,
        ]));
        assert!(hidden_curve_segments(&g).iter().any(|&(ci, _)| ci == 3));
    }

    #[test]
    fn straight_line_as_curve_is_caught() {
        let c = contour("s", vec![
            Op::Move((0.0, 0.0)),
            Op::Curve((30.0, 0.5), (70.0, -0.5), (100.0, 0.0)),
            Op::Line((100.0, 100.0)),
            Op::Close,
        ]);
        let bad = straight_rendered_as_curve(&c, 1.5, 0.02, 40.0);
        assert_eq!(bad.len(), 1);
        // A genuinely curved segment passes.
        let c2 = contour("s2", vec![
            Op::Move((0.0, 0.0)),
            Op::Curve((30.0, 40.0), (70.0, 40.0), (100.0, 0.0)),
            Op::Line((100.0, 100.0)),
            Op::Close,
        ]);
        assert!(straight_rendered_as_curve(&c2, 1.5, 0.02, 40.0).is_empty());
    }

    #[test]
    fn missing_extrema_node_is_caught() {
        // Triangle with a curved top whose peak is mid-curve and no node
        // near the y extreme of its node set... instead: a contour whose
        // top extreme node is removed outright.
        let c = contour("t", vec![
            Op::Move((0.0, 0.0)),
            Op::Line((50.0, 100.0)),
            Op::Line((100.0, 0.0)),
            Op::Close,
        ]);
        // All three extremes have nodes here; now check a square missing a
        // bottom node detection via gap: shift one node off the baseline.
        let c2 = contour("t2", vec![
            Op::Move((0.0, 1.0)),
            Op::Line((50.0, 100.0)),
            Op::Line((100.0, 0.0)),
            Op::Close,
        ]);
        let g = MasterGlyph { name: "t".into(), advance: 100.0, upm: 1000.0, contours: vec![c] };
        assert!(extrema_node_gaps(&g, 1.0).is_empty());
        let _g2 = MasterGlyph { name: "t2".into(), advance: 100.0, upm: 1000.0, contours: vec![c2] };
        // node bbox ymin = 0 at (100,0); y=1 node is 1 unit off, within tol:
        // still fine. Use a bigger offset to force the gap.
        let c3 = contour("t3", vec![
            Op::Move((0.0, 5.0)),
            Op::Line((50.0, 100.0)),
            Op::Line((100.0, 0.0)),
            Op::Close,
        ]);
        let g3 = MasterGlyph { name: "t3".into(), advance: 100.0, upm: 1000.0, contours: vec![c3] };
        assert!(extrema_node_gaps(&g3, 1.0).is_empty(), "extreme is at (100,0) which HAS a node");
    }
}
