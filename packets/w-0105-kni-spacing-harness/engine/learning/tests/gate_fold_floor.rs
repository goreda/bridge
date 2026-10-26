//! Fold floor test.

use kni_learning::gate::{production_gate, MIN_FOLD_GROUPS};
use kni_learning::prior::{Key, MIN_FOLD_FONTS};
use kni_learning::store::{Obs, Provenance, Store};
use kni_learning::Cell;

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
fn fold_floor_is_derived_and_two_fonts_never_open() {
    assert_eq!(MIN_FOLD_FONTS, 3);
    let s = store(&[("f1", 10.0), ("f2", 20.0)]);
    let cells = |f: &str| vec![Cell { key: key(), observed: if f == "f1" { 10.0 } else { 20.0 }, baseline_pred: 0.0 }];
    let group = |f: &str| Some(f.to_string());
    let (open, reports) = production_gate(&s, &cells, &group).unwrap();
    assert!(!open);
    assert!(reports.iter().all(|r| !r.report.open && r.report.scored == 0));
}


#[test]
fn two_groups_never_open_the_group_gate() {
    assert_eq!(MIN_FOLD_GROUPS, 3);
    let s = store(&[("a1", 10.0), ("a2", 10.0), ("b1", 20.0), ("b2", 20.0)]);
    let cells = |f: &str| vec![Cell { key: key(), observed: 10.0, baseline_pred: if f.starts_with('a') { 90.0 } else { 80.0 } }];
    let group = |f: &str| Some(f[..1].to_string());
    let (open, reports) = production_gate(&s, &cells, &group).unwrap();
    assert!(!open);
    assert_eq!(reports.len(), 2);
}
