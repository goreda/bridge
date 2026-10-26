//! D4: post-fit repair of regions the crop fit distorts (serif / pendant tails and similar).
//! No glyph-specific logic. Two local, deterministic passes over the final emitted rings:
//! Pass T (curve flow): at a smooth node (both adjacent spans cubic, handles opposed and collinear
//!   within one grid step of rounding wobble) the shorter handle is re-aimed along the longer
//!   handle's direction, so the tangent flows through the node. Kept only if the tangent deviation
//!   strictly drops and area error / missing_extrema do not rise.
//! Pass L (EXPERIMENTAL, off by default, never on the production route): every cubic handle is re-scaled along its own current direction (the
//!   node role and tangent direction are untouched) over a fixed ladder of factors; a move is kept
//!   only if area error strictly drops, missing_extrema does not rise, the handle stays within
//!   `MAX_LEN_PER_CHORD` of the span chord, and smooth nodes stay smooth. Sweeps repeat until no
//!   move is accepted or `max_sweeps` is reached. Its candidate policy (ladder, chord cap, sweep count)
//!   is NOT derived from any source or measurement; it exists only for explicit experimental use via
//!   `TailConfig::experimental_length_search`. The default route reports
//!   `length-search unsupported: no grounded candidate policy` and runs pass T only.
//! Never changes: node count, node coordinates, line spans, span types. Output stays closed and
//! integer. Pure and deterministic. It does not edit capture_fit; D1 calls `refine_tails` after
//! `refine_emitted`. Registration in lib.rs is the lead architect's.
//! Not verified here: how `area_error` indexes `SourceMask`; this module only calls it.
use crate::lever_api::*;
use crate::reference_slice::{Point, ReferenceRing, Span};

pub const LEVER_ID: &str = "D4.tail_refine";
pub const GRID_STEP: f64 = 1.0;
/// EXPERIMENTAL, underived: handle-length factors for the opt-in length search only.
pub const LENGTH_LADDER: [f64; 8] = [0.5, 0.625, 0.75, 0.875, 1.125, 1.25, 1.375, 1.5];
/// EXPERIMENTAL, underived: chord multiple cap for the opt-in length search only.
pub const MAX_LEN_PER_CHORD: f64 = 2.0;

#[derive(Clone, Copy, Debug)]
pub struct TailConfig {
    pub max_sweeps: usize,
    pub run_curve_flow: bool,
    /// Opt-in, underived candidate policy. Must stay false on the production route.
    pub experimental_length_search: bool,
    /// Caller-imposed cap on full-ring area_error evaluations; remaining candidates are skipped (counted).
    pub max_area_evals: usize,
}
impl Default for TailConfig {
    fn default() -> Self { TailConfig { max_sweeps: 4, run_curve_flow: true, experimental_length_search: false, max_area_evals: usize::MAX } }
}
impl TailConfig {
    pub fn validate(&self) -> Result<(), LeverError> {
        if self.max_sweeps == 0 { return Err(LeverError::Violation("cfg.max_sweeps must be >= 1".into())); }
        Ok(())
    }
}

fn end_of(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn is_int(v: f64) -> bool { v.is_finite() && v == v.round() }
fn ring_ok(r: &ReferenceRing) -> bool {
    let ok = |p: &Point| is_int(p.x) && is_int(p.y);
    ok(&r.start) && r.spans.iter().all(|s| match s {
        Span::Line { end } => ok(end),
        Span::Cubic { control_one, control_two, end } => ok(control_one) && ok(control_two) && ok(end),
    }) && r.spans.last().map_or(false, |s| end_of(s) == r.start)
}
/// Source guard: refuses rings that cannot belong to this mask. The mask must contain ink, the rings
/// must be non-empty, finite, and their node bbox must fall inside the mask canvas, with slack of
/// exactly one integer grid step (GRID_STEP / mask.scale px): the derived rounding bound of integer
/// emission, as in emitted_geometry_refine. No other tolerance. A y-flip or origin mix-up between ring frame and mask frame fails here
/// instead of producing a meaningless area_error.
fn source_guard(rings: &[ReferenceRing], mask: &SourceMask) -> Result<(), LeverError> {
    if rings.is_empty() || rings.iter().any(|r| r.spans.is_empty()) { return Err(LeverError::Violation("source guard: empty ring set".into())); }
    if !mask.ink.iter().any(|&v| v < 128) { return Err(LeverError::Violation("source guard: mask has no ink".into())); }
    let (mut lo, mut hi) = ((f64::INFINITY, f64::INFINITY), (f64::NEG_INFINITY, f64::NEG_INFINITY));
    for r in rings { for p in std::iter::once(r.start).chain(r.spans.iter().map(end_of)) {
        if !(p.x.is_finite() && p.y.is_finite()) { return Err(LeverError::Violation("source guard: non-finite node".into())); }
        let (px, py) = mask.to_pixel(p);
        lo.0 = lo.0.min(px); lo.1 = lo.1.min(py); hi.0 = hi.0.max(px); hi.1 = hi.1.max(py);
    } }
    let t = GRID_STEP / mask.scale;
    if lo.0 < -t || lo.1 < -t || hi.0 > mask.w as f64 + t || hi.1 > mask.h as f64 + t {
        return Err(LeverError::Violation(format!("source guard: ring bbox px ({:.1},{:.1})-({:.1},{:.1}) outside mask {}x{}", lo.0, lo.1, hi.0, hi.1, mask.w, mask.h)));
    }
    Ok(())
}
/// Form guard, final check: every handle keeps its side of its node (direction dot > 0 against the
/// input handle, or the input handle was degenerate) and an axis-aligned handle stays axis-aligned.
fn form_guard(before: &[ReferenceRing], after: &[ReferenceRing]) -> Result<(), LeverError> {
    for (ri, (a, b)) in before.iter().zip(after).enumerate() {
        for k in 0..a.spans.len() { for first in [true, false] {
            let (Some(h0), Some(h1)) = (get(a, (k, first)), get(b, (k, first))) else { continue };
            let (n0, n1) = (node_of(a, (k, first)), node_of(b, (k, first)));
            let (v0, v1) = (sub(h0, n0), sub(h1, n1));
            if v0 == (0.0, 0.0) { if v1 != (0.0, 0.0) { return Err(LeverError::Violation(format!("form guard: ring {} span {} degenerate handle changed", ri, k))); } continue; }
            if v1 == (0.0, 0.0) || v0.0 * v1.0 + v0.1 * v1.1 <= 0.0 {
                return Err(LeverError::Violation(format!("form guard: ring {} span {} handle flipped or collapsed", ri, k)));
            }
            if (v0.0 == 0.0 && v1.0 != 0.0) || (v0.1 == 0.0 && v1.1 != 0.0) {
                return Err(LeverError::Violation(format!("form guard: ring {} span {} axis-aligned handle tilted", ri, k)));
            }
        } }
    }
    Ok(())
}
fn sub(a: Point, b: Point) -> (f64, f64) { (a.x - b.x, a.y - b.y) }
fn len(v: (f64, f64)) -> f64 { v.0.hypot(v.1) }

/// Handle slot: span index and which handle (first = control_one, else control_two).
type Slot = (usize, bool);
fn node_of(r: &ReferenceRing, (k, first): Slot) -> Point {
    if first { if k == 0 { r.start } else { end_of(&r.spans[k - 1]) } } else { end_of(&r.spans[k]) }
}
fn get(r: &ReferenceRing, (k, first): Slot) -> Option<Point> {
    match &r.spans[k] { Span::Cubic { control_one, control_two, .. } => Some(if first { *control_one } else { *control_two }), _ => None }
}
fn set(r: &mut ReferenceRing, (k, first): Slot, p: Point) {
    if let Span::Cubic { control_one, control_two, .. } = &mut r.spans[k] { if first { *control_one = p } else { *control_two = p } }
}
fn chord(r: &ReferenceRing, k: usize) -> f64 {
    let a = if k == 0 { r.start } else { end_of(&r.spans[k - 1]) };
    len(sub(end_of(&r.spans[k]), a))
}
/// |sin| of the angle between the two handles at node `j` (end of span j) measured against a
/// straight continuation; None unless both adjacent spans are cubic with non-degenerate handles.
fn flow_dev(r: &ReferenceRing, j: usize) -> Option<(f64, f64, f64)> {
    let n = r.spans.len();
    let c = end_of(&r.spans[j]);
    let hin = get(r, (j, false))?;
    let hout = get(r, ((j + 1) % n, true))?;
    let (a, b) = (sub(hin, c), sub(hout, c));
    let (la, lb) = (len(a), len(b));
    if la == 0.0 || lb == 0.0 { return None; }
    let cross = (a.0 * b.1 - a.1 * b.0) / (la * lb);
    let dot = (a.0 * b.0 + a.1 * b.1) / (la * lb);
    Some((cross.abs(), dot, la.min(lb)))
}
/// Smooth node: opposed handles whose deviation is within one grid step of rounding wobble.
fn is_smooth(r: &ReferenceRing, j: usize) -> bool {
    match flow_dev(r, j) { Some((s, d, lmin)) => d < 0.0 && s <= GRID_STEP / lmin, None => false }
}
/// Nodes that look smooth but are measurably off-tangent (candidates for pass T): opposed handles
/// (dot < 0) with a deviation above rounding wobble. No upper angle bound: a designed corner is
/// protected by the acceptance rule (tangent deviation, area_error and missing_extrema must not worsen).
fn flow_candidate(r: &ReferenceRing, j: usize) -> bool {
    match flow_dev(r, j) { Some((s, d, lmin)) => d < 0.0 && s > GRID_STEP / lmin, None => false }
}

// Exact reject-fast pre-screen (same contract as lever_api::area_error_below):
// both passes decide on thresholds (`e <= best` / `e < pick_or_best`), so a
// None from area_error_below at the matching strict-successor limit is a
// certain reject. Skipped scans still increment `evals`, keeping the cap, the
// counters and the report notes bit-identical; only the runtime of rejected
// candidates changes.
#[cfg(not(test))]
fn tails_prescreen_enabled() -> bool { true }
#[cfg(test)]
fn tails_prescreen_enabled() -> bool { TAILS_PRESCREEN_ENABLED.load(std::sync::atomic::Ordering::SeqCst) }
#[cfg(test)]
static TAILS_PRESCREEN_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
#[cfg(test)]
static TAILS_PRESCREEN_FIRED: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
/// strict successor of a nonnegative finite f64 (best/thresholds are >= 0 here)
fn next_up_nn(x: f64) -> f64 { debug_assert!(x.is_finite() && x >= 0.0); f64::from_bits(x.to_bits() + 1) }

struct Ctx<'a> { mask: &'a SourceMask, evals: usize, cap: usize, skipped: usize, flatten_rejected: usize }
impl<'a> Ctx<'a> {
    fn area(&mut self, rings: &[ReferenceRing]) -> Option<f64> {
        if self.evals >= self.cap { self.skipped += 1; return None; }
        // flatten budget guard (candidate): a candidate that would exceed the declared budget is rejected, never flattened.
        if let Some(max_total) = crate::flatten_budget::max_total_segments(self.mask.w, self.mask.h) {
            if crate::flatten_budget::check_flatten_budget(rings, self.mask, max_total).is_err() { self.flatten_rejected += 1; return None; }
        }
        self.evals += 1;
        Some(area_error(rings, self.mask))
    }
    /// Same bookkeeping as `area` (cap, flatten guard, eval counter), with the
    /// exact reject-fast scan: outer None = caller-config refusal, inner None
    /// = certain reject at `limit`.
    fn area_below(&mut self, rings: &[ReferenceRing], limit: f64) -> Option<Option<f64>> {
        if self.evals >= self.cap { self.skipped += 1; return None; }
        if let Some(max_total) = crate::flatten_budget::max_total_segments(self.mask.w, self.mask.h) {
            if crate::flatten_budget::check_flatten_budget(rings, self.mask, max_total).is_err() { self.flatten_rejected += 1; return None; }
        }
        self.evals += 1;
        Some(crate::lever_api::area_error_below(rings, self.mask, limit))
    }
}

pub fn refine_tails(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, cfg: &TailConfig) -> LeverResult {
    cfg.validate()?;
    if !mask.valid() { return Err(LeverError::BadMask); }
    // flatten budget guard (entry): before any area_error/flatten on this input. Typed refusal, no retry/growth.
    let max_total = crate::flatten_budget::max_total_segments(mask.w, mask.h).ok_or_else(|| LeverError::Violation("flatten budget refused: no declarable budget".into()))?;
    crate::flatten_budget::check_flatten_budget(rings, mask, max_total).map_err(|e| LeverError::Violation(format!("flatten budget refused: {e:?}")))?;
    source_guard(rings, mask)?;
    for (i, r) in rings.iter().enumerate() {
        if !ring_ok(r) {
            return Err(if r.spans.last().map_or(true, |s| end_of(s) != r.start) { LeverError::NonClosedRing { ring: i } }
                       else { LeverError::NonIntegerInput { ring: i } });
        }
        let cap = budget.max_nodes_per_ring.get(i).copied().unwrap_or(r.spans.len());
        if r.spans.len() > cap { return Err(LeverError::NodeCeiling { ring: i, got: r.spans.len(), max: cap }); }
    }
    let nodes_before = count_nodes(rings);
    if nodes_before > budget.max_nodes {
        return Err(LeverError::NodeCeiling { ring: usize::MAX, got: nodes_before, max: budget.max_nodes });
    }
    let input_hash = hash_rings(rings);
    let area_before = area_error(rings, mask);
    let c2_before = missing_extrema(rings);

    let mut cur: Vec<ReferenceRing> = rings.to_vec();
    let mut best = area_before;
    let mut ctx = Ctx { mask, evals: 0, cap: cfg.max_area_evals, skipped: 0, flatten_rejected: 0 };
    // one-time finiteness anchor (same argument as node_objective): every
    // coverage term is in [0,1], so (w*h)*scale*scale finite proves every
    // area_error on this mask finite; otherwise the plain path runs verbatim.
    let prescreen_anchor = ((mask.w as f64) * (mask.h as f64) * mask.scale) * mask.scale;
    let prescreen_ok = tails_prescreen_enabled() && prescreen_anchor.is_finite();
    let (mut flow_ok, mut flow_rej, mut len_ok, mut len_rej, mut sweeps) = (0usize, 0usize, 0usize, 0usize, 0usize);

    // Pass T: curve flow
    if cfg.run_curve_flow {
        for ri in 0..cur.len() {
            let n = cur[ri].spans.len();
            for j in 0..n {
                if !flow_candidate(&cur[ri], j) { continue; }
                let dev0 = flow_dev(&cur[ri], j).map(|t| t.0).unwrap_or(1.0);
                let c = end_of(&cur[ri].spans[j]);
                let (si, so) = ((j, false), ((j + 1) % n, true));
                let (hi, ho) = (get(&cur[ri], si).unwrap(), get(&cur[ri], so).unwrap());
                let (a, b) = (sub(hi, c), sub(ho, c));
                // re-aim the shorter handle onto the reverse direction of the longer one
                let (slot, short, long) = if len(a) <= len(b) { (si, a, b) } else { (so, b, a) };
                let (ls, ll) = (len(short), len(long));
                let tgt = Point { x: (c.x - long.0 / ll * ls).round(), y: (c.y - long.1 / ll * ls).round() };
                if Some(tgt) == get(&cur[ri], slot) { continue; }
                let old = get(&cur[ri], slot).unwrap();
                if old.x == c.x || old.y == c.y { flow_rej += 1; continue; } // never tilt an axis-aligned (extremum) handle
                let mut trial = cur[ri].clone();
                set(&mut trial, slot, tgt);
                let dev1 = flow_dev(&trial, j).map(|t| t.0).unwrap_or(1.0);
                if dev1 >= dev0 { flow_rej += 1; continue; }
                let saved = std::mem::replace(&mut cur[ri], trial);
                // accept iff e <= best: a None at limit = next_up(best) proves e > best
                let decided = if prescreen_ok && best.is_finite() {
                    match ctx.area_below(&cur, next_up_nn(best)) {
                        None => None,
                        Some(None) => { #[cfg(test)] TAILS_PRESCREEN_FIRED.fetch_add(1, std::sync::atomic::Ordering::SeqCst); Some(None) }
                        Some(Some(e)) => Some(Some(e)),
                    }
                } else {
                    ctx.area(&cur).map(Some)
                };
                match decided {
                    Some(Some(e)) if e <= best && missing_extrema(&cur) <= c2_before => { best = e; flow_ok += 1; }
                    _ => { cur[ri] = saved; flow_rej += 1; }
                }
            }
        }
    }

    // Pass L: open-form handle length
    if cfg.experimental_length_search {
        for _ in 0..cfg.max_sweeps {
            sweeps += 1;
            let mut changed = false;
            for ri in 0..cur.len() {
                let n = cur[ri].spans.len();
                for k in 0..n {
                    if get(&cur[ri], (k, true)).is_none() { continue; }
                    for first in [true, false] {
                        let slot = (k, first);
                        let node = node_of(&cur[ri], slot);
                        let h = get(&cur[ri], slot).unwrap();
                        let v = sub(h, node);
                        let l0 = len(v);
                        if l0 == 0.0 { continue; } // degenerate handle: node role decision, not ours
                        let ch = chord(&cur[ri], k);
                        // node index whose smoothness this handle belongs to
                        let nj = if first { (k + n - 1) % n } else { k };
                        let was_smooth = is_smooth(&cur[ri], nj);
                        let mut pick: Option<(f64, Point)> = None;
                        for f in LENGTH_LADDER {
                            let cand = Point { x: (node.x + v.0 * f).round(), y: (node.y + v.1 * f).round() };
                            if cand == h || len(sub(cand, node)) > MAX_LEN_PER_CHORD * ch { continue; }
                            let mut trial = cur[ri].clone();
                            set(&mut trial, slot, cand);
                            if was_smooth && !is_smooth(&trial, nj) { len_rej += 1; continue; }
                            let saved = std::mem::replace(&mut cur[ri], trial);
                            // accept iff e < pick_or_best: a None at that exact
                            // limit proves e >= pick_or_best
                            let threshold = pick.map_or(best, |p| p.0);
                            let e = if prescreen_ok && threshold.is_finite() {
                                match ctx.area_below(&cur, threshold) {
                                    None => None,
                                    Some(None) => { #[cfg(test)] TAILS_PRESCREEN_FIRED.fetch_add(1, std::sync::atomic::Ordering::SeqCst); Some(None) }
                                    Some(Some(v)) => Some(Some(v)),
                                }
                            } else {
                                ctx.area(&cur).map(Some)
                            };
                            let m = missing_extrema(&cur);
                            cur[ri] = saved;
                            match e {
                                Some(Some(e)) if e < pick.map_or(best, |p| p.0) && m <= c2_before => pick = Some((e, cand)),
                                _ => len_rej += 1,
                            }
                        }
                        if let Some((e, cand)) = pick { set(&mut cur[ri], slot, cand); best = e; len_ok += 1; changed = true; }
                    }
                }
            }
            if !changed { break; }
        }
    }

    if count_nodes(&cur) != nodes_before { return Err(LeverError::Violation("node count changed".into())); }
    if !cur.iter().all(ring_ok) { return Err(LeverError::Violation("output not closed/integer".into())); }
    form_guard(rings, &cur)?;
    if missing_extrema(&cur) > c2_before { return Err(LeverError::Violation("C2 increased".into())); }
    let area_after = area_error(&cur, mask);
    if area_after > area_before { return Err(LeverError::Violation("area_after > area_before".into())); }
    let disp = rings.iter().zip(&cur).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
    let length_note = if cfg.experimental_length_search { "length-search=experimental" } else { "length-search unsupported: no grounded candidate policy" };
    let notes = format!("{};flow_applied={};flow_rejected={};len_applied={};len_rejected={};sweeps={};area_evals={};skipped_budget={};flatten_rejected={}",
        length_note, flow_ok, flow_rej, len_ok, len_rej, sweeps, ctx.evals, ctx.skipped, ctx.flatten_rejected);
    let report = LeverReport {
        lever: "tail_refine", lever_id: LEVER_ID, api_version: LEVER_API_VERSION,
        stage_tag: "post-fit/default", input_hash, output_hash: hash_rings(&cur), seed: 0,
        nodes_before, nodes_after: nodes_before, area_before, area_after, c2_missing: missing_extrema(&cur),
        max_node_displacement: disp, notes,
    };
    Ok((cur, report))
}

/// Largest coordinate change over handles and nodes (nodes never move, so this is handle motion).
fn max_disp(a: &ReferenceRing, b: &ReferenceRing) -> f64 {
    let d = |p: Point, q: Point| (p.x - q.x).abs().max((p.y - q.y).abs());
    let mut m = d(a.start, b.start);
    for (s, t) in a.spans.iter().zip(&b.spans) {
        match (s, t) {
            (Span::Line { end: e1 }, Span::Line { end: e2 }) => m = m.max(d(*e1, *e2)),
            (Span::Cubic { control_one: a1, control_two: a2, end: a3 }, Span::Cubic { control_one: b1, control_two: b2, end: b3 }) =>
                m = m.max(d(*a1, *b1)).max(d(*a2, *b2)).max(d(*a3, *b3)),
            _ => {}
        }
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn circle(kx: f64) -> ReferenceRing {
        let r = 20.0; let k = kx;
        ReferenceRing { start: p(r, 0.0), spans: vec![
            Span::Cubic { control_one: p(r, k), control_two: p(k, r), end: p(0.0, r) },
            Span::Cubic { control_one: p(-k, r), control_two: p(-r, k), end: p(-r, 0.0) },
            Span::Cubic { control_one: p(-r, -k), control_two: p(-k, -r), end: p(0.0, -r) },
            Span::Cubic { control_one: p(k, -r), control_two: p(r, -k), end: p(r, 0.0) },
        ]}
    }
    fn mask() -> SourceMask {
        let (w, h) = (60usize, 60usize);
        let mut ink = vec![255u8; w * h];
        for j in 0..h { for i in 0..w {
            let (x, y) = (i as f64 + 0.5 - 30.0, 30.0 - (j as f64 + 0.5));
            if x * x + y * y <= 400.0 { ink[j * w + i] = 0; }
        }}
        SourceMask { w, h, ink, scale: 1.0, origin: (-30.0, 30.0) }
    }
    fn exp() -> TailConfig { TailConfig { experimental_length_search: true, ..Default::default() } }
    fn budget() -> NodeBudget { NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] } }
    /// Dual-driver oracle (cascade precedent): the pre-screen driver must
    /// produce bit-identical rings AND reports (notes counters included) on
    /// fixtures exercising flow accepts and rejects, with and without the
    /// experimental length pass; and the skip must actually fire.
    #[test]
    fn prescreen_bit_identical_and_fires() {
        let mut fired_total = 0usize;
        for input in [circle(4.0), circle(11.0), circle(7.0)] {
            for cfg in [TailConfig::default(), exp()] {
                let m = mask();
                TAILS_PRESCREEN_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
                let plain = refine_tails(&[input.clone()], &m, &budget(), &cfg).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
                TAILS_PRESCREEN_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
                TAILS_PRESCREEN_FIRED.store(0, std::sync::atomic::Ordering::SeqCst);
                let pre = refine_tails(&[input.clone()], &m, &budget(), &cfg).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
                assert_eq!(plain, pre, "pre-screen must be bit-identical to the plain driver");
                fired_total += TAILS_PRESCREEN_FIRED.load(std::sync::atomic::Ordering::SeqCst);
            }
        }
        assert!(fired_total > 0, "pre-screen must actually skip at least one certain reject");
    }

    #[test]
    fn repairs_collapsed_handles_keeping_nodes() {
        // kappa*r = 11 is the exact circle handle; 4 collapses the arc (a distorted region)
        let input = circle(4.0);
        let (out, rep) = refine_tails(&[input.clone()], &mask(), &budget(), &exp()).unwrap();
        assert!(rep.area_after < rep.area_before, "{}", rep.notes);
        assert_eq!(rep.nodes_after, 4);
        assert_eq!(out[0].start, input.start);
        for (a, b) in input.spans.iter().zip(&out[0].spans) { assert_eq!(end_of(a), end_of(b)); }
        for j in 0..4 { assert!(is_smooth(&out[0], j), "node {} lost smoothness", j); }
    }
    #[test]
    fn default_route_has_no_length_search_and_says_so() {
        let input = circle(4.0);
        let (out, rep) = refine_tails(&[input.clone()], &mask(), &budget(), &TailConfig::default()).unwrap();
        assert!(rep.notes.starts_with("length-search unsupported: no grounded candidate policy"), "{}", rep.notes);
        assert!(rep.notes.contains("len_applied=0"), "{}", rep.notes);
        // pass T alone cannot repair collapsed handles on a circle: output equals input or differs only in flow moves
        for (a, b) in input.spans.iter().zip(&out[0].spans) { assert_eq!(end_of(a), end_of(b)); }
        let (_, rx) = refine_tails(&[input], &mask(), &budget(), &exp()).unwrap();
        assert!(rx.notes.starts_with("length-search=experimental") && rx.area_after <= rep.area_after);
    }
    #[test]
    fn good_ring_untouched() {
        let (out, rep) = refine_tails(&[circle(11.0)], &mask(), &budget(), &TailConfig::default()).unwrap();
        assert!(rep.area_after <= rep.area_before);
        assert!(rep.max_node_displacement <= 2.0, "{}", rep.notes);
        assert_eq!(out.len(), 1);
    }
    #[test]
    fn curve_flow_reaims_offtangent_handle() {
        let mut r = circle(11.0);
        if let Span::Cubic { control_two, .. } = &mut r.spans[0] { control_two.y = 20.0; control_two.x = 11.0; }
        // make the node at (0,20) off-tangent: outgoing handle tilted
        if let Span::Cubic { control_one, .. } = &mut r.spans[1] { control_one.y = 17.0; control_one.x = -11.0; }
        let before = flow_dev(&r, 0).unwrap().0;
        let cfg = TailConfig { experimental_length_search: false, ..Default::default() };
        let (out, rep) = refine_tails(&[r], &mask(), &budget(), &cfg).unwrap();
        let after = flow_dev(&out[0], 0).unwrap().0;
        assert!(after <= before, "{} {}", before, after);
        assert!(rep.area_after <= rep.area_before);
    }
    fn mask_px() -> SourceMask { mask() }
    #[test]
    fn source_guard_refuses_wrong_frame_and_blank_mask() {
        // y-flipped frame: ring far outside the canvas
        let mut m = mask(); m.origin = (-30.0, 30.0 + 500.0);
        let e = refine_tails(&[circle(11.0)], &m, &budget(), &TailConfig::default()).unwrap_err();
        assert!(matches!(&e, LeverError::Violation(s) if s.starts_with("source guard")), "{:?}", e);
        let mut blank = mask_px(); blank.ink = vec![255u8; blank.w * blank.h];
        assert!(matches!(refine_tails(&[circle(11.0)], &blank, &budget(), &TailConfig::default()), Err(LeverError::Violation(s)) if s.contains("no ink")));
        assert!(matches!(refine_tails(&[], &mask(), &budget(), &TailConfig::default()), Err(LeverError::Violation(_))));
    }
    #[test]
    fn frame_slack_is_one_grid_step_only() {
        // circle radius 20 centred at origin; mask spans x in [-30,30). Shift origin so max node x lands 1 step / 2 steps past the edge.
        let mut m = mask();
        m.origin = (-(60.0 - 20.0), 30.0); // max node x = 20 -> pixel 60: on the edge
        assert!(source_guard(&[circle(11.0)], &m).is_ok());
        m.origin = (-(60.0 - 20.0) - 1.0, 30.0); // 1 px past edge at scale 1 = one grid step: allowed
        assert!(source_guard(&[circle(11.0)], &m).is_ok());
        m.origin = (-(60.0 - 20.0) - 2.0, 30.0); // two px past: refused
        assert!(source_guard(&[circle(11.0)], &m).is_err());
    }
    #[test]
    fn form_guard_catches_flip_tilt_collapse() {
        let a = circle(11.0);
        let mut flip = a.clone(); if let Span::Cubic { control_one, .. } = &mut flip.spans[0] { control_one.y = -11.0; }
        assert!(form_guard(&[a.clone()], &[flip]).is_err());
        let mut tilt = a.clone(); if let Span::Cubic { control_one, .. } = &mut tilt.spans[0] { control_one.x = 19.0; }
        assert!(matches!(form_guard(&[a.clone()], &[tilt]), Err(LeverError::Violation(s)) if s.contains("tilted")));
        let mut col = a.clone(); if let Span::Cubic { control_one, .. } = &mut col.spans[0] { control_one.y = 0.0; }
        assert!(form_guard(&[a.clone()], &[col]).is_err());
        assert!(form_guard(&[a.clone()], &[a]).is_ok());
    }
    #[test]
    fn c2_guard_with_real_missing_extrema() {
        // tilted ring: nodes are off the axis extrema, so missing_extrema is non-trivial
        let rot = |q: Point| p((q.x * 0.8 - q.y * 0.6).round(), (q.x * 0.6 + q.y * 0.8).round());
        for k in [4.0, 8.0, 11.0] {
            let mut r = circle(k);
            r.start = rot(r.start);
            for s in &mut r.spans { if let Span::Cubic { control_one, control_two, end } = s { *control_one = rot(*control_one); *control_two = rot(*control_two); *end = rot(*end); } }
            let before = missing_extrema(&[r.clone()]);
            let (out, rep) = refine_tails(&[r], &mask(), &budget(), &TailConfig::default()).unwrap();
            assert!(missing_extrema(&out) <= before, "k={} {} -> {}", k, before, missing_extrema(&out));
            assert_eq!(rep.c2_missing, missing_extrema(&out));
            assert!(rep.area_after <= rep.area_before);
        }
    }
    #[test]
    fn deterministic() {
        let r = vec![circle(5.0)];
        let a = refine_tails(&r, &mask(), &budget(), &TailConfig::default()).unwrap();
        let b = refine_tails(&r, &mask(), &budget(), &TailConfig::default()).unwrap();
        assert_eq!(a.1.output_hash, b.1.output_hash);
    }
    #[test]
    fn typed_errors() {
        let mut bad = circle(11.0);
        if let Span::Cubic { control_one, .. } = &mut bad.spans[0] { control_one.y = 5.5; }
        assert!(matches!(refine_tails(&[bad], &mask(), &budget(), &TailConfig::default()), Err(LeverError::NonIntegerInput { .. })));
        let mut open = circle(11.0); open.start = p(1.0, 0.0);
        assert!(matches!(refine_tails(&[open], &mask(), &budget(), &TailConfig::default()), Err(LeverError::NonClosedRing { .. })));
        let c = TailConfig { max_sweeps: 0, ..Default::default() };
        assert!(refine_tails(&[circle(11.0)], &mask(), &budget(), &c).is_err());
        let tight = NodeBudget { max_nodes: 3, max_nodes_per_ring: vec![] };
        assert!(matches!(refine_tails(&[circle(11.0)], &mask(), &tight, &TailConfig::default()), Err(LeverError::NodeCeiling { .. })));
    }
}
