//! L2 actual-placement pair solve: closure tests for the frozen-cells bug.
//! The OLD path (cells at base + channel_stats c+t shift) claims gap 25 at
//! residual 20 on the counterexample; the L2 solve must never ship a
//! residual inside a forbidden interval and must agree with the guard's
//! canonical evidence at the shipped placement.
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{solve_pair_t_l2, PairSolve};
use kni_metrics::signed_clearance;

fn profile(id: &str, ink: &[(f64, f64)]) -> OutlineProfile {
    let mk = |y: f64| ScanRow {
        y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(),
    };
    let xmax = ink.iter().map(|&(_, r)| r).fold(0.0_f64, f64::max);
    OutlineProfile {
        glyph_id: id.to_string(), source_pin: format!("pin-{id}"), upm: 1000,
        origin: [0.0, 0.0], rows: vec![mk(0.0), mk(1.0)],
        bounds: [0.0, 0.0, xmax, 2.0],
        ink_area: 2.0 * ink.iter().map(|&(l, r)| r - l).sum::<f64>(),
        counter_area: 0.0, open_left: 0.0, open_right: 0.0,
        profile_method: "l2-pair-solve-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// Chief's counterexample closed: pair_gap 25 (the old path's claimed value),
/// base 15. The old solver returns residual 20 (inside forbidden (10,25));
/// L2 must land the W=25 root in the feasible component ABOVE the pocket at
/// residual 50 (gap = 15+50-40 = 25 at placement 65, verified by hand), and
/// the shipped placement must pass canonical evidence.
#[test]
fn counterexample_l2_solves_above_the_pocket() {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let out = solve_pair_t_l2(&l, &r, 15.0, 50.0, 25.0, 0.0, -5.0, 100.0, 15.0, 0.0, 0.0);
    let PairSolve::Solved { residual, wall_gap, component, .. } = out else {
        panic!("expected Solved, got {out:?}");
    };
    assert_eq!(residual, 50.0, "W=25 root must land at residual 50, not 20");
    assert_eq!(component, (25.0, 100.0));
    assert!((wall_gap - 25.0).abs() < 1e-12, "wall gap {wall_gap}");
    let e = signed_clearance::evidence_at(&l, &r, 0.0, 0.0, 15.0 + residual)
        .expect("evidence");
    assert!(!e.collides(), "shipped placement must pass canonical evidence");
    assert!(!signed_clearance::is_forbidden(residual,
        &signed_clearance::forbidden_residual_intervals(&l, &r, 15.0).unwrap()));
}

/// No feasible residual in the domain: typed hold, never a collision verdict.
#[test]
fn no_feasible_domain_is_typed_hold() {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let out = solve_pair_t_l2(&l, &r, 15.0, 50.0, 25.0, 0.0, 12.0, 20.0, 15.0, 0.0, 0.0);
    assert_eq!(out, PairSolve::NoFeasible);
}

/// Unmeasurable pair (no common span) keeps its existing ledger class.
#[test]
fn unmeasurable_is_not_a_solve() {
    let l = profile("L", &[(0.0, 10.0)]);
    let r = profile("R", &[]);
    let out = solve_pair_t_l2(&l, &r, 15.0, 50.0, 25.0, 0.0, -5.0, 100.0, 15.0, 0.0, 0.0);
    assert_eq!(out, PairSolve::Unmeasurable);
}

/// A point-only component is a legal touching candidate and can win.
#[test]
fn point_component_is_a_legal_candidate() {
    // Domain clipped so only the touching point t=10 of the pocket edge is
    // feasible: components [( -5,10)] exists too; clip domain to [10,10].
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let out = solve_pair_t_l2(&l, &r, 15.0, 50.0, 25.0, 0.0, 10.0, 10.0, 15.0, 0.0, 0.0);
    let PairSolve::Solved { residual, .. } = out else {
        panic!("expected Solved at the touching point, got {out:?}");
    };
    assert_eq!(residual, 10.0);
    let e = signed_clearance::evidence_at(&l, &r, 0.0, 0.0, 25.0).expect("evidence");
    assert!(!e.collides(), "touching at the pocket edge is legal");
}
