//! Diagnostic (skips unless KNI_RINGS names a ring dump): exact stage-4 evidence for real production-flattened rings at the ledger
//! placement (profile frame, per-glyph x translation, export distance). Compare with the sampled 10 fu profile (the ledger reading).
use kni_metrics::exact_rows::{exact_aligned_rows_at, ExactSlabs};
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy};
use kni_metrics::signed_clearance::{evidence_at, exact_evidence_rows};
use std::collections::HashMap;

fn load(path: &str) -> HashMap<String, Vec<Vec<[f64; 2]>>> {
    let mut m = HashMap::new();
    let mut cur = String::new();
    for l in std::fs::read_to_string(path).unwrap().lines() {
        if let Some(n) = l.strip_prefix("G ") { cur = n.into(); m.insert(cur.clone(), vec![]); }
        else if l == "R" { m.get_mut(&cur).unwrap().push(vec![]); }
        else { let v: Vec<f64> = l.split(' ').map(|s| s.parse().unwrap()).collect(); m.get_mut(&cur).unwrap().last_mut().unwrap().push([v[0], v[1]]); }
    }
    m
}

#[test]
fn exact_vs_sampled_on_the_three_ledger_pairs() {
    let Ok(path) = std::env::var("KNI_RINGS") else { return };
    let g = load(&path);
    let pol = ScanPolicy { row_step: 10.0, max_rows: 100000, merge_guard: 1.0, grid_anchor_y: Some(0.0) };
    for (l, r, d, ltr, rtr) in [
        ("four", "three", 124.0, -53.3341935303481, -51.605984780280274),
        ("t", "three", 89.0, -22.533670464020993, -51.605984780280274),
        ("F", "z", 93.0, 0.7902901582514807, -34.05988507539338),
        ("four", "three", 130.0, -53.3341935303481, -51.605984780280274),
    ] {
        let mk = |n: &str| profile_outline(&OutlineInput { glyph_id: n.into(), source_pin: "t".into(), upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.5, rings: g[n].clone() }, pol).unwrap();
        let sampled = evidence_at(&mk(l), &mk(r), ltr, rtr, d).unwrap();
        let rows = exact_aligned_rows_at(&ExactSlabs::from_rings(&g[l]).unwrap(), &ExactSlabs::from_rings(&g[r]).unwrap(), d + rtr - ltr);
        let ex = exact_evidence_rows(&rows, ltr, rtr, d).unwrap();
        println!("EXACT {l}|{r} d={d}: sampled gap {:.6} hit {} | exact gap {:.6} hit {} rows {}", sampled.clearance.min_gap, sampled.interval_hit, ex.clearance.min_gap, ex.interval_hit, rows.len());
    }
}
