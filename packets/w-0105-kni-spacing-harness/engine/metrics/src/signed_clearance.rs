//! Shared signed collision primitive for the K2 solver and the K3 export guard.
//!
//! One geometric model for both: PIECEWISE-CONSTANT full-interval clearance
//! cells on the shared aligned native grid (align_pair_rows), counters kept,
//! signed clearance of a span is `right.left - left.right + offset` at the
//! queried placement. The minimum over constant spans is exact, not sampled.
//!
//! Sign semantics (single source of truth):
//! - `min_gap` is signed. Negative means ink penetration on a common y.
//! - `penetration_depth = max(0, -min_gap)`. A positive gap is NEVER depth.
//! - `collides` is true only for a negative clearance; touching (0) is legal.
//! - Counter/inner-interval collisions that the outer walls cannot see are
//!   reported separately by `interval_collision` (true ink intersection on a
//!   sampled span), so `min_gap > 0` never hides a real intersection.

use crate::outline_spacing::{align_pair_rows, AlignedRow, OutlineProfile};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Clearance {
    /// Signed minimum clearance over all cells (exact for linear cells).
    pub min_gap: f64,
    /// max(0, -min_gap). Never derived from a positive gap.
    pub penetration_depth: f64,
    /// Length-weighted mean clearance (optical view).
    pub weighted_mean_gap: f64,
    /// Total common-y length.
    pub covered_len: f64,
}

impl Clearance {
    pub fn collides(&self) -> bool { self.min_gap < 0.0 }
}

pub fn clearance_of(cells: &[(f64, f64, f64)]) -> Option<Clearance> {
    let min_gap = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
    if !min_gap.is_finite() { return None; }
    let len: f64 = cells.iter().map(|c| c.0).sum();
    let area: f64 = cells.iter().map(|c| c.0 * (c.1 + c.2) * 0.5).sum();
    Some(Clearance {
        min_gap,
        penetration_depth: (-min_gap).max(0.0),
        weighted_mean_gap: if len > 0.0 { area / len } else { min_gap },
        covered_len: len,
    })
}

/// Piecewise-CONSTANT clearance cells on the shared aligned native grid
/// (chief ruling 22:55: single canonical model). Full ink intervals of both
/// sides, counters kept; one constant value per aligned span: the minimum
/// over right ink intervals of (r_left - nearest left wall right) + offset.
/// The solver's objective AND collision constraint AND the export guard all
/// read this same interval evidence; no between-row lerp exists anywhere.
pub fn clearance_cells_constant(left: &OutlineProfile, right: &OutlineProfile,
                                offset: f64) -> Vec<(f64, f64, f64)> {
    clearance_cells_constant_rows(&align_pair_rows(left, right), offset)
}

/// clearance_cells_constant with the placement-independent row alignment
/// hoisted out (K2 pair-cascade hot path evaluates many placements over one
/// pair's rows). Identical per-row math on the identical aligned grid:
/// same inputs, same bits.
pub fn clearance_cells_constant_rows(rows: &[AlignedRow],
                                     offset: f64) -> Vec<(f64, f64, f64)> {
    let mut out = Vec::new();
    for_each_clearance_cell_constant_rows(rows, offset, |w, c0, c1| out.push((w, c0, c1)));
    out
}

/// clearance_cells_constant_rows with the per-call allocation hoisted out:
/// clears `out` and pushes the same (weight, gmin, gmin) cells in the same
/// row order (K2 pair-cascade hot path: one scratch Vec per solve instead of
/// one fresh Vec per evaluated placement). Same inputs, same bits.
pub fn clearance_cells_constant_rows_into(rows: &[AlignedRow], offset: f64,
                                          out: &mut Vec<(f64, f64, f64)>) {
    out.clear();
    for_each_clearance_cell_constant_rows(rows, offset, |w, c0, c1| out.push((w, c0, c1)));
}

/// Per-cell walk of clearance_cells_constant_rows without materialising the
/// cell Vec: `f` receives each (weight, gmin, gmin) cell in exactly the order
/// clearance_cells_constant_rows pushes them. Identical per-row math on the
/// identical aligned grid: same cells, same order, same bits.
pub fn for_each_clearance_cell_constant_rows(rows: &[AlignedRow], offset: f64,
                                             mut f: impl FnMut(f64, f64, f64)) {
    for row in rows {
        if row.left.is_empty() || row.right.is_empty() { continue; }
        let mut gmin = f64::INFINITY;
        for ri in &row.right {
            let rl = ri.left + offset;
            let rr = ri.right + offset;
            let mut nearest: Option<f64> = None;
            for li in &row.left {
                if li.left >= rr { continue; } // wholly right: no wall behind
                let g = rl - li.right;
                if nearest.map_or(true, |n| g < n) { nearest = Some(g); }
            }
            if let Some(g) = nearest { if g < gmin { gmin = g; } }
        }
        if gmin.is_finite() && row.weight > 0.0 { f(row.weight, gmin, gmin); }
    }
}

/// Clearance of a pair in the caller-bound frame: left translated by `l_tr`,
/// right by `r_tr`, right origin placed at `origin_distance`.
pub fn pair_clearance(left: &OutlineProfile, right: &OutlineProfile,
                      l_tr: f64, r_tr: f64, origin_distance: f64) -> Option<Clearance> {
    pair_clearance_rows(&align_pair_rows(left, right), l_tr, r_tr, origin_distance)
}

/// pair_clearance with the placement-independent row alignment hoisted out
/// (same ruling text applies: measured AT this placement, never
/// extrapolated). Identical per-row math on the identical aligned grid:
/// same inputs, same bits.
pub fn pair_clearance_rows(rows: &[AlignedRow],
                           l_tr: f64, r_tr: f64, origin_distance: f64) -> Option<Clearance> {
    let mut min_gap = f64::INFINITY;
    let (mut wsum, mut gsum, mut len) = (0.0_f64, 0.0_f64, 0.0_f64);
    let mut compared = false;
    for row in rows {
        if row.left.is_empty() || row.right.is_empty() { continue; }
        compared = true;
        let w = row.weight;
        for ri in &row.right {
            let rl = ri.left + r_tr + origin_distance;
            let rr = ri.right + r_tr + origin_distance;
            let mut nearest: Option<f64> = None;
            let mut max_right = f64::NEG_INFINITY;
            for li in &row.left {
                let ll = li.left + l_tr;
                let lr = li.right + l_tr;
                if lr > max_right { max_right = lr; }
                if ll >= rr { continue; } // wholly to the right: no wall behind
                let g = rl - lr;
                if nearest.map_or(true, |n| g < n) { nearest = Some(g); }
            }
            // Wholly-reversed interval (every left wall to its right): the
            // truthful signed gap is negative (shift that un-reverses it);
            // never skip it into a fake +INFINITY (wholly-right regression).
            let g = nearest.unwrap_or(rl - max_right);
            if g.is_finite() {
                if g < min_gap { min_gap = g; }
                if w.is_finite() && w > 0.0 { wsum += w; gsum += w * g; len += w; }
            }
        }
    }
    if !compared || !min_gap.is_finite() { return None; }
    Some(Clearance {
        min_gap,
        penetration_depth: (-min_gap).max(0.0),
        weighted_mean_gap: if wsum > 0.0 { gsum / wsum } else { min_gap },
        covered_len: len,
    })
}

/// True ink intersection on any sampled aligned span, counters included.
/// Evidence the outer-wall clearance cannot see. Strict overlap only.
pub fn interval_collision(left: &OutlineProfile, right: &OutlineProfile,
                          l_tr: f64, r_tr: f64, origin_distance: f64) -> bool {
    interval_collision_rows(&align_pair_rows(left, right), l_tr, r_tr, origin_distance)
}

/// interval_collision with the placement-independent row alignment hoisted
/// out. Identical per-row math on the identical aligned grid.
pub fn interval_collision_rows(rows: &[AlignedRow],
                               l_tr: f64, r_tr: f64, origin_distance: f64) -> bool {
    for row in rows {
        for ri in &row.right {
            let (rl, rr) = (ri.left + r_tr + origin_distance, ri.right + r_tr + origin_distance);
            for li in &row.left {
                let (ll, lr) = (li.left + l_tr, li.right + l_tr);
                if ll < rr && rl < lr { return true; }
            }
        }
    }
    false
}

/// Maximum strict ink-overlap depth over the aligned grid: for every
/// (left, right) interval pair with `ll < rr && rl < lr` the overlap is
/// `min(rr, lr) - max(ll, rl) > 0`; the result is the maximum such depth,
/// or 0.0 when no pair strictly overlaps. Touching endpoints contribute
/// nothing, so exact contact measures exactly 0.0 while any real
/// penetration measures its true depth. Same inputs, same bits as
/// `interval_collision_rows`: that predicate is exactly `depth > 0.0`.
pub fn interval_overlap_depth(left: &OutlineProfile, right: &OutlineProfile,
                              l_tr: f64, r_tr: f64, origin_distance: f64) -> f64 {
    interval_overlap_depth_rows(&align_pair_rows(left, right), l_tr, r_tr, origin_distance)
}

/// interval_overlap_depth with the placement-independent row alignment
/// hoisted out. Identical per-row math on the identical aligned grid.
pub fn interval_overlap_depth_rows(rows: &[AlignedRow],
                                   l_tr: f64, r_tr: f64, origin_distance: f64) -> f64 {
    let mut depth = 0.0f64;
    for row in rows {
        for ri in &row.right {
            let (rl, rr) = (ri.left + r_tr + origin_distance, ri.right + r_tr + origin_distance);
            for li in &row.left {
                let (ll, lr) = (li.left + l_tr, li.right + l_tr);
                if ll < rr && rl < lr {
                    let d = rr.min(lr) - rl.max(ll);
                    if d > depth { depth = d; }
                }
            }
        }
    }
    depth
}

/// Full collision evidence at one placement.
#[derive(Debug, Clone, Copy)]
pub struct Evidence { pub clearance: Clearance, pub interval_hit: bool }

impl Evidence {
    pub fn collides(&self) -> bool { self.clearance.collides() || self.interval_hit }
}

/// Next representable f64 strictly greater than `v` ("outward" for the
/// placement bracket). Sign-aware bit stepping with an explicit contract,
/// NOT a naive `from_bits(v.to_bits()+1)`: for negative v, bits+1 steps to
/// a MORE negative value (inward); value-up for negatives is bits-1.
///   v > 0  -> bits + 1
///   v < 0  -> bits - 1   (toward zero is value-up for negatives)
///   +-0.0  -> minimum positive subnormal (from_bits(1))
///   NaN / +-inf -> None (typed failure; the caller holds, never guesses)
/// Matches std `f64::next_up` on every finite input except `f64::MAX`,
/// which has no finite outward step and returns None; pinned locally so the
/// solver and the guard share one ordered stepping contract.
pub fn next_up_outward(v: f64) -> Option<f64> {
    if v.is_nan() || v.is_infinite() { return None; }
    if v == 0.0 { return Some(f64::from_bits(1)); } // covers -0.0
    let b = v.to_bits();
    let u = f64::from_bits(if v > 0.0 { b + 1 } else { b - 1 });
    // f64::MAX has no finite outward step: typed boundary, not a placement.
    if u.is_finite() { Some(u) } else { None }
}

pub fn evidence_at(left: &OutlineProfile, right: &OutlineProfile,
                   l_tr: f64, r_tr: f64, origin_distance: f64) -> Option<Evidence> {
    evidence_at_rows(&align_pair_rows(left, right), l_tr, r_tr, origin_distance)
}

/// evidence_at with the placement-independent row alignment hoisted out:
/// ONE aligned grid serves both the clearance and the interval-collision
/// pass (previously aligned twice per call). Same inputs, same bits.
pub fn evidence_at_rows(rows: &[AlignedRow],
                        l_tr: f64, r_tr: f64, origin_distance: f64) -> Option<Evidence> {
    let clearance = pair_clearance_rows(rows, l_tr, r_tr, origin_distance)?;
    Some(Evidence { clearance,
        interval_hit: interval_collision_rows(rows, l_tr, r_tr, origin_distance) })
}

/// Deterministic safe integer export distance.
///
/// `exact` is the solver's intended origin distance (already collision-free
/// at the exact placement; the caller verifies that). The start candidate is
/// `round(exact)` raised to `ceil(exact - max(clearance,0))` when the exact
/// clearance cannot absorb the rounding loss; with ample clearance this CAN
/// land BELOW exact (nearest-safe, chief-confirmed doc fix 22:55: an earlier
/// "never closer" claim was wrong, as were "clearance 1:1 in distance" and
/// "counter hits monotone" — the facing-interval set changes with distance).
/// Every candidate is verified with actual interval evidence at that integer
/// placement before acceptance; the search steps upward until evidence is
/// clean. The upper bound is derived from the pair itself (ink widths), not
/// a constant. Returns None when no candidate verifies.
pub fn safe_integer_distance(left: &OutlineProfile, right: &OutlineProfile,
                             l_tr: f64, r_tr: f64, exact: f64,
                             exact_clearance: f64) -> Option<i32> {
    // Nearest lattice point is kept unless it sits closer than the exact
    // clearance can absorb; then the first absorbing integer is used.
    let start = exact.round().max((exact - exact_clearance.max(0.0)).ceil());
    let span = (left.bounds[2] - left.bounds[0]) + (right.bounds[2] - right.bounds[0]);
    let limit = start + span.ceil() + 1.0;
    let mut d = start;
    while d <= limit {
        match evidence_at(left, right, l_tr, r_tr, d) {
            Some(e) if !e.collides() => return Some(d as i32),
            Some(_) => {}
            None => return None,
        }
        d += 1.0;
    }
    None
}

/// STAGE-4 exact evidence on exact slab rows (`exact_rows`). Same nearest-wall cells, same strict-overlap predicate as `evidence_at_rows`,
/// with two differences that remove the sampled-model fallbacks:
///   * collision is the exact interval overlap (`interval_hit`) OR a negative nearest-wall gap; a right ink piece lying wholly behind
///     every left ink piece does NOT create a negative gap (it is skipped, as the solver cells skip it), and
///   * min_gap is the minimum nearest-wall gap over the exact rows; when no row has a facing wall at all the value falls back to
///     `pair_clearance_rows` (reversed-interval rule) so a pair with no facing wall stays measurable and typed.
pub fn exact_evidence_rows(rows: &[AlignedRow], l_tr: f64, r_tr: f64, origin_distance: f64) -> Option<Evidence> {
    exact_evidence_rows_marked(rows, l_tr, r_tr, origin_distance).map(|(e, _)| e)
}

/// `exact_evidence_rows` plus the typed evidence source: `true` when no row had a facing wall and the value came from the
/// `pair_clearance_rows` reversed-interval fallback (conservative, fail-closed), `false` when it is the nearest-wall measurement.
pub fn exact_evidence_rows_marked(rows: &[AlignedRow], l_tr: f64, r_tr: f64, origin_distance: f64) -> Option<(Evidence, bool)> {
    let hit = interval_collision_rows(rows, l_tr, r_tr, origin_distance);
    let cells = clearance_cells_constant_rows(rows, origin_distance + r_tr - l_tr);
    let (clearance, fallback) = match clearance_of(&cells) {
        Some(c) => (c, false),
        None => (pair_clearance_rows(rows, l_tr, r_tr, origin_distance)?, true),
    };
    Some((Evidence { clearance, interval_hit: hit }, fallback))
}

/// First integer of the export-lattice search (shared by the walk and by the stage-4 below-epsilon check, one definition):
/// `max(round(exact), ceil(exact - max(0, exact_clearance)))`.
pub fn lattice_start(exact: f64, exact_clearance: f64) -> f64 {
    exact.round().max((exact - exact_clearance.max(0.0)).ceil())
}

/// `safe_integer_distance` over a caller-supplied evidence function (the exact stage-4 rows). Same search order and bound.
pub fn safe_integer_distance_by(eval: impl Fn(f64) -> Option<Evidence>, span: f64, exact: f64, exact_clearance: f64) -> Option<i32> {
    let start = lattice_start(exact, exact_clearance);
    let limit = start + span.ceil() + 1.0;
    let mut d = start;
    while d <= limit {
        match eval(d) {
            Some(e) if !e.collides() => return Some(d as i32),
            Some(_) => {}
            None => return None,
        }
        d += 1.0;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};

    fn prof(id: &str, rings: Vec<Vec<[f64; 2]>>) -> OutlineProfile {
        let input = OutlineInput {
            glyph_id: id.to_string(), source_pin: format!("sha256:test:{id}"),
            upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0, rings,
        };
        // Shared grid anchor, as the pipeline caller uses.
        let pol = ScanPolicy { row_step: 2.0, max_rows: 4000, merge_guard: MERGE_GUARD_UNITS,
                               grid_anchor_y: Some(0.0) };
        profile_outline(&input, pol).expect("profile")
    }
    fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
        vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    }
    /// Eacute-like: body + detached slanted accent (separate run), right wall
    /// of the accent slopes outward with height.
    fn eacute_like() -> OutlineProfile {
        prof("Eacute", vec![
            rect(0.0, 0.0, 100.0, 200.0),
            vec![[60.0, 230.0], [100.0, 230.0], [160.0, 300.0], [120.0, 300.0]],
        ])
    }
    fn u_like() -> OutlineProfile { prof("u", vec![rect(0.0, 0.0, 80.0, 160.0)]) }

    /// The OLD guard model: piecewise-constant interval rows, nearest wall.
    fn legacy_constant_min_gap(l: &OutlineProfile, r: &OutlineProfile, d: f64) -> f64 {
        let mut min = f64::INFINITY;
        for row in align_pair_rows(l, r) {
            for ri in &row.right {
                let mut nearest: Option<f64> = None;
                for li in &row.left {
                    if li.right <= ri.left + d && nearest.map_or(true, |n| li.right > n) {
                        nearest = Some(li.right);
                    }
                }
                if let Some(w) = nearest { min = min.min(ri.left + d - w); }
            }
        }
        min
    }

    #[test]
    fn eacute_u_exact_origin_solver_and_guard_share_one_value() {
        let (l, r) = (eacute_like(), u_like());
        // Solver side: normalised walls + l_width + sides. Guard side: raw
        // frame with translations. Same primitive, same number.
        let d = 100.0 + 7.5; // advance-ish + residual
        let guard = pair_clearance(&l, &r, 0.0, 0.0, d).unwrap();
        // Canonical model is PIECEWISE-CONSTANT (chief 22:46): the safety
        // primitive must agree with the constant full-interval reference,
        // while the solver's optical J stays the DECLARED linear cell model
        // (not bit-identical to the guard by design).
        let legacy = legacy_constant_min_gap(&l, &r, d);
        assert!((guard.min_gap - legacy).abs() < 1e-9,
            "constant guard {} must match constant reference {}", guard.min_gap, legacy);
        // Single canonical model: the solver reads the SAME constant cells.
        let cells = clearance_cells_constant(&l, &r, d);
        let solver = clearance_of(&cells).unwrap();
        assert!((solver.min_gap - guard.min_gap).abs() < 1e-9,
            "solver cells {} and guard {} share one model", solver.min_gap, guard.min_gap);
        // Body vs u share y in [0,160): gap = 100+7.5... u.left=0 -> d - 100.
        assert!((guard.min_gap - 7.5).abs() < 1e-9, "min_gap {}", guard.min_gap);
        assert!(!guard.collides());
    }

    #[test]
    fn slanted_wall_linear_model_matches_constant_half_row_at_sample_rows() {
        // Left glyph with a slanted right wall, right glyph a tall rect.
        let l = prof("slant", vec![vec![[0.0, 0.0], [100.0, 0.0], [160.0, 120.0], [60.0, 120.0]]]);
        let r = prof("bar", vec![rect(0.0, 0.0, 30.0, 120.0)]);
        let d = 170.0;
        let lin = pair_clearance(&l, &r, 0.0, 0.0, d).unwrap();
        let legacy = legacy_constant_min_gap(&l, &r, d);
        // Wall at y is 100 + 0.5*y; tightest common y is the top row center.
        assert!(lin.min_gap <= legacy + 1e-9, "linear {} legacy {}", lin.min_gap, legacy);
        // Parity: on a uniform grid the linear min over cells is attained at row
        // centers, where the constant-half-row model reads the same wall value.
        assert!((lin.min_gap - legacy).abs() < 1e-9, "parity at sample rows: {} vs {}", lin.min_gap, legacy);
    }

    #[test]
    fn positive_gap_is_never_penetration_depth() {
        let (l, r) = (eacute_like(), u_like());
        let c = pair_clearance(&l, &r, 0.0, 0.0, 130.0).unwrap();
        assert!(c.min_gap > 0.0);
        assert_eq!(c.penetration_depth, 0.0);
        let c2 = pair_clearance(&l, &r, 0.0, 0.0, 90.0).unwrap();
        assert!(c2.collides());
        assert!((c2.penetration_depth + c2.min_gap).abs() < 1e-12);
    }

    #[test]
    fn interval_collision_sees_what_outer_wall_clearance_cannot() {
        // Right ink sits inside the left glyph's counter: outer-wall model is
        // conservative (reports collision), interval evidence says no ink hit.
        let ring = prof("o", vec![rect(0.0, 0.0, 100.0, 100.0),
                                   vec![[30.0, 30.0], [30.0, 70.0], [70.0, 70.0], [70.0, 30.0]]]);
        let bar = prof("bar", vec![rect(0.0, 0.0, 10.0, 100.0)]);
        // bar spans x 40..50 at d=40, inside the counter (30..70) for y in 30..70
        // but overlaps the ring strokes elsewhere -> a real hit exists.
        assert!(interval_collision(&ring, &bar, 0.0, 0.0, 40.0));
        // Fully clear placement.
        assert!(!interval_collision(&ring, &bar, 0.0, 0.0, 100.0));
    }

    #[test]
    fn safe_integer_distance_fixes_downward_rounding_collision() {
        // Left width 100.4, right clear rect. Exact placement touches (gap 0)
        // at 100.4; round() gives 100 which collides by 0.4.
        let l = prof("w", vec![rect(0.0, 0.0, 100.4, 100.0)]);
        let r = prof("r", vec![rect(0.0, 0.0, 50.0, 100.0)]);
        let exact = 100.4;
        let c = pair_clearance(&l, &r, 0.0, 0.0, exact).unwrap();
        assert!(c.min_gap.abs() < 1e-9 && !c.collides());
        assert!(evidence_at(&l, &r, 0.0, 0.0, 100.0).unwrap().collides());
        let d = safe_integer_distance(&l, &r, 0.0, 0.0, exact, c.min_gap).unwrap();
        assert_eq!(d, 101);
        assert!(!evidence_at(&l, &r, 0.0, 0.0, d as f64).unwrap().collides());
        // Rounding up already safe: nearest kept.
        let d2 = safe_integer_distance(&l, &r, 0.0, 0.0, 100.6, 0.2).unwrap();
        assert_eq!(d2, 101);
    }

    #[test]
    fn rows_variants_bit_identical_to_aligning_wrappers() {
        // The *_rows variants must reproduce the wrapper results bit for bit:
        // same aligned grid, same per-row math. Bitwise (to_bits) comparison,
        // not approximate equality.
        let l = eacute_like();
        let r = u_like();
        let rows = align_pair_rows(&l, &r);
        let bits = |v: &[(f64, f64, f64)]| v.iter().map(|c| (c.0.to_bits(), c.1.to_bits(), c.2.to_bits())).collect::<Vec<_>>();
        let cbits = |c: &Clearance| (c.min_gap.to_bits(), c.penetration_depth.to_bits(),
                                     c.weighted_mean_gap.to_bits(), c.covered_len.to_bits());
        for &o in &[-500.0, -37.5, 0.0, 12.25, 160.0, 400.0] {
            assert_eq!(bits(&clearance_cells_constant(&l, &r, o)), bits(&clearance_cells_constant_rows(&rows, o)), "cells at {o}");
            match (pair_clearance(&l, &r, 3.0, -2.0, o), pair_clearance_rows(&rows, 3.0, -2.0, o)) {
                (None, None) => {}
                (Some(a), Some(b)) => assert_eq!(cbits(&a), cbits(&b), "clearance at {o}"),
                _ => panic!("clearance presence mismatch at {o}"),
            }
            assert_eq!(interval_collision(&l, &r, 3.0, -2.0, o), interval_collision_rows(&rows, 3.0, -2.0, o), "interval at {o}");
            match (evidence_at(&l, &r, 3.0, -2.0, o), evidence_at_rows(&rows, 3.0, -2.0, o)) {
                (None, None) => {}
                (Some(a), Some(b)) => { assert_eq!(cbits(&a.clearance), cbits(&b.clearance), "evidence clearance at {o}");
                                        assert_eq!(a.interval_hit, b.interval_hit, "evidence hit at {o}"); }
                _ => panic!("evidence presence mismatch at {o}"),
            }
        }
    }

    #[test]
    fn alloc_free_cell_variants_bit_identical_to_allocating_cells() {
        // clearance_cells_constant_rows_into (scratch reuse) and
        // for_each_clearance_cell_constant_rows (no materialised Vec) must
        // reproduce clearance_cells_constant_rows bit for bit: same row
        // walk, same per-row math, same cell order. Bitwise (to_bits)
        // comparison, not approximate equality.
        let l = eacute_like();
        let r = u_like();
        let rows = align_pair_rows(&l, &r);
        // Vertically disjoint right profile: every aligned row is one-sided,
        // so the cell set is empty (the callers' empty branch).
        let far = prof("far", vec![rect(0.0, 5000.0, 10.0, 5100.0)]);
        let rows_empty = align_pair_rows(&l, &far);
        let bits = |v: &[(f64, f64, f64)]| v.iter().map(|c| (c.0.to_bits(), c.1.to_bits(), c.2.to_bits())).collect::<Vec<_>>();
        let mut scratch = Vec::with_capacity(64);
        for (tag, rows) in [("shared", &rows), ("empty", &rows_empty)] {
            for &o in &[-500.0, -37.5, 0.0, 12.25, 160.0, 400.0] {
                let want = clearance_cells_constant_rows(rows, o);
                clearance_cells_constant_rows_into(rows, o, &mut scratch);
                assert_eq!(bits(&want), bits(&scratch), "into at {tag}/{o}");
                let mut folded = Vec::new();
                for_each_clearance_cell_constant_rows(rows, o, |w, c0, c1| folded.push((w, c0, c1)));
                assert_eq!(bits(&want), bits(&folded), "fold at {tag}/{o}");
            }
        }
    }

    #[test]
    fn safe_integer_distance_is_deterministic_and_none_on_no_coverage() {
        let l = prof("a", vec![rect(0.0, 0.0, 50.0, 100.0)]);
        let r = prof("b", vec![rect(0.0, 500.0, 50.0, 600.0)]);
        assert_eq!(safe_integer_distance(&l, &r, 0.0, 0.0, 60.0, 5.0), None);
        let l2 = prof("w", vec![rect(0.0, 0.0, 100.4, 100.0)]);
        let r2 = prof("r", vec![rect(0.0, 0.0, 50.0, 100.0)]);
        let a = safe_integer_distance(&l2, &r2, 0.0, 0.0, 100.4, 0.0);
        let b = safe_integer_distance(&l2, &r2, 0.0, 0.0, 100.4, 0.0);
        assert_eq!(a, b);
    }
}

// ==== Exact forbidden-interval constraints (J-fix layer 1, chief dar onay 23:07/23:16) ====
//
// INPUT SEMANTICS (explicit, chief condition): intervals enter through
// `align_pair_rows(left, right)` exactly like pair_clearance/interval_collision;
// left and right are RAW profiles in their own frames, `base_offset` is the
// right-origin placement at which the pair is evaluated BEFORE residual t.
// The residual t is added ONCE, here, as (ri + base_offset + t): the caller
// passes base_offset WITHOUT t and never pre-adds it to the intervals.
//
// For one same-row pair (li, ri) at residual t, ink strictly intersects iff
//   li.left < ri.right + base + t  AND  ri.left + base + t < li.right
// i.e. t in the OPEN interval (li.left - ri.right - base, li.right - ri.left - base).
// Touching boundaries (t exactly at an edge) are legal. A fully reversed
// placement (rr + base + t <= ll) does NOT intersect and is not forbidden
// here, matching interval_collision's strict-overlap semantics; whether the
// guard measures such a pair at all is the separate reversed-fallback
// question (regression (b)), not this module's concern.

/// Why forbidden-interval construction cannot produce constraints.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ForbiddenError {
    /// No aligned row carries ink on both sides: nothing to constrain.
    NoCommonSpan,
    /// Non-finite base offset or interval coordinate: typed failure, never a guess.
    NonFinite,
    /// Malformed interval list: non-finite bound, non-positive width (a >= b),
    /// or unsorted input. `forbidden_residual_intervals` output always
    /// satisfies the contract; external callers are validated, never trusted.
    MalformedIntervals,
}

/// Merged exact forbidden residual intervals (open), sorted, overlap-merged.
/// Adjacent intervals (a,b),(b,c) are NOT merged: point b is legal touching
/// and must stay feasible. Empty Vec = no pair can intersect at any residual.
pub fn forbidden_residual_intervals(left: &OutlineProfile, right: &OutlineProfile,
                                    base_offset: f64) -> Result<Vec<(f64, f64)>, ForbiddenError> {
    if !base_offset.is_finite() { return Err(ForbiddenError::NonFinite); }
    let mut iv: Vec<(f64, f64)> = Vec::new();
    let mut any_common = false;
    for row in &align_pair_rows(left, right) {
        if row.left.is_empty() || row.right.is_empty() { continue; }
        any_common = true;
        for ri in &row.right {
            for li in &row.left {
                let (a, b) = (li.left - ri.right - base_offset, li.right - ri.left - base_offset);
                if !a.is_finite() || !b.is_finite() { return Err(ForbiddenError::NonFinite); }
                if a < b { iv.push((a, b)); } // a == b: zero-length, no strict-interior residual
            }
        }
    }
    if !any_common { return Err(ForbiddenError::NoCommonSpan); }
    iv.sort_by(|x, y| x.0.partial_cmp(&y.0).unwrap_or(std::cmp::Ordering::Equal)
        .then(x.1.partial_cmp(&y.1).unwrap_or(std::cmp::Ordering::Equal)));
    let mut out: Vec<(f64, f64)> = Vec::new();
    for (a, b) in iv {
        match out.last_mut() {
            // overlap-merge only (a < end): touching (a == end) stays separate
            // so the shared boundary point remains feasible.
            Some(last) if a < last.1 => { if b > last.1 { last.1 = b; } }
            _ => out.push((a, b)),
        }
    }
    Ok(out)
}

/// Actual forbidden membership of one residual: t strictly inside any open
/// interval. Component endpoints MUST be checked with this (chief 23:19):
/// a closed component (a, b) from `feasible_components` claims legal
/// touching at both ends, and this function is the check that proves it.
/// FP CAVEAT (chief 23:19): edges are subtraction-form (li - ri - base);
/// the guard adds (base + t + endpoint). On arbitrary floats the two orders
/// can round apart by ~1 ulp, so every candidate edge a solver ships MUST
/// be re-verified with `evidence_at` in the guard's exact ordered frame
/// (layer-2 contract); this membership is the constraint model, not the
/// final evidence. Equivalence is established ONLY against `interval_collision` (strict ink
/// overlap); the reversed-fallback question is a separate gate and is NOT
/// covered by this membership.
pub fn is_forbidden(t: f64, forbidden: &[(f64, f64)]) -> bool {
    forbidden.iter().any(|&(a, b)| t > a && t < b)
}

/// Validate the interval-list contract: finite bounds, positive width,
/// sorted by start. `forbidden_residual_intervals` output always passes;
/// any other source must be validated before `feasible_components`.
pub fn validate_intervals(forbidden: &[(f64, f64)]) -> Result<(), ForbiddenError> {
    let mut prev_start = f64::NEG_INFINITY;
    for &(a, b) in forbidden {
        if !a.is_finite() || !b.is_finite() { return Err(ForbiddenError::NonFinite); }
        if !(a < b) || a < prev_start { return Err(ForbiddenError::MalformedIntervals); }
        prev_start = a;
    }
    Ok(())
}

/// Feasible residual components: [t_lo, t_hi] minus the forbidden open
/// intervals, as CLOSED components (boundary touching is legal). Zero-length
/// components (x, x) are kept: a single legal touching residual. Empty Vec =
/// no feasible residual in the domain: the caller's typed hold, never an
/// automatic extension of the domain.
pub fn feasible_components(t_lo: f64, t_hi: f64, forbidden: &[(f64, f64)]) -> Result<Vec<(f64, f64)>, ForbiddenError> {
    validate_intervals(forbidden)?;
    if !t_lo.is_finite() || !t_hi.is_finite() { return Err(ForbiddenError::NonFinite); }
    if t_hi < t_lo { return Ok(Vec::new()); }
    // Strictness-preserving clip: a domain edge strictly INSIDE a forbidden
    // open interval is itself forbidden; only interval edges are legal.
    let mut out = Vec::new();
    let mut cur = t_lo;
    for &(a, b) in forbidden {
        if b <= cur { continue; }        // interval at/below cur; b == cur is a legal edge
        if a > t_hi { break; }           // sorted: nothing left in domain
        if a < cur { cur = b; continue; } // cur strictly inside (a,b): jump to the legal edge b
        out.push((cur, a.min(t_hi)));    // a >= cur: feasible chunk, edge a legal
        cur = b;
    }
    if cur <= t_hi { out.push((cur, t_hi)); }
    Ok(out)
}
