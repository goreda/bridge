//! Node-economy OBJECTIVE (lever N1). Opt-in post-fit lever on the lever_api v3 contract.
//!
//! Greedy removal reward (what the code actually computes), per candidate removal k:
//!   dj_k = deltaA_k - slack * g_k,   deltaA_k = area_error(after) - area_error(before) (shared exact-coverage
//!   L1 objective vs the threshold-128 mask), g_k = (scale/2) * L_k (half-pixel boundary-uncertainty band of a
//!   binary mask along the merged span; L_k = chord length of the merged pair in font units).
//!   A removal is taken iff dj_k <= 0; the most negative dj_k goes first. slack = 0 => deltaA_k <= 0, i.e. area
//!   error never increases. slack > 0 ACCEPTS area-error increases up to slack*g_k per removal (cumulative,
//!   not globally bounded) and therefore must not be selected as a default: see `Candidate::default_eligible`.
//! Max deviation guard: outward-rounded interval bracket on the curve-to-curve (Hausdorff)
//! distance per candidate merge (`bracket_dev`): symmetric nearest-sample terms plus Lipschitz slack
//! certificates L*(1/(2n) + 2^-53), every operation outward-rounded via one-ulp successors, so the
//! bracket is certified IN binary64, not only in real arithmetic. Refined by doubling until the bracket
//! decides against the caller's half-scale band (mask.scale/2, the acquisition half-pixel uncertainty,
//! caller-derived). `Within` requires the certified upper bound <= the band; `Beyond` is a certified
//! geometric violation only; work-budget exhaustion is a typed `Indeterminate` (conservative reject),
//! never conflated with Beyond. SAMPLES = 24 remains the base sampling-resolution convention of the
//! fit/measurement samplers, never a quality threshold; DEV_WORK_BUDGET is a declared per-candidate
//! pair-evaluation resource convention with wall-time evidence in core/CHANGELOG.md.
//! One removal = merge span k and span k+1 (drop node k) into one span: Line+Line -> Line;
//! otherwise a single cubic with end tangents of the old spans and handle lengths from a
//! least-squares (Schneider) fit to the old path, rounded to integers. Greedy best-first by delta J.
//! Hard guards (a removal that violates any is never taken):
//!  - ring start node never removed; a ring keeps >= 3 spans;
//!  - extremum nodes (x or y) never removed (neighbour-node HEURISTIC: node coordinate vs its two adjacent node
//!    coordinates, not a curve-interior analysis); missing_extrema(out) <= missing_extrema(in) (lever_api count,
//!    non-increase only, inherits that function's definition);
//!  - corner nodes never removed (tangent angle at node exceeds the integer-grid resolution
//!    HALF_DIAG*(1/|ta|+1/|tb|) in sin-angle: the rounding error of both handle end points);
//!  - integer output; axis-aligned end tangents keep exact axis alignment (handle direction is exact);
//!  - node count never increases; deterministic, serial, no randomness.
use crate::lever_api::*;
use std::collections::BTreeSet;
use crate::flatten_budget::check_flatten_budget;
use crate::reference_slice::{Point, ReferenceRing, Span};

pub const LEVER_ID: &str = "N1.node_objective";
pub const STAGE_TAG: &str = "post-fit/opt-in";
pub const SEED: u64 = 0;

#[derive(Clone, Copy, Debug)]
pub struct Policy {
    /// Multiple of the half-pixel noise band a removal may add in area error. 0 = no area increase.
    pub slack: f64,
}
impl Policy {
    pub const STRICT: Policy = Policy { slack: 0.0 };
    pub const HALF_NOISE: Policy = Policy { slack: 0.5 };
    pub const NOISE: Policy = Policy { slack: 1.0 };
}

#[derive(Clone, Debug)]
pub struct Candidate {
    pub name: &'static str,
    pub policy: Policy,
    pub rings: Vec<ReferenceRing>,
    pub report: LeverReport,
    pub removed: Vec<Removal>,
    /// true only if this candidate may be chosen as a global default: slack == 0 AND global area_error did not
    /// increase (area_after <= area_before). HALF_NOISE / NOISE are never default-eligible.
    pub default_eligible: bool,
}
#[derive(Clone, Debug)]
/// `original_node` = identity of the dropped node in the INPUT ring (node i = end_of(spans[i]) of the input).
pub struct Removal { pub ring: usize, pub original_node: usize, pub node_end: Point, pub delta_area: f64, pub gain_bound: f64 }
/// Protected node identity: (ring index, node index) in the INPUT rings, node i = end_of(input.spans[i]). Node n-1 is the
/// ring start / closing occurrence (never removable anyway). Identity is stable: removals never renumber it.
pub type Protected = BTreeSet<(usize, usize)>;

fn end_of(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn sub(a: Point, b: Point) -> (f64, f64) { (a.x - b.x, a.y - b.y) }
fn len(v: (f64, f64)) -> f64 { (v.0 * v.0 + v.1 * v.1).sqrt() }
fn is_int(v: f64) -> bool { v.is_finite() && v == v.round() }
fn ring_int(r: &ReferenceRing) -> bool {
    let ok = |p: &Point| is_int(p.x) && is_int(p.y);
    ok(&r.start) && r.spans.iter().all(|s| match s {
        Span::Line { end } => ok(end),
        Span::Cubic { control_one, control_two, end } => ok(control_one) && ok(control_two) && ok(end),
    })
}
fn closed(r: &ReferenceRing) -> bool { r.spans.last().map_or(false, |s| end_of(s) == r.start) }
fn is_ext(v: f64, a: f64, b: f64) -> bool {
    (v >= a && v >= b && (v > a || v > b)) || (v <= a && v <= b && (v < a || v < b))
}
fn eval(p0: Point, s: &Span, t: f64) -> Point {
    match s {
        Span::Line { end } => Point { x: p0.x + (end.x - p0.x) * t, y: p0.y + (end.y - p0.y) * t },
        Span::Cubic { control_one: a, control_two: b, end } => {
            let u = 1.0 - t;
            Point { x: u*u*u*p0.x + 3.0*u*u*t*a.x + 3.0*u*t*t*b.x + t*t*t*end.x,
                    y: u*u*u*p0.y + 3.0*u*u*t*a.y + 3.0*u*t*t*b.y + t*t*t*end.y }
        }
    }
}
/// Half-diagonal of one integer cell: worst-case rounding error of one integer point.
const HALF_DIAG: f64 = std::f64::consts::FRAC_1_SQRT_2;
const SAMPLES: usize = 24; // sampling resolution of the deviation/fit measurement, not a quality threshold

/// Start / end unit tangents (pointing along travel) of one span.
fn tangents(p0: Point, s: &Span) -> ((f64, f64), (f64, f64)) {
    match s {
        Span::Line { end } => { let d = sub(*end, p0); (d, d) }
        Span::Cubic { control_one: a, control_two: b, end } => {
            let mut d0 = sub(*a, p0); if len(d0) == 0.0 { d0 = sub(*b, p0); } if len(d0) == 0.0 { d0 = sub(*end, p0); }
            let mut d1 = sub(*end, *b); if len(d1) == 0.0 { d1 = sub(*end, *a); } if len(d1) == 0.0 { d1 = sub(*end, p0); }
            (d0, d1)
        }
    }
}
fn unit(v: (f64, f64)) -> (f64, f64) { let l = len(v); if l == 0.0 { (0.0, 0.0) } else { (v.0 / l, v.1 / l) } }

/// Is node M (end of `a`, start of `b`) a smooth join to within the integer-grid angular resolution?
fn smooth(p0: Point, a: &Span, b: &Span) -> bool {
    let m = end_of(a);
    let (_, ta) = tangents(p0, a);
    let (tb, _) = tangents(m, b);
    let (la, lb) = (len(ta), len(tb));
    if la == 0.0 || lb == 0.0 { return false; }
    let cross = ta.0 * tb.1 - ta.1 * tb.0;
    let dot = ta.0 * tb.0 + ta.1 * tb.1;
    // one integer unit of lateral error over the shorter tangent vector
    dot > 0.0 && (cross / (la * lb)).abs() <= HALF_DIAG * (1.0 / la + 1.0 / lb)
}

/// Build the merged span for spans a (p0 -> m) and b (m -> p3). None = cannot form a valid integer span.
fn merge(p0: Point, a: &Span, b: &Span) -> Option<Span> {
    let m = end_of(a); let p3 = end_of(b);
    if let (Span::Line { .. }, Span::Line { .. }) = (a, b) { return Some(Span::Line { end: p3 }); }
    let t0 = unit(tangents(p0, a).0);
    let tb = tangents(m, b).1; let t1 = unit((-tb.0, -tb.1)); // pointing from p3 back along the curve
    if t0 == (0.0, 0.0) || t1 == (0.0, 0.0) { return None; }
    // sample old path, chord-length parametrisation
    let mut pts = vec![p0];
    for k in 1..=SAMPLES { pts.push(eval(p0, a, k as f64 / SAMPLES as f64)); }
    for k in 1..=SAMPLES { pts.push(eval(m, b, k as f64 / SAMPLES as f64)); }
    let mut u = vec![0.0]; for i in 1..pts.len() { let l = len(sub(pts[i], pts[i-1])); u.push(u[i-1] + l); }
    let total = *u.last().unwrap(); if total == 0.0 { return None; }
    for v in u.iter_mut() { *v /= total; }
    let chord = len(sub(p3, p0));
    let (mut c00, mut c01, mut c11, mut x0, mut x1) = (0.0, 0.0, 0.0, 0.0, 0.0);
    for (i, p) in pts.iter().enumerate() {
        let t = u[i]; let s = 1.0 - t;
        let (b0, b1, b2, b3) = (s*s*s, 3.0*s*s*t, 3.0*s*t*t, t*t*t);
        let a1 = (t0.0 * b1, t0.1 * b1); let a2 = (t1.0 * b2, t1.1 * b2);
        c00 += a1.0*a1.0 + a1.1*a1.1; c01 += a1.0*a2.0 + a1.1*a2.1; c11 += a2.0*a2.0 + a2.1*a2.1;
        let base = (b0 + b1) * 1.0; let base2 = (b2 + b3) * 1.0;
        let tmp = (p.x - base * p0.x - base2 * p3.x, p.y - base * p0.y - base2 * p3.y);
        x0 += a1.0*tmp.0 + a1.1*tmp.1; x1 += a2.0*tmp.0 + a2.1*tmp.1;
    }
    let det = c00 * c11 - c01 * c01;
    let (mut al, mut ar) = (chord / 3.0, chord / 3.0);
    // Scale-aware Gram conditioning heuristic (NOT a certified round-off
    // bound). The basis/tangent factors are unitless, so compare det with
    // c00*c11 rather than an absolute or dimensioned cutoff. n and u are
    // the actual accumulation count and binary64 unit roundoff; this margin
    // is a conservative refusal rule, not a proof that every basis,
    // tangent, product and two-component add is accounted for. Below the
    // margin, decline the solve and keep the conservative chord/3 fallback.
    let unit_roundoff = f64::EPSILON / 2.0;
    let n = pts.len() as f64;
    let rho_margin = 2.0 * n * unit_roundoff + unit_roundoff;
    let gram_independence_margin = 2.0 * rho_margin + rho_margin * rho_margin + 3.0 * unit_roundoff;
    let gram_scale = c00 * c11;
    if gram_scale.is_finite() && gram_scale > 0.0 && det.is_finite()
        && det > gram_scale * gram_independence_margin {
        let (l, r) = ((x0 * c11 - x1 * c01) / det, (c00 * x1 - c01 * x0) / det);
        if l > 0.0 && r > 0.0 && l.is_finite() && r.is_finite() { al = l; ar = r; }
    }
    let c1 = Point { x: (p0.x + t0.0 * al).round(), y: (p0.y + t0.1 * al).round() };
    let c2 = Point { x: (p3.x + t1.0 * ar).round(), y: (p3.y + t1.1 * ar).round() };
    Some(Span::Cubic { control_one: c1, control_two: c2, end: p3 })
}

/// Resource guard BEFORE every area_error/flatten call: chord count must not exceed MAX_TOTAL_SEGMENTS = mask.w*mask.h
/// (bounded-input convention). Over budget or non-finite geometry = typed refusal; no budget growth, no retry, no skip.
fn flatten_guard(rings: &[ReferenceRing], mask: &SourceMask) -> Result<usize, LeverError> {
    let max = mask.w.checked_mul(mask.h).filter(|&n| n > 0)
        .ok_or_else(|| LeverError::Violation("flatten budget refused: no MAX_TOTAL_SEGMENTS (w*h)".into()))?;
    check_flatten_budget(rings, mask, max)
        .map_err(|e| LeverError::Violation(format!("flatten budget refused (MAX_TOTAL_SEGMENTS={max}): {e:?}")))
}
fn span_finite(s: &Span) -> bool {
    match s { Span::Line { end } => end.x.is_finite() && end.y.is_finite(),
        Span::Cubic { control_one: a, control_two: b, end } => [a.x, a.y, b.x, b.y, end.x, end.y].iter().all(|v| v.is_finite()) }
}
/// Outward-rounded binary64 interval. Every operation rounds the true
/// result into [lo, hi] via one-ulp successors (f64::next_down/next_up), and
/// every primitive revalidates its result as an ordered finite enclosure
/// (lo <= hi, both finite): overflow to +-inf, NaN from 0*inf, and any
/// ordering collapse are arithmetic failures, propagated as None and
/// surfaced as DevBracket::NonFinite - never silently dropped by f64
/// min/max NaN suppression. With validated finite inputs, finite*finite
/// products can only overflow to +-inf (never NaN), so validation after
/// each op keeps every enclosure sound. No invented tolerance exists
/// anywhere; the only float margin is f64::EPSILON (2^-52), a conservative
/// bound on the binary64 parameter rounding |fl(k/n) - k/n| <= 2^-53.
#[derive(Clone, Copy, Debug)]
struct Iv { lo: f64, hi: f64 }
impl Iv {
    fn pt(x: f64) -> Iv { Iv { lo: x, hi: x } }
    /// Ordered finite enclosure validation; None = arithmetic failure.
    fn ok(self) -> Option<Iv> {
        if self.lo.is_finite() && self.hi.is_finite() && self.lo <= self.hi { Some(self) } else { None }
    }
    fn add(self, o: Iv) -> Option<Iv> {
        self.ok()?; o.ok()?;
        (Iv { lo: (self.lo + o.lo).next_down(), hi: (self.hi + o.hi).next_up() }).ok()
    }
    fn sub(self, o: Iv) -> Option<Iv> {
        self.ok()?; o.ok()?;
        (Iv { lo: (self.lo - o.hi).next_down(), hi: (self.hi - o.lo).next_up() }).ok()
    }
    fn mul(self, o: Iv) -> Option<Iv> {
        self.ok()?; o.ok()?;
        let (a, b, c, d) = (self.lo * o.lo, self.lo * o.hi, self.hi * o.lo, self.hi * o.hi);
        (Iv { lo: a.min(b).min(c).min(d).next_down(), hi: a.max(b).max(c).max(d).next_up() }).ok()
    }
    /// Square root of a provably nonnegative quantity. The mathematical
    /// value is >= 0, so a slightly negative lo (interval overestimation)
    /// clamps to 0 without breaking containment.
    fn sqrt(self) -> Option<Iv> {
        self.ok()?;
        (Iv { lo: if self.lo <= 0.0 { 0.0 } else { self.lo.sqrt().next_down() },
              hi: self.hi.sqrt().next_up() }).ok()
    }
    /// Outward division by an exactly represented positive divisor.
    fn div_exact(self, d: f64) -> Option<Iv> {
        self.ok()?;
        if !(d > 0.0 && d.is_finite()) { return None; }
        (Iv { lo: (self.lo / d).next_down(), hi: (self.hi / d).next_up() }).ok()
    }
    fn max_iv(self, o: Iv) -> Iv { Iv { lo: self.lo.max(o.lo), hi: self.hi.max(o.hi) } }
}

/// Interval evaluation of one span at parameter interval t. Input
/// coordinates are exact as stored f64 values; every DERIVED quantity
/// (coordinate differences included - integers of any width are NOT
/// assumed exactly subtractable, e.g. 2^53 - (-1) is not exact in binary64)
/// goes through outward interval arithmetic.
fn eval_iv(p0: Point, s: &Span, t: Iv) -> Option<(Iv, Iv)> {
    let one = Iv::pt(1.0);
    let (px, py) = (Iv::pt(p0.x), Iv::pt(p0.y));
    match s {
        Span::Line { end } => {
            let dx = Iv::pt(end.x).sub(px)?;
            let dy = Iv::pt(end.y).sub(py)?;
            Some((px.add(dx.mul(t)?)?, py.add(dy.mul(t)?)?))
        }
        Span::Cubic { control_one: a, control_two: b, end } => {
            let u = one.sub(t)?;
            let three = Iv::pt(3.0);
            let b0 = u.mul(u)?.mul(u)?;
            let b1 = three.mul(u)?.mul(u)?.mul(t)?;
            let b2 = three.mul(u)?.mul(t)?.mul(t)?;
            let b3 = t.mul(t)?.mul(t)?;
            let x = b0.mul(px)?.add(b1.mul(Iv::pt(a.x))?)?.add(b2.mul(Iv::pt(b.x))?)?.add(b3.mul(Iv::pt(end.x))?)?;
            let y = b0.mul(py)?.add(b1.mul(Iv::pt(a.y))?)?.add(b2.mul(Iv::pt(b.y))?)?.add(b3.mul(Iv::pt(end.y))?)?;
            Some((x, y))
        }
    }
}

/// Interval Lipschitz constant of a span's parameterization: |dB/dt| <= L on
/// [0,1]. A cubic's derivative is a quadratic Bezier over the vectors
/// 3(P1-P0), 3(P2-P1), 3(P3-P2), a convex combination of them, so its norm
/// never exceeds 3*max|P(i+1)-P(i)|. Differences are interval subtractions
/// (no exactness premise), norms outward-rounded. A line's speed is constant.
fn speed_bound_iv(p0: Point, s: &Span) -> Option<Iv> {
    let norm = |x0: f64, x1: f64, y0: f64, y1: f64| -> Option<Iv> {
        let dx = Iv::pt(x1).sub(Iv::pt(x0))?;
        let dy = Iv::pt(y1).sub(Iv::pt(y0))?;
        dx.mul(dx)?.add(dy.mul(dy)?)?.sqrt()
    };
    match s {
        Span::Line { end } => norm(p0.x, end.x, p0.y, end.y),
        Span::Cubic { control_one: a, control_two: b, end } => {
            let m = norm(p0.x, a.x, p0.y, a.y)?
                .max_iv(norm(a.x, b.x, a.y, b.y)?)
                .max_iv(norm(b.x, end.x, b.y, end.y)?);
            m.mul(Iv::pt(3.0))
        }
    }
}

/// Decision for one candidate merge, against the caller's band `cap`
/// (mask.scale/2: the acquisition half-pixel uncertainty, caller-derived).
#[derive(Clone, Copy, Debug, PartialEq)]
enum DevBracket {
    /// Certified: the outward-rounded upper bound is <= cap. Carries it.
    Within(f64),
    /// Certified violation: the outward-rounded lower bound is > cap.
    /// Carries it. Geometric verdict, never a resource outcome.
    Beyond(f64),
    /// Work budget exhausted (or a whole-glyph budget already spent) with
    /// the bracket still straddling cap. Conservative reject, deliberately
    /// distinct from Beyond: nothing geometric is claimed.
    Indeterminate,
    /// Non-finite input or an interval arithmetic failure (overflow, NaN,
    /// ordering collapse); preserves the incumbent typed-failure contract
    /// at the call sites.
    NonFinite,
}

/// Pair-distance evaluations one candidate's bracket may spend, base round
/// included. Declared resource convention (work per candidate, independent
/// of drawing quality): the base round costs 2*(2*24+1)*(2*24+1) = 4802
/// distance evaluations (two symmetric nearest-sample loops, actual calls);
/// the budget caps refinement. Whole-pass latency evidence in
/// core/CHANGELOG.md (0.1.4).
const DEV_WORK_BUDGET: u64 = 1 << 18;
/// Whole-glyph bracket work budget: declared resource convention bounding
/// the TOTAL bracket work of one lever run (all candidates, rings and
/// removal rounds), so candidate-heavy glyphs are bounded independently of
/// the input node ceiling. Once spent, later candidates receive no bracket
/// work and are Indeterminate (conservative reject). Deterministic: the
/// scan order and the budget are both fixed.
const DEV_GLYPH_WORK_BUDGET: u64 = 1 << 24;

/// One bracket round at per-span resolutions n_old / n_new. Returns
/// (lower, upper, pair_evaluations): outward-rounded interval bounds on the
/// true Hausdorff distance between the old two-span path and the merged
/// span, or None on interval arithmetic failure.
///
/// Derivation (no invented tolerances). Every old-path point is within
/// L_old*(1/(2 n_old) + EPS) of an old sample in arc parameter, EPS =
/// f64::EPSILON = 2^-52 conservatively bounding the binary64 parameter
/// rounding |fl(k/n) - k/n| <= 2^-53, and |dB/dt| <= L_old. Then
/// d(p, C_new) <= |p - p_k| + min_j |p_k - q_j| for the nearest sample p_k,
/// so with (on, no) the symmetric nearest-sample terms (interval distances
/// between interval points):
///     H <= max(on + slack_old, no + slack_new) = U,
///     H >= max(on - slack_new, no - slack_old) = Lo,
/// slack_* = L_*(1/(2 n_*) + EPS). The parameter-grid contribution to
/// bracket width shrinks under doubling; interval rounding leaves a
/// nonzero floor, so convergence to a decision is not promised. All arithmetic is outward-rounded and
/// validated intervals: U.hi and Lo.lo are certified in binary64.
fn bracket_at(p0: Point, a: &Span, b: &Span, new: &Span, n_old: usize, n_new: usize)
    -> (Option<(Iv, Iv)>, u64) // every counted pair evaluation is returned, including on arithmetic failure
{
    let m = end_of(a);
    let Some(l0) = speed_bound_iv(p0, a) else { return (None, 0) };
    let Some(l1) = speed_bound_iv(m, b) else { return (None, 0) };
    let l_old = l0.max_iv(l1);
    let Some(l_new) = speed_bound_iv(p0, new) else { return (None, 0) };
    let eps = Iv::pt(f64::EPSILON);
    let slack = |l: Iv, n: usize| -> Option<Iv> {
        let n_f = n as f64; // exact: n << 2^53
        l.mul(Iv::pt(1.0).div_exact(2.0 * n_f)? .add(eps)?)
    };
    let Some(slack_old) = slack(l_old, n_old) else { return (None, 0) };
    let Some(slack_new) = slack(l_new, n_new) else { return (None, 0) };
    let mut old_pts: Vec<(Iv, Iv)> = Vec::with_capacity(2 * n_old + 1);
    for k in 0..=n_old {
        let t = k as f64 / n_old as f64;
        let Some(pt) = eval_iv(p0, a, Iv { lo: t.next_down(), hi: t.next_up() }) else { return (None, 0) };
        old_pts.push(pt);
    }
    for k in 1..=n_old {
        let t = k as f64 / n_old as f64;
        let Some(pt) = eval_iv(m, b, Iv { lo: t.next_down(), hi: t.next_up() }) else { return (None, 0) };
        old_pts.push(pt);
    }
    let mut new_pts: Vec<(Iv, Iv)> = Vec::with_capacity(n_new + 1);
    for k in 0..=n_new {
        let t = k as f64 / n_new as f64;
        let Some(pt) = eval_iv(p0, new, Iv { lo: t.next_down(), hi: t.next_up() }) else { return (None, 0) };
        new_pts.push(pt);
    }
    let dist = |p: &(Iv, Iv), q: &(Iv, Iv)| -> Option<Iv> {
        let dx = p.0.sub(q.0)?;
        let dy = p.1.sub(q.1)?;
        dx.mul(dx)?.add(dy.mul(dy)?)?.sqrt()
    };
    let mut on = Iv::pt(0.0);
    let mut no = Iv::pt(0.0);
    let mut pairs: u64 = 0;
    for pk in &old_pts {
        let mut best: Option<Iv> = None;
        for qj in &new_pts {
            let Some(d) = dist(pk, qj) else { return (None, pairs) };
            pairs += 1;
            best = Some(match best { None => d, Some(bv) => Iv { lo: bv.lo.min(d.lo), hi: bv.hi.min(d.hi) } });
        }
        let Some(best) = best else { return (None, pairs) };
        on = on.max_iv(best);
    }
    for qj in &new_pts {
        let mut best: Option<Iv> = None;
        for pk in &old_pts {
            let Some(d) = dist(qj, pk) else { return (None, pairs) };
            pairs += 1;
            best = Some(match best { None => d, Some(bv) => Iv { lo: bv.lo.min(d.lo), hi: bv.hi.min(d.hi) } });
        }
        let Some(best) = best else { return (None, pairs) };
        no = no.max_iv(best);
    }
    let Some(u0) = on.add(slack_old) else { return (None, pairs) };
    let Some(u1) = no.add(slack_new) else { return (None, pairs) };
    let upper = u0.max_iv(u1);
    let Some(l0) = on.sub(slack_new) else { return (None, pairs) };
    let Some(l1) = no.sub(slack_old) else { return (None, pairs) };
    let lower = l0.max_iv(l1);
    (Some((lower, upper)), pairs)
}

fn bracket_cost(n_old: usize, n_new: usize) -> u64 {
    2 * (2 * n_old as u64 + 1) * (n_new as u64 + 1)
}

/// Certified max-deviation guard, returning the decision and the pair
/// evaluations spent. Refines by doubling until the bracket decides against
/// `cap`, under `budget`; when the remaining budget cannot afford the base
/// round the guard does no work and returns Indeterminate. Within is
/// returned only when U.hi <= cap (certified in binary64); Beyond only when
/// Lo.lo > cap (certified violation); otherwise Indeterminate. A final
/// partial round spends the remaining budget at the largest resolution it
/// affords.
fn bracket_dev(p0: Point, a: &Span, b: &Span, new: &Span, cap: f64, budget: u64) -> (DevBracket, u64) {
    let finite = |pt: Point| pt.x.is_finite() && pt.y.is_finite();
    let span_ok = |s: &Span| match s {
        Span::Line { end } => finite(*end),
        Span::Cubic { control_one, control_two, end } =>
            finite(*control_one) && finite(*control_two) && finite(*end),
    };
    if !finite(p0) || !span_ok(a) || !span_ok(b) || !span_ok(new) || !cap.is_finite() {
        return (DevBracket::NonFinite, 0);
    }
    if budget < bracket_cost(SAMPLES, 2 * SAMPLES) {
        return (DevBracket::Indeterminate, 0);
    }
    let mut n_old = SAMPLES;
    let mut n_new = 2 * SAMPLES;
    let mut spent: u64 = 0;
    loop {
        let (bounds, pairs) = bracket_at(p0, a, b, new, n_old, n_new);
        spent += pairs;
        let Some((lower, upper)) = bounds
            else { return (DevBracket::NonFinite, spent) };
        if upper.hi <= cap { return (DevBracket::Within(upper.hi), spent); }
        if lower.lo > cap { return (DevBracket::Beyond(lower.lo), spent); }
        // Refine: full doubling while affordable, then one capped final round.
        let (want_old, want_new) = if spent + bracket_cost(2 * n_old, 2 * n_new) <= budget {
            (2 * n_old, 2 * n_new)
        } else {
            let remaining = budget - spent;
            // largest n with 2*(2n+1)*(2n+1) <= remaining, keeping n_new = 2 n_old
            let n = (((remaining / 2) as f64).sqrt() as u64).saturating_sub(1) / 2;
            let n = n as usize;
            if n <= n_old { return (DevBracket::Indeterminate, spent); }
            (n, 2 * n)
        };
        n_old = want_old;
        n_new = want_new;
    }
}

/// One candidate's deviation decision under the whole-glyph budget. The
/// per-candidate allowance is min(DEV_WORK_BUDGET, remaining glyph budget);
/// a spent glyph budget yields Indeterminate without work. `glyph_spent`
/// accumulates across all candidates, rings and removal rounds of a run.
fn eval_dev(p0: Point, a: &Span, b: &Span, new: &Span, cap: f64, glyph_spent: &mut u64) -> DevBracket {
    let allowance = DEV_WORK_BUDGET.min(DEV_GLYPH_WORK_BUDGET.saturating_sub(*glyph_spent));
    let (decision, spent) = bracket_dev(p0, a, b, new, cap, allowance);
    *glyph_spent = glyph_spent.saturating_add(spent);
    decision
}

// Exact reject-fast pre-screen (same contract as lever_api::area_error_below):
// every coverage term is |cov-ink| in [0,1], so the raw error sum is <= w*h and
// total = sum*scale*scale. If (w*h)*scale*scale is finite, EVERY area_error on
// this mask is finite, so a None from area_error_below means a finite total
// strictly above the limit: a certain `dj > 0` reject, skipped exactly.
#[cfg(not(test))]
fn node_prescreen_enabled() -> bool { true }
#[cfg(test)]
fn node_prescreen_enabled() -> bool { NODE_PRESCREEN_ENABLED.load(std::sync::atomic::Ordering::SeqCst) }
#[cfg(test)]
static NODE_PRESCREEN_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
#[cfg(test)]
thread_local! { static NODE_PRESCREEN_FIRED: std::cell::Cell<usize> = std::cell::Cell::new(0); }
/// strict successor of a nonnegative finite f64 (area + gain is always >= 0 here)
fn next_up_nn(x: f64) -> f64 { debug_assert!(x.is_finite() && x >= 0.0); f64::from_bits(x.to_bits() + 1) }

/// Per-span missing-extrema contribution: the exact per-span term
/// lever_api::missing_extrema sums (integer arithmetic, so a candidate's
/// delta is bit-exact against the full scan).
fn roots_contrib(prev: Point, s: &Span) -> usize {
    match s {
        Span::Line { .. } => 0,
        Span::Cubic { control_one: a, control_two: b, end } =>
            interior_roots(prev.x, a.x, b.x, end.x) as usize + interior_roots(prev.y, a.y, b.y, end.y) as usize,
    }
}

/// flatten_budget chord contribution of ONE span with the serial per-span
/// checks (flatten_budget.rs formula parity: same d(), same ceil, the same
/// f64 comparison before the cast). Ok(n) is integer-exact: every span that
/// survives into `cur` passed this check when it entered (input guard or a
/// candidate flatten_guard), so its pixel points are finite and its needed
/// count in budget; only the candidate's merged span can trip the typed
/// paths, and then SerialFallback makes the caller run the serial
/// flatten_guard on the swapped-in trial for the exact typed result.
#[derive(Clone, Copy)]
enum ChordContrib { Ok(usize), SerialFallback }
fn chord_contrib(mask: &SourceMask, from: Point, s: &Span, max_total: usize) -> ChordContrib {
    let px = |p: Point| -> Option<(f64, f64)> {
        let q = mask.to_pixel(p);
        if q.0.is_finite() && q.1.is_finite() { Some(q) } else { None }
    };
    match s {
        Span::Line { end } => match px(*end) { Some(_) => ChordContrib::Ok(1), None => ChordContrib::SerialFallback },
        Span::Cubic { control_one, control_two, end } => {
            let (Some(p0), Some(p1), Some(p2), Some(p3)) = (px(from), px(*control_one), px(*control_two), px(*end))
                else { return ChordContrib::SerialFallback };
            let d = |a: (f64, f64), b: (f64, f64)| ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
            let len = d(p0, p1) + d(p1, p2) + d(p2, p3);
            if !len.is_finite() { return ChordContrib::SerialFallback; }
            let needed = len.ceil() + 1.0; // compared as f64 BEFORE the cast (serial parity)
            if needed > max_total as f64 { return ChordContrib::SerialFallback; }
            ChordContrib::Ok(needed as usize)
        }
    }
}

/// Cached filter-phase decision for one (ring, node) candidate. The decision
/// is a pure function of ring content, ids, `protected` and dev_cap, so a
/// cached value is a bit-identical recomputation; only the ring an applied
/// removal touched is rebuilt next round. Failed stores the typed error the
/// serial evaluation returns at this candidate's exact iteration position
/// (deferred, never swallowed, returned at most once: the run aborts there).
enum CandEntry { Filtered, Cand(Span, Point, Point) }
struct RingCache { version: u64, entries: Vec<CandEntry> }

#[cfg(not(test))]
fn node_incremental_enabled() -> bool { true }
#[cfg(test)]
fn node_incremental_enabled() -> bool { NODE_INCREMENTAL_ENABLED.load(std::sync::atomic::Ordering::SeqCst) }
#[cfg(test)]
static NODE_INCREMENTAL_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

/// Sorted-pool driver (lever A, node-economy eval elimination). The greedy
/// full scan re-evaluates every surviving candidate's trial area_error every
/// round; W6 measurement (g: 109 candidates x 95 rounds = 5890 calls) shows
/// only the popped candidate's ring neighbours get fresh values. The pool
/// memoizes each candidate's trial evaluation and re-derives dj from the
/// cached value with the CURRENT running area (area shifts every round, so a
/// persistent sorted structure would re-key every entry anyway; the memoized
/// scan in serial scan order IS the sorted pool's decision, with the index
/// tie-break exact by construction). Bit-identity vs the serial full scan is
/// NOT proven for all inputs: DECLARED RISK (land-track, Chief-approved
/// 2026-10-17): da = e_cached - area uses a global-sum value whose bits can
/// in theory shift by f64 reassociation (~1e-13) after removals in disjoint
/// regions; no flip was observed on W6 real-g or the oracle battery, and the
/// dual-driver oracle (exact ties + randomized fuzz) is the land gate, not a
/// formal proof. A single ulp flip anywhere in the battery = no land, fall
/// back to plan B (da-cache + ring-version).
#[cfg(not(test))]
fn node_pool_enabled() -> bool { true }
#[cfg(test)]
fn node_pool_enabled() -> bool { NODE_POOL_ENABLED.load(std::sync::atomic::Ordering::SeqCst) }
#[cfg(test)]
static NODE_POOL_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
// cfg(test) eval counter: candidate area_error / area_error_below calls in
// the greedy loop (the W6 5890 metric), for serial-vs-pool measurements.
#[cfg(test)]
thread_local! { static NODE_EVAL_CALLS: std::cell::Cell<usize> = std::cell::Cell::new(0); }
#[cfg(test)]
static NODE_POOL_PROBE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
#[cfg(test)]
static NODE_POOL_DRIFT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

/// Cached trial evaluation for one (ring, node) candidate. Validity: a
/// removal only rewrites its own ring's local spans, so non-neighbour
/// candidates keep their filter-phase inputs, integer guard contributions
/// and (oracle-gated) trial area value; neighbours {k-1, k} post-splice are
/// dropped. PrescreenRejected stays a certain reject while area <= area_eval
/// (monotone next_up_nn limit; under STRICT area is non-increasing so the
/// skip is permanent).
#[derive(Clone, Copy)]
enum MemoEval {
    /// da = e_trial - area at the EVALUATION round. Reused verbatim on later
    /// rounds: the trial's global-sum value shifts by exactly the running
    /// area's shift (A_t - A_s cancels area_t - area_s), so da is the stable
    /// quantity; e alone is NOT (probe-confirmed ~1-3 per round drift).
    Full { da: f64 },
    PrescreenRejected { area_eval: f64 },
}
#[derive(Clone, Copy)]
enum MemoChords { Exact { a0: usize, a1: usize, an: usize }, Fallback }
/// Cached evaluation plus the geometry needed to test whether a later
/// removal's change region can touch this candidate's trial pixels.
#[derive(Clone)]
struct EvalMemo {
    old_c2: usize,
    new_c2: usize,
    chords: MemoChords,
    eval: MemoEval,
    new_span: Span,
    from: Point,
    // Cached evaluation geometry used to test whether a later removal can touch trial pixels.
    #[allow(dead_code)]
    end_b: Point,
}

/// Dilated pixel bbox of a set of points (control hull of the spans involved
/// in one candidate/removal). Dilation covers the flatten kernel reach (1px,
/// see accumulate/coverage_accumulate_into) plus chord discretisation.
fn px_bbox(m: &SourceMask, pts: &[Point]) -> (usize, usize, usize, usize) {
    let (mut x0, mut y0, mut x1, mut y1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for p in pts {
        let q = m.to_pixel(*p);
        x0 = x0.min(q.0); y0 = y0.min(q.1); x1 = x1.max(q.0); y1 = y1.max(q.1);
    }
    const D: i64 = 1; // flatten kernel reach, mirrors coverage_accumulate_into's own bbox guard
    let cx = |v: f64, hi: usize| -> usize { (v as i64 - D).clamp(0, hi.saturating_sub(1) as i64) as usize };
    let cx1 = |v: f64, hi: usize| -> usize { (v as i64 + D).clamp(0, hi.saturating_sub(1) as i64) as usize };
    (cx(x0.floor(), m.w), cx(y0.floor(), m.h), cx1(x1.ceil(), m.w), cx1(y1.ceil(), m.h))
}
fn span_points(from: Point, s: &Span, out: &mut Vec<Point>) {
    out.push(from);
    match s { Span::Line { end } => out.push(*end), Span::Cubic { control_one, control_two, end } => { out.push(*control_one); out.push(*control_two); out.push(*end); } }
}
fn bb_overlap(a: (usize, usize, usize, usize), b: (usize, usize, usize, usize)) -> bool {
    a.0 <= b.2 && b.0 <= a.2 && a.1 <= b.3 && b.1 <= a.3
}

fn run(rings: &[ReferenceRing], mask: &SourceMask, policy: Policy, budget: &NodeBudget, protected: &Protected)
    -> Result<(Vec<ReferenceRing>, Vec<Removal>), LeverError> {
    if node_pool_enabled() { return run_pool(rings, mask, policy, budget, protected); }
    if !mask.valid() { return Err(LeverError::BadMask); }
    // a protected identity that does not exist is a contract error, never silently ignored
    for &(ri, ni) in protected {
        match rings.get(ri) {
            Some(r) if ni < r.spans.len() => {}
            _ => return Err(LeverError::Violation(format!("protected node ({ri},{ni}) does not exist in the input"))),
        }
    }
    if !(policy.slack.is_finite() && policy.slack >= 0.0) { return Err(LeverError::Violation("bad slack".into())); }
    for (i, r) in rings.iter().enumerate() {
        if !closed(r) { return Err(LeverError::NonClosedRing { ring: i }); }
        if !ring_int(r) { return Err(LeverError::NonIntegerInput { ring: i }); }
        let cap = budget.max_nodes_per_ring.get(i).copied().unwrap_or(r.spans.len());
        if r.spans.len() > cap { return Err(LeverError::NodeCeiling { ring: i, got: r.spans.len(), max: cap }); }
    }
    let nb = count_nodes(rings);
    if nb > budget.max_nodes { return Err(LeverError::NodeCeiling { ring: usize::MAX, got: nb, max: budget.max_nodes }); }
    let mut cur_chords = flatten_guard(rings, mask)?; // input, before the first area_error
    let c2_in = missing_extrema(rings);
    // Incremental integer-exact guard state (cur == rings here, so these hold
    // the full-scan values). flatten_guard above proved w*h > 0 and
    // non-overflowing, so max_total_segments is Some.
    let mut cur_c2: usize = c2_in;
    let Some(max_total) = crate::flatten_budget::max_total_segments(mask.w, mask.h) else {
        return Err(LeverError::Violation("flatten budget refused: no MAX_TOTAL_SEGMENTS (w*h)".into()));
    };
    let mut cur = rings.to_vec();
    // ids[ri][j] = original node index of the current node j (stable lineage through removals)
    let mut ids: Vec<Vec<usize>> = rings.iter().map(|r| (0..r.spans.len()).collect()).collect();
    let mut area = area_error(&cur, mask);
    // numerical-failure guard: a non-finite objective is an INPUT failure, reported typed, never a skipped candidate.
    if !area.is_finite() { return Err(LeverError::Violation(format!("non-finite source objective on input (area_error={area})"))); }
    let mut removed = Vec::new();
    let dev_cap = mask.scale / 2.0;
    let mut glyph_spent: u64 = 0;
    // one-time finiteness anchor: (w*h)*scale*scale finite proves every
    // area_error on this mask finite (per-pixel term in [0,1], sum <= w*h).
    // When it fails, the pre-screen is disabled and the plain eval path
    // (with its non-finite -> typed refusal behaviour) runs verbatim.
    let prescreen_anchor = ((mask.w as f64) * (mask.h as f64) * mask.scale) * mask.scale;
    let prescreen_ok = node_prescreen_enabled() && prescreen_anchor.is_finite();
    // Filter-phase cache: rebuilt only for the ring an applied removal
    // touched (u64::MAX forces the first build). See CandEntry.
    let mut versions: Vec<u64> = vec![0; cur.len()];
    let mut filt: Vec<RingCache> = (0..cur.len()).map(|_| RingCache { version: u64::MAX, entries: Vec::new() }).collect();
    loop {
        // best candidate: (delta_j, ring, k, new span, delta_area, gain)
        let mut best: Option<(f64, usize, usize, Span, f64, f64)> = None;
        for ri in 0..cur.len() {
            let n = cur[ri].spans.len();
            if n <= 3 { continue; }
            let incremental_on = node_incremental_enabled();
            if incremental_on && filt[ri].version != versions[ri] {
                let mut entries: Vec<CandEntry> = Vec::with_capacity(n - 1);
                {
                    let r = &cur[ri];
                    let nodes: Vec<Point> = r.spans.iter().map(end_of).collect();
                    for k in 0..n - 1 {
                        let from = if k == 0 { r.start } else { nodes[k - 1] };
                        let (a, b) = (&r.spans[k], &r.spans[k + 1]);
                        let (pm, pn) = (nodes[(k + n - 1) % n], nodes[(k + 1) % n]);
                        let m = nodes[k];
                        entries.push(
                            if protected.contains(&(ri, ids[ri][k])) { CandEntry::Filtered }
                            else if is_ext(m.x, pm.x, pn.x) || is_ext(m.y, pm.y, pn.y) { CandEntry::Filtered }
                            else if !smooth(from, a, b) { CandEntry::Filtered }
                            else {
                                match merge(from, a, b) {
                                    None => CandEntry::Filtered,
                                    Some(new) => {
                                        if !span_finite(&new) { return Err(LeverError::Violation(format!("non-finite merged span (ring {ri}, node {k})"))) }
                                        else {
                                            match eval_dev(from, a, b, &new, dev_cap, &mut glyph_spent) {
                                                DevBracket::Within(_) => CandEntry::Cand(new, from, nodes[k + 1]),
                                                DevBracket::Beyond(_) | DevBracket::Indeterminate => CandEntry::Filtered,
                                                DevBracket::NonFinite => return Err(LeverError::Violation(format!("non-finite deviation (ring {ri}, node {k})"))),
                                            }
                                        }
                                    }
                                }
                            }
                        );
                    }
                }
                filt[ri] = RingCache { version: versions[ri], entries };
            }
            // k = index of dropped node; node n-1 is the start node, never dropped
            for k in 0..n - 1 {
                // filter phase: cached pure recomputation (incremental mode)
                // or the serial inline evaluation (hook off, verbatim).
                let cand: Option<(Span, Point, Point)> = if incremental_on {
                    match &filt[ri].entries[k] {
                        CandEntry::Filtered => None,
                        CandEntry::Cand(cn, cf, ce) => Some((cn.clone(), *cf, *ce)),
                    }
                } else {
                    let cand: Option<(Span, Point, Point)> = {
                        let r = &cur[ri];
                        let nodes: Vec<Point> = r.spans.iter().map(end_of).collect();
                        let from = if k == 0 { r.start } else { nodes[k - 1] };
                        let (a, b) = (&r.spans[k], &r.spans[k + 1]);
                        let (pm, pn) = (nodes[(k + n - 1) % n], nodes[(k + 1) % n]);
                        let m = nodes[k];
                        if protected.contains(&(ri, ids[ri][k])) { None }
                        else if is_ext(m.x, pm.x, pn.x) || is_ext(m.y, pm.y, pn.y) { None }
                        else if !smooth(from, a, b) { None }
                        else {
                            match merge(from, a, b) {
                                None => None,
                                Some(new) => {
                                    if !span_finite(&new) { return Err(LeverError::Violation(format!("non-finite merged span (ring {ri}, node {k})"))); }
                                    match eval_dev(from, a, b, &new, dev_cap, &mut glyph_spent) {
                                        DevBracket::Within(_) => Some((new, from, nodes[k + 1])),
                                        DevBracket::Beyond(_) | DevBracket::Indeterminate => None,
                                        DevBracket::NonFinite => return Err(LeverError::Violation(format!("non-finite deviation (ring {ri}, node {k})"))),
                                    }
                                }
                            }
                        }
                    };
                    cand
                };
                let Some((new, from, end_b)) = cand else { continue };
                let gain = policy.slack * dev_cap * len(sub(end_b, from));
                // Integer-exact trial guards (incremental mode): c2 and the
                // chord budget are integer counts, so per-candidate deltas
                // reproduce the full scans exactly (roots_contrib /
                // ChordContrib). trial_chords None = the serial flatten call
                // below decides (typed-error paths exact by construction).
                let (c2_trial, trial_chords) = if incremental_on {
                    let old_c2 = roots_contrib(from, &cur[ri].spans[k])
                        + roots_contrib(end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1]);
                    let tc = match (chord_contrib(mask, from, &cur[ri].spans[k], max_total),
                                    chord_contrib(mask, end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1], max_total),
                                    chord_contrib(mask, from, &new, max_total)) {
                        (ChordContrib::Ok(a0), ChordContrib::Ok(a1), ChordContrib::Ok(an)) =>
                            cur_chords.checked_sub(a0).and_then(|v| v.checked_sub(a1)).and_then(|v| v.checked_add(an)),
                        _ => None,
                    };
                    (cur_c2 - old_c2 + roots_contrib(from, &new), tc)
                } else {
                    (0, None)
                };
                // evaluate the trial state in place (single-ring clone + swap, restored
                // right after): the checked ring set is identical to the old full clone.
                let mut trial_ring = cur[ri].clone();
                trial_ring.spans.splice(k..k + 2, [new.clone()]);
                let saved = std::mem::replace(&mut cur[ri], trial_ring);
                let c2_ok = if incremental_on { c2_trial <= c2_in } else { missing_extrema(&cur) <= c2_in };
                let mut da = None;
                if c2_ok {
                    let chords_ok = match trial_chords {
                        Some(t) if t <= max_total => true,
                        _ => match flatten_guard(&cur, mask) { // candidate, before its area_error
                            Ok(_) => true,
                            Err(e) => { cur[ri] = saved; return Err(e); }
                        },
                    };
                    if chords_ok {
                            // Pre-screen: None proves e_trial > area + gain
                            // (limit is the strict successor, so da == gain
                            // exactly still runs the full eval), i.e. dj > 0:
                            // a certain reject. gain non-finite falls back to
                            // the plain eval so the typed refusal below is
                            // bit-identical to the old order.
                            if prescreen_ok && gain.is_finite() {
                                #[cfg(test)]
                                NODE_EVAL_CALLS.with(|c| c.set(c.get() + 1));
                                match crate::lever_api::area_error_below(&cur, mask, next_up_nn(area + gain)) {
                                    None => {
                                        #[cfg(test)]
                                        NODE_PRESCREEN_FIRED.with(|c| c.set(c.get() + 1));
                                        cur[ri] = saved;
                                        continue;
                                    }
                                    Some(e) => da = Some(e - area),
                                }
                            } else {
                                #[cfg(test)]
                                NODE_EVAL_CALLS.with(|c| c.set(c.get() + 1));
                                da = Some(area_error(&cur, mask) - area);
                            }
                    }
                }
                cur[ri] = saved;
                if !c2_ok { continue; }
                let da = da.unwrap();
                let dj = da - gain;
                // NaN would make `dj > 0.0` false and ACCEPT the removal: reject the whole run instead.
                if !(da.is_finite() && gain.is_finite() && dj.is_finite()) {
                    return Err(LeverError::Violation(format!("non-finite objective (ring {ri}, node {k}): da={da} gain={gain} dj={dj}")));
                }
                // removal is taken only if the added area is within the noise allowance (dj <= 0);
                // slack 0 requires da <= 0 exactly.
                if dj > 0.0 { continue; }
                if best.as_ref().map_or(true, |x| dj < x.0) { best = Some((dj, ri, k, new, da, gain)); }
            }
        }
        match best {
            None => break,
            Some((_, ri, k, new, da, gain)) => {
                let node = end_of(&cur[ri].spans[k]);
                let from = if k == 0 { cur[ri].start } else { end_of(&cur[ri].spans[k - 1]) };
                // advance the integer-exact guard state with the same deltas
                // the candidate evaluation measured (no f64 involvement)
                let old_c2 = roots_contrib(from, &cur[ri].spans[k])
                    + roots_contrib(end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1]);
                let new_c2 = roots_contrib(from, &new);
                let chord_next = match (chord_contrib(mask, from, &cur[ri].spans[k], max_total),
                                        chord_contrib(mask, end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1], max_total),
                                        chord_contrib(mask, from, &new, max_total)) {
                    (ChordContrib::Ok(a0), ChordContrib::Ok(a1), ChordContrib::Ok(an)) =>
                        cur_chords.checked_sub(a0).and_then(|v| v.checked_sub(a1)).and_then(|v| v.checked_add(an)),
                    _ => None,
                };
                cur[ri].spans.splice(k..k + 2, [new]);
                cur_c2 = cur_c2 - old_c2 + new_c2;
                cur_chords = match chord_next {
                    Some(t) => t,
                    // unreachable while the finiteness induction holds; the
                    // serial call is the exact value either way
                    None => flatten_guard(&cur, mask)?,
                };
                versions[ri] += 1;
                area += da;
                let original_node = ids[ri].remove(k);
                removed.push(Removal { ring: ri, original_node, node_end: node, delta_area: da, gain_bound: gain });
            }
        }
    }
    if !area.is_finite() { return Err(LeverError::Violation("non-finite running objective at exit".into())); }
    if count_nodes(&cur) > nb { return Err(LeverError::Violation("node count increased".into())); }
    if missing_extrema(&cur) > c2_in { return Err(LeverError::Violation("C2 increased".into())); }
    Ok((cur, removed))
}


/// Sorted-pool twin of the serial greedy loop in run(): identical preamble,
/// identical per-candidate eval sequence (filter cache, integer guards,
/// pre-screen, trial swap), identical best-pick scan order and removal
/// application; the only difference is that a candidate with a valid
/// EvalMemo skips its area_error / area_error_below call and re-derives
/// da/dj from the cached trial value with the CURRENT running area.
/// Bit-identity vs run() is enforced by the pool_tests dual-driver oracle,
/// not assumed (see node_pool_enabled comment).
fn run_pool(rings: &[ReferenceRing], mask: &SourceMask, policy: Policy, budget: &NodeBudget, protected: &Protected)
    -> Result<(Vec<ReferenceRing>, Vec<Removal>), LeverError> {
    if !mask.valid() { return Err(LeverError::BadMask); }
    // a protected identity that does not exist is a contract error, never silently ignored
    for &(ri, ni) in protected {
        match rings.get(ri) {
            Some(r) if ni < r.spans.len() => {}
            _ => return Err(LeverError::Violation(format!("protected node ({ri},{ni}) does not exist in the input"))),
        }
    }
    if !(policy.slack.is_finite() && policy.slack >= 0.0) { return Err(LeverError::Violation("bad slack".into())); }
    for (i, r) in rings.iter().enumerate() {
        if !closed(r) { return Err(LeverError::NonClosedRing { ring: i }); }
        if !ring_int(r) { return Err(LeverError::NonIntegerInput { ring: i }); }
        let cap = budget.max_nodes_per_ring.get(i).copied().unwrap_or(r.spans.len());
        if r.spans.len() > cap { return Err(LeverError::NodeCeiling { ring: i, got: r.spans.len(), max: cap }); }
    }
    let nb = count_nodes(rings);
    if nb > budget.max_nodes { return Err(LeverError::NodeCeiling { ring: usize::MAX, got: nb, max: budget.max_nodes }); }
    let mut cur_chords = flatten_guard(rings, mask)?; // input, before the first area_error
    let c2_in = missing_extrema(rings);
    let mut cur_c2: usize = c2_in;
    let Some(max_total) = crate::flatten_budget::max_total_segments(mask.w, mask.h) else {
        return Err(LeverError::Violation("flatten budget refused: no MAX_TOTAL_SEGMENTS (w*h)".into()));
    };
    let mut cur = rings.to_vec();
    let mut ids: Vec<Vec<usize>> = rings.iter().map(|r| (0..r.spans.len()).collect()).collect();
    let mut area = area_error(&cur, mask);
    if !area.is_finite() { return Err(LeverError::Violation(format!("non-finite source objective on input (area_error={area})"))); }
    let mut removed = Vec::new();
    let dev_cap = mask.scale / 2.0;
    let mut glyph_spent: u64 = 0;
    let prescreen_anchor = ((mask.w as f64) * (mask.h as f64) * mask.scale) * mask.scale;
    let prescreen_ok = node_prescreen_enabled() && prescreen_anchor.is_finite();
    let mut versions: Vec<u64> = vec![0; cur.len()];
    let mut filt: Vec<RingCache> = (0..cur.len()).map(|_| RingCache { version: u64::MAX, entries: Vec::new() }).collect();
    // per-ring candidate evaluation memos, parallel to filt[ri].entries
    let mut memo: Vec<Vec<Option<EvalMemo>>> = (0..cur.len()).map(|_| Vec::new()).collect();
    loop {
        // best candidate: (delta_j, ring, k, new span, delta_area, gain) — serial scan order.
        // Three passes (pop-revalidate, Chief-approved band rule):
        //  pass 1: cached/cheap per-candidate values (dirty or missing memos
        //          are marked NeedsEval; PrescreenRejected contributes its
        //          approximate lower bound).
        //  pass 2: fresh serial eval for NeedsEval candidates AND for every
        //          cached value inside the uncertainty band [M, M + 2*eps]
        //          around the cached min M — the true argmin is provably in
        //          the band whenever every cached value drifted by <= eps
        //          (eps is a DECLARED CONVENTION: 2^-30 * max(1, |area|);
        //          measured drift is <= 64 ulps of the objective, five
        //          orders below eps; oracle fuzz is the gate).
        //  pass 3: argmin over the round values in serial scan order with
        //          the serial strict-< tie-break; band members carry FRESH
        //          values, so the accepted candidate's recorded da is
        //          bit-exact against the serial driver.
        let mut round: Vec<Vec<Option<(f64, f64, bool)>>> = Vec::with_capacity(cur.len()); // (dj, da, is_prescreen_lb)
        let mut cached_min = f64::INFINITY;
        for ri in 0..cur.len() {
            let n = cur[ri].spans.len();
            if n <= 3 { round.push(Vec::new()); continue; }
            if filt[ri].version != versions[ri] {
                let mut entries: Vec<CandEntry> = Vec::with_capacity(n - 1);
                {
                    let r = &cur[ri];
                    let nodes: Vec<Point> = r.spans.iter().map(end_of).collect();
                    for k in 0..n - 1 {
                        let from = if k == 0 { r.start } else { nodes[k - 1] };
                        let (a, b) = (&r.spans[k], &r.spans[k + 1]);
                        let (pm, pn) = (nodes[(k + n - 1) % n], nodes[(k + 1) % n]);
                        let m = nodes[k];
                        entries.push(
                            if protected.contains(&(ri, ids[ri][k])) { CandEntry::Filtered }
                            else if is_ext(m.x, pm.x, pn.x) || is_ext(m.y, pm.y, pn.y) { CandEntry::Filtered }
                            else if !smooth(from, a, b) { CandEntry::Filtered }
                            else {
                                match merge(from, a, b) {
                                    None => CandEntry::Filtered,
                                    Some(new) => {
                                        if !span_finite(&new) { return Err(LeverError::Violation(format!("non-finite merged span (ring {ri}, node {k})"))) }
                                        else {
                                            match eval_dev(from, a, b, &new, dev_cap, &mut glyph_spent) {
                                                DevBracket::Within(_) => CandEntry::Cand(new, from, nodes[k + 1]),
                                                DevBracket::Beyond(_) | DevBracket::Indeterminate => CandEntry::Filtered,
                                                DevBracket::NonFinite => return Err(LeverError::Violation(format!("non-finite deviation (ring {ri}, node {k})"))),
                                            }
                                        }
                                    }
                                }
                            }
                        );
                    }
                }
                filt[ri] = RingCache { version: versions[ri], entries };
                if memo[ri].len() != n - 1 { memo[ri].clear(); memo[ri].resize(n - 1, None); }
            }
            let mut row: Vec<Option<(f64, f64, bool)>> = vec![None; n - 1]; // (dj, da, is_prescreen_lb)
            for k in 0..n - 1 {
                let cand: Option<(Span, Point, Point)> = match &filt[ri].entries[k] {
                    CandEntry::Filtered => None,
                    CandEntry::Cand(cn, cf, ce) => Some((cn.clone(), *cf, *ce)),
                };
                let Some((_new, from, end_b)) = cand else { continue };
                let gain = policy.slack * dev_cap * len(sub(end_b, from));
                // cached value validity + cheap integer guards (serial parity:
                // same formulas, recomputed against the CURRENT guard state)
                let valid = match &memo[ri][k] {
                    Some(m) => match m.eval {
                        MemoEval::Full { .. } => true,
                        MemoEval::PrescreenRejected { area_eval } => area <= area_eval,
                    },
                    None => false,
                };
                if !valid { continue; } // NeedsEval: row stays None
                let m = memo[ri][k].as_ref().unwrap();
                if cur_c2 - m.old_c2 + m.new_c2 > c2_in { continue; } // c2 guard fails this round: serial skips
                let exact = match m.chords {
                    MemoChords::Exact { a0, a1, an } =>
                        cur_chords.checked_sub(a0).and_then(|v| v.checked_sub(a1)).and_then(|v| v.checked_add(an)),
                    MemoChords::Fallback => None,
                };
                match exact {
                    Some(t) if t <= max_total => {}
                    _ => {
                        let mut trial_ring = cur[ri].clone();
                        trial_ring.spans.splice(k..k + 2, [_new.clone()]);
                        let saved = std::mem::replace(&mut cur[ri], trial_ring);
                        if let Err(e) = flatten_guard(&cur, mask) { cur[ri] = saved; return Err(e); }
                        cur[ri] = saved;
                    }
                }
                let (dj, da, is_pr) = match m.eval {
                    MemoEval::Full { da } => {
                        let dj = da - gain;
                        if !(da.is_finite() && gain.is_finite() && dj.is_finite()) {
                            return Err(LeverError::Violation(format!("non-finite objective (ring {ri}, node {k}): da={da} gain={gain} dj={dj}")));
                        }
                        (dj, da, false)
                    }
                    // approximate lower bound of the fresh dj: e >= next_up(area_eval + gain),
                    // so the true dj is PROVABLY > 0 while the memo is valid (exact
                    // arithmetic, not a drift bound): the row can never be the round
                    // argmin (a <= 0 row always wins; all-> 0 ends the round), so band
                    // re-evaluation is provably wasted on it. Always > 0 while valid,
                    // so pass 3 skips it; da unused.
                    MemoEval::PrescreenRejected { area_eval } => { let lb = next_up_nn(area_eval + gain) - area - gain; (lb, lb, true) }
                };
                row[k] = Some((dj, da, is_pr));
                if dj < cached_min { cached_min = dj; }
            }
            round.push(row);
        }
        // pass 2: fresh serial evaluation for NeedsEval candidates and for
        // every cached value inside the uncertainty band around cached_min.
        let eps = f64::powi(2.0, -30) * area.abs().max(1.0); // DECLARED CONVENTION, see pass-2 comment
        let band = cached_min + 2.0 * eps;
        for ri in 0..cur.len() {
            let n = cur[ri].spans.len();
            if n <= 3 { continue; }
            for k in 0..n - 1 {
                let needs = match round[ri][k] {
                    Some((dj, _, is_pr)) => !is_pr && dj <= band,
                    None => matches!(filt[ri].entries[k], CandEntry::Cand(..)),
                };
                if !needs { continue; }
                let (new, from, end_b) = match &filt[ri].entries[k] {
                    CandEntry::Cand(cn, cf, ce) => (cn.clone(), *cf, *ce),
                    _ => continue, // Filtered rows (None, not a candidate)
                };
                let gain = policy.slack * dev_cap * len(sub(end_b, from));
                // verbatim serial evaluation sequence (single-ring clone +
                // swap, restored right after), then memo store.
                let old_c2 = roots_contrib(from, &cur[ri].spans[k])
                    + roots_contrib(end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1]);
                let new_c2 = roots_contrib(from, &new);
                let ca = chord_contrib(mask, from, &cur[ri].spans[k], max_total);
                let cb = chord_contrib(mask, end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1], max_total);
                let cn = chord_contrib(mask, from, &new, max_total);
                let trial_chords = match (ca, cb, cn) {
                    (ChordContrib::Ok(a0), ChordContrib::Ok(a1), ChordContrib::Ok(an)) =>
                        cur_chords.checked_sub(a0).and_then(|v| v.checked_sub(a1)).and_then(|v| v.checked_add(an)),
                    _ => None,
                };
                let memo_chords = match (ca, cb, cn) {
                    (ChordContrib::Ok(a0), ChordContrib::Ok(a1), ChordContrib::Ok(an)) => MemoChords::Exact { a0, a1, an },
                    _ => MemoChords::Fallback,
                };
                let mut trial_ring = cur[ri].clone();
                trial_ring.spans.splice(k..k + 2, [new.clone()]);
                let saved = std::mem::replace(&mut cur[ri], trial_ring);
                let c2_ok = cur_c2 - old_c2 + new_c2 <= c2_in;
                let mut da = None;
                let mut memo_eval = None;
                if c2_ok {
                    let chords_ok = match trial_chords {
                        Some(t) if t <= max_total => true,
                        _ => match flatten_guard(&cur, mask) { // candidate, before its area_error
                            Ok(_) => true,
                            Err(e) => { cur[ri] = saved; return Err(e); }
                        },
                    };
                    if chords_ok {
                        if prescreen_ok && gain.is_finite() {
                            #[cfg(test)]
                            NODE_EVAL_CALLS.with(|c| c.set(c.get() + 1));
                            match crate::lever_api::area_error_below(&cur, mask, next_up_nn(area + gain)) {
                                None => {
                                    #[cfg(test)]
                                    NODE_PRESCREEN_FIRED.with(|c| c.set(c.get() + 1));
                                    memo_eval = Some(MemoEval::PrescreenRejected { area_eval: area });
                                }
                                Some(e) => { da = Some(e - area); memo_eval = Some(MemoEval::Full { da: e - area }); }
                            }
                        } else {
                            #[cfg(test)]
                            NODE_EVAL_CALLS.with(|c| c.set(c.get() + 1));
                            let e = area_error(&cur, mask);
                            da = Some(e - area);
                            memo_eval = Some(MemoEval::Full { da: e - area });
                        }
                    }
                }
                cur[ri] = saved;
                if let Some(ev) = memo_eval {
                    memo[ri][k] = Some(EvalMemo { old_c2, new_c2, chords: memo_chords, eval: ev, new_span: new.clone(), from, end_b });
                }
                let Some(da) = da else { round[ri][k] = None; continue };
                let dj = da - gain;
                if !(da.is_finite() && gain.is_finite() && dj.is_finite()) {
                    return Err(LeverError::Violation(format!("non-finite objective (ring {ri}, node {k}): da={da} gain={gain} dj={dj}")));
                }
                round[ri][k] = Some((dj, da, false));
            }
        }
        // pass 3: serial scan order, strict-< keeps the first index on ties.
        let mut best: Option<(f64, usize, usize, Span, f64, f64)> = None;
        for ri in 0..cur.len() {
            let n = cur[ri].spans.len();
            if n <= 3 { continue; }
            for k in 0..n - 1 {
                let Some((dj, da, _)) = round[ri][k] else { continue };
                if dj > 0.0 { continue; }
                let (new, from, end_b) = match &filt[ri].entries[k] {
                    CandEntry::Cand(cn, cf, ce) => (cn.clone(), *cf, *ce),
                    _ => continue,
                };
                let gain = policy.slack * dev_cap * len(sub(end_b, from));
                if best.as_ref().map_or(true, |x| dj < x.0) { best = Some((dj, ri, k, new, da, gain)); }
            }
        }
        match best {
            None => break,
            Some((_, ri, k, new, da, gain)) => {
                let node = end_of(&cur[ri].spans[k]);
                let from = if k == 0 { cur[ri].start } else { end_of(&cur[ri].spans[k - 1]) };
                let old_c2 = roots_contrib(from, &cur[ri].spans[k])
                    + roots_contrib(end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1]);
                let new_c2 = roots_contrib(from, &new);
                let chord_next = match (chord_contrib(mask, from, &cur[ri].spans[k], max_total),
                                        chord_contrib(mask, end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1], max_total),
                                        chord_contrib(mask, from, &new, max_total)) {
                    (ChordContrib::Ok(a0), ChordContrib::Ok(a1), ChordContrib::Ok(an)) =>
                        cur_chords.checked_sub(a0).and_then(|v| v.checked_sub(a1)).and_then(|v| v.checked_add(an)),
                    _ => None,
                };
                // change region of this removal (BEFORE the splice): the two
                // old spans and the merged span, control hull in pixel space.
                let mut rb_pts = Vec::with_capacity(12);
                span_points(from, &cur[ri].spans[k], &mut rb_pts);
                span_points(end_of(&cur[ri].spans[k]), &cur[ri].spans[k + 1], &mut rb_pts);
                span_points(from, &new, &mut rb_pts);
                let rb = px_bbox(mask, &rb_pts);
                cur[ri].spans.splice(k..k + 2, [new]);
                cur_c2 = cur_c2 - old_c2 + new_c2;
                cur_chords = match chord_next {
                    Some(t) => t,
                    None => flatten_guard(&cur, mask)?,
                };
                versions[ri] += 1;
                area += da;
                let original_node = ids[ri].remove(k);
                removed.push(Removal { ring: ri, original_node, node_end: node, delta_area: da, gain_bound: gain });
                // memo remap for the spliced ring: post-splice candidate j is
                // the pre-splice candidate j (j < k-1), a DIRTY neighbour
                // (j in {k-1, k}: its span pair changed), or the pre-splice
                // candidate j+1 (j > k: identical node identity and spans).
                let n2 = cur[ri].spans.len();
                let old = std::mem::take(&mut memo[ri]);
                let mut nm: Vec<Option<EvalMemo>> = Vec::with_capacity(n2.saturating_sub(1));
                for j in 0..n2.saturating_sub(1) {
                    nm.push(if j == k || j + 1 == k { None }
                            else if j + 1 < k { old.get(j).cloned().flatten() }
                            else { old.get(j + 1).cloned().flatten() });
                }
                memo[ri] = nm;
                // Geometric dirty set (Chief-approved): an index neighbour
                // rule is NOT sufficient — W6's "popped + same-ring
                // neighbours fresh" holds on real glyphs where candidates are
                // sparse, but fuzz case 0 proved a candidate 3 index-steps
                // away changes value (~1.0, not ulp) when its trial region
                // pixel-overlaps the removal's change region. Candidates
                // whose change hull (both spans + cached merged span, kernel
                // dilation) intersects the removal's change hull are dirty;
                // disjoint hulls keep bit-identical pixel terms (net signed
                // row crossings of a path are endpoint-determined, so no
                // winding coupling reaches across disjoint intervals).
                for (rj, mj) in memo.iter_mut().enumerate() {
                    for (j, slot) in mj.iter_mut().enumerate() {
                        let Some(m2) = slot else { continue };
                        let mut cb_pts = Vec::with_capacity(12);
                        span_points(m2.from, &cur[rj].spans[j], &mut cb_pts);
                        span_points(end_of(&cur[rj].spans[j]), &cur[rj].spans[j + 1], &mut cb_pts);
                        span_points(m2.from, &m2.new_span, &mut cb_pts);
                        if bb_overlap(rb, px_bbox(mask, &cb_pts)) { *slot = None; }
                    }
                }
            }
        }
    }
    if !area.is_finite() { return Err(LeverError::Violation("non-finite running objective at exit".into())); }
    if count_nodes(&cur) > nb { return Err(LeverError::Violation("node count increased".into())); }
    if missing_extrema(&cur) > c2_in { return Err(LeverError::Violation("C2 increased".into())); }
    Ok((cur, removed))
}

fn max_disp_nodes(a: &[ReferenceRing], b: &[ReferenceRing]) -> f64 {
    // removals do not move surviving nodes except rounded handles; report max over surviving end nodes
    let mut m: f64 = 0.0;
    for (ra, rb) in a.iter().zip(b) {
        let ea: Vec<Point> = ra.spans.iter().map(end_of).collect();
        for s in &rb.spans { let p = end_of(s); let d = ea.iter().map(|q| len(sub(p, *q))).fold(f64::INFINITY, f64::min); m = m.max(d); }
    }
    m
}

/// Raster no-regression check in the same pixel-centre, nonzero-winding
/// semantics as the curve_stress proof/IoU measurement. SourceMask's frame
/// supplies the coordinate mapping; the comparison itself uses exact pixel
/// counts and admits no tolerance. This guards the global rendered result,
/// which a per-merge deviation bound cannot certify by itself.
fn proof_iou(rings: &[ReferenceRing], mask: &SourceMask) -> Option<crate::curve_stress::TileIou> {
    let tol = mask.scale / 2.0;
    let polys: Vec<Vec<(f64, f64)>> = rings.iter().map(|r| {
        crate::curve_stress::flatten_ring(r, tol).iter().map(|p| {
            let q = mask.to_pixel(*p);
            (q.0, (mask.h - 1) as f64 - q.1)
        }).collect()
    }).collect();
    let fill = crate::curve_stress::rasterize_nonzero(mask.w, mask.h, &polys);
    crate::curve_stress::tile_iou(&fill, &mask.ink)
}

/// Exact ratio comparison: after.iou >= before.iou iff
/// after.intersection / after.union >= before.intersection / before.union.
/// Integer cross-multiplication avoids any float tolerance or rounding gap.
fn iou_not_worse(before: Option<crate::curve_stress::TileIou>, after: Option<crate::curve_stress::TileIou>) -> bool {
    match (before, after) {
        (Some(b), Some(a)) =>
            (a.intersection as u128) * (b.union as u128) >= (b.intersection as u128) * (a.union as u128),
        (None, None) => true,
        _ => false,
    }
}

/// Run the lever, then enforce the global raster no-regression contract. A
/// regressive output is replaced by the exact input and reported as a
/// guard reversion, never silently mixed with accepted removals.
fn run_guarded(rings: &[ReferenceRing], mask: &SourceMask, policy: Policy, budget: &NodeBudget, protected: &Protected)
    -> Result<(Vec<ReferenceRing>, Vec<Removal>, bool), LeverError> {
    let (out, removed) = run(rings, mask, policy, budget, protected)?;
    if removed.is_empty() { return Ok((out, removed, false)); }
    if iou_not_worse(proof_iou(rings, mask), proof_iou(&out, mask)) {
        Ok((out, removed, false))
    } else {
        Ok((rings.to_vec(), Vec::new(), true))
    }
}

/// Single entry point for one policy. Any contract violation is an Err; no clipped result.
pub fn try_apply(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, policy: Policy) -> LeverResult {
    try_apply_protected(rings, mask, budget, policy, &Protected::new())
}
/// Same contract and guards as `try_apply`; nodes whose input identity is in `protected` are never removed.
/// Protection is checked before every removal against stable identity, so earlier removals do not shift it.
/// An empty set is byte-identical to `try_apply`. Out-of-range protected identities are a Violation.
pub fn try_apply_protected(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, policy: Policy, protected: &Protected) -> LeverResult {
    let (out, removed, reverted) = run_guarded(rings, mask, policy, budget, protected)?;
    let mut report = report_for(rings, &out, mask, policy, removed.len());
    if reverted { report.notes.push_str(" raster_iou_guard=reverted"); }
    Ok((out, report))
}
fn report_for(rings: &[ReferenceRing], out: &[ReferenceRing], mask: &SourceMask, policy: Policy, nrem: usize) -> LeverReport {
    LeverReport {
        lever: "node_objective", lever_id: LEVER_ID, api_version: LEVER_API_VERSION, stage_tag: STAGE_TAG,
        input_hash: hash_rings(rings), output_hash: hash_rings(out), seed: SEED,
        nodes_before: count_nodes(rings), nodes_after: count_nodes(out),
        area_before: area_error(rings, mask), area_after: area_error(out, mask),
        c2_missing: missing_extrema(out), max_node_displacement: max_disp_nodes(rings, out),
        notes: format!("slack={} removed={} flatten_chords_out={}", policy.slack, nrem, flatten_guard(out, mask).map(|n| n.to_string()).unwrap_or_else(|e| format!("{e:?}"))),
    }
}

/// Selectable candidate set for the default/economy selector: strict, half-noise, noise.
/// Candidates are monotone in node count (fewer or equal) and each is independently valid.
pub fn candidates(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget) -> Result<Vec<Candidate>, LeverError> {
    candidates_protected(rings, mask, budget, &Protected::new())
}
pub fn candidates_protected(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, protected: &Protected) -> Result<Vec<Candidate>, LeverError> {
    let mut v = Vec::new();
    for (name, policy) in [("n1-strict", Policy::STRICT), ("n1-half-noise", Policy::HALF_NOISE), ("n1-noise", Policy::NOISE)] {
        let (out, removed, reverted) = run_guarded(rings, mask, policy, budget, protected)?;
        let mut report = report_for(rings, &out, mask, policy, removed.len());
        if reverted { report.notes.push_str(" raster_iou_guard=reverted"); }
        let default_eligible = policy.slack == 0.0 && report.area_after <= report.area_before;
        v.push(Candidate { name, policy, rings: out, report, removed, default_eligible });
    }
    Ok(v)
}

#[cfg(test)]
mod prescreen_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// 10x10 square with collinear extra nodes (removal candidates).
    fn ring() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Line { end: p(3., 0.) }, Span::Line { end: p(6., 0.) }, Span::Line { end: p(10., 0.) },
            Span::Line { end: p(10., 5.) }, Span::Line { end: p(10., 10.) },
            Span::Line { end: p(0., 10.) }, Span::Line { end: p(0., 0.) } ] }
    }
    fn mask() -> SourceMask { let mut ink = vec![255u8; 144]; for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
        SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) } }
    fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: r.iter().map(|x| x.spans.len()).collect() } }

    /// Circular ink with an inscribed integer polygon: merging two chords
    /// shortcuts inside the circle (deviation ~0.08 < dev_cap 0.5 at scale 1)
    /// and strictly loses coverage, so candidates are dj > 0 rejects.
    fn circle_fixture(n: usize) -> (Vec<ReferenceRing>, SourceMask) {
        let mut ink = vec![255u8; 24 * 24];
        for j in 0..24 { for i in 0..24 {
            let (dx, dy) = (i as f64 - 11.5, j as f64 - 11.5);
            if dx * dx + dy * dy <= 81.0 { ink[j * 24 + i] = 0; }
        } }
        let m = SourceMask { w: 24, h: 24, ink, scale: 1.0, origin: (0.0, 24.0) };
        let pts: Vec<(f64, f64)> = (0..n).map(|i| {
            let t = i as f64 * std::f64::consts::TAU / n as f64;
            ((12.0 + 9.0 * t.cos()).round(), (12.0 + 9.0 * t.sin()).round())
        }).collect();
        let r = ReferenceRing { start: p(pts[0].0, pts[0].1), spans: pts[1..].iter().chain(std::iter::once(&pts[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect() };
        (vec![r], m)
    }

    /// Dual-driver oracle (cascade precedent): the pre-screen driver must be
    /// bit-identical to the plain area_error driver across policies and
    /// fixtures, and the skip must actually fire somewhere.
    #[test]
    fn prescreen_bit_identical_and_fires() {
        let mut fired_total = 0usize;
        for (input, m) in [circle_fixture(16), circle_fixture(24)] {
            for policy in [Policy::STRICT, Policy::HALF_NOISE, Policy::NOISE] {
                NODE_PRESCREEN_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
                let plain = try_apply(&input, &m, &budget(&input), policy).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
                NODE_PRESCREEN_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
                NODE_PRESCREEN_FIRED.with(|c| c.set(0));
                let pre = try_apply(&input, &m, &budget(&input), policy).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
                assert_eq!(plain, pre, "pre-screen must be bit-identical to the plain driver (policy {:?})", policy.slack);
                fired_total += NODE_PRESCREEN_FIRED.with(|c| c.get());
            }
        }
        assert!(fired_total > 0, "pre-screen must actually skip at least one certain reject");
    }

    /// The finiteness anchor: a mask whose scale^2 overflows the objective
    /// disables the pre-screen, preserving the old non-finite behaviour.
    #[test]
    fn prescreen_anchor_disabled_matches_plain() {
        let mut m = mask();
        m.scale = 1e200; // scale^2 overflows
        let input = vec![ring()];
        NODE_PRESCREEN_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
        let plain = try_apply(&input, &m, &budget(&input), Policy::STRICT).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
        NODE_PRESCREEN_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        let pre = try_apply(&input, &m, &budget(&input), Policy::STRICT).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
        assert_eq!(plain, pre);
    }
}

#[cfg(test)]
mod protected_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// 10x10 square drawn clockwise in font frame (y up), two collinear extra nodes on the bottom edge and one on the right edge.
    fn ring() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Line { end: p(3., 0.) }, Span::Line { end: p(6., 0.) }, Span::Line { end: p(10., 0.) },
            Span::Line { end: p(10., 5.) }, Span::Line { end: p(10., 10.) },
            Span::Line { end: p(0., 10.) }, Span::Line { end: p(0., 0.) } ] }
    }
    fn mask() -> SourceMask { let mut ink = vec![255u8; 144]; for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
        SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) } }
    fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: r.iter().map(|x| x.spans.len()).collect() } }
    fn nodes(r: &ReferenceRing) -> Vec<(f64, f64)> { r.spans.iter().map(|s| { let e = end_of(s); (e.x, e.y) }).collect() }
    #[test] fn empty_protected_is_identical_to_try_apply() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        let (a, ra) = try_apply(&r, &m, &b, Policy::STRICT).unwrap();
        let (c, rc) = try_apply_protected(&r, &m, &b, Policy::STRICT, &Protected::new()).unwrap();
        assert_eq!(hash_rings(&a), hash_rings(&c)); assert_eq!(ra.output_hash, rc.output_hash);
        assert!(count_nodes(&a) < count_nodes(&r), "fixture must be reducible, got {:?}", nodes(&a[0]));
    }
    #[test] fn protected_survives_and_identity_does_not_shift() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        // protect original node 1 (6,0) and node 3 (10,5)?? node 3 is index 3 -> (10,5)
        let prot: Protected = [(0usize, 1usize), (0usize, 3usize)].into_iter().collect();
        let (out, _) = try_apply_protected(&r, &m, &b, Policy::STRICT, &prot).unwrap();
        let n = nodes(&out[0]);
        assert!(n.contains(&(6., 0.)) && n.contains(&(10., 5.)), "{n:?}");
        // the unprotected collinear node (3,0), earlier in the ring, may be removed, which shifts later indices:
        assert!(!n.contains(&(3., 0.)), "unprotected node 0 should go: {n:?}");
        assert!(count_nodes(&out) <= count_nodes(&r));
    }
    #[test] fn protecting_everything_removable_keeps_input() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        let prot: Protected = (0..r[0].spans.len()).map(|i| (0usize, i)).collect();
        let (out, rep) = try_apply_protected(&r, &m, &b, Policy::STRICT, &prot).unwrap();
        assert_eq!(hash_rings(&out), hash_rings(&r)); assert_eq!(rep.nodes_before, rep.nodes_after);
    }
    #[test] fn missing_protected_identity_is_rejected() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        for bad in [(1usize, 0usize), (0, 99)] {
            let prot: Protected = [bad].into_iter().collect();
            assert!(matches!(try_apply_protected(&r, &m, &b, Policy::STRICT, &prot), Err(LeverError::Violation(_))));
        }
    }
    #[test] fn removal_reports_original_identity_and_candidates_protected_all_respect_set() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        let prot: Protected = [(0usize, 1usize)].into_iter().collect();
        let cs = candidates_protected(&r, &m, &b, &prot).unwrap();
        for c in &cs { assert!(nodes(&c.rings[0]).contains(&(6., 0.)), "{}", c.name); assert!(c.removed.iter().all(|x| x.original_node != 1)); }
        let plain = candidates(&r, &m, &b).unwrap();
        assert!(plain[0].removed.iter().any(|x| x.original_node == 1) || count_nodes(&plain[0].rings) < count_nodes(&r));
    }

    #[test] fn nonfinite_objective_on_input_is_typed_violation_not_skip() {
        // fully valid mask (finite, positive scale) whose scale^2 overflows the f64 objective: area_error = inf/NaN
        let r = vec![ring()];
        let mut m = mask(); m.scale = 1e200; m.origin = (-1e200, 11e200);
        let b = budget(&r);
        assert!(m.valid());
        assert!(!area_error(&r, &m).is_finite(), "fixture must produce a non-finite objective");
        match try_apply(&r, &m, &b, Policy::STRICT) { Err(LeverError::Violation(msg)) => assert!(msg.contains("non-finite"), "{msg}"), o => panic!("expected typed Violation, got {:?}", o.map(|x| x.1.nodes_after)) }
        assert!(matches!(candidates(&r, &m, &b), Err(LeverError::Violation(_))));
    }
    #[test] fn nonfinite_guard_does_not_disturb_normal_fixture() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        let (_, rep) = try_apply(&r, &m, &b, Policy::STRICT).unwrap();
        assert!(rep.area_after.is_finite() && rep.area_before.is_finite());
    }

    #[test] fn over_budget_input_is_refused_before_area_error() {
        // cubic whose control polygon is ~1e10 px long on a 12x12 mask (budget 144): would allocate ~1e10 chords
        let r = vec![ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Cubic { control_one: p(10., 0.), control_two: p(10., 10.), end: p(0., 10.) }, Span::Line { end: p(0., 0.) }] }];
        let mut m = mask(); m.scale = 1e-9; m.origin = (-1e-9, 11e-9);
        let b = budget(&r); assert!(m.valid());
        match try_apply(&r, &m, &b, Policy::STRICT) { Err(LeverError::Violation(msg)) => assert!(msg.contains("flatten budget refused"), "{msg}"), o => panic!("expected typed refusal, got {:?}", o.map(|x| x.1.nodes_after)) }
        assert!(matches!(candidates(&r, &m, &b), Err(LeverError::Violation(_))));
    }
    #[test] fn receipt_notes_carry_flatten_chords_and_normal_run_unchanged() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        let (_, rep) = try_apply(&r, &m, &b, Policy::STRICT).unwrap();
        assert!(rep.notes.contains("flatten_chords_out="), "{}", rep.notes);
    }
}

#[cfg(test)]
mod incremental_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// 10x10 square with collinear extra nodes (multi-round removals).
    fn ring() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Line { end: p(3., 0.) }, Span::Line { end: p(6., 0.) }, Span::Line { end: p(10., 0.) },
            Span::Line { end: p(10., 5.) }, Span::Line { end: p(10., 10.) },
            Span::Line { end: p(0., 10.) }, Span::Line { end: p(0., 0.) } ] }
    }
    /// second ring at an offset (multi-ring rounds; cache reuse across rounds)
    fn ring2() -> ReferenceRing {
        ReferenceRing { start: p(1., 1.), spans: vec![
            Span::Line { end: p(4., 1.) }, Span::Line { end: p(7., 1.) }, Span::Line { end: p(9., 1.) },
            Span::Line { end: p(9., 9.) }, Span::Line { end: p(1., 9.) }, Span::Line { end: p(1., 1.) } ] }
    }
    /// cubic-heavy ring: exercises roots_contrib / chord_contrib cubic terms
    fn ring_cubic() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Cubic { control_one: p(3., 0.), control_two: p(7., 0.), end: p(10., 0.) },
            Span::Cubic { control_one: p(10., 3.), control_two: p(10., 7.), end: p(10., 10.) },
            Span::Cubic { control_one: p(7., 10.), control_two: p(3., 10.), end: p(0., 10.) },
            Span::Line { end: p(0., 0.) } ] }
    }
    fn mask() -> SourceMask { let mut ink = vec![255u8; 144]; for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
        SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) } }
    fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: r.iter().map(|x| x.spans.len()).collect() } }

    fn run_both(rings: &[ReferenceRing], mask: &SourceMask, policy: Policy, budget: &NodeBudget, protected: &Protected)
        -> ((Vec<ReferenceRing>, Vec<Removal>), (Vec<ReferenceRing>, Vec<Removal>)) {
        NODE_INCREMENTAL_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        let a = run(rings, mask, policy, budget, protected);
        NODE_INCREMENTAL_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
        let b = run(rings, mask, policy, budget, protected);
        NODE_INCREMENTAL_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        (a.unwrap(), b.unwrap())
    }
    fn assert_identical(a: &(Vec<ReferenceRing>, Vec<Removal>), b: &(Vec<ReferenceRing>, Vec<Removal>)) {
        assert_eq!(hash_rings(&a.0), hash_rings(&b.0), "output rings diverged");
        assert_eq!(a.1.len(), b.1.len(), "removal count diverged");
        for (x, y) in a.1.iter().zip(b.1.iter()) {
            assert_eq!((x.ring, x.original_node), (y.ring, y.original_node));
            assert_eq!((x.node_end.x.to_bits(), x.node_end.y.to_bits()), (y.node_end.x.to_bits(), y.node_end.y.to_bits()));
            assert_eq!(x.delta_area.to_bits(), y.delta_area.to_bits(), "delta_area bits diverged");
            assert_eq!(x.gain_bound.to_bits(), y.gain_bound.to_bits());
        }
    }

    /// Dual-driver oracle (cascade/prescreen precedent): the incremental
    /// integer-exact driver must be bit-identical to the serial full-scan
    /// driver across policies, fixtures and protected sets.
    #[test]
    fn incremental_bit_identical_across_fixtures() {
        let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
        for policy in [Policy::STRICT, Policy::HALF_NOISE, Policy::NOISE] {
            let (a, c) = run_both(&r, &m, policy, &b, &Protected::new());
            assert_identical(&a, &c);
        }
        let prot: Protected = [(0usize, 1usize)].into_iter().collect();
        let (a, c) = run_both(&r, &m, Policy::STRICT, &b, &prot);
        assert_identical(&a, &c);
        // multi-ring: cross-ring rounds, cache reuse on unmodified rings
        let r2 = vec![ring(), ring2()]; let b2 = budget(&r2);
        let (a, c) = run_both(&r2, &m, Policy::STRICT, &b2, &Protected::new());
        assert_identical(&a, &c);
        assert!(a.1.len() >= 2, "multi-ring fixture must remove in both rings, got {}", a.1.len());
        // cubic fixture: cubic chord/roots contributions
        let rc = vec![ring_cubic()]; let bc = budget(&rc);
        let (a, c) = run_both(&rc, &m, Policy::STRICT, &bc, &Protected::new());
        assert_identical(&a, &c);
        // cubic + line multi-ring
        let r3 = vec![ring_cubic(), ring()]; let b3 = budget(&r3);
        let (a, c) = run_both(&r3, &m, Policy::STRICT, &b3, &Protected::new());
        assert_identical(&a, &c);
    }

    /// chord_contrib per-span sums + closing chords == check_flatten_budget total.
    #[test] fn chord_contrib_parity_with_check_flatten_budget() {
        let m = mask();
        let max = crate::flatten_budget::max_total_segments(m.w, m.h).unwrap();
        for r in [vec![ring()], vec![ring_cubic()], vec![ring(), ring2()]] {
            let full = crate::flatten_budget::check_flatten_budget(&r, &m, max).unwrap();
            let mut sum = r.len(); // one closing chord per ring
            for rr in &r {
                let mut prev = rr.start;
                for sp in &rr.spans {
                    match chord_contrib(&m, prev, sp, max) {
                        ChordContrib::Ok(n) => sum += n,
                        ChordContrib::SerialFallback => panic!("fixture must be finite and in budget"),
                    }
                    prev = end_of(sp);
                }
            }
            assert_eq!(sum, full, "chord contribution parity");
        }
    }

    /// roots_contrib per-span sums == missing_extrema total.
    #[test] fn roots_contrib_parity_with_missing_extrema() {
        for r in [vec![ring()], vec![ring_cubic()]] {
            let full = missing_extrema(&r);
            let mut sum = 0usize;
            for rr in &r {
                let mut prev = rr.start;
                for sp in &rr.spans {
                    sum += roots_contrib(prev, sp);
                    prev = end_of(sp);
                }
            }
            assert_eq!(sum, full, "roots contribution parity");
        }
    }
}

#[cfg(test)]
mod pool_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// 10x10 square with collinear extra nodes (exact dj ties: da = 0 removals).
    fn ring() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Line { end: p(3., 0.) }, Span::Line { end: p(6., 0.) }, Span::Line { end: p(10., 0.) },
            Span::Line { end: p(10., 5.) }, Span::Line { end: p(10., 10.) },
            Span::Line { end: p(4., 10.) }, Span::Line { end: p(0., 10.) }, Span::Line { end: p(0., 0.) } ] }
    }
    fn ring2() -> ReferenceRing {
        ReferenceRing { start: p(1., 1.), spans: vec![
            Span::Line { end: p(4., 1.) }, Span::Line { end: p(7., 1.) }, Span::Line { end: p(9., 1.) },
            Span::Line { end: p(9., 9.) }, Span::Line { end: p(1., 9.) }, Span::Line { end: p(1., 1.) } ] }
    }
    fn ring_cubic() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Cubic { control_one: p(3., 0.), control_two: p(7., 0.), end: p(10., 0.) },
            Span::Cubic { control_one: p(10., 3.), control_two: p(10., 7.), end: p(10., 10.) },
            Span::Cubic { control_one: p(7., 10.), control_two: p(3., 10.), end: p(0., 10.) },
            Span::Line { end: p(0., 0.) } ] }
    }
    /// Circular ink with an inscribed integer polygon: dj > 0 rejects (pre-screen fires).
    fn circle_fixture(n: usize) -> (Vec<ReferenceRing>, SourceMask) {
        let mut ink = vec![255u8; 24 * 24];
        for j in 0..24 { for i in 0..24 {
            let (dx, dy) = (i as f64 - 11.5, j as f64 - 11.5);
            if dx * dx + dy * dy <= 81.0 { ink[j * 24 + i] = 0; }
        } }
        let m = SourceMask { w: 24, h: 24, ink, scale: 1.0, origin: (0.0, 24.0) };
        let pts: Vec<(f64, f64)> = (0..n).map(|i| {
            let t = i as f64 * std::f64::consts::TAU / n as f64;
            ((12.0 + 9.0 * t.cos()).round(), (12.0 + 9.0 * t.sin()).round())
        }).collect();
        let r = ReferenceRing { start: p(pts[0].0, pts[0].1), spans: pts[1..].iter().chain(std::iter::once(&pts[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect() };
        (vec![r], m)
    }
    fn mask() -> SourceMask { let mut ink = vec![255u8; 144]; for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
        SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) } }
    fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: r.iter().map(|x| x.spans.len()).collect() } }

    fn run_both(rings: &[ReferenceRing], mask: &SourceMask, policy: Policy, budget: &NodeBudget, protected: &Protected)
        -> (Result<(Vec<ReferenceRing>, Vec<Removal>), String>, Result<(Vec<ReferenceRing>, Vec<Removal>), String>) {
        NODE_POOL_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
        let a = run(rings, mask, policy, budget, protected).map_err(|e| format!("{e:?}"));
        NODE_POOL_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        NODE_POOL_PROBE.store(true, std::sync::atomic::Ordering::SeqCst);
        let b = run(rings, mask, policy, budget, protected).map_err(|e| format!("{e:?}"));
        NODE_POOL_PROBE.store(false, std::sync::atomic::Ordering::SeqCst);
        (a, b)
    }
    fn assert_identical(a: &Result<(Vec<ReferenceRing>, Vec<Removal>), String>, b: &Result<(Vec<ReferenceRing>, Vec<Removal>), String>) {
        match (a, b) {
            (Err(x), Err(y)) => assert_eq!(x, y, "typed errors diverged"),
            (Ok(a), Ok(b)) => {
                assert_eq!(hash_rings(&a.0), hash_rings(&b.0), "output rings diverged");
                assert_eq!(a.1.len(), b.1.len(), "removal count diverged");
                for (x, y) in a.1.iter().zip(b.1.iter()) {
                    assert_eq!((x.ring, x.original_node), (y.ring, y.original_node));
                    assert_eq!((x.node_end.x.to_bits(), x.node_end.y.to_bits()), (y.node_end.x.to_bits(), y.node_end.y.to_bits()));
                    assert_eq!(x.delta_area.to_bits(), y.delta_area.to_bits(), "delta_area bits diverged");
                    assert_eq!(x.gain_bound.to_bits(), y.gain_bound.to_bits());
                }
            }
            _ => panic!("ok/err shape diverged: {:?} vs {:?}", a.as_ref().map(|r| r.1.len()), b.as_ref().map(|r| r.1.len())),
        }
    }

    /// Dual-driver oracle (cascade/prescreen/incremental precedent): the
    /// sorted-pool driver must be bit-identical to the serial full scan
    /// across policies, fixtures, protected sets — exact dj ties included.
    #[test]
    fn pool_bit_identical_across_fixtures() {
        for policy in [Policy::STRICT, Policy::HALF_NOISE, Policy::NOISE] {
            let r = vec![ring()]; let (m, b) = (mask(), budget(&r));
            let (a, c) = run_both(&r, &m, policy, &b, &Protected::new());
            assert_identical(&a, &c);
        }
        // multi-ring: cross-ring rounds, memo reuse on unmodified rings
        let r2 = vec![ring(), ring2()]; let b2 = budget(&r2);
        for policy in [Policy::STRICT, Policy::HALF_NOISE] {
            let (a, c) = run_both(&r2, &mask(), policy, &b2, &Protected::new());
            assert_identical(&a, &c);
        }
        let prot: Protected = [(0usize, 1usize)].into_iter().collect();
        let (a, c) = run_both(&r2, &mask(), Policy::STRICT, &b2, &prot);
        assert_identical(&a, &c);
        // cubic fixture + mixed multi-ring
        let rc = vec![ring_cubic()]; let bc = budget(&rc);
        let (a, c) = run_both(&rc, &mask(), Policy::STRICT, &bc, &Protected::new());
        assert_identical(&a, &c);
        let r3 = vec![ring_cubic(), ring()]; let b3 = budget(&r3);
        let (a, c) = run_both(&r3, &mask(), Policy::NOISE, &b3, &Protected::new());
        assert_identical(&a, &c);
        // pre-screen-reject heavy fixtures (cached PrescreenRejected path)
        for n in [16usize, 24] {
            let (input, m) = circle_fixture(n);
            for policy in [Policy::STRICT, Policy::HALF_NOISE, Policy::NOISE] {
                let (a, c) = run_both(&input, &m, policy, &budget(&input), &Protected::new());
                assert_identical(&a, &c);
            }
        }
    }

    /// Randomized drift hunt: f64 reassociation could in theory move a cached
    /// value after removals elsewhere; fuzz small integer rings over varied
    /// masks and compare the two drivers bitwise, Err strings included.
    #[test]
    fn pool_bit_identical_fuzz() {
        let mut state = 0x9e3779b97f4a7c15u64;
        let mut rnd = move || { state ^= state << 13; state ^= state >> 7; state ^= state << 17; state };
        for case in 0..240u32 {
            let w = 8 + (rnd() % 9) as usize; let h = 8 + (rnd() % 9) as usize;
            let mut ink = vec![255u8; w * h];
            let blocks = 1 + rnd() % 3;
            for _ in 0..blocks {
                let x0 = (rnd() as usize) % w; let y0 = (rnd() as usize) % h;
                let x1 = (x0 + 1 + (rnd() as usize) % (w - x0).max(1)).min(w);
                let y1 = (y0 + 1 + (rnd() as usize) % (h - y0).max(1)).min(h);
                for j in y0..y1 { for i in x0..x1 { ink[j * w + i] = 0; } }
            }
            let scale = [1.0, 0.5, 2.0, 1.5][(rnd() % 4) as usize];
            let m = SourceMask { w, h, ink, scale, origin: (0.0, h as f64) };
            let nrings = 1 + (rnd() % 2) as usize;
            let mut rings = Vec::new();
            for _ in 0..nrings {
                let npts = 4 + (rnd() % 8) as usize;
                let cx = (rnd() % (w as u64 * 2)) as f64 / 2.0; let cy = (rnd() % (h as u64 * 2)) as f64 / 2.0;
                let mut pts: Vec<(f64, f64)> = (0..npts).map(|i| {
                    let t = i as f64 * std::f64::consts::TAU / npts as f64;
                    ((cx + 4.0 * t.cos()).round(), (cy + 4.0 * t.sin()).round())
                }).collect();
                pts.dedup();
                if pts.len() < 4 { continue; }
                rings.push(ReferenceRing { start: p(pts[0].0, pts[0].1), spans: pts[1..].iter().chain(std::iter::once(&pts[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect() });
            }
            if rings.is_empty() { continue; }
            let b = budget(&rings);
            NODE_POOL_PROBE.store(true, std::sync::atomic::Ordering::SeqCst);
            for policy in [Policy::STRICT, Policy::HALF_NOISE] {
                NODE_POOL_DRIFT.store(0, std::sync::atomic::Ordering::SeqCst);
                let (a, c) = run_both(&rings, &m, policy, &b, &Protected::new());
                let _drifts = NODE_POOL_DRIFT.load(std::sync::atomic::Ordering::SeqCst);
                if format!("{a:?}") != format!("{c:?}") {
                    eprintln!("DIVERGE case {case} policy {:?} mask {}x{} scale {} origin {:?}", policy.slack, m.w, m.h, m.scale, m.origin);
                    eprintln!("rings: {:?}", rings);
                    eprintln!("serial: {:?}", a.as_ref().map(|x| &x.1));
                    eprintln!("pool:   {:?}", c.as_ref().map(|x| &x.1));
                    panic!("case {case} diverged");
                }
                if case == 0 { assert!(a.is_ok(), "sanity: first fuzz case must run"); }
            }
            NODE_POOL_PROBE.store(false, std::sync::atomic::Ordering::SeqCst);
        }
    }


    /// The pool must actually eliminate evaluations: serial candidate eval
    /// calls vs pool calls on a multi-round fixture (measured, not claimed).
    #[test]
    fn pool_eliminates_evals_measured() {
        // Distinct-dj fixture (measured elimination, Chief condition 3): a
        // 32-gon "circle" whose candidates carry varied nonzero dj (integer
        // rounding of the vertices breaks the symmetry) plus a rectangle with
        // 12 collinear da=0 side nodes, spatially disjoint so one ring's
        // removals never dirty the other's memos. An all-tied fixture is the
        // band rule's degenerate worst case (every cached value sits in the
        // band) and cannot demonstrate elimination.
        let mut circle_spans: Vec<Span> = Vec::new();
        let npts = 24;
        let pts: Vec<(f64, f64)> = (0..npts).map(|t| {
            let a = t as f64 * std::f64::consts::TAU / npts as f64;
            ((32.0 + 12.0 * a.cos()).round(), (22.0 + 12.0 * a.sin()).round())
        }).collect();
        for t in 1..=npts { circle_spans.push(Span::Line { end: p(pts[t % npts].0, pts[t % npts].1) }); }
        let circle = ReferenceRing { start: p(pts[0].0, pts[0].1), spans: circle_spans };
        let mut rect_spans: Vec<Span> = Vec::new();
        for x in [7., 10., 12.] { rect_spans.push(Span::Line { end: p(x, 10.) }); }
        for y in [18., 26., 34.] { rect_spans.push(Span::Line { end: p(12., y) }); }
        for x in [9., 6., 4.] { rect_spans.push(Span::Line { end: p(x, 34.) }); }
        for y in [26., 18., 10.] { rect_spans.push(Span::Line { end: p(4., y) }); }
        let rect = ReferenceRing { start: p(4., 10.), spans: rect_spans };
        let r = vec![circle, rect];
        let mut ink = vec![255u8; 44 * 44];
        for j in 0..44 { for i in 0..44 {
            let di = i as f64 - 30.0; let dj = j as f64 - 20.0;
            if di * di + dj * dj <= 13.0 * 13.0 { ink[j * 44 + i] = 0; }
        } }
        let m = SourceMask { w: 44, h: 44, ink, scale: 1.0, origin: (2.0, 42.0) };
        let b = budget(&r);
        NODE_POOL_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
        NODE_EVAL_CALLS.with(|c| c.set(0));
        let a = run(&r, &m, Policy::STRICT, &b, &Protected::new()).unwrap();
        let serial_evals = NODE_EVAL_CALLS.with(|c| c.get());
        NODE_POOL_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        NODE_EVAL_CALLS.with(|c| c.set(0));
        let c = run(&r, &m, Policy::STRICT, &b, &Protected::new()).unwrap();
        let pool_evals = NODE_EVAL_CALLS.with(|c| c.get());
        assert_eq!(a.1.len(), c.1.len());
        assert!(a.1.len() >= 8, "fixture must run many rounds, got {}", a.1.len());
        eprintln!("elim measured: serial_evals={serial_evals} pool_evals={pool_evals} removals={}", a.1.len());
        // measured floor: the all-tied collinear removals force per-round band
        // re-evals by design (the band must fresh-eval every candidate that can
        // tie the argmin); distinct-dj workloads eliminate far more (W6 numbers
        // are the real target). Require a robust 25% elimination here.
        assert!(serial_evals * 3 > pool_evals * 4, "pool must eliminate evals: serial={serial_evals} pool={pool_evals}");
    }
}

#[cfg(test)]
mod pool_probe_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn ring_cubic() -> ReferenceRing {
        ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Cubic { control_one: p(3., 0.), control_two: p(7., 0.), end: p(10., 0.) },
            Span::Cubic { control_one: p(10., 3.), control_two: p(10., 7.), end: p(10., 10.) },
            Span::Cubic { control_one: p(7., 10.), control_two: p(3., 10.), end: p(0., 10.) },
            Span::Line { end: p(0., 0.) } ] }
    }
    fn mask() -> SourceMask { let mut ink = vec![255u8; 144]; for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
        SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) } }
    fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: r.iter().map(|x| x.spans.len()).collect() } }
    #[test]
    fn memo_value_stability_probe() {
        let r = vec![ring_cubic()]; let (m, b) = (mask(), budget(&r));
        NODE_POOL_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        NODE_POOL_PROBE.store(true, std::sync::atomic::Ordering::SeqCst);
        NODE_POOL_DRIFT.store(0, std::sync::atomic::Ordering::SeqCst);
        let out = run(&r, &m, Policy::STRICT, &b, &Protected::new());
        NODE_POOL_PROBE.store(false, std::sync::atomic::Ordering::SeqCst);
        eprintln!("probe result ok={} removals={} drifts={}", out.is_ok(), out.map(|x| x.1.len()).unwrap_or(0), NODE_POOL_DRIFT.load(std::sync::atomic::Ordering::SeqCst));
    }
}



#[cfg(test)]
mod bracket_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn decide(p0: Point, a: &Span, b: &Span, new: &Span, cap: f64) -> DevBracket {
        bracket_dev(p0, a, b, new, cap, DEV_WORK_BUDGET).0
    }

    /// Shallow V: old (0,0)->(10,1)->(20,0), merged chord (0,0)->(20,0).
    /// Exact oracle, real arithmetic: H = 1 (apex (10,1) to the x-axis
    /// chord; every chord point is nearer to the polyline than that).
    fn v_case() -> (Span, Span, Span) {
        (Span::Line { end: p(10., 1.) }, Span::Line { end: p(20., 0.) }, Span::Line { end: p(20., 0.) })
    }
    /// Symmetric cubic bulge: (0,0)->(20,0) with both controls at (10,4).
    /// Exact oracle: y(t) = 12 t (1-t), x monotone on [0,20], so the max
    /// distance to the chord is y(1/2) = 3 exactly, attained at (10,3).
    fn bulge_case() -> (Span, Span, Span) {
        (Span::Cubic { control_one: p(10., 4.), control_two: p(10., 4.), end: p(20., 0.) },
         Span::Line { end: p(20., 0.) },
         Span::Line { end: p(20., 0.) })
    }

    #[test]
    fn v_within_certified() {
        let (a, b, new) = v_case();
        match decide(p(0., 0.), &a, &b, &new, 2.0) {
            DevBracket::Within(u) => assert!(u >= 1.0 && u <= 2.0, "bound {u}"),
            o => panic!("expected Within, got {o:?}"),
        }
    }
    #[test]
    fn v_beyond_certified() {
        let (a, b, new) = v_case();
        match decide(p(0., 0.), &a, &b, &new, 0.5) {
            DevBracket::Beyond(l) => assert!(l > 0.5 && l <= 1.0, "bound {l}"),
            o => panic!("expected Beyond, got {o:?}"),
        }
    }
    /// Boundary: true H == cap exactly. The upper bound always carries a
    /// positive slack (never Within), the lower bound always subtracts one
    /// (never Beyond), so the budget must exhaust: typed Indeterminate,
    /// distinct from a geometric verdict - and the spent accounting must
    /// respect the per-candidate budget on this instrumented worst path.
    #[test]
    fn v_boundary_is_indeterminate_and_within_budget() {
        let (a, b, new) = v_case();
        let (r, spent) = bracket_dev(p(0., 0.), &a, &b, &new, 1.0, DEV_WORK_BUDGET);
        assert_eq!(r, DevBracket::Indeterminate);
        assert!(spent <= DEV_WORK_BUDGET, "spent {spent} above budget");
        assert!(spent >= bracket_cost(SAMPLES, 2 * SAMPLES), "base round must run");
    }
    /// A budget below the base-round cost does no work and abstains.
    #[test]
    fn tiny_budget_abstains_without_work() {
        let (a, b, new) = v_case();
        let (r, spent) = bracket_dev(p(0., 0.), &a, &b, &new, 2.0, 100);
        assert_eq!((r, spent), (DevBracket::Indeterminate, 0));
    }
    /// Whole-glyph budget: once spent, candidates abstain without work.
    #[test]
    fn glyph_budget_exhaustion_abstains() {
        let (a, b, new) = v_case();
        let mut glyph_spent = DEV_GLYPH_WORK_BUDGET;
        let r = eval_dev(p(0., 0.), &a, &b, &new, 2.0, &mut glyph_spent);
        assert_eq!(r, DevBracket::Indeterminate);
        assert_eq!(glyph_spent, DEV_GLYPH_WORK_BUDGET, "no work after exhaustion");
        let mut nearly = DEV_GLYPH_WORK_BUDGET - 100;
        let r2 = eval_dev(p(0., 0.), &a, &b, &new, 2.0, &mut nearly);
        assert_eq!(r2, DevBracket::Indeterminate, "allowance below base cost abstains");
    }
    /// Power-of-two scaling is exact in binary64: decisions and certified
    /// bounds scale exactly with the coordinates.
    #[test]
    fn scale_invariance_pow2() {
        let (a, b, new) = v_case();
        let s = 1024.0;
        let sc = |sp: &Span| match sp {
            Span::Line { end } => Span::Line { end: p(end.x * s, end.y * s) },
            Span::Cubic { control_one, control_two, end } => Span::Cubic {
                control_one: p(control_one.x * s, control_one.y * s),
                control_two: p(control_two.x * s, control_two.y * s), end: p(end.x * s, end.y * s) },
        };
        let (sa, sb, snew) = (sc(&a), sc(&b), sc(&new));
        match (decide(p(0., 0.), &a, &b, &new, 2.0), decide(p(0., 0.), &sa, &sb, &snew, 2.0 * s)) {
            (DevBracket::Within(u), DevBracket::Within(us)) => assert_eq!(us, u * s, "{u} vs {us}"),
            o => panic!("expected Within/Within, got {o:?}"),
        }
        assert_eq!(decide(p(0., 0.), &sa, &sb, &snew, 1.0 * s), DevBracket::Indeterminate);
    }
    /// Large-magnitude cancellation: the V shape shifted by 2^53, where
    /// ulp = 2 font units. Differences against nearby coordinates stay
    /// exact (Sterbenz) and interval subtraction keeps them enclosed, but
    /// absolute outward rounding widens point intervals by ~ulp, so a band
    /// of 2 units is below the representational resolution at this
    /// magnitude: the guard must abstain (Indeterminate), never certify.
    /// At a band above the representational rounding (8 units) it must
    /// decide, with a certified bound still >= the exact H = 1.
    #[test]
    fn large_magnitude_cancellation() {
        let o = 9007199254740992.0; // 2^53
        let a = Span::Line { end: p(o + 10., 1.) };
        let b = Span::Line { end: p(o + 20., 0.) };
        let new = Span::Line { end: p(o + 20., 0.) };
        let tight = decide(p(o, 0.), &a, &b, &new, 2.0);
        assert!(!matches!(tight, DevBracket::Within(_)), "certified below ulp resolution: {tight:?}");
        match decide(p(o, 0.), &a, &b, &new, 8.0) {
            DevBracket::Within(u) => assert!(u >= 1.0 && u <= 8.0, "bound {u}"),
            x => panic!("expected Within at resolvable band, got {x:?}"),
        }
    }
    /// Interval subtraction encloses a difference that binary64 cannot
    /// represent: 2^53 - (-1) = 2^53 + 1 is not a binary64 value; the
    /// interval must contain it, so evaluating the span at t = 1 must
    /// enclose the true endpoint -1 (a raw rounded subtraction would not).
    #[test]
    fn unrepresentable_difference_enclosed() {
        let s = Span::Line { end: p(-1., 0.) };
        let (x, _y) = eval_iv(p(9007199254740992.0, 0.), &s, Iv::pt(1.0)).unwrap();
        assert!(x.lo <= -1.0 && x.hi >= -1.0, "interval [{}, {}] misses -1", x.lo, x.hi);
    }
    /// Overflow: finite but huge coordinates overflow the squared norms;
    /// the arithmetic failure surfaces as typed NonFinite, never a verdict.
    #[test]
    fn overflow_is_typed_nonfinite() {
        let a = Span::Line { end: p(1e200, 0.) };
        let b = Span::Line { end: p(2e200, 0.) };
        let new = Span::Line { end: p(2e200, 0.) };
        assert_eq!(decide(p(0., 0.), &a, &b, &new, 1.0), DevBracket::NonFinite);
    }
    /// Subnormal regime: a V scaled by 2^-1022. Squared distances underflow
    /// toward 0; outward rounding keeps every enclosure sound (0 <= true),
    /// so the guard can never false-accept: no Within at any cap here.
    #[test]
    fn subnormal_never_false_accepts() {
        let s = 2.0f64.powi(-1022);
        let a = Span::Line { end: p(10. * s, 1. * s) };
        let b = Span::Line { end: p(20. * s, 0.) };
        let new = Span::Line { end: p(20. * s, 0.) };
        let r = decide(p(0., 0.), &a, &b, &new, 2.0 * s);
        assert!(!matches!(r, DevBracket::Within(_)), "false accept at subnormal scale: {r:?}");
        assert!(matches!(r, DevBracket::Indeterminate | DevBracket::Beyond(_)), "{r:?}");
    }
    #[test]
    fn bulge_within_and_beyond_certified() {
        let (a, b, new) = bulge_case();
        match decide(p(0., 0.), &a, &b, &new, 4.0) {
            DevBracket::Within(u) => assert!(u >= 3.0 && u <= 4.0, "bound {u}"),
            o => panic!("expected Within, got {o:?}"),
        }
        match decide(p(0., 0.), &a, &b, &new, 2.0) {
            DevBracket::Beyond(l) => assert!(l > 2.0 && l <= 3.0, "bound {l}"),
            o => panic!("expected Beyond, got {o:?}"),
        }
        assert_eq!(decide(p(0., 0.), &a, &b, &new, 3.0), DevBracket::Indeterminate);
    }
    /// Consistency only (same implementation, two resolutions): an
    /// x-reversing S-cubic with interior extrema; two certified brackets
    /// both contain H, hence must overlap. Not an independent oracle.
    #[test]
    fn extremum_brackets_overlap() {
        let a = Span::Cubic { control_one: p(-10., 12.), control_two: p(30., -12.), end: p(20., 0.) };
        let b = Span::Line { end: p(40., 0.) };
        let new = Span::Cubic { control_one: p(8., 2.), control_two: p(28., -2.), end: p(40., 0.) };
        let (Some((lo1, u1)), _) = bracket_at(p(0., 0.), &a, &b, &new, 24, 48) else { panic!("bracket_at failed") };
        let (Some((lo2, u2)), _) = bracket_at(p(0., 0.), &a, &b, &new, 768, 1536) else { panic!("bracket_at failed") };
        assert!(u1.hi >= lo2.lo && u2.hi >= lo1.lo,
            "brackets [{},{}] vs [{},{}] disjoint", lo1.lo, u1.hi, lo2.lo, u2.hi);
    }
    /// Resource accounting: base round cost is the actual double-loop
    /// evaluation count (2*(2*24+1)*(2*24+1)), and the per-candidate budget
    /// covers it by construction.
    #[test]
    fn resource_accounting() {
        assert_eq!(bracket_cost(SAMPLES, 2 * SAMPLES), 4802);
        assert!(DEV_WORK_BUDGET >= bracket_cost(SAMPLES, 2 * SAMPLES));
        assert!(DEV_GLYPH_WORK_BUDGET >= DEV_WORK_BUDGET);
    }
    /// Raster no-regression is an exact integer-count comparison, with no
    /// float tolerance that could admit a one-pixel regression.
    #[test]
    fn raster_iou_no_regression_counting() {
        let row = |intersection: u64, union: u64| Some(crate::curve_stress::TileIou {
            intersection, union, source_ink: union, outline_ink: intersection, iou: intersection as f64 / union as f64,
        });
        assert!(iou_not_worse(row(1, 2), row(1, 2)));
        assert!(iou_not_worse(row(1, 2), row(2, 4)));
        assert!(!iou_not_worse(row(1, 2), row(1, 3)));
        assert!(iou_not_worse(None, None));
        assert!(!iou_not_worse(None, row(1, 2)));
        assert!(!iou_not_worse(row(1, 2), None));
    }
    #[test]
    fn invalid_interval_operands_cannot_hide_nan() {
        for bad in [Iv::pt(f64::NAN), Iv::pt(f64::INFINITY), Iv { lo: 2.0, hi: 1.0 }] {
            assert!(Iv::pt(0.0).mul(bad).is_none());
            assert!(bad.add(Iv::pt(0.0)).is_none());
            assert!(bad.sub(Iv::pt(0.0)).is_none());
            assert!(bad.sqrt().is_none());
            assert!(bad.div_exact(2.0).is_none());
        }
        assert!(Iv::pt(f64::MAX).mul(Iv::pt(2.0)).is_none());
        assert!(Iv::pt(1.0).div_exact(0.0).is_none());
    }
    #[test]
    fn repeated_boundary_candidates_respect_glyph_accounting() {
        let (a, b, new) = v_case();
        let mut spent = 0;
        let mut calls = 0;
        while DEV_GLYPH_WORK_BUDGET - spent >= bracket_cost(SAMPLES, 2*SAMPLES) {
            let old = spent;
            assert_eq!(eval_dev(p(0.,0.), &a, &b, &new, 1.0, &mut spent), DevBracket::Indeterminate);
            assert!(spent > old && spent - old <= DEV_WORK_BUDGET);
            assert!(spent <= DEV_GLYPH_WORK_BUDGET);
            calls += 1;
        }
        let old = spent;
        assert_eq!(eval_dev(p(0.,0.), &a, &b, &new, 1.0, &mut spent), DevBracket::Indeterminate);
        assert_eq!(old, spent);
        assert!(calls > 1);
    }
    #[test]
    fn non_finite_is_typed_not_geometric() {
        let a = Span::Line { end: p(1., 0.) };
        let b = Span::Line { end: p(2., 0.) };
        let new = Span::Line { end: p(f64::NAN, 0.) };
        assert_eq!(decide(p(0., 0.), &a, &b, &new, 1.0), DevBracket::NonFinite);
    }
    /// Lever-level regression: the square with collinear extra nodes still
    /// reduces to 4 nodes at scale 1 (economy preserved under the guard).
    #[test]
    fn lever_square_economy_preserved() {
        let ring = ReferenceRing { start: p(0., 0.), spans: vec![
            Span::Line { end: p(3., 0.) }, Span::Line { end: p(6., 0.) }, Span::Line { end: p(10., 0.) },
            Span::Line { end: p(10., 5.) }, Span::Line { end: p(10., 10.) },
            Span::Line { end: p(0., 10.) }, Span::Line { end: p(0., 0.) } ] };
        let mut ink = vec![255u8; 144];
        for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
        let mask = SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) };
        let rings = vec![ring];
        let budget = NodeBudget { max_nodes: 7, max_nodes_per_ring: vec![7] };
        let (out, report) = try_apply(&rings, &mask, &budget, Policy::STRICT).unwrap();
        assert_eq!(report.nodes_before, 7);
        assert_eq!(report.nodes_after, 4, "out: {out:?}");
    }
}

#[cfg(test)]
mod bracket_bench_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// Wall-time witness (not asserted): one full-budget exhaustion, the
    /// worst case DEV_WORK_BUDGET allows for a single candidate.
    #[test]
    fn full_budget_exhaustion_wall_time() {
        let a = Span::Line { end: p(10., 1.) };
        let b = Span::Line { end: p(20., 0.) };
        let new = Span::Line { end: p(20., 0.) };
        let t = std::time::Instant::now();
        let (r, spent) = bracket_dev(p(0., 0.), &a, &b, &new, 1.0, DEV_WORK_BUDGET);
        eprintln!("full-budget exhaustion (V boundary, debug build): {:?} -> {r:?} spent {spent}", t.elapsed());
        assert_eq!(r, DevBracket::Indeterminate);
    }
}
