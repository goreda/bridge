//! Segment economy after the fidelity and construction decisions.
//! This first candidate is geometry-identical on integer coordinates only.
//! No fitted curve, corner, extremum boundary or capture threshold is changed.
use crate::reference_slice::{Point, Span};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SpanCounts { pub lines: usize, pub cubics: usize }
impl SpanCounts { pub fn segments(&self) -> usize { self.lines + self.cubics } }
pub fn count(spans: &[Span]) -> SpanCounts {
    let mut c = SpanCounts::default();
    for s in spans { match s { Span::Line { .. } => c.lines += 1, Span::Cubic { .. } => c.cubics += 1 } }
    c
}
#[derive(Clone, Debug, PartialEq)]
pub struct EconomyDecision {
    pub rule: &'static str,
    pub arc: usize,
    /// Original inclusive span range, prior to this pass.
    pub first_span: usize,
    pub last_span: usize,
    pub before: SpanCounts,
    pub after: SpanCounts,
    pub geometry_identical: bool,
    pub construction_boundary_preserved: bool,
}

// Integers exactly representable in binary64 only. Arithmetic must be exact:
// products/sums are limited to the binary64 consecutive-integer range.
// 2^53 is a representation limit, not a drawing/calibration threshold.
fn integer(p: Point) -> bool {
    p.x.is_finite() && p.y.is_finite() && p.x.fract() == 0.0 && p.y.fract() == 0.0
        && p.x.abs() <= (1u64 << f64::MANTISSA_DIGITS) as f64
        && p.y.abs() <= (1u64 << f64::MANTISSA_DIGITS) as f64
}
fn straight_forward(a: Point, b: Point, c: Point) -> bool {
    if ![a,b,c].into_iter().all(integer) { return false; }
    // i128 arithmetic avoids falsely accepting a nearly collinear span due to
    // binary64 multiplication rounding. Input integers have at most 54-bit
    // differences, so products and sums fit in i128.
    let (abx,aby) = (b.x as i128-a.x as i128, b.y as i128-a.y as i128);
    let (bcx,bcy) = (c.x as i128-b.x as i128, c.y as i128-b.y as i128);
    abx*bcy == aby*bcx && abx*bcx+aby*bcy > 0
}

fn on_closed_chord(a:Point,p:Point,b:Point)->bool {
    if ![a,p,b].into_iter().all(integer) {return false;}
    let (dx,dy)=(b.x as i128-a.x as i128,b.y as i128-a.y as i128);
    let (px,py)=(p.x as i128-a.x as i128,p.y as i128-a.y as i128);
    dx*py==dy*px && px*dx+py*dy>=0 && px*dx+py*dy<=dx*dx+dy*dy
}
/// Exact geometric cubic-to-line candidate. The convex hull of both controls
/// lies on the closed chord, hence the curve's image is exactly that chord.
/// Endpoint/corner identity remains. Continuity and downstream extrema are
/// still judged by the final-font evaluator, never waived here.
pub fn exact_cubic_lines(start:Point,spans:Vec<Span>,arcs:&[usize])
    ->(Vec<Span>,Vec<EconomyDecision>) {
    if arcs.len()!=spans.len(){return(spans,Vec::new());}
    let mut current=start;let mut out=Vec::with_capacity(spans.len());let mut records=Vec::new();
    for (i,span) in spans.into_iter().enumerate(){
        let end=match span {Span::Line{end}|Span::Cubic{end,..}=>end};
        let convert=match span {Span::Cubic{control_one,control_two,..}=>
            current!=end && on_closed_chord(current,control_one,end)
                && on_closed_chord(current,control_two,end),_=>false};
        if convert {out.push(Span::Line{end});records.push(EconomyDecision{
            rule:"exact-integer-chord-cubic-to-line",arc:arcs[i],first_span:i,last_span:i,
            before:SpanCounts{lines:0,cubics:1},after:SpanCounts{lines:1,cubics:0},
            geometry_identical:true,construction_boundary_preserved:true});}
        else {out.push(span);}
        current=end;
    }
    (out,records)
}

/// Collapse only forward, exactly collinear integer Lines of one source arc.
/// Arc identifiers are mandatory provenance. Each arc endpoint protects a
/// capture corner, rescue split or pre-fit extremum. Cubics and direction
/// reversals stop a run. No tolerance, source-error relaxation or C->L occurs.
/// An invalid provenance length fails closed and returns the original spans.
pub fn exact_line_economy(start: Point, spans: Vec<Span>, arcs: &[usize])
    -> (Vec<Span>, Vec<EconomyDecision>) {
    if spans.len() != arcs.len() { return (spans, Vec::new()); }
    let mut out = Vec::with_capacity(spans.len());
    let mut decisions = Vec::new();
    let mut current = start;
    let mut i = 0;
    while i < spans.len() {
        let mut j = i;
        let mut end = match spans[i] { Span::Line { end } => end, Span::Cubic { end, .. } => end };
        if matches!(spans[i], Span::Line { .. }) {
            while j+1 < spans.len() && arcs[j+1] == arcs[i] {
                let Span::Line { end: next } = spans[j+1] else { break; };
                if !straight_forward(current, end, next) { break; }
                end = next; j += 1;
            }
        }
        if j > i {
            out.push(Span::Line { end });
            decisions.push(EconomyDecision { rule: "exact-integer-same-arc-line-merge", arc: arcs[i],
                first_span: i, last_span: j, before: SpanCounts { lines: j-i+1, cubics: 0 },
                after: SpanCounts { lines: 1, cubics: 0 }, geometry_identical: true,
                construction_boundary_preserved: true });
        } else { out.push(spans[i].clone()); }
        current = end; i = j+1;
    }
    (out, decisions)
}

use crate::reference_slice::DrawnGlyph;

/// DECLARED_CONVENTION: per-glyph tile-IoU loss gate for economy selection.
/// A candidate whose final-font tile IoU falls more than this below the
/// current engine output is rejected (`SelectionReason::FidelityBound`);
/// a loss of exactly this value passes. Callers pass it as
/// `FontEconomyBound.allowed_iou_loss`.
/// Provenance: owner directive 2026-10-13 12:15 +03 via main (node/segment
/// economy is the core objective); ECONOMY-SPEC-v0.1 (hub draft) gate
/// suggestion 0.002, adopted by the NE-1 writer brief 2026-10-18;
/// docs/kni/2026-10-18-economy-objective-conventions.md.
pub const ECONOMY_IOU_LOSS_GATE: f64 = 0.002;

/// Gate tolerances must have a recoverable within-font derivation. This type
/// records the caller's derivation; it does not certify that derivation.
#[derive(Clone, Debug)]
pub struct FontEconomyBound {
    pub font_measurement_pin: String,
    pub loss_derivation: LossDerivation,
    pub squared_fit_budget: f64,
    pub maximum_deviation: f64,
    pub allowed_iou_loss: f64,
}
/// Caller must supply source measurements and a derivation, not just a label.
#[derive(Clone, Debug)]
pub struct LossDerivation {
    pub source_measurement_pin: String,
    pub method: String,
    pub measurements: Vec<(String, f64)>,
}
#[derive(Clone, Debug)]
pub struct RegionDelta {
    pub region_id: String,
    pub baseline_squared_error: f64,
    pub candidate_squared_error: f64,
    pub baseline_deviation: f64,
    pub candidate_deviation: f64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConstructionComparison { Preserved, Improved, Regressed, Unknown }
#[derive(Clone, Debug)]
pub struct RegionAssessment {
    pub region_id: String,
    pub squared_fit_error: f64,
    pub maximum_deviation: f64,
    pub construction: ConstructionComparison,
    pub extrema_preserved: bool,
    pub corners_preserved: bool,
    pub continuity_preserved: bool,
}
/// Final integer-charstring font render only, not pre-container SVG. The
/// evaluator owns this assertion and must return None when it cannot verify.
#[derive(Clone, Debug)]
pub struct FontAssessment {
    pub source_pin: String,
    pub render_frame_pin: String,
    pub domain: String,
    pub threshold: u8,
    pub font_iou: f64,
    pub regions: Vec<RegionAssessment>,
}
/// A source-aware evaluator must encode/parse/render the candidate's final
/// integer font and measure regions against the same source. Returning None
/// blocks the candidate. No dummy score or fallback estimate is provided.
pub trait FontEconomyEvaluator {
    fn assess(&mut self, baseline: &DrawnGlyph, candidate: &DrawnGlyph) -> Option<FontAssessment>;
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SelectionReason {
    AcceptedEconomy, InvalidBound, UnverifiedBaseline, UnverifiedCandidate,
    GlyphMismatch, FrameMismatch, RegionMismatch, FidelityBound, RegionRegression, ConstructionGuard, NoEconomyGain,
}
#[derive(Clone, Debug)]
pub struct SelectionRecord {
    pub candidate_index: usize,
    pub before: SpanCounts,
    pub after: SpanCounts,
    pub reason: SelectionReason,
    pub assessment: Option<FontAssessment>,
    pub bound_used: FontEconomyBound,
    pub region_deltas: Vec<RegionDelta>,
}
fn glyph_count(g: &DrawnGlyph) -> SpanCounts {
    let mut c=SpanCounts::default();
    for r in &g.rings { let rc=count(&r.spans); c.lines+=rc.lines;c.cubics+=rc.cubics; }
    c
}
fn valid_bound(b:&FontEconomyBound)->bool {
    !b.font_measurement_pin.is_empty()
        && !b.loss_derivation.source_measurement_pin.is_empty()
        && !b.loss_derivation.method.is_empty()
        && !b.loss_derivation.measurements.is_empty()
        && b.loss_derivation.measurements.iter().all(|(name,value)|!name.is_empty()&&value.is_finite())
        && [b.squared_fit_budget,b.maximum_deviation,b.allowed_iou_loss]
        .into_iter().all(|x|x.is_finite()&&x>=0.) && b.allowed_iou_loss<1.
}
fn valid_assessment(a:&FontAssessment,b:&FontEconomyBound)->bool {
    !a.source_pin.is_empty() && !a.render_frame_pin.is_empty() && !a.domain.is_empty()
        && a.font_iou.is_finite() && (0.0..=1.0).contains(&a.font_iou) && !a.regions.is_empty()
        && a.regions.iter().all(|r| !r.region_id.is_empty()
            && r.squared_fit_error.is_finite() && r.squared_fit_error>=0.
            && r.squared_fit_error<=b.squared_fit_budget
            && r.maximum_deviation.is_finite() && r.maximum_deviation>=0.
            && r.maximum_deviation<=b.maximum_deviation)
        && a.regions.iter().enumerate().all(|(i,r)|a.regions[..i].iter().all(|p|p.region_id!=r.region_id))
}
/// Engine objective: choose fewer segments only AFTER the fidelity bound,
/// per-region construction guards and final font-domain comparison pass.
/// All candidates are compared against the original baseline, preventing
/// cumulative IoU drift. Unknown construction or missing evidence abstains.
/// Caller candidates must have the same glyph id; there is no reference-R goal.
pub fn select_economical_glyph<E:FontEconomyEvaluator>(
    baseline: DrawnGlyph, candidates: Vec<DrawnGlyph>, bound: &FontEconomyBound, evaluator:&mut E,
) -> (DrawnGlyph, Vec<SelectionRecord>) {
    let base_count=glyph_count(&baseline);
    let base_assessment=if valid_bound(bound){evaluator.assess(&baseline,&baseline)}else{None};
    let mut selected=baseline.clone();let mut records=Vec::new();
    let mut selected_assessment=base_assessment.clone();
    for (candidate_index,c) in candidates.into_iter().enumerate() {
        let before=glyph_count(&selected);let after=glyph_count(&c);
        let mut assessment=None;
        let mut region_deltas=Vec::new();
        let reason=if !valid_bound(bound){SelectionReason::InvalidBound}
        else if base_assessment.as_ref().is_none_or(|a|!valid_assessment(a,bound)) {
            SelectionReason::UnverifiedBaseline
        } else if c.glyph_id!=baseline.glyph_id {SelectionReason::GlyphMismatch}
        else {
            assessment=evaluator.assess(&baseline,&c);
            match assessment.as_ref() {
                None=>SelectionReason::UnverifiedCandidate,
                Some(a)=>{
                    let ba=base_assessment.as_ref().unwrap();
                    for br in &ba.regions {
                        if let Some(cr)=a.regions.iter().find(|r|r.region_id==br.region_id) {
                            region_deltas.push(RegionDelta{region_id:br.region_id.clone(),
                                baseline_squared_error:br.squared_fit_error,candidate_squared_error:cr.squared_fit_error,
                                baseline_deviation:br.maximum_deviation,candidate_deviation:cr.maximum_deviation});
                        }
                    }
                    if a.source_pin!=ba.source_pin || a.render_frame_pin!=ba.render_frame_pin
                        || a.domain!=ba.domain || a.threshold!=ba.threshold {SelectionReason::FrameMismatch}
                    else if !valid_assessment(a,bound) || a.font_iou<ba.font_iou-bound.allowed_iou_loss {
                        SelectionReason::FidelityBound
                    } else if a.regions.len()!=ba.regions.len()
                        || ba.regions.iter().any(|r|!a.regions.iter().any(|p|p.region_id==r.region_id)) {
                        SelectionReason::RegionMismatch
                    } else if region_deltas.iter().any(|r|r.candidate_squared_error>r.baseline_squared_error
                        ||r.candidate_deviation>r.baseline_deviation) {
                        // Conservative first policy: no local regression. Future
                        // relaxations need a recorded within-font derivation.
                        SelectionReason::RegionRegression
                    } else if a.regions.iter().any(|r|!r.extrema_preserved||!r.corners_preserved
                        ||!r.continuity_preserved||matches!(r.construction,ConstructionComparison::Regressed|ConstructionComparison::Unknown)) {
                        SelectionReason::ConstructionGuard
                    } else if selected_assessment.as_ref().is_some_and(|prior|
                        prior.regions.iter().any(|r|r.construction==ConstructionComparison::Improved
                            && a.regions.iter().any(|p|p.region_id==r.region_id
                                && p.construction!=ConstructionComparison::Improved))) {
                        SelectionReason::ConstructionGuard
                    } else if after.segments()>=before.segments() || after.segments()>=base_count.segments() {
                        SelectionReason::NoEconomyGain
                    } else {SelectionReason::AcceptedEconomy}
                }
            }
        };
        if reason==SelectionReason::AcceptedEconomy {selected=c; selected_assessment=assessment.clone();}
        records.push(SelectionRecord{candidate_index,before,after,reason,assessment,bound_used:bound.clone(),region_deltas});
    }
    (selected,records)
}
