//! Dar patch tests (NON-VACUOUS): typed SpaceStatus replaces the W_target
//! space fallback. Fixture = the r7 wired fixture: a measured
//! (straight, diagonal) class pair whose class median (20.0) differs from
//! the straight anchor W_s (25.0, from measured sidebearings 12/13), so
//! BOTH ordered directions solve to a REAL residual -5.0 and are EMITTED
//! (L->R origin 60.0, R->L origin 25.0, wall_gap 17.0). A straight|straight
//! fixture would be vacuous here (residual 0 -> below-epsilon exclusion ->
//! empty pair lists prove nothing).
//!
//! (1) measured_space_advance None + space profile present -> NO space
//!     emission, typed MissingEvidence (candidate = W_target anchor 25.0,
//!     diagnostic only); the 2 emitted pairs are bit-identical to the same
//!     solve without the space profile; the FULL pair ledger (id, class,
//!     reason code, residual value + finite state) is identical.
//! (2) Some(finite, >= 0) -> space glyph emitted with the exact measured
//!     advance; pairs and ledger still identical to the no-space baseline.
//!
//! COMPLETE vs SPACE GATE (explicit): `complete` covers PAIR SOLVING only
//! (excluded_pairs / numeric / geometric holds). MissingEvidence does NOT
//! force complete=false: a solution can be pair-complete AND carry no
//! space glyph. Full-output consumers must therefore gate on space_status
//! SEPARATELY (pipeline stage2 does: MissingEvidence refuses full output).
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    solve_spacing, FontContext, MeasuredPair, MeasuredSidebearing, SpaceStatus,
    SpacingPolicy, SpacingSolution,
};

const EPS: f64 = 1e-9;

fn profile(id: &str, ink: &[(f64, f64)], rows: usize) -> OutlineProfile {
    let mk = |y: f64| ScanRow { y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect() };
    let xmin = ink.iter().map(|&(l, _)| l).fold(f64::INFINITY, f64::min);
    let xmax = ink.iter().map(|&(_, r)| r).fold(f64::NEG_INFINITY, f64::max);
    let (x0, x1) = if xmin <= xmax { (xmin, xmax) } else { (0.0, 0.0) };
    OutlineProfile {
        glyph_id: id.to_string(), source_pin: format!("pin-{id}"), upm: 1000,
        origin: [0.0, 0.0], rows: (0..rows).map(|i| mk(i as f64)).collect(),
        bounds: [x0, 0.0, x1, rows as f64],
        ink_area: rows as f64 * ink.iter().map(|&(l, r)| r - l).sum::<f64>(),
        counter_area: 0.0, open_left: 0.0, open_right: 0.0,
        profile_method: "space-status-dar-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// r7 wired fixture, verbatim geometry: L straight sides; R left wall
/// drifts 0,2,4,6 across 4 rows (constant width 5) -> (straight, diagonal).
fn wired_fixture() -> (OutlineProfile, OutlineProfile) {
    let l = profile("L", &[(0.0, 10.0), (30.0, 40.0)], 4);
    let mk = |y: f64, off: f64| ScanRow { y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: vec![InkInterval { left: off, right: off + 5.0 }] };
    let r = OutlineProfile {
        glyph_id: "R".into(), source_pin: "pin-R-wired".into(), upm: 1000,
        origin: [0.0, 0.0], rows: (0..4).map(|i| mk(i as f64, 2.0 * i as f64)).collect(),
        bounds: [0.0, 0.0, 11.0, 4.0], ink_area: 20.0, counter_area: 0.0,
        open_left: 0.0, open_right: 0.0,
        profile_method: "space-status-dar-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    };
    (l, r)
}

/// Inkless space profile (present in solver input, carries no ink).
fn space_profile() -> OutlineProfile {
    let mk = |y: f64| ScanRow { y, weight: 1.0, span_lo: y, span_hi: y + 1.0, ink: vec![] };
    OutlineProfile {
        glyph_id: "space".into(), source_pin: "pin-space".into(), upm: 1000,
        origin: [0.0, 0.0], rows: (0..4).map(|i| mk(i as f64)).collect(),
        bounds: [0.0, 0.0, 10.0, 4.0], ink_area: 0.0,
        counter_area: 0.0, open_left: 0.0, open_right: 0.0,
        profile_method: "space-status-dar-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// Wired context: W_s = median(12+13) = 25.0 from measured sidebearings;
/// both measured directions gap 20.0 (the real residual source).
fn ctx_wired(space_advance: Option<f64>, with_space: bool) -> FontContext {
    FontContext {
        x_height: None, cap_height: None, baseline: None,
        measured_sidebearings: vec![
            MeasuredSidebearing { glyph_id: "L".into(), lsb: 12.0, rsb: 13.0 },
            MeasuredSidebearing { glyph_id: "R".into(), lsb: 12.0, rsb: 13.0 }],
        measured_pairs: vec![
            MeasuredPair { left: "L".into(), right: "R".into(), gap: 20.0 },
            MeasuredPair { left: "R".into(), right: "L".into(), gap: 20.0 }],
        measured_space_advance: space_advance,
        glyph_codepoints: if with_space { vec![
            ("L".into(), 0x4C), ("R".into(), 0x52), ("space".into(), 0x20)]
        } else { vec![("L".into(), 0x4C), ("R".into(), 0x52)] },
    }
}

/// Hard emission gate (verbatim r7 expectations): both ordered directions
/// emitted with the exact fixture-derived values.
fn assert_wired_pairs_emitted(sol: &SpacingSolution) {
    assert_eq!(sol.pairs.len(), 2,
        "wired fixture must emit EXACTLY the 2 ordered pairs, got {}", sol.pairs.len());
    for (left, right, origin, wall_gap, advance) in [
        ("L", "R", 60.0, 17.0, 65.0),
        ("R", "L", 25.0, 17.0, 30.0),
    ] {
        let p = sol.pairs.iter().find(|p| p.left == left && p.right == right)
            .unwrap_or_else(|| panic!("ordered pair {left}->{right} must be EMITTED"));
        let g = sol.glyphs.iter().find(|g| g.glyph_id == left)
            .unwrap_or_else(|| panic!("{left} in solution"));
        assert!((g.advance - advance).abs() < EPS,
            "{left} advance {} != fixture-derived {advance}", g.advance);
        assert!((p.origin_distance - origin).abs() < EPS,
            "{left}->{right} origin {} != fixture-derived {origin}", p.origin_distance);
        assert!((p.wall_gap - wall_gap).abs() < EPS,
            "{left}->{right} wall_gap {} != fixture-derived {wall_gap}", p.wall_gap);
        let residual = p.origin_distance - g.advance;
        assert!((residual - (-5.0)).abs() < EPS,
            "{left}->{right} residual {residual} != fixture-derived -5.0");
        assert!(residual.abs() >= 2.0,
            "{left}->{right} residual {residual} must be a real adjustment");
    }
}

/// Full ledger identity: (left, right, class, reason code, tier, residual
/// value, residual finite state, kern_units). Not a length check - a
/// row-by-row identity comparison.
fn ledger_identity(sol: &SpacingSolution)
    -> Vec<(String, String, String, &'static str, u8, f64, bool, Option<f64>)> {
    sol.pair_ledger.iter().map(|r| (
        r.left.clone(), r.right.clone(), r.class.clone(), r.reason.code(),
        r.tier, r.residual, r.residual.is_finite(), r.kern_units,
    )).collect()
}

/// NaN-safe ledger identity assert: residual is NaN on rows where no
/// residual exists (e.g. self pairs); NaN != NaN under f64 PartialEq, so
/// rows compare field-wise with (a == b) || (a.is_nan() && b.is_nan()).
fn assert_ledger_identical(a: &SpacingSolution, b: &SpacingSolution) {
    let (la, lb) = (ledger_identity(a), ledger_identity(b));
    assert_eq!(la.len(), lb.len(), "ledger length {} != {}", la.len(), lb.len());
    for (ra, rb) in la.iter().zip(lb.iter()) {
        let num_eq = |x: f64, y: f64| x == y || (x.is_nan() && y.is_nan());
        let opt_eq = |x: Option<f64>, y: Option<f64>| match (x, y) {
            (Some(u), Some(v)) => num_eq(u, v),
            (None, None) => true,
            _ => false,
        };
        assert!(ra.0 == rb.0 && ra.1 == rb.1 && ra.2 == rb.2 && ra.3 == rb.3
            && ra.4 == rb.4 && num_eq(ra.5, rb.5) && ra.6 == rb.6 && opt_eq(ra.7, rb.7),
            "ledger row mismatch:\n  left:  {ra:?}\n  right: {rb:?}");
    }
}

#[test]
fn none_measured_space_advance_no_emit_typed_missing_pairs_unchanged() {
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let (l, r) = wired_fixture();
    let baseline = solve_spacing(&[l.clone(), r.clone()],
        Some(&ctx_wired(None, false)), &policy).expect("solve without space");
    let (l2, r2) = wired_fixture();
    let with_space = solve_spacing(&[l2, r2, space_profile()],
        Some(&ctx_wired(None, true)), &policy).expect("solve with space");
    assert_eq!(with_space.space_status,
        SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 },
        "candidate = W_target anchor (W_s=25.0), diagnostic only");
    match with_space.space_status {
        SpaceStatus::MissingEvidence { candidate_diagnostic } =>
            assert!(candidate_diagnostic.is_finite(), "diagnostic candidate finite"),
        other => panic!("expected MissingEvidence, got {other:?}"),
    }
    assert!(!with_space.glyphs.iter().any(|g| g.glyph_id == "space"),
        "NO space glyph emission without a measured advance");
    // Non-vacuous pair identity: real residuals, exact expected values,
    // identical with and without the space profile.
    assert_wired_pairs_emitted(&baseline);
    assert_wired_pairs_emitted(&with_space);
    assert_ledger_identical(&with_space, &baseline);
    // COMPLETE vs SPACE GATE, explicit: pair-complete solution, no space
    // glyph. complete=true here covers pair solving ONLY; a full-output
    // consumer must still gate on space_status (MissingEvidence).
    assert!(baseline.complete, "wired fixture is pair-complete");
    assert_eq!(with_space.complete, baseline.complete,
        "space presence does not change pair completeness");
    assert!(with_space.complete,
        "pair-complete AND MissingEvidence: the two gates are separate");
}

#[test]
fn some_measured_space_advance_emitted_exact() {
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let (l, r) = wired_fixture();
    let baseline = solve_spacing(&[l.clone(), r.clone()],
        Some(&ctx_wired(None, false)), &policy).expect("solve without space");
    let (l2, r2) = wired_fixture();
    let sol = solve_spacing(&[l2, r2, space_profile()],
        Some(&ctx_wired(Some(30.0), true)), &policy).expect("solve with measured space");
    assert_eq!(sol.space_status, SpaceStatus::Measured { advance: 30.0 });
    let g = sol.glyphs.iter().find(|g| g.glyph_id == "space").expect("space glyph emitted");
    assert_eq!(g.advance, 30.0, "exact measured advance");
    assert_eq!((g.lsb, g.rsb), (0.0, 0.0));
    assert_wired_pairs_emitted(&sol);
    assert_ledger_identical(&sol, &baseline);
}
