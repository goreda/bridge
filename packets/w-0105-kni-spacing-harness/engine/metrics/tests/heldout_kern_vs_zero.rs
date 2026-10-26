//! Held-out kern must not be worse than writing kern = 0.
//! Leave-one-glyph-out on the shared fixtures: all rows touching glyph g are
//! removed, targets and policy are refit, and every held-out row is predicted.
//! A pair the policy does not emit keeps kern 0 (error = |source kern|).
use kni_metrics::gen::{self, ClassTargets, GenerationInputs};
use std::collections::{BTreeSet, HashMap};

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    let m = v.len() / 2;
    if v.len() % 2 == 0 { (v[m - 1] + v[m]) / 2.0 } else { v[m] }
}

#[test]
fn leave_one_glyph_out_beats_zero_and_geom_never_emitted_when_gate_closed() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
    let rd = |n: &str| std::fs::read_to_string(format!("{dir}/{n}")).unwrap();
    let (glyphs, knowledge) = gen::parse_classes(&rd("classes.tsv")).unwrap();
    let walls = gen::parse_walls(&rd("walls.tsv")).unwrap();
    let rows = gen::parse_pairs(&rd("existing.tsv")).unwrap();
    let usable: Vec<_> = rows
        .iter()
        .filter(|r| knowledge.contains_key(&r.left) && knowledge.contains_key(&r.right)
            && walls.contains_key(&r.left) && walls.contains_key(&r.right)
            && gen::min_gap0(&walls[&r.left], &walls[&r.right]).is_some())
        .collect();
    let held: BTreeSet<String> = usable.iter().flat_map(|r| [r.left.clone(), r.right.clone()]).collect();
    let mut seen = BTreeSet::new();
    let (mut pred_err, mut zero_err, mut n) = (0.0f64, 0.0f64, 0usize);
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
        let mut inp = GenerationInputs {
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
        inp.knowledge.insert(g.clone(), knowledge[g].clone());
        inp.walls.insert(g.clone(), walls[g].clone());
        for r in usable.iter().filter(|r| &r.left == g || &r.right == g) {
            if !seen.insert((r.left.clone(), r.right.clone())) { continue; }
            let t = f64::from(r.kern);
            let p = match gen::predict_policy(&inp, &r.left, &r.right, None, &pol) {
                Some((k, tag)) => {
                    let st = (knowledge[&r.left].case, knowledge[&r.right].case);
                    assert!(tag != "geom" || pol.geom_open.as_ref().unwrap()[&st], "geom emitted from a closed stratum");
                    f64::from(k)
                }
                None => 0.0,
            };
            pred_err += (p - t).abs();
            zero_err += t.abs();
            n += 1;
        }
    }
    assert!(n > 0);
    assert!(pred_err < zero_err, "held-out error {pred_err} not below kern=0 error {zero_err} over {n} pairs");
}
