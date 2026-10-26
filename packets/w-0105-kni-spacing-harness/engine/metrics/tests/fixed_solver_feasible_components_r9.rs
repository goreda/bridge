//! tests/fixed_solver_feasible_components_r9.rs
//! SOURCE ONLY - NOT RUN, no run authority; no integration, RED, or PASS claims.
//! Oracle-correctness guards for the fixed solver around feasible components.
//! Every assertion is a property of the RETURNED solution checked against
//! canonical guard evidence - never an assert about any historical bug.
//!
//! BINDING: self_anchored_spacing.rs sha256 401347ff21106682f7a1c064597a0ed0ada5db6a3e88a50489fe6bf633a77c7d
//! (tree a6704fbf5f82fcc3d36fb150a3a1b2d86adf99cd7554ecf1101e8da1ee0c5b1a),
//! with signed_clearance.rs 585267dc... . The frozen 16b48b9f/444c8ca4 gate
//! is the separate r5 file, untouched.
//! AMENDED for the Lane D optical-centre LSB/RSB split (source sha256
//! 139ef8954e63c634a6f2556a3e90f286a74c6462e2231ae81d5d1ff89a74c51b):
//! the wired fixtures' L carries vertically non-uniform ink, so the split
//! changes its sidebearings (wired 5/5 -> 4/6, rowgap rsb 2.5 -> 5.714...);
//! keyed measured targets were raised (wired 25/30 -> 30/30, rowgap 25 ->
//! 30) to keep real residuals above the epsilon, and the expected values in
//! the touched tests were re-derived and verified by instrumented dump.
//!
//! Scope:
//! (i) [WIRED] solve_spacing of 401347ff: the pair path IS solve_pair_t_l2
//!     (the frozen cells+t shift is retired in this source). Returned
//!     placements must be non-colliding under canonical evidence in the
//!     EXPORT frame (l_tr, r_tr, origin_distance), and receipted values must
//!     agree with actual evidence: wall_gap is the guard-verified min_gap,
//!     optical_cost is the capped-gap variance V of cells recomputed at the
//!     ACTUAL raw placement, recomposed in the source's exact f64 expression
//!     order (raw_base + residual, residual = origin - advance_l). Both
//!     agreements are
//!     construction-pins in this source (they held as discriminating oracles
//!     against the retired shift); they are kept as regression pins.
//! (ii) [CONSTRAINT] signed_clearance: forbidden residual intervals, feasible
//!     components, membership, scoped guard agreement at non-reversed edges.
//! (iii) [L2-UNIT] direct solve_pair_t_l2 calls: component-respecting argmin,
//!     edge/touch legality, typed holds (NoFeasible vs NoAcceptedCandidate vs
//!     NotConverged), export-frame origin binding.
//!
//! Frames (from source): evidence_at(l, r, l_tr, r_tr, origin) places left
//! ink at x + l_tr and right ink at x + r_tr + origin;
//! clearance_cells_constant(l, r, o) uses raw offset o. The frames are
//! related by o = origin + r_tr - l_tr MATHEMATICALLY, but f64 addition
//! order is load-bearing: every raw-frame oracle here recomposes the
//! placement in the source's exact expression order (raw_base + residual
//! with residual = origin - advance_l), never as origin + r_tr - l_tr.
//! In solve_pair_t_l2, Solved.origin is the bit-exact verified export-frame
//! origin and residual = origin - advance by construction. In the [L2-UNIT]
//! fixtures the frames are unified by choosing base_offset = advance and
//! l_tr = r_tr = 0, so origin = base + residual.
//!
//! Fixture geometry:
//! - 20-unit counterexample: L ink [0,10],[30,40], R ink [0,5], base 15.
//!   Forbidden open residuals (-20,-5),(10,25); feasible components over
//!   [-30,30]: [-30,-20] (WHOLLY REVERSED: constraint-feasible, NOT
//!   guard-feasible, contributes no solve candidates), [-5,10], [25,30].
//!   Residual 20 sits inside (10,25): forbidden.
//! - Wired-trio fixture (r9): counterexample geometry plus class-breaking
//!   outer-wall variation on extra rows (L rows 0-2: [0,10],[30,40]; rows
//!   3-5: [10,20],[30,50]; R: [0,5] x4) so both measured directions get
//!   non-(Straight,Straight) class keys and the anchor w_s = 20 (one
//!   sidebearing entry) decouples from the keyed targets. Keyed targets
//!   30/30 (raised from 25/30 under the Lane D optical-centre split: L's
//!   ink is vertically non-uniform, so its sidebearings are now 4/6, not
//!   5/5, and the old 25 target lands L->R inside the residual epsilon -
//!   a counter-only below_epsilon absence this file's gate rejects).
//!   Mirrored variant for the counter-reversed test.
//! - Row-gap V fixture: rows with walls 10 and 25 (gaps d-10, d-25).
//! - Cap/flip V fixture: rows with ink [0,10],[30,40] plus rows with ink
//!   [0,10], cap 25: facing membership flips at placement 30 and clamping
//!   makes V placement-dependent (V(40) = 156.25, V(45) = 100.0).
//!
//! ASSUMPTIONS (unrun):
//! A1: ctx.measured_pairs gap is the pair's class-keyed solve target
//!     (class_target falls back to the anchor w_s for unmeasured class
//!     keys, 1344-1348); with lambda = None (= 0.0, distribution term off,
//!     per SpacingPolicy doc) the pair objective is J(t) = (W(t) -
//!     target)^2 with a KNOWN target. Wired ctx shapes (r9, reasons inline
//!     at the helpers): the wired trio measures both directions (25/30)
//!     under NON-(Straight,Straight) class keys plus one sidebearing entry
//!     (anchor w_s = 20 via the fallback, 1267-1271) - for a
//!     (Straight,Straight) key the class target IS the group median
//!     (1247-1261) = w_s and W(base) = w_s identically, so residual 0 is
//!     unavoidable there; rowgap/capflip keep one sidebearing entry
//!     (w_s = 20) because their varying outer wall classifies Arm (537)
//!     and would otherwise hit the typed InvalidContext refusal
//!     (1273-1275).
//! A2 (fixture-equivalence claim ONLY): W at a placement is the canonical
//!     constant-cell weighted mean gap; V at a placement is the capped
//!     weighted variance of those constant cells, recomputed with the same
//!     clamped-integral semantics as channel_stats/cell_integrals (constant
//!     cells: c0 == c1).
//! A3: 4 identical rows satisfy pair_min_shared_rows (default 3) so the pair
//!     is solved, not excluded_unmeasurable.
//! A4: policy.dcap is set EXPLICITLY in every wired test so the cap in the V
//!     oracle is a known input, not the internal plateau default.
//! A5 (GATE): an attempted ordered pair is either EMITTED or receipted PER
//!     PAIR. hold_reasons carries exact "left->right: <Variant>" entries and
//!     excluded_pairs carries exact (left, right) entries; the tests assert
//!     one of the two for the EXACT fixture direction, never a global
//!     counter. Absence through the counter-only paths
//!     (excluded_unmeasurable / excluded_below_epsilon /
//!     numeric_failed_pairs) carries no per-pair receipt and FAILS this gate
//!     by design: it surfaces as a red run for fixture/base review, never a
//!     silent pass. Expected values derive from source math only and must
//!     NOT be changed on the basis of any future red result; a red run
//!     triggers fixture/base review, not value edits.

use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    solve_pair_t_l2, solve_spacing, FontContext, MeasuredPair, MeasuredSidebearing, PairSolve,
    SpacingPolicy, SpacingSolution,
};
use kni_metrics::signed_clearance::{
    self, evidence_at, feasible_components, forbidden_residual_intervals, is_forbidden,
};

const EPS: f64 = 1e-9;

fn profile(id: &str, ink: &[(f64, f64)], rows: usize) -> OutlineProfile {
    let mk = |y: f64| ScanRow {
        y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(),
    };
    // Actual ink bounds: mirrored fixtures have xmin < 0; an empty-ink
    // profile degenerates to zero bounds, never a guessed xmin.
    let xmin = ink.iter().map(|&(l, _)| l).fold(f64::INFINITY, f64::min);
    let xmax = ink.iter().map(|&(_, r)| r).fold(f64::NEG_INFINITY, f64::max);
    let (x0, x1) = if xmin <= xmax { (xmin, xmax) } else { (0.0, 0.0) };
    OutlineProfile {
        glyph_id: id.to_string(), source_pin: format!("pin-{id}"), upm: 1000,
        origin: [0.0, 0.0], rows: (0..rows).map(|i| mk(i as f64)).collect(),
        bounds: [x0, 0.0, x1, rows as f64],
        ink_area: rows as f64 * ink.iter().map(|&(l, r)| r - l).sum::<f64>(),
        counter_area: 0.0, open_left: 0.0, open_right: 0.0,
        profile_method: "fixed-solver-feasible-components-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// The 20-unit counterexample pair: L ink [0,10],[30,40], R ink [0,5],
/// measured (target) gap 25. Base placement 15 has cell gap 5.
fn counterexample() -> (OutlineProfile, OutlineProfile, f64) {
    (profile("L", &[(0.0, 10.0), (30.0, 40.0)], 4),
     profile("R", &[(0.0, 5.0)], 4),
     25.0)
}

/// Wired-trio fixture (r9): the counterexample geometry plus CLASS-BREAKING
/// outer-wall variation on extra rows. Rows 0-2 carry the original ink
/// [0,10],[30,40]; rows 3-5 carry [10,20],[30,50], so BOTH outer walls of L
/// vary across the band [0,5] (wall series [10,10,10,0,0,0] and
/// [0,0,0,10,10,10], s = 10: not Arm (jump 10 !> 10), not Straight (range
/// 10 > 5), not Diagonal (same_sign+1 = 1 < 3), not Round (jump 10 > 5) ->
/// Open; classify_side 518-548). Reason: for (Straight,Straight) measured
/// pairs the class target IS w_s and W(base) = w_s identically, so
/// residual 0 is unavoidable - only a class-key split decouples the
/// measured targets (25/30) from the anchor (w_s = 20). Fresh oracle
/// (source math only): W(base) = 20 both directions; L->R: W(t) = 20 + t,
/// argmin t = 5, domain [-15,35], d = 70, wall 20, V = 25; R->L: argmin
/// t = 10, domain [-15,35], d = 30, wall 25. Both |residual| > eps 2.0.
fn wired_pair_fixture() -> (OutlineProfile, OutlineProfile) {
    let mk_rows = |ink: &[(f64, f64)], ys: &[f64]| ys.iter().map(|&y| ScanRow {
        y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(),
    }).collect::<Vec<_>>();
    let ink_a = [(0.0, 10.0), (30.0, 40.0)];
    let ink_b = [(10.0, 20.0), (30.0, 50.0)];
    let mut rows = mk_rows(&ink_a, &[0.0, 1.0, 2.0]);
    rows.extend(mk_rows(&ink_b, &[3.0, 4.0, 5.0]));
    let l = OutlineProfile {
        glyph_id: "L".into(), source_pin: "pin-L-wired".into(), upm: 1000,
        origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 50.0, 6.0],
        ink_area: 3.0 * 20.0 + 3.0 * 30.0, counter_area: 0.0,
        open_left: 0.0, open_right: 0.0,
        profile_method: "wired-pair-fixture".into(), row_step: 1.0,
        flatten_tolerance: 0.0,
    };
    (l, profile("R", &[(0.0, 5.0)], 4))
}

/// Mirrored wired-trio fixture for the counter-reversed test: exact x -> -x
/// mirror of wired_pair_fixture (class keys mirror to the same Open/
/// Straight split; side-channel means mirror identically).
fn wired_pair_fixture_mirrored() -> (OutlineProfile, OutlineProfile) {
    let mk_rows = |ink: &[(f64, f64)], ys: &[f64]| ys.iter().map(|&y| ScanRow {
        y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(),
    }).collect::<Vec<_>>();
    let ink_a = [(-40.0, -30.0), (-10.0, 0.0)];
    let ink_b = [(-50.0, -30.0), (-20.0, -10.0)];
    let mut rows = mk_rows(&ink_a, &[0.0, 1.0, 2.0]);
    rows.extend(mk_rows(&ink_b, &[3.0, 4.0, 5.0]));
    let l = OutlineProfile {
        glyph_id: "L".into(), source_pin: "pin-L-wired-mir".into(), upm: 1000,
        origin: [0.0, 0.0], rows, bounds: [-50.0, 0.0, 0.0, 6.0],
        ink_area: 3.0 * 20.0 + 3.0 * 30.0, counter_area: 0.0,
        open_left: 0.0, open_right: 0.0,
        profile_method: "wired-pair-fixture-mirrored".into(), row_step: 1.0,
        flatten_tolerance: 0.0,
    };
    (l, profile("R", &[(-5.0, 0.0)], 4))
}

/// Wired-trio ctx (r9): both directions measured (fwd/rev) PLUS one
/// sidebearing entry carrying the anchor. Reason (r9): measured pairs
/// group by CLASS KEY and collapse to the group median (1247-1261); with
/// the wired-trio fixture both directions have NON-(Straight,Straight)
/// keys, so no (S,S) group exists, w_s comes from the sidebearing median
/// fallback (1267-1271) = sb_sum, and the keyed targets stay fwd/rev
/// (1344-1348). w_s must differ from both targets: the equal-area rule
/// (1354-1376) makes the mean base gap identically w_s for any geometry
/// (the side-channel means cancel), so a target equal to w_s forces
/// residual 0 and the epsilon gate (1513, eps = 2.0) drops the pair.
fn ctx_with_pair_reverse_anchor(fwd: f64, rev: f64, sb_sum: f64) -> FontContext {
    FontContext {
        x_height: None, cap_height: None, baseline: None,
        measured_sidebearings: vec![MeasuredSidebearing {
            glyph_id: "L".into(), lsb: sb_sum / 2.0, rsb: sb_sum / 2.0 }],
        measured_pairs: vec![
            MeasuredPair { left: "L".into(), right: "R".into(), gap: fwd },
            MeasuredPair { left: "R".into(), right: "L".into(), gap: rev }],
        measured_space_advance: None, glyph_codepoints: vec![],
    }
}

/// Rowgap/capflip wired ctx: measured pair PLUS one sidebearing entry.
/// Reason (r8, log class 1): these fixtures vary L's OUTER right wall
/// across rows (the V discrimination needs a varying gap), so
/// classify_side (518-548) reads Arm, the measured pair groups under
/// (Arm, Straight) not (Straight, Straight), w_s stays None
/// (1249-1261), and with empty measured_sidebearings the typed refusal
/// InvalidContext fires (1273-1275). One sidebearing entry makes the
/// median fallback derivable (1267-1271): w_s = lsb + rsb = 20, chosen
/// != pair target 30 so the L->R residual is nonzero (rowgap under the
/// Lane D optical-centre split: rsb_L = 10 - 300/70 = 5.714..., residual
/// +6.785..., d = 47.5, V = 56.25; the pre-Lane-D 25 target lands the
/// pair inside the residual epsilon; capflip: argmin at the domain edge
/// t = 20, d = 65). The R->L direction is not consumed by these tests; under
/// this ctx it solves toward w_s and may drop below_epsilon, which is
/// the source's designed counter-only behavior for an unconsumed pair.
fn ctx_with_sidebearing_anchor(target: f64, sb_sum: f64) -> FontContext {
    FontContext {
        x_height: None, cap_height: None, baseline: None,
        measured_sidebearings: vec![MeasuredSidebearing {
            glyph_id: "L".into(), lsb: sb_sum / 2.0, rsb: sb_sum / 2.0 }],
        measured_pairs: vec![MeasuredPair {
            left: "L".into(), right: "R".into(), gap: target }],
        measured_space_advance: None, glyph_codepoints: vec![],
    }
}

/// Export-frame translation of one glyph in a returned solution:
/// GlyphFrame::new composes lsb - ink_xmin.
fn tr(sol: &SpacingSolution, prof: &OutlineProfile, glyph_id: &str) -> f64 {
    let g = sol.glyphs.iter().find(|g| g.glyph_id == glyph_id)
        .expect("glyph in solution");
    g.lsb - prof.bounds[0]
}

/// Oracle guard applied to every returned pair placement, in the EXPORT
/// frame: the RETURNED solution must be non-colliding under the canonical
/// guard, and its receipted wall_gap must agree with the actual evidence at
/// that placement. In 401347ff wall_gap IS the guard-verified min_gap, so
/// this is a construction-pin kept as a regression pin.
fn guard_returned_pair(sol: &SpacingSolution, l: &OutlineProfile, r: &OutlineProfile,
                       left_id: &str, right_id: &str, origin_distance: f64, wall_gap: f64) {
    let l_tr = tr(sol, l, left_id);
    let r_tr = tr(sol, r, right_id);
    let ev = evidence_at(l, r, l_tr, r_tr, origin_distance)
        .expect("finite evidence at returned placement");
    assert!(!ev.collides(),
        "returned origin {origin_distance} collides under canonical guard: \
         min_gap {} interval_hit {}", ev.clearance.min_gap, ev.interval_hit);
    assert!((ev.clearance.min_gap - wall_gap).abs() < EPS,
        "receipted wall_gap {wall_gap} != actual min_gap {} at returned origin",
        ev.clearance.min_gap);
}

/// Direction-aware profile binding: an emitted ordered pair is guarded with
/// the profiles in the pair's OWN role order - ("L","R") gets (l, r), the
/// reversed ordered pair ("R","L") gets (r, l). Pairing R->L metrics with
/// the forward geometry would guard the wrong instance.
fn direction_profiles<'a>(l: &'a OutlineProfile, r: &'a OutlineProfile,
                          left: &str, right: &str)
                          -> (&'a OutlineProfile, &'a OutlineProfile) {
    if left == l.glyph_id && right == r.glyph_id { return (l, r); }
    assert!(left == r.glyph_id && right == l.glyph_id,
        "unexpected ordered pair {left}->{right} in solution");
    (r, l)
}

/// Exact per-pair absence gate (A5): an attempted ordered pair that is not
/// emitted must be receipted PER PAIR - an exact "left->right:" entry in
/// hold_reasons or an exact (left, right) entry in excluded_pairs. Global
/// counters alone never satisfy this gate: excluded_unmeasurable,
/// excluded_below_epsilon and numeric_failed_pairs carry no per-pair
/// receipt, so absence through those paths fails here by design and
/// surfaces as a red run for fixture/base review.
fn assert_pair_absence_is_ledgered(sol: &SpacingSolution, left: &str, right: &str) {
    let prefix = format!("{left}->{right}:");
    let held = sol.hold_reasons.iter().any(|h| h.starts_with(&prefix));
    let excluded = sol.excluded_pairs.iter()
        .any(|e| e.left == left && e.right == right);
    assert!(held || excluded,
        "ordered pair {left}->{right} absent from pairs with NO per-pair ledger entry \
         (hold_reasons {:?}; excluded_pairs {:?}; counter-only paths - geometric_hold {} \
         no_accepted {} unmeasurable {} below_epsilon {} numeric_failed {} - do not \
         satisfy this gate)",
        sol.hold_reasons, sol.excluded_pairs, sol.geometric_hold_pairs,
        sol.no_accepted_candidate_pairs, sol.excluded_unmeasurable,
        sol.excluded_below_epsilon, sol.numeric_failed_pairs);
}

/// Raw placement recomposed in the source's EXACT f64 expression order:
/// base_offset = rsb_l + lsb_r, raw_base = (l.bounds[2] - r.bounds[0]) +
/// base_offset, placement = raw_base + (origin - advance_l). The
/// algebraically equal origin + r_tr - l_tr is a DIFFERENT f64 expression
/// and is never used for this construction pin.
fn actual_raw_placement(sol: &SpacingSolution, l: &OutlineProfile, r: &OutlineProfile,
                        left_id: &str, right_id: &str, origin: f64) -> f64 {
    let gl = sol.glyphs.iter().find(|g| g.glyph_id == left_id)
        .expect("left glyph in solution");
    let gr = sol.glyphs.iter().find(|g| g.glyph_id == right_id)
        .expect("right glyph in solution");
    let raw_base = (l.bounds[2] - r.bounds[0]) + (gl.rsb + gr.lsb);
    raw_base + (origin - gl.advance)
}

/// Capped variance of the canonical constant cells at a RAW placement offset
/// o (recomposed by actual_raw_placement in the source's exact f64 order),
/// same clamped-integral semantics as
/// channel_stats/cell_integrals for constant cells (c0 == c1):
/// W = sum(l*c)/sum(l), V = sum(l*c^2)/sum(l) - W^2, c = min(cell_gap, cap).
/// None when no cells (unmeasurable placement).
fn actual_capped_variance(l: &OutlineProfile, r: &OutlineProfile,
                          o: f64, cap: f64) -> Option<f64> {
    let cells = signed_clearance::clearance_cells_constant(l, r, o);
    if cells.is_empty() { return None; }
    let (mut len, mut s1, mut s2) = (0.0, 0.0, 0.0);
    for &(l0, c0, c1) in &cells {
        assert!((c0 - c1).abs() < EPS,
            "canonical model is piecewise-CONSTANT; got a sloped cell ({c0},{c1})");
        let c = c0.min(cap);
        len += l0; s1 += l0 * c; s2 += l0 * c * c;
    }
    if !(len > 0.0) { return None; }
    let w = s1 / len;
    Some((s2 / len - w * w).max(0.0))
}

/// [WIRED] 20-unit counterexample returned-solution guard (non-colliding).
/// Whatever placement the solver returns for either ordered direction of the
/// counterexample pair, the canonical guard at that export-frame origin must
/// show no collision - with the profiles in the pair's OWN role order (the
/// R->L direction swaps geometry, it does not reuse the forward pair).
/// Fresh r9 derivation (source math only, wired_pair_fixture): w_s = 20,
/// keyed targets 30/30; lsb_L = 4, rsb_L = 6 (Lane D optical-centre
/// weighted: rows 0-2 carry ink width 20, rows 3-5 width 30), lsb_R =
/// rsb_R = 10; residuals +6.5 / +13.5 (|r| > eps 2.0), raw placements
/// 66.5 / 38.5, wall gaps 22.5 / 27.5. The r8 slack/median plan was
/// falsified by the class-key median aggregation (1247-1261) and the
/// W(base) = w_s identity: distinct measured gaps in one class key
/// collapse, and straight-wall slack cancels in the equal-area rule.
/// Purpose preserved: every returned placement guarded non-colliding under
/// canonical evidence in the pair's own role order.
#[test]
fn wired_counterexample_returned_solution_is_non_colliding() {
    let (l, r) = wired_pair_fixture();
    let ctx = ctx_with_pair_reverse_anchor(30.0, 30.0, 20.0);
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let sol = solve_spacing(&[l.clone(), r.clone()], Some(&ctx), &policy)
        .expect("counterexample pair solves");
    let mut seen: Vec<(String, String)> = Vec::new();
    for p in &sol.pairs {
        let (pl, pr) = direction_profiles(&l, &r, &p.left, &p.right);
        guard_returned_pair(&sol, pl, pr, &p.left, &p.right, p.origin_distance, p.wall_gap);
        seen.push((p.left.clone(), p.right.clone()));
    }
    for (a, b) in [("L", "R"), ("R", "L")] {
        if !seen.iter().any(|s| s.0 == a && s.1 == b) {
            assert_pair_absence_is_ledgered(&sol, a, b);
        }
    }
}

/// [WIRED] optical_cost agreement: optical_cost IS the capped-gap variance V
/// of cells recomputed at the ACTUAL raw placement, recomposed in the
/// source's exact f64 expression order (raw_base + residual, residual =
/// origin - advance_l). Construction-pin in this source, kept as a
/// regression pin. r9: the wired-trio fixture now carries TWO distinct row
/// gaps at the returned placement (30 and 20 at d = 70), so V = 25 > 0 and
/// the agreement assert discriminates a zero/stale channel, not 0 == 0.
/// Purpose preserved: receipted optical_cost vs actual capped variance.
#[test]
fn wired_optical_cost_agrees_with_actual_variance() {
    let (l, r) = wired_pair_fixture();
    let ctx = ctx_with_pair_reverse_anchor(30.0, 30.0, 20.0);
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let sol = solve_spacing(&[l.clone(), r.clone()], Some(&ctx), &policy)
        .expect("counterexample pair solves");
    let Some(p) = sol.pairs.iter().find(|p| p.left == "L" && p.right == "R")
        else { assert_pair_absence_is_ledgered(&sol, "L", "R"); return; };
    let d = actual_raw_placement(&sol, &l, &r, "L", "R", p.origin_distance);
    let v_actual = actual_capped_variance(&l, &r, d, 50.0)
        .expect("canonical cells exist at returned raw placement");
    assert!((p.optical_cost - v_actual).abs() < EPS,
        "receipted optical_cost (V) {} != actual capped variance {v_actual} at raw placement",
        p.optical_cost);
}

/// Row-gap V fixture: L rows with DIFFERENT wall positions (rows 0-1: ink
/// [0,10]; rows 2-3: ink [0,25]) so the aligned spans carry two different
/// constant gaps (d-10 and d-25) and V > 0 - with identical rows V would be
/// 0 at every placement and could not discriminate a wrong optical_cost
/// channel. Note: with facing membership fixed, V is shift-invariant; this
/// fixture rules out V0 blindness, not placement staleness (that is the cap
/// fixture's job).
fn rowgap_fixture() -> (OutlineProfile, OutlineProfile) {
    let mk_rows = |ink: &[(f64, f64)], ys: &[f64]| ys.iter().map(|&y| ScanRow {
        y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(),
    }).collect::<Vec<_>>();
    let ink_a = [(0.0, 10.0)]; let ink_b = [(0.0, 25.0)];
    let mut rows = mk_rows(&ink_a, &[0.0, 1.0]);
    rows.extend(mk_rows(&ink_b, &[2.0, 3.0]));
    let l = OutlineProfile {
        glyph_id: "L".into(), source_pin: "pin-L-rowgap".into(), upm: 1000,
        origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 25.0, 4.0],
        ink_area: 2.0 * 10.0 + 2.0 * 25.0, counter_area: 0.0,
        open_left: 0.0, open_right: 0.0,
        profile_method: "v-rowgap-fixture".into(), row_step: 1.0, flatten_tolerance: 0.0,
    };
    (l, profile("R", &[(0.0, 5.0)], 4))
}

/// [WIRED] Row-gap fixture: the returned pair's optical_cost agrees with the
/// ACTUAL capped variance at the returned raw placement. Fresh r8 derivation:
/// w_s = 20, raw_base = 37.5, W(t) = 20 + t, base min clearance -12.5 ->
/// domain [12.5, 62.5] (1487-1490), argmin of (t - 5)^2 clamped to the
/// edge t = 12.5, d = 50 in the constant-V region (V = 56.25 > 0).
/// Fixture value pinned
/// at the known-legal raw placement d = 40 (gaps 30 and 15, V = 56.25
/// exactly). The V > 0 property is CONDITIONAL: for guard-legal d >= 25 it
/// holds on [25,75) - constant V = 56.25 on [25,60]; on (60,75) one row gap
/// clamps at cap 50 while the other is d-25, giving V = (75-d)^2/4 > 0; at
/// d >= 75 both row gaps clamp at 50 and V collapses to 0.
#[test]
fn wired_rowgap_v_not_v0_and_agrees() {
    let (l, r) = rowgap_fixture();
    let v40 = actual_capped_variance(&l, &r, 40.0, 50.0).expect("cells at 40");
    assert!((v40 - 56.25).abs() < EPS, "fixture pin V(40) = 56.25, got {v40}");
    let ctx = ctx_with_sidebearing_anchor(30.0, 20.0);
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let sol = solve_spacing(&[l.clone(), r.clone()], Some(&ctx), &policy)
        .expect("rowgap pair solves");
    let Some(p) = sol.pairs.iter().find(|p| p.left == "L" && p.right == "R")
        else { assert_pair_absence_is_ledgered(&sol, "L", "R"); return; };
    guard_returned_pair(&sol, &l, &r, "L", "R", p.origin_distance, p.wall_gap);
    let d = actual_raw_placement(&sol, &l, &r, "L", "R", p.origin_distance);
    let v_actual = actual_capped_variance(&l, &r, d, 50.0)
        .expect("canonical cells exist at returned raw placement");
    assert!(v_actual > 0.0,
        "V>0 holds only for returned raw placement in 25<=d<75; got d {d} V {v_actual}");
    assert!((p.optical_cost - v_actual).abs() < EPS,
        "receipted optical_cost (V) {} != actual V {v_actual}", p.optical_cost);
}

/// Cap/membership-flip V fixture: rows 0-1 carry ink [0,10],[30,40] (facing
/// membership FLIPS at raw placement 30), rows 2-3 carry [0,10] with a gap
/// that CLAMPS at the dcap 25 cap on legal placements in [40,45]. V is
/// placement-dependent here (V(40) = 156.25, V(45) = 100.0 under cap 25),
/// so a stale shifted-base V is discriminated from actual V.
fn capflip_fixture() -> (OutlineProfile, OutlineProfile) {
    let mk_rows = |ink: &[(f64, f64)], ys: &[f64]| ys.iter().map(|&y| ScanRow {
        y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(),
    }).collect::<Vec<_>>();
    let ink_a = [(0.0, 10.0), (30.0, 40.0)]; let ink_b = [(0.0, 10.0)];
    let mut rows = mk_rows(&ink_a, &[0.0, 1.0]);
    rows.extend(mk_rows(&ink_b, &[2.0, 3.0]));
    let l = OutlineProfile {
        glyph_id: "L".into(), source_pin: "pin-L-capflip".into(), upm: 1000,
        origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 40.0, 4.0],
        ink_area: 2.0 * 20.0 + 2.0 * 10.0, counter_area: 0.0,
        open_left: 0.0, open_right: 0.0,
        profile_method: "v-capflip-fixture".into(), row_step: 1.0, flatten_tolerance: 0.0,
    };
    (l, profile("R", &[(0.0, 5.0)], 4))
}

/// [WIRED] Cap/flip fixture: agreement with ACTUAL capped variance, plus
/// fixture-level discrimination proofs (canonical cells only, no solver
/// internals): V_actual differs across the legal domain, and facing
/// membership at raw placement 45 is NOT the shifted membership of 20.
/// GATE (A5): the returned solution is NOT forced into the stale-sensitive
/// region [40,45]; the discrimination asserts below are fixture-level (raw
/// canonical cells at fixed placements) and stand regardless of where the
/// solver lands. Fresh r8 derivation: w_s = 20, rsb_L = -5 (kept, never
/// clamped, 1379-1382), raw_base = 45, capped W <= 25 with W = 25 first at
/// the domain edge t = 20 -> d = 65 (V = 0 there; the optical_cost
/// agreement assert still discriminates a stale shifted V, which would be
/// V(20) != 0). Where it lands beyond this derivation is an emit receipt
/// question that only a run can answer - this file is NO RUN.
#[test]
fn wired_capflip_v_discriminates_and_agrees() {
    let (l, r) = capflip_fixture();
    let v40 = actual_capped_variance(&l, &r, 40.0, 25.0).expect("cells at 40");
    let v45 = actual_capped_variance(&l, &r, 45.0, 25.0).expect("cells at 45");
    assert!((v40 - 156.25).abs() < EPS && (v45 - 100.0).abs() < EPS,
        "cap-clamped V must be placement-dependent: V(40) {v40}, V(45) {v45}");
    let cells20 = signed_clearance::clearance_cells_constant(&l, &r, 20.0);
    let cells45 = signed_clearance::clearance_cells_constant(&l, &r, 45.0);
    let shifted: Vec<f64> = cells20.iter().map(|c| c.1 + 25.0).collect();
    let actual: Vec<f64> = cells45.iter().map(|c| c.1).collect();
    assert!(shifted.len() != actual.len()
        || shifted.iter().zip(&actual).any(|(a, b)| (a - b).abs() > 1.0),
        "facing membership must flip between 20 and 45 (stale-shift witness)");
    let ctx = ctx_with_sidebearing_anchor(25.0, 20.0);
    let policy = SpacingPolicy { dcap: Some(25.0), ..Default::default() };
    let sol = solve_spacing(&[l.clone(), r.clone()], Some(&ctx), &policy)
        .expect("capflip pair solves");
    let Some(p) = sol.pairs.iter().find(|p| p.left == "L" && p.right == "R")
        else { assert_pair_absence_is_ledgered(&sol, "L", "R"); return; };
    guard_returned_pair(&sol, &l, &r, "L", "R", p.origin_distance, p.wall_gap);
    let d = actual_raw_placement(&sol, &l, &r, "L", "R", p.origin_distance);
    let v_actual = actual_capped_variance(&l, &r, d, 25.0)
        .expect("canonical cells exist at returned raw placement");
    assert!((p.optical_cost - v_actual).abs() < EPS,
        "receipted optical_cost (V) {} != actual V {v_actual}", p.optical_cost);
}

/// [WIRED] Counter-reversed: mirrored ink, counters reversed (r9: mirrored
/// wired-trio fixture). The returned solution must satisfy the SAME
/// oracle guard; forbidden intervals derived from the reversed geometry must
/// match guard membership point-by-point, including the reversed edges.
/// Canonical cells measure the right ink's behind-gap, so the reversed
/// instance is NOT a numeric mirror of the forward case: feasibility, guard
/// agreement and wall_gap agreement only, no exact value claimed.
#[test]
fn wired_counter_reversed_returned_solution_agrees_with_guard() {
    let (l, r) = wired_pair_fixture_mirrored();
    let ctx = ctx_with_pair_reverse_anchor(25.0, 30.0, 20.0);
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let sol = solve_spacing(&[l.clone(), r.clone()], Some(&ctx), &policy)
        .expect("reversed instance solves");
    let mut seen: Vec<(String, String)> = Vec::new();
    for p in &sol.pairs {
        let (pl, pr) = direction_profiles(&l, &r, &p.left, &p.right);
        guard_returned_pair(&sol, pl, pr, &p.left, &p.right, p.origin_distance, p.wall_gap);
        seen.push((p.left.clone(), p.right.clone()));
    }
    for (a, b) in [("L", "R"), ("R", "L")] {
        if !seen.iter().any(|s| s.0 == a && s.1 == b) {
            assert_pair_absence_is_ledgered(&sol, a, b);
        }
    }
    // Fresh r9 oracle replacing the old pinned literals (the mirrored
    // geometry changed, so the old [(-25,-10),(5,20)] pins no longer
    // apply): collision intervals mirror EXACTLY under x -> -x with base
    // 15 -> -15 - confirmed by the original counterexample pins, where the
    // forward set (-20,-5),(10,25) mirrors to (-25,-10),(5,20). Assert the
    // relational symmetry against the forward fixture instead of
    // hand-derived literals for the new geometry.
    let (fl, fr) = wired_pair_fixture();
    let ivf = forbidden_residual_intervals(&fl, &fr, 15.0).expect("forward intervals");
    let iv = forbidden_residual_intervals(&l, &r, -15.0).expect("intervals");
    let mut mirrored: Vec<(f64, f64)> =
        ivf.iter().map(|&(a, b)| (-b, -a)).collect();
    mirrored.sort_by(|x, y| x.partial_cmp(y).unwrap());
    assert_eq!(iv, mirrored,
        "mirrored intervals must be the exact mirror of the forward fixture");
    let mut ts: Vec<f64> = (-70..=50).map(|k| k as f64).collect();
    for &(a, b) in &iv { ts.extend([a, b]); }
    for t in ts {
        let forbidden = is_forbidden(t, &iv);
        let hit = signed_clearance::interval_collision(&l, &r, 0.0, 0.0, -15.0 + t);
        assert_eq!(forbidden, hit, "reversed membership mismatch at t={t}");
    }
}

/// [CONSTRAINT] Disconnected feasible components: the counterexample's
/// forbidden set (-20,-5) union (10,25) splits the domain into three disjoint
/// closed components. A returned residual is feasible ONLY inside one
/// component. Constraint-only; not wiring proof.
#[test]
fn constraint_disconnected_components_are_the_only_legal_returns() {
    let (l, r, _) = counterexample();
    let base = 15.0;
    let iv = forbidden_residual_intervals(&l, &r, base).expect("intervals");
    assert_eq!(iv, vec![(-20.0, -5.0), (10.0, 25.0)]);
    let comp = feasible_components(-30.0, 30.0, &iv).expect("components");
    assert_eq!(comp, vec![(-30.0, -20.0), (-5.0, 10.0), (25.0, 30.0)],
        "three DISCONNECTED feasible components");
    // Component (-30,-20) is WHOLLY REVERSED (R placed entirely left of L):
    // constraint-feasible (strict-overlap membership only) but NOT
    // guard-feasible - the canonical guard's wholly-reversed fallback
    // measures a negative gap there. A returned solution must be re-verified
    // with evidence_at; membership alone is not legality.
    {
        let ev = evidence_at(&l, &r, 0.0, 0.0, base - 25.0).expect("evidence at reversed placement");
        assert!(ev.collides(), "reversed placement must read as a guard collision");
    }
    // Every candidate a solver may return from a NON-REVERSED component is
    // legal, and the gap between components is entirely forbidden.
    for &(a, b) in &comp[1..] {
        assert!(!is_forbidden(a, &iv) && !is_forbidden(b, &iv),
            "component edge ({a},{b}) must be legal touching");
        let mid = a + (b - a) / 2.0;
        assert!(!is_forbidden(mid, &iv), "component interior {mid} forbidden");
    }
    for &(a, b) in &iv {
        let mid = a + (b - a) / 2.0;
        assert!(is_forbidden(mid, &iv));
        assert!(!comp.iter().any(|&(x, y)| mid >= x && mid <= y),
            "forbidden {mid} inside a feasible component");
    }
    // Guard agreement, SCOPED (no universal "every forbidden edge is
    // guard-legal" claim): the NON-REVERSED edges -5, 10, 25 are legal
    // touching under strict-overlap interval semantics. The -20 edge is a
    // reversed-boundary: membership-legal here, but its guard reading goes
    // through the wholly-reversed fallback (asserted above), so no
    // guard-legality claim is made for it.
    for &t in &[-5.0, 10.0, 25.0] {
        let hit = signed_clearance::interval_collision(&l, &r, 0.0, 0.0, base + t);
        assert!(!hit, "non-reversed edge residual {t} must be legal touching, guard disagrees");
    }
}

/// [CONSTRAINT] Singleton touch: two feasible components meeting at exactly
/// one point keep that point as a legal zero-length component; a returned
/// solution at the touch residual is legal touching, verified by actual
/// guard evidence. Constraint-only; not wiring proof.
#[test]
fn constraint_singleton_touch_point_is_a_legal_return() {
    let iv = vec![(0.0, 1.0), (1.0, 2.0)];
    let comp = feasible_components(0.0, 2.0, &iv).expect("components");
    assert_eq!(comp, vec![(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)]);
    assert!(!is_forbidden(1.0, &iv), "touch point must be feasible");
    let (l, r, _) = counterexample();
    let ev = evidence_at(&l, &r, 0.0, 0.0, 15.0 - 5.0).expect("evidence at touch");
    assert!(!ev.collides(), "touch at the singleton edge must be legal");
    assert!((ev.clearance.min_gap - 0.0).abs() < EPS,
        "touch edge min_gap should be 0, got {}", ev.clearance.min_gap);
}

/// [CONSTRAINT] Constraint edges are legal oracle candidates (a
/// constraint-EDGE test, NOT a cap-breakpoint fixture; the real
/// cap-breakpoint fixture is l2_optimum_at_cap_breakpoint_is_returned).
/// Forbidden-interval edges are legal touching candidates under actual guard
/// evidence, and strictly-interior points are not. Constraint-only; not
/// wiring proof.
#[test]
fn constraint_edges_are_legal_oracle_candidates() {
    let (l, r, _) = counterexample();
    let base = 15.0;
    let iv = forbidden_residual_intervals(&l, &r, base).expect("intervals");
    // The breakpoint residuals are the forbidden-interval edges: every edge is
    // a legal (non-forbidden) candidate, strictly-interior points are not.
    for &(a, b) in &iv {
        assert!(!is_forbidden(a, &iv) && !is_forbidden(b, &iv),
            "breakpoint edge ({a},{b}) must be a legal candidate");
    }
    // The non-reversed breakpoint-adjacent edges -5 and 10 are legal touching
    // under actual evidence (candidate edges must be re-verified in the
    // guard's ordered frame). Scoped claim: reversed boundaries are excluded.
    for &t in &[-5.0, 10.0] {
        let ev = evidence_at(&l, &r, 0.0, 0.0, base + t).expect("evidence at edge");
        assert!(!ev.collides(), "breakpoint edge residual {t} must be legal touching");
    }
    // And a strictly interior point of a forbidden interval is NOT a legal
    // candidate even though cells+shift math claims a positive gap there.
    let ev = evidence_at(&l, &r, 0.0, 0.0, base + 20.0).expect("evidence at 35");
    assert!(ev.collides(), "actual evidence at the claimed placement must be truth");
}

// ---------------------------------------------------------------------------
// [L2-UNIT] Direct solve_pair_t_l2 guards (401347ff signature: + advance,
// l_tr, r_tr; Solved carries the bit-exact verified export-frame origin).
// Fixture frame unification: base_offset = advance = base, l_tr = r_tr = 0,
// so origin = base + residual. Exact expected values are hand-derived from
// the constant-cell model; they remain UNRUN oracle claims.
// ---------------------------------------------------------------------------

/// Actual J at residual t from canonical evidence (lambda = 0), with the
/// solver's cap applied to the cells (capped solver W, never the uncapped
/// guard mean). None when the placement collides under the guard (forbidden
/// or wholly reversed) or has no cells.
fn actual_j(l: &OutlineProfile, r: &OutlineProfile, base: f64, t: f64,
            target: f64, cap: f64) -> Option<f64> {
    let ev = evidence_at(l, r, 0.0, 0.0, base + t)?;
    if ev.collides() { return None; }
    let cells = signed_clearance::clearance_cells_constant(l, r, base + t);
    if cells.is_empty() { return None; }
    let (mut len, mut s1) = (0.0, 0.0);
    for &(l0, c0, _c1) in &cells { len += l0; s1 += l0 * c0.min(cap); }
    if !(len > 0.0) { return None; }
    let w = s1 / len;
    Some((w - target) * (w - target))
}

/// [L2-UNIT] 20-unit counterexample returned-solution guard: the solve must
/// return a feasible, non-colliding residual whose receipted wall_gap equals
/// actual evidence, and the export-frame origin binding must hold
/// (origin = advance + residual, bit-exact). Hand derivation (constant
/// rectangular cells, cap 50: no clamping): within component (-5,10),
/// W(t) = 5 + t, so J = (t - 20)^2 is minimized at the legal edge t = 10
/// (origin 25, R [25,30] touching L [30,40]): expected residual 10.0,
/// origin 25.0, wall_gap 15.0. The residual 20 is FORBIDDEN and must never
/// be returned.
#[test]
fn l2_counterexample_returns_feasible_noncolliding_edge() {
    let (l, r, target) = counterexample();
    let iv = forbidden_residual_intervals(&l, &r, 15.0).expect("intervals");
    match solve_pair_t_l2(&l, &r, 15.0, 50.0, target, 0.0, -30.0, 30.0, 15.0, 0.0, 0.0) {
        PairSolve::Solved { residual, origin, wall_gap, component } => {
            assert!(!is_forbidden(residual, &iv), "returned residual {residual} forbidden");
            assert!(residual >= component.0 - EPS && residual <= component.1 + EPS,
                "residual outside its receipted component {component:?}");
            assert!((residual - 20.0).abs() > EPS, "forbidden residual 20 must never be returned");
            assert!((residual - 10.0).abs() < EPS, "oracle argmin is the legal edge 10, got {residual}");
            assert!((origin - 25.0).abs() < EPS, "origin = advance + residual = 25, got {origin}");
            assert_eq!(residual.to_bits(), (origin - 15.0).to_bits(),
                "residual must be origin - advance bit-exact");
            let ev = evidence_at(&l, &r, 0.0, 0.0, origin).expect("evidence at origin");
            assert!(!ev.collides(), "returned origin collides under the guard");
            assert!((wall_gap - ev.clearance.min_gap).abs() < EPS,
                "receipted wall_gap {wall_gap} != actual {}", ev.clearance.min_gap);
            assert!((wall_gap - 15.0).abs() < EPS, "oracle wall_gap 15, got {wall_gap}");
        }
        other => panic!("expected Solved, got {other:?}"),
    }
}

/// [L2-UNIT] Actual J agreement as a FINITE oracle comparison (a 0.5 grid
/// plus edges is a finite comparison oracle, NOT a global argmin proof): the
/// returned residual's actual J must be <= the actual J of every grid/edge
/// candidate. Wholly-reversed placements are guard collisions and are
/// excluded, matching the solver's empty-cell skip.
#[test]
fn l2_returned_residual_is_actual_j_argmin() {
    let (l, r, target) = counterexample();
    let iv = forbidden_residual_intervals(&l, &r, 15.0).expect("intervals");
    let comp = feasible_components(-30.0, 30.0, &iv).expect("components");
    let PairSolve::Solved { residual, .. } =
        solve_pair_t_l2(&l, &r, 15.0, 50.0, target, 0.0, -30.0, 30.0, 15.0, 0.0, 0.0)
        else { panic!("expected Solved") };
    let j_ret = actual_j(&l, &r, 15.0, residual, target, 50.0).expect("returned must be legal");
    let mut cands: Vec<f64> = Vec::new();
    for &(a, b) in &comp {
        cands.extend([a, b]);
        let mut k = (a * 2.0).ceil() / 2.0;
        while k <= b { cands.push(k); k += 0.5; }
    }
    for t in cands {
        if let Some(j) = actual_j(&l, &r, 15.0, t, target, 50.0) {
            assert!(j_ret <= j + EPS,
                "returned J {j_ret} > actual J {j} at feasible {t}: not the actual argmin");
        }
    }
}

/// [L2-UNIT] Disconnected components: a domain restricted strictly inside
/// ONE component must return from that component only. Domain [26,29] lies
/// inside component (25,30); W(t) = t - 25 there, J = (t - 50)^2 decreasing,
/// oracle argmin = 29 (origin 44). A fully forbidden domain [-19,-6] is a
/// typed NoFeasible hold, never a fabricated placement.
#[test]
fn l2_disconnected_components_domain_restriction_and_no_feasible() {
    let (l, r, target) = counterexample();
    let PairSolve::Solved { residual, origin, component, .. } =
        solve_pair_t_l2(&l, &r, 15.0, 50.0, target, 0.0, 26.0, 29.0, 15.0, 0.0, 0.0)
        else { panic!("expected Solved") };
    assert!((residual - 29.0).abs() < EPS, "oracle argmin 29 in restricted domain, got {residual}");
    assert!((origin - 44.0).abs() < EPS, "origin = 15 + 29 = 44, got {origin}");
    assert!((component.0 - 26.0).abs() < EPS && (component.1 - 29.0).abs() < EPS);
    assert_eq!(solve_pair_t_l2(&l, &r, 15.0, 50.0, target, 0.0, -19.0, -6.0, 15.0, 0.0, 0.0),
               PairSolve::NoFeasible, "fully forbidden domain must be a typed hold");
}

/// [L2-UNIT] NoAcceptedCandidate typed hold: the domain [-30,-20] contains
/// exactly the wholly-reversed component - components EXIST (not NoFeasible)
/// but every candidate has empty objective cells (reversed: no facing wall),
/// so no candidate is accepted and no bracket budget is exhausted (not
/// NotConverged). The three typed holds must stay distinct.
#[test]
fn l2_no_accepted_candidate_is_distinct_typed_hold() {
    let (l, r, target) = counterexample();
    let iv = forbidden_residual_intervals(&l, &r, 15.0).expect("intervals");
    let comp = feasible_components(-30.0, -20.0, &iv).expect("components");
    assert_eq!(comp, vec![(-30.0, -20.0)], "component exists in the domain");
    assert_eq!(solve_pair_t_l2(&l, &r, 15.0, 50.0, target, 0.0, -30.0, -20.0, 15.0, 0.0, 0.0),
               PairSolve::NoAcceptedCandidate,
               "components existed but no accepted candidate: NoAcceptedCandidate, not NoFeasible, not NotConverged");
}

/// [L2-UNIT] Singleton touch: a domain collapsed to the legal touching point
/// -5 yields the point component; returned residual -5 with actual wall_gap 0
/// (inks touch at origin 10) and no collision.
#[test]
fn l2_singleton_touch_domain_returns_touch_point() {
    let (l, r, target) = counterexample();
    let PairSolve::Solved { residual, origin, wall_gap, component } =
        solve_pair_t_l2(&l, &r, 15.0, 50.0, target, 0.0, -5.0, -5.0, 15.0, 0.0, 0.0)
        else { panic!("expected Solved") };
    assert!((residual - -5.0).abs() < EPS && (component.0 - -5.0).abs() < EPS
        && (component.1 - -5.0).abs() < EPS, "point component expected, got {component:?}");
    assert!((origin - 10.0).abs() < EPS, "origin = 15 - 5 = 10, got {origin}");
    let ev = evidence_at(&l, &r, 0.0, 0.0, origin).expect("evidence at touch");
    assert!(!ev.collides() && (ev.clearance.min_gap - 0.0).abs() < EPS);
    assert!((wall_gap - 0.0).abs() < EPS, "touch wall_gap 0, got {wall_gap}");
}

/// [L2-UNIT] Counter-reversed: mirrored geometry (counters reversed),
/// base -15. Canonical cells measure the right ink's behind-gap, so the
/// reversed instance is NOT a numeric mirror of the forward case; the oracle
/// guards are feasibility, guard agreement and wall_gap agreement only.
#[test]
fn l2_counter_reversed_returned_solution_agrees_with_guard() {
    let l = profile("L", &[(-40.0, -30.0), (-10.0, 0.0)], 4);
    let r = profile("R", &[(-5.0, 0.0)], 4);
    let iv = forbidden_residual_intervals(&l, &r, -15.0).expect("intervals");
    assert_eq!(iv, vec![(-25.0, -10.0), (5.0, 20.0)]);
    let PairSolve::Solved { residual, origin, wall_gap, component } =
        solve_pair_t_l2(&l, &r, -15.0, 50.0, 25.0, 0.0, -30.0, 30.0, -15.0, 0.0, 0.0)
        else { panic!("expected Solved") };
    assert!(!is_forbidden(residual, &iv), "reversed returned residual {residual} forbidden");
    assert!(residual >= component.0 - EPS && residual <= component.1 + EPS);
    assert_eq!(residual.to_bits(), (origin - -15.0).to_bits(),
        "residual must be origin - advance bit-exact");
    let ev = evidence_at(&l, &r, 0.0, 0.0, origin).expect("evidence at origin");
    assert!(!ev.collides(), "reversed returned origin collides");
    assert!((wall_gap - ev.clearance.min_gap).abs() < EPS);
}

/// [L2-UNIT] Cap breakpoint: cap 13 puts a cap breakpoint strictly inside
/// component (-5,10). Hand derivation (constant cells, documented
/// candidate-set contract): W(t) = min(5 + t, 13) on (-5,10), so J is flat
/// at (13-25)^2 = 144 for t in [8, 10); the tie rule (smaller J, then
/// smaller |t|) selects the breakpoint t = 8 over component (25,30)
/// (J >= 400). Component (-30,-20) is wholly REVERSED: its cells are empty,
/// obj_at returns None, and it contributes NO candidates. Expected: residual
/// exactly 8.0 (the cap breakpoint), origin 23.0, wall_gap 13.0 at
/// placement 23, no collision.
#[test]
fn l2_optimum_at_cap_breakpoint_is_returned() {
    let (l, r, target) = counterexample();
    let PairSolve::Solved { residual, origin, wall_gap, component } =
        solve_pair_t_l2(&l, &r, 15.0, 13.0, target, 0.0, -30.0, 30.0, 15.0, 0.0, 0.0)
        else { panic!("expected Solved") };
    assert!((residual - 8.0).abs() < EPS, "cap breakpoint argmin 8, got {residual}");
    assert!((origin - 23.0).abs() < EPS, "origin = 15 + 8 = 23, got {origin}");
    assert!((component.0 - -5.0).abs() < EPS && (component.1 - 10.0).abs() < EPS);
    let ev = evidence_at(&l, &r, 0.0, 0.0, origin).expect("evidence at origin 23");
    assert!(!ev.collides() && (ev.clearance.min_gap - 13.0).abs() < EPS);
    assert!((wall_gap - 13.0).abs() < EPS, "wall_gap 13, got {wall_gap}");
}
