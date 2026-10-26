//! Supplied-outline vertical slice, not raster tracing or an archived fitter.
//! Preserves supplied geometry and explicit closure; all execution NOT_RUN.
use crate::decision_evidence_envelope::PinClaim;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point { pub x: f64, pub y: f64 }

#[derive(Clone, Debug)]
pub enum Span {
    Line { end: Point },
    Cubic { control_one: Point, control_two: Point, end: Point },
}

impl Span {
    fn end(&self) -> Point {
        match self { Self::Line { end } | Self::Cubic { end, .. } => *end }
    }
    fn points(&self) -> Vec<Point> {
        match self {
            Self::Line { end } => vec![*end],
            Self::Cubic { control_one, control_two, end } => vec![*control_one, *control_two, *end],
        }
    }
}

/// Input closure requirement: final endpoint must equal the explicit start.
/// Public fields do not enforce it; preserve_reference validates actual geometry.
/// No implicit line, tolerance or normalization is inserted.
#[derive(Clone, Debug)]
pub struct ReferenceRing { pub start: Point, pub spans: Vec<Span> }

#[derive(Clone, Debug)]
pub struct ReferenceGlyph {
    pub glyph_id: String,
    pub source_pin: PinClaim,
    pub rings: Vec<ReferenceRing>,
    pub declared_junction_decision_required: bool,
}

#[derive(Clone, Debug)]
pub struct Bounds { pub minimum: Point, pub maximum: Point }

#[derive(Clone, Debug)]
pub struct RingMeasurement {
    pub ring_index: usize,
    pub endpoints: Vec<Point>,
    pub cubic_span_indices: Vec<usize>,
    pub control_hull_bounds: Bounds,
    /// Binary64 polygon shoelace observation only; absent for curves/overflow.
    pub polygon_signed_area: Option<f64>,
}

#[derive(Clone, Debug)]
pub struct ContainmentObservation {
    pub inner_ring: usize,
    pub outer_ring: usize,
    /// Opposite direction plus containment is an observation, not fill policy.
    pub opposite_winding: bool,
}

#[derive(Clone, Debug)]
pub enum InternalBoundary {
    JunctionDecisionUnresolved,
    CurvedRingContainmentUnresolved,
    ThicknessFlowMethodUnbound,
    ArchivedSolverMethodsUnbound,
    TouchingOrIntersectingRingsUnresolved,
    PolygonAreaNumericallyUnresolved,
    SingleRingTopologyUnresolved { ring_index: usize },
}

#[derive(Clone, Debug)]
pub enum GlyphImpossible { NoData, NonFiniteGeometry, OpenContour, DegenerateContour }

#[derive(Clone, Debug)]
pub struct MetricPass {
    pub pass_number: u8,
    pub control_hull_bounds: Bounds,
    pub ring_count: usize,
}

/// Drawn geometry only; diagnostics are kept in the separate internal run record.
#[derive(Clone, Debug)]
pub struct DrawnGlyph { pub glyph_id: String, pub rings: Vec<ReferenceRing> }

#[derive(Clone, Debug)]
pub struct InternalRun {
    pub source_pin: PinClaim,
    pub measurements: Vec<RingMeasurement>,
    pub containment_observations: Vec<ContainmentObservation>,
    pub pass_one: MetricPass,
    pub pass_two: MetricPass,
    pub open_boundaries: Vec<InternalBoundary>,
}

#[derive(Clone, Debug)]
pub enum GlyphSliceResult {
    Drawn { output: DrawnGlyph, internal: InternalRun },
    Impossible { glyph_id: String, reason: GlyphImpossible },
}

fn finite(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }

fn measure(index: usize, ring: &ReferenceRing) -> Result<RingMeasurement, GlyphImpossible> {
    if ring.spans.is_empty() { return Err(GlyphImpossible::NoData); }
    if !finite(ring.start) || ring.spans.iter().flat_map(Span::points).any(|p| !finite(p)) {
        return Err(GlyphImpossible::NonFiniteGeometry);
    }
    if ring.spans.last().map(Span::end) != Some(ring.start) { return Err(GlyphImpossible::OpenContour); }
    let mut minimum = ring.start;
    let mut maximum = ring.start;
    let mut endpoints = vec![ring.start];
    let mut cubic_span_indices = Vec::new();
    let mut area = 0.0;
    let mut previous = ring.start;
    for (i, span) in ring.spans.iter().enumerate() {
        let end = span.end();
        area += previous.x * end.y - end.x * previous.y;
        for p in span.points() {
            minimum.x = minimum.x.min(p.x); minimum.y = minimum.y.min(p.y);
            maximum.x = maximum.x.max(p.x); maximum.y = maximum.y.max(p.y);
        }
        if matches!(span, Span::Cubic { .. }) { cubic_span_indices.push(i); }
        endpoints.push(end); previous = end;
    }
    if cubic_span_indices.is_empty() && area == 0.0 { return Err(GlyphImpossible::DegenerateContour); }
    let polygon_signed_area = if cubic_span_indices.is_empty() && area.is_finite() { Some(area * 0.5) } else { None };
    Ok(RingMeasurement { ring_index: index, endpoints, cubic_span_indices,
        control_hull_bounds: Bounds { minimum, maximum }, polygon_signed_area })
}

/// Polygon point classification: boundary contact is explicit unknown.
fn inside(point: Point, ring: &RingMeasurement) -> Option<bool> {
    let mut result = false;
    for edge in ring.endpoints.windows(2) {
        let (a, b) = (edge[0], edge[1]);
        let cross = (point.x-a.x)*(b.y-a.y)-(point.y-a.y)*(b.x-a.x);
        if !cross.is_finite() { return None; }
        if cross == 0.0 && point.x >= a.x.min(b.x) && point.x <= a.x.max(b.x)
            && point.y >= a.y.min(b.y) && point.y <= a.y.max(b.y) { return None; }
        if (a.y > point.y) != (b.y > point.y) {
            let x = (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x;
            if !x.is_finite() { return None; }
            if point.x < x { result = !result; }
        }
    }
    Some(result)
}

/// Explicit identity reconstruction of an already supplied outline.
/// This method is not one of the missing archived solvers and selects no winner.
pub fn preserve_reference(glyph: ReferenceGlyph) -> GlyphSliceResult {
    if glyph.rings.is_empty() { return GlyphSliceResult::Impossible { glyph_id: glyph.glyph_id, reason: GlyphImpossible::NoData }; }
    let mut measurements = Vec::new();
    for (i, ring) in glyph.rings.iter().enumerate() {
        match measure(i, ring) {
            Ok(m) => measurements.push(m),
            Err(reason) => return GlyphSliceResult::Impossible { glyph_id: glyph.glyph_id, reason },
        }
    }
    let mut bounds = measurements[0].control_hull_bounds.clone();
    for m in &measurements[1..] {
        bounds.minimum.x = bounds.minimum.x.min(m.control_hull_bounds.minimum.x);
        bounds.minimum.y = bounds.minimum.y.min(m.control_hull_bounds.minimum.y);
        bounds.maximum.x = bounds.maximum.x.max(m.control_hull_bounds.maximum.x);
        bounds.maximum.y = bounds.maximum.y.max(m.control_hull_bounds.maximum.y);
    }
    let mut open_boundaries = vec![InternalBoundary::ThicknessFlowMethodUnbound, InternalBoundary::ArchivedSolverMethodsUnbound];
    if measurements.iter().any(|m|m.cubic_span_indices.is_empty()&&m.polygon_signed_area.is_none()){open_boundaries.push(InternalBoundary::PolygonAreaNumericallyUnresolved);}
    if glyph.declared_junction_decision_required { open_boundaries.push(InternalBoundary::JunctionDecisionUnresolved); }
    for m in &measurements{if m.cubic_span_indices.is_empty()&&!crate::polygon_intersections::ring_is_simple_observation(&m.endpoints){open_boundaries.push(InternalBoundary::SingleRingTopologyUnresolved{ring_index:m.ring_index});}}
    let mut containment_observations = Vec::new();
    for inner in &measurements {
        for outer in &measurements {
            if inner.ring_index == outer.ring_index { continue; }
            match (inner.polygon_signed_area, outer.polygon_signed_area) {
                (Some(a), Some(b)) => {
                    if !crate::polygon_intersections::ring_is_simple_observation(&inner.endpoints) || !crate::polygon_intersections::ring_is_simple_observation(&outer.endpoints) || !crate::polygon_intersections::ring_edges_disjoint(&inner.endpoints,&outer.endpoints) {
                        open_boundaries.push(InternalBoundary::TouchingOrIntersectingRingsUnresolved); continue;
                    }
                    let classifications: Vec<_> = inner.endpoints.iter().map(|p| inside(*p, outer)).collect();
                    if classifications.iter().all(|v| *v == Some(true)) {
                        containment_observations.push(ContainmentObservation { inner_ring: inner.ring_index,
                            outer_ring: outer.ring_index, opposite_winding: a.signum() != b.signum() });
                    } else if classifications.iter().any(|v| v.is_none()) {
                        open_boundaries.push(InternalBoundary::TouchingOrIntersectingRingsUnresolved);
                    }
                },
                _ if !inner.cubic_span_indices.is_empty()||!outer.cubic_span_indices.is_empty() => open_boundaries.push(InternalBoundary::CurvedRingContainmentUnresolved),
                _ => open_boundaries.push(InternalBoundary::PolygonAreaNumericallyUnresolved),
            }
        }
    }
    let pass_one = MetricPass { pass_number: 1, control_hull_bounds: bounds.clone(), ring_count: glyph.rings.len() };
    let pass_two = MetricPass { pass_number: 2, control_hull_bounds: bounds, ring_count: glyph.rings.len() };
    GlyphSliceResult::Drawn { output: DrawnGlyph { glyph_id: glyph.glyph_id, rings: glyph.rings },
        internal: InternalRun { source_pin: glyph.source_pin, measurements, containment_observations,
            pass_one, pass_two, open_boundaries } }
}

/// One glyph's failure is retained locally; siblings are always processed.
pub fn preserve_reference_batch(glyphs: Vec<ReferenceGlyph>) -> Vec<GlyphSliceResult> {
    glyphs.into_iter().map(preserve_reference).collect()
}

/// Policy slot deliberately empty until exact archived bodies are supplied.
pub trait ArchivedOutlineSolver {
    fn method_revision(&self) -> &PinClaim;
    fn solve(&self, reference: ReferenceGlyph) -> GlyphSliceResult;
}

/// Explicit intentional emptiness, never inferred from missing data.
#[derive(Clone,Debug)]
pub enum EmptyGlyphIntent { Space,Notdef,CallerDeclared { purpose:String } }
#[derive(Clone,Debug)]
pub struct IntentionalEmptyGlyph {pub glyph_id:String,pub source_pin:PinClaim,pub intent:EmptyGlyphIntent}
pub fn preserve_intentional_empty(input:IntentionalEmptyGlyph)->DrawnGlyph{DrawnGlyph{glyph_id:input.glyph_id,rings:Vec::new()}}
