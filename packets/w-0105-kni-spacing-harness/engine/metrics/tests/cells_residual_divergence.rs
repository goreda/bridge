//! K123 regression, retargeted to the v2 single-model package (tgz
//! 33326a04...): the distance-dependent facing-membership counterexample
//! against the canonical piecewise-constant cells.
//!
//! L ink [0,10],[30,40], R ink [0,5], base offset 15 (chief 2026-10-15,
//! relayed via parent):
//!   - clearance_cells_constant at base drops L[30,40] (li.left=30 >= R
//!     right edge 20) -> base cell gap 5.
//!   - Solver objective shifts cells by residual (channel_stats c+t):
//!     5 + 20 = claimed gap 25 at offset 35.
//!   - Canonical evidence_at AT offset 35: R=[35,40] faces L[30,40] ->
//!     actual min_gap -5, interval_hit true, COLLISION.
//! clearance(d+t) != clearance(d)+t: membership flips with distance, so
//! cells+residual J math is unsound on this class even in the v2 unified
//! model. The 1-ulp outward bracket is a numeric-contact repair and does
//! NOT close this 20-unit divergence; the guard as final checker catches it.

use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::signed_clearance::{self, next_up_outward};

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
        profile_method: "cells-divergence-regression".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// The chief's concrete source counterexample: solver cells at base + residual
/// vs canonical evidence at the final distance.
#[test]
fn facing_membership_changes_with_distance() {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    // Solver side: cells at base offset 15.
    let cells = signed_clearance::clearance_cells_constant(&l, &r, 15.0);
    assert!(!cells.is_empty(), "aligned row spans exist");
    let base_gap = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1));
    assert!((base_gap - 5.0).abs() < 1e-12, "base cell gap {}", base_gap);
    // Solver J math: cell gap + residual 20.
    let claimed = base_gap + 20.0;
    assert!((claimed - 25.0).abs() < 1e-12);
    // Canonical guard evidence AT the final offset 35:
    let actual = signed_clearance::evidence_at(&l, &r, 0.0, 0.0, 35.0).unwrap();
    assert!((actual.clearance.min_gap - -5.0).abs() < 1e-12, "actual gap {}", actual.clearance.min_gap);
    assert!(actual.interval_hit);
    assert!(actual.collides());
    assert!(claimed != actual.clearance.min_gap,
        "clearance(d+t) != clearance(d)+t: membership flipped");
    // The primitive itself is right AT each placement: cells recomputed at 35
    // agree with the guard. The unsound step is the +t shift, not the cells.
    let cells35 = signed_clearance::clearance_cells_constant(&l, &r, 35.0);
    assert!((cells35[0].1 - -5.0).abs() < 1e-12);
}

/// Second layer (ruling: "clearance_cells_constant fallback YOK", still true
/// in v2): a wholly-reversed right interval has no facing left wall, so the
/// cells emit NO constraint (gmin stays infinite, no cell) while the guard's
/// pair_clearance wholly-reversed fallback measures the truthful signed -25.
/// Solver sees no coverage; the guard sees a collision, at the SAME distance.
#[test]
fn cells_constant_missing_reversed_fallback() {
    let l = profile("L", &[(30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let cells = signed_clearance::clearance_cells_constant(&l, &r, 15.0);
    assert!(cells.is_empty(), "no facing wall -> no cell -> solver no-coverage path");
    let ev = signed_clearance::evidence_at(&l, &r, 0.0, 0.0, 15.0).unwrap();
    assert!((ev.clearance.min_gap - -25.0).abs() < 1e-12, "guard gap {}", ev.clearance.min_gap);
    assert!(ev.collides());
}

/// The outward bracket is a numeric-contact repair only: from the true
/// 20-unit collision at offset 35, a 64-step representable budget must
/// exhaust. Exhaustion is "bounded search did not find a safe point" - a
/// computational resource outcome, NOT a semantic classification that the
/// collision is real (and never an automatic extension past 64).
#[test]
fn ulp_bracket_does_not_close_unit_scale_collision() {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let mut d = 35.0_f64;
    let mut found = None;
    for _ in 0..64 {
        d = next_up_outward(d).expect("finite placement");
        let ev = signed_clearance::evidence_at(&l, &r, 0.0, 0.0, d).unwrap();
        if !ev.collides() { found = Some(d); break; }
    }
    assert!(found.is_none(), "64 representable steps cannot repair a 20-unit collision");
    let still = signed_clearance::evidence_at(&l, &r, 0.0, 0.0, d).unwrap();
    assert!(still.collides());
}

/// next_up_outward regression (chief: sign-aware, zero special, nan/inf
/// guard). The naive from_bits(v.to_bits()+1) steps NEGATIVE values further
/// negative (inward); the helper must step every finite value strictly up.
#[test]
fn next_up_outward_sign_aware_contract() {
    assert_eq!(next_up_outward(0.0), Some(f64::from_bits(1)));
    assert_eq!(next_up_outward(-0.0), Some(f64::from_bits(1)));
    assert_eq!(next_up_outward(f64::NAN), None);
    assert_eq!(next_up_outward(f64::INFINITY), None);
    assert_eq!(next_up_outward(f64::NEG_INFINITY), None);
    for &v in &[306.2705522639156, 1.0, 5e-324, -1.0, -306.2705522639156,
                -5e-324, -1.7976931348623157e308, 1.7976931348623155e308] {
        let u = next_up_outward(v).expect("finite input");
        assert!(u > v, "next_up_outward({v}) = {u} is not strictly greater");
        assert_eq!(Some(u), if v == 0.0 { Some(f64::from_bits(1)) } else { Some(v.next_up()) },
            "helper must match std next_up on finite input");
    }
    let naive = f64::from_bits((-1.0_f64).to_bits() + 1);
    assert!(naive < -1.0);
    assert!(next_up_outward(-1.0).unwrap() > -1.0);
    assert_eq!(next_up_outward(f64::MAX), None);
}
