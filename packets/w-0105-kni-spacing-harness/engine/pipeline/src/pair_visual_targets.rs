//! pair_visual_targets.rs — PC-K2 side of the joint PC-K1/K2 opt-in
//! spacing-target mapping over a DECLARED same-source scale context.
//!
//! STATUS: new file, add-only. Nothing existing is modified. The mapping
//! runs only when the manifest declares `pair_visual_same_source` AND the
//! K1 pair-visual stage ran (`--pair-visual <dir>` wrote the pinned
//! report); with no declaration the run is byte-identical to before.
//!
//! THE CONTRACT (what the declaration means):
//! `pair_visual_same_source` is the caller's explicit declaration that the
//! `--pair-visual` kerning folder is rendered from the SAME source as this
//! run's capture, at this run's declared scale context (kni_core
//! ScaleContext binding: same source identity and frame). Only under that
//! declaration is a measured source-pixel gap a font-unit white gap:
//!   gap_fu = min_gap_px * scale.units_per_px()
//! The conservative per-row MINIMUM gap is always used, never the mean
//! (the K1 measurement layer's own rule). Without the declaration the
//! mapping does not run: no scale context is guessed, no fu/px ratio is
//! invented, no label vocabulary is introduced, and no kern table (source
//! or shipped) is read or written — the mapped values are spacing
//! objective targets (measured white gaps), never kern values.
//!
//! UNCERTAINTY IS TYPED, NEVER FILLED. Per report row, anything uncertain
//! becomes a counted typed `unavailable`, never a guessed target:
//!   k1_refused              the K1 row itself is a typed refusal
//!   bad_label               label is neither one Unicode scalar nor U+XXXX
//!   ambiguous_codepoint     the run's manifest-bound cp map has 2+ glyphs
//!   glyph_not_in_population codepoint not in this run's solve population
//!   bad_gap                 min_gap_px missing / non-finite / negative
//!   scale_conflict          report gap_fu disagrees with declared scale
//!   conflicting_measurement two measured rows, one glyph pair, unlike gaps
//! A pin/schema break (missing pin, unreadable report, sha mismatch, a row
//! shape the pinned writer never emits) is NOT uncertainty: it is a hard
//! refusal, because declared evidence must be exactly what was pinned.
//!
//! CONSUMPTION: report-only in the B port (chief S1a). Mapping produces
//! typed evidence and receipts, but the runner never passes it to the solve.
//! No new flag or default spacing policy is introduced.

use std::collections::BTreeMap;
use std::path::Path;

use kni_core::cff_reader::sha256_hex;
use kni_metrics::self_anchored_spacing::MeasuredPair;

/// Outcome of one mapping run over the pinned K1 report.
pub struct Mapping {
    /// Mapped measured white gaps (font units), deduplicated, solve-ready.
    pub pairs: Vec<MeasuredPair>,
    /// typed unavailable reason -> row count.
    pub unavailable: BTreeMap<&'static str, usize>,
    /// Measured rows seen (mapped + unavailable-from-measured).
    pub measured_rows: usize,
    /// Refused (K1) rows seen.
    pub refused_rows: usize,
    /// sha256 of the verified report bytes (echoed into the receipt).
    pub report_sha256: String,
    /// Declared scale used for the conversion.
    pub units_per_px: f64,
}

impl Mapping {
    /// Receipt rows (tab-separated, house style). One `state` line, the
    /// counts, one line per unavailable reason, scale, report pin.
    pub fn receipt(&self) -> String {
        let mut s = String::new();
        let total_unavailable: usize = self.unavailable.values().sum();
        let state = if self.pairs.is_empty() { "unavailable" } else { "mapped" };
        s.push_str(&format!("pair_visual_targets\tstate\t{state}\n"));
        s.push_str(&format!(
            "pair_visual_targets\tmapped_pairs\t{}\tunavailable\t{}\tmeasured_rows\t{}\trefused_rows\t{}\n",
            self.pairs.len(), total_unavailable, self.measured_rows, self.refused_rows
        ));
        for (reason, count) in &self.unavailable {
            s.push_str(&format!("pair_visual_targets\tunavailable_reason\t{reason}\t{count}\n"));
        }
        s.push_str(&format!("pair_visual_targets\tscale_units_per_px\t{:e}\n", self.units_per_px));
        s.push_str(&format!("pair_visual_targets\treport_sha256\t{}\n", self.report_sha256));
        s.push_str("pair_visual_targets\ttargets\tmeasured_white_gap_fu\tnever_kern_values\tnever_labels\n");
        s
    }
}

/// Reads the K1 pin + report from `out_dir`, verifies the report sha
/// against the pin, and maps measured rows to font-unit white-gap targets
/// under the declared scale. Hard Err on any pin/schema break; per-row
/// uncertainty is a typed unavailable inside the returned Mapping.
pub fn map_pinned(out_dir: &Path, cps: &[(String, u32)], units_per_px: f64) -> Result<Mapping, String> {
    if !units_per_px.is_finite() || units_per_px <= 0.0 {
        return Err(format!("pair_visual_targets: declared scale units_per_px must be finite and > 0, got {units_per_px}"));
    }
    let pin_path = out_dir.join("pair_visual_report.pin.tsv");
    let pin = std::fs::read_to_string(&pin_path).map_err(|e| {
        format!(
            "pair_visual_same_source declared but the K1 pin is unreadable ({}): {e} — run --pair-visual <dir> or remove the declaration",
            pin_path.display()
        )
    })?;
    let report_line = pin
        .lines()
        .find(|l| l.starts_with("pair_visual_report\tpath\t"))
        .ok_or("pair_visual_targets: pin carries no pair_visual_report path line")?;
    let f: Vec<&str> = report_line.split('\t').collect();
    if f.len() != 7 || f[3] != "report_sha256" || f[5] != "source_dir" {
        return Err("pair_visual_targets: pin report line is not the pinned writer's shape".into());
    }
    let (report_path, pinned_sha) = (f[2].to_string(), f[4].to_string());
    let report = std::fs::read(&report_path)
        .map_err(|e| format!("pair_visual_targets: pinned report unreadable ({report_path}): {e}"))?;
    let report_sha = sha256_hex(&report);
    if report_sha != pinned_sha {
        return Err(format!(
            "pair_visual_targets: report sha256 mismatch (pin {pinned_sha}, actual {report_sha}); declared evidence is not what was pinned"
        ));
    }
    let text = String::from_utf8(report).map_err(|_| "pair_visual_targets: report is not UTF-8".to_string())?;
    map_report(&text, cps, units_per_px, report_sha)
}

/// Maps an already-verified report text. Row shapes are exactly the two the
/// pinned K1 writer emits; anything else is a schema break (hard Err).
fn map_report(
    text: &str,
    cps: &[(String, u32)],
    units_per_px: f64,
    report_sha: String,
) -> Result<Mapping, String> {
    const HEADER: &str = "left\tright\tmin_gap_px\tmean_gap_px\tshared_rows\tgap_band_start\tgap_band_end\tthreshold\tgap_fu\tsource_sha256\tstatus\treason\timage_path";
    let mut lines = text.lines();
    if lines.next() != Some(HEADER) {
        return Err("pair_visual_targets: report header is not the pinned writer's fixed header".into());
    }
    // Manifest-bound identity map cp -> glyph id; a duplicated codepoint is
    // ambiguous and maps nothing (typed unavailable per affected row).
    let mut by_cp: BTreeMap<u32, Option<&str>> = BTreeMap::new();
    for (name, cp) in cps {
        by_cp.entry(*cp)
            .and_modify(|slot| *slot = None)
            .or_insert(Some(name.as_str()));
    }
    let mut pairs: Vec<MeasuredPair> = Vec::new();
    let mut seen: BTreeMap<(String, String), f64> = BTreeMap::new();
    let mut unavailable: BTreeMap<&'static str, usize> = BTreeMap::new();
    let (mut measured_rows, mut refused_rows) = (0usize, 0usize);
    for (i, line) in lines.enumerate() {
        if line.is_empty() {
            continue;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        // Measured rows: 13 columns, status at index 10.
        // Refused rows: left,right, 8 empty fields, sha, "refused", reason, path (14 columns).
        if cols.len() == 13 && cols[10] == "measured" {
            measured_rows += 1;
            let left = match resolve_label(cols[0], &by_cp) {
                Ok(g) => g,
                Err(reason) => { *unavailable.entry(reason).or_default() += 1; continue; }
            };
            let right = match resolve_label(cols[1], &by_cp) {
                Ok(g) => g,
                Err(reason) => { *unavailable.entry(reason).or_default() += 1; continue; }
            };
            let min_gap_px: f64 = match cols[2].parse::<f64>().ok().filter(|v| v.is_finite() && *v >= 0.0) {
                Some(v) => v,
                None => { *unavailable.entry("bad_gap").or_default() += 1; continue; }
            };
            let gap_fu = min_gap_px * units_per_px;
            if !cols[8].is_empty() {
                let reported: f64 = cols[8].parse().map_err(|_| format!(
                    "pair_visual_targets: row {} carries a non-numeric gap_fu (schema break)", i + 2))?;
                let tol = 1e-9 * gap_fu.abs().max(1.0);
                if (reported - gap_fu).abs() > tol {
                    *unavailable.entry("scale_conflict").or_default() += 1;
                    continue;
                }
            }
            match seen.entry((left.to_string(), right.to_string())) {
                std::collections::btree_map::Entry::Vacant(v) => {
                    v.insert(gap_fu);
                    pairs.push(MeasuredPair { left: left.to_string(), right: right.to_string(), gap: gap_fu });
                }
                std::collections::btree_map::Entry::Occupied(o) => {
                    if *o.get() != gap_fu {
                        // Two unlike measurements of one glyph pair: neither
                        // is evidence; drop the earlier emit, count both.
                        let key = o.key().clone();
                        pairs.retain(|p| !(p.left == key.0 && p.right == key.1));
                        o.remove();
                        *unavailable.entry("conflicting_measurement").or_default() += 2;
                    }
                }
            }
        } else if cols.len() >= 13 && cols[cols.len() - 3] == "refused" {
            refused_rows += 1;
            *unavailable.entry("k1_refused").or_default() += 1;
        } else {
            return Err(format!(
                "pair_visual_targets: row {} is not a shape the pinned writer emits ({} columns)",
                i + 2,
                cols.len()
            ));
        }
    }
    // Deterministic emit order (the solve groups by class pair; a stable
    // order keeps receipts and downstream behavior reproducible).
    pairs.sort_by(|a, b| (&a.left, &a.right).cmp(&(&b.left, &b.right)));
    Ok(Mapping { pairs, unavailable, measured_rows, refused_rows, report_sha256: report_sha, units_per_px })
}

/// Resolves one K1 row label (a single Unicode scalar or U+XXXX) through
/// the run's manifest-bound codepoint map to a solver glyph id.
fn resolve_label<'a>(
    label: &str,
    by_cp: &BTreeMap<u32, Option<&'a str>>,
) -> Result<&'a str, &'static str> {
    let cp: u32 = if let Some(hex) = label.strip_prefix("U+") {
        u32::from_str_radix(hex, 16).map_err(|_| "bad_label")?
    } else {
        let mut chars = label.chars();
        match (chars.next(), chars.next()) {
            (Some(c), None) => c as u32,
            _ => return Err("bad_label"),
        }
    };
    match by_cp.get(&cp) {
        Some(Some(g)) => Ok(g),
        Some(None) => Err("ambiguous_codepoint"),
        None => Err("glyph_not_in_population"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEADER: &str = "left\tright\tmin_gap_px\tmean_gap_px\tshared_rows\tgap_band_start\tgap_band_end\tthreshold\tgap_fu\tsource_sha256\tstatus\treason\timage_path";

    fn cps() -> Vec<(String, u32)> {
        vec![("H".into(), 0x48), ("V".into(), 0x56), ("A".into(), 0x41)]
    }

    fn measured(l: &str, r: &str, min: f64, sha: &str) -> String {
        format!("{l}\t{r}\t{min:.3}\t{min:.3}\t10\t3\t7\t128\t\t{sha}\tmeasured\t\t\n")
    }

    #[test]
    fn maps_measured_rows_to_font_unit_targets() {
        let text = format!("{HEADER}\n{}{}", measured("H", "H", 20.0, "aa"), measured("H", "V", 12.5, "bb"));
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert_eq!(m.pairs.len(), 2);
        assert!((m.pairs[0].left == "H" && m.pairs[0].right == "H" && m.pairs[0].gap == 40.0), "{:?}", m.pairs[0]);
        assert!((m.pairs[1].left == "H" && m.pairs[1].right == "V" && m.pairs[1].gap == 25.0), "{:?}", m.pairs[1]);
        assert!(m.unavailable.is_empty());
        assert_eq!(m.measured_rows, 2);
    }

    #[test]
    fn u_plus_form_resolves() {
        let text = format!("{HEADER}\n{}", measured("U+0048", "U+0056", 10.0, "aa"));
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert_eq!(m.pairs.len(), 1);
        assert_eq!(m.pairs[0].gap, 20.0);
    }

    #[test]
    fn refused_row_is_typed_unavailable_never_mapped() {
        let text = format!(
            "{HEADER}\nA\tV\t\t\t\t\t\t\t\t\tcc\trefused\tkern-negative overlap\t/img/a_v.png\n"
        );
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["k1_refused"], 1);
        assert_eq!(m.refused_rows, 1);
    }

    #[test]
    fn bad_label_is_typed_unavailable() {
        let text = format!("{HEADER}\n{}", measured("HH", "V", 10.0, "aa"));
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["bad_label"], 1);
    }

    #[test]
    fn glyph_outside_population_is_typed_unavailable() {
        let text = format!("{HEADER}\n{}", measured("H", "T", 10.0, "aa"));
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["glyph_not_in_population"], 1);
    }

    #[test]
    fn duplicate_codepoint_is_ambiguous_never_first_wins() {
        let dup = vec![("H".into(), 0x48u32), ("H.alt".into(), 0x48u32), ("V".into(), 0x56)];
        let text = format!("{HEADER}\n{}", measured("H", "V", 10.0, "aa"));
        let m = map_report(&text, &dup, 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["ambiguous_codepoint"], 1);
    }

    #[test]
    fn negative_gap_is_typed_unavailable() {
        let text = format!("{HEADER}\nH\tV\t-4.000\t-4.000\t10\t3\t7\t128\t\taa\tmeasured\t\t\n");
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["bad_gap"], 1);
    }

    #[test]
    fn conflicting_duplicate_measurement_drops_both() {
        let text = format!("{HEADER}\n{}{}", measured("H", "V", 10.0, "aa"), measured("H", "V", 11.0, "bb"));
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["conflicting_measurement"], 2);
    }

    #[test]
    fn identical_duplicate_measurement_dedupes() {
        let text = format!("{HEADER}\n{}{}", measured("H", "V", 10.0, "aa"), measured("H", "V", 10.0, "bb"));
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert_eq!(m.pairs.len(), 1);
    }

    #[test]
    fn gap_fu_disagreeing_with_declared_scale_is_typed_unavailable() {
        let mut row = measured("H", "V", 10.0, "aa");
        row = row.replacen("\t\taa\t", "\t999.000\taa\t", 1);
        let text = format!("{HEADER}\n{row}");
        let m = map_report(&text, &cps(), 2.0, "pin".into()).unwrap();
        assert!(m.pairs.is_empty());
        assert_eq!(m.unavailable["scale_conflict"], 1);
    }

    #[test]
    fn schema_break_row_refuses_loudly() {
        let text = format!("{HEADER}\nH\tV\t10.0\n");
        assert!(map_report(&text, &cps(), 2.0, "pin".into()).is_err());
    }

    #[test]
    fn bad_header_refuses_loudly() {
        assert!(map_report("x\ty\n", &cps(), 2.0, "pin".into()).is_err());
    }

    #[test]
    fn invalid_scale_refuses_loudly() {
        assert!(map_pinned(Path::new("/nonexistent"), &cps(), 0.0).is_err());
    }

    #[test]
    fn pin_round_trip_and_tamper_refusal() {
        let dir = std::env::temp_dir().join(format!("kni-pvt-{:x}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let report = format!("{HEADER}\n{}", measured("H", "V", 10.0, "aa"));
        let report_path = dir.join("pair_visual_report.tsv");
        std::fs::write(&report_path, &report).unwrap();
        let sha = sha256_hex(report.as_bytes());
        let pin = format!(
            "pair_visual_scope\treport_only\tspacing_use\tnone\npair_visual_report\tpath\t{}\treport_sha256\t{sha}\tsource_dir\t/src\npair_visual_report\tmeasured\t1\tfailed\t0\tunavailable\t0\tnon_pair\t0\taliases\t0\n",
            report_path.display()
        );
        std::fs::write(dir.join("pair_visual_report.pin.tsv"), &pin).unwrap();
        let m = map_pinned(&dir, &cps(), 2.0).unwrap();
        assert_eq!(m.pairs.len(), 1);
        assert_eq!(m.report_sha256, sha);
        std::fs::write(&report_path, format!("{HEADER}\n{}", measured("H", "V", 11.0, "aa"))).unwrap();
        assert!(map_pinned(&dir, &cps(), 2.0).err().unwrap().contains("sha256 mismatch"));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn missing_pin_is_a_loud_refusal() {
        assert!(map_pinned(Path::new("/nonexistent"), &cps(), 2.0)
            .err()
            .unwrap()
            .contains("pair_visual_same_source declared"));
    }
}
