//! Tests for the leave-group-out gate: ungrouped fonts, build_excluding, sibling
//! leakage. The numbers in the sibling scenario are worked out in the comment
//! on that test.

use kni_learning::gate::{production_gate, GateError};
use kni_learning::prior::Key;
use kni_learning::store::{Obs, Provenance, Store};
use kni_learning::{Cell, Priors};

fn key() -> Key {
    vec![("shape".to_string(), "a".to_string())]
}

fn obs(font: &str, mean: f64) -> Obs {
    Obs {
        key: key(),
        n: 1,
        sum: mean,
        sumsq: mean * mean,
        prov: Provenance {
            font_id: font.to_string(),
            run_id: "r".to_string(),
            receipt_id: "c".to_string(),
            tested_sha: "s".to_string(),
            declared_cap_u: 700.0,
            measured_cap_px: 70.0,
            certified: true,
        },
    }
}

fn store(fonts: &[(&str, f64)]) -> Store {
    let mut s = Store::new(1, &["shape"]).unwrap();
    for (f, m) in fonts {
        s.append(obs(f, *m)).unwrap();
    }
    s
}

#[test]
fn ungrouped_font_is_a_typed_error() {
    let s = store(&[("f1", 10.0), ("f2", 20.0), ("f3", 30.0)]);
    let cells = |_: &str| -> Vec<Cell> { vec![] };
    let group = |f: &str| if f == "f2" { None } else { Some(f.to_string()) };
    assert_eq!(production_gate(&s, &cells, &group), Err(GateError::UngroupedFont("f2".to_string())));
}

#[test]
fn build_excluding_matches_build_for_one_font() {
    let s = store(&[("f1", 10.0), ("f2", 20.0), ("f3", 30.0), ("f4", 5.0)]);
    assert_eq!(Priors::build(&s.records, Some("f2")), Priors::build_excluding(&s.records, &|f| f == "f2"));
    assert_eq!(Priors::build(&s.records, None), Priors::build_excluding(&s.records, &|_| false));
}

/// Three families of two siblings each. Family means: x 10, y 100, z 100.
/// Per-font folds (identity grouping): x1 held out -> prior 82, error 72 against
/// a baseline error of 80; y1 held out -> prior 64, error 36 against 40; z the
/// same. Every report is open. Per-family folds: X held out -> prior 100, error
/// 90 against 80 (closed); Y held out -> prior 55, error 45 against 40 (closed).
#[test]
fn sibling_leakage_opens_the_per_font_gate_but_not_the_per_group_gate() {
    let fonts = [("x1", 10.0), ("x2", 10.0), ("y1", 100.0), ("y2", 100.0), ("z1", 100.0), ("z2", 100.0)];
    let s = store(&fonts);
    let cells = |f: &str| {
        let (obs, base) = if f.starts_with('x') { (10.0, 90.0) } else { (100.0, 60.0) };
        vec![Cell { key: key(), observed: obs, baseline_pred: base }]
    };
    let per_font = |f: &str| Some(f.to_string());
    let per_family = |f: &str| Some(f[..1].to_string());
    let (open_font, rep_font) = production_gate(&s, &cells, &per_font).unwrap();
    assert!(open_font, "{:?}", rep_font);
    let (open_family, rep_family) = production_gate(&s, &cells, &per_family).unwrap();
    assert!(!open_family, "{:?}", rep_family);
    assert_eq!(rep_family.len(), 3);
    assert!(rep_family.iter().all(|r| !r.report.open));
}
