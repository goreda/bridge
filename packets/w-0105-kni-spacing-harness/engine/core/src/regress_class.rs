//! Per-class regression report for a cohort of glyphs (item 12).
//!
//! Joins a cohort table (glyph, codepoint, declared shape class, historical
//! old_iou, status) to a canonical-run measurements table
//! (docs/engine/execution/*/measurements*.tsv schema) by codepoint, and
//! reports per class: n, how many glyphs sit below their historical
//! baseline on each arm, and mean deltas. "Below" is a plain sign test
//! (arm IoU < baseline IoU); no cutoff or band is introduced here. Cohort
//! rows with no measurement row are returned as typed unmatched rows,
//! never dropped.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub struct CohortRow {
    pub glyph: String,
    pub codepoint: u32,
    pub class: String,
    pub old_iou: f64,
    pub status: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ClassRow {
    pub n: usize,
    pub arm_a_below_old: usize,
    pub arm_b_below_old: usize,
    pub arm_a_below_arm_b: usize,
    pub sum_a_minus_old: f64,
    pub sum_b_minus_old: f64,
    pub sum_a_minus_b: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Report {
    /// Key: (status, class).
    pub classes: BTreeMap<(String, String), ClassRow>,
    pub unmatched: Vec<String>,
}

fn col(h: &[&str], name: &str) -> Result<usize, String> {
    h.iter().position(|c| *c == name).ok_or_else(|| format!("missing column {name}"))
}

fn parse_cp(s: &str) -> Result<u32, String> {
    let t = s.trim_start_matches("U+").trim_start_matches("0x").trim_start_matches("0X");
    u32::from_str_radix(t, 16).map_err(|e| format!("bad codepoint {s}: {e}"))
}

pub fn parse_cohort(text: &str) -> Result<Vec<CohortRow>, String> {
    let mut lines = text.lines();
    let h: Vec<&str> = lines.next().ok_or("empty cohort")?.split('\t').collect();
    let (g, c, k, o, s) = (
        col(&h, "glyph")?, col(&h, "codepoint")?, col(&h, "shape_class")?,
        col(&h, "old_iou")?, col(&h, "status")?,
    );
    let mut out = Vec::new();
    for l in lines.filter(|l| !l.is_empty()) {
        let f: Vec<&str> = l.split('\t').collect();
        let get = |i: usize| f.get(i).copied().ok_or_else(|| format!("short row: {l}"));
        out.push(CohortRow {
            glyph: get(g)?.to_string(),
            codepoint: parse_cp(get(c)?)?,
            class: get(k)?.to_string(),
            old_iou: get(o)?.parse().map_err(|e| format!("old_iou {l}: {e}"))?,
            status: get(s)?.to_string(),
        });
    }
    Ok(out)
}

/// Returns codepoint -> arm name -> scan-domain IoU.
pub fn parse_measurements(text: &str) -> Result<BTreeMap<u32, BTreeMap<String, f64>>, String> {
    let mut lines = text.lines();
    let h: Vec<&str> = lines.next().ok_or("empty measurements")?.split('\t').collect();
    let (c, a, i) = (col(&h, "codepoint")?, col(&h, "arm")?, col(&h, "iou_scan_domain")?);
    let mut m: BTreeMap<u32, BTreeMap<String, f64>> = BTreeMap::new();
    for l in lines.filter(|l| !l.is_empty()) {
        let f: Vec<&str> = l.split('\t').collect();
        let get = |j: usize| f.get(j).copied().ok_or_else(|| format!("short row: {l}"));
        let iou: f64 = get(i)?.parse().map_err(|e| format!("iou {l}: {e}"))?;
        m.entry(parse_cp(get(c)?)?).or_default().insert(get(a)?.to_string(), iou);
    }
    Ok(m)
}

pub fn report(
    cohort: &[CohortRow],
    meas: &BTreeMap<u32, BTreeMap<String, f64>>,
    arm_a: &str,
    arm_b: &str,
) -> Report {
    let mut classes: BTreeMap<(String, String), ClassRow> = BTreeMap::new();
    let mut unmatched = Vec::new();
    for r in cohort {
        let ab = meas.get(&r.codepoint).and_then(|m| Some((*m.get(arm_a)?, *m.get(arm_b)?)));
        let Some((a, b)) = ab else {
            unmatched.push(r.glyph.clone());
            continue;
        };
        let e = classes.entry((r.status.clone(), r.class.clone())).or_default();
        e.n += 1;
        e.arm_a_below_old += (a < r.old_iou) as usize;
        e.arm_b_below_old += (b < r.old_iou) as usize;
        e.arm_a_below_arm_b += (a < b) as usize;
        e.sum_a_minus_old += a - r.old_iou;
        e.sum_b_minus_old += b - r.old_iou;
        e.sum_a_minus_b += a - b;
    }
    Report { classes, unmatched }
}

pub fn render_tsv(r: &Report) -> String {
    let mut s = String::from(
        "status\tclass\tn\ta_below_old\tb_below_old\ta_below_b\tmean_a_minus_old\tmean_b_minus_old\tmean_a_minus_b\n",
    );
    for ((st, cl), v) in &r.classes {
        let n = v.n as f64;
        s += &format!(
            "{st}\t{cl}\t{}\t{}\t{}\t{}\t{:.6}\t{:.6}\t{:.6}\n",
            v.n, v.arm_a_below_old, v.arm_b_below_old, v.arm_a_below_arm_b,
            v.sum_a_minus_old / n, v.sum_b_minus_old / n, v.sum_a_minus_b / n
        );
    }
    for u in &r.unmatched {
        s += &format!("unmatched\t{u}\n");
    }
    s
}
