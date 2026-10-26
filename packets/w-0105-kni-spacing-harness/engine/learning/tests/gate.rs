use kni_learning::gate::*;
use kni_learning::prior::Cell;
use kni_learning::*;

fn obs(font: &str, bucket: &str, mean: f64) -> Obs {
    Obs {
        key: vec![("wall".into(), bucket.into())], n: 1, sum: mean, sumsq: mean * mean,
        prov: Provenance { font_id: font.into(), run_id: "r".into(), receipt_id: "x".into(), tested_sha: "s".into(), declared_cap_u: 1.0, measured_cap_px: 1.0, certified: true },
    }
}
fn cell(b: &str, observed: f64) -> Cell {
    Cell { key: vec![("wall".into(), b.into())], observed, baseline_pred: 0.0 }
}

/// Each font is its own group, which is the per-font fold the gate used before
/// the group argument existed.
fn per_font(f: &str) -> Option<String> {
    Some(f.to_string())
}

fn run_gate(s: &Store, cells_of: &dyn Fn(&str) -> Vec<Cell>) -> (bool, Vec<GroupReport>) {
    production_gate(s, cells_of, &per_font).unwrap()
}

#[test]
fn quantiles_nearest_rank() {
    let v: Vec<f64> = (1..=10).map(|x| x as f64).collect();
    assert_eq!(try_quantile(&v, 0.5), Ok(5.0));
    assert_eq!(try_quantile(&v, 0.9), Ok(9.0));
}

fn two_font_store(prior_mean: f64) -> Store {
    let mut s = Store::new(1, &["wall"]).unwrap();
    for f in ["a", "b", "c"] {
        for b in ["x", "y", "z"] {
            s.append(obs(f, b, prior_mean)).unwrap();
        }
    }
    s
}

#[test]
fn opens_only_when_beating_baseline_on_median_and_p90() {
    let s = two_font_store(10.0);
    let good = |_: &str| vec![cell("x", 11.0), cell("y", 9.0), cell("z", 12.0)]; // prior err ~1-2, baseline ~10
    let (open, r) = run_gate(&s, &good);
    assert!(open, "{r:?}");
    let bad = |_: &str| vec![cell("x", 0.5), cell("y", 0.4), cell("z", 0.3)]; // baseline (0) is better
    assert!(!run_gate(&s, &bad).0);
}

#[test]
fn must_win_both_quantiles() {
    let s = two_font_store(10.0);
    // median favors prior, p90 favors baseline (one near-zero cell the prior misses)
    let mix = |_: &str| vec![cell("x", 6.0), cell("y", 6.0), cell("z", 0.0)];
    let (open, r) = run_gate(&s, &mix);
    assert!(!open, "{r:?}");
}

#[test]
fn unseen_cells_never_open_the_gate() {
    let s = two_font_store(10.0);
    let only_unseen = |_: &str| vec![cell("nope", 10.0)];
    let (open, r) = run_gate(&s, &only_unseen);
    assert!(!open);
    assert!(r.iter().all(|x| x.report.scored == 0 && x.report.unseen == 1));
}

#[test]
fn single_font_or_empty_store_is_closed() {
    let mut s = Store::new(1, &["wall"]).unwrap();
    s.append(obs("a", "x", 1.0)).unwrap();
    assert!(!run_gate(&s, &|_| vec![cell("x", 1.0)]).0);
    let e = Store::new(1, &["wall"]).unwrap();
    assert!(!run_gate(&e, &|_| vec![]).0);
}

#[test]
fn baseline_is_computed_not_stored() {
    // same prior, baseline_pred changes -> verdict changes (no embedded 19u/62u)
    let s = two_font_store(10.0);
    let cells = |_: &str| vec![Cell { key: vec![("wall".into(), "x".into())], observed: 11.0, baseline_pred: 10.9 }];
    assert!(!run_gate(&s, &cells).0);
    let cells2 = |_: &str| vec![Cell { key: vec![("wall".into(), "x".into())], observed: 11.0, baseline_pred: 0.0 }];
    assert!(run_gate(&s, &cells2).0);
}

#[test]
fn two_fonts_cannot_validate_each_other() {
    // leaving one of two fonts out leaves a single font: no priors, gate closed
    let mut s = Store::new(1, &["wall"]).unwrap();
    for f in ["a", "b"] {
        s.append(obs(f, "x", 10.0)).unwrap();
    }
    assert!(!run_gate(&s, &|_| vec![cell("x", 11.0)]).0);
}
