//! D2: post-fit refinement of the final emitted rings.
//! Extremum detection is a neighbour-node heuristic: a node is an x (y) extremum when its coordinate is
//! strictly beyond/at-and-beyond both neighbouring on-curve nodes; it is not computed from the curve
//! itself, and nodes that are extrema on both axes or neither are left alone.
//! Pass A (extrema handles): at every node that is an x (or y) extremum, an adjacent cubic handle
//! that is off the node's tangent axis by at most `max_snap` units is snapped onto it (handle.x ==
//! node.x for an x-extremum, handle.y == node.y for a y-extremum). A snap is kept only if it does not
//! raise area error and does not raise missing_extrema (strict: no slack, no policy knob).
//! Pass B (integer grid): int_refine::try_apply, +-1 unit local search on the integer grid; its shape
//! fingerprint keeps the aligned handles from pass A aligned.
//! Not touched: duplicate/zero-span handling (clean_emitted_ring), node count (never changes), line
//! spans, extremum node coordinates. Pure, deterministic. Input must be closed and integer, else Err.
//! Does not edit capture_fit; D1 calls `refine_emitted` on the output of fit_captured*.
use crate::lever_api::*;
use crate::int_refine::RingMask;
use crate::reference_slice::{Point, ReferenceRing, Span};

pub const LEVER_ID: &str = "D2.emitted_geometry_refine";

#[derive(Clone, Copy, Debug)]
pub struct RefineConfig {
    /// Largest handle off-axis distance (font units) that pass A will snap.
    pub max_snap: f64,
    pub run_int_refine: bool,
    /// Max full-ring area_error evaluations in pass A; remaining candidates are skipped (counted).
    pub max_area_evals: usize,
}
/// Derived, not tuned: two independently rounded integer coordinates (node and handle) of a point
/// pair that was exactly aligned before emission can differ by at most one grid step (0.5 + 0.5).
pub const GRID_STEP: f64 = 1.0;
pub const DERIVED_MAX_SNAP: f64 = GRID_STEP;
/// Exact upper bound on pass-A candidates: only nodes that are an extremum on exactly one axis
/// qualify (ex != ey), each such node has two adjacent handles (incoming, outgoing), and only the
/// one coordinate of the extremum axis is snapped: <= 2 candidates per node. The derived budget
/// therefore never skips a candidate; `max_area_evals` is a caller-imposed cap only.
pub fn derived_eval_budget(nodes: usize) -> usize { 2 * nodes }
impl Default for RefineConfig {
    fn default() -> Self { RefineConfig { max_snap: DERIVED_MAX_SNAP, run_int_refine: true, max_area_evals: usize::MAX } }
}
impl RefineConfig {
    pub fn validate(&self) -> Result<(), LeverError> {
        if !(self.max_snap.is_finite() && self.max_snap >= 0.0) { return Err(LeverError::Violation("cfg.max_snap must be finite and >= 0".into())); }
        Ok(())
    }
}

/// Prefix of the typed refusal for input that would exceed the flatten budget.
pub const FLATTEN_REFUSED_PREFIX: &str = "flatten budget refused:";
pub fn is_flatten_refused(e: &LeverError) -> bool {
    matches!(e, LeverError::Violation(m) if m.starts_with(FLATTEN_REFUSED_PREFIX))
}
/// Candidate-before-flatten guard. Runs BEFORE every area_error / flatten call on `rings`.
/// Budget convention (hub/D3 draft): MAX_TOTAL_SEGMENTS = checked mask w*h. No retry, no enlargement.
fn flatten_guard(rings: &[ReferenceRing], mask: &SourceMask) -> Result<usize, LeverError> {
    let max_total = crate::flatten_budget::max_total_segments(mask.w, mask.h)
        .ok_or_else(|| LeverError::Violation(format!("{} BadBudget (w*h overflow or zero)", FLATTEN_REFUSED_PREFIX)))?;
    crate::flatten_budget::check_flatten_budget(rings, mask, max_total)
        .map_err(|e| LeverError::Violation(format!("{} {:?}", FLATTEN_REFUSED_PREFIX, e)))
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
fn is_ext(v: f64, a: f64, b: f64) -> bool {
    (v >= a && v >= b && (v > a || v > b)) || (v <= a && v <= b && (v < a || v < b))
}

/// Candidate snaps for one ring: (span index, is_first_handle, set_x, new_value).
fn candidates(r: &ReferenceRing, max_snap: f64) -> Vec<(usize, bool, bool, f64)> {
    let n = r.spans.len();
    let nd: Vec<Point> = r.spans.iter().map(end_of).collect();
    let mut out = vec![];
    for j in 0..n {
        let (p, q, c) = (nd[(j + n - 1) % n], nd[(j + 1) % n], nd[j]);
        let (ex, ey) = (is_ext(c.x, p.x, q.x), is_ext(c.y, p.y, q.y));
        if ex == ey { continue; } // not an extremum, or a corner-like node: leave alone
        // incoming handle: control_two of span j; outgoing: control_one of span j+1
        if let Span::Cubic { control_two, .. } = &r.spans[j] {
            if ex && control_two.x != c.x && (control_two.x - c.x).abs() <= max_snap { out.push((j, false, true, c.x)); }
            if ey && control_two.y != c.y && (control_two.y - c.y).abs() <= max_snap { out.push((j, false, false, c.y)); }
        }
        if let Span::Cubic { control_one, .. } = &r.spans[(j + 1) % n] {
            if ex && control_one.x != c.x && (control_one.x - c.x).abs() <= max_snap { out.push(((j + 1) % n, true, true, c.x)); }
            if ey && control_one.y != c.y && (control_one.y - c.y).abs() <= max_snap { out.push(((j + 1) % n, true, false, c.y)); }
        }
    }
    out
}

fn with_snap(r: &ReferenceRing, (k, first, set_x, v): (usize, bool, bool, f64)) -> ReferenceRing {
    let mut q = r.clone();
    if let Span::Cubic { control_one, control_two, .. } = &mut q.spans[k] {
        let h = if first { control_one } else { control_two };
        if set_x { h.x = v } else { h.y = v }
    }
    q
}

fn refine_once(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, cfg: &RefineConfig, masks: &[RingMask], anchored: bool) -> LeverResult {
    cfg.validate()?;
    if !mask.valid() { return Err(LeverError::BadMask); }
    if let Some(i) = rings.iter().position(|r| !in_frame(r, mask)) { return Err(LeverError::Violation(format!("ring {} has a node outside the source frame", i))); }
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
    flatten_guard(rings, mask)?;
    let area_before = area_error(rings, mask);
    let c2_before = missing_extrema(rings);

    // Pass A
    let mut cur: Vec<ReferenceRing> = rings.to_vec();
    let mut best = area_before;
    let mut c2 = c2_before;
    let mut snaps = 0usize;
    let (mut rej_area, mut rej_c2, mut skipped, mut evals, mut rej_budget, mut rej_masked, mut rej_disp) = (0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize);
    let eval_cap = cfg.max_area_evals.min(derived_eval_budget(nodes_before));
    for ri in 0..cur.len() {
        for cand in candidates(&rings[ri], cfg.max_snap) {
            if let Some(m) = masks.get(ri) {
                let slot = if cand.1 { crate::int_refine::Slot::C1 } else { crate::int_refine::Slot::C2 };
                if m.frozen.contains(&(cand.0, slot)) { rej_masked += 1; continue; }
            }
            if evals >= eval_cap { skipped += 1; continue; }
            evals += 1;
            let trial = with_snap(&cur[ri], cand);
            if !disp_ok(&rings[ri..=ri], std::slice::from_ref(&trial), cfg.max_snap) { rej_disp += 1; continue; }
            let saved = std::mem::replace(&mut cur[ri], trial);
            if flatten_guard(&cur, mask).is_err() { rej_budget += 1; cur[ri] = saved; continue; }
            let e = area_error(&cur, mask);
            let m = missing_extrema(&cur);
            if e <= best && m <= c2 { best = e; c2 = m; snaps += 1; }
            else { if m > c2 { rej_c2 += 1 } else { rej_area += 1 } cur[ri] = saved; }
        }
    }
    let after_a = cur.clone();
    if !disp_ok(rings, &after_a, cfg.max_snap) { return Err(LeverError::Violation("after-A candidate exceeds the displacement bound".into())); }

    // Pass B
    let mut notes = format!("max_snap={};snapped={};rejected_area={};rejected_c2={};rejected_flatten_budget={};skipped_budget={};area_evals={}", cfg.max_snap, snaps, rej_area, rej_c2, rej_budget, skipped, evals);
    notes += &format!(";passA_displacement_rejected={}", rej_disp);
    // passA_masked = pass-A candidate checks rejected because the slot is masked (always printed, 0 included).
    // passB_masked = pass-B candidate moves refused by the mask. accepted_moves (inside int_refine[..]) = moves applied.
    notes += &format!(";passA_masked={};passA_status=completed", rej_masked);
    if cfg.run_int_refine {
        // after_a passed the guard per candidate; re-check as a whole before any area_error / try_apply
        flatten_guard(&after_a, mask)?;
        let area_a = area_error(&after_a, mask);
        match crate::int_refine::try_apply_masked(&after_a, mask, budget, masks, if anchored { Some(rings) } else { None }) {
            Ok((out, rep)) => {
                let bound_b = displacement_bound(cfg);
                let cnt = note_count(&rep.notes, "masked_skipped=");
                if !disp_ok(rings, &out, bound_b) {
                    cur = after_a; notes += &passb_note(PassB::Breach, cnt); notes += &format!(";passB_bound={}", bound_b);
                } else {
                let valid = topology_same(rings, &out) && count_nodes(&out) == nodes_before && out.iter().all(ring_ok)
                    && flatten_guard(&out, mask).is_ok()
                    && missing_extrema(&out) <= c2_before && area_error(&out, mask) <= area_a;
                if valid { cur = out; notes += &passb_note(PassB::Accepted, cnt); notes += &format!(";int_refine[{}]", rep.notes); }
                else { cur = after_a; notes += &passb_note(PassB::Invalid, cnt); }
                }
            }
            Err(e) => { cur = after_a; notes += &passb_note(PassB::Failed, None); notes += &format!(";passB_error={:?}", e); }
        }
    } else { cur = after_a; notes += &passb_note(PassB::Disabled, None); }
    if count_nodes(&cur) != nodes_before { return Err(LeverError::Violation("node count changed".into())); }
    if !cur.iter().all(ring_ok) { return Err(LeverError::Violation("output not closed/integer".into())); }
    let c2_after = missing_extrema(&cur);
    if c2_after > c2_before { return Err(LeverError::Violation("C2 increased".into())); }
    flatten_guard(&cur, mask)?;
    let area_after = area_error(&cur, mask);
    if area_after > area_before { return Err(LeverError::Violation("area_after > area_before".into())); }
    if !area_after.is_finite() { return Err(LeverError::Violation("non-finite area".into())); }
    if !topology_same(rings, &cur) { return Err(LeverError::Violation("topology changed".into())); }
    let disp = rings.iter().zip(&cur).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
    if !disp.is_finite() || !all_finite(&cur) { return Err(LeverError::Violation("non-finite displacement".into())); }
    if disp > cfg.max_snap { return Err(LeverError::Violation(format!("displacement {} exceeds bound {}", disp, cfg.max_snap))); }
    let report = LeverReport {
        lever: "emitted_geometry_refine", lever_id: LEVER_ID, api_version: LEVER_API_VERSION,
        stage_tag: "post-fit/default", input_hash, output_hash: hash_rings(&cur), seed: 0,
        nodes_before, nodes_after: nodes_before, area_before, area_after, c2_missing: c2_after,
        max_node_displacement: disp, notes,
    };
    Ok((cur, report))
}

/// Displacement bound, anchored to the call input and equal to cfg.max_snap (default 1 FU). Pass B moves
/// whole grid steps, so with max_snap < 1 every pass-B move breaches and the after-A candidate is returned.
fn displacement_bound(cfg: &RefineConfig) -> f64 { cfg.max_snap }
fn all_finite(rings: &[ReferenceRing]) -> bool {
    let ok = |p: &Point| p.x.is_finite() && p.y.is_finite();
    rings.iter().all(|r| ok(&r.start) && r.spans.iter().all(|s| match s {
        Span::Line { end } => ok(end),
        Span::Cubic { control_one, control_two, end } => ok(control_one) && ok(control_two) && ok(end),
    }))
}
/// f64::max swallows NaN, so finiteness of every coordinate is checked explicitly.
fn disp_ok(input: &[ReferenceRing], out: &[ReferenceRing], bound: f64) -> bool {
    if !all_finite(input) || !all_finite(out) { return false; }
    let d = input.iter().zip(out).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
    d.is_finite() && d <= bound
}
/// Topology identity: same ring count, same span count and the same Line/Cubic kind at every index.
fn topology_same(a: &[ReferenceRing], b: &[ReferenceRing]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.spans.len() == y.spans.len()
        && x.spans.iter().zip(&y.spans).all(|(p, q)| matches!((p, q), (Span::Line { .. }, Span::Line { .. }) | (Span::Cubic { .. }, Span::Cubic { .. }))))
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PassB { Disabled, Accepted, Breach, Invalid, Failed }
/// Pass-B receipt fragment. Count is the actual masked_skipped of the int_refine report; a missing or
/// unparsable count is printed as UNAVAILABLE (never 0), a pass that did not run prints NOT_RUN.
fn passb_note(o: PassB, count: Option<usize>) -> String {
    let (status, cnt) = match o {
        PassB::Disabled => ("disabled", "NOT_RUN".to_string()),
        PassB::Accepted => ("accepted", count.map_or("UNAVAILABLE".to_string(), |v| v.to_string())),
        PassB::Breach => ("displacement_breach_return_after_A", count.map_or("UNAVAILABLE".to_string(), |v| v.to_string())),
        PassB::Invalid => ("invalid_return_after_A", count.map_or("UNAVAILABLE".to_string(), |v| v.to_string())),
        PassB::Failed => ("error_return_after_A", "UNAVAILABLE".to_string()),
    };
    format!(";passB_status={};passB_masked={}", status, cnt)
}
fn note_count(notes: &str, key: &str) -> Option<usize> {
    notes.split(|c| c == ';' || c == '[' || c == ']').find_map(|t| t.strip_prefix(key)).and_then(|v| v.parse().ok())
}

/// Source-frame guard: every on-curve node must lie inside the mask frame, widened by one grid step
/// for integer rounding of nodes on the bitmap edge; handles may leave the frame. Frame is
/// x in [origin.0, origin.0 + w*scale], y in [origin.1 - h*scale, origin.1] (y-up, same as SourceMask).
fn in_frame(r: &ReferenceRing, m: &SourceMask) -> bool {
    let (x0, x1) = (m.origin.0 - GRID_STEP, m.origin.0 + m.w as f64 * m.scale + GRID_STEP);
    let (y0, y1) = (m.origin.1 - m.h as f64 * m.scale - GRID_STEP, m.origin.1 + GRID_STEP);
    let ok = |p: Point| p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;
    ok(r.start) && r.spans.iter().all(|s| ok(end_of(s)))
}

/// SINGLE PASS. DECLARED behaviour change: the earlier iterate-until-stable loop (up to 64 rounds) is removed.
/// Whenever a second round would have moved anything (blank or poorly matching masks drifted rings by
/// 10+ font units) the output now differs and stays within the bound of the call input.
/// One pass A + one pass B, one receipt (`passes=1`). Pass B is anchored to the INPUT: every point
/// ends within one grid step of where the caller gave it (pass A snaps are bounded by max_snap).
/// Not idempotent by design: a second call re-anchors on its own input.
pub fn refine_emitted(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget, cfg: &RefineConfig) -> LeverResult {
    let (out, mut rep) = refine_once(rings, mask, budget, cfg, &[], true)?;
    rep.notes = format!("passes=1;convergence=not_evaluated;{};final_status=accepted", rep.notes);
    Ok((out, rep))
}

/// What a reference target requires of one on-curve node. Local, minimal type: A1 maps its
/// reference_targets (corner / extremum hints) onto this.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Protect {
    /// Corner: node position fixed exactly; neither adjacent handle may be moved off its input value.
    Corner,
    /// Extremum on x (true) or y (false) axis: node keeps that coordinate and stays an extremum;
    /// adjacent handles keep their alignment on that axis.
    Extremum { x_axis: bool },
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ProtectedNode { pub ring: usize, pub node: usize, pub kind: Protect }

/// Prefix of the hard-fail error for a protected identity that does not exist in the input.
/// Callers must propagate it as a hard Err (a wrong identity is a caller bug, not a refusal).
pub const INVALID_IDENTITY_PREFIX: &str = "protected identity invalid:";
pub fn is_invalid_protected_identity(e: &LeverError) -> bool {
    matches!(e, LeverError::Violation(m) if m.starts_with(INVALID_IDENTITY_PREFIX))
}
/// Receipt marker (in LeverReport.notes) for a valid-identity protection violation found by the
/// final post-check: the candidate was refused and the exact input returned.
pub const CANDIDATE_REFUSED_NOTE: &str = "candidate_refused=protection_violated";

/// Validate identities BEFORE any mask is built or any area_error/flatten runs. Identity =
/// (ring index, node index) in the INPUT rings, node i = end_of(spans[i]) (node n-1 owns `start`).
fn validate_identities(rings: &[ReferenceRing], protect: &[ProtectedNode]) -> Result<(), LeverError> {
    for p in protect {
        match rings.get(p.ring) {
            Some(r) if p.node < r.spans.len() => {}
            _ => return Err(LeverError::Violation(format!("{} ring {} node {} out of range", INVALID_IDENTITY_PREFIX, p.ring, p.node))),
        }
    }
    Ok(())
}

/// Build per-ring masks from validated identities.
/// Node j = end(spans[j]); IN = C2 of spans[j] (only when it is a Cubic), OUT = C1 of spans[(j+1)%n]
/// (only when it is a Cubic); Line spans have no handles and no synthetic cubic is invented.
/// Corner at node k: node endpoint, IN and OUT are frozen. Extremum at node k: conservative full-node
/// freeze (the same three points, so the required handles cannot move) plus an axis lock on the node
/// itself and on its two neighbouring NODES (k-1, k+1): their coordinate on the protected axis stays
/// identical. Neighbouring node coordinates are locked; neighbouring handles are NOT locked and may
/// change, and the final protection check still requires the extremum status to hold. The axis lock
/// compares End points (and `ring.start` for the last node) only. The final `mask_holds` is the
/// actual slot rejection.
fn build_masks(rings: &[ReferenceRing], protect: &[ProtectedNode]) -> Vec<RingMask> {
    use crate::int_refine::Slot;
    let mut masks = vec![RingMask::default(); rings.len()];
    for p in protect {
        let n = rings[p.ring].spans.len();
        let m = &mut masks[p.ring];
        let k = p.node;
        m.frozen.insert((k, Slot::End));
        m.frozen.insert((k, Slot::C2));
        m.frozen.insert(((k + 1) % n, Slot::C1));
        if let Protect::Extremum { x_axis } = p.kind {
            m.axis_lock.insert((k, x_axis));
            m.axis_lock.insert(((k + n - 1) % n, x_axis));
            m.axis_lock.insert(((k + 1) % n, x_axis));
        }
    }
    masks
}

/// Masked entry. Order: (1) identities validated (hard Err, nothing else runs), (2) empty protect
/// delegates to `refine_emitted`, (3) otherwise ONE pass (pass A
/// with masked handles, pass B int_refine with masks and the +-1 bound anchored to the INPUT), one
/// receipt (passes=1), (4) final post-check against the input: masks, extremum status and the input
/// anchored displacement bound; any failure returns the exact input with CANDIDATE_REFUSED_NOTE.
/// Not idempotent by design: a second call re-anchors on its own input.
pub fn refine_emitted_masked(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget,
                             cfg: &RefineConfig, protect: &[ProtectedNode]) -> LeverResult {
    validate_identities(rings, protect)?;
    if protect.is_empty() { return refine_emitted(rings, mask, budget, cfg); }
    let masks = build_masks(rings, protect);
    let (out, mut rep) = refine_once(rings, mask, budget, cfg, &masks, true)?;
    let bound = displacement_bound(cfg);
    match post_check(rings, &out, &masks, protect, bound) {
        Ok(()) => {
            rep.notes = format!("passes=1;convergence=not_evaluated;protected={};protection_violations=0;bound={};{};final_status=accepted", protect.len(), bound, rep.notes);
            Ok((out, rep))
        }
        Err(violations) => Ok(fallback_to_input(rings, rep, protect.len(), violations, bound)),
    }
}
/// Compatibility name used by earlier callers; same semantics as `refine_emitted_masked`.
pub fn refine_emitted_guided(rings: &[ReferenceRing], mask: &SourceMask, budget: &NodeBudget,
                             cfg: &RefineConfig, protect: &[ProtectedNode]) -> LeverResult {
    refine_emitted_masked(rings, mask, budget, cfg, protect)
}

/// Final post-check; Err carries the number of violated checks (>= 1).
fn post_check(input: &[ReferenceRing], out: &[ReferenceRing], masks: &[RingMask], protect: &[ProtectedNode], bound: f64) -> Result<(), usize> {
    let mut v = 0usize;
    if !all_finite(input) || !all_finite(out) || !bound.is_finite() || bound < 0.0 { return Err(1); }
    if !topology_same(input, out) { return Err(1); }
    for (i, (a, b)) in input.iter().zip(out).enumerate() {
        if !crate::int_refine::mask_holds(a, b, &masks[i]) { v += 1; }
    }
    v += protect.iter().filter(|p| !protection_holds(&input[p.ring], &out[p.ring], p)).count();
    let disp = input.iter().zip(out).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
    if !(disp <= bound) { v += 1; }
    if v == 0 { Ok(()) } else { Err(v) }
}
fn fallback_to_input(rings: &[ReferenceRing], mut rep: LeverReport, nprot: usize, violations: usize, bound: f64) -> (Vec<ReferenceRing>, LeverReport) {
    rep.output_hash = rep.input_hash;
    rep.area_after = rep.area_before;
    rep.c2_missing = missing_extrema(rings);
    rep.nodes_after = rep.nodes_before;
    rep.max_node_displacement = 0.0;
    rep.notes = format!("passes=1;convergence=not_evaluated;{};{};protected={};protection_violations={};bound={};final_status=input_fallback;fell_back_to_input", rep.notes, CANDIDATE_REFUSED_NOTE, nprot, violations, bound);
    (rings.to_vec(), rep)
}

fn protection_holds(a: &ReferenceRing, b: &ReferenceRing, p: &ProtectedNode) -> bool {
    let n = a.spans.len();
    let (na, nb) = (end_of(&a.spans[p.node]), end_of(&b.spans[p.node]));
    let in_h = |r: &ReferenceRing| match &r.spans[p.node] { Span::Cubic { control_two, .. } => Some(*control_two), _ => None };
    let out_h = |r: &ReferenceRing| match &r.spans[(p.node + 1) % n] { Span::Cubic { control_one, .. } => Some(*control_one), _ => None };
    match p.kind {
        Protect::Corner => na == nb && in_h(a) == in_h(b) && out_h(a) == out_h(b),
        Protect::Extremum { x_axis } => {
            let (prev_a, next_a) = (end_of(&a.spans[(p.node + n - 1) % n]), end_of(&a.spans[(p.node + 1) % n]));
            let (prev_b, next_b) = (end_of(&b.spans[(p.node + n - 1) % n]), end_of(&b.spans[(p.node + 1) % n]));
            let get = |q: Point| if x_axis { q.x } else { q.y };
            let same_align = |h: Option<Point>, hb: Option<Point>| match (h, hb) {
                (Some(h), Some(hb)) => (get(h) == get(na)) == (get(hb) == get(nb)),
                (None, None) => true, _ => false,
            };
            get(na) == get(nb)
                && is_ext(get(nb), get(prev_b), get(next_b)) == is_ext(get(na), get(prev_a), get(next_a))
                && same_align(in_h(a), in_h(b)) && same_align(out_h(a), out_h(b))
        }
    }
}

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
    // A rounded blob: 4 cubic spans with extremum nodes; one handle is 1 unit off-axis.
    fn blob(off: f64) -> ReferenceRing {
        let k = 5.0;
        ReferenceRing { start: p(10.0, 0.0), spans: vec![
            Span::Cubic { control_one: p(10.0 + off, k), control_two: p(k, 10.0), end: p(0.0, 10.0) },
            Span::Cubic { control_one: p(-k, 10.0), control_two: p(-10.0, k), end: p(-10.0, 0.0) },
            Span::Cubic { control_one: p(-10.0, -k), control_two: p(-k, -10.0), end: p(0.0, -10.0) },
            Span::Cubic { control_one: p(k, -10.0), control_two: p(10.0, -k), end: p(10.0, 0.0) },
        ]}
    }
    fn mask() -> SourceMask {
        let (w, h) = (40usize, 40usize);
        let mut ink = vec![255u8; w * h];
        for j in 0..h { for i in 0..w {
            let (x, y) = (i as f64 + 0.5 - 20.0, 20.0 - (j as f64 + 0.5));
            if x * x + y * y <= 100.0 { ink[j * w + i] = 0; }
        }}
        SourceMask { w, h, ink, scale: 1.0, origin: (-20.0, 20.0) }
    }
    #[test]
    fn default_snaps_improving_handle_exactly() {
        // handle 1 unit inside the extremum: snapping lowers area error (18.594 -> 16.515 on this mask)
        let b = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] };
        let (out, rep) = refine_emitted(&[blob(-1.0)], &mask(), &b, &RefineConfig::default()).unwrap();
        assert_eq!(rep.nodes_after, 4);
        assert!(rep.area_after < rep.area_before);
        assert!(rep.notes.contains("snapped=1"), "{}", rep.notes);
        match &out[0].spans[0] { Span::Cubic { control_one, .. } => assert_eq!(control_one.x, 10.0), _ => panic!() }
    }
    #[test]
    fn default_rejects_worsening_snap_exactly() {
        // handle 1 unit outside fits the mask better (16.045 vs 16.515): snap must be rejected, handle untouched
        let b = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] };
        let cfg = RefineConfig { run_int_refine: false, ..Default::default() };
        let (out, rep) = refine_emitted(&[blob(1.0)], &mask(), &b, &cfg).unwrap();
        assert!(rep.notes.contains("snapped=0") && rep.notes.contains("rejected_area=1"), "{}", rep.notes);
        match &out[0].spans[0] { Span::Cubic { control_one, .. } => assert_eq!(control_one.x, 11.0), _ => panic!() }
    }
    #[test]
    fn rejects_bad_cfg() {
        let b = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] };
        for c in [RefineConfig{max_snap:f64::NAN,..Default::default()}, RefineConfig{max_snap:-1.0,..Default::default()}] {
            assert!(refine_emitted(&[blob(0.0)], &mask(), &b, &c).is_err());
        }
    }
    #[test]
    fn default_never_worse() {
        let b = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] };
        for off in [-1.0, 0.0, 1.0] {
            let (_, rep) = refine_emitted(&[blob(off)], &mask(), &b, &RefineConfig::default()).unwrap();
            assert!(rep.area_after <= rep.area_before);
        }
    }
    #[test]
    fn deterministic_and_rejects_noninteger() {
        let r = vec![blob(0.0)];
        let b = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] };
        let a = refine_emitted(&r, &mask(), &b, &RefineConfig::default()).unwrap();
        let c = refine_emitted(&r, &mask(), &b, &RefineConfig::default()).unwrap();
        assert_eq!(a.1.output_hash, c.1.output_hash);
        let mut bad = blob(0.0); bad.start = p(10.0, 0.0); if let Span::Cubic{control_one,..}=&mut bad.spans[0]{control_one.y=5.5}
        assert!(refine_emitted(&[bad], &mask(), &b, &RefineConfig::default()).is_err());
    }
}

#[cfg(test)]
mod flatten_tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn mask(scale: f64) -> SourceMask { SourceMask { w: 12, h: 12, ink: vec![255; 144], scale, origin: (0.0, 12.0 * scale) } }
    #[test]
    fn over_budget_input_is_refused_before_any_area_error() {
        // tiny scale makes the cubic span need > w*h chords; must be Err before area_error runs
        let r = ReferenceRing { start: p(0.0, 0.0), spans: vec![
            Span::Cubic { control_one: p(1000.0, 0.0), control_two: p(1000.0, 1000.0), end: p(1.0, 0.0) },
            Span::Line { end: p(0.0, 0.0) } ] };
        let b = NodeBudget { max_nodes: 2, max_nodes_per_ring: vec![] };
        let m = mask(1e-3);
        let e = refine_emitted(&[r.clone()], &m, &b, &RefineConfig::default()).unwrap_err();
        assert!(is_flatten_refused(&e), "{:?}", e);
        let e2 = refine_emitted_guided(&[r], &m, &b, &RefineConfig::default(), &[]).unwrap_err();
        assert!(is_flatten_refused(&e2), "{:?}", e2);
    }
    #[test]
    fn total_over_budget_with_each_ring_under_is_refused() {
        // each ring alone fits the budget (w*h=144 chords), the sum does not: guard must see ALL rings
        let ring = |dx: f64| ReferenceRing { start: p(dx, 0.0), spans: vec![
            Span::Cubic { control_one: p(dx + 40.0, 0.0), control_two: p(dx + 40.0, 40.0), end: p(dx + 1.0, 0.0) },
            Span::Line { end: p(dx, 0.0) } ] };
        let m = SourceMask { w: 12, h: 12, ink: vec![255; 144], scale: 1.0, origin: (0.0, 0.0) };
        let one = [ring(0.0)];
        assert!(flatten_guard(&one, &m).is_ok());
        let two = [ring(0.0), ring(2.0), ring(4.0)];
        assert!(is_flatten_refused(&flatten_guard(&two, &m).unwrap_err()), "sum must exceed");
        let b = NodeBudget { max_nodes: 6, max_nodes_per_ring: vec![] };
        assert!(is_flatten_refused(&refine_emitted(&two, &m, &b, &RefineConfig::default()).unwrap_err()));
    }
    #[test]
    fn in_budget_input_still_refines() {
        let r = ReferenceRing { start: p(2.0, -2.0), spans: vec![
            Span::Line { end: p(8.0, -2.0) }, Span::Line { end: p(8.0, -8.0) }, Span::Line { end: p(2.0, -8.0) }, Span::Line { end: p(2.0, -2.0) } ] };
        let b = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![] };
        let mut g = vec![255u8; 144]; for y in 2..8 { for x in 2..8 { g[y * 12 + x] = 0; } }
        let m = SourceMask { w: 12, h: 12, ink: g, scale: 1.0, origin: (0.0, 0.0) };
        assert!(refine_emitted(&[r], &m, &b, &RefineConfig::default()).is_ok());
    }
}

#[cfg(test)]
mod real_rings {
    use super::*;
    use crate::{capture::capture_gray, capture_fit::{fit_captured, round_and_clean_ring}, cubic_fit::FitPolicy};
    fn shapes() -> Vec<(usize, usize, Vec<u8>)> {
        let mut v = vec![];
        for (w, h, f) in [
            (40usize, 40usize, 0u8), (48, 36, 1), (48, 48, 2), (40, 40, 3),
        ] {
            let mut g = vec![255u8; w * h];
            for y in 0..h { for x in 0..w {
                let (fx, fy) = (x as f64 + 0.5, y as f64 + 0.5);
                let (cx, cy) = (w as f64 / 2.0, h as f64 / 2.0);
                let r = ((fx - cx).powi(2) + (fy - cy).powi(2)).sqrt();
                let ink = match f {
                    0 => r < 13.0,
                    1 => ((fx - cx) / 17.0).powi(2) + ((fy - cy) / 11.0).powi(2) < 1.0,
                    2 => r < 18.0 && r > 8.0,
                    _ => (fx > 8.0 && fx < 16.0 && fy > 6.0 && fy < 34.0) || (fy > 26.0 && fy < 34.0 && fx > 8.0 && fx < 32.0),
                };
                if ink { g[y * w + x] = 0; }
            }}
            v.push((w, h, g));
        }
        v
    }
    #[test]
    fn real_rings_single_pass_bounded_and_frame_guarded() {
        for (i, (w, h, g)) in shapes().into_iter().enumerate() {
            let c = capture_gray(w, h, &g, 0.25).unwrap();
            let p = FitPolicy { squared_error: 0.25, max_refits: 8 };
            let (mut fl, ..) = fit_captured(&c.rings, 1.0, &p);
            let dy = c.origin_y;
            for r in &mut fl { r.start.y += dy; for s in &mut r.spans { match s { Span::Line{end}=>end.y+=dy, Span::Cubic{control_one,control_two,end}=>{control_one.y+=dy;control_two.y+=dy;end.y+=dy;}}}}
            let base: Vec<_> = fl.iter().map(|r| round_and_clean_ring(r, 1.0)).collect();
            let mask = SourceMask { w, h, ink: g.clone(), scale: 1.0, origin: (-c.origin_x, 0.0) };
            let b = NodeBudget { max_nodes: count_nodes(&base), max_nodes_per_ring: base.iter().map(|r| r.spans.len()).collect() };
            let cfg = RefineConfig::default();
            let r1 = refine_emitted(&base, &mask, &b, &cfg);
            let (o1, rep1) = r1.unwrap();
            let r2 = refine_emitted(&o1, &mask, &b, &cfg);
            let (o2, rep2) = r2.unwrap();
            assert!(rep1.notes.starts_with("passes=1;") && !rep1.notes.contains("converged"), "{}", rep1.notes);
            // single pass: bounded against ITS input, area never worse; a re-run re-anchors (not idempotent by design)
            let d1 = base.iter().zip(&o1).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
            let d2 = o1.iter().zip(&o2).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
            assert!(d1 <= 1.0 && d2 <= 1.0, "shape {}: {} {}", i, d1, d2);
            assert!(rep1.area_after <= rep1.area_before && rep2.area_after <= rep1.area_after);
            assert_eq!(count_nodes(&o1), count_nodes(&base));
            assert!(missing_extrema(&o1) <= missing_extrema(&base));
            // frame guard: the same rings shifted far outside the mask frame are refused
            let far: Vec<_> = base.iter().map(|r| { let mut r = r.clone(); r.start.x += 1000.0; for s in &mut r.spans { match s { Span::Line{end}=>end.x+=1000.0, Span::Cubic{control_one,control_two,end}=>{control_one.x+=1000.0;control_two.x+=1000.0;end.x+=1000.0;}}} r }).collect();
            assert!(matches!(refine_emitted(&far, &mask, &b, &cfg), Err(LeverError::Violation(_))));
        }
    }
}

#[cfg(test)]
mod golden {
    use super::*;
    use crate::{capture::capture_gray, capture_fit::{fit_captured, round_and_clean_ring}, cubic_fit::FitPolicy};
    pub(super) fn fixtures() -> Vec<(String, Vec<ReferenceRing>, SourceMask)> {
        let mut out = vec![];
        for (idx, (w, h, f)) in [(40usize, 40usize, 0u8), (48, 36, 1), (48, 48, 2), (40, 40, 3)].into_iter().enumerate() {
            let mut g = vec![255u8; w * h];
            for y in 0..h { for x in 0..w {
                let (fx, fy) = (x as f64 + 0.5, y as f64 + 0.5);
                let (cx, cy) = (w as f64 / 2.0, h as f64 / 2.0);
                let r = ((fx - cx).powi(2) + (fy - cy).powi(2)).sqrt();
                let ink = match f {
                    0 => r < 13.0,
                    1 => ((fx - cx) / 17.0).powi(2) + ((fy - cy) / 11.0).powi(2) < 1.0,
                    2 => r < 18.0 && r > 8.0,
                    _ => (fx > 8.0 && fx < 16.0 && fy > 6.0 && fy < 34.0) || (fy > 26.0 && fy < 34.0 && fx > 8.0 && fx < 32.0),
                };
                if ink { g[y * w + x] = 0; }
            }}
            let c = capture_gray(w, h, &g, 0.25).unwrap();
            let p = FitPolicy { squared_error: 0.25, max_refits: 8 };
            let (mut fl, ..) = fit_captured(&c.rings, 1.0, &p);
            let dy = c.origin_y;
            for r in &mut fl { r.start.y += dy; for s in &mut r.spans { match s { Span::Line{end}=>end.y+=dy, Span::Cubic{control_one,control_two,end}=>{control_one.y+=dy;control_two.y+=dy;end.y+=dy;}}}}
            let base: Vec<_> = fl.iter().map(|r| round_and_clean_ring(r, 1.0)).collect();
            out.push((format!("real{}", idx), base, SourceMask { w, h, ink: g, scale: 1.0, origin: (-c.origin_x, 0.0) }));
        }
        out
    }
    /// Contract regression hashes (input, int_refine::try_apply, single-pass refine_emitted).
    const GOLDEN: [(&str, u64, u64, u64); 4] = [
        ("real0", 1136128311302899890, 10549801807758374651, 10549801807758374651),
        ("real1", 6526385164213313019, 16879577151104914058, 16879577151104914058),
        ("real2", 5056721174774437843, 2364212730760772652, 2364212730760772652),
        ("real3", 10448131117539542536, 10448131117539542536, 10448131117539542536),
    ];
    /// CANDIDATE_REGRESSION_CONSTANTS: the golden hashes in this module are regression constants for this
    /// implementation, not independently proven reference outputs.
    /// Outputs of the removed multi-round path, kept only as a comparison reference.
    const MULTIROUND_REFERENCE: [u64; 4] = [3713652985609007775, 3505294184860234482, 13265787520899080469, 10448131117539542536];
    #[test]
    fn no_protect_matches_regression_cases() {
        for ((name, base, mask), g) in fixtures().into_iter().zip(GOLDEN) {
            assert_eq!(name, g.0);
            let b = NodeBudget { max_nodes: count_nodes(&base), max_nodes_per_ring: base.iter().map(|r| r.spans.len()).collect() };
            assert_eq!(hash_rings(&base), g.1, "{} input", name);
            let a = crate::int_refine::try_apply(&base, &mask, &b).unwrap();
            assert_eq!(hash_rings(&a.0), g.2, "{} int_refine", name);
            let am = crate::int_refine::try_apply_masked(&base, &mask, &b, &[], None).unwrap();
            assert_eq!(hash_rings(&am.0), g.2, "{} int_refine masked-empty", name);
            let e = refine_emitted(&base, &mask, &b, &RefineConfig::default()).unwrap();
            assert_eq!(hash_rings(&e.0), g.3, "{} refine_emitted single-pass", name);
            assert!(e.1.notes.starts_with("passes=1;") && !e.1.notes.contains("rounds="), "{}", e.1.notes);
            // declared change vs the removed multi-round path, measured on the running code
            let pre_m = MULTIROUND_REFERENCE[GOLDEN.iter().position(|x| x.0 == name).unwrap()];
            // SUP-2 (staircase-aware rescue confirmation + truly-ambiguous
            // rescue trigger) moved real0/real1/real2 input geometry: the
            // low-res circle/ellipse/ring captures ARE pixel staircases, and
            // their chopped arcs now stay whole for the cubic fitter; real3
            // (straight-edged rectangle) is untouched, which is the fix's
            // own control. Values measured on the running code.
            // solver changes shifted real1/real2 input geometry: real1's refine output
            // legitimately differs from the historical multi-round reference, while
            // the dual-init r3r change moved real2's input so its single-pass refine
            // output coincides with that reference again. The PN-3 (a) rule
            // (in-bound ambiguous-lineage lines accepted event-free) restored
            // the original input geometry on all four fixtures. The G2 joint-repair
            // pass (harmonize + line-chain fold) then moved real2's input geometry,
            // so its single-pass refine output no longer coincides with the
            // multi-round reference; the declared-difference set is now
            // real0/real1/real2. Values above are measured on the running code.
            assert_eq!(hash_rings(&e.0) != pre_m, name != "real3", "{} declared difference", name);
            let em = refine_emitted_masked(&base, &mask, &b, &RefineConfig::default(), &[]).unwrap();
            assert_eq!(hash_rings(&em.0), g.3, "{} masked-empty", name);
            let eg = refine_emitted_guided(&base, &mask, &b, &RefineConfig::default(), &[]).unwrap();
            assert_eq!(hash_rings(&eg.0), g.3, "{} guided-empty", name);
        }
    }
}


#[cfg(test)]
mod masked_tests {
    use super::*;
    use super::golden::fixtures;
    use crate::int_refine::{mask_holds, RingMask, Slot};
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn blob_off(hx: f64) -> ReferenceRing {
        let k = 5.0;
        ReferenceRing { start: p(10.0, 0.0), spans: vec![
            Span::Cubic { control_one: p(hx, k), control_two: p(k, 10.0), end: p(0.0, 10.0) },
            Span::Cubic { control_one: p(-k, 10.0), control_two: p(-10.0, k), end: p(-10.0, 0.0) },
            Span::Cubic { control_one: p(-10.0, -k), control_two: p(-k, -10.0), end: p(0.0, -10.0) },
            Span::Cubic { control_one: p(k, -10.0), control_two: p(10.0, -k), end: p(10.0, 0.0) },
        ]}
    }
    // Line->Cubic, Cubic->Line, Cubic->Cubic transitions in one closed ring (D shape).
    fn dshape() -> ReferenceRing {
        ReferenceRing { start: p(-8.0, -8.0), spans: vec![
            Span::Line { end: p(-8.0, 8.0) },
            Span::Line { end: p(2.0, 8.0) },
            Span::Cubic { control_one: p(7.0, 8.0), control_two: p(9.0, 4.0), end: p(9.0, 0.0) },
            Span::Cubic { control_one: p(9.0, -4.0), control_two: p(7.0, -8.0), end: p(2.0, -8.0) },
            Span::Line { end: p(-8.0, -8.0) },
        ]}
    }
    fn mask() -> SourceMask {
        let (w, h) = (40usize, 40usize);
        let mut ink = vec![255u8; w * h];
        for j in 0..h { for i in 0..w {
            let (x, y) = (i as f64 + 0.5 - 20.0, 20.0 - (j as f64 + 0.5));
            if x * x + y * y <= 100.0 { ink[j * w + i] = 0; }
        }}
        SourceMask { w, h, ink, scale: 1.0, origin: (-20.0, 20.0) }
    }
    fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: r.iter().map(|x| x.spans.len()).collect() } }
    fn all_nodes(r: &[ReferenceRing], kind: Protect) -> Vec<ProtectedNode> {
        let mut v = vec![]; for (i, x) in r.iter().enumerate() { for k in 0..x.spans.len() { v.push(ProtectedNode { ring: i, node: k, kind }); } } v
    }
    fn holds_all(inp: &[ReferenceRing], out: &[ReferenceRing], prot: &[ProtectedNode]) {
        let masks = build_masks(inp, prot);
        for (i, (a, b)) in inp.iter().zip(out).enumerate() { assert!(mask_holds(a, b, &masks[i]), "ring {} mask", i); }
        for q in prot { assert!(protection_holds(&inp[q.ring], &out[q.ring], q)); }
        let disp = inp.iter().zip(out).map(|(a, b)| max_disp(a, b)).fold(0.0, f64::max);
        assert!(disp <= 1.0, "input-anchored bound: {}", disp);
    }

    #[test]
    fn all_masked_returns_input_exactly() {
        let mut cases: Vec<(Vec<ReferenceRing>, SourceMask)> = vec![(vec![blob_off(9.0)], mask()), (vec![dshape()], mask())];
        for (_, base, m) in fixtures() { cases.push((base, m)); }
        for (r, m) in cases {
            for kind in [Protect::Corner, Protect::Extremum { x_axis: true }, Protect::Extremum { x_axis: false }] {
                let prot = all_nodes(&r, kind);
                let (out, rep) = refine_emitted_masked(&r, &m, &budget(&r), &RefineConfig::default(), &prot).unwrap();
                assert_eq!(hash_rings(&out), hash_rings(&r), "{:?}", kind);
                assert!(rep.notes.starts_with("passes=1;convergence=not_evaluated;") && rep.notes.contains("protection_violations=0") && !rep.notes.contains("fell_back"), "{}", rep.notes);
            }
        }
    }
    #[test]
    fn pass_a_and_pass_b_counts_with_mask() {
        // handle (9,5) is 1 inside node (10,0): unprotected it is snapped by pass A
        let r = vec![blob_off(9.0)];
        let cfg = RefineConfig::default();
        let (out, rep) = refine_emitted_masked(&r, &mask(), &budget(&r), &cfg, &[ProtectedNode { ring: 0, node: 1, kind: Protect::Corner }]).unwrap();
        assert!(rep.notes.contains("snapped=1") && rep.notes.contains("passA_masked=0"), "{}", rep.notes);
        match &out[0].spans[0] { Span::Cubic { control_one, .. } => assert_eq!(control_one.x, 10.0), _ => panic!() }
        // protecting node 3 (owner of that outgoing handle) masks the snap: pass A count 0, masked reject 1
        let prot = [ProtectedNode { ring: 0, node: 3, kind: Protect::Corner }];
        let (out, rep) = refine_emitted_masked(&r, &mask(), &budget(&r), &cfg, &prot).unwrap();
        assert!(rep.notes.contains("snapped=0") && rep.notes.contains("passA_masked=1"), "{}", rep.notes);
        match &out[0].spans[0] { Span::Cubic { control_one, .. } => assert_eq!(control_one.x, 9.0), _ => panic!() }
        holds_all(&r, &out, &prot);
        // pass B: masked_skipped is reported and masks hold on real-path rings
        let (_, base, m) = fixtures().remove(0);
        let prot = vec![ProtectedNode { ring: 0, node: 0, kind: Protect::Corner }, ProtectedNode { ring: 0, node: 2, kind: Protect::Corner }];
        let (out, rep) = refine_emitted_masked(&base, &m, &budget(&base), &cfg, &prot).unwrap();
        assert!(rep.notes.contains("accepted_moves=") && rep.notes.contains("masked_skipped="), "{}", rep.notes);
        holds_all(&base, &out, &prot);
        assert!(rep.area_after <= rep.area_before);
    }
    #[test]
    fn nonprotected_moves_survive_and_counts_are_separate() {
        let (_, base, m) = fixtures().remove(0);
        let b = budget(&base);
        let cfg = RefineConfig::default();
        let free = refine_emitted(&base, &m, &b, &cfg).unwrap();
        assert_ne!(hash_rings(&free.0), hash_rings(&base), "fixture must move without protection");
        let prot = [ProtectedNode { ring: 0, node: 0, kind: Protect::Corner }];
        let (out, rep) = refine_emitted_masked(&base, &m, &b, &cfg, &prot).unwrap();
        assert_ne!(hash_rings(&out), hash_rings(&base), "non-protected moves must survive: {}", rep.notes);
        holds_all(&base, &out, &prot);
        assert!(rep.notes.contains("passA_masked=") && rep.notes.contains("passB_masked=") && rep.notes.contains("passA_displacement_rejected="), "{}", rep.notes);
        assert!(note_count(&rep.notes, "passB_masked=").unwrap() > 0, "{}", rep.notes);
    }
    #[test]
    fn pass_b_breach_helpers_and_topology_identity() {
        let r = vec![blob_off(9.0)];
        let mut far = r.clone();
        if let Span::Cubic { control_two, .. } = &mut far[0].spans[2] { control_two.x += 2.0; }
        assert!(!disp_ok(&r, &far, 1.0) && disp_ok(&r, &far, 2.0));
        let mut nan = r.clone();
        if let Span::Cubic { control_two, .. } = &mut nan[0].spans[2] { control_two.x = f64::NAN; }
        assert!(!disp_ok(&r, &nan, 1e9));
        assert_eq!(displacement_bound(&RefineConfig::default()), 1.0);
        assert_eq!(displacement_bound(&RefineConfig { max_snap: 3.0, ..Default::default() }), 3.0);
        assert_eq!(displacement_bound(&RefineConfig { max_snap: 0.0, ..Default::default() }), 0.0);
        assert_eq!(displacement_bound(&RefineConfig { max_snap: 0.25, ..Default::default() }), 0.25);
        // Cubic -> Line at the same index is a topology change
        let mut t = r.clone();
        let e = end_of(&t[0].spans[1]); t[0].spans[1] = Span::Line { end: e };
        assert!(topology_same(&r, &r) && !topology_same(&r, &t));
        let prot = [ProtectedNode { ring: 0, node: 3, kind: Protect::Corner }];
        assert!(post_check(&r, &t, &build_masks(&r, &prot), &prot, 1e9).is_err());
    }
    #[test]
    fn bound_is_cfg_max_snap_for_sub_grid_values() {
        let r = vec![blob_off(9.0)];
        let b = budget(&r);
        for ms in [0.25, 0.5, 0.0] {
            let cfg = RefineConfig { max_snap: ms, ..Default::default() };
            let (out, rep) = refine_emitted(&r, &mask(), &b, &cfg).unwrap();
            assert!(rep.max_node_displacement <= ms, "max_snap {}: {}", ms, rep.max_node_displacement);
            assert!(disp_ok(&r, &out, ms));
            assert_eq!(hash_rings(&out), hash_rings(&r), "no whole-grid move may survive below one grid step");
            assert!(rep.notes.contains("passB_status=displacement_breach_return_after_A"), "{}", rep.notes);
            let (mo, mrep) = refine_emitted_masked(&r, &mask(), &b, &cfg, &[ProtectedNode { ring: 0, node: 1, kind: Protect::Corner }]).unwrap();
            assert_eq!(hash_rings(&mo), hash_rings(&r));
            assert!(mrep.notes.contains(&format!("bound={}", ms)), "{}", mrep.notes);
        }
        // default (1 FU) still snaps and refines
        let (_, rep) = refine_emitted(&r, &mask(), &b, &RefineConfig::default()).unwrap();
        assert!(rep.area_after < rep.area_before && rep.max_node_displacement <= 1.0);
        // invalid cfg values are typed refusals; 0 is valid (it means: nothing may move)
        for bad in [f64::NAN, -0.5, f64::INFINITY, f64::NEG_INFINITY] {
            assert!(refine_emitted(&r, &mask(), &b, &RefineConfig { max_snap: bad, ..Default::default() }).is_err());
        }
    }
    #[test]
    fn wrap_node_owns_start() {
        let r = vec![blob_off(9.0)];
        let n = r[0].spans.len();
        for kind in [Protect::Corner, Protect::Extremum { x_axis: true }] {
            let prot = [ProtectedNode { ring: 0, node: n - 1, kind }];
            let (out, _) = refine_emitted_masked(&r, &mask(), &budget(&r), &RefineConfig::default(), &prot).unwrap();
            assert_eq!(out[0].start, r[0].start);
            assert_eq!(end_of(&out[0].spans[n - 1]), r[0].start);
            holds_all(&r, &out, &prot);
        }
        // frozen End on the last span also pins `start` in mask_holds
        let mut cand = r[0].clone(); cand.start.x += 1.0;
        let mut m = RingMask::default(); m.frozen.insert((n - 1, Slot::End));
        assert!(!mask_holds(&r[0], &cand, &m));
        // node 0 outgoing handle is C1 of span 1, incoming is C2 of span 0
        let prot = [ProtectedNode { ring: 0, node: 0, kind: Protect::Corner }];
        let (out, _) = refine_emitted_masked(&r, &mask(), &budget(&r), &RefineConfig::default(), &prot).unwrap();
        holds_all(&r, &out, &prot);
    }
    #[test]
    fn line_cubic_transitions() {
        let r = vec![dshape()];
        let m = mask();
        for node in 0..5 {
            for kind in [Protect::Corner, Protect::Extremum { x_axis: true }, Protect::Extremum { x_axis: false }] {
                let prot = [ProtectedNode { ring: 0, node, kind }];
                let (out, rep) = refine_emitted_masked(&r, &m, &budget(&r), &RefineConfig::default(), &prot).unwrap();
                assert_eq!(count_nodes(&out), count_nodes(&r));
                assert!(rep.area_after <= rep.area_before);
                holds_all(&r, &out, &prot);
                assert!(!rep.notes.contains("fell_back"), "node {} {:?}: {}", node, kind, rep.notes);
            }
        }
        // spans: L L C C L. Node j = end of spans[j]; IN handle = C2 of spans[j] (Cubic only), OUT handle = C1 of spans[j+1] (Cubic only).
        let fr = |node: usize| build_masks(&r, &[ProtectedNode { ring: 0, node, kind: Protect::Corner }]).remove(0).frozen;
        // node 1: Line -> Cubic: no IN handle, OUT = C1 of span 2
        let f = fr(1);
        assert!(f.contains(&(1, Slot::End)) && f.contains(&(2, Slot::C1)));
        assert!(matches!(r[0].spans[1], Span::Line { .. }) && matches!(r[0].spans[2], Span::Cubic { .. }));
        // node 2: Cubic -> Cubic: IN = C2 of span 2, OUT = C1 of span 3
        let f = fr(2);
        assert!(f.contains(&(2, Slot::End)) && f.contains(&(2, Slot::C2)) && f.contains(&(3, Slot::C1)));
        assert!(matches!(r[0].spans[2], Span::Cubic { .. }) && matches!(r[0].spans[3], Span::Cubic { .. }));
        // node 3: Cubic -> Line: IN = C2 of span 3, OUT none (span 4 is a Line)
        let f = fr(3);
        assert!(f.contains(&(3, Slot::End)) && f.contains(&(3, Slot::C2)));
        assert!(matches!(r[0].spans[3], Span::Cubic { .. }) && matches!(r[0].spans[4], Span::Line { .. }));
        // node 4: Line -> Line, wraps to span 0 (Line); end(spans[4]) aliases ring.start
        let f = fr(4);
        assert!(f.contains(&(4, Slot::End)) && f.contains(&(0, Slot::C1)));
        assert!(matches!(r[0].spans[4], Span::Line { .. }) && matches!(r[0].spans[0], Span::Line { .. }));
        assert_eq!(end_of(&r[0].spans[4]), r[0].start);
        // handle slots on Line spans resolve to nothing, so freezing them is a no-op, never a synthetic cubic
        assert!(crate::int_refine::mask_holds(&r[0], &r[0], &RingMask { frozen: f, ..Default::default() }));
    }
    #[test]
    fn x_and_y_extremum_conservative_mask_and_neighbour_node_axis_lock() {
        let r = vec![blob_off(9.0)];
        // node 3 = (10,0) is an x extremum; node 0 = (0,10) is a y extremum
        for (node, x_axis) in [(3usize, true), (0usize, false)] {
            let prot = [ProtectedNode { ring: 0, node, kind: Protect::Extremum { x_axis } }];
            let masks = build_masks(&r, &prot);
            for nb in [(node + 3) % 4, (node + 1) % 4, node] { assert!(masks[0].axis_lock.contains(&(nb, x_axis))); }
            let (out, _) = refine_emitted_masked(&r, &mask(), &budget(&r), &RefineConfig::default(), &prot).unwrap();
            holds_all(&r, &out, &prot);
            let get = |q: Point| if x_axis { q.x } else { q.y };
            for nb in [(node + 3) % 4, node, (node + 1) % 4] {
                assert_eq!(get(end_of(&out[0].spans[nb])), get(end_of(&r[0].spans[nb])));
            }
        }
        // real-path rings: protect every detected extremum node
        for (_, base, m) in fixtures() {
            let mut prot = vec![];
            for (ri, ring) in base.iter().enumerate() {
                let nd: Vec<Point> = ring.spans.iter().map(end_of).collect();
                let n = nd.len();
                for j in 0..n {
                    let (a, b, c) = (nd[(j + n - 1) % n], nd[j], nd[(j + 1) % n]);
                    if is_ext(b.x, a.x, c.x) { prot.push(ProtectedNode { ring: ri, node: j, kind: Protect::Extremum { x_axis: true } }); }
                    if is_ext(b.y, a.y, c.y) { prot.push(ProtectedNode { ring: ri, node: j, kind: Protect::Extremum { x_axis: false } }); }
                }
            }
            let (out, rep) = refine_emitted_masked(&base, &m, &budget(&base), &RefineConfig::default(), &prot).unwrap();
            holds_all(&base, &out, &prot);
            assert!(rep.area_after <= rep.area_before);
            assert!(missing_extrema(&out) <= missing_extrema(&base));
        }
    }
    #[test]
    fn empty_and_invalid_identity_typed_err_before_anything_else() {
        let r = vec![blob_off(9.0)];
        let b = budget(&r);
        let cfg = RefineConfig::default();
        let bad = [
            ProtectedNode { ring: 0, node: 4, kind: Protect::Corner },
            ProtectedNode { ring: 1, node: 0, kind: Protect::Corner },
            ProtectedNode { ring: usize::MAX, node: 0, kind: Protect::Corner },
            ProtectedNode { ring: 0, node: usize::MAX, kind: Protect::Extremum { x_axis: true } },
        ];
        for q in bad {
            let e = refine_emitted_masked(&r, &mask(), &b, &cfg, &[q]).unwrap_err();
            assert!(is_invalid_protected_identity(&e), "{:?}", e);
            assert!(is_invalid_protected_identity(&refine_emitted_guided(&r, &mask(), &b, &cfg, &[q]).unwrap_err()));
            // identity wins over every later check: an invalid SourceMask and a bad cfg do not mask the error
            let badmask = SourceMask { w: 0, h: 0, ink: vec![], scale: 1.0, origin: (0.0, 0.0) };
            let badcfg = RefineConfig { max_snap: f64::NAN, ..Default::default() };
            assert!(is_invalid_protected_identity(&refine_emitted_masked(&r, &badmask, &b, &badcfg, &[q]).unwrap_err()));
        }
        // empty ring list: any identity is invalid; no identity is fine
        let none: Vec<ReferenceRing> = vec![];
        let e = refine_emitted_masked(&none, &mask(), &NodeBudget { max_nodes: 0, max_nodes_per_ring: vec![] }, &cfg, &[ProtectedNode { ring: 0, node: 0, kind: Protect::Corner }]).unwrap_err();
        assert!(is_invalid_protected_identity(&e));
        // a ring with no spans cannot be protected at any node
        let hollow = vec![ReferenceRing { start: p(0.0, 0.0), spans: vec![] }];
        let e = refine_emitted_masked(&hollow, &mask(), &NodeBudget { max_nodes: 0, max_nodes_per_ring: vec![] }, &cfg, &[ProtectedNode { ring: 0, node: 0, kind: Protect::Corner }]).unwrap_err();
        assert!(is_invalid_protected_identity(&e));
        // int_refine level: misaligned masks / anchor are typed errors too
        let e = crate::int_refine::try_apply_masked(&r, &mask(), &b, &[RingMask::default(), RingMask::default()], None).unwrap_err();
        assert!(matches!(e, LeverError::Violation(_)));
        let mut oob = RingMask::default(); oob.frozen.insert((9, Slot::End));
        assert!(matches!(crate::int_refine::try_apply_masked(&r, &mask(), &b, &[oob], None), Err(LeverError::Violation(_))));
    }
    #[test]
    fn receipt_branches_and_final_status() {
        let r = vec![blob_off(9.0)];
        let b = budget(&r);
        let prot0: [ProtectedNode; 0] = [];
        // pass B disabled
        let cfg = RefineConfig { run_int_refine: false, ..Default::default() };
        let (_, rep) = refine_emitted(&r, &mask(), &b, &cfg).unwrap();
        assert!(rep.notes.contains("passA_masked=0;passA_status=completed;passB_status=disabled;passB_masked=NOT_RUN;final_status=accepted"), "{}", rep.notes);
        // accepted, actual count (0 is an actual count)
        let (_, rep) = refine_emitted_masked(&r, &mask(), &b, &RefineConfig::default(), &prot0).unwrap();
        assert!(rep.notes.contains("passB_status=accepted;passB_masked=0;") && rep.notes.ends_with("final_status=accepted"), "{}", rep.notes);
        // masked accepted keeps both counts
        let prot = [ProtectedNode { ring: 0, node: 3, kind: Protect::Corner }];
        let (_, rep) = refine_emitted_masked(&r, &mask(), &b, &RefineConfig::default(), &prot).unwrap();
        assert!(rep.notes.contains("passA_masked=1") && rep.notes.contains("passB_status=accepted") && rep.notes.ends_with("final_status=accepted"), "{}", rep.notes);
        // displacement breach (max_snap < 1): after-A candidate returned, actual count printed
        let cfg = RefineConfig { max_snap: 0.5, ..Default::default() };
        let (_, rep) = refine_emitted(&r, &mask(), &b, &cfg).unwrap();
        assert!(rep.notes.contains("passB_status=displacement_breach_return_after_A;passB_masked=0;"), "{}", rep.notes);
        // invalid / error / unparsable count, direct
        assert_eq!(passb_note(PassB::Invalid, Some(2)), ";passB_status=invalid_return_after_A;passB_masked=2");
        assert_eq!(passb_note(PassB::Invalid, None), ";passB_status=invalid_return_after_A;passB_masked=UNAVAILABLE");
        assert_eq!(passb_note(PassB::Failed, Some(5)), ";passB_status=error_return_after_A;passB_masked=UNAVAILABLE");
        assert_eq!(passb_note(PassB::Breach, None), ";passB_status=displacement_breach_return_after_A;passB_masked=UNAVAILABLE");
        assert_eq!(note_count("a=1;masked_skipped=x", "masked_skipped="), None);
        assert_eq!(note_count("a=1", "masked_skipped="), None);
        // fallback retains the pass notes and marks the final status
        let mut rep0 = LeverReport { lever: "x", lever_id: "x", api_version: 3, stage_tag: "x", input_hash: hash_rings(&r), output_hash: 7, seed: 0,
            nodes_before: 4, nodes_after: 4, area_before: 3.0, area_after: 2.0, c2_missing: 0, max_node_displacement: 1.0, notes: String::new() };
        rep0.notes = format!("snapped=1;passA_masked=1;passA_status=completed{}", passb_note(PassB::Accepted, Some(3)));
        let (_, rep) = fallback_to_input(&r, rep0, 1, 1, 1.0);
        assert!(rep.notes.contains("passA_masked=1;passA_status=completed;passB_status=accepted;passB_masked=3") && rep.notes.contains(";final_status=input_fallback;"), "{}", rep.notes);
    }
    #[test]
    fn neighbour_handle_change_allowed_neighbour_node_axis_locked() {
        let r = vec![blob_off(9.0)];
        let prot = [ProtectedNode { ring: 0, node: 3, kind: Protect::Extremum { x_axis: true } }];
        let masks = build_masks(&r, &prot);
        // adversarial: a neighbouring handle (span 1 C1, owned by node 0) changes on the protected axis
        let mut nb = r.clone();
        if let Span::Cubic { control_one, .. } = &mut nb[0].spans[1] { control_one.x += 1.0; }
        assert!(crate::int_refine::mask_holds(&r[0], &nb[0], &masks[0]));
        assert_eq!(post_check(&r, &nb, &masks, &prot, 1.0), Ok(()));
        // neighbour NODE coordinate on the protected axis (node 2 and node 0, x axis) is rejected
        for nbk in [2usize, 0usize] {
            let mut nn = r.clone();
            if let Span::Cubic { end, .. } = &mut nn[0].spans[nbk] { end.x += 1.0; }
            assert!(!crate::int_refine::mask_holds(&r[0], &nn[0], &masks[0]), "neighbour node {}", nbk);
        }
        // protected central node's own required handles stay rejected
        for which in 0..2 {
            let mut bad = r.clone();
            if which == 0 { if let Span::Cubic { control_two, .. } = &mut bad[0].spans[3] { control_two.y += 1.0; } }
            else if let Span::Cubic { control_one, .. } = &mut bad[0].spans[0] { control_one.y += 1.0; }
            assert!(!crate::int_refine::mask_holds(&r[0], &bad[0], &masks[0]));
            assert!(post_check(&r, &bad, &masks, &prot, 1.0).is_err());
        }
    }
    #[test]
    fn fallback_post_check_direct_coverage() {
        let r = vec![blob_off(9.0)];
        let prot = [ProtectedNode { ring: 0, node: 3, kind: Protect::Corner }, ProtectedNode { ring: 0, node: 0, kind: Protect::Extremum { x_axis: false } }];
        let masks = build_masks(&r, &prot);
        assert_eq!(post_check(&r, &r, &masks, &prot, 1.0), Ok(()));
        // a protected node moved by one unit
        let mut moved = r.clone();
        if let Span::Cubic { end, .. } = &mut moved[0].spans[3] { end.y += 1.0; }
        moved[0].start.y += 1.0;
        assert!(post_check(&r, &moved, &masks, &prot, 1.0).is_err());
        // a protected handle moved
        let mut moved = r.clone();
        if let Span::Cubic { control_one, .. } = &mut moved[0].spans[0] { control_one.x += 1.0; }
        assert!(post_check(&r, &moved, &masks, &prot, 1.0).unwrap_err() >= 1);
        // extremum neighbour node coordinate moved on the protected axis: rejected
        let mut moved = r.clone();
        if let Span::Cubic { end, .. } = &mut moved[0].spans[1] { end.y += 1.0; }
        assert!(post_check(&r, &moved, &masks, &prot, 1.0).is_err());
        // protected node's own extremum coordinate moved: rejected
        let mut moved2 = r.clone();
        if let Span::Cubic { end, .. } = &mut moved2[0].spans[0] { end.y += 1.0; }
        assert!(post_check(&r, &moved2, &masks, &prot, 1.0).is_err());
        // unprotected point moved beyond the input-anchored bound only
        let mut far = r.clone();
        if let Span::Cubic { control_two, .. } = &mut far[0].spans[2] { control_two.x += 2.0; }
        assert_eq!(post_check(&r, &far, &masks, &prot, 1.0), Err(1));
        assert_eq!(post_check(&r, &far, &masks, &prot, 2.0), Ok(()));
        // wrong ring count
        assert!(post_check(&r, &[], &masks, &prot, 1.0).is_err());
        // the fallback returns the exact input and the explicit refusal receipt
        let rep = LeverReport { lever: "x", lever_id: "x", api_version: 3, stage_tag: "x", input_hash: hash_rings(&r), output_hash: 7, seed: 0,
            nodes_before: 4, nodes_after: 4, area_before: 3.0, area_after: 2.0, c2_missing: 0, max_node_displacement: 1.0, notes: String::new() };
        let (out, rep) = fallback_to_input(&r, rep, prot.len(), 2, 1.0);
        assert_eq!(hash_rings(&out), hash_rings(&r));
        assert_eq!(rep.output_hash, rep.input_hash);
        assert_eq!(rep.area_after, rep.area_before);
        assert!(rep.notes.contains(CANDIDATE_REFUSED_NOTE) && rep.notes.contains("protection_violations=2") && rep.notes.contains("fell_back_to_input"));
    }
    #[test]
    fn int_refine_masked_entry_honours_anchor_and_masks() {
        let (_, base, m) = fixtures().remove(0);
        let b = budget(&base);
        // frozen everything: no move can be accepted
        let mut masks = vec![];
        for r in &base { let mut mk = RingMask::default(); for k in 0..r.spans.len() { mk.frozen.insert((k, Slot::End)); mk.frozen.insert((k, Slot::C1)); mk.frozen.insert((k, Slot::C2)); } masks.push(mk); }
        let (out, rep) = crate::int_refine::try_apply_masked(&base, &m, &b, &masks, None).unwrap();
        assert_eq!(hash_rings(&out), hash_rings(&base));
        assert!(rep.notes.contains("accepted_moves=0"));
        // entry violation against an anchor is typed
        let mut shifted = base.clone(); shifted[0].start.x += 1.0;
        if let Some(Span::Cubic { end, .. } | Span::Line { end }) = shifted[0].spans.last_mut() { end.x += 1.0; }
        assert!(matches!(crate::int_refine::try_apply_masked(&shifted, &m, &b, &masks, Some(&base)), Err(LeverError::Violation(_))));
    }
}

#[cfg(test)]
mod single_pass_cases {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn disc_mask() -> SourceMask {
        let (w, h) = (40usize, 40usize);
        let mut ink = vec![255u8; w * h];
        for j in 0..h { for i in 0..w {
            let (x, y) = (i as f64 + 0.5 - 20.0, 20.0 - (j as f64 + 0.5));
            if x * x + y * y <= 100.0 { ink[j * w + i] = 0; }
        }}
        SourceMask { w, h, ink, scale: 1.0, origin: (-20.0, 20.0) }
    }
    fn half_mask() -> SourceMask {
        let mut m = disc_mask();
        for j in 0..40 { for i in 0..40 { if (i as f64 + 0.5 - 20.0) < 0.0 { m.ink[j * 40 + i] = 255; } } }
        m
    }
    /// EMPTY_SOURCE_MASK: same frame as disc_mask, ink never present (every pixel 255).
    fn blank_mask() -> SourceMask { let mut m = disc_mask(); for v in m.ink.iter_mut() { *v = 255; } m }
    /// Parse "M(x,y) L(x,y) C(a,b c,d e,f)".
    fn parse_ring(t: &str) -> ReferenceRing {
        let mut start = None; let mut spans = vec![];
        let mut rest = t.trim();
        while !rest.is_empty() {
            let kind = rest.chars().next().unwrap();
            let close = rest.find(')').unwrap();
            let nums: Vec<f64> = rest[2..close].split(|c| c == ',' || c == ' ').filter(|x| !x.is_empty()).map(|x| x.parse().unwrap()).collect();
            match kind {
                'M' => start = Some(p(nums[0], nums[1])),
                'L' => spans.push(Span::Line { end: p(nums[0], nums[1]) }),
                'C' => spans.push(Span::Cubic { control_one: p(nums[0], nums[1]), control_two: p(nums[2], nums[3]), end: p(nums[4], nums[5]) }),
                _ => panic!("bad token {}", kind),
            }
            rest = rest[close + 1..].trim_start();
        }
        ReferenceRing { start: start.unwrap(), spans }
    }
    /// (case, cfg, mask, max_nodes, input ring, input hash, multi-round-path hash, single-pass hash, guided hash).
    /// Empty-protect output must equal the single-pass hash. Where the multi-round hash differs the change is
    /// declared and the output must not equal it.
    const CASES: [(&str, &str, &str, usize, &str, &str, &str, &str, &str); 26] = [
        ("blob_off(9)", "default", "disc", 4, "M(10,0) C(9,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "87a534c69138f472", "a78a7d9f1f3ee264", "a78a7d9f1f3ee264", "a78a7d9f1f3ee264"),
        ("blob_off(9)", "no_int_refine", "disc", 4, "M(10,0) C(9,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "87a534c69138f472", "01f7366003072964", "01f7366003072964", "01f7366003072964"),
        ("blob_off(11)", "default", "disc", 4, "M(10,0) C(11,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "f3b64e90c5103716", "ad80ff19ed96463a", "ad80ff19ed96463a", ""),
        ("blob_off(11)", "no_int_refine", "disc", 4, "M(10,0) C(11,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "f3b64e90c5103716", "f3b64e90c5103716", "f3b64e90c5103716", ""),
        ("blob_off(10)", "default", "disc", 4, "M(10,0) C(10,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "01f7366003072964", "a78a7d9f1f3ee264", "a78a7d9f1f3ee264", ""),
        ("blob_off(10)", "no_int_refine", "disc", 4, "M(10,0) C(10,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "01f7366003072964", "01f7366003072964", "01f7366003072964", ""),
        ("blob_off(12)", "default", "disc", 4, "M(10,0) C(12,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "2a907b3999bc4308", "a20fa07a6a6891ff", "a20fa07a6a6891ff", ""),
        ("blob_off(12)", "no_int_refine", "disc", 4, "M(10,0) C(12,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "2a907b3999bc4308", "2a907b3999bc4308", "2a907b3999bc4308", ""),
        ("conv_dshape(in=9,out=11)", "default", "half", 3, "M(0,10) L(0,-10) C(6,-10 9,-6 10,0) C(11,6 6,10 0,10)", "c5efb727f9abb3c2", "80d9821864264146", "80d9821864264146", ""),
        ("conv_dshape(in=9,out=11)", "no_int_refine", "half", 3, "M(0,10) L(0,-10) C(6,-10 9,-6 10,0) C(11,6 6,10 0,10)", "c5efb727f9abb3c2", "fa940e527a4b68c6", "fa940e527a4b68c6", ""),
        ("conv_dshape(in=11,out=9)", "default", "half", 3, "M(0,10) L(0,-10) C(6,-10 11,-6 10,0) C(9,6 6,10 0,10)", "e8c0280e66d39dc2", "80d9821864264146", "80d9821864264146", ""),
        ("conv_dshape(in=11,out=9)", "no_int_refine", "half", 3, "M(0,10) L(0,-10) C(6,-10 11,-6 10,0) C(9,6 6,10 0,10)", "e8c0280e66d39dc2", "fa940e527a4b68c6", "fa940e527a4b68c6", ""),
        ("conv_dshape(in=10,out=10)", "default", "half", 3, "M(0,10) L(0,-10) C(6,-10 10,-6 10,0) C(10,6 6,10 0,10)", "fa940e527a4b68c6", "80d9821864264146", "80d9821864264146", ""),
        ("conv_dshape(in=10,out=10)", "no_int_refine", "half", 3, "M(0,10) L(0,-10) C(6,-10 10,-6 10,0) C(10,6 6,10 0,10)", "fa940e527a4b68c6", "fa940e527a4b68c6", "fa940e527a4b68c6", ""),
        ("conv_dshape(in=9,out=9)", "default", "half", 3, "M(0,10) L(0,-10) C(6,-10 9,-6 10,0) C(9,6 6,10 0,10)", "15a5c5ff1b1be9e6", "80d9821864264146", "80d9821864264146", ""),
        ("conv_dshape(in=9,out=9)", "no_int_refine", "half", 3, "M(0,10) L(0,-10) C(6,-10 9,-6 10,0) C(9,6 6,10 0,10)", "15a5c5ff1b1be9e6", "fa940e527a4b68c6", "fa940e527a4b68c6", ""),
        ("DISTINGUISH multi([-3.0, -3.0, 0.0, 0.0, 3.0, 0.0, -3.0, -3.0])", "default", "disc", 4, "M(10,0) C(7,2 5,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-5 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "1fb7dbf71cd1f81a", "de956b67dd2b5d40", "b867f64df21c0ba9", "de956b67dd2b5d40"),
        ("DISTINGUISH multi([-3.0, -3.0, 0.0, 0.0, 3.0, 0.0, -3.0, -3.0])", "no_int_refine", "disc", 4, "M(10,0) C(7,2 5,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-5 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "1fb7dbf71cd1f81a", "1fb7dbf71cd1f81a", "1fb7dbf71cd1f81a", "1fb7dbf71cd1f81a"),
        ("DISTINGUISH multi([-3.0, -3.0, 1.0, 0.0, 3.0, 1.0, -3.0, -3.0])", "default", "disc", 4, "M(10,0) C(7,2 6,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-4 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "58b166e2669e19d2", "53c50ab51414c2e6", "4d486c3a15081891", "53c50ab51414c2e6"),
        ("DISTINGUISH multi([-3.0, -3.0, 1.0, 0.0, 3.0, 1.0, -3.0, -3.0])", "no_int_refine", "disc", 4, "M(10,0) C(7,2 6,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-4 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "58b166e2669e19d2", "58b166e2669e19d2", "58b166e2669e19d2", "58b166e2669e19d2"),
        ("DISTINGUISH multi([-3.0, -3.0, -2.0, 0.0, 3.0, -2.0, -3.0, -3.0])", "default", "disc", 4, "M(10,0) C(7,2 3,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-7 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "b0c63b499e8bc72e", "7f34f583b2aa300c", "613e369dc002b431", "7f34f583b2aa300c"),
        ("DISTINGUISH multi([-3.0, -3.0, -2.0, 0.0, 3.0, -2.0, -3.0, -3.0])", "no_int_refine", "disc", 4, "M(10,0) C(7,2 3,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-7 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "b0c63b499e8bc72e", "b0c63b499e8bc72e", "b0c63b499e8bc72e", "b0c63b499e8bc72e"),
        ("EMPTY_SOURCE_MASK blob_off(9)", "default", "blank", 4, "M(10,0) C(9,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "87a534c69138f472", "d85b9fed180574e8", "32fd425cc9d8f085", ""),
        ("EMPTY_SOURCE_MASK blob_off(9)", "no_int_refine", "blank", 4, "M(10,0) C(9,5 5,10 0,10) C(-5,10 -10,5 -10,0) C(-10,-5 -5,-10 0,-10) C(5,-10 10,-5 10,0)", "87a534c69138f472", "87a534c69138f472", "87a534c69138f472", ""),
        ("EMPTY_SOURCE_MASK multi", "default", "blank", 4, "M(10,0) C(7,2 5,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-5 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "1fb7dbf71cd1f81a", "4fe76bbe6492751a", "a1444594cb57f6b8", ""),
        ("EMPTY_SOURCE_MASK multi", "no_int_refine", "blank", 4, "M(10,0) C(7,2 5,10 0,10) C(-5,10 -10,5 -10,0) C(-7,-5 -8,-13 0,-10) C(5,-10 10,-5 10,0)", "1fb7dbf71cd1f81a", "1fb7dbf71cd1f81a", "1fb7dbf71cd1f81a", "")
    ];
    fn mask_of(kind: &str) -> SourceMask { match kind { "blank" => blank_mask(), "half" => half_mask(), _ => disc_mask() } }
    fn hx(r: &[ReferenceRing]) -> String { format!("{:016x}", hash_rings(r)) }
    #[test]
    fn empty_protect_matches_single_pass_hashes_and_declared_differences() {
        let (mut checked, mut declared_diff, mut distinguish_diff, mut empty_mask_diff) = (0, 0, 0, 0);
        for (case, cfgname, kind, nb, ring, in_hash, a_hash, b_hash, g_hash) in CASES {
            let cfg = if cfgname == "default" { RefineConfig::default() } else { RefineConfig { run_int_refine: false, ..Default::default() } };
            let r = vec![parse_ring(ring)];
            assert_eq!(hx(&r), in_hash, "{} input", case);
            let mask = mask_of(kind);
            let b = NodeBudget { max_nodes: nb, max_nodes_per_ring: vec![] };
            let pub_out = refine_emitted(&r, &mask, &b, &cfg).unwrap();
            let masked = refine_emitted_masked(&r, &mask, &b, &cfg, &[]).unwrap();
            let guided = refine_emitted_guided(&r, &mask, &b, &cfg, &[]).unwrap();
            assert_eq!(hx(&pub_out.0), b_hash, "{} {} single-pass hash", case, cfgname);
            assert_eq!(hash_rings(&pub_out.0), hash_rings(&masked.0), "{} {} masked-empty", case, cfgname);
            assert_eq!(hash_rings(&pub_out.0), hash_rings(&guided.0), "{} {} guided-empty", case, cfgname);
            assert!(pub_out.1.notes.starts_with("passes=1;convergence=not_evaluated;"));
            // displacement against the call input, across both passes
            assert!(pub_out.1.max_node_displacement <= 1.0, "{} disp {}", case, pub_out.1.max_node_displacement);
            if a_hash != b_hash {
                declared_diff += 1;
                assert_ne!(hx(&pub_out.0), a_hash, "{} {}: declared difference to the multi-round path", case, cfgname);
                if case.starts_with("DISTINGUISH") { distinguish_diff += 1; }
                if case.starts_with("multi") || kind == "blank" { empty_mask_diff += 1; }
            }
            if !g_hash.is_empty() { assert_eq!(g_hash, a_hash, "{}: guided hash column", case); }
            checked += 1;
        }
        assert_eq!(checked, 26);
        // 5 of 26 pairs differ: 3 multi-handle cases + 2 blank-mask cases
        assert_eq!(declared_diff, 5);
        assert_eq!(distinguish_diff, 3);
        assert_eq!(empty_mask_diff, 2);
    }
}
