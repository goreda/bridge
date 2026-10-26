//! Tests for the per-member reports of the grouped gate.

use kni_learning::gate::{production_gate, StatsError};
use kni_learning::prior::Key;
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

fn cell(observed: f64, baseline_pred: f64) -> Cell {
    Cell { key: key(), observed, baseline_pred }
}

fn unseen_cell() -> Cell {
    Cell { key: vec![("shape".to_string(), "never".to_string())], observed: 1.0, baseline_pred: 0.0 }
}

fn family(f: &str) -> Option<String> {
    Some(f[..1].to_string())
}

/// Member counts add up to the group report, for cells, scored and unseen, and
/// every member shares the same pooled total.
#[test]
fn member_counts_sum_to_the_group_report() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("c1", 100.0)]);
    let cells = |f: &str| match f {
        "a1" => vec![cell(100.0, 0.0), cell(100.0, 0.0), unseen_cell()],
        "a2" => vec![cell(100.0, 0.0), unseen_cell(), unseen_cell()],
        _ => vec![cell(100.0, 0.0)],
    };
    let (_, groups) = production_gate(&s, &cells, &family).unwrap();
    for g in &groups {
        let total = g.report.cells;
        assert_eq!(g.members.iter().map(|m| m.cells).sum::<usize>(), g.report.cells);
        assert_eq!(g.members.iter().map(|m| m.scored).sum::<usize>(), g.report.scored);
        assert_eq!(g.members.iter().map(|m| m.unseen).sum::<usize>(), g.report.unseen);
        assert!(g.members.iter().all(|m| m.total_cell_share == (m.cells, total)));
        assert!(g.members.iter().all(|m| m.scored_share == (m.scored, g.report.scored)));
        assert_eq!(g.members.len(), g.fonts.len());
    }
    let a = groups.iter().find(|g| g.group_id == "a").unwrap();
    assert_eq!((a.report.cells, a.report.scored, a.report.unseen), (6, 3, 3));
}

/// Group A has a1 with ten cells the prior gets right (baseline off by 100) and
/// a2 with one cell the prior misses by 60 (baseline off by 10). Pooled, group A
/// is open (prior median 0, p90 0 against baseline 100, 100); member a2 on its
/// own is not (60 against 10). The failure is reported and does not close A.
#[test]
fn failing_member_is_reported_while_the_group_stays_open() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("c1", 100.0)]);
    let cells = |f: &str| match f {
        "a1" => (0..10).map(|_| cell(100.0, 0.0)).collect(),
        "a2" => vec![cell(160.0, 150.0)],
        _ => vec![cell(100.0, 0.0)],
    };
    let (open, groups) = production_gate(&s, &cells, &family).unwrap();
    let a = groups.iter().find(|g| g.group_id == "a").unwrap();
    assert!(a.report.open, "{:?}", a.report);
    assert!(a.members[0].open, "{:?}", a.members[0]);
    assert!(!a.members[1].open, "{:?}", a.members[1]);
    assert_eq!(a.members[1].total_cell_share, (1, 11));
    assert!(open);
}

/// A member with no cells gives a closed report with zero counts, no statistics
/// and no refusal; it does not change the group report.
#[test]
fn empty_member_is_a_closed_zero_report() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("c1", 100.0)]);
    let cells = |f: &str| if f == "a2" { vec![] } else { vec![cell(100.0, 0.0)] };
    let (_, groups) = production_gate(&s, &cells, &family).unwrap();
    let a = groups.iter().find(|g| g.group_id == "a").unwrap();
    let m = &a.members[1];
    assert_eq!(m.font_id, "a2");
    assert_eq!((m.cells, m.scored, m.unseen), (0, 0, 0));
    assert!(m.prior.is_none() && m.baseline.is_none() && m.refusal.is_none());
    assert!(!m.open);
    assert_eq!(m.total_cell_share, (0, 1));
    assert_eq!(m.scored_share, (0, 1));
    assert_eq!(a.report.cells, 1);
}

/// Members follow the sorted font order and groups the sorted group order,
/// whatever order the store was filled in.
#[test]
fn order_is_deterministic() {
    let s = store(&[("c1", 100.0), ("b1", 100.0), ("a2", 100.0), ("a1", 100.0)]);
    let cells = |_: &str| vec![cell(100.0, 0.0)];
    let (_, groups) = production_gate(&s, &cells, &family).unwrap();
    let ids: Vec<&str> = groups.iter().map(|g| g.group_id.as_str()).collect();
    assert_eq!(ids, ["a", "b", "c"]);
    let a = &groups[0];
    assert_eq!(a.fonts, ["a1", "a2"]);
    assert_eq!(a.members.iter().map(|m| m.font_id.as_str()).collect::<Vec<_>>(), ["a1", "a2"]);
}

/// a1 has 3 cells of which 2 are scored, a2 has 3 cells of which 1 is scored.
/// Pooled: 6 cells, 3 scored. Both members share the same pooled totals.
#[test]
fn unequal_unseen_gives_different_scored_shares_and_equal_cell_shares() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("c1", 100.0)]);
    let cells = |f: &str| match f {
        "a1" => vec![cell(100.0, 0.0), cell(100.0, 0.0), unseen_cell()],
        "a2" => vec![cell(100.0, 0.0), unseen_cell(), unseen_cell()],
        _ => vec![cell(100.0, 0.0)],
    };
    let (_, groups) = production_gate(&s, &cells, &family).unwrap();
    let a = groups.iter().find(|g| g.group_id == "a").unwrap();
    assert_eq!(a.members[0].scored_share, (2, 3));
    assert_eq!(a.members[1].scored_share, (1, 3));
    assert_eq!(a.members[0].total_cell_share, (3, 6));
    assert_eq!(a.members[1].total_cell_share, (3, 6));
}

/// A group whose cells are all unseen scores nothing: scored shares are (0, 0),
/// no refusal, closed.
#[test]
fn all_unseen_group_has_zero_scored_share_and_no_refusal() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("c1", 100.0)]);
    let cells = |f: &str| match f {
        "a1" | "a2" => vec![unseen_cell(), unseen_cell()],
        _ => vec![cell(100.0, 0.0)],
    };
    let (open, groups) = production_gate(&s, &cells, &family).unwrap();
    let a = groups.iter().find(|g| g.group_id == "a").unwrap();
    assert!(!open);
    assert!(!a.report.open && a.report.refusal.is_none());
    for m in &a.members {
        assert_eq!(m.scored_share, (0, 0));
        assert_eq!(m.total_cell_share, (2, 4));
        assert!(m.refusal.is_none() && !m.open && m.prior.is_none());
    }
}

/// A non-finite observed value makes that member's statistics refuse. The
/// pooled statistics refuse too (the bad cell is index 1 of the pooled errors),
/// so the group is closed with a reason; the clean member is unaffected.
#[test]
fn non_finite_member_refuses_and_closes_the_group_with_a_reason() {
    let s = store(&[("a1", 100.0), ("a2", 100.0), ("b1", 100.0), ("c1", 100.0)]);
    let cells = |f: &str| match f {
        "a1" => vec![cell(100.0, 0.0)],
        "a2" => vec![cell(f64::NAN, 0.0)],
        _ => vec![cell(100.0, 0.0)],
    };
    let (open, groups) = production_gate(&s, &cells, &family).unwrap();
    let a = groups.iter().find(|g| g.group_id == "a").unwrap();
    assert_eq!(a.members[1].refusal, Some(StatsError::NonFinite { index: 0 }));
    assert!(!a.members[1].open);
    assert!(a.members[0].refusal.is_none() && a.members[0].open);
    assert_eq!(a.report.refusal, Some(StatsError::NonFinite { index: 1 }));
    assert!(!a.report.open);
    assert!(!open);
}
