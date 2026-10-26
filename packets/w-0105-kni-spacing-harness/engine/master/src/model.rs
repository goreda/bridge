//! Master-mode outline data model.

/// One point in font units (y up).
pub type Pt = (f64, f64);

/// Contour operations, closed contours only in master mode.
#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    Move(Pt),
    Line(Pt),
    Curve(Pt, Pt, Pt),
    Close,
}

/// One structural stroke's contour (stem, bowl, leg, ...). The stroke name
/// is the contour's identity; strokes overlap freely.
#[derive(Debug, Clone, PartialEq)]
pub struct StrokeContour {
    pub stroke: String,
    pub ops: Vec<Op>,
}

/// A master glyph: named strokes, advance, upm.
#[derive(Debug, Clone)]
pub struct MasterGlyph {
    pub name: String,
    pub advance: f64,
    pub upm: f64,
    pub contours: Vec<StrokeContour>,
}

/// Segment view of one contour: (kind, start, c1, c2, end); the implicit
/// closing line (end != start) is materialized as a Line segment.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SegKind {
    Line,
    Curve,
}

#[derive(Debug, Clone, Copy)]
pub struct Seg {
    pub kind: SegKind,
    pub p0: Pt,
    pub c1: Option<Pt>,
    pub c2: Option<Pt>,
    pub p1: Pt,
}

impl StrokeContour {
    /// Materialize segments (implicit straight closure included when the
    /// last point differs from the start, per the v0.2 counting rule).
    pub fn segments(&self) -> Vec<Seg> {
        let mut segs = Vec::new();
        let mut cur: Option<Pt> = None;
        let mut start: Option<Pt> = None;
        for op in &self.ops {
            match op {
                Op::Move(p) => {
                    cur = Some(*p);
                    start = Some(*p);
                }
                Op::Line(p) => {
                    if let Some(p0) = cur {
                        segs.push(Seg { kind: SegKind::Line, p0, c1: None, c2: None, p1: *p });
                    }
                    cur = Some(*p);
                }
                Op::Curve(c1, c2, p) => {
                    if let Some(p0) = cur {
                        segs.push(Seg { kind: SegKind::Curve, p0, c1: Some(*c1), c2: Some(*c2), p1: *p });
                    }
                    cur = Some(*p);
                }
                Op::Close => {
                    if let (Some(p0), Some(s)) = (cur, start) {
                        let gap = (p0.0 - s.0).hypot(p0.1 - s.1);
                        if gap > 0.25 {
                            segs.push(Seg { kind: SegKind::Line, p0, c1: None, c2: None, p1: s });
                        }
                    }
                    cur = start;
                }
            }
        }
        segs
    }

    /// On-curve nodes (distinct points; the closing point is not double
    /// counted).
    pub fn nodes(&self) -> Vec<Pt> {
        self.segments().iter().map(|s| s.p0).collect()
    }

    /// Exact axis-aligned bbox: curve segments contribute their true
    /// interior extrema, not their control points. Derivation per axis:
    /// x(t) = at^3+bt^2+ct+d over t in [0,1]; interior extrema sit at the
    /// roots of 3at^2+2bt+c in the open interval. (Chief ruling 2026-10-18
    /// 20:24, item 10: the pair-gap floor measures true ink, not hull.)
    pub fn bbox_exact(&self) -> Option<(f64, f64, f64, f64)> {
        let mut bb: Option<(f64, f64, f64, f64)> = None;
        let eat = |bb: &mut Option<(f64, f64, f64, f64)>, x: f64, y: f64| {
            *bb = Some(match *bb {
                None => (x, y, x, y),
                Some((x0, y0, x1, y1)) => (x0.min(x), y0.min(y), x1.max(x), y1.max(y)),
            });
        };
        for s in self.segments() {
            eat(&mut bb, s.p0.0, s.p0.1);
            eat(&mut bb, s.p1.0, s.p1.1);
            if let (Some(c1), Some(c2)) = (s.c1, s.c2) {
                // Interior extrema per axis; the evaluated point keeps
                // both coordinates consistent (x and y at the same t).
                let mut ts = cubic_extremum_ts(s.p0.0, c1.0, c2.0, s.p1.0);
                ts.extend(cubic_extremum_ts(s.p0.1, c1.1, c2.1, s.p1.1));
                for t in ts {
                    eat(
                        &mut bb,
                        cubic_at(s.p0.0, c1.0, c2.0, s.p1.0, t),
                        cubic_at(s.p0.1, c1.1, c2.1, s.p1.1, t),
                    );
                }
            }
        }
        bb
    }

    /// Axis-aligned bbox over segments (curves contribute control points;
    /// checkers that need exact curve extrema refine this).
    pub fn bbox(&self) -> Option<(f64, f64, f64, f64)> {
        let mut bb: Option<(f64, f64, f64, f64)> = None;
        let mut eat = |p: Pt| {
            bb = Some(match bb {
                None => (p.0, p.1, p.0, p.1),
                Some((x0, y0, x1, y1)) => (x0.min(p.0), y0.min(p.1), x1.max(p.0), y1.max(p.1)),
            });
        };
        for s in self.segments() {
            eat(s.p0);
            eat(s.p1);
            if let Some(c1) = s.c1 {
                eat(c1);
            }
            if let Some(c2) = s.c2 {
                eat(c2);
            }
        }
        bb
    }
}

/// Turn angle at a joint in degrees: 0 = smooth continuation, 180 = full
/// reversal.
pub fn joint_turn(prev: &Seg, next: &Seg) -> f64 {
    let out = dir_out(prev);
    let inn = dir_in(next);
    let a1 = out.1.atan2(out.0);
    let a2 = inn.1.atan2(inn.0);
    let d = (a1 - a2).abs();
    let d = d.min(2.0 * std::f64::consts::PI - d);
    d.to_degrees()
}

pub fn dir_out(s: &Seg) -> Pt {
    match (s.c2, s.c1) {
        (Some(c2), _) if (s.p1.0 - c2.0).hypot(s.p1.1 - c2.1) > 1e-9 => (s.p1.0 - c2.0, s.p1.1 - c2.1),
        (_, Some(c1)) if (s.p1.0 - c1.0).hypot(s.p1.1 - c1.1) > 1e-9 => (s.p1.0 - c1.0, s.p1.1 - c1.1),
        _ => (s.p1.0 - s.p0.0, s.p1.1 - s.p0.1),
    }
}

pub fn dir_in(s: &Seg) -> Pt {
    match s.c1 {
        Some(c1) if (c1.0 - s.p0.0).hypot(c1.1 - s.p0.1) > 1e-9 => (c1.0 - s.p0.0, c1.1 - s.p0.1),
        _ => (s.p1.0 - s.p0.0, s.p1.1 - s.p0.1),
    }
}

fn cubic_at(p0: f64, c1: f64, c2: f64, p1: f64, t: f64) -> f64 {
    let u = 1.0 - t;
    u * u * u * p0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * p1
}

/// Roots of d/dt cubic in the open interval (0,1): 3at^2+2bt+c with
/// a=-p0+3c1-3c2+p1, b=3p0-6c1+3c2, c=-3p0+3c1. Degenerate (a~0) falls
/// back to the linear equation; double roots and out-of-range roots drop.
fn cubic_extremum_ts(p0: f64, c1: f64, c2: f64, p1: f64) -> Vec<f64> {
    let a = -p0 + 3.0 * c1 - 3.0 * c2 + p1;
    let b = 3.0 * p0 - 6.0 * c1 + 3.0 * c2;
    let c = -3.0 * p0 + 3.0 * c1;
    let (qa, qb, qc) = (3.0 * a, 2.0 * b, c);
    let mut out = Vec::new();
    if qa.abs() < 1e-12 {
        if qb.abs() >= 1e-12 {
            out.push(-qc / qb);
        }
    } else {
        let disc = qb * qb - 4.0 * qa * qc;
        if disc > 0.0 {
            let r = disc.sqrt();
            out.push((-qb + r) / (2.0 * qa));
            out.push((-qb - r) / (2.0 * qa));
        }
    }
    out.retain(|&t| t > 0.0 && t < 1.0);
    out
}
