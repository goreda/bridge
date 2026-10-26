//! C3 corner wiring: seam-joint corner emission vs tangent continuity.
//!
//! Policy-gated by the manifest (`corner_wiring on|off`, default off) and
//! called from the stage-1 emission path on the SHIPPED rings only. When a
//! seam joint's measured tangent-angle delta exceeds the export grid's own
//! resolvability floor, the joint is a genuine corner and keeps its tangent
//! break (corner node). Below the floor the break is not resolvable on the
//! export grid, so the joint is made tangent-continuous (G1) by rotating the
//! inner handles onto the mean tangent, preserving handle lengths.
//!
//! Threshold (chief ruling, no free parameters): per joint
//!   floor = atan(ER/2 / L_in) + atan(ER/2 / L_out)
//! with ER = generated_native::EXPORT_RESOLUTION and L_in/L_out the neighbour
//! span chord lengths in export units.
//!
//! Guards (any failure leaves the seam untouched and counted):
//!  - non-finite or degenerate tangents / lengths -> abstain
//!  - line-line seams cannot be smoothed without moving nodes -> abstain
//!  - a handle rotation that moves any control point by more than ER/2
//!    (sub-resolvable on the export grid) is rejected, original kept.

use crate::generated_native::EXPORT_RESOLUTION;
use crate::reference_slice::{Point, ReferenceRing, Span};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SeamKind { CubicCubic, CubicLine, LineCubic, LineLine }
impl SeamKind {
    pub fn tag(self) -> &'static str {
        match self { Self::CubicCubic => "cc", Self::CubicLine => "cl", Self::LineCubic => "lc", Self::LineLine => "ll" }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SeamAction { Corner, Smoothed, Abstained, GuardRejected }
impl SeamAction {
    pub fn tag(self) -> &'static str {
        match self { Self::Corner => "corner", Self::Smoothed => "smooth", Self::Abstained => "abstain", Self::GuardRejected => "guard_reject" }
    }
}

#[derive(Clone, Debug)]
pub struct SeamReport {
    pub ring: usize,
    pub seam: usize,
    pub kind: SeamKind,
    pub delta_deg: f64,
    pub floor_deg: f64,
    pub l_in: f64,
    pub l_out: f64,
    pub action: SeamAction,
}

#[derive(Clone, Debug, Default)]
pub struct WiringTotals {
    pub seams: usize,
    pub corners: usize,
    pub smoothed: usize,
    pub abstained: usize,
    pub guard_rejected: usize,
}

fn sub(a: Point, b: Point) -> Point { Point { x: a.x - b.x, y: a.y - b.y } }
fn unit(v: Point) -> Option<Point> {
    let n = v.x.hypot(v.y);
    if !n.is_finite() || n == 0.0 { return None; }
    let u = Point { x: v.x / n, y: v.y / n };
    if u.x.is_finite() && u.y.is_finite() { Some(u) } else { None }
}
fn span_end(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn span_chord(start: Point, s: &Span) -> Point { sub(span_end(s), start) }
/// Outgoing tangent direction at the span's end (handle direction, chord
/// fallback for degenerate handles).
fn tangent_out(start: Point, s: &Span) -> Option<Point> {
    match s {
        Span::Line { .. } => unit(span_chord(start, s)),
        Span::Cubic { control_two, end, .. } => unit(sub(*end, *control_two)).or_else(|| unit(span_chord(start, s))),
    }
}
/// Incoming tangent direction at the span's start.
fn tangent_in(start: Point, s: &Span) -> Option<Point> {
    match s {
        Span::Line { .. } => unit(span_chord(start, s)),
        Span::Cubic { control_one, .. } => unit(sub(*control_one, start)).or_else(|| unit(span_chord(start, s))),
    }
}

/// Wire one ring's seam joints. Returns per-seam reports; the ring is
/// mutated only where a sub-floor seam was smoothed within the guard.
pub fn wire_ring(ring: &mut ReferenceRing) -> Vec<SeamReport> {
    let m = ring.spans.len();
    let mut reports = Vec::new();
    if m < 2 { return reports; }
    let er = EXPORT_RESOLUTION;
    // Seam j sits between span j and span (j+1) % m.
    for j in 0..m {
        let k = (j + 1) % m;
        // Start points are implicit: span 0 starts at ring.start, each later
        // span starts at the previous span's end.
        let (mut start_j, mut start_k) = (ring.start, ring.start);
        let mut p = ring.start;
        for (i, s) in ring.spans.iter().enumerate() {
            if i == j { start_j = p; }
            if i == k { start_k = p; }
            p = span_end(s);
        }
        let joint = span_end(&ring.spans[j]);
        let kind = match (&ring.spans[j], &ring.spans[k]) {
            (Span::Cubic { .. }, Span::Cubic { .. }) => SeamKind::CubicCubic,
            (Span::Cubic { .. }, Span::Line { .. }) => SeamKind::CubicLine,
            (Span::Line { .. }, Span::Cubic { .. }) => SeamKind::LineCubic,
            (Span::Line { .. }, Span::Line { .. }) => SeamKind::LineLine,
        };
        let t_out = tangent_out(start_j, &ring.spans[j]);
        let t_in = tangent_in(start_k, &ring.spans[k]);
        let chord_j = span_chord(start_j, &ring.spans[j]);
        let chord_k = span_chord(start_k, &ring.spans[k]);
        let l_in = chord_j.x.hypot(chord_j.y);
        let l_out = chord_k.x.hypot(chord_k.y);
        let base = SeamReport { ring: 0, seam: j, kind, delta_deg: f64::NAN, floor_deg: f64::NAN, l_in, l_out, action: SeamAction::Abstained };
        let (t_out, t_in) = match (t_out, t_in) {
            (Some(a), Some(b)) => (a, b),
            _ => { reports.push(base); continue; }
        };
        if !l_in.is_finite() || !l_out.is_finite() || l_in <= 0.0 || l_out <= 0.0 {
            reports.push(base); continue;
        }
        let cross = (t_out.x * t_in.y - t_out.y * t_in.x).abs();
        let dot = t_out.x * t_in.x + t_out.y * t_in.y;
        let delta = cross.atan2(dot);
        let floor = (er / 2.0 / l_in).atan() + (er / 2.0 / l_out).atan();
        let mut rep = SeamReport { delta_deg: delta.to_degrees(), floor_deg: floor.to_degrees(), ..base };
        if delta > floor {
            // Genuine, grid-resolvable corner: keep the tangent break.
            rep.action = SeamAction::Corner;
            reports.push(rep);
            continue;
        }
        // Below the floor: enforce tangent continuity. Mean tangent
        // direction; handle lengths preserved.
        let mean = match unit(Point { x: t_out.x + t_in.x, y: t_out.y + t_in.y }) {
            Some(u) => u,
            None => { reports.push(rep); continue; } // antiparallel: leave untouched
        };
        let mut moves: Vec<(usize, usize, Point)> = Vec::new(); // (span, handle 1|2, new point)
        match kind {
            SeamKind::LineLine => { reports.push(rep); continue; }
            SeamKind::CubicCubic => {
                if let Span::Cubic { control_two, .. } = ring.spans[j] {
                    let h = sub(joint, control_two);
                    let n = h.x.hypot(h.y);
                    if n > 0.0 { moves.push((j, 2, Point { x: joint.x - mean.x * n, y: joint.y - mean.y * n })); }
                }
                if let Span::Cubic { control_one, .. } = ring.spans[k] {
                    let h = sub(control_one, joint);
                    let n = h.x.hypot(h.y);
                    if n > 0.0 { moves.push((k, 1, Point { x: joint.x + mean.x * n, y: joint.y + mean.y * n })); }
                }
            }
            // Mixed seams: align the cubic's inner handle to the line's
            // fixed tangent; the line itself never moves.
            SeamKind::CubicLine => {
                if let Span::Cubic { control_two, .. } = ring.spans[j] {
                    let h = sub(joint, control_two);
                    let n = h.x.hypot(h.y);
                    if n > 0.0 { moves.push((j, 2, Point { x: joint.x - t_in.x * n, y: joint.y - t_in.y * n })); }
                }
            }
            SeamKind::LineCubic => {
                if let Span::Cubic { control_one, .. } = ring.spans[k] {
                    let h = sub(control_one, joint);
                    let n = h.x.hypot(h.y);
                    if n > 0.0 { moves.push((k, 1, Point { x: joint.x + t_out.x * n, y: joint.y + t_out.y * n })); }
                }
            }
        }
        // Guard: every control move must stay sub-resolvable (<= ER/2).
        let mut max_move = 0.0f64;
        for (si, hi, np) in &moves {
            let old = match (&ring.spans[*si], hi) {
                (Span::Cubic { control_one, .. }, 1) => *control_one,
                (Span::Cubic { control_two, .. }, 2) => *control_two,
                _ => continue,
            };
            let d = sub(*np, old);
            max_move = max_move.max(d.x.hypot(d.y));
        }
        if !max_move.is_finite() || max_move > er / 2.0 {
            rep.action = SeamAction::GuardRejected;
            reports.push(rep);
            continue;
        }
        for (si, hi, np) in moves {
            match (&mut ring.spans[si], hi) {
                (Span::Cubic { control_one, .. }, 1) => *control_one = np,
                (Span::Cubic { control_two, .. }, 2) => *control_two = np,
                _ => {}
            }
        }
        rep.action = SeamAction::Smoothed;
        reports.push(rep);
    }
    reports
}

/// Wire every ring of a shipped drawing. Returns per-seam reports (ring
/// indices filled in) and the run totals.
pub fn wire_drawing(rings: &mut [ReferenceRing]) -> (Vec<SeamReport>, WiringTotals) {
    let mut all = Vec::new();
    let mut totals = WiringTotals::default();
    for (ri, ring) in rings.iter_mut().enumerate() {
        for mut r in wire_ring(ring) {
            r.ring = ri;
            totals.seams += 1;
            match r.action {
                SeamAction::Corner => totals.corners += 1,
                SeamAction::Smoothed => totals.smoothed += 1,
                SeamAction::Abstained => totals.abstained += 1,
                SeamAction::GuardRejected => totals.guard_rejected += 1,
            }
            all.push(r);
        }
    }
    (all, totals)
}

pub fn seam_report_tsv(glyph: &str, r: &SeamReport) -> String {
    let f = |v: f64| if v.is_nan() { "na".to_string() } else { format!("{v:.6}") };
    format!("{glyph}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
        r.ring, r.seam, r.kind.tag(), f(r.delta_deg), f(r.floor_deg), f(r.l_in), f(r.l_out), r.action.tag())
}
