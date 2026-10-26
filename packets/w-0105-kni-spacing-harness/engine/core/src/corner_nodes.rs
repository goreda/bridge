//! corner_nodes: explicit corner-node outline representation (C3).
//!
//! General machinery only: the module carries no style name and no metric
//! number. It rewrites no geometry and drops no glyph, ring or pair.
//!
//! The problem: in the engine's single-node outline model
//! (`reference_slice::ReferenceRing`) every node joins one incoming span to
//! one outgoing span. Where the two tangents meet G1-smooth, one node is the
//! right representation. Where they do not - a corner - the tangent break
//! lives implicitly inside the shared node: nothing in the node list says a
//! G1 break is there, and nothing separates an intended corner from an
//! accidental break. Reading G1 breaks out of the outline becomes
//! impossible without re-deriving tangents at every node.
//!
//! The representation here splits every corner into a pair of explicit
//! corner nodes: an exit node (the incoming span's last point) and an entry
//! node (the outgoing span's first point), joined by a typed `CornerLink`
//! that carries the measured turn and the smooth floor it was classified
//! against. Coordinates stay coincident, so the drawn geometry is unchanged;
//! what changes is that a G1 break can now live only on a `CornerLink`,
//! never hidden inside a single node. A tangent break found on an ordinary
//! (non-link) joint in the explicit form is an undeclared break and surfaces
//! as a typed issue from `verify_explicit_ring`.
//!
//! Smooth floor derivation (declared, no free constants): the caller passes
//! the encoding `grid` the outline will be quantized to (the engine's CFF
//! export rounds to integers, so the export grid is 1.0 font unit). A node
//! and the point defining one of its tangents each carry at most grid/2 of
//! quantization error per axis; their difference vector therefore carries at
//! most one full grid of lateral error, over the tangent leg length. A turn
//! no larger than atan(grid/leg) on each side is indistinguishable from
//! quantization noise and is classified smooth. The joint floor is the sum
//! of the incoming and outgoing floors. A joint whose tangent leg is zero
//! after every fallback is a zero tangent: it is never auto-classified, it
//! is reported.
//!
//! Additive module: no production path calls it, so every existing style
//! and pair remains bit-identical while it is unwired. `collapse_ring` is
//! the exact inverse of `split_ring` for geometry-preserving rings, which is
//! the byte-identity proof of the representation.

use crate::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

/// One explicit corner link: the typed home of a G1 break between the exit
/// node and the entry node of one split corner.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CornerLink {
    /// Measured tangent turn at the original single node, degrees.
    pub turn_deg: f64,
    /// Smooth floor the turn was classified against, degrees.
    pub floor_deg: f64,
}

/// Connector leaving one explicit node: an ordinary geometry span, or a
/// corner link with no geometry of its own.
#[derive(Clone, Debug)]
pub enum Connector {
    Geometry(Span),
    CornerLink(CornerLink),
}

/// Corner-explicit ring: nodes in ring order, one connector leaving each
/// node (connector i runs from node i to node (i+1) % len). Corners appear
/// as adjacent exit/entry node pairs joined by a `Connector::CornerLink`.
#[derive(Clone, Debug)]
pub struct CornerExplicitRing {
    pub nodes: Vec<Point>,
    pub connectors: Vec<Connector>,
}

/// Corner-explicit glyph: drawn geometry only, same contract as DrawnGlyph.
#[derive(Clone, Debug)]
pub struct CornerExplicitGlyph {
    pub glyph_id: String,
    pub rings: Vec<CornerExplicitRing>,
}

/// Joint classification of one single-node ring joint.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum JointClass {
    /// Turn at or below the quantization-derived smooth floor.
    Smooth,
    /// Turn above the floor: a real tangent break, split candidate.
    Corner,
    /// A tangent leg degenerated to zero length: unclassifiable, reported.
    ZeroTangent,
}

/// Measured observation of one joint of a single-node ring.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct JointObservation {
    pub node_index: usize,
    pub turn_deg: f64,
    pub floor_deg: f64,
    pub class: JointClass,
}

/// Typed failure of the split/collapse transforms.
#[derive(Clone, Debug, PartialEq)]
pub enum CornerSplitError {
    /// Input ring is not closed: final span end differs from the start.
    OpenContour,
    /// Collapse of a corner link whose exit and entry nodes diverged: the
    /// explicit ring no longer describes the original geometry.
    DivergedCornerLink { node_index: usize },
    /// A geometry connector's recorded end differs from the next node.
    ConnectorEndMismatch { node_index: usize },
    /// Two corner links in a row: malformed explicit ring.
    AdjacentCornerLinks { node_index: usize },
}

/// Typed issue from verifying an explicit ring.
#[derive(Clone, Debug, PartialEq)]
pub enum ExplicitIssue {
    /// A G1 break measured on an ordinary joint: the break is not declared
    /// on any corner link, so it is hidden exactly the way C3 removes.
    UndeclaredBreak { node_index: usize, turn_deg: f64, floor_deg: f64 },
    DivergedCornerLink { node_index: usize },
    AdjacentCornerLinks { node_index: usize },
    ConnectorEndMismatch { node_index: usize },
    ZeroTangent { node_index: usize },
}

/// Before/after counts of the representation change, per glyph or per set.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct CornerSplitStats {
    pub rings: usize,
    pub nodes_before: usize,
    pub nodes_after: usize,
    /// Explicit corner pairs after splitting (one link = one pair).
    pub corner_pairs: usize,
    /// Joints whose G1 break was hidden inside a single node before.
    pub hidden_breaks_before: usize,
    /// Undeclared breaks remaining in the explicit form after splitting.
    pub residual_breaks_after: usize,
    pub zero_tangents: usize,
}

fn sub(a: Point, b: Point) -> Point {
    Point { x: a.x - b.x, y: a.y - b.y }
}

fn norm(v: Point) -> f64 {
    v.x.hypot(v.y)
}

/// Tangent leaving the start of a span, with degenerate-control fallbacks;
/// the leg length is the distance to the point that defined the direction.
fn start_tangent(start: Point, span: &Span) -> Option<(Point, f64)> {
    let candidates: &[Point] = match span {
        Span::Line { end } => &[*end],
        Span::Cubic { control_one, control_two, end } => &[*control_one, *control_two, *end],
    };
    for c in candidates {
        let v = sub(*c, start);
        let leg = norm(v);
        if leg > 0.0 {
            return Some((v, leg));
        }
    }
    None
}

/// Tangent arriving at the end of a span, same fallback order in reverse.
/// `start` is the span's own start point, the final fallback for a line.
fn end_tangent(start: Point, span: &Span) -> Option<(Point, f64)> {
    let end = match span {
        Span::Line { end } => *end,
        Span::Cubic { end, .. } => *end,
    };
    let candidates: &[Point] = match span {
        Span::Line { .. } => &[start],
        Span::Cubic { control_one, control_two, .. } => &[*control_two, *control_one, start],
    };
    for c in candidates {
        let v = sub(end, *c);
        let leg = norm(v);
        if leg > 0.0 {
            return Some((v, leg));
        }
    }
    None
}

/// Turn between an incoming and an outgoing tangent, degrees in [0, 180].
/// Both legs are nonzero by construction of the tangent helpers.
fn turn_deg(incoming: Point, outgoing: Point) -> f64 {
    let cross = incoming.x * outgoing.y - incoming.y * outgoing.x;
    let dot = incoming.x * outgoing.x + incoming.y * outgoing.y;
    cross.atan2(dot).abs().to_degrees()
}

/// Smooth floor for one tangent, degrees: atan(grid / leg) per the declared
/// derivation in the module header.
fn tangent_floor_deg(leg: f64, grid: f64) -> f64 {
    (grid / leg).atan().to_degrees()
}

fn ring_nodes(ring: &ReferenceRing) -> Vec<Point> {
    let mut nodes = Vec::with_capacity(ring.spans.len());
    nodes.push(ring.start);
    for span in &ring.spans {
        nodes.push(match span {
            Span::Line { end } => *end,
            Span::Cubic { end, .. } => *end,
        });
    }
    nodes.pop(); // final end duplicates the closure start
    nodes
}

/// Measure every joint of a closed single-node ring. An open ring yields no
/// observations: closure is the caller's contract, checked by `split_ring`.
pub fn observe_joints(ring: &ReferenceRing, grid: f64) -> Vec<JointObservation> {
    let nodes = ring_nodes(ring);
    let m = nodes.len();
    if m == 0 || ring.spans.len() != m || !grid.is_finite() || grid <= 0.0 {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(m);
    for i in 0..m {
        let incoming = end_tangent(nodes[(i + m - 1) % m], &ring.spans[(i + m - 1) % m]);
        let outgoing = start_tangent(nodes[i], &ring.spans[i]);
        match (incoming, outgoing) {
            (Some((ti, li)), Some((to, lo))) => {
                let floor = tangent_floor_deg(li, grid) + tangent_floor_deg(lo, grid);
                let turn = turn_deg(ti, to);
                out.push(JointObservation {
                    node_index: i,
                    turn_deg: turn,
                    floor_deg: floor,
                    class: if turn > floor { JointClass::Corner } else { JointClass::Smooth },
                });
            }
            _ => out.push(JointObservation {
                node_index: i,
                turn_deg: 0.0,
                floor_deg: 0.0,
                class: JointClass::ZeroTangent,
            }),
        }
    }
    out
}

/// Split every corner joint of a closed ring into an explicit exit/entry
/// node pair joined by a typed corner link. Geometry is preserved: the pair
/// is coincident and no span is touched.
pub fn split_ring(ring: &ReferenceRing, grid: f64) -> Result<CornerExplicitRing, CornerSplitError> {
    let nodes = ring_nodes(ring);
    let m = nodes.len();
    if m == 0 {
        if ring.spans.is_empty() {
            return Ok(CornerExplicitRing { nodes: Vec::new(), connectors: Vec::new() });
        }
        return Err(CornerSplitError::OpenContour);
    }
    if ring.spans.len() != m {
        return Err(CornerSplitError::OpenContour);
    }
    let closed_end = match ring.spans.last() {
        Some(Span::Line { end }) => *end,
        Some(Span::Cubic { end, .. }) => *end,
        None => return Err(CornerSplitError::OpenContour),
    };
    if closed_end != ring.start {
        return Err(CornerSplitError::OpenContour);
    }
    let joints = observe_joints(ring, grid);
    let mut out_nodes = Vec::with_capacity(m);
    let mut out_connectors = Vec::with_capacity(m);
    for i in 0..m {
        let span = ring.spans[i].clone();
        match joints[i].class {
            JointClass::Corner => {
                out_nodes.push(nodes[i]); // exit node of the corner
                out_connectors.push(Connector::CornerLink(CornerLink {
                    turn_deg: joints[i].turn_deg,
                    floor_deg: joints[i].floor_deg,
                }));
                out_nodes.push(nodes[i]); // entry node of the corner
                out_connectors.push(Connector::Geometry(span));
            }
            _ => {
                out_nodes.push(nodes[i]);
                out_connectors.push(Connector::Geometry(span));
            }
        }
    }
    Ok(CornerExplicitRing { nodes: out_nodes, connectors: out_connectors })
}

/// Exact inverse of `split_ring` for geometry-preserving explicit rings:
/// every corner link must join coincident exit/entry nodes. This is the
/// byte-identity property of the representation, asserted in tests against
/// real fitted output.
pub fn collapse_ring(ring: &CornerExplicitRing) -> Result<ReferenceRing, CornerSplitError> {
    let n = ring.nodes.len();
    if n == 0 {
        if ring.connectors.is_empty() {
            return Ok(ReferenceRing { start: Point { x: 0.0, y: 0.0 }, spans: Vec::new() });
        }
        return Err(CornerSplitError::ConnectorEndMismatch { node_index: 0 });
    }
    if ring.connectors.len() != n {
        return Err(CornerSplitError::ConnectorEndMismatch { node_index: n - 1 });
    }
    let start = ring.nodes[0];
    let mut spans = Vec::with_capacity(n);
    for i in 0..n {
        let next = ring.nodes[(i + 1) % n];
        match &ring.connectors[i] {
            Connector::Geometry(span) => {
                let end = match span {
                    Span::Line { end } => *end,
                    Span::Cubic { end, .. } => *end,
                };
                if end != next {
                    return Err(CornerSplitError::ConnectorEndMismatch { node_index: i });
                }
                spans.push(span.clone());
            }
            Connector::CornerLink(_) => {
                if matches!(ring.connectors[(i + n - 1) % n], Connector::CornerLink(_)) {
                    return Err(CornerSplitError::AdjacentCornerLinks { node_index: i });
                }
                if ring.nodes[i] != next {
                    return Err(CornerSplitError::DivergedCornerLink { node_index: i });
                }
                // Coincident exit/entry pair: the link carries no geometry,
                // the collapse merges the pair back into one node.
            }
        }
    }
    Ok(ReferenceRing { start, spans })
}

/// Verify the explicit-form contract: no hidden break on an ordinary joint,
/// every corner link coincident, every connector end consistent.
pub fn verify_explicit_ring(ring: &CornerExplicitRing, grid: f64) -> Vec<ExplicitIssue> {
    let n = ring.nodes.len();
    let mut issues = Vec::new();
    if n == 0 || ring.connectors.len() != n || !grid.is_finite() || grid <= 0.0 {
        if n != ring.connectors.len() {
            issues.push(ExplicitIssue::ConnectorEndMismatch { node_index: 0 });
        }
        return issues;
    }
    for i in 0..n {
        let next = ring.nodes[(i + 1) % n];
        match &ring.connectors[i] {
            Connector::Geometry(span) => {
                let end = match span {
                    Span::Line { end } => *end,
                    Span::Cubic { end, .. } => *end,
                };
                if end != next {
                    issues.push(ExplicitIssue::ConnectorEndMismatch { node_index: i });
                }
            }
            Connector::CornerLink(_) => {
                if matches!(ring.connectors[(i + n - 1) % n], Connector::CornerLink(_)) {
                    issues.push(ExplicitIssue::AdjacentCornerLinks { node_index: i });
                }
                if ring.nodes[i] != next {
                    issues.push(ExplicitIssue::DivergedCornerLink { node_index: i });
                }
            }
        }
        // A G1 break may live only on a corner link. Measure the joints that
        // are not one: geometry-into-geometry transitions.
        let incoming = &ring.connectors[(i + n - 1) % n];
        let outgoing = &ring.connectors[i];
        if let (Connector::Geometry(si), Connector::Geometry(so)) = (incoming, outgoing) {
            let prev_node = ring.nodes[(i + n - 1) % n];
            match (end_tangent(prev_node, si), start_tangent(ring.nodes[i], so)) {
                (Some((ti, li)), Some((to, lo))) => {
                    let floor = tangent_floor_deg(li, grid) + tangent_floor_deg(lo, grid);
                    let turn = turn_deg(ti, to);
                    if turn > floor {
                        issues.push(ExplicitIssue::UndeclaredBreak { node_index: i, turn_deg: turn, floor_deg: floor });
                    }
                }
                _ => issues.push(ExplicitIssue::ZeroTangent { node_index: i }),
            }
        }
    }
    issues
}

/// Split every ring of a drawn glyph. Empty rings stay empty: the glyph,
/// ring and pair population is never changed by the representation.
pub fn split_glyph(glyph: &DrawnGlyph, grid: f64) -> Result<CornerExplicitGlyph, CornerSplitError> {
    let mut rings = Vec::with_capacity(glyph.rings.len());
    for ring in &glyph.rings {
        rings.push(split_ring(ring, grid)?);
    }
    Ok(CornerExplicitGlyph { glyph_id: glyph.glyph_id.clone(), rings })
}

/// Collapse every ring of an explicit glyph back to single-node form.
pub fn collapse_glyph(glyph: &CornerExplicitGlyph) -> Result<DrawnGlyph, CornerSplitError> {
    let mut rings = Vec::with_capacity(glyph.rings.len());
    for ring in &glyph.rings {
        rings.push(collapse_ring(ring)?);
    }
    Ok(DrawnGlyph { glyph_id: glyph.glyph_id.clone(), rings })
}

/// Before/after counts for one glyph: hidden breaks in the single-node form
/// vs explicit corner pairs and residual undeclared breaks after splitting.
pub fn glyph_stats(before: &DrawnGlyph, after: &CornerExplicitGlyph, grid: f64) -> CornerSplitStats {
    let mut stats = CornerSplitStats::default();
    for ring in &before.rings {
        stats.rings += 1;
        let nodes = ring_nodes(ring).len();
        stats.nodes_before += nodes;
        for joint in observe_joints(ring, grid) {
            match joint.class {
                JointClass::Corner => stats.hidden_breaks_before += 1,
                JointClass::ZeroTangent => stats.zero_tangents += 1,
                JointClass::Smooth => {}
            }
        }
    }
    for ring in &after.rings {
        stats.nodes_after += ring.nodes.len();
        stats.corner_pairs += ring
            .connectors
            .iter()
            .filter(|c| matches!(c, Connector::CornerLink(_)))
            .count();
        for issue in verify_explicit_ring(ring, grid) {
            if let ExplicitIssue::UndeclaredBreak { .. } = issue {
                stats.residual_breaks_after += 1;
            }
        }
    }
    stats
}

/// Deterministic one-row-per-glyph report of the representation change.
pub fn render_report(rows: &[(String, CornerSplitStats)]) -> String {
    let mut out = String::from(
        "glyph | rings | nodes_before | nodes_after | corner_pairs | hidden_g1_breaks_before | residual_breaks_after | zero_tangents",
    );
    for (glyph_id, s) in rows {
        out.push_str(&format!(
            "\n{} | {} | {} | {} | {} | {} | {} | {}",
            glyph_id, s.rings, s.nodes_before, s.nodes_after, s.corner_pairs,
            s.hidden_breaks_before, s.residual_breaks_after, s.zero_tangents
        ));
    }
    out
}
