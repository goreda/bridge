//! Source-bound cubic point evaluation only. NOT fitting or reconstruction.
//! No parameter sampling defaults, normalization or control-point mutation.
use crate::decision_evidence_envelope::PinClaim;
use crate::reference_slice::Point;

#[derive(Clone, Debug)]
pub struct SourceCubic {
    pub source_pin: PinClaim,
    pub ring_index: usize,
    pub span_index: usize,
    pub start: Point,
    pub control_one: Point,
    pub control_two: Point,
    pub end: Point,
}

#[derive(Clone, Debug)]
pub struct CubicPointObservation {
    /// Complete source claim and original controls retained, never authenticated.
    pub source: SourceCubic,
    pub parameter: f64,
    pub evaluated_point: Point,
    pub evaluation_method: &'static str,
}

#[derive(Clone, Debug)]
pub enum CubicEvaluationError {
    NonFiniteSource,
    NonFiniteParameter,
    ParameterOutOfRange,
    NonFiniteIntermediate,
}

fn finite(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }

fn blend(a: Point,b: Point,t: f64) -> Result<Point,CubicEvaluationError> {
    let p = Point { x:(1.0-t)*a.x+t*b.x,y:(1.0-t)*a.y+t*b.y };
    if finite(p) { Ok(p) } else { Err(CubicEvaluationError::NonFiniteIntermediate) }
}

/// De Casteljau evaluation at an explicitly supplied t in [0,1].
/// Endpoints return exact original values/bits, no arithmetic canonicalization.
pub fn evaluate_cubic(source: &SourceCubic,t: f64) -> Result<CubicPointObservation,CubicEvaluationError> {
    if ![source.start,source.control_one,source.control_two,source.end].iter().all(|p| finite(*p)) {
        return Err(CubicEvaluationError::NonFiniteSource);
    }
    if !t.is_finite() { return Err(CubicEvaluationError::NonFiniteParameter); }
    if !(0.0..=1.0).contains(&t) { return Err(CubicEvaluationError::ParameterOutOfRange); }
    let evaluated_point = if t == 0.0 { source.start } else if t == 1.0 { source.end } else {
        let a = blend(source.start,source.control_one,t)?;
        let b = blend(source.control_one,source.control_two,t)?;
        let c = blend(source.control_two,source.end,t)?;
        blend(blend(a,b,t)?,blend(b,c,t)?,t)?
    };
    Ok(CubicPointObservation { source:source.clone(),parameter:t,evaluated_point,
        evaluation_method:"de-casteljau-binary64-v0.1" })
}
