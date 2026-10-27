//! W10 MONA-FITSEARCH integration gate: closed-gate bit-identity against the
//! incumbent fitter, open-gate validity and determinism, and the measured
//! (not assumed) parity/divergence of BaselineObjective against fit_run.
//! Pure-math fixtures, no external files.
use kni_core::cubic_fit::{adjacent_chord_tangents, fit_run, FitOutcome, FitPolicy};
use kni_core::fit_search::{
    fit_run_search, fit_run_search_reported, BaselineObjective, FitSearchPolicy, FIT_SEARCH_OFF,
    FIT_SEARCH_ON,
};
use kni_core::reference_slice::Point;

fn p(x: f64, y: f64) -> Point { Point { x, y } }

fn same_outcome(a: &FitOutcome, b: &FitOutcome) -> bool {
    match (a, b) {
        (FitOutcome::Fitted { controls: ca, parameters: ua, max_squared_error: ma },
         FitOutcome::Fitted { controls: cb, parameters: ub, max_squared_error: mb }) =>
            ca.iter().zip(cb.iter()).all(|(x, y)| x.x.to_bits() == y.x.to_bits() && x.y.to_bits() == y.y.to_bits())
            && ua.len() == ub.len() && ua.iter().zip(ub.iter()).all(|(x, y)| x.to_bits() == y.to_bits())
            && ma.to_bits() == mb.to_bits(),
        (FitOutcome::SplitUnresolved { sample_index: sa, stop: ta },
         FitOutcome::SplitUnresolved { sample_index: sb, stop: tb }) => sa == sb && ta == tb,
        (FitOutcome::InvalidInput, FitOutcome::InvalidInput) => true,
        _ => false,
    }
}

/// Fixture battery across the classes the fitter sees: smooth arcs at two
/// resolutions, curvature sign change, near-collinear, exact-collinear,
/// high-curvature hook, tiny arc, zig-zag under tolerance.
fn battery() -> Vec<Vec<Point>> {
    let mut v: Vec<Vec<Point>> = Vec::new();
    for (r, n) in [(200., 9usize), (50., 25), (1000., 33)] {
        v.push((0..n).map(|i| {
            let t = i as f64 / (n - 1) as f64 * std::f64::consts::FRAC_PI_2;
            p(r * t.cos(), r * t.sin())
        }).collect());
    }
    v.push((0..17).map(|i| { let t = i as f64 / 16.; p(300. * t, 80. * (t * std::f64::consts::PI).sin()) }).collect());
    v.push(vec![p(0., 0.), p(1., 0.1), p(2., -0.1), p(3., 0.)]);
    v.push(vec![p(0., 0.), p(10., 0.), p(20., 0.), p(30., 0.)]);
    v.push(vec![p(0., 0.), p(0.4, 3.), p(0.8, 0.)]);
    v.push(vec![p(0., 0.), p(1., 1.), p(2., 0.3), p(3., 1.), p(4., 0.)]);
    v.push(vec![p(0., 0.), p(2., 0.4), p(4., -0.4), p(6., 0.4), p(8., 0.)]);
    v
}

const POLICIES: [FitPolicy; 3] = [
    FitPolicy { squared_error: 0.25, max_refits: 6 },
    FitPolicy { squared_error: 1.0e-9, max_refits: 8 },
    FitPolicy { squared_error: 1.0e9, max_refits: 2 },
];

#[test]
fn closed_gate_bit_identity_sweep() {
    for pol in POLICIES {
        for pts in battery() {
            let Some((lt, rt)) = adjacent_chord_tangents(&pts) else { continue };
            let inc = fit_run(&pts, lt, rt, &pol);
            let got = fit_run_search(&pts, lt, rt, &pol, &FIT_SEARCH_OFF, &BaselineObjective);
            assert!(same_outcome(&inc, &got), "closed gate diverged on {pts:?}");
            let (_, rep) = fit_run_search_reported(&pts, lt, rt, &pol, &FIT_SEARCH_OFF, &BaselineObjective);
            assert!(rep.is_none());
        }
    }
}

#[test]
fn open_gate_validity_and_determinism_sweep() {
    for pol in POLICIES {
        for pts in battery() {
            let Some((lt, rt)) = adjacent_chord_tangents(&pts) else { continue };
            let (a, ra) = fit_run_search_reported(&pts, lt, rt, &pol, &FIT_SEARCH_ON, &BaselineObjective);
            let (b, _) = fit_run_search_reported(&pts, lt, rt, &pol, &FIT_SEARCH_ON, &BaselineObjective);
            assert!(same_outcome(&a, &b), "open gate nondeterministic");
            let rep = ra.expect("report");
            assert!(rep.candidates_generated >= 1 && rep.candidates_generated <= 2);
            assert!(rep.selected < rep.candidates_generated);
            if let FitOutcome::Fitted { max_squared_error, .. } = a {
                assert!(max_squared_error <= pol.squared_error, "fitted outcome over tolerance");
                assert_eq!(rep.matches_incumbent.is_some(), true);
            }
        }
    }
}

/// Measurement, not a gate: how often does the open gate with the incumbent
/// rule select the incumbent outcome on this battery? Reported in the
/// delivery note; divergence is expected whenever the non-picked map's
/// refit trajectory ends below the picked one's dense excursion.
#[test]
fn baseline_parity_is_measured() {
    let mut total = 0usize; let mut parity = 0usize;
    for pol in POLICIES {
        for pts in battery() {
            let Some((lt, rt)) = adjacent_chord_tangents(&pts) else { continue };
            let inc = fit_run(&pts, lt, rt, &pol);
            let (got, _) = fit_run_search_reported(&pts, lt, rt, &pol, &FIT_SEARCH_ON, &BaselineObjective);
            total += 1;
            if same_outcome(&inc, &got) { parity += 1; } else {
                eprintln!("divergence: policy {pol:?} fixture {:?}", pts.first());
            }
        }
    }
    eprintln!("W10 baseline parity: {parity}/{total}");
    // Parity count is a bench datum (W13), not a ship gate: the open gate is
    // a different, documented selection (terminal-state ranking across both
    // trajectories vs incumbent's initial-solve pick). The gate here is that
    // the search never collapses onto a non-incumbent outcome everywhere.
    assert!(parity * 2 >= total, "baseline parity collapsed: {parity}/{total}");
}

#[test]
fn gate_constant_default_is_closed() {
    assert_eq!(FitSearchPolicy::default(), FIT_SEARCH_OFF);
}

/// Measured Paul New period arc 0 (the same fixture cubic_fit pins for the
/// damped rescue): the all-or-nothing reparametrisation fails
/// (CandidateFailed) and the incumbent bottoms out unresolved. The open-gate
/// trajectory's damped fallback must resolve the SAME arc under the SAME
/// bound and budget (fewer splits = node economy, lower residual), while the
/// closed gate stays bit-identical to the incumbent by construction.
#[test]
fn open_gate_trajectory_survives_one_bad_newton_step() {
    let pts = vec![
        p(700.5284365239951, 0.0011130230473815556),
        p(700.5276576403832, 999.5472654835204),
        p(700.0891265597148, 999.9857965641887),
        p(0.44563279857397503, 999.9928982820943),
        p(0.008030624145048803, 999.9828417402697),
    ];
    let (lt, rt) = adjacent_chord_tangents(&pts).unwrap();
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    // Receipt: the incumbent abandons this arc (CandidateFailed).
    let inc = fit_run(&pts, lt, rt, &policy);
    assert!(matches!(inc, FitOutcome::SplitUnresolved { .. }), "incumbent must still abandon: {inc:?}");
    // Closed gate: bit-identical delegation, no search report.
    let (closed, rep) = fit_run_search_reported(&pts, lt, rt, &policy, &FIT_SEARCH_OFF, &BaselineObjective);
    assert!(rep.is_none(), "closed gate must not emit a search report");
    assert!(same_outcome(&closed, &inc), "closed gate must stay bit-identical");
    // Open gate: damped fallback inside the trajectory resolves the arc
    // under the same accept bound and budget - no split requested.
    let (open, rep) = fit_run_search_reported(&pts, lt, rt, &policy, &FIT_SEARCH_ON, &BaselineObjective);
    match open {
        FitOutcome::Fitted { parameters, max_squared_error, .. } => {
            assert!(max_squared_error <= policy.squared_error, "resolved fit exceeds its own bound: {max_squared_error}");
            assert!(parameters.windows(2).all(|w| w[0] <= w[1]), "parameters must stay monotone");
        }
        other => panic!("open-gate trajectory must resolve the measured arc via the damped fallback, got {other:?}"),
    }
    assert!(rep.is_some(), "open gate must emit a search report");
}
