//! L1 integer refinement. Opt-in post-fit lever: local search on integer node and control
//! coordinates, each moved by at most 1 font unit from its input value, minimising the exact-area
//! coverage error against the threshold-128 mask (lever_api::area_error).
//! No node is added or removed; extremum nodes keep their extremum; axis-aligned lines and
//! axis-aligned handles stay aligned; no new interior extremum appears in any cubic.
//! Pure, deterministic, serial; fixed visiting order; no constants beyond the +-1 unit step the
//! contract names.
use crate::lever_api::*;
use crate::reference_slice::{Point, ReferenceRing, Span};

pub const LEVER_ID: &str = "L1.int_refine";
pub const STAGE_TAG: &str = "post-fit/opt-in";
pub const SEED: u64 = 0; // no randomness; reported for the run report

fn end_of(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }

fn is_int(v: f64) -> bool { v.is_finite() && v == v.round() }
fn ring_is_integer(r: &ReferenceRing) -> bool {
    let ok = |p: &Point| is_int(p.x) && is_int(p.y);
    ok(&r.start) && r.spans.iter().all(|s| match s {
        Span::Line { end } => ok(end),
        Span::Cubic { control_one, control_two, end } => ok(control_one) && ok(control_two) && ok(end),
    })
}
fn closed(r: &ReferenceRing) -> bool {
    match r.spans.last() { Some(s) => end_of(s) == r.start, None => false }
}

/// Structural fingerprint that a move must preserve.
#[derive(PartialEq, Clone, Debug)]
struct Shape {
    ext: Vec<(bool, bool)>,          // per node: extremum in x, in y
    interior: Vec<(u8, u8)>,         // per span: interior extrema roots count in x, y
    line_aligned: Vec<(bool, bool)>, // per line span: shares x, shares y with start node
    handle_aligned: Vec<[(bool, bool); 2]>, // per cubic: handle shares x/y with its node
    smooth: Vec<bool>,               // per node: tangent-continuous join (exact cross == 0, dot >= 0)
}

fn nodes(r: &ReferenceRing) -> Vec<Point> { r.spans.iter().map(end_of).collect() }

fn is_ext(v: f64, a: f64, b: f64) -> bool {
    (v >= a && v >= b && (v > a || v > b)) || (v <= a && v <= b && (v < a || v < b))
}

fn shape(r: &ReferenceRing) -> Shape {
    let nd = nodes(r);
    let n = nd.len();
    let ext = (0..n).map(|j| {
        let (p, q) = (nd[(j + n - 1) % n], nd[(j + 1) % n]);
        (is_ext(nd[j].x, p.x, q.x), is_ext(nd[j].y, p.y, q.y))
    }).collect();
    let mut interior = vec![];
    let mut line_aligned = vec![];
    let mut handle_aligned = vec![];
    for (k, s) in r.spans.iter().enumerate() {
        let from = nd[(k + n - 1) % n];
        match s {
            Span::Line { end } => {
                interior.push((0, 0));
                line_aligned.push((from.x == end.x, from.y == end.y));
            }
            Span::Cubic { control_one: a, control_two: b, end } => {
                interior.push((interior_roots(from.x, a.x, b.x, end.x),
                               interior_roots(from.y, a.y, b.y, end.y)));
                handle_aligned.push([(a.x == from.x, a.y == from.y), (b.x == end.x, b.y == end.y)]);
            }
        }
    }
    let smooth = (0..n).map(|j| {
        let prev = nd[(j + n - 1) % n];
        let cur = nd[j];
        let tin = match &r.spans[j] { Span::Cubic { control_two, .. } => (cur.x - control_two.x, cur.y - control_two.y), _ => (cur.x - prev.x, cur.y - prev.y) };
        let tout = match &r.spans[(j + 1) % n] { Span::Cubic { control_one, .. } => (control_one.x - cur.x, control_one.y - cur.y), Span::Line { end } => (end.x - cur.x, end.y - cur.y) };
        tin.0 * tout.1 - tin.1 * tout.0 == 0.0 && tin.0 * tout.0 + tin.1 * tout.1 >= 0.0
    }).collect();
    Shape { ext, interior, line_aligned, handle_aligned, smooth }
}

#[derive(Clone, Copy)]
enum Mv { Node(usize), C1(usize), C2(usize) }

fn moves(r: &ReferenceRing) -> Vec<Mv> {
    let mut v = vec![];
    for k in 0..r.spans.len() {
        v.push(Mv::Node(k));
        if let Span::Cubic { .. } = r.spans[k] { v.push(Mv::C1(k)); v.push(Mv::C2(k)); }
    }
    v
}

fn shift(p: &mut Point, d: (f64, f64)) { p.x += d.0; p.y += d.1; }

fn apply_move(r: &ReferenceRing, mv: Mv, d: (f64, f64)) -> ReferenceRing {
    let mut q = r.clone();
    let n = q.spans.len();
    match mv {
        Mv::C1(k) => if let Span::Cubic { control_one, .. } = &mut q.spans[k] { shift(control_one, d) },
        Mv::C2(k) => if let Span::Cubic { control_two, .. } = &mut q.spans[k] { shift(control_two, d) },
        Mv::Node(k) => {
            // translate the node with both adjacent handles (preserves handle vectors)
            match &mut q.spans[k] {
                Span::Line { end } => shift(end, d),
                Span::Cubic { control_two, end, .. } => { shift(control_two, d); shift(end, d) }
            }
            if let Span::Cubic { control_one, .. } = &mut q.spans[(k + 1) % n] { shift(control_one, d) }
            if k == n - 1 { shift(&mut q.start, d) }
            if k == n - 1 {
                // start node is also the out-node of span 0 (handled above via (k+1)%n == 0)
            }
        }
    }
    q
}

/// Point slot inside a span: C1 = control_one, C2 = control_two, End = on-curve end (node).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Slot { C1, C2, End }
/// Per-ring movement mask. `frozen`: (span index, slot) points that must stay numerically equal (==, so +0.0 equals -0.0) to the
/// anchor. `axis_lock`: (node index, x_axis) node coordinates that must stay identical to the anchor.
/// Node n-1 owns `ring.start` as well (start == end of the last span).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RingMask {
    pub frozen: std::collections::BTreeSet<(usize, Slot)>,
    pub axis_lock: std::collections::BTreeSet<(usize, bool)>,
}
impl RingMask {
    pub fn is_empty(&self) -> bool { self.frozen.is_empty() && self.axis_lock.is_empty() }
}
fn slot_point(r: &ReferenceRing, span: usize, slot: Slot) -> Option<Point> {
    match (&r.spans[span], slot) {
        (Span::Cubic { control_one, .. }, Slot::C1) => Some(*control_one),
        (Span::Cubic { control_two, .. }, Slot::C2) => Some(*control_two),
        (Span::Line { end } | Span::Cubic { end, .. }, Slot::End) => Some(*end),
        _ => None, // Line spans have no handles
    }
}
/// True when `cand` keeps every masked point of `anchor` (exact f64 equality, no tolerance).
pub fn mask_holds(anchor: &ReferenceRing, cand: &ReferenceRing, m: &RingMask) -> bool {
    if anchor.spans.len() != cand.spans.len() { return false; }
    let n = anchor.spans.len();
    for &(k, slot) in &m.frozen {
        if k >= n { return false; }
        if slot_point(anchor, k, slot) != slot_point(cand, k, slot) { return false; }
        if slot == Slot::End && k == n - 1 && anchor.start != cand.start { return false; }
    }
    for &(k, x_axis) in &m.axis_lock {
        if k >= n { return false; }
        let (a, c) = (slot_point(anchor, k, Slot::End).unwrap(), slot_point(cand, k, Slot::End).unwrap());
        // Exact f64 equality mask check: the nested if selects the locked axis coordinate.
        #[allow(unused_parens)]
        if (if x_axis { a.x != c.x } else { a.y != c.y }) { return false; }
        if k == n - 1 && (if x_axis { anchor.start.x != cand.start.x } else { anchor.start.y != cand.start.y }) { return false; }
    }
    true
}

fn max_disp(a: &ReferenceRing, b: &ReferenceRing) -> f64 {
    let mut m: f64 = (a.start.x - b.start.x).abs().max((a.start.y - b.start.y).abs());
    for (s, t) in a.spans.iter().zip(&b.spans) {
        let pairs: Vec<(Point, Point)> = match (s, t) {
            (Span::Line { end: e1 }, Span::Line { end: e2 }) => vec![(*e1, *e2)],
            (Span::Cubic { control_one: a1, control_two: a2, end: a3 },
             Span::Cubic { control_one: b1, control_two: b2, end: b3 }) => vec![(*a1, *b1), (*a2, *b2), (*a3, *b3)],
            _ => vec![],
        };
        for (p, q) in pairs { m = m.max((p.x - q.x).abs()).max((p.y - q.y).abs()); }
    }
    m
}

/// The single entry point. Any contract violation is an Err; there is no clipped result.
// Pre-screen driver selection (pair-cascade precedent): production always
// runs the exact reject-fast evaluation; the test override forces the plain
// area_error path through the SAME accept/reject decision so the oracle can
// assert bit-identity between the two drivers.
#[cfg(not(test))]
fn area_below_enabled() -> bool { true }
#[cfg(test)]
fn area_below_enabled() -> bool { AREA_BELOW_ENABLED.load(std::sync::atomic::Ordering::SeqCst) }
#[cfg(test)]
static AREA_BELOW_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
#[cfg(test)]
static SKIP_DEDUP_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
#[cfg(test)]
static SKIP_DEDUP_FIRED: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
#[cfg(not(test))]
fn skip_dedup_enabled() -> bool { true }
#[cfg(test)]
fn skip_dedup_enabled() -> bool { SKIP_DEDUP_ENABLED.load(std::sync::atomic::Ordering::SeqCst) }

pub fn try_apply(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget) -> LeverResult {
    try_apply_masked(rings, mask, budget, &[], None)
}

/// Masked, input-anchored variant. `masks` is aligned to `rings` (empty = no mask; otherwise one
/// RingMask per ring, else typed Err). `anchor`: when Some, the +-1 displacement bound and the mask
/// are measured against these rings (the original input of a multi-pass caller) instead of `rings`.
/// With empty masks and anchor None the output is identical to `try_apply`.
pub fn try_apply_masked(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, masks: &[RingMask], anchor: Option<&[ReferenceRing]>) -> LeverResult {
    if !masks.is_empty() && masks.len() != rings.len() { return Err(LeverError::Violation("mask list not aligned to rings".into())); }
    if let Some(a) = anchor {
        if a.len() != rings.len() || a.iter().zip(rings).any(|(x, y)| x.spans.len() != y.spans.len()) { return Err(LeverError::Violation("anchor not aligned to rings".into())); }
        if !masks.is_empty() {
            for (i, ((x, y), m)) in a.iter().zip(rings).zip(masks).enumerate() {
                if !mask_holds(x, y, m) { return Err(LeverError::Violation(format!("ring {} violates its mask at entry", i))); }
            }
        }
    } else if !masks.is_empty() {
        // anchor == rings: masks hold trivially, but node indices must exist
        for (i, (r, m)) in rings.iter().zip(masks).enumerate() {
            if !mask_holds(r, r, m) { return Err(LeverError::Violation(format!("ring {} mask index out of range", i))); }
        }
    }
    if !mask.valid() { return Err(LeverError::BadMask); }
    // flatten budget guard (entry): typed refusal before any area_error/flatten on this input.
    let max_total = crate::flatten_budget::max_total_segments(mask.w, mask.h).ok_or_else(|| LeverError::Violation("flatten budget refused: no declarable budget".into()))?;
    crate::flatten_budget::check_flatten_budget(rings, mask, max_total).map_err(|e| LeverError::Violation(format!("flatten budget refused: {e:?}")))?;
    let nodes_before = count_nodes(rings);
    for (i, r) in rings.iter().enumerate() {
        if !closed(r) { return Err(LeverError::NonClosedRing { ring: i }); }
        if !ring_is_integer(r) { return Err(LeverError::NonIntegerInput { ring: i }); }
        let cap = budget.max_nodes_per_ring.get(i).copied().unwrap_or(r.spans.len());
        if r.spans.len() > cap { return Err(LeverError::NodeCeiling { ring: i, got: r.spans.len(), max: cap }); }
    }
    if nodes_before > budget.max_nodes {
        return Err(LeverError::NodeCeiling { ring: usize::MAX, got: nodes_before, max: budget.max_nodes });
    }
    let input_hash = hash_rings(rings);
    let area_before = area_error(rings, mask);
    let mut cur: Vec<ReferenceRing> = rings.to_vec();
    let mut best = area_before;
    let mut accepted = 0usize;
    let mut flatten_skipped = 0usize;
    let dirs = [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)];
    let mut masked_skipped = 0usize;
    for ri in 0..cur.len() {
        let orig = cur[ri].clone();
        let anchor_ring = match anchor { Some(a) => a[ri].clone(), None => orig.clone() };
        let ring_mask = masks.get(ri);
        let sh0 = shape(&orig);
        let mvs = moves(&orig);
        // Exact same-state skip (idea 1): `segment` bumps on every accept, so
        // within one segment `cur` and `best` are both unchanged. A candidate
        // already evaluated in the current segment was rejected (an accept
        // would have bumped the segment); the deterministic re-eval would
        // reject again, so the eval is skipped exactly - decisions, accepted
        // moves and output are unchanged.
        let mut segment = 0u64;
        let mut last_eval = vec![u64::MAX; mvs.len() * 4];
        loop {
            let mut improved = false;
            for (mi, &mv) in mvs.iter().enumerate() {
                for (di, &d) in dirs.iter().enumerate() {
                    let cand_ring = apply_move(&cur[ri], mv, d);
                    if let Mv::Node(k) = mv {
                        // an extremum node keeps its extremum coordinate: no motion on that axis
                        let (ex, ey) = sh0.ext[k];
                        if (ex && d.0 != 0.0) || (ey && d.1 != 0.0) { continue; }
                    }
                    if max_disp(&anchor_ring, &cand_ring) > 1.0 { continue; }
                    if let Some(m) = ring_mask { if !mask_holds(&anchor_ring, &cand_ring, m) { masked_skipped += 1; continue; } }
                    if shape(&cand_ring) != sh0 { continue; }
                    if skip_dedup_enabled() && last_eval[mi * 4 + di] == segment {
                        #[cfg(test)]
                        SKIP_DEDUP_FIRED.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                        continue;
                    }
                    let saved = std::mem::replace(&mut cur[ri], cand_ring);
                    // flatten budget guard (per-move candidate): a move whose flatten would exceed the declared
                    // budget is skipped (never flattened), matching the entry-guard contract.
                    if crate::flatten_budget::check_flatten_budget(&cur, mask, max_total).is_err() { cur[ri] = saved; flatten_skipped += 1; continue; }
                    last_eval[mi * 4 + di] = segment;
                    // Exact reject-fast pre-screen: area_error_below returns the
                    // bit-identical area_error value on Some, or None as soon as
                    // the nonnegative scan prefix proves e >= best. The accept
                    // decision still compares the full value (`e < best`), so
                    // accepted moves, `best` updates and the final rings are
                    // unchanged; only rejected evaluations run faster.
                    let decided = if area_below_enabled() {
                        area_error_below(&cur, mask, best)
                    } else {
                        Some(area_error(&cur, mask))
                    };
                    match decided {
                        Some(e) if e < best => { best = e; improved = true; accepted += 1; segment += 1; }
                        _ => { cur[ri] = saved; }
                    }
                }
            }
            if !improved { break; }
        }
    }
    let nodes_after = count_nodes(&cur);
    if nodes_after > nodes_before {
        return Err(LeverError::Violation("node count increased".into()));
    }
    for (i, (a, b)) in rings.iter().zip(&cur).enumerate() {
        let (sa, sb) = (shape(a), shape(b));
        if let Some(j) = (0..sa.ext.len()).find(|&j| sa.ext[j] != sb.ext[j]) {
            return Err(LeverError::ExtremumMoved { ring: i, node: j });
        }
    }
    if missing_extrema(&cur) > missing_extrema(rings) { return Err(LeverError::Violation("C2 increased".into())); }
    // final post-check: the output must still honour every mask against the anchor
    if !masks.is_empty() {
        let base: &[ReferenceRing] = anchor.unwrap_or(rings);
        if let Some(i) = (0..cur.len()).find(|&i| !mask_holds(&base[i], &cur[i], &masks[i])) {
            return Err(LeverError::Violation(format!("ring {} violates its mask in the output", i)));
        }
    }
    let disp = rings.iter().zip(&cur).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
    let report = LeverReport {
        lever: "int_refine", lever_id: LEVER_ID, api_version: LEVER_API_VERSION, stage_tag: STAGE_TAG,
        input_hash, output_hash: hash_rings(&cur), seed: SEED,
        nodes_before, nodes_after, area_before, area_after: best,
        c2_missing: missing_extrema(&cur), max_node_displacement: disp,
        // accepted_moves = moves applied; masked_skipped = candidate moves refused by the mask (0 when no mask)
        notes: format!("accepted_moves={};flatten_skipped={};masked_skipped={}", accepted, flatten_skipped, masked_skipped),
    };
    Ok((cur, report))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::reference_slice::{Point, Span};

    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn poly(v: &[(f64, f64)]) -> ReferenceRing {
        let spans = v[1..].iter().chain(std::iter::once(&v[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect();
        ReferenceRing { start: p(v[0].0, v[0].1), spans }
    }
    fn tri_inside(a: (f64, f64), b: (f64, f64), c: (f64, f64)) -> impl Fn(f64, f64) -> bool {
        move |x, y| {
            let s = |p: (f64, f64), q: (f64, f64)| (q.0 - p.0) * (y - p.1) - (q.1 - p.1) * (x - p.0);
            let (d1, d2, d3) = (s(a, b), s(b, c), s(c, a));
            (d1 >= 0.0 && d2 >= 0.0 && d3 >= 0.0) || (d1 <= 0.0 && d2 <= 0.0 && d3 <= 0.0)
        }
    }
    fn mask_from(f: impl Fn(f64, f64) -> bool) -> SourceMask {
        let (w, h, scale, origin) = (64usize, 64usize, 2.0, (0.0, 128.0));
        let mut ink = vec![255u8; w * h];
        let mut m = SourceMask { w, h, ink: vec![], scale, origin };
        for j in 0..h { for i in 0..w {
            let c = m.pixel_centre_to_font(i, j);
            if f(c.x, c.y) { ink[j * w + i] = 0; }
        } }
        m.ink = ink; m
    }
    fn budget_of(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: vec![] } }

    /// Dual-driver oracle (pair-cascade precedent): the reject-fast
    /// pre-screen driver and the plain area_error driver must produce the
    /// exact same accepted rings, report counters and hashes on a fixture
    /// that exercises both accepted and rejected candidate moves.
    #[test]
    fn area_error_below_bit_identical_to_plain_driver() {
        let m = mask_from(tri_inside((40.0, 44.0), (124.0, 36.0), (80.0, 120.0)));
        let input = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
        AREA_BELOW_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
        let plain = try_apply(&input, &m, &budget_of(&input)).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
        AREA_BELOW_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        let prescreen = try_apply(&input, &m, &budget_of(&input)).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
        assert_eq!(plain, prescreen, "pre-screen driver must be bit-identical to the plain area_error driver");
        // the fixture must actually exercise both arms: at least one accepted
        // and one rejected candidate evaluation
        let (_, rep) = try_apply(&input, &m, &budget_of(&input)).unwrap();
        assert!(rep.area_after < rep.area_before, "fixture must accept at least one move");
    }

    /// Dual-driver oracle for the same-state skip (idea 1): with the skip
    /// enabled vs disabled the full result (rings, report, hashes) must be
    /// identical, and the skip must actually fire on an accept-heavy fixture.
    #[test]
    fn skip_dedup_bit_identical_and_fires() {
        let tri_m = mask_from(tri_inside((40.0, 44.0), (124.0, 36.0), (80.0, 120.0)));
        let tri = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
        let k = 33.0;
        let (cx, cy, r) = (64.0, 64.0, 40.0);
        let cub = |c1: (f64, f64), c2: (f64, f64), e: (f64, f64)| Span::Cubic { control_one: p(c1.0, c1.1), control_two: p(c2.0, c2.1), end: p(e.0, e.1) };
        let mut off = ReferenceRing { start: p(cx + r, cy), spans: vec![
            cub((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)),
            cub((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
            cub((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)),
            cub((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)),
        ]};
        for sp in off.spans.iter_mut() {
            if let Span::Cubic { control_one, control_two, end } = sp {
                control_one.x += 1.0; control_two.y -= 1.0; end.x += 1.0;
            }
        }
        let shifted_start = match off.spans.last().unwrap() { Span::Cubic { end, .. } => *end, Span::Line { end } => *end };
        off.start = shifted_start;
        let circle_m = mask_from(|x, y| (x - 64.0).powi(2) + (y - 64.0).powi(2) <= 41.0 * 41.0);
        let mut fired_total = 0usize;
        for input in [tri, vec![off]] {
            let m = if input[0].spans.len() == 3 { &tri_m } else { &circle_m };
            SKIP_DEDUP_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
            let plain = try_apply(&input, m, &budget_of(&input)).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
            SKIP_DEDUP_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
            SKIP_DEDUP_FIRED.store(0, std::sync::atomic::Ordering::SeqCst);
            let dedup = try_apply(&input, m, &budget_of(&input)).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
            assert_eq!(plain, dedup, "same-state skip must be bit-identical to the plain sweep");
            fired_total += SKIP_DEDUP_FIRED.load(std::sync::atomic::Ordering::SeqCst);
        }
assert!(fired_total > 0, "skip must actually fire on these fixtures (got 0)");
    }

    /// Masked/anchored entry point exercises the same driver.
    #[test]
    fn area_error_below_bit_identical_masked() {
        let m = mask_from(tri_inside((40.0, 44.0), (124.0, 36.0), (80.0, 120.0)));
        let input = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
        AREA_BELOW_ENABLED.store(false, std::sync::atomic::Ordering::SeqCst);
        let plain = try_apply_masked(&input, &m, &budget_of(&input), &[], None).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
        AREA_BELOW_ENABLED.store(true, std::sync::atomic::Ordering::SeqCst);
        let prescreen = try_apply_masked(&input, &m, &budget_of(&input), &[], None).map(|(r, rep)| (format!("{r:?}"), format!("{rep:?}")));
        assert_eq!(plain, prescreen);
    }
}
