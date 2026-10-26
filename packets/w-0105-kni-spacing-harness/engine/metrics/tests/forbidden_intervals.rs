//! Exact forbidden-interval constraint tests (J-fix layer 1).
//! Regression-first partner of cells_residual_divergence.rs: (a) pins the
//! counterexample's constraint set, (b) pins guard agreement by construction.
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::signed_clearance::{self, ForbiddenError, feasible_components,
    forbidden_residual_intervals, validate_intervals};

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
        profile_method: "forbidden-intervals-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// Chief's 20-unit counterexample constraint set: L [0,10],[30,40], R [0,5],
/// base 15 -> forbidden open residuals (-20,-5) and (10,25). Residual 20
/// (the cells+residual claim 'gap 25') sits INSIDE (10,25): forbidden.
#[test]
fn counterexample_intervals_exact() {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let iv = forbidden_residual_intervals(&l, &r, 15.0).expect("intervals");
    assert_eq!(iv, vec![(-20.0, -5.0), (10.0, 25.0)]);
    assert!(iv.iter().any(|&(a, b)| 20.0 > a && 20.0 < b), "residual 20 must be forbidden");
    assert!(!iv.iter().any(|&(a, b)| 0.0 > a && 0.0 < b), "base residual 0 must be feasible");
    let comp = feasible_components(-30.0, 30.0, &iv).expect("components");
    assert_eq!(comp, vec![(-30.0, -20.0), (-5.0, 10.0), (25.0, 30.0)]);
}

/// Guard agreement by construction: forbidden membership at residual t
/// equals interval_collision at placement base+t, sampled on a grid plus
/// exact interval edges (touching legal at edges).
#[test]
fn forbidden_membership_matches_interval_collision() {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)]);
    let r = profile("R", &[(0.0, 5.0)]);
    let base = 15.0;
    let iv = forbidden_residual_intervals(&l, &r, base).expect("intervals");
    let mut ts: Vec<f64> = (-60..=80).map(|k| k as f64 * 0.5).collect();
    for &(a, b) in &iv { ts.extend([a, b]); } // exact edges
    for t in ts {
        let forbidden = iv.iter().any(|&(a, b)| t > a && t < b);
        let hit = signed_clearance::interval_collision(&l, &r, 0.0, 0.0, base + t);
        assert_eq!(forbidden, hit, "membership mismatch at t={t}");
    }
}

/// Touching is legal: adjacent open intervals are not merged, the shared
/// boundary point survives as a feasible zero-length component.
#[test]
fn adjacent_intervals_keep_legal_touching_point() {
    let iv = vec![(0.0, 1.0), (1.0, 2.0)];
    let comp = feasible_components(0.0, 2.0, &iv).expect("components");
    assert_eq!(comp, vec![(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)]);
}

/// Typed outcomes: no common span and non-finite input are typed failures,
/// never an empty-constraint pass.
#[test]
fn typed_outcomes() {
    let l = profile("L", &[(0.0, 10.0)]);
    let empty_right = profile("R", &[]);
    assert_eq!(forbidden_residual_intervals(&l, &empty_right, 0.0),
               Err(ForbiddenError::NoCommonSpan));
    assert_eq!(forbidden_residual_intervals(&l, &l, f64::NAN),
               Err(ForbiddenError::NonFinite));
    // No feasible residual in domain -> empty components (typed hold upstream).
    let iv = vec![(0.0, 10.0)];
    assert_eq!(feasible_components(1.0, 9.0, &iv), Ok(Vec::<(f64, f64)>::new()));
}

/// Domain invariants: i16/i32 export-bounded callers need bounded domains;
/// non-finite or inverted domains produce no components.
#[test]
fn domain_invariants() {
    assert_eq!(feasible_components(f64::NAN, 1.0, &[]), Err(ForbiddenError::NonFinite));
    assert_eq!(feasible_components(2.0, 1.0, &[]), Ok(Vec::<(f64, f64)>::new()));
    assert_eq!(feasible_components(0.0, 10.0, &[]), Ok(vec![(0.0, 10.0)]));
}

/// Chief 23:19 (1): a point-only feasible component between two open
/// intervals sharing an endpoint is a legal candidate and must survive.
#[test]
fn point_only_component_survives() {
    let iv = vec![(0.0, 1.0), (1.0, 2.0)];
    let comp = feasible_components(0.0, 2.0, &iv).expect("components");
    assert!(comp.contains(&(1.0, 1.0)), "point-only component [1,1] lost: {comp:?}");
}

/// Chief 23:19 (2): every component endpoint is proven legal by the ACTUAL
/// forbidden-membership check, not by construction alone.
#[test]
fn component_endpoints_proven_legal_by_membership() {
    let iv = vec![(-20.0, -5.0), (10.0, 25.0), (25.0, 40.0)];
    let comp = feasible_components(-30.0, 45.0, &iv).expect("components");
    assert!(comp.contains(&(25.0, 25.0)), "shared endpoint (25,25) lost: {comp:?}");
    for &(a, b) in &comp {
        assert!(!signed_clearance::is_forbidden(a, &iv), "component start {a} forbidden");
        assert!(!signed_clearance::is_forbidden(b, &iv), "component end {b} forbidden");
    }
    // And every strictly-interior residual of a forbidden interval is absent
    // from every component.
    for &(a, b) in &iv {
        let mid = a + (b - a) / 2.0;
        assert!(signed_clearance::is_forbidden(mid, &iv));
        assert!(!comp.iter().any(|&(x, y)| mid >= x && mid <= y), "forbidden {mid} inside a component");
    }
}

/// Chief 23:19 hardening: malformed interval lists are rejected, never trusted.
#[test]
fn malformed_interval_lists_rejected() {
    assert_eq!(validate_intervals(&[(f64::NAN, 1.0)]), Err(ForbiddenError::NonFinite));
    assert_eq!(validate_intervals(&[(1.0, 1.0)]), Err(ForbiddenError::MalformedIntervals)); // zero-width
    assert_eq!(validate_intervals(&[(2.0, 1.0)]), Err(ForbiddenError::MalformedIntervals)); // inverted
    assert_eq!(validate_intervals(&[(5.0, 9.0), (0.0, 1.0)]), Err(ForbiddenError::MalformedIntervals)); // unsorted
    assert_eq!(feasible_components(0.0, 10.0, &[(1.0, 1.0)]), Err(ForbiddenError::MalformedIntervals));
    assert!(validate_intervals(&[]).is_ok());
}
