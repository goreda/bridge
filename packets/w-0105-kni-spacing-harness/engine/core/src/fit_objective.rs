//! fit_objective: node-economy objective for the cubic fitter (MONA-FITOBJ).
//!
//! General machinery only: nothing here knows a style, a font name, or a
//! glyph class. The objective scores a candidate segmentation/fitting of one
//! captured open run of source samples against three terms, all expressed in
//! ONE currency - squared source-acquisition bands:
//!
//!   total = fidelity + curvature + node_price
//!
//! Currency derivation (no global constants): the source tile's own pixel
//! step in working units is `source_step`, supplied by the caller from the
//! engine's scale derivation (e.g. canonical_scale); it is a measurement of
//! this font's tile, never a literal. A binary acquisition assigns every
//! ink/background boundary to a pixel cell, so a true boundary can sit at
//! most half a step from its recorded position: the half-step band
//! (source_step/2) is the acquisition's own quantization uncertainty, and
//! squared deviations inside band^2 cannot be evidence of structure. Every
//! term below is normalized by band^2 = (source_step/2)^2 so the objective
//! is scale-invariant across fonts and resolutions (scale-invariance is
//! unit-tested bit-exact for power-of-two scalings).
//!
//! Terms:
//! - fidelity: max squared footpoint deviation over interior samples,
//!   divided by band^2. Max (not mean) matches the fitter's existing
//!   worst-sample acceptance policy in cubic_fit.
//! - curvature: mean over scored interior samples of
//!   (dK * s^2 / source_step)^2, where dK = kappa_candidate - kappa_source
//!   at the sample and s is the sample's local step (mean distance to its
//!   two neighbours, measured from the samples). Derivation: a curvature
//!   error dK held over one local step s bends the path away from the
//!   source by the sagitta dK*s^2/2; measured in the half-step band that is
//!   dK*s^2/source_step, and squaring puts it in the same band^2 currency
//!   as fidelity. kappa_source is the circumscribed curvature of the
//!   sample's own triple; kappa_candidate is analytic from the cubic at the
//!   sample's footpoint. Samples where either curvature is undefined
//!   (degenerate triple, zero cubic speed) are excluded from the mean and
//!   counted in `curvature_undefined`.
//! - node_price: CONVENTION - each on-curve node costs exactly 1 band^2.
//!   Written derivation: below one full band of worst-sample squared
//!   deviation a node is fitting the acquisition's own quantization noise,
//!   not structure, so a node must be able to remove at least one band^2 of
//!   error to pay for itself. Endpoints of the run are shared by every
//!   candidate segmentation, so the per-node price ranks candidates
//!   identically whether or not endpoints are included; the report counts
//!   all on-curve nodes (segments + 1).
//!
//! Candidate selection (`compare`) is a pure function of the two scores:
//! lower total wins; exact ties break to fewer nodes, then to lower raw
//! max_deviation. Deterministic, serial, no randomness, no I/O.
//!
//! W10 (fit_search) consumes `Objective`, `CurveCandidate`, `ObjectiveScore`
//! and `compare` as its objective API. This module is additive: no
//! production path calls it, so every existing style and pair remains
//! bit-identical while it is unused. The measurement report
//! (`render_measurement_report`) consumes the W13 bench TSV
//! (KNI_FIT_BENCH_OUT, format `fit_bench_v1`) and joins per-glyph timings
//! with per-glyph scores; every report carries its measurement domain label
//! (Mona stress, Paul New stress, or bench).

//! NE-1 (2026-10-18): `EconomyObjective` implements the W10 `FitObjective`
//! contract with this module's band currency, and `accept_refit` carries the
//! economy-aware refit accept rule (error reduction, or segment reduction
//! within budget). Both are additive like the rest of the module: no
//! production path calls them until the search gate and the fitter lane wire
//! them, so every existing style and pair remains bit-identical.
//!
//! Gate split (the objective's bound side): fit error <= caller budget and
//! per-glyph tile-IoU loss <= `economy::ECONOMY_IOU_LOSS_GATE` are enforced
//! where whole states are compared - `accept_refit` for trajectory/candidate
//! decisions, `economy::select_economical_glyph` for per-glyph selection.

use crate::fit_search::{CandidateState, FitObjective, SearchContext};
use crate::reference_slice::Point;

/// Which measurement domain a report's numbers belong to. The label is
/// written into the report header so numbers from different domains are
/// never mixed or compared silently.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MeasurementDomain {
    MonaStress,
    PaulNewStress,
    Bench,
    Custom(String),
}

impl MeasurementDomain {
    pub fn label(&self) -> &str {
        match self {
            Self::MonaStress => "mona-stress",
            Self::PaulNewStress => "paul-new-stress",
            Self::Bench => "bench",
            Self::Custom(s) => s.as_str(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ObjectiveError {
    /// source_step must be finite and strictly positive.
    InvalidStep,
    /// A point, parameter or derived quantity was not finite.
    NonFiniteInput,
    /// Fewer than 2 samples: no interior exists to score.
    EmptySamples,
    /// Segments must partition [0, samples.len()-1] with shared
    /// endpoints: first segment starts at 0, each next first == previous
    /// last, and the final last == samples.len()-1.
    BadSegmentLayout(&'static str),
    /// A footpoint parameter lay outside [0,1].
    ParameterOutOfRange,
    /// parameters.len() must equal last - first + 1 for each segment.
    ParameterCountMismatch,
    /// Bench TSV did not match the fit_bench_v1 shape.
    MalformedBench(&'static str),
}

impl std::fmt::Display for ObjectiveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidStep => write!(f, "source_step must be finite and > 0"),
            Self::NonFiniteInput => write!(f, "non-finite coordinate or parameter"),
            Self::EmptySamples => write!(f, "need at least 2 samples"),
            Self::BadSegmentLayout(why) => write!(f, "bad segment layout: {why}"),
            Self::ParameterOutOfRange => write!(f, "footpoint parameter outside [0,1]"),
            Self::ParameterCountMismatch => write!(f, "parameter count != sample range"),
            Self::MalformedBench(why) => write!(f, "malformed bench tsv: {why}"),
        }
    }
}
impl std::error::Error for ObjectiveError {}

/// One cubic segment of a candidate fitting, bound to the source samples it
/// explains. `first..=last` indexes the shared sample array; `parameters[k]`
/// is the footpoint parameter of samples[first + k] on `controls`.
#[derive(Clone, Debug)]
pub struct CurveCandidate {
    pub controls: [Point; 4],
    pub parameters: Vec<f64>,
    pub first: usize,
    pub last: usize,
}

/// The derived objective: one half-step band carries all weights.
#[derive(Clone, Copy, Debug)]
pub struct Objective {
    source_step: f64,
    band: f64,
    band_sq: f64,
}

/// Full score of one candidate fitting. `total` is the only number `compare`
/// ranks first; the rest are report and tie-break evidence.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ObjectiveScore {
    pub total: f64,
    pub fidelity: f64,
    pub curvature: f64,
    pub node_price: f64,
    /// On-curve nodes of the candidate (segments + 1, endpoints included).
    pub nodes: usize,
    /// Worst footpoint distance in raw working units.
    pub max_deviation: f64,
    /// Samples whose footpoint distance exceeds one half-step band.
    pub deviation_events: usize,
    /// Interior samples excluded from the curvature mean (undefined kappa).
    pub curvature_undefined: usize,
    /// Echo of the step this score was derived with (report normalization).
    pub source_step: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CandidateOrder {
    /// Second candidate scores better than the first.
    SecondBetter,
    /// First candidate scores better than the second.
    FirstBetter,
    /// Identical on every ranked field.
    Equal,
}

fn finite(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }
fn sub(a: Point, b: Point) -> Point { Point { x: a.x - b.x, y: a.y - b.y } }
fn dot(a: Point, b: Point) -> f64 { a.x * b.x + a.y * b.y }
fn cross(a: Point, b: Point) -> f64 { a.x * b.y - a.y * b.x }
fn norm(a: Point) -> f64 { a.x.hypot(a.y) }

fn cubic_point(q: &[Point; 4], t: f64) -> Point {
    let v = 1.0 - t;
    let b = [v * v * v, 3.0 * t * v * v, 3.0 * t * t * v, t * t * t];
    let mut p = Point { x: 0.0, y: 0.0 };
    for i in 0..4 {
        p.x += q[i].x * b[i];
        p.y += q[i].y * b[i];
    }
    p
}

/// First and second derivative of the cubic at t.
fn cubic_derivatives(q: &[Point; 4], t: f64) -> (Point, Point) {
    let v = 1.0 - t;
    let d1 = Point {
        x: 3.0 * (v * v * (q[1].x - q[0].x) + 2.0 * t * v * (q[2].x - q[1].x) + t * t * (q[3].x - q[2].x)),
        y: 3.0 * (v * v * (q[1].y - q[0].y) + 2.0 * t * v * (q[2].y - q[1].y) + t * t * (q[3].y - q[2].y)),
    };
    let d2 = Point {
        x: 6.0 * (v * (q[2].x - 2.0 * q[1].x + q[0].x) + t * (q[3].x - 2.0 * q[2].x + q[1].x)),
        y: 6.0 * (v * (q[2].y - 2.0 * q[1].y + q[0].y) + t * (q[3].y - 2.0 * q[2].y + q[1].y)),
    };
    (d1, d2)
}

/// Analytic curvature of the cubic at t. None when the speed vanishes
/// (curvature undefined at a cusp/coincident-control point).
fn cubic_curvature(q: &[Point; 4], t: f64) -> Option<f64> {
    let (d1, d2) = cubic_derivatives(q, t);
    let speed = norm(d1);
    if !speed.is_finite() || speed == 0.0 {
        return None;
    }
    let k = cross(d1, d2) / (speed * speed * speed);
    if k.is_finite() { Some(k) } else { None }
}

/// Circumscribed curvature of the triple (a,b,c): 2*cross(b-a,c-a) /
/// (|b-a|*|c-b|*|c-a|). None when the triple is degenerate (any zero side);
/// a collinear triple yields exactly 0.
fn sample_curvature(a: Point, b: Point, c: Point) -> Option<f64> {
    let ab = sub(b, a);
    let bc = sub(c, b);
    let ca = sub(a, c);
    let (lab, lbc, lca) = (norm(ab), norm(bc), norm(ca));
    if lab == 0.0 || lbc == 0.0 || lca == 0.0 {
        return None;
    }
    let k = 2.0 * cross(ab, sub(c, a)) / (lab * lbc * lca);
    if k.is_finite() { Some(k) } else { None }
}

impl Objective {
    /// Derive the objective from the source tile's own pixel step in working
    /// units (engine scale derivation output; never a literal).
    pub fn derive(source_step: f64) -> Result<Objective, ObjectiveError> {
        if !source_step.is_finite() || source_step <= 0.0 {
            return Err(ObjectiveError::InvalidStep);
        }
        let band = source_step / 2.0;
        Ok(Objective { source_step, band, band_sq: band * band })
    }

    pub fn source_step(&self) -> f64 { self.source_step }

    /// Score one candidate fitting of `samples`. Segments must partition the
    /// run with shared endpoints: seg[0].first == 0, seg[k+1].first ==
    /// seg[k].last, seg[n-1].last == samples.len()-1.
    pub fn score(&self, samples: &[Point], segments: &[CurveCandidate]) -> Result<ObjectiveScore, ObjectiveError> {
        if samples.len() < 2 {
            return Err(ObjectiveError::EmptySamples);
        }
        if !samples.iter().all(|p| finite(*p)) {
            return Err(ObjectiveError::NonFiniteInput);
        }
        if segments.is_empty() {
            return Err(ObjectiveError::BadSegmentLayout("no segments"));
        }
        if segments[0].first != 0 {
            return Err(ObjectiveError::BadSegmentLayout("first segment must start at sample 0"));
        }
        if segments[segments.len() - 1].last != samples.len() - 1 {
            return Err(ObjectiveError::BadSegmentLayout("last segment must end at final sample"));
        }
        for (k, seg) in segments.iter().enumerate() {
            if seg.first > seg.last {
                return Err(ObjectiveError::BadSegmentLayout("empty range"));
            }
            if seg.last >= samples.len() {
                return Err(ObjectiveError::BadSegmentLayout("range beyond samples"));
            }
            if seg.parameters.len() != seg.last - seg.first + 1 {
                return Err(ObjectiveError::ParameterCountMismatch);
            }
            if k + 1 < segments.len() && segments[k + 1].first != seg.last {
                return Err(ObjectiveError::BadSegmentLayout("segments must share endpoints"));
            }
            if !seg.controls.iter().all(|p| finite(*p)) {
                return Err(ObjectiveError::NonFiniteInput);
            }
            for &t in &seg.parameters {
                if !t.is_finite() {
                    return Err(ObjectiveError::NonFiniteInput);
                }
                if !(0.0..=1.0).contains(&t) {
                    return Err(ObjectiveError::ParameterOutOfRange);
                }
            }
        }

        let mut max_sq = 0.0f64;
        let mut deviation_events = 0usize;
        let mut curvature_sum = 0.0f64;
        let mut curvature_n = 0usize;
        let mut curvature_undefined = 0usize;

        for seg in segments {
            for i in seg.first..=seg.last {
                let t = seg.parameters[i - seg.first];
                let q = cubic_point(&seg.controls, t);
                let d = sub(q, samples[i]);
                let e = dot(d, d);
                if !e.is_finite() {
                    return Err(ObjectiveError::NonFiniteInput);
                }
                let interior_of_segment = i > seg.first && i < seg.last;
                if interior_of_segment {
                    if e > max_sq {
                        max_sq = e;
                    }
                    if e.sqrt() > self.band {
                        deviation_events += 1;
                    }
                }
                // Curvature is a run-level property: an interior sample of the
                // run keeps its two neighbours even at a segment seam (the
                // shared endpoint's curvature is seam evidence, not segment
                // noise), so every sample in 1..len-1 is scored.
                let run_interior = i > 0 && i < samples.len() - 1;
                if run_interior {
                    let ks = sample_curvature(samples[i - 1], samples[i], samples[i + 1]);
                    let kc = cubic_curvature(&seg.controls, t);
                    if let (Some(ks), Some(kc)) = (ks, kc) {
                        let s = (norm(sub(samples[i], samples[i - 1]))
                            + norm(sub(samples[i + 1], samples[i])))
                            / 2.0;
                        let term = (kc - ks) * s * s / self.source_step;
                        if !term.is_finite() {
                            return Err(ObjectiveError::NonFiniteInput);
                        }
                        curvature_sum += term * term;
                        curvature_n += 1;
                    } else {
                        curvature_undefined += 1;
                    }
                }
            }
        }

        let fidelity = max_sq / self.band_sq;
        let curvature = if curvature_n > 0 { curvature_sum / curvature_n as f64 } else { 0.0 };
        let nodes = segments.len() + 1;
        let node_price = nodes as f64;
        Ok(ObjectiveScore {
            total: fidelity + curvature + node_price,
            fidelity,
            curvature,
            node_price,
            nodes,
            max_deviation: max_sq.sqrt(),
            deviation_events,
            curvature_undefined,
            source_step: self.source_step,
        })
    }

    /// Rank two candidate scores. Lower total wins; exact ties break to
    /// fewer nodes, then lower raw max_deviation.
    pub fn compare(&self, a: &ObjectiveScore, b: &ObjectiveScore) -> CandidateOrder {
        if a.total != b.total {
            return if b.total < a.total { CandidateOrder::SecondBetter } else { CandidateOrder::FirstBetter };
        }
        if a.nodes != b.nodes {
            return if b.nodes < a.nodes { CandidateOrder::SecondBetter } else { CandidateOrder::FirstBetter };
        }
        if a.max_deviation != b.max_deviation {
            return if b.max_deviation < a.max_deviation { CandidateOrder::SecondBetter } else { CandidateOrder::FirstBetter };
        }
        CandidateOrder::Equal
    }
}

/// Economy-aware candidate objective for the W10 open-gate search (owner
/// directive 2026-10-13 12:15 +03 via main; ECONOMY-SPEC-v0.1: segment
/// economy is the fitter's objective, bounded by the existing fidelity
/// budget and the declared per-glyph IoU gate).
///
/// Scoring reuses this module's `Objective` machinery verbatim: the
/// candidate's controls and footpoint parameters are scored against the
/// run's samples, so fidelity and curvature keep the squared half-step-band
/// currency. The node price is taken from the candidate's own
/// `spans_used` (every candidate the current search generates is one cubic
/// span, so the price is 2 and the total is bit-identical to
/// `Objective::score(...).total` for a single-span candidate); when the
/// search is later extended past the split seam the same score prices
/// multi-span candidates without a format change.
///
/// Gate contract (mirrors `BaselineObjective`): an implausible candidate,
/// and any candidate the scorer cannot measure, score +infinity and win
/// only when every candidate does; the search treats non-finite scores as
/// +infinity, so this objective never fabricates a failure and the
/// incumbent best-effort fallback order is preserved. The score ranks only
/// and never hard-rejects: the budget and IoU bounds live in
/// `accept_refit` and `economy::select_economical_glyph`, where whole
/// states are compared.
#[derive(Clone, Copy, Debug)]
pub struct EconomyObjective {
    objective: Objective,
}

impl EconomyObjective {
    /// Derive from the source tile's own pixel step in working units
    /// (same input and provenance as `Objective::derive`).
    pub fn derive(source_step: f64) -> Result<Self, ObjectiveError> {
        Objective::derive(source_step).map(|objective| EconomyObjective { objective })
    }

    pub fn source_step(&self) -> f64 { self.objective.source_step() }
}

impl FitObjective for EconomyObjective {
    fn score(&self, cand: &CandidateState, ctx: &SearchContext) -> f64 {
        if !cand.plausible || ctx.points.len() < 2 {
            return f64::INFINITY;
        }
        let segment = CurveCandidate {
            controls: cand.controls,
            parameters: cand.parameters.clone(),
            first: 0,
            last: ctx.points.len() - 1,
        };
        match self.objective.score(ctx.points, &[segment]) {
            Ok(s) => s.fidelity + s.curvature + (cand.spans_used + 1) as f64,
            Err(_) => f64::INFINITY,
        }
    }
}

/// Why a refit or span-level candidate was accepted under the economy-aware
/// accept rule.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RefitVerdict {
    /// The candidate strictly reduces the fit error (the incumbent rule).
    ErrorReduced,
    /// The candidate does not reduce the error but strictly reduces the
    /// segment count while staying within the existing error budget.
    EconomyWithinBudget,
}

/// Economy-aware refit accept rule (owner directive 2026-10-13 12:15 +03
/// via main; ECONOMY-SPEC-v0.1 item 4: accept a refit only if it reduces
/// error OR reduces the segment count without exceeding the budget; the
/// incumbent accept is error-only).
///
/// `prior_error` and `candidate_error` are max squared footpoint deviations
/// in the caller's own metric and units (the same metric
/// `FitPolicy.squared_error` expresses, which supplies
/// `squared_error_budget`). `prior_segments` / `candidate_segments` are the
/// compared states' on-curve segment counts: equal along one arc's Newton
/// trajectory (the rule then reduces exactly to the incumbent
/// strict-improvement accept), different for span-level merge/degrade
/// candidates, where they carry the economy claim.
///
/// The rule: accept iff candidate_error < prior_error (branch one keeps the
/// incumbent's budget-free strict-improvement ratchet), else accept iff the
/// segment count strictly drops and candidate_error <= squared_error_budget
/// (exact budget equality accepts). Every other shape - equal state, more
/// segments, an economy claim over budget, non-finite or negative input -
/// rejects. Pure, deterministic, no I/O.
pub fn accept_refit(
    prior_error: f64,
    prior_segments: usize,
    candidate_error: f64,
    candidate_segments: usize,
    squared_error_budget: f64,
) -> Option<RefitVerdict> {
    if ![prior_error, candidate_error, squared_error_budget].into_iter().all(|x| x.is_finite() && x >= 0.0) {
        return None;
    }
    if candidate_error < prior_error {
        return Some(RefitVerdict::ErrorReduced);
    }
    if candidate_segments < prior_segments && candidate_error <= squared_error_budget {
        return Some(RefitVerdict::EconomyWithinBudget);
    }
    None
}

/// Per-glyph row for the measurement report: one glyph's score, optionally
/// joined with its fit duration from the W13 bench TSV.
#[derive(Clone, Debug)]
pub struct GlyphMeasurement {
    pub name: String,
    pub score: ObjectiveScore,
    pub fit_seconds: Option<f64>,
}

/// Parse the W13 bench TSV (`fit_bench_v1`, KNI_FIT_BENCH_OUT) and return
/// per-glyph fit durations in row order. Only `glyph\t<name>\t<seconds>`
/// rows and the version line are interpreted; all other rows are validated
/// for shape but skipped. Durations are joined by glyph name; a repeated
/// name keeps the last row, matching the bench's own sort-by-name emission.
pub fn parse_bench_fit_seconds(tsv: &str) -> Result<Vec<(String, f64)>, ObjectiveError> {
    let mut lines = tsv.lines();
    match lines.next() {
        Some("fit_bench_v1") => {}
        _ => return Err(ObjectiveError::MalformedBench("missing fit_bench_v1 header")),
    }
    let mut rows: Vec<(String, f64)> = Vec::new();
    for line in lines {
        let mut cells = line.split('\t');
        let key = cells.next().ok_or(ObjectiveError::MalformedBench("empty line"))?;
        if key == "glyph" {
            let name = cells.next().ok_or(ObjectiveError::MalformedBench("glyph row without name"))?;
            let secs = cells
                .next()
                .ok_or(ObjectiveError::MalformedBench("glyph row without seconds"))?
                .parse::<f64>()
                .map_err(|_| ObjectiveError::MalformedBench("glyph seconds not a number"))?;
            if !secs.is_finite() {
                return Err(ObjectiveError::MalformedBench("glyph seconds not finite"));
            }
            if let Some(slot) = rows.iter_mut().find(|(n, _)| n == name) {
                slot.1 = secs;
            } else {
                rows.push((name.to_string(), secs));
            }
        }
    }
    Ok(rows)
}

/// Render the labeled measurement report (format
/// `fit_objective_report_v1`). Columns per glyph: nodes, raw max deviation,
/// max deviation in source steps, deviation events (samples beyond one
/// half-step band), curvature-mean term, fit seconds when the bench row
/// exists (`-` otherwise). Deterministic: rows render in the order given;
/// totals are sums of the rendered rows only.
pub fn render_measurement_report(domain: &MeasurementDomain, rows: &[GlyphMeasurement]) -> String {
    let mut s = String::from("fit_objective_report_v1\n");
    s.push_str(&format!("domain\t{}\n", domain.label()));
    s.push_str(&format!("glyphs\t{}\n", rows.len()));
    let mut node_total = 0usize;
    let mut event_total = 0usize;
    for r in rows {
        node_total += r.score.nodes;
        event_total += r.score.deviation_events;
        let secs = match r.fit_seconds {
            Some(v) => format!("{v:.6}"),
            None => "-".to_string(),
        };
        s.push_str(&format!(
            "glyph\t{}\t{}\t{:.6}\t{:.3}\t{}\t{:.6}\t{}\n",
            r.name.replace(['\t', '\n', '\r'], " "),
            r.score.nodes,
            r.score.max_deviation,
            r.score.max_deviation / r.score.source_step,
            r.score.deviation_events,
            r.score.curvature,
            secs,
        ));
    }
    s.push_str(&format!("nodes_total\t{node_total}\n"));
    s.push_str(&format!("deviation_events_total\t{event_total}\n"));
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(x: f64, y: f64) -> Point { Point { x, y } }

    /// Samples on a quarter circle of radius r centered at origin, from
    /// angle a0 to a1 inclusive, n samples.
    fn arc(r: f64, a0: f64, a1: f64, n: usize) -> Vec<Point> {
        (0..n)
            .map(|i| {
                let a = a0 + (a1 - a0) * i as f64 / (n - 1) as f64;
                p(r * a.cos(), r * a.sin())
            })
            .collect()
    }

    /// Least-squares-ish single cubic for tests: endpoints exact, handles
    /// along end tangents with the standard circle-arc handle length
    /// 4/3*tan(theta/4) * r (exact geometry, not a fitted constant).
    fn arc_cubic(r: f64, a0: f64, a1: f64) -> [Point; 4] {
        let h = 4.0 / 3.0 * ((a1 - a0) / 4.0).tan() * r;
        let (p0, p3) = (p(r * a0.cos(), r * a0.sin()), p(r * a1.cos(), r * a1.sin()));
        let t0 = p(-a0.sin(), a0.cos());
        let t1 = p(a1.sin(), -a1.cos());
        [p0, p(p0.x + h * t0.x, p0.y + h * t0.y), p(p3.x + h * t1.x, p3.y + h * t1.y), p3]
    }

    fn uniform_params(n: usize) -> Vec<f64> {
        (0..n).map(|i| i as f64 / (n - 1) as f64).collect()
    }

    #[test]
    fn derive_rejects_bad_steps() {
        assert!(Objective::derive(0.0).is_err());
        assert!(Objective::derive(-1.0).is_err());
        assert!(Objective::derive(f64::NAN).is_err());
        assert!(Objective::derive(f64::INFINITY).is_err());
        assert!(Objective::derive(1.0).is_ok());
    }

    #[test]
    fn straight_line_one_segment_beats_two() {
        // Exact straight run: both candidates have zero deviation and zero
        // curvature, so only the node price separates them.
        let samples: Vec<Point> = (0..=10).map(|i| p(i as f64, 0.0)).collect();
        let obj = Objective::derive(1.0).unwrap();
        let one = vec![CurveCandidate {
            controls: [p(0.0, 0.0), p(10.0 / 3.0, 0.0), p(20.0 / 3.0, 0.0), p(10.0, 0.0)],
            parameters: uniform_params(11),
            first: 0,
            last: 10,
        }];
        let two = vec![
            CurveCandidate {
                controls: [p(0.0, 0.0), p(5.0 / 3.0, 0.0), p(10.0 / 3.0, 0.0), p(5.0, 0.0)],
                parameters: uniform_params(6),
                first: 0,
                last: 5,
            },
            CurveCandidate {
                controls: [p(5.0, 0.0), p(20.0 / 3.0, 0.0), p(25.0 / 3.0, 0.0), p(10.0, 0.0)],
                parameters: uniform_params(6),
                first: 5,
                last: 10,
            },
        ];
        let s1 = obj.score(&samples, &one).unwrap();
        let s2 = obj.score(&samples, &two).unwrap();
        assert_eq!(s1.nodes, 2);
        assert_eq!(s2.nodes, 3);
        // Collinear cubic evaluation leaves a binary64 residue (~1e-15 in x),
        // so fidelity is ~1e-30 band^2, not exact 0; curvature is exact 0.
        assert!(s1.fidelity < 1e-24, "{}", s1.fidelity);
        assert!(s2.fidelity < 1e-24, "{}", s2.fidelity);
        assert_eq!(s1.curvature, 0.0);
        assert_eq!(s2.curvature, 0.0);
        assert!(s1.total < s2.total);
        assert_eq!(obj.compare(&s2, &s1), CandidateOrder::SecondBetter);
        assert_eq!(obj.compare(&s1, &s2), CandidateOrder::FirstBetter);
        assert_eq!(obj.compare(&s1, &s1), CandidateOrder::Equal);
    }

    #[test]
    fn arc_fit_beats_chord_on_fidelity_and_curvature() {
        // Quarter circle, radius 8 steps: the chord has zero curvature and a
        // sagitta of r*(1-cos45) ~ 2.34 steps = 4.7 bands of deviation; the
        // standard arc cubic tracks both position and curvature closely.
        let r = 8.0;
        let samples = arc(r, 0.0, std::f64::consts::FRAC_PI_2, 17);
        let obj = Objective::derive(1.0).unwrap();
        let chord = vec![CurveCandidate {
            controls: [samples[0], p(6.0, 2.0), p(2.0, 6.0), samples[16]],
            parameters: uniform_params(17),
            first: 0,
            last: 16,
        }];
        let fit = vec![CurveCandidate {
            controls: arc_cubic(r, 0.0, std::f64::consts::FRAC_PI_2),
            parameters: uniform_params(17),
            first: 0,
            last: 16,
        }];
        let sc = obj.score(&samples, &chord).unwrap();
        let sf = obj.score(&samples, &fit).unwrap();
        assert!(sc.max_deviation > 2.0, "chord sagitta {}", sc.max_deviation);
        assert!(sc.deviation_events > 0);
        assert_eq!(sf.deviation_events, 0, "arc fit stays inside the band");
        assert!(sc.curvature > sf.curvature, "chord {} vs arc {}", sc.curvature, sf.curvature);
        assert!(sf.total < sc.total);
    }

    #[test]
    fn scale_invariance_bit_exact_for_power_of_two() {
        let r = 8.0;
        let samples = arc(r, 0.1, 1.4, 13);
        let seg = |r: f64| {
            vec![CurveCandidate {
                controls: arc_cubic(r, 0.1, 1.4),
                parameters: uniform_params(13),
                first: 0,
                last: 12,
            }]
        };
        let s1 = Objective::derive(1.0).unwrap().score(&samples, &seg(r)).unwrap();
        let big: Vec<Point> = samples.iter().map(|q| p(q.x * 4.0, q.y * 4.0)).collect();
        let s2 = Objective::derive(4.0).unwrap().score(&big, &seg(r * 4.0)).unwrap();
        assert_eq!(s1.total.to_bits(), s2.total.to_bits());
        assert_eq!(s1.fidelity.to_bits(), s2.fidelity.to_bits());
        assert_eq!(s1.curvature.to_bits(), s2.curvature.to_bits());
        assert_eq!(s1.deviation_events, s2.deviation_events);
        assert!((s2.max_deviation - 4.0 * s1.max_deviation).abs() == 0.0);
    }

    #[test]
    fn scoring_is_deterministic() {
        let samples = arc(8.0, 0.0, 1.2, 21);
        let seg = vec![CurveCandidate {
            controls: arc_cubic(8.0, 0.0, 1.2),
            parameters: uniform_params(21),
            first: 0,
            last: 20,
        }];
        let obj = Objective::derive(1.5).unwrap();
        let a = obj.score(&samples, &seg).unwrap();
        let b = obj.score(&samples, &seg).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn deviation_events_count_outlier_samples() {
        // One sample pushed 3 steps off a straight run: fidelity = 9/band^2
        // with band 0.5 -> 36; exactly one deviation event.
        let mut samples: Vec<Point> = (0..=10).map(|i| p(i as f64, 0.0)).collect();
        samples[5] = p(5.0, 3.0);
        let obj = Objective::derive(1.0).unwrap();
        let seg = vec![CurveCandidate {
            controls: [p(0.0, 0.0), p(10.0 / 3.0, 0.0), p(20.0 / 3.0, 0.0), p(10.0, 0.0)],
            parameters: uniform_params(11),
            first: 0,
            last: 10,
        }];
        let s = obj.score(&samples, &seg).unwrap();
        assert_eq!(s.deviation_events, 1);
        assert_eq!(s.max_deviation, 3.0);
        assert_eq!(s.fidelity, 36.0);
    }

    #[test]
    fn layout_validation_is_typed() {
        let obj = Objective::derive(1.0).unwrap();
        let samples: Vec<Point> = (0..=4).map(|i| p(i as f64, 0.0)).collect();
        let seg = |first, last, n| CurveCandidate {
            controls: [p(0.0, 0.0), p(1.0, 0.0), p(3.0, 0.0), p(4.0, 0.0)],
            parameters: uniform_params(n),
            first,
            last,
        };
        assert_eq!(obj.score(&samples, &[]), Err(ObjectiveError::BadSegmentLayout("no segments")));
        assert_eq!(obj.score(&samples, &[seg(1, 4, 4)]), Err(ObjectiveError::BadSegmentLayout("first segment must start at sample 0")));
        assert_eq!(obj.score(&samples, &[seg(0, 3, 4)]), Err(ObjectiveError::BadSegmentLayout("last segment must end at final sample")));
        assert_eq!(obj.score(&samples, &[seg(0, 2, 3), seg(1, 4, 4)]), Err(ObjectiveError::BadSegmentLayout("segments must share endpoints")));
        assert_eq!(obj.score(&samples, &[seg(0, 4, 3)]), Err(ObjectiveError::ParameterCountMismatch));
        let mut bad = seg(0, 4, 5);
        bad.parameters[2] = 1.5;
        assert_eq!(obj.score(&samples, &[bad]), Err(ObjectiveError::ParameterOutOfRange));
        let mut nan = seg(0, 4, 5);
        nan.controls[1] = p(f64::NAN, 0.0);
        assert_eq!(obj.score(&samples, &[nan]), Err(ObjectiveError::NonFiniteInput));
        assert_eq!(obj.score(&samples[..1], &[seg(0, 0, 1)]), Err(ObjectiveError::EmptySamples));
    }

    #[test]
    fn node_price_is_one_band_squared_per_node() {
        // Declared convention: with zero deviation and zero curvature the
        // total equals the on-curve node count.
        let samples: Vec<Point> = (0..=6).map(|i| p(i as f64, 0.0)).collect();
        let obj = Objective::derive(2.0).unwrap();
        let seg = vec![CurveCandidate {
            controls: [p(0.0, 0.0), p(2.0, 0.0), p(4.0, 0.0), p(6.0, 0.0)],
            parameters: uniform_params(7),
            first: 0,
            last: 6,
        }];
        let s = obj.score(&samples, &seg).unwrap();
        assert_eq!(s.nodes, 2);
        assert_eq!(s.node_price, 2.0);
        assert_eq!(s.total, 2.0);
    }

    #[test]
    fn curvature_undefined_samples_are_counted_not_scored() {
        // A duplicate consecutive sample makes its triple degenerate.
        let mut samples: Vec<Point> = (0..=5).map(|i| p(i as f64, 0.0)).collect();
        samples[3] = samples[2];
        let obj = Objective::derive(1.0).unwrap();
        let seg = vec![CurveCandidate {
            controls: [p(0.0, 0.0), p(5.0 / 3.0, 0.0), p(10.0 / 3.0, 0.0), p(5.0, 0.0)],
            parameters: uniform_params(6),
            first: 0,
            last: 5,
        }];
        let s = obj.score(&samples, &seg).unwrap();
        assert!(s.curvature_undefined >= 1);
    }

    #[test]
    fn bench_tsv_parse_and_join() {
        let tsv = "fit_bench_v1\ncreated_unix\t42\noutcome\tok\ntotal_s\t1.200000\nphase\tfitting\t1.000000\nglyphs\t2\nglyph_cpu_sum_s\t0.950000\nglyph\tA\t0.250000\nglyph\tb\t0.700000\n";
        let rows = parse_bench_fit_seconds(tsv).unwrap();
        assert_eq!(rows, vec![("A".to_string(), 0.25), ("b".to_string(), 0.7)]);
        assert!(parse_bench_fit_seconds("wrong\n").is_err());
        assert!(parse_bench_fit_seconds("fit_bench_v1\nglyph\tA\n").is_err());
        assert!(parse_bench_fit_seconds("fit_bench_v1\nglyph\tA\txyz\n").is_err());
    }

    #[test]
    fn report_is_golden_and_labeled() {
        let obj = Objective::derive(1.0).unwrap();
        let samples: Vec<Point> = (0..=4).map(|i| p(i as f64, 0.0)).collect();
        let seg = vec![CurveCandidate {
            controls: [p(0.0, 0.0), p(4.0 / 3.0, 0.0), p(8.0 / 3.0, 0.0), p(4.0, 0.0)],
            parameters: uniform_params(5),
            first: 0,
            last: 4,
        }];
        let score = obj.score(&samples, &seg).unwrap();
        let rows = vec![
            GlyphMeasurement { name: "A".into(), score, fit_seconds: Some(0.25) },
            GlyphMeasurement { name: "g".into(), score, fit_seconds: None },
        ];
        let got = render_measurement_report(&MeasurementDomain::MonaStress, &rows);
        let want = "fit_objective_report_v1\n\
            domain\tmona-stress\n\
            glyphs\t2\n\
            glyph\tA\t2\t0.000000\t0.000\t0\t0.000000\t0.250000\n\
            glyph\tg\t2\t0.000000\t0.000\t0\t0.000000\t-\n\
            nodes_total\t4\n\
            deviation_events_total\t0\n";
        assert_eq!(got, want);
        let pn = render_measurement_report(&MeasurementDomain::PaulNewStress, &[]);
        assert!(pn.contains("domain\tpaul-new-stress\n"));
        assert!(pn.contains("glyphs\t0\n"));
    }

    #[test]
    fn compare_tie_breaks_by_nodes_then_deviation() {
        let obj = Objective::derive(1.0).unwrap();
        let base = ObjectiveScore {
            total: 5.0, fidelity: 1.0, curvature: 1.0, node_price: 3.0,
            nodes: 3, max_deviation: 0.5, deviation_events: 0,
            curvature_undefined: 0, source_step: 1.0,
        };
        let fewer_nodes = ObjectiveScore { nodes: 2, node_price: 2.0, fidelity: 2.0, ..base };
        assert_eq!(obj.compare(&base, &fewer_nodes), CandidateOrder::SecondBetter);
        let lower_dev = ObjectiveScore { max_deviation: 0.25, ..base };
        assert_eq!(obj.compare(&base, &lower_dev), CandidateOrder::SecondBetter);
        assert_eq!(obj.compare(&base, &base), CandidateOrder::Equal);
    }

    // ---- NE-1: EconomyObjective (W10 FitObjective impl) + accept_refit ----

    use crate::cubic_fit::{FitPolicy, RefitStop};
    use crate::fit_search::{ParameterMap, SearchContext};

    fn cand(controls: [Point; 4], parameters: Vec<f64>, plausible: bool, spans_used: usize) -> CandidateState {
        CandidateState {
            controls,
            parameters,
            max_squared_error: 0.0,
            dense: 0.0,
            plausible,
            spans_used,
            segments: vec![],
            d2_start: p(0.0, 0.0),
            d2_end: p(0.0, 0.0),
            map: ParameterMap::Centripetal,
            stop: RefitStop::BudgetExhausted,
            split_index: 0,
            converged: true,
        }
    }

    #[test]
    fn economy_objective_matches_objective_total_for_single_span() {
        let samples: Vec<Point> = (0..=10).map(|i| p(i as f64, 0.0)).collect();
        let controls = [p(0.0, 0.0), p(10.0 / 3.0, 0.0), p(20.0 / 3.0, 0.0), p(10.0, 0.0)];
        let params = uniform_params(11);
        let obj = Objective::derive(1.0).unwrap();
        let reference = obj
            .score(&samples, &[CurveCandidate { controls, parameters: params.clone(), first: 0, last: 10 }])
            .unwrap();
        let policy = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let ctx = SearchContext::new(&samples, p(1.0, 0.0), p(1.0, 0.0), &policy);
        let got = EconomyObjective::derive(1.0).unwrap().score(&cand(controls, params, true, 1), &ctx);
        // Single-span candidate: node price 2 from spans_used, identical total.
        assert_eq!(got, reference.total);
        assert_eq!(got, reference.fidelity + reference.curvature + 2.0);
    }

    #[test]
    fn economy_objective_implausible_and_unscorable_are_infinite() {
        let samples: Vec<Point> = (0..=10).map(|i| p(i as f64, 0.0)).collect();
        let controls = [p(0.0, 0.0), p(10.0 / 3.0, 0.0), p(20.0 / 3.0, 0.0), p(10.0, 0.0)];
        let policy = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let ctx = SearchContext::new(&samples, p(1.0, 0.0), p(1.0, 0.0), &policy);
        let obj = EconomyObjective::derive(1.0).unwrap();
        assert_eq!(obj.score(&cand(controls, uniform_params(11), false, 1), &ctx), f64::INFINITY);
        // Parameter count mismatch: unscorable, never a fabricated failure.
        assert_eq!(obj.score(&cand(controls, uniform_params(7), true, 1), &ctx), f64::INFINITY);
        // Derive rejects bad steps like Objective::derive.
        assert!(EconomyObjective::derive(0.0).is_err());
    }

    #[test]
    fn economy_objective_prices_spans_from_candidate() {
        // Identical geometry, different span claims: the fewer-span
        // candidate wins by exactly one node price (1 band^2).
        let samples: Vec<Point> = (0..=10).map(|i| p(i as f64, 0.0)).collect();
        let controls = [p(0.0, 0.0), p(10.0 / 3.0, 0.0), p(20.0 / 3.0, 0.0), p(10.0, 0.0)];
        let policy = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let ctx = SearchContext::new(&samples, p(1.0, 0.0), p(1.0, 0.0), &policy);
        let obj = EconomyObjective::derive(1.0).unwrap();
        let one = obj.score(&cand(controls, uniform_params(11), true, 1), &ctx);
        let two = obj.score(&cand(controls, uniform_params(11), true, 2), &ctx);
        assert_eq!(two - one, 1.0);
        assert!(one < two);
    }

    #[test]
    fn economy_objective_arc_fit_beats_chord() {
        // Same fixture as arc_fit_beats_chord_on_fidelity_and_curvature,
        // scored through the W10 contract.
        let r = 8.0;
        let samples = arc(r, 0.0, std::f64::consts::FRAC_PI_2, 17);
        let policy = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let ctx = SearchContext::new(&samples, p(1.0, 0.0), p(1.0, 0.0), &policy);
        let obj = EconomyObjective::derive(1.0).unwrap();
        let chord = obj.score(
            &cand([samples[0], p(6.0, 2.0), p(2.0, 6.0), samples[16]], uniform_params(17), true, 1),
            &ctx,
        );
        let fit = obj.score(
            &cand(arc_cubic(r, 0.0, std::f64::consts::FRAC_PI_2), uniform_params(17), true, 1),
            &ctx,
        );
        assert!(fit < chord, "fit {fit} must beat chord {chord}");
    }

    #[test]
    fn economy_objective_drives_open_gate_search() {
        // W9 <-> W10 contract end to end: the open-gate search runs both
        // incumbent map trajectories and selects under EconomyObjective.
        let samples = arc(8.0, 0.0, 1.2, 21);
        let policy = FitPolicy { squared_error: 4.0, max_refits: 16 };
        let obj = EconomyObjective::derive(1.0).unwrap();
        let (outcome, report) = crate::fit_search::fit_run_search_reported(
            &samples,
            p(1.2, -0.5),
            p(0.5, 1.2),
            &policy,
            &crate::fit_search::FIT_SEARCH_ON,
            &obj,
        );
        let report = report.expect("open gate always reports");
        assert_eq!(report.candidates_generated, 2);
        assert!(report.selected_score.is_finite());
        assert!(matches!(outcome, crate::cubic_fit::FitOutcome::Fitted { .. }));
    }

    #[test]
    fn accept_refit_rule_table() {
        use RefitVerdict::*;
        // Incumbent branch: strict error reduction, budget-free.
        assert_eq!(accept_refit(0.5, 3, 0.4, 3, 0.1), Some(ErrorReduced));
        // Error reduction classifies as ErrorReduced even with fewer segments.
        assert_eq!(accept_refit(0.5, 3, 0.4, 2, 0.1), Some(ErrorReduced));
        // Economy branch: fewer segments within budget (tie, rise, exact budget).
        assert_eq!(accept_refit(0.05, 3, 0.05, 2, 0.1), Some(EconomyWithinBudget));
        assert_eq!(accept_refit(0.05, 3, 0.09, 2, 0.1), Some(EconomyWithinBudget));
        assert_eq!(accept_refit(0.05, 3, 0.1, 2, 0.1), Some(EconomyWithinBudget));
        // Rejects.
        assert_eq!(accept_refit(0.05, 3, 0.2, 2, 0.1), None); // economy claim over budget
        assert_eq!(accept_refit(0.05, 3, 0.05, 3, 0.1), None); // equal state, no gain
        assert_eq!(accept_refit(0.05, 3, 0.2, 3, 0.1), None); // error-only worsening
        assert_eq!(accept_refit(0.05, 3, 0.05, 4, 0.1), None); // more segments
        // Non-finite or negative inputs never accept.
        assert_eq!(accept_refit(f64::NAN, 3, 0.0, 2, 0.1), None);
        assert_eq!(accept_refit(0.0, 3, f64::INFINITY, 2, 0.1), None);
        assert_eq!(accept_refit(0.0, 3, 0.0, 2, -0.1), None);
        assert_eq!(accept_refit(-0.1, 3, 0.0, 2, 0.1), None);
        assert_eq!(accept_refit(0.0, 3, f64::NAN, 2, f64::NAN), None);
    }

    #[test]
    fn accept_refit_reduces_to_incumbent_rule_when_segments_tie() {
        // Along one arc's Newton trajectory the segment count is constant,
        // so the rule must coincide with the incumbent error-only accept.
        for (prior, cand) in [(0.5, 0.4), (0.4, 0.5), (0.5, 0.5), (0.0, 0.0), (1.0, 0.999), (0.1, 0.1)] {
            let got = accept_refit(prior, 2, cand, 2, 0.1);
            assert_eq!(got, if cand < prior { Some(RefitVerdict::ErrorReduced) } else { None }, "prior={prior} cand={cand}");
        }
    }
}
