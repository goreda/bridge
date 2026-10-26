//! Leave-one-glyph-out held-out kern evaluation against kern = 0.
//! Measurement only. For each glyph g with source kern rows, every row with g
//! at either end is removed, targets and policy are refit from the remaining
//! rows (same target construction as training_only_fit::fit), and each held-out
//! row is predicted. Error = |predicted - source kern|; baseline = |0 - source|.
//! Usage: heldout_kern_eval [fixtures_dir]
use kni_metrics::gen::{self, ClassTargets, GenerationInputs};
use std::collections::{BTreeMap, BTreeSet, HashMap};

fn median(mut v: Vec<f64>) -> f64 {
    if v.is_empty() { return f64::NAN; }
    v.sort_by(f64::total_cmp);
    let m = v.len() / 2;
    if v.len() % 2 == 0 { (v[m - 1] + v[m]) / 2.0 } else { v[m] }
}
fn pct(v: &[f64], p: f64) -> f64 {
    if v.is_empty() { return f64::NAN; }
    let mut s = v.to_vec();
    s.sort_by(f64::total_cmp);
    s[(((s.len() - 1) as f64) * p).round() as usize]
}

fn main() {
    let dir = std::env::args().nth(1).unwrap_or_else(|| concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures").to_string());
    let rd = |n: &str| std::fs::read_to_string(format!("{dir}/{n}")).unwrap();
    let (glyphs, knowledge) = gen::parse_classes(&rd("classes.tsv")).unwrap();
    let walls = gen::parse_walls(&rd("walls.tsv")).unwrap();
    let rows = gen::parse_pairs(&rd("existing.tsv")).unwrap();
    let usable: Vec<_> = rows.iter().filter(|r| knowledge.contains_key(&r.left) && knowledge.contains_key(&r.right)
        && walls.contains_key(&r.left) && walls.contains_key(&r.right)
        && gen::min_gap0(&walls[&r.left], &walls[&r.right]).is_some()).collect();
    let held: BTreeSet<String> = usable.iter().flat_map(|r| [r.left.clone(), r.right.clone()]).collect();
    println!("rows_total={} rows_usable={} glyphs_with_rows={}", rows.len(), usable.len(), held.len());

    // per-row result keyed by pair so each ordered pair is scored once
    let mut res: BTreeMap<(String, String), (f64, f64, &'static str)> = BTreeMap::new();
    // variant errors: [v0 shipped, v1 geom off, v2 cell gated by in-cell beats-zero, v3 = v1+v2, v4 geom gated by in-sample beats-zero]
    let mut var: BTreeMap<(String, String), [f64; 5]> = BTreeMap::new();
    let mut unavailable = 0usize;
    for g in &held {
        let train: Vec<_> = usable.iter().filter(|r| &r.left != g && &r.right != g).collect();
        let mut cell: HashMap<(u32, u32, char, char), Vec<f64>> = HashMap::new();
        let mut stratum: HashMap<(char, char), Vec<f64>> = HashMap::new();
        let mut global = Vec::new();
        let mut existing = HashMap::new();
        for r in &train {
            let (kl, kr) = (&knowledge[&r.left], &knowledge[&r.right]);
            let gap = gen::min_gap0(&walls[&r.left], &walls[&r.right]).unwrap() + f64::from(r.kern);
            cell.entry((kl.right_class, kr.left_class, kl.case, kr.case)).or_default().push(f64::from(r.kern));
            stratum.entry((kl.case, kr.case)).or_default().push(gap);
            global.push(gap);
            existing.insert((r.left.clone(), r.right.clone()), r.kern);
        }
        let inp = GenerationInputs {
            glyphs: glyphs.iter().filter(|x| *x != g).cloned().collect(),
            knowledge: knowledge.iter().filter(|(k, _)| *k != g).map(|(k, v)| (k.clone(), v.clone())).collect(),
            walls: walls.iter().filter(|(k, _)| *k != g).map(|(k, v)| (k.clone(), v.clone())).collect(),
            targets: ClassTargets {
                cell_median: cell.into_iter().map(|(k, v)| (k, median(v))).collect(),
                stratum_mingap: stratum.into_iter().map(|(k, v)| (k, median(v))).collect(),
                global_mingap: median(global),
            },
            existing,
            restore: vec![],
        };
        let Ok(pol) = gen::derive_policy(&inp) else { continue };
        // cell gate: median must beat zero on the cell's own training members
        let mut cell_ok: HashMap<(u32, u32, char, char), bool> = HashMap::new();
        {
            let mut mem: HashMap<(u32, u32, char, char), Vec<f64>> = HashMap::new();
            for r in &train { let (kl, kr) = (&knowledge[&r.left], &knowledge[&r.right]); mem.entry((kl.right_class, kr.left_class, kl.case, kr.case)).or_default().push(f64::from(r.kern)); }
            for (k, v) in mem { let m = median(v.clone()); let e: f64 = v.iter().map(|x| (x - m).abs()).sum(); let z: f64 = v.iter().map(|x| x.abs()).sum(); cell_ok.insert(k, e < z); }
        }
        // geom gate: stratum-target geometric solve must beat zero on training rows
        let mut geom_ok: HashMap<(char, char), bool> = HashMap::new();
        {
            for (st, tgt) in &inp.targets.stratum_mingap {
                let (mut e, mut z) = (0.0, 0.0);
                for r in &train { let (kl, kr) = (&knowledge[&r.left], &knowledge[&r.right]); if (kl.case, kr.case) != *st { continue; }
                    let g0 = gen::min_gap0(&walls[&r.left], &walls[&r.right]).unwrap(); e += (((tgt - g0).round()) - f64::from(r.kern)).abs(); z += f64::from(r.kern).abs(); }
                geom_ok.insert(*st, e < z);
            }
        }
        // query inputs: add g back as query-only geometry/class
        let mut q = inp.clone();
        q.knowledge.insert(g.clone(), knowledge[g].clone());
        q.walls.insert(g.clone(), walls[g].clone());
        for r in usable.iter().filter(|r| &r.left == g || &r.right == g) {
            let key = (r.left.clone(), r.right.clone());
            if res.contains_key(&key) { continue; }
            match gen::predict_policy(&q, &r.left, &r.right, None, &pol) {
                Some((k, tag)) => {
                    let (kl, kr) = (&knowledge[&r.left], &knowledge[&r.right]);
                    let cellk = (kl.right_class, kr.left_class, kl.case, kr.case);
                    let t = f64::from(r.kern); let p = f64::from(k);
                    let cell_pass = *cell_ok.get(&cellk).unwrap_or(&false);
                    let geom_pass = *geom_ok.get(&(kl.case, kr.case)).unwrap_or(&false);
                    let v1 = if tag == "geom" { t.abs() } else { (p - t).abs() };
                    let v2 = if tag == "cell" && !cell_pass { t.abs() } else { (p - t).abs() };
                    let v3 = if tag == "geom" || (tag == "cell" && !cell_pass) { t.abs() } else { (p - t).abs() };
                    let v4 = if tag == "geom" && !geom_pass { t.abs() } else { (p - t).abs() };
                    var.insert(key.clone(), [(p - t).abs(), v1, v2, v3, v4]);
                    res.insert(key, ((f64::from(k) - f64::from(r.kern)).abs(), f64::from(r.kern).abs(), tag)); }
                None => {
                    // no pair emitted: the font keeps kern 0, so the error equals the zero baseline
                    let key2 = (r.left.clone(), r.right.clone());
                    if !res.contains_key(&key2) {
                        unavailable += 1;
                        let t = f64::from(r.kern).abs();
                        var.insert(key2.clone(), [t; 5]);
                        res.insert(key2, (t, t, "none"));
                    }
                }
            }
        }
    }
    println!("scored_pairs={} unavailable={}", res.len(), unavailable);
    for (i, name) in ["v0_shipped", "v1_geom_off", "v2_cell_gated", "v3_geom_off+cell_gated", "v4_geom_gated_insample"].iter().enumerate() {
        let e: Vec<f64> = var.values().map(|a| a[i]).collect();
        println!("variant={name} n={} mean_abs_err={:.2} median={:.1} p90={:.1}", e.len(), e.iter().sum::<f64>() / e.len() as f64, median(e.clone()), pct(&e, 0.9));
    }
    let mut tags: BTreeSet<&str> = res.values().map(|v| v.2).collect();
    tags.insert("ALL");
    for t in tags {
        let sel: Vec<_> = res.values().filter(|v| t == "ALL" || v.2 == t).collect();
        let pe: Vec<f64> = sel.iter().map(|v| v.0).collect();
        let ze: Vec<f64> = sel.iter().map(|v| v.1).collect();
        let worse = sel.iter().filter(|v| v.0 > v.1).count();
        let better = sel.iter().filter(|v| v.0 < v.1).count();
        println!("tier={t} n={} pred_err[median={:.1} mean={:.2} p90={:.1}] zero_err[median={:.1} mean={:.2} p90={:.1}] worse_than_zero={worse} better={better} equal={}",
            sel.len(), median(pe.clone()), pe.iter().sum::<f64>() / pe.len() as f64, pct(&pe, 0.9),
            median(ze.clone()), ze.iter().sum::<f64>() / ze.len() as f64, pct(&ze, 0.9), sel.len() - worse - better);
    }
}

