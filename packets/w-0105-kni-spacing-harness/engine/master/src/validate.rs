//! Master-mode validator, rules R1-R7.
//!
//! Every check runs on ONE glyph and derives its tolerances from that
//! glyph's own geometry (coordinate pitch, segment lengths, upm). No node
//! count, node ratio or other figure from any glyph is used as a norm:
//! node architecture and economy are judged per glyph. Economy is reported
//! (see `Report::economy`), never gated against another glyph.

use crate::check::{economy, hidden_curve_segments, locate, stroke_polygon, Economy};
use crate::model::{dir_in, dir_out, joint_turn, MasterGlyph, Op, Pt, Seg, SegKind, StrokeContour};
use crate::raster::{bounds_of, paired_iou, polygons, rasterize};

/// Tolerances derived from the glyph itself.
#[derive(Debug, Clone, Copy)]
pub struct Params {
    /// Half the coordinate pitch: the rounding error of the drawing.
    pub grid: f64,
    /// One drawing step (2 * grid): the distance within which a node counts
    /// as lying on another stroke's edge.
    pub margin: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ValidateError {
    /// The coordinates sit on no binary pitch down to the search floor. The
    /// caller must supply the drawing's rounding error (`Params::from_rounding`).
    NoPitch,
    /// The silhouette raster would exceed the allocation limit.
    PixelBudget { pixels: u128, limit: usize },
}

/// Allocation guard for the R7 raster. A resource limit, not a measurement.
pub const MAX_RASTER_PIXELS: usize = 1 << 26;

impl Params {
    /// Rounding error given by the caller (grid = half the pitch).
    pub fn from_rounding(grid: f64) -> Params {
        Params { grid, margin: 2.0 * grid }
    }

    /// Pitch = the coarsest binary step (1, 1/2, ... 1/64) that every
    /// coordinate of the glyph is a multiple of. Pitch is found per axis and
    /// the finer axis wins (the stricter tolerance). `NoPitch` when nothing
    /// down to 1/64 fits: the old silent 1/64 fallback is gone.
    pub fn derive(g: &MasterGlyph) -> Result<Params, ValidateError> {
        let (mut xs, mut ys) = (Vec::new(), Vec::new());
        let mut eat = |p: Pt| {
            xs.push(p.0);
            ys.push(p.1);
        };
        for o in g.contours.iter().flat_map(|c| c.ops.iter()) {
            match o {
                Op::Move(p) | Op::Line(p) => eat(*p),
                Op::Curve(a, b, p) => {
                    eat(*a);
                    eat(*b);
                    eat(*p);
                }
                Op::Close => {}
            }
        }
        let axis = |v: &[f64]| -> Option<f64> {
            let mut cand = 1.0;
            while cand >= 1.0 / 64.0 {
                if v.iter().all(|c| ((c / cand) - (c / cand).round()).abs() < 1e-9) {
                    return Some(cand);
                }
                cand /= 2.0;
            }
            None
        };
        match (axis(&xs), axis(&ys)) {
            (Some(a), Some(b)) => Ok(Params::from_rounding(a.min(b) / 2.0)),
            _ => Err(ValidateError::NoPitch),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Violation {
    pub rule: &'static str,
    pub stroke: String,
    pub at: Option<Pt>,
    pub what: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Role {
    Extremum,
    Corner,
    Junction,
    Wrap,
    /// Hidden line-line corner where a stroke's root ends inside another stroke.
    Root,
    /// Smooth line<->curve hand-over: the segment kind changes here.
    Transition,
}

#[derive(Debug, Clone)]
pub struct Report {
    pub params: Params,
    pub violations: Vec<Violation>,
    pub roles: Vec<(String, Pt, Role)>,
    pub economy: Economy,
}

impl Report {
    pub fn rule_ok(&self, rule: &str) -> bool {
        !self.violations.iter().any(|v| v.rule == rule)
    }
    pub fn ok(&self) -> bool {
        self.violations.is_empty()
    }
}

fn dist(a: Pt, b: Pt) -> f64 {
    (a.0 - b.0).hypot(a.1 - b.1)
}

fn len_in(s: &Seg) -> f64 {
    let d = dir_in(s);
    d.0.hypot(d.1)
}
fn len_out(s: &Seg) -> f64 {
    let d = dir_out(s);
    d.0.hypot(d.1)
}

/// Turn tolerance at one joint, from the shorter of the two direction
/// vectors that define it and the drawing's rounding error.
fn joint_tol(p: &Params, a: &Seg, b: &Seg) -> f64 {
    let l = len_out(a).min(len_in(b)).max(1e-9);
    p.grid.atan2(l).to_degrees()
}

fn signed_area(poly: &[Pt]) -> f64 {
    let n = poly.len();
    (0..n).map(|i| poly[i].0 * poly[(i + 1) % n].1 - poly[(i + 1) % n].0 * poly[i].1).sum::<f64>() / 2.0
}

fn on_edge_of_other(pt: Pt, own: usize, polys: &[Vec<Pt>], margin: f64) -> bool {
    polys.iter().enumerate().any(|(i, poly)| i != own && locate(pt, poly).1 <= margin)
}
fn buried_in_other(pt: Pt, own: usize, polys: &[Vec<Pt>], margin: f64) -> bool {
    polys.iter().enumerate().any(|(i, poly)| {
        if i == own {
            return false;
        }
        let (inside, d) = locate(pt, poly);
        inside && d > margin
    })
}

fn is_axis_aligned(d: Pt, tol_deg: f64) -> bool {
    let a = d.1.atan2(d.0).to_degrees().rem_euclid(90.0);
    a.min(90.0 - a) <= tol_deg
}

/// Validate rules R1-R6 on one master glyph. R7 needs an expected outline:
/// see [`silhouette_gate`].
pub fn validate(g: &MasterGlyph) -> Result<Report, ValidateError> {
    Ok(validate_with(g, Params::derive(g)?))
}

/// As [`validate`], with caller-supplied tolerances.
pub fn validate_with(g: &MasterGlyph, p: Params) -> Report {
    let polys: Vec<Vec<Pt>> = g.contours.iter().map(stroke_polygon).collect();
    let mut v: Vec<Violation> = Vec::new();
    let mut roles = Vec::new();
    let mut push = |rule: &'static str, c: &StrokeContour, at: Option<Pt>, what: String| {
        v.push(Violation { rule, stroke: c.stroke.clone(), at, what })
    };

    // R1: one contour per structural stroke, free overlap, no merge.
    let mut seen = std::collections::HashSet::new();
    for (ci, c) in g.contours.iter().enumerate() {
        if !seen.insert(c.stroke.clone()) {
            push("R1", c, None, "two contours claim the same stroke".into());
        }
        let moves = c.ops.iter().filter(|o| matches!(o, Op::Move(_))).count();
        if moves != 1 || !matches!(c.ops.last(), Some(Op::Close)) {
            push("R1", c, None, format!("a stroke is one closed subpath (moves={moves})"));
        }
        if c.segments().len() < 3 {
            push("R1", c, None, "fewer than 3 segments".into());
        }
        // R1/R2: a counter is not its own contour. A contour lying inside
        // another stroke with opposite winding is a separate counter.
        let a = signed_area(&polys[ci]);
        if let Some(first) = c.nodes().first().copied() {
            for (oi, op) in polys.iter().enumerate() {
                if oi == ci || signed_area(op) * a >= 0.0 {
                    continue;
                }
                let (inside, d) = locate(first, op);
                if inside && d > p.margin {
                    push("R2", c, Some(first), "counter drawn as a separate opposite-winding contour (must be a band wrap in its parent stroke)".into());
                }
            }
        }
        // identical outline drawn twice
        for oi in 0..ci {
            if polys[oi].len() == polys[ci].len()
                && polys[oi].iter().zip(&polys[ci]).all(|(a, b)| dist(*a, *b) <= p.grid)
            {
                push("R1", c, None, format!("duplicates stroke {}", g.contours[oi].stroke));
            }
        }
    }

    for (ci, c) in g.contours.iter().enumerate() {
        let segs = c.segments();
        let m = segs.len();
        for i in 0..m {
            let (a, b) = (&segs[i], &segs[(i + 1) % m]);
            let node = b.p0;
            let turn = joint_turn(a, b);
            let tol = joint_tol(&p, a, b);
            let ll = a.kind == SegKind::Line && b.kind == SegKind::Line;
            let hidden = buried_in_other(node, ci, &polys, p.margin);
            let edge = on_edge_of_other(node, ci, &polys, p.margin);
            if dist(a.p0, a.p1) <= p.grid {
                push("R3", c, Some(a.p0), "zero-length segment (duplicate node)".into());
            }
            // R3 / R5 classification.
            let role = if ll {
                if turn <= tol {
                    push("R3", c, Some(node), format!("collinear midpoint (turn {turn:.2} deg <= tolerance {tol:.2})"));
                    None
                } else if (turn - 90.0).abs() <= tol && (hidden || edge) {
                    Some(Role::Wrap)
                } else if hidden {
                    Some(Role::Root)
                } else if edge {
                    Some(Role::Junction)
                } else {
                    Some(Role::Corner)
                }
            } else if turn > tol {
                // explicit corner touching a curve: handles must not collide
                let collapsed = |s: &Seg, end: bool| match (s.kind, end) {
                    (SegKind::Curve, true) => dist(s.c2.unwrap(), s.p1) <= p.grid,
                    (SegKind::Curve, false) => dist(s.c1.unwrap(), s.p0) <= p.grid,
                    _ => false,
                };
                if collapsed(a, true) || collapsed(b, false) {
                    push("R5", c, Some(node), "corner implied by handle collision (zero-length handle)".into());
                }
                Some(Role::Corner)
            } else if a.kind == SegKind::Curve && b.kind == SegKind::Curve {
                if is_axis_aligned(dir_out(a), tol) {
                    Some(Role::Extremum)
                } else if edge {
                    Some(Role::Junction)
                } else {
                    push("R3", c, Some(node), "smooth curve-curve node away from an extremum, junction or corner".into());
                    None
                }
            } else if is_axis_aligned(dir_out(a), tol) && (a.kind == SegKind::Curve || b.kind == SegKind::Curve) && !edge {
                // smooth hand-over whose tangent is axis aligned is an extremum
                Some(Role::Extremum)
            } else if edge {
                Some(Role::Junction)
            } else {
                Some(Role::Transition)
            };
            if let Some(r) = role {
                roles.push((c.stroke.clone(), node, r));
            }
            // R6: strictly hidden nodes are line-line corners only (90-degree wrap
            // corners, or stroke-root corners); a hidden node on a curve is waste.
            if hidden && !ll {
                push("R6", c, Some(node), format!("hidden node touches a curve (turn {turn:.2})"));
            }
        }
        // R4: curves only where the silhouette curves.
        for (si, s) in segs.iter().enumerate() {
            if s.kind != SegKind::Curve {
                continue;
            }
            let (p0, p1) = (s.p0, s.p1);
            let (vx, vy) = (p1.0 - p0.0, p1.1 - p0.1);
            let len = vx.hypot(vy).max(1e-9);
            let dev = |q: Pt| ((q.0 - p0.0) * vy - (q.1 - p0.1) * vx).abs() / len;
            let d = dev(s.c1.unwrap()).max(dev(s.c2.unwrap()));
            if d <= p.grid {
                push("R4", c, Some(p0), format!("curve segment {si} is straight within the drawing's own rounding ({d:.3} <= {:.3})", p.grid));
            }
        }
    }
    // R6: no hidden curves.
    for (ci, si) in hidden_curve_segments(g) {
        push("R6", &g.contours[ci], None, format!("hidden curve segment {si}"));
    }
    Report { params: p, violations: v, roles, economy: economy(g) }
}

#[derive(Debug, Clone)]
pub struct Gate {
    pub iou: f64,
    /// IoU of the expected outline against itself with the sampling grid
    /// shifted by the drawing's own rounding error (`grid`): how much the
    /// silhouette may move if every coordinate is off by its own rounding.
    pub noise_iou: f64,
    pub union_px: usize,
    pub miss_px: usize,
    pub excess_px: usize,
    pub pass: bool,
}

/// R7: master silhouette versus the intended export outline. `expected`
/// polygons are filled with summed nonzero winding (holes subtract).
/// Pixel size = the coordinate pitch; the sampling shift for the noise
/// measurement is the rounding error (grid) itself, i.e. half a pixel. The
/// pass threshold is that measured noise IoU, not a fixed number.
pub fn silhouette_gate(master: &MasterGlyph, expected: &[Vec<Pt>]) -> Result<Gate, ValidateError> {
    silhouette_gate_with(master, expected, Params::derive(master)?)
}

pub fn silhouette_gate_with(master: &MasterGlyph, expected: &[Vec<Pt>], p: Params) -> Result<Gate, ValidateError> {
    let px = 2.0 * p.grid;
    let mp = polygons(master);
    let b = bounds_of(&[&mp, expected], px);
    let pixels = (((b.2 - b.0) / px).ceil().max(0.0) as u128) * (((b.3 - b.1) / px).ceil().max(0.0) as u128);
    if pixels > MAX_RASTER_PIXELS as u128 {
        return Err(ValidateError::PixelBudget { pixels, limit: MAX_RASTER_PIXELS });
    }
    let shift = p.grid / px;
    let (_, _, a) = rasterize(&mp, false, b, px, (0.5, 0.5));
    let (_, _, e) = rasterize(expected, true, b, px, (0.5, 0.5));
    let (_, _, e2) = rasterize(expected, true, b, px, (0.5 + shift, 0.5 + shift));
    let (iou, union_px, miss_px, excess_px) = paired_iou(&a, &e);
    let (noise_iou, ..) = paired_iou(&e, &e2);
    Ok(Gate { iou, noise_iou, union_px, miss_px, excess_px, pass: iou >= noise_iou })
}
