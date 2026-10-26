//! Sensitivity of the gate verdict to its two declared choices: the upper
//! quantile (0.9) and the group floor (MIN_FOLD_GROUPS). The tests show where
//! the verdict changes, so a change of either choice is visible as a test
//! failure that names the scenario.

use kni_learning::gate::{evaluate_font, production_gate, try_quantile, MIN_FOLD_GROUPS};
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

fn family(f: &str) -> Option<String> {
    Some(f[..1].to_string())
}

/// Nine cells the prior misses by 1 and one cell it misses by 50; the baseline
/// misses every cell by 10. The default gate (median and p90) opens, because p90
/// of ten values is rank 9 and ignores the single worst cell.
fn tail_cells() -> Vec<Cell> {
    let mut cells: Vec<Cell> = (0..9).map(|_| Cell { key: key(), observed: 101.0, baseline_pred: 111.0 }).collect();
    cells.push(Cell { key: key(), observed: 150.0, baseline_pred: 160.0 });
    cells
}

#[test]
fn default_gate_opens_when_only_the_single_worst_cell_is_bad() {
    let s = store(&[("f1", 100.0), ("f2", 100.0), ("f3", 100.0)]);
    let pri = Priors::build(&s.records, Some("f1"));
    let r = evaluate_font(&pri, "f1", &tail_cells());
    assert_eq!(r.scored, 10);
    assert!(r.open, "{:?}", r);
}

/// The same errors under other upper quantiles, with the same rule as
/// `evaluate_font` (prior beats baseline on the median and on the tail). The
/// verdict flips between 0.9 and 0.91: from n = 10 up the worst cell enters
/// the tail as soon as the rank passes 9.
#[test]
fn verdict_flips_when_the_tail_quantile_reaches_the_worst_cell() {
    let pe: Vec<f64> = (0..9).map(|_| 1.0).chain(std::iter::once(50.0)).collect();
    let be: Vec<f64> = (0..10).map(|_| 10.0).collect();
    let verdict = |q: f64| {
        let m = try_quantile(&pe, 0.5).unwrap() < try_quantile(&be, 0.5).unwrap();
        m && try_quantile(&pe, q).unwrap() < try_quantile(&be, q).unwrap()
    };
    for q in [0.5, 0.8, 0.9] {
        assert!(verdict(q), "q={q}");
    }
    for q in [0.91, 0.95, 0.99, 1.0] {
        assert!(!verdict(q), "q={q}");
    }
}

/// With every fold open on its own, the gate opens exactly when the number of
/// groups reaches MIN_FOLD_GROUPS; below it the floor alone keeps it closed.
#[test]
fn group_floor_alone_decides_when_every_fold_is_open() {
    for k in 2..=5usize {
        let names: Vec<String> = (0..k).flat_map(|i| (1..=2).map(move |j| format!("{}{}", (b'a' + i as u8) as char, j))).collect();
        let fonts: Vec<(&str, f64)> = names.iter().map(|n| (n.as_str(), 100.0)).collect();
        let s = store(&fonts);
        let cells = |_: &str| vec![Cell { key: key(), observed: 100.0, baseline_pred: 0.0 }];
        let (open, groups) = production_gate(&s, &cells, &family).unwrap();
        assert_eq!(groups.len(), k);
        assert!(groups.iter().all(|g| g.report.open), "k={k} {:?}", groups);
        assert_eq!(open, k >= MIN_FOLD_GROUPS, "k={k}");
    }
}

/// Adding a fourth group to an open three-group gate leaves it open, so the
/// floor is not a hidden cap on the number of groups.
#[test]
fn more_groups_than_the_floor_stay_open() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("b2", 100.0), ("c1", 100.0), ("c2", 100.0), ("d1", 100.0), ("d2", 100.0)]);
    let cells = |_: &str| vec![Cell { key: key(), observed: 100.0, baseline_pred: 0.0 }];
    let (open, groups) = production_gate(&s, &cells, &family).unwrap();
    assert!(open);
    assert_eq!(groups.len(), 4);
}
