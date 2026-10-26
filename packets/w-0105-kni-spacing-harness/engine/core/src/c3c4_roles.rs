//! C3/C4 production measurement: axis/alignment (C3) and join/tangency (C4).
//!
//! Definition v0.1: derived from the reference library;
//! NOT validated. Measurement rows only: no enforcement, no gate, no intent
//! inference. Every report carries its noise record (measured|declared, with
//! derivation) and the input-path label. Tolerances are derived from the
//! glyph's own noise record; the decision multiplier is CONVENTION.
//!
//! Raw formulas mirror the diagnostic formulas used in the collection
//! measurement tooling exactly: C3 deviation = atan2(min(|dx|,|dy|), max(|dx|,|dy|))
//! against the nearest axis; C4 join = atan2(|cross(u,v)|, dot(u,v)) on the
//! endpoint tangent vectors.

use crate::reference_slice::{Point, ReferenceRing, Span};

/// CONVENTION: 3-sigma decision multiplier (a convention, not a measurement).
pub const CONVENTION_SIGMA_MULTIPLIER: f64 = 3.0;
/// CONVENTION: axis window used only inside measure_noise to decide which
/// straight segments count as axis-aligned (~1 degree, relative form).
pub const CONVENTION_AXIS_WINDOW_REL: f64 = 0.02;
/// Declared floor: integer-coordinate quantisation sigma (1/sqrt(12)).
pub fn quantization_sigma() -> f64 { 1.0 / (12.0_f64).sqrt() }

#[derive(Clone, Debug, PartialEq)]
pub enum NoiseOrigin { Measured, Declared }

#[derive(Clone, Debug)]
pub struct NoiseRecord {
    pub sigma: f64,
    pub origin: NoiseOrigin,
    pub derivation: String,
}

impl NoiseRecord {
    /// sigma_eff = sqrt(sigma^2 + Q^2), Q = declared quantisation floor.
    pub fn effective_sigma(&self) -> f64 {
        (self.sigma * self.sigma + quantization_sigma().powi(2)).sqrt()
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum InputPath { Vector, Image }
impl InputPath {
    pub fn label(&self) -> &'static str {
        match self { Self::Vector => "vector", Self::Image => "image" }
    }
}

fn vec_of(a: Point, b: Point) -> (f64, f64) { (b.x - a.x, b.y - a.y) }
fn norm(v: (f64, f64)) -> f64 { (v.0 * v.0 + v.1 * v.1).sqrt() }
/// End point of a span (reference_slice::Span::end is crate-private).
fn span_end(span: &Span) -> Point {
    match span { Span::Line { end } | Span::Cubic { end, .. } => *end }
}

/// Measured noise: RMS endpoint mismatch of axis-aligned straight segments,
/// divided by sqrt(2). If there are no axis-aligned straight segments, the
/// sigma is declared 0 and only the quantisation floor applies.
/// Every qualifying segment counts; the qualifying window is
/// CONVENTION_AXIS_WINDOW_REL (a minimum segment length cutoff is deliberately
/// not used: it would be a font-external number).
pub fn measure_noise(rings: &[ReferenceRing]) -> NoiseRecord {
    let mut residuals: Vec<f64> = Vec::new();
    for ring in rings {
        let mut cur = ring.start;
        for span in &ring.spans {
            if let Span::Line { end } = span {
                let d = vec_of(cur, *end);
                let len = norm(d);
                if len > 0.0 {
                    if d.1.abs() < CONVENTION_AXIS_WINDOW_REL * len { residuals.push(d.1); }
                    if d.0.abs() < CONVENTION_AXIS_WINDOW_REL * len { residuals.push(d.0); }
                }
            }
            cur = span_end(span);
        }
    }
    if residuals.is_empty() {
        NoiseRecord {
            sigma: 0.0,
            origin: NoiseOrigin::Declared,
            derivation: "no axis-aligned straight segments to measure; declared 0 + quantisation floor".into(),
        }
    } else {
        let mean_sq = residuals.iter().map(|r| r * r).sum::<f64>() / residuals.len() as f64;
        NoiseRecord {
            sigma: (mean_sq / 2.0).sqrt(),
            origin: NoiseOrigin::Measured,
            derivation: format!(
                "RMS endpoint mismatch of {} axis-aligned straight-segment residuals / sqrt2 (window CONVENTION_AXIS_WINDOW_REL)",
                residuals.len()),
        }
    }
}

/// Angular tolerance for one measured direction of length L:
/// single-vector angular noise = sqrt(2) * sigma_eff / L, times the
/// CONVENTION multiplier, bounded by atan.
fn axis_tolerance(sigma_eff: f64, len: f64) -> f64 {
    CONVENTION_SIGMA_MULTIPLIER * (2.0_f64.sqrt() * sigma_eff / len).atan()
}

/// Angular tolerance for a join of two tangents of lengths lin/lout:
/// two-vector angular noise = sqrt(2) * sigma_eff * sqrt(1/lin^2 + 1/lout^2),
/// times the CONVENTION multiplier, bounded by atan.
fn join_tolerance(sigma_eff: f64, lin: f64, lout: f64) -> f64 {
    CONVENTION_SIGMA_MULTIPLIER
        * (2.0_f64.sqrt() * sigma_eff * (1.0 / (lin * lin) + 1.0 / (lout * lout)).sqrt()).atan()
}

#[derive(Clone, Debug, PartialEq)]
pub enum AxisClass { Aligned, Deviant, Abstain(String) }

#[derive(Clone, Debug)]
pub struct C3Element {
    pub ring: usize,
    pub span: usize,
    /// 0 = line direction or cubic out-handle at span start; 1 = cubic in-handle at span end.
    pub which: u8,
    pub deviation_rad: Option<f64>,
    pub tolerance_rad: Option<f64>,
    pub class: AxisClass,
}

#[derive(Clone, Debug)]
pub struct C3Report {
    pub path: String,
    pub noise: NoiseRecord,
    pub conventions: Vec<String>,
    pub elements: Vec<C3Element>,
    pub aligned: usize,
    pub deviant: usize,
    pub abstain: usize,
}

/// C3 axis/alignment measurement. Raw deviation formula:
/// atan2(min(|dx|,|dy|), max(|dx|,|dy|)) against the nearest axis.
pub fn c3_measure(rings: &[ReferenceRing], noise: &NoiseRecord, path: InputPath) -> C3Report {
    let sig = noise.effective_sigma();
    let mut elements = Vec::new();
    for (ri, ring) in rings.iter().enumerate() {
        let mut cur = ring.start;
        for (si, span) in ring.spans.iter().enumerate() {
            let mut push = |which: u8, v: (f64, f64)| {
                let len = norm(v);
                if len == 0.0 {
                    elements.push(C3Element {
                        ring: ri, span: si, which,
                        deviation_rad: None, tolerance_rad: None,
                        class: AxisClass::Abstain("zero-length direction has no angle".into()),
                    });
                } else {
                    let dev = (v.0.abs().min(v.1.abs())).atan2(v.0.abs().max(v.1.abs()));
                    let tol = axis_tolerance(sig, len);
                    let class = if dev <= tol { AxisClass::Aligned } else { AxisClass::Deviant };
                    elements.push(C3Element {
                        ring: ri, span: si, which,
                        deviation_rad: Some(dev), tolerance_rad: Some(tol), class,
                    });
                }
            };
            match span {
                Span::Line { end } => push(0, vec_of(cur, *end)),
                Span::Cubic { control_one, control_two, end } => {
                    push(0, vec_of(cur, *control_one));
                    push(1, vec_of(*control_two, *end));
                }
            }
            cur = span_end(span);
        }
    }
    let aligned = elements.iter().filter(|e| e.class == AxisClass::Aligned).count();
    let deviant = elements.iter().filter(|e| e.class == AxisClass::Deviant).count();
    let abstain = elements.len() - aligned - deviant;
    C3Report {
        path: path.label().into(),
        noise: noise.clone(),
        conventions: vec![
            "CONVENTION_SIGMA_MULTIPLIER = 3 (decision multiplier, not a measurement)".into(),
        ],
        elements, aligned, deviant, abstain,
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum JoinClass { Smooth, Corner, Abstain(String) }

#[derive(Clone, Debug)]
pub struct C4Node {
    pub ring: usize,
    /// Index of the span whose start is this node.
    pub node: usize,
    pub join_rad: Option<f64>,
    pub tolerance_rad: Option<f64>,
    pub class: JoinClass,
}

#[derive(Clone, Debug)]
pub struct C4Report {
    pub path: String,
    pub noise: NoiseRecord,
    pub conventions: Vec<String>,
    pub nodes: Vec<C4Node>,
    pub smooth: usize,
    pub corner: usize,
    pub abstain: usize,
}

/// Incoming tangent at the end of a span (line = start->end,
/// cubic = control_two->end).
fn in_tangent(start: Point, span: &Span) -> (f64, f64) {
    match span {
        Span::Line { end } => vec_of(start, *end),
        Span::Cubic { control_two, end, .. } => vec_of(*control_two, *end),
    }
}
/// Outgoing tangent at the start of a span (line = start->end,
/// cubic = start->control_one).
fn out_tangent(start: Point, span: &Span) -> (f64, f64) {
    match span {
        Span::Line { end } => vec_of(start, *end),
        Span::Cubic { control_one, .. } => vec_of(start, *control_one),
    }
}

/// C4 join/tangency measurement at every node (span start). Raw formula:
/// atan2(|cross(u,v)|, dot(u,v)); u = incoming tangent of the previous span,
/// v = outgoing tangent of this span. A zero-length tangent abstains.
/// Closed rings wrap; the implicit closing geometry is the caller's spans.
pub fn c4_measure(rings: &[ReferenceRing], noise: &NoiseRecord, path: InputPath) -> C4Report {
    let sig = noise.effective_sigma();
    let mut nodes = Vec::new();
    for (ri, ring) in rings.iter().enumerate() {
        let n = ring.spans.len();
        if n == 0 { continue; }
        let mut starts = Vec::with_capacity(n);
        let mut cur = ring.start;
        for span in &ring.spans { starts.push(cur); cur = span_end(span); }
        for i in 0..n {
            let u = in_tangent(starts[(i + n - 1) % n], &ring.spans[(i + n - 1) % n]);
            let v = out_tangent(starts[i], &ring.spans[i]);
            let (lu, lv) = (norm(u), norm(v));
            if lu == 0.0 || lv == 0.0 {
                nodes.push(C4Node {
                    ring: ri, node: i,
                    join_rad: None, tolerance_rad: None,
                    class: JoinClass::Abstain("zero-length tangent at join has no angle".into()),
                });
            } else {
                let join = (u.0 * v.1 - u.1 * v.0).abs().atan2(u.0 * v.0 + u.1 * v.1);
                let tol = join_tolerance(sig, lu, lv);
                let class = if join <= tol { JoinClass::Smooth } else { JoinClass::Corner };
                nodes.push(C4Node {
                    ring: ri, node: i,
                    join_rad: Some(join), tolerance_rad: Some(tol), class,
                });
            }
        }
    }
    let smooth = nodes.iter().filter(|e| e.class == JoinClass::Smooth).count();
    let corner = nodes.iter().filter(|e| e.class == JoinClass::Corner).count();
    let abstain = nodes.len() - smooth - corner;
    C4Report {
        path: path.label().into(),
        noise: noise.clone(),
        conventions: vec![
            "CONVENTION_SIGMA_MULTIPLIER = 3 (decision multiplier, not a measurement)".into(),
        ],
        nodes, smooth, corner, abstain,
    }
}
