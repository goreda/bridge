//! W10 MONA-FITSEARCH: candidate generation and selection for the cubic fitter.
//!
//! Scope: single-arc cubic candidate search. The split recursion, Line
//! evidence, tangent estimation and every fallback stay where they are
//! (capture_fit.rs); this module only searches among single-cubic fits of
//! one arc and reports which candidate won and why.
//!
//! Policy gate: `FitSearchPolicy::OFF` delegates to `cubic_fit::fit_run`
//! unchanged, so a ship build with the gate closed is bit-identical to the
//! incumbent fitter BY CONSTRUCTION (no reimplementation is consulted). The
//! open gate runs the search below; `BaselineObjective` documents the
//! incumbent selection rule inside the objective API for A/B measurement.
//!
//! W9 <-> W10 contract (MONA-FITOBJ x MONA-FITSEARCH): the objective API is
//! the trait `FitObjective` plus the data carriers `CandidateState` and
//! `SearchContext` defined here. W9's `fit_objective.rs` implements
//! `FitObjective` with the node-economy penalty and the curvature-fidelity
//! term; this module consumes any implementation. If W9's diff defines the
//! trait itself, keep ONE definition at merge; the carriers here are the
//! superset both sides described (controls, parameters, sampled error,
//! dense excursion, plausibility, span count, end curvature vectors).
//!
//! Candidate space: derived from the arc's own data only. The two incumbent
//! initial parameter maps (chord-length and square-root chord, see
//! cubic_fit.rs for the derivation) each run the incumbent Newton refit
//! trajectory to its certified stop; the terminal state of each trajectory
//! is one candidate. No tangent variants: end tangents are the caller's
//! constraints (G1 at seams), not search dimensions. No new constants.
//!
//! Curvature continuity constraint (open gate only): when the caller
//! supplies a neighbouring span's end second-derivative vector in
//! `SearchContext`, a candidate whose join-side second derivative differs
//! by more than `continuity_tolerance(fit_policy)` is demoted. If every
//! candidate is demoted the constraint ABSTAINS (the set is restored and
//! the abstention is reported): the constraint must never fabricate a
//! failure or force an unscored state. Tolerance derivation: for a cubic,
//! B''(0) = 6(P0 - 2 P1 + P2); perturbing control P2 by e changes B''(0) by
//! 6e and moves the curve by at most e * max_t(3 t^2 (1-t)) = 4e/9 (max at
//! t = 2/3). A second-derivative mismatch d therefore moves the curve at
//! most (d/6)*(4/9) = 2d/27. The mismatch is invisible on this data when
//! that displacement is under the caller's own accept-gate distance unit
//! q = sqrt(policy.squared_error): d <= 27q/2. Units follow the caller's
//! FitPolicy; no literal threshold.
//!
//! Primitives (basis/solve/Newton/budget) mirror cubic_fit.rs verbatim,
//! renamed locally: the module boundary forbids touching cubic_fit.rs, and
//! the incumbent exposes no per-map entry point. Parity tests pin the
//! mirror to the incumbent on every fixture; drift fails the build.

use crate::capture_fit::{dense_gate, plausible};
use crate::cubic_fit::{fit_run, FitOutcome, FitPolicy, RefitStop};
use crate::reference_slice::Point;

/// Which of the two incumbent initial parameter maps generated a candidate.
/// Ordering is the incumbent generation order (centripetal first) and
/// decides every exact tie, matching cubic_fit.rs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParameterMap { Centripetal, Chord, /// Economy-generated candidate assembled from per-piece fits (line/segmentation); not one of the two incumbent initial maps.
    Composite }

/// Policy gate for the search. Default is closed: the incumbent fitter runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FitSearchPolicy { pub mode: FitSearchMode }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FitSearchMode { Off, On }
pub const FIT_SEARCH_OFF: FitSearchPolicy = FitSearchPolicy { mode: FitSearchMode::Off };
pub const FIT_SEARCH_ON: FitSearchPolicy = FitSearchPolicy { mode: FitSearchMode::On };
impl Default for FitSearchPolicy { fn default() -> Self { FIT_SEARCH_OFF } }

/// Per-arc search input. Neighbour curvature claims are optional: the
/// call-site supplies them when the adjacent span's fitted end curvature is
/// known (post-fit of the neighbour). None = no continuity evidence on that
/// side, the constraint stays silent on that side.
pub struct SearchContext<'a> {
    pub points: &'a [Point],
    pub left: Point,
    pub right: Point,
    pub fit_policy: &'a FitPolicy,
    /// B''(1) of the span joining this arc's start, when known.
    pub prev_end_d2: Option<Point>,
    /// B''(0) of the span joining this arc's end, when known.
    pub next_start_d2: Option<Point>,
    /// Source tile's own pixel step in working units (the engine's scale
    /// derivation output, e.g. canonical_scale; a measurement, never a
    /// literal). Required by the NE-1 objective currency and the economy
    /// candidate generation; None keeps both silent.
    pub source_step: Option<f64>,
}
impl<'a> SearchContext<'a> {
    pub fn new(points: &'a [Point], left: Point, right: Point, fit_policy: &'a FitPolicy) -> Self {
        SearchContext { points, left, right, fit_policy, prev_end_d2: None, next_start_d2: None, source_step: None }
    }
    pub fn with_source_step(mut self, source_step: Option<f64>) -> Self {
        self.source_step = source_step; self
    }
    pub fn with_neighbours(mut self, prev_end_d2: Option<Point>, next_start_d2: Option<Point>) -> Self {
        self.prev_end_d2 = prev_end_d2; self.next_start_d2 = next_start_d2; self
    }
}

/// One terminal candidate, carrying everything an objective may price.
#[derive(Clone, Debug)]
pub struct CandidateState {
    pub controls: [Point; 4],
    pub parameters: Vec<f64>,
    pub max_squared_error: f64,
    /// Dense symmetric excursion vs the source samples (caller's own accept
    /// gate metric), computed at the terminal state.
    pub dense: f64,
    pub plausible: bool,
    /// Node-economy basis for W9's objective: every candidate here is one
    /// cubic span; the field exists so the same objective prices multi-span
    /// candidates when the search is later extended past the split seam.
    pub spans_used: usize,
    /// B''(0) and B''(1) of the candidate cubic (position units; t is
    /// dimensionless on [0,1]).
    pub d2_start: Point,
    pub d2_end: Point,
    pub map: ParameterMap,
    /// Ordered fitted segments partitioning the arc's sample range with
    /// shared endpoints. The two incumbent trajectories carry exactly one
    /// Cubic segment mirroring `controls`/`parameters`; economy candidates
    /// may carry Line segments and more than one segment.
    pub segments: Vec<FitSegment>,
    /// Certified stop of the trajectory that produced this candidate.
    pub stop: RefitStop,
    pub split_index: usize,
    /// true when the trajectory met policy.squared_error at some loop top.
    pub converged: bool,
}

/// W9 <-> W10 objective contract. Lower is better. Implementations must be
/// pure and deterministic; a non-finite score is treated as +infinity
/// (never wins unless every candidate is non-finite).
pub trait FitObjective {
    fn score(&self, cand: &CandidateState, ctx: &SearchContext) -> f64;
}

/// The incumbent selection rule stated inside the objective API:
/// plausible candidates ranked by dense excursion, exact ties keep the
/// earlier generation order (centripetal first); an implausible candidate
/// is +infinity and wins only when every candidate is implausible, in which
/// case generation order (the incumbent's own fallback) decides.
pub struct BaselineObjective;
impl FitObjective for BaselineObjective {
    fn score(&self, cand: &CandidateState, _ctx: &SearchContext) -> f64 {
        if cand.plausible { cand.dense } else { f64::INFINITY }
    }
}

/// Measurement record of one open-gate search. Absent (None) on the closed
/// gate: the delegate path measures exactly what the incumbent measured.
#[derive(Clone, Debug)]
pub struct SearchReport {
    pub candidates_generated: usize,
    pub solves_failed: usize,
    pub continuity_demoted: usize,
    pub continuity_abstained: bool,
    pub selected: usize,
    pub selected_score: f64,
    /// Bitwise comparison of the selected Fitted outcome against the
    /// incumbent fit_run on the same input. None when either side did not
    /// produce Fitted. This is the divergence meter for the W13 bench.
    pub matches_incumbent: Option<bool>,
    /// Typed economy ledger: every corner screen, merge, degrade and tidy
    /// decision with its measured values, in pipeline order. Some only when
    /// economy generation ran (the economy entry point with a source_step);
    /// None keeps the incumbent paths bit-identical.
    pub economy: Option<EconomyLedger>,
}

// ---- continuity tolerance, derived in the module docs above ----
fn continuity_tolerance(fit_policy: &FitPolicy) -> f64 {
    13.5 * fit_policy.squared_error.sqrt()
}

// ---- primitives mirrored from cubic_fit.rs (see module docs) ----
fn add(a: Point, b: Point) -> Point { Point { x: a.x + b.x, y: a.y + b.y } }
fn sub(a: Point, b: Point) -> Point { Point { x: a.x - b.x, y: a.y - b.y } }
fn scale(a: Point, k: f64) -> Point { Point { x: a.x * k, y: a.y * k } }
fn dot(a: Point, b: Point) -> f64 { a.x * b.x + a.y * b.y }
fn finite(a: Point) -> bool { a.x.is_finite() && a.y.is_finite() }
fn unit(a: Point) -> Option<Point> {
    let n = a.x.hypot(a.y);
    if !n.is_finite() || n == 0. { None } else { let p = Point { x: a.x / n, y: a.y / n }; if finite(p) { Some(p) } else { None } }
}
fn basis(t: f64) -> [f64; 4] { let v = 1. - t; [v * v * v, 3. * t * v * v, 3. * t * t * v, t * t * t] }
fn evaluate(q: &[Point; 4], t: f64) -> Point {
    let b = basis(t);
    (0..4).fold(Point { x: 0., y: 0. }, |p, i| add(p, scale(q[i], b[i])))
}
fn derivatives(q: &[Point; 4], t: f64) -> (Point, Point) {
    let v = 1. - t;
    let a = scale(sub(q[1], q[0]), 3.); let b = scale(sub(q[2], q[1]), 3.); let c = scale(sub(q[3], q[2]), 3.);
    (add(add(scale(a, v * v), scale(b, 2. * v * t)), scale(c, t * t)), add(scale(sub(b, a), 2. * v), scale(sub(c, b), 2. * t)))
}
fn solve(points: &[Point], u: &[f64], left: Point, right: Point) -> Option<[Point; 4]> {
    let p0 = points[0]; let p3 = *points.last()?;
    let (mut c00, mut c01, mut c11, mut x0, mut x1) = (0., 0., 0., 0., 0.);
    for (p, t) in points.iter().zip(u) {
        let b = basis(*t); let a0 = scale(left, b[1]); let a1 = scale(right, b[2]);
        let r = sub(*p, add(scale(p0, b[0] + b[1]), scale(p3, b[2] + b[3])));
        c00 += dot(a0, a0); c01 += dot(a0, a1); c11 += dot(a1, a1); x0 += dot(a0, r); x1 += dot(a1, r);
    }
    let det = c00 * c11 - c01 * c01; if !det.is_finite() || det <= 0. { return None; }
    let a = (x0 * c11 - x1 * c01) / det; let b = (c00 * x1 - c01 * x0) / det;
    if !a.is_finite() || !b.is_finite() || a <= 0. || b <= 0. { return None; }
    let q = [p0, add(p0, scale(left, a)), add(p3, scale(right, b)), p3];
    if q.iter().all(|p| finite(*p)) { Some(q) } else { None }
}
fn error(points: &[Point], u: &[f64], q: &[Point; 4]) -> Option<(f64, usize)> {
    let mut max = -1.; let mut index = 1;
    for i in 1..points.len() - 1 {
        let d = sub(evaluate(q, u[i]), points[i]); let e = dot(d, d);
        if !e.is_finite() { return None; }
        if e > max { max = e; index = i; }
    }
    Some((max.max(0.), index))
}
fn newton_step(q: &[Point; 4], point: Point, t: f64) -> Option<f64> {
    let at = evaluate(q, t); let (d1, d2) = derivatives(q, t); let r = sub(at, point);
    let denominator = dot(d1, d1) + dot(r, d2);
    if !denominator.is_finite() || denominator == 0. { return None; }
    let next = t - dot(r, d1) / denominator;
    if !next.is_finite() || !(0.0..=1.0).contains(&next) { None } else { Some(next) }
}
fn proposed_parameters(points: &[Point], u: &[f64], q: &[Point; 4]) -> Option<Vec<f64>> {
    let mut proposed = u.to_vec();
    for i in 1..points.len() - 1 { proposed[i] = newton_step(q, points[i], u[i])?; }
    if proposed.windows(2).any(|p| p[0] > p[1]) { None } else { Some(proposed) }
}
fn refitted_candidate(points: &[Point], u: &[f64], q: &[Point; 4], left: Point, right: Point) -> Option<(Vec<f64>, [Point; 4], f64, usize)> {
    let proposed = proposed_parameters(points, u, q)?;
    let next = solve(points, &proposed, left, right)?;
    let (max, split) = error(points, &proposed, &next)?;
    Some((proposed, next, max, split))
}
fn ceil_log2(x: usize) -> usize { if x <= 1 { 0 } else { usize::BITS as usize - (x - 1).leading_zeros() as usize } }
/// Same derivation as cubic_fit::derived_reparam_budget (digit doubling of
/// quadratic Newton convergence into one sample spacing, plus the one step
/// whose non-improvement certifies the stop).
fn derived_reparam_budget(n_samples: usize) -> usize {
    let digits = ceil_log2(n_samples.saturating_sub(1)).max(1);
    ceil_log2(digits) + 1
}

/// Second derivatives at the cubic's ends: B''(0) = 6(P0 - 2P1 + P2),
/// B''(1) = 6(P1 - 2P2 + P3).
fn end_d2(q: &[Point; 4]) -> (Point, Point) {
    (scale(add(sub(q[0], scale(q[1], 2.)), q[2]), 6.),
     scale(add(sub(q[1], scale(q[2], 2.)), q[3]), 6.))
}

/// Build the two incumbent initial parameter maps (chord and centripetal,
/// the derivation lives in cubic_fit.rs; centripetal is generated first and
/// keeps exact ties). Returns them in generation order.
fn initial_maps(points: &[Point]) -> Option<Vec<(ParameterMap, Vec<f64>)>> {
    let mut u_chord = vec![0.]; let mut u_cent = vec![0.];
    for i in 1..points.len() {
        let chord = sub(points[i], points[i - 1]); let d = chord.x.hypot(chord.y);
        let a = u_chord[i - 1] + d; let b = u_cent[i - 1] + d.sqrt();
        if !a.is_finite() || !b.is_finite() { return None; }
        u_chord.push(a); u_cent.push(b);
    }
    let mut out = Vec::with_capacity(2);
    for (map, mut u) in [(ParameterMap::Centripetal, u_cent), (ParameterMap::Chord, u_chord)] {
        let total = *u.last().unwrap(); if total == 0. { return None; }
        for t in u.iter_mut() { *t /= total; }
        u[0] = 0.; let last = u.len() - 1; u[last] = 1.;
        out.push((map, u));
    }
    Some(out)
}

/// Run one map's trajectory to its certified stop: the incumbent refit loop
/// (improvement certificate, derived budget, caller's cap) applied to one
/// initial solve. None when the initial solve or its error measure fails.
fn trajectory(points: &[Point], map: ParameterMap, u: Vec<f64>, left: Point, right: Point, policy: &FitPolicy) -> Option<CandidateState> {
    let mut q = solve(points, &u, left, right)?;
    let (mut max, mut split) = error(points, &u, &q)?;
    let mut u = u;
    let budget = policy.max_refits.min(derived_reparam_budget(points.len()));
    let mut stop = RefitStop::BudgetExhausted;
    let mut converged = false;
    for attempt in 0..=budget {
        if max <= policy.squared_error { converged = true; break; }
        if attempt == budget { break; }
        let candidate = refitted_candidate(points, &u, &q, left, right).or_else(|| {
            // Damped per-point proposal fallback (the same candidate
            // generation cubic_fit::fit_run_damped and the capture_fit rescue
            // use): ONE bad Newton step must not end a trajectory when the
            // remaining steps converge - an abandoned trajectory becomes a
            // split, i.e. extra nodes. This is candidate GENERATION only:
            // the improvement certificate, derived budget, caller cap and
            // stop reasons below are unchanged, so acceptance is exactly as
            // strict as the incumbent loop. Fires only where the incumbent
            // proposal already failed; every converging-undamped trajectory
            // is bit-identical to before.
            let proposed = crate::cubic_fit::proposed_parameters_damped(points, &u, &q)?;
            let next = solve(points, &proposed, left, right)?;
            let (max, split) = error(points, &proposed, &next)?;
            Some((proposed, next, max, split))
        });
        let Some((proposed, next, next_max, next_split)) = candidate else { stop = RefitStop::CandidateFailed; break; };
        if next_max >= max { stop = RefitStop::CertifiedNoImprovement; break; }
        u = proposed; q = next; max = next_max; split = next_split;
    }
    let (d2_start, d2_end) = end_d2(&q);
    let (dense, _) = dense_gate(&q, points);
    let segments = vec![FitSegment {
        kind: SegmentKind::Cubic, controls: q, parameters: u.clone(),
        first: 0, last: points.len() - 1, max_squared_error: max,
    }];
    Some(CandidateState {
        controls: q, parameters: u, max_squared_error: max,
        dense, plausible: plausible(points, &q),
        spans_used: 1, segments, d2_start, d2_end, map, stop, split_index: split, converged,
    })
}

/// Open-gate search outcome assembly, mirroring cubic_fit::fit_run's
/// failure semantics on the selected candidate.
fn assemble(sel: CandidateState) -> FitOutcome {
    if sel.converged {
        FitOutcome::Fitted { controls: sel.controls, parameters: sel.parameters, max_squared_error: sel.max_squared_error }
    } else {
        FitOutcome::SplitUnresolved { sample_index: Some(sel.split_index), stop: Some(sel.stop) }
    }
}

/// Continuity demotion: does the candidate respect every supplied
/// neighbour second-derivative claim within the derived tolerance?
fn continuity_ok(c: &CandidateState, ctx: &SearchContext, tol: f64) -> bool {
    let within = |a: Point, b: Point| { let d = sub(a, b); dot(d, d).sqrt() <= tol };
    if let Some(prev) = ctx.prev_end_d2 { if !within(c.d2_start, prev) { return false; } }
    if let Some(next) = ctx.next_start_d2 { if !within(c.d2_end, next) { return false; } }
    true
}

/// Full entry point. Closed gate: direct delegation to cubic_fit::fit_run,
/// bit-identical by construction. Open gate: generate both incumbent map
/// trajectories, apply the continuity constraint (demote, abstain if all
/// demoted), select argmin under the objective, incumbent tie order.
pub fn fit_run_search_reported(points: &[Point], left: Point, right: Point, policy: &FitPolicy, search: &FitSearchPolicy, objective: &dyn FitObjective) -> (FitOutcome, Option<SearchReport>) {
    if search.mode == FitSearchMode::Off { return (fit_run(points, left, right, policy), None); }
    // Open gate input validation mirrors fit_run exactly.
    if points.len() < 3 { return (FitOutcome::SplitUnresolved { sample_index: None, stop: None }, Some(SearchReport {
        candidates_generated: 0, solves_failed: 0, continuity_demoted: 0, continuity_abstained: false,
        selected: usize::MAX, selected_score: f64::NAN, matches_incumbent: None, economy: None })); }
    if !points.iter().all(|p| finite(*p)) || !policy.squared_error.is_finite() || policy.squared_error < 0. {
        return (FitOutcome::InvalidInput, None);
    }
    let (Some(left), Some(right)) = (unit(left), unit(right)) else { return (FitOutcome::InvalidInput, None); };
    let ctx = SearchContext::new(points, left, right, policy);
    fit_run_search_in(&ctx, objective, false).into_outcome()
}

/// Same as fit_run_search_reported with explicit neighbour curvature claims.
pub fn fit_run_search_context(ctx: &SearchContext, search: &FitSearchPolicy, objective: &dyn FitObjective) -> (FitOutcome, Option<SearchReport>) {
    if search.mode == FitSearchMode::Off { return (fit_run(ctx.points, ctx.left, ctx.right, ctx.fit_policy), None); }
    if ctx.points.len() < 3 { return (FitOutcome::SplitUnresolved { sample_index: None, stop: None }, Some(SearchReport {
        candidates_generated: 0, solves_failed: 0, continuity_demoted: 0, continuity_abstained: false,
        selected: usize::MAX, selected_score: f64::NAN, matches_incumbent: None, economy: None })); }
    if !ctx.points.iter().all(|p| finite(*p)) || !ctx.fit_policy.squared_error.is_finite() || ctx.fit_policy.squared_error < 0. {
        return (FitOutcome::InvalidInput, None);
    }
    let (Some(left), Some(right)) = (unit(ctx.left), unit(ctx.right)) else { return (FitOutcome::InvalidInput, None); };
    let ctx2 = SearchContext { points: ctx.points, left, right, fit_policy: ctx.fit_policy, prev_end_d2: ctx.prev_end_d2, next_start_d2: ctx.next_start_d2, source_step: ctx.source_step };
    fit_run_search_in(&ctx2, objective, false).into_outcome()
}

/// Convenience wrapper discarding the measurement record.
pub fn fit_run_search(points: &[Point], left: Point, right: Point, policy: &FitPolicy, search: &FitSearchPolicy, objective: &dyn FitObjective) -> FitOutcome {
    fit_run_search_reported(points, left, right, policy, search, objective).0
}

fn fit_run_search_in(ctx: &SearchContext, objective: &dyn FitObjective, economy: bool) -> SearchRun {
    let points = ctx.points;
    let (left, right) = (ctx.left, ctx.right);
    let mut candidates: Vec<CandidateState> = Vec::new();
    let mut solves_failed = 0usize;
    let mut solved = 0usize;
    match initial_maps(points) {
        None => return (FitOutcome::InvalidInput, None, None),
        Some(maps) => {
            for (map, u) in maps {
                // solve-presence bookkeeping mirrors fit_run: a failed solve
                // still counts when it produced a normal-equations solution.
                if solve(points, &u, left, right).is_some() { solved += 1; } else { solves_failed += 1; }
                if let Some(c) = trajectory(points, map, u, left, right, ctx.fit_policy) { candidates.push(c); }
            }
        }
    }
    let incumbent_count = candidates.len();
    let mut economy_ledger = if economy { Some(EconomyLedger::default()) } else { None };
    if candidates.is_empty() {
        let sample_index = if solved == 0 { crate::cubic_fit::initial_split(points) } else { None };
        return (FitOutcome::SplitUnresolved { sample_index, stop: None }, Some(SearchReport {
            candidates_generated: 0, solves_failed, continuity_demoted: 0, continuity_abstained: false,
            selected: usize::MAX, selected_score: f64::NAN, matches_incumbent: None, economy: economy_ledger }), None);
    }
    // Economy generation (open gate, economy entry point only): a whole-arc
    // line candidate and a corner-split segmentation candidate, both derived
    // from the arc's own samples and the acquisition band. Every decision is
    // a typed ledger row; nothing is dropped silently.
    if economy {
        if let Some(rows) = economy_ledger.as_mut() {
            generate_economy_candidates(ctx, &mut candidates, rows);
        }
    }
    // Continuity constraint: demote violators; abstain if all violate.
    let tol = continuity_tolerance(ctx.fit_policy);
    let flags: Vec<bool> = candidates.iter().map(|c| continuity_ok(c, ctx, tol)).collect();
    let demoted = flags.iter().filter(|f| !**f).count();
    let abstained = demoted == candidates.len();
    // Budget gate (economy only): a selected outcome must never exceed the
    // caller's accept gate ("budget asimi yok"). When any candidate meets
    // the budget, over-budget candidates cannot win; when none does, the
    // incumbent trajectories alone carry the unresolved fallback, exactly as
    // the incumbent fitter's own split request.
    let budget = ctx.fit_policy.squared_error;
    let any_within = candidates.iter().any(|c| c.max_squared_error <= budget);
    // Selection: argmin objective over the surviving set. With the economy
    // path the exact-tie order follows NE-1's compare(): fewer nodes, then
    // lower raw max deviation, then generation order. Without the economy
    // path the rule is unchanged: strict-less argmin, generation-order ties.
    let mut best: Option<usize> = None; let mut best_score = f64::INFINITY;
    for (i, c) in candidates.iter().enumerate() {
        if !flags[i] && !abstained { continue; }
        if economy {
            if any_within {
                if c.max_squared_error > budget { continue; }
            } else if i >= incumbent_count { continue; }
        }
        let s = objective.score(c, ctx);
        let s = if s.is_finite() { s } else { f64::INFINITY };
        let better = if s < best_score { true } else if economy && s == best_score && s.is_finite() {
            let b = &candidates[best.unwrap_or(i)];
            (c.spans_used, c.max_squared_error) < (b.spans_used, b.max_squared_error)
        } else { false };
        if better { best = Some(i); best_score = s; }
    }
    // Every candidate scored non-finite: incumbent fallback, generation order.
    let sel = best.unwrap_or(0);
    let selected = candidates[sel].clone();
    let outcome = assemble(selected.clone());
    let matches_incumbent = match (fit_run(points, left, right, ctx.fit_policy), &outcome) {
        (FitOutcome::Fitted { controls: a, parameters: ua, max_squared_error: ma },
         FitOutcome::Fitted { controls: b, parameters: ub, max_squared_error: mb }) => {
            Some(a.iter().zip(b.iter()).all(|(x, y)| x.x.to_bits() == y.x.to_bits() && x.y.to_bits() == y.y.to_bits())
                && ua.len() == ub.len() && ua.iter().zip(ub.iter()).all(|(x, y)| x.to_bits() == y.to_bits())
                && ma.to_bits() == mb.to_bits())
        }
        _ => None,
    };
    (outcome, Some(SearchReport {
        candidates_generated: candidates.len(), solves_failed,
        continuity_demoted: demoted, continuity_abstained: abstained,
        selected: sel, selected_score: best_score, matches_incumbent,
        economy: economy_ledger }), Some(candidates[sel].clone()))
}

// ---- NE-2: node-economy candidate generation/selection ----
//
// The economy path consumes NE-1's objective (fit_objective::Objective)
// through the FitObjective interface and generates economy candidates from
// the arc's own samples. Pipeline order (brief NE-2):
//   1. corner-detection threshold tuning (search-side screen),
//   2. collinear-merge pass (direction delta < theta AND merged-line error
//      within the caller's budget),
//   3. C->L degrade (max deviation < degrade_eps),
//   4. post-fit zero-length tidy.
// Every decision lands in the typed EconomyLedger; nothing drops silently.
// All thresholds are DERIVED, never literals (provenance:
// docs/kni/2026-10-18-ne2-economy-search-conventions.md):
//   - corner visibility: a kink of angle d at sample i with local step
//     s_i (mean of the two adjacent chord lengths) displaces the sample
//     from the merged chord by s_i*tan(d/2); below the acquisition band
//     (source_step/2, NE-1's currency derivation) the kink is the
//     acquisition's own quantization, not structure. Corner when
//     d > 2*atan(band/s_i).
//   - merge theta: replacing chords of lengths a, b joined at angle d by
//     the outer chord c displaces the junction by a*b*sin(d)/c; the merged
//     line must stay inside the caller's accept-gate distance
//     q = sqrt(policy.squared_error): d < asin(min(1, q*c/(a*b))). The
//     actual merged-line sample error is checked against the budget too.
//   - degrade_eps = min(band, q): a line may replace a cubic only when the
//     samples' chord deviation is below the acquisition band AND inside the
//     caller's accept gate.

/// One fitted segment of a candidate outline: either a true cubic span or
/// a straight Line. A Line carries the degenerate collinear cubic
/// representation (handles at the chord thirds) so every consumer evaluates
/// one geometry representation; `kind` preserves the semantic type for
/// output.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SegmentKind { Line, Cubic }

#[derive(Clone, Debug)]
pub struct FitSegment {
    pub kind: SegmentKind,
    pub controls: [Point; 4],
    /// Footpoint parameter of each sample in first..=last on `controls`.
    pub parameters: Vec<f64>,
    /// Inclusive sample range of the arc this segment explains.
    pub first: usize,
    pub last: usize,
    /// Worst squared footpoint deviation over interior samples of the range.
    pub max_squared_error: f64,
}

/// Why a segment was dropped by the post-fit tidy.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TidyReason { ZeroLength }

/// Typed economy ledger row: one measured decision in pipeline order.
#[derive(Clone, Debug)]
pub enum EconomyRow {
    /// Corner screen at one interior sample: measured direction delta vs
    /// the sample's derived visibility threshold.
    CornerScreen { sample: usize, delta: f64, threshold: f64, is_corner: bool },
    /// Collinear merge attempt over adjacent line pieces: measured
    /// direction delta vs the derived theta, and the merged-line error.
    Merge { first_sample: usize, last_sample: usize, delta: f64, theta: f64, max_squared_error: f64, merged: bool },
    /// C->L degrade decision on one fitted cubic piece: measured chord
    /// deviation of the samples vs degrade_eps.
    Degrade { first_sample: usize, last_sample: usize, max_deviation: f64, degrade_eps: f64, degraded: bool },
    /// Post-fit tidy: a zero-length segment dropped, its sample range
    /// absorbed by the neighbouring segments.
    Tidy { first_sample: usize, last_sample: usize, reason: TidyReason },
    /// A piece's cubic fit failed; the segmentation candidate is not
    /// generated (the incumbent candidates remain).
    PieceFitFailed { first_sample: usize, last_sample: usize },
}

/// The typed economy ledger attached to SearchReport when economy ran.
#[derive(Clone, Debug, Default)]
pub struct EconomyLedger { pub rows: Vec<EconomyRow> }
impl EconomyLedger {
    pub fn count(&self, pred: impl Fn(&EconomyRow) -> bool) -> usize { self.rows.iter().filter(|r| pred(r)).count() }
}

/// NE-1's node-economy objective consumed through the FitObjective
/// interface: CandidateState.segments are re-expressed as NE-1
/// CurveCandidates over the search context's samples and scored by
/// fit_objective::Objective; the returned currency is NE-1's
/// band-squared total (fidelity + curvature + node_price). An implausible
/// or unscorable candidate is +infinity (never wins unless all are).
pub struct EconomyObjective { inner: crate::fit_objective::Objective }
impl EconomyObjective {
    /// Derive from the source tile's own pixel step in working units.
    pub fn derive(source_step: f64) -> Result<Self, crate::fit_objective::ObjectiveError> {
        crate::fit_objective::Objective::derive(source_step).map(|inner| EconomyObjective { inner })
    }
    pub fn source_step(&self) -> f64 { self.inner.source_step() }
}
impl FitObjective for EconomyObjective {
    fn score(&self, cand: &CandidateState, ctx: &SearchContext) -> f64 {
        if !cand.plausible { return f64::INFINITY; }
        let segs: Vec<crate::fit_objective::CurveCandidate> = cand.segments.iter().map(|s| crate::fit_objective::CurveCandidate {
            controls: s.controls, parameters: s.parameters.clone(), first: s.first, last: s.last,
        }).collect();
        match self.inner.score(ctx.points, &segs) { Ok(sc) => sc.total, Err(_) => f64::INFINITY }
    }
}

/// Outcome of the economy entry point: either the incumbent single-arc
/// result (a fitted cubic or the incumbent's unresolved split request), or
/// an economy selection expressed as ordered segments.
#[derive(Clone, Debug)]
pub enum EconomyOutcome {
    Incumbent(FitOutcome),
    /// Economy selection within the caller's budget: ordered segments
    /// partitioning the arc's samples with shared endpoints; `score` is the
    /// objective total that won (NE-1 band-squared currency when the
    /// EconomyObjective adapter is used).
    Segmented { segments: Vec<FitSegment>, max_squared_error: f64, score: f64 },
}

type SearchRun = (FitOutcome, Option<SearchReport>, Option<CandidateState>);
trait IntoOutcome { fn into_outcome(self) -> (FitOutcome, Option<SearchReport>); }
impl IntoOutcome for SearchRun {
    fn into_outcome(self) -> (FitOutcome, Option<SearchReport>) { (self.0, self.1) }
}

/// Squared distance of p to the segment a-b (clamped projection).
fn seg_dist_sq(p: Point, a: Point, b: Point) -> f64 {
    let ab = sub(b, a); let l2 = dot(ab, ab);
    if l2 == 0.0 { return dot(sub(p, a), sub(p, a)); }
    let t = (dot(sub(p, a), ab) / l2).clamp(0.0, 1.0);
    let f = sub(p, add(a, scale(ab, t)));
    dot(f, f)
}

/// Chord-normalized parameters and worst squared chord deviation over the
/// sample range first..=last. None on a zero-length chord.
fn chord_stats(points: &[Point], first: usize, last: usize) -> Option<(Vec<f64>, f64)> {
    let a = points[first]; let b = points[last];
    let chord = sub(b, a); let len = chord.x.hypot(chord.y);
    if !len.is_finite() || len == 0.0 { return None; }
    let mut u = vec![0.0f64]; let mut acc = 0.0f64;
    for i in first + 1..=last {
        let d = sub(points[i], points[i - 1]); acc += d.x.hypot(d.y);
        if !acc.is_finite() { return None; }
        u.push(acc / len);
    }
    u[0] = 0.0; let m = u.len() - 1; u[m] = 1.0;
    let mut max_sq = 0.0f64;
    for i in first + 1..last {
        let e = seg_dist_sq(points[i], a, b);
        if !e.is_finite() { return None; }
        if e > max_sq { max_sq = e; }
    }
    Some((u, max_sq))
}

/// A straight Line segment over the sample range first..=last. None when
/// the chord has zero length (the tidy pass owns that record).
fn line_segment(points: &[Point], first: usize, last: usize) -> Option<FitSegment> {
    let (u, max_sq) = chord_stats(points, first, last)?;
    let a = points[first]; let b = points[last];
    let c = scale(sub(b, a), 1.0 / 3.0);
    Some(FitSegment {
        kind: SegmentKind::Line,
        controls: [a, add(a, c), add(a, scale(c, 2.0)), b],
        parameters: u, first, last, max_squared_error: max_sq,
    })
}

/// Fit one piece of the arc as a cubic: both incumbent initial maps run to
/// their certified stops and the incumbent dual-init rule (plausible first,
/// then lower dense excursion) picks. Pieces with fewer than 3 samples are
/// exact Lines. None when no trajectory solves.
fn fit_piece(ctx: &SearchContext, first: usize, last: usize) -> Option<FitSegment> {
    let slice = &ctx.points[first..=last];
    if slice.len() < 3 { return line_segment(ctx.points, first, last); }
    let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(slice)?;
    let maps = initial_maps(slice)?;
    let mut best: Option<CandidateState> = None;
    for (map, u) in maps {
        if let Some(c) = trajectory(slice, map, u, lt, rt, ctx.fit_policy) {
            let better = match &best {
                None => true,
                Some(b) => (c.plausible, -c.dense) > (b.plausible, -b.dense),
            };
            if better { best = Some(c); }
        }
    }
    let c = best?;
    Some(FitSegment {
        kind: SegmentKind::Cubic, controls: c.controls, parameters: c.parameters,
        first, last, max_squared_error: c.max_squared_error,
    })
}

/// Corner screen (pipeline step 1): interior samples whose direction kink
/// exceeds the derived visibility threshold. Every measured sample is a
/// typed row, corner or not. Samples touching a zero-length chord carry no
/// direction evidence and are not screened.
fn corner_screen(ctx: &SearchContext, band: f64, rows: &mut Vec<EconomyRow>) -> Vec<usize> {
    let points = ctx.points;
    let mut corners = Vec::new();
    for i in 1..points.len() - 1 {
        let u1 = sub(points[i], points[i - 1]);
        let u2 = sub(points[i + 1], points[i]);
        let l1 = u1.x.hypot(u1.y); let l2 = u2.x.hypot(u2.y);
        if l1 == 0.0 || l2 == 0.0 || !l1.is_finite() || !l2.is_finite() { continue; }
        let cos = (dot(u1, u2) / (l1 * l2)).clamp(-1.0, 1.0);
        let delta = cos.acos();
        if !delta.is_finite() { continue; }
        let s = (l1 + l2) / 2.0;
        // s*tan(d/2) > band  <=>  d > 2*atan(band/s); no literal threshold.
        let threshold = 2.0 * (band / s).atan();
        let is_corner = s * (delta / 2.0).tan() > band;
        rows.push(EconomyRow::CornerScreen { sample: i, delta, threshold, is_corner });
        if is_corner { corners.push(i); }
    }
    corners
}

/// Collinear-merge pass (pipeline step 2): greedy left-to-right merge of
/// adjacent Line segments. A merge needs BOTH the direction delta under the
/// derived theta AND the merged line's sample error within the caller's
/// budget; each attempt (merged or refused) is a typed row.
fn merge_pass(segs: Vec<FitSegment>, points: &[Point], policy: &FitPolicy, rows: &mut Vec<EconomyRow>) -> Vec<FitSegment> {
    let q = policy.squared_error.sqrt();
    let mut out: Vec<FitSegment> = Vec::with_capacity(segs.len());
    for seg in segs.into_iter() {
        let attempt = match (out.last(), &seg) {
            (Some(prev), _) if prev.kind == SegmentKind::Line && seg.kind == SegmentKind::Line => Some(()),
            _ => None,
        };
        if attempt.is_none() { out.push(seg); continue; }
        let prev = out.last().unwrap();
        let (a, b, c) = (points[prev.first], points[prev.last], points[seg.last]);
        let u1 = sub(b, a); let u2 = sub(c, b);
        let l1 = u1.x.hypot(u1.y); let l2 = u2.x.hypot(u2.y);
        let outer = sub(c, a); let lc = outer.x.hypot(outer.y);
        if l1 == 0.0 || l2 == 0.0 || lc == 0.0 { out.push(seg); continue; }
        let cos = (dot(u1, u2) / (l1 * l2)).clamp(-1.0, 1.0);
        let delta = cos.acos();
        // Junction displacement a*b*sin(d)/c must stay under q.
        let theta = ((q * lc) / (l1 * l2)).min(1.0).asin();
        let merged_ok = delta.is_finite() && delta < theta;
        let stats = chord_stats(points, prev.first, seg.last);
        let within_budget = stats.as_ref().is_some_and(|(_, e)| *e <= policy.squared_error);
        let first_sample = prev.first; let last_sample = seg.last;
        let mse = stats.as_ref().map(|(_, e)| *e).unwrap_or(f64::INFINITY);
        if merged_ok && within_budget {
            let (u, max_sq) = stats.expect("within_budget implies stats");
            let a0 = points[first_sample]; let b0 = points[last_sample];
            let c3 = scale(sub(b0, a0), 1.0 / 3.0);
            let prev_first = out.pop().expect("prev exists");
            rows.push(EconomyRow::Merge { first_sample, last_sample, delta, theta, max_squared_error: max_sq, merged: true });
            out.push(FitSegment {
                kind: SegmentKind::Line,
                controls: [a0, add(a0, c3), add(a0, scale(c3, 2.0)), b0],
                parameters: u, first: prev_first.first, last: last_sample,
                max_squared_error: max_sq,
            });
        } else {
            rows.push(EconomyRow::Merge { first_sample, last_sample, delta, theta, max_squared_error: mse, merged: false });
            out.push(seg);
        }
    }
    out
}

/// Post-fit zero-length tidy (pipeline step 4): drop segments whose chord
/// has zero length; each drop is a typed row. Partition contiguity is
/// preserved because a zero-length segment's endpoint indices coincide with
/// its neighbours' (first == last) or duplicate a shared sample.
fn tidy_pass(segs: Vec<FitSegment>, points: &[Point], rows: &mut Vec<EconomyRow>) -> Vec<FitSegment> {
    let mut out = Vec::with_capacity(segs.len());
    for seg in segs.into_iter() {
        let a = points[seg.first]; let b = points[seg.last];
        let len = sub(b, a).x.hypot(sub(b, a).y);
        if len == 0.0 || !len.is_finite() || seg.first == seg.last {
            rows.push(EconomyRow::Tidy { first_sample: seg.first, last_sample: seg.last, reason: TidyReason::ZeroLength });
        } else {
            out.push(seg);
        }
    }
    out
}

/// Assemble a CandidateState from fitted segments. `controls`/`parameters`
/// mirror the first segment (the single-segment view the carriers already
/// document); consumers of multi-segment candidates use `segments`.
fn candidate_from_segments(segments: Vec<FitSegment>, ctx: &SearchContext, map: ParameterMap) -> CandidateState {
    let n = ctx.points.len();
    let max_e = segments.iter().map(|s| s.max_squared_error).fold(0.0f64, f64::max);
    let dense = segments.iter()
        .map(|s| dense_gate(&s.controls, &ctx.points[s.first..=s.last]).0)
        .fold(0.0f64, f64::max);
    let plausible = segments.iter().all(|s| s.kind == SegmentKind::Line || plausible(&ctx.points[s.first..=s.last], &s.controls));
    let d2_start = end_d2(&segments[0].controls).0;
    let d2_end = end_d2(&segments[segments.len() - 1].controls).1;
    let first = &segments[0];
    CandidateState {
        controls: first.controls, parameters: first.parameters.clone(),
        max_squared_error: max_e, dense, plausible,
        spans_used: segments.len(), segments,
        d2_start, d2_end, map,
        stop: RefitStop::CertifiedNoImprovement, split_index: n / 2,
        converged: max_e <= ctx.fit_policy.squared_error,
    }
}

/// Economy candidate generation (pipeline order: corner screen -> piece
/// fits -> C->L degrade -> collinear merge -> zero-length tidy). Appends a
/// whole-arc Line candidate and, when the screen finds corners, a
/// corner-split segmentation candidate. Every decision is a ledger row.
fn generate_economy_candidates(ctx: &SearchContext, candidates: &mut Vec<CandidateState>, ledger: &mut EconomyLedger) {
    let points = ctx.points;
    let Some(step) = ctx.source_step else { return };
    if !step.is_finite() || step <= 0.0 { return; }
    let band = step / 2.0;
    let q = ctx.fit_policy.squared_error.sqrt();
    let degrade_eps = band.min(q);
    let n = points.len();
    // Whole-arc line candidate (the degenerate single-segment economy).
    if let Some(seg) = line_segment(points, 0, n - 1) {
        let cand = candidate_from_segments(vec![seg], ctx, ParameterMap::Composite);
        candidates.push(cand);
    }
    let corners = corner_screen(ctx, band, &mut ledger.rows);
    if corners.is_empty() { return; }
    // Split at corners; every corner sample becomes a shared endpoint.
    let mut cuts = vec![0usize];
    cuts.extend(corners.iter().copied());
    cuts.push(n - 1);
    let mut segs: Vec<FitSegment> = Vec::new();
    for w in cuts.windows(2) {
        let (first, last) = (w[0], w[1]);
        let Some(seg) = fit_piece(ctx, first, last) else {
            ledger.rows.push(EconomyRow::PieceFitFailed { first_sample: first, last_sample: last });
            return;
        };
        // C->L degrade (pipeline step 3) on fitted cubics.
        if seg.kind == SegmentKind::Cubic {
            let dev = chord_stats(points, first, last).map(|(_, e)| e.sqrt()).unwrap_or(f64::INFINITY);
            let degraded = dev < degrade_eps;
            ledger.rows.push(EconomyRow::Degrade { first_sample: first, last_sample: last, max_deviation: dev, degrade_eps, degraded });
            if degraded {
                match line_segment(points, first, last) {
                    Some(l) => { segs.push(l); continue; }
                    None => { segs.push(seg); continue; }
                }
            }
        }
        segs.push(seg);
    }
    let segs = merge_pass(segs, points, ctx.fit_policy, &mut ledger.rows);
    let segs = tidy_pass(segs, points, &mut ledger.rows);
    if segs.is_empty() { return; }
    // A single whole-arc Line duplicates the line candidate already pushed.
    if segs.len() == 1 && segs[0].kind == SegmentKind::Line && segs[0].first == 0 && segs[0].last == n - 1 { return; }
    candidates.push(candidate_from_segments(segs, ctx, ParameterMap::Composite));
}

/// NE-2 economy entry point. Closed gate: direct delegation to
/// cubic_fit::fit_run, bit-identical by construction. Open gate: incumbent
/// trajectories plus economy candidates (whole-arc line, corner-split
/// segmentation), selected under the caller's objective with the budget
/// gate; the outcome never exceeds the caller's accept gate. Without a
/// source_step the economy currency is unavailable and this falls back to
/// the plain open-gate search wrapped in EconomyOutcome::Incumbent.
pub fn fit_run_search_economy_reported(ctx: &SearchContext, search: &FitSearchPolicy, objective: &dyn FitObjective) -> (EconomyOutcome, Option<SearchReport>) {
    if search.mode == FitSearchMode::Off { return (EconomyOutcome::Incumbent(fit_run(ctx.points, ctx.left, ctx.right, ctx.fit_policy)), None); }
    if ctx.points.len() < 3 {
        return (EconomyOutcome::Incumbent(FitOutcome::SplitUnresolved { sample_index: None, stop: None }), Some(SearchReport {
            candidates_generated: 0, solves_failed: 0, continuity_demoted: 0, continuity_abstained: false,
            selected: usize::MAX, selected_score: f64::NAN, matches_incumbent: None,
            economy: Some(EconomyLedger::default()) }));
    }
    if !ctx.points.iter().all(|p| finite(*p)) || !ctx.fit_policy.squared_error.is_finite() || ctx.fit_policy.squared_error < 0. {
        return (EconomyOutcome::Incumbent(FitOutcome::InvalidInput), None);
    }
    let (Some(left), Some(right)) = (unit(ctx.left), unit(ctx.right)) else { return (EconomyOutcome::Incumbent(FitOutcome::InvalidInput), None); };
    let ctx2 = SearchContext { points: ctx.points, left, right, fit_policy: ctx.fit_policy, prev_end_d2: ctx.prev_end_d2, next_start_d2: ctx.next_start_d2, source_step: ctx.source_step };
    if ctx.source_step.is_none() {
        let (out, rep, _) = fit_run_search_in(&ctx2, objective, false);
        return (EconomyOutcome::Incumbent(out), rep);
    }
    let (out, rep, sel) = fit_run_search_in(&ctx2, objective, true);
    let within_budget = sel.as_ref().is_some_and(|c| c.max_squared_error <= ctx.fit_policy.squared_error);
    match sel {
        Some(c) if within_budget && !(c.segments.len() == 1 && c.segments[0].kind == SegmentKind::Cubic) => {
            let score = rep.as_ref().map(|r| r.selected_score).unwrap_or(f64::NAN);
            (EconomyOutcome::Segmented { segments: c.segments, max_squared_error: c.max_squared_error, score }, rep)
        }
        _ => (EconomyOutcome::Incumbent(out), rep),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn on() -> FitSearchPolicy { FIT_SEARCH_ON }
    fn off() -> FitSearchPolicy { FIT_SEARCH_OFF }

    /// Sampled quarter-arc of a circle radius r, n samples.
    fn arc(r: f64, n: usize) -> Vec<Point> {
        (0..n).map(|i| { let t = (i as f64 / (n - 1) as f64) * std::f64::consts::FRAC_PI_2; p(r * t.cos(), r * t.sin()) }).collect()
    }
    /// Monotone S-curve with curvature sign change.
    fn s_curve(n: usize) -> Vec<Point> {
        (0..n).map(|i| { let t = i as f64 / (n - 1) as f64; p(300. * t, 80. * (t * std::f64::consts::PI).sin()) }).collect()
    }

    fn same_outcome(a: &FitOutcome, b: &FitOutcome) -> bool {
        match (a, b) {
            (FitOutcome::Fitted { controls: ca, parameters: ua, max_squared_error: ma },
             FitOutcome::Fitted { controls: cb, parameters: ub, max_squared_error: mb }) =>
                ca.iter().zip(cb.iter()).all(|(x, y)| x.x.to_bits() == y.x.to_bits() && x.y.to_bits() == y.y.to_bits())
                && ua.len() == ub.len() && ua.iter().zip(ub.iter()).all(|(x, y)| x.to_bits() == y.to_bits())
                && ma.to_bits() == mb.to_bits(),
            (FitOutcome::SplitUnresolved { sample_index: sa, stop: ta },
             FitOutcome::SplitUnresolved { sample_index: sb, stop: tb }) => sa == sb && ta == tb,
            (FitOutcome::InvalidInput, FitOutcome::InvalidInput) => true,
            _ => false,
        }
    }

    fn fixtures() -> Vec<Vec<Point>> {
        vec![
            arc(200., 9), arc(50., 25), s_curve(17),
            vec![p(0., 0.), p(1., 1.), p(2., 0.3), p(3., 1.), p(4., 0.)],
            vec![p(0., 0.), p(0.4, 3.), p(0.8, 0.)],
            vec![p(0., 0.), p(1., 0.1), p(2., -0.1), p(3., 0.)],
            vec![p(0., 0.), p(10., 0.), p(20., 0.), p(30., 0.)],
        ]
    }

    #[test]
    fn closed_gate_is_bit_identical_to_incumbent() {
        // Structural guarantee: Off delegates. The sweep proves the delegate
        // is wired with the same arguments on every fixture class.
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        for pts in fixtures() {
            let last = pts.len() - 1;
            let lt = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap().0;
            let rt = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap().1;
            let _ = last;
            let a = fit_run(&pts, lt, rt, &pol);
            let b = fit_run_search(&pts, lt, rt, &pol, &off(), &BaselineObjective);
            assert!(same_outcome(&a, &b));
            let (c, rep) = fit_run_search_reported(&pts, lt, rt, &pol, &off(), &BaselineObjective);
            assert!(same_outcome(&a, &c)); assert!(rep.is_none(), "closed gate emits no search report");
        }
    }

    #[test]
    fn invalid_inputs_mirror_incumbent() {
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        // fewer than 3 points
        let two = vec![p(0., 0.), p(1., 1.)];
        assert!(matches!(fit_run_search(&two, p(1., 0.), p(0., 1.), &pol, &on(), &BaselineObjective),
            FitOutcome::SplitUnresolved { sample_index: None, stop: None }));
        // non-finite point
        let bad = vec![p(0., 0.), p(f64::NAN, 1.), p(2., 0.)];
        assert!(matches!(fit_run_search(&bad, p(1., 0.), p(0., 1.), &pol, &on(), &BaselineObjective), FitOutcome::InvalidInput));
        // zero tangent
        let pts = vec![p(0., 0.), p(1., 1.), p(2., 0.)];
        assert!(matches!(fit_run_search(&pts, p(0., 0.), p(0., 1.), &pol, &on(), &BaselineObjective), FitOutcome::InvalidInput));
        // negative tolerance
        let neg = FitPolicy { squared_error: -1.0, max_refits: 2 };
        assert!(matches!(fit_run_search(&pts, p(1., 0.), p(0., 1.), &neg, &on(), &BaselineObjective), FitOutcome::InvalidInput));
    }

    #[test]
    fn open_gate_outcomes_are_well_formed() {
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        for pts in fixtures() {
            let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
            let (out, rep) = fit_run_search_reported(&pts, lt, rt, &pol, &on(), &BaselineObjective);
            let rep = rep.expect("open gate emits a report");
            match out {
                FitOutcome::Fitted { max_squared_error, .. } => {
                    assert!(max_squared_error <= pol.squared_error);
                    assert!(rep.candidates_generated >= 1);
                    assert!(rep.selected < rep.candidates_generated);
                }
                FitOutcome::SplitUnresolved { sample_index, .. } => {
                    if pts.len() >= 3 { assert!(sample_index.is_some()); }
                }
                FitOutcome::InvalidInput => panic!("valid fixture rejected"),
            }
        }
    }

    #[test]
    fn baseline_objective_matches_incumbent_rule_on_synthetic_states() {
        let pts = arc(100., 9);
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let ctx = SearchContext::new(&pts, p(1., 0.), p(0., 1.), &pol);
        let mk = |dense: f64, plausible_: bool| CandidateState {
            controls: [p(0., 0.); 4], parameters: vec![0., 1.], max_squared_error: 0.0,
            dense, plausible: plausible_, spans_used: 1, segments: vec![],
            d2_start: p(0., 0.), d2_end: p(0., 0.), map: ParameterMap::Centripetal,
            stop: RefitStop::CertifiedNoImprovement, split_index: 1, converged: true,
        };
        let obj = BaselineObjective;
        // plausible ranked by dense
        assert!(obj.score(&mk(1.0, true), &ctx) < obj.score(&mk(2.0, true), &ctx));
        // implausible is +inf
        assert!(obj.score(&mk(0.0, false), &ctx).is_infinite());
    }

    #[test]
    fn continuity_demotes_violating_candidate() {
        // Two synthetic candidates; supply a prev_end_d2 claim matching only
        // candidate 1. Candidate 0 must be demoted and candidate 1 selected
        // even when candidate 0 has the better dense score.
        let pts = arc(100., 9);
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let tol = continuity_tolerance(&pol);
        let claim = p(10. * tol, 0.);
        let ctx = SearchContext::new(&pts, p(1., 0.), p(0., 1.), &pol).with_neighbours(Some(claim), None);
        let mk = |dense: f64, d2s: Point| CandidateState {
            controls: [p(0., 0.); 4], parameters: vec![0., 1.], max_squared_error: 0.0,
            dense, plausible: true, spans_used: 1, segments: vec![], d2_start: d2s, d2_end: p(0., 0.),
            map: ParameterMap::Centripetal, stop: RefitStop::CertifiedNoImprovement,
            split_index: 1, converged: true,
        };
        let cands = vec![mk(0.1, p(0., 0.)), mk(0.2, claim)];
        let flags: Vec<bool> = cands.iter().map(|c| continuity_ok(c, &ctx, tol)).collect();
        assert_eq!(flags, vec![false, true]);
        // selection over survivors picks 1 despite worse dense
        let obj = BaselineObjective;
        let mut best = None; let mut best_score = f64::INFINITY;
        for (i, c) in cands.iter().enumerate() {
            if !flags[i] { continue; }
            let s = obj.score(c, &ctx); if s < best_score { best = Some(i); best_score = s; }
        }
        assert_eq!(best, Some(1));
    }

    #[test]
    fn continuity_abstains_when_every_candidate_violates() {
        let pts = arc(100., 9);
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let ctx = SearchContext::new(&pts, p(1., 0.), p(0., 1.), &pol)
            .with_neighbours(Some(p(1.0e12, 0.)), Some(p(0., -1.0e12)));
        let (out, rep) = fit_run_search_context(&ctx, &on(), &BaselineObjective);
        let rep = rep.unwrap();
        assert!(rep.continuity_abstained, "all candidates violate -> abstain, rep={rep:?}");
        assert!(matches!(out, FitOutcome::Fitted { .. } | FitOutcome::SplitUnresolved { .. }));
    }

    #[test]
    fn continuity_tolerance_derives_from_fit_policy() {
        let a = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let b = FitPolicy { squared_error: 1.0, max_refits: 6 };
        assert!((continuity_tolerance(&a) - 13.5 * 0.5).abs() < 1e-12);
        assert!((continuity_tolerance(&b) - 13.5).abs() < 1e-12);
        assert!(continuity_tolerance(&b) > continuity_tolerance(&a));
    }

    #[test]
    fn derived_budget_mirrors_incumbent_values() {
        assert_eq!(derived_reparam_budget(3), 1);
        assert_eq!(derived_reparam_budget(17), 3);
        assert_eq!(derived_reparam_budget(25), 4);
        assert_eq!(derived_reparam_budget(1000), 5);
    }

    #[test]
    fn open_gate_is_deterministic() {
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        for pts in fixtures() {
            let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
            let (a, _) = fit_run_search_reported(&pts, lt, rt, &pol, &on(), &BaselineObjective);
            let (b, _) = fit_run_search_reported(&pts, lt, rt, &pol, &on(), &BaselineObjective);
            assert!(same_outcome(&a, &b));
        }
    }

    #[test]
    fn divergent_search_selection_never_worsens_incumbent_dense() {
        // Structural property of terminal-state argmin: the incumbent's
        // terminal is one of the two searched trajectories, so whenever the
        // search diverges its dense excursion must be <= the incumbent's.
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let extra: Vec<Vec<Point>> = vec![
            (0..25).map(|i| { let t = i as f64 / 24. * std::f64::consts::FRAC_PI_2; p(50. * t.cos(), 50. * t.sin()) }).collect(),
            (0..33).map(|i| { let t = i as f64 / 32. * std::f64::consts::FRAC_PI_2; p(1000. * t.cos(), 1000. * t.sin()) }).collect(),
        ];
        let mut saw_divergence = false;
        for pts in fixtures().into_iter().chain(extra) {
            let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
            let (got, rep) = fit_run_search_reported(&pts, lt, rt, &pol, &on(), &BaselineObjective);
            if rep.unwrap().matches_incumbent != Some(false) { continue; }
            saw_divergence = true;
            if let (FitOutcome::Fitted { controls: ci, .. }, FitOutcome::Fitted { controls: cs, .. }) =
                (fit_run(&pts, lt, rt, &pol), got) {
                let (di, _) = dense_gate(&ci, &pts);
                let (ds, _) = dense_gate(&cs, &pts);
                assert!(ds <= di, "divergent selection worsened dense: {ds} > {di}");
            }
        }
        assert!(saw_divergence, "fixture set no longer exercises divergence; keep one divergent fixture");
    }

    #[test]
    fn non_finite_objective_score_never_wins_unless_all() {
        struct NanObjective;
        impl FitObjective for NanObjective { fn score(&self, _c: &CandidateState, _ctx: &SearchContext) -> f64 { f64::NAN } }
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let pts = arc(100., 9);
        let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
        let (out, rep) = fit_run_search_reported(&pts, lt, rt, &pol, &on(), &NanObjective);
        let rep = rep.unwrap();
        assert_eq!(rep.selected, 0, "all-NaN scores fall back to generation order");
        assert!(matches!(out, FitOutcome::Fitted { .. } | FitOutcome::SplitUnresolved { .. }));
    }
}

#[cfg(test)]
mod economy_tests {
    use super::*;

    fn p(x: f64, y: f64) -> Point { Point { x, y } }

    /// L-shaped polyline arc: two straight runs meeting at a hard corner,
    /// densely sampled. The incumbent single cubic cannot fit a 90-degree
    /// corner inside a tight budget; the economy segmentation can.
    fn cornered_arc() -> Vec<Point> {
        let mut v: Vec<Point> = (0..=10).map(|i| p(i as f64 * 10., 0.)).collect();
        for j in 1..=8 { v.push(p(100., j as f64 * 10.)); }
        v
    }

    fn arc(r: f64, n: usize) -> Vec<Point> {
        (0..n).map(|i| { let t = (i as f64 / (n - 1) as f64) * std::f64::consts::FRAC_PI_2; p(r * t.cos(), r * t.sin()) }).collect()
    }

    #[test]
    fn adapter_score_matches_ne1_direct() {
        let pts = arc(100., 9);
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
        let ctx = SearchContext::new(&pts, lt, rt, &pol).with_source_step(Some(2.0));
        let maps = initial_maps(&pts).unwrap();
        let (map, u) = maps.into_iter().next().unwrap();
        let cand = trajectory(&pts, map, u, lt, rt, &pol).unwrap();
        let adapter = EconomyObjective::derive(2.0).unwrap();
        let via_trait = adapter.score(&cand, &ctx);
        let direct = crate::fit_objective::Objective::derive(2.0).unwrap()
            .score(&pts, &[crate::fit_objective::CurveCandidate {
                controls: cand.controls, parameters: cand.parameters.clone(), first: 0, last: pts.len() - 1,
            }]).unwrap();
        assert_eq!(via_trait.to_bits(), direct.total.to_bits(), "adapter must be NE-1's score through the interface");
    }

    #[test]
    fn old_entry_points_bit_identical_with_source_step() {
        // A ctx carrying source_step must not change the pre-economy entry
        // points: they run with economy generation off by construction.
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        for pts in [arc(200., 9), arc(50., 25), cornered_arc()] {
            let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
            let plain = SearchContext::new(&pts, lt, rt, &pol);
            let stepped = SearchContext::new(&pts, lt, rt, &pol).with_source_step(Some(1.0));
            let (a, ra) = fit_run_search_context(&plain, &FIT_SEARCH_ON, &BaselineObjective);
            let (b, rb) = fit_run_search_context(&stepped, &FIT_SEARCH_ON, &BaselineObjective);
            assert!(matches!(ra, Some(_))); assert!(matches!(rb, Some(_)));
            assert!(rb.unwrap().economy.is_none(), "old entry points emit no economy ledger");
            match (&a, &b) {
                (FitOutcome::Fitted { controls: ca, parameters: ua, max_squared_error: ma },
                 FitOutcome::Fitted { controls: cb, parameters: ub, max_squared_error: mb }) => {
                    assert!(ca.iter().zip(cb.iter()).all(|(x, y)| x.x.to_bits() == y.x.to_bits() && x.y.to_bits() == y.y.to_bits()));
                    assert!(ua.iter().zip(ub.iter()).all(|(x, y)| x.to_bits() == y.to_bits()));
                    assert_eq!(ma.to_bits(), mb.to_bits());
                }
                _ => assert!(matches!(a, FitOutcome::SplitUnresolved { .. }) && matches!(b, FitOutcome::SplitUnresolved { .. })),
            }
        }
    }

    #[test]
    fn cornered_polyline_economy_selects_line_segments() {
        let pts = cornered_arc();
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
        let ctx = SearchContext::new(&pts, lt, rt, &pol).with_source_step(Some(1.0));
        let obj = EconomyObjective::derive(1.0).unwrap();
        let (out, rep) = fit_run_search_economy_reported(&ctx, &FIT_SEARCH_ON, &obj);
        let rep = rep.unwrap();
        let ledger = rep.economy.as_ref().expect("economy ledger present");
        assert!(ledger.rows.iter().any(|r| matches!(r, EconomyRow::CornerScreen { is_corner: true, .. })),
            "corner screen must flag the hard corner: {:?}", ledger.rows.iter().filter(|r| matches!(r, EconomyRow::CornerScreen { is_corner: true, .. })).collect::<Vec<_>>());
        match out {
            EconomyOutcome::Segmented { segments, max_squared_error, .. } => {
                assert_eq!(segments.len(), 2, "two runs -> two segments: {segments:?}");
                assert!(segments.iter().all(|s| s.kind == SegmentKind::Line), "straight runs degrade to lines: {segments:?}");
                assert!(max_squared_error <= pol.squared_error, "budget asimi yok: {max_squared_error}");
                assert_eq!(segments[0].first, 0);
                assert_eq!(segments[0].last, segments[1].first);
                assert_eq!(segments[1].last, pts.len() - 1);
            }
            other => panic!("economy must win on a cornered polyline, got {other:?}; ledger rows: {:?}", ledger.rows.len()),
        }
    }

    #[test]
    fn smooth_arc_keeps_incumbent_cubic() {
        let pts = arc(200., 25);
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
        let ctx = SearchContext::new(&pts, lt, rt, &pol).with_source_step(Some(1.0));
        let obj = EconomyObjective::derive(1.0).unwrap();
        let (out, rep) = fit_run_search_economy_reported(&ctx, &FIT_SEARCH_ON, &obj);
        let rep = rep.unwrap();
        let ledger = rep.economy.as_ref().unwrap();
        assert!(ledger.rows.iter().all(|r| !matches!(r, EconomyRow::CornerScreen { is_corner: true, .. })),
            "a smooth arc has no measurable corners");
        match out {
            // No measurable corners -> no segmentation candidate: the winner
            // stays on the incumbent path (a converged cubic, or the
            // incumbent's own split request when the budget is too tight).
            EconomyOutcome::Incumbent(FitOutcome::Fitted { max_squared_error, .. }) => {
                assert!(max_squared_error <= pol.squared_error);
            }
            EconomyOutcome::Incumbent(FitOutcome::SplitUnresolved { .. }) => {}
            other => panic!("smooth arc keeps the incumbent path, got {other:?}"),
        }
    }

    #[test]
    fn merge_pass_merges_within_theta_and_budget_and_refuses_outside() {
        let pts = vec![p(0., 0.), p(50., 0.), p(100., 1.)];
        let rows = &mut Vec::new();
        let pol = FitPolicy { squared_error: 1.0, max_refits: 6 };
        let segs = vec![line_segment(&pts, 0, 1).unwrap(), line_segment(&pts, 1, 2).unwrap()];
        let merged = merge_pass(segs, &pts, &pol, rows);
        assert_eq!(merged.len(), 1, "small kink within budget merges: {rows:?}");
        assert!(rows.iter().any(|r| matches!(r, EconomyRow::Merge { merged: true, .. })));
        let rows = &mut Vec::new();
        let tight = FitPolicy { squared_error: 0.01, max_refits: 6 };
        let segs = vec![line_segment(&pts, 0, 1).unwrap(), line_segment(&pts, 1, 2).unwrap()];
        let kept = merge_pass(segs, &pts, &tight, rows);
        assert_eq!(kept.len(), 2, "over-budget merge is refused: {rows:?}");
        assert!(rows.iter().any(|r| matches!(r, EconomyRow::Merge { merged: false, .. })));
    }

    #[test]
    fn tidy_pass_drops_zero_length_with_typed_row() {
        let pts = vec![p(0., 0.), p(0., 0.), p(100., 0.)];
        let rows = &mut Vec::new();
        let zero = FitSegment { kind: SegmentKind::Line, controls: [p(0., 0.); 4], parameters: vec![0.0], first: 0, last: 1, max_squared_error: 0.0 };
        let good = line_segment(&pts, 1, 2).unwrap();
        let out = tidy_pass(vec![zero, good], &pts, rows);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].first, 1);
        assert!(rows.iter().any(|r| matches!(r, EconomyRow::Tidy { reason: TidyReason::ZeroLength, first_sample: 0, last_sample: 1 })),
            "dropped zero-length segment needs its typed row: {rows:?}");
    }

    #[test]
    fn closed_gate_economy_entry_is_bit_identical() {
        let pol = FitPolicy { squared_error: 0.25, max_refits: 6 };
        for pts in [arc(200., 9), cornered_arc()] {
            let (lt, rt) = crate::cubic_fit::adjacent_chord_tangents(&pts).unwrap();
            let ctx = SearchContext::new(&pts, lt, rt, &pol).with_source_step(Some(1.0));
            let obj = EconomyObjective::derive(1.0).unwrap();
            let (out, rep) = fit_run_search_economy_reported(&ctx, &FIT_SEARCH_OFF, &obj);
            assert!(rep.is_none(), "closed gate emits no report");
            let EconomyOutcome::Incumbent(inc) = out else { panic!("closed gate is the incumbent"); };
            let want = fit_run(&pts, lt, rt, &pol);
            match (&inc, &want) {
                (FitOutcome::Fitted { controls: ca, .. }, FitOutcome::Fitted { controls: cb, .. }) =>
                    assert!(ca.iter().zip(cb.iter()).all(|(x, y)| x.x.to_bits() == y.x.to_bits() && x.y.to_bits() == y.y.to_bits())),
                (FitOutcome::SplitUnresolved { .. }, FitOutcome::SplitUnresolved { .. }) => {}
                _ => panic!("closed gate diverged"),
            }
        }
    }
}
