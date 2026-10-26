//! DECLARED_CONVENTION (K2 learned spacing pass, opt-in, default Cold).
//!
//! Wiring between the frozen spacing solve and the landed learned-priors
//! consumer (`kni_pipeline::learned_priors`). The frozen solve
//! (`solve_spacing_excluding_culprits`, with its jobs cap and culprit
//! retry) always runs first and unchanged; this module can only re-target
//! the unsaturated anchor-fallback pairs of its solution, post-solve, and
//! only when the manifest opts in and the production gate opens.
//!
//! Manifest keys (declared together; either alone is a manifest error;
//! both absent = Cold, a byte-identical run):
//!   learned_store <repo-relative path> <sha256-hex>   pinned K2 learned store
//!   learned_gate_evidence <repo-relative path>        gate-evidence sidecar
//!
//! The gate-evidence sidecar is the explicit carrier of the certified-cell
//! and family-group sources the consumer's `cells_of` / `group_of` need.
//! The driver never derives family groups from font names (a store font_id
//! is opaque, never a family name) and never predicts baselines at load
//! time (the store fonts are not solvable at driver load); both are
//! measured upstream by the training pipeline and shipped as:
//!   line 1:  KNI-LEARN-GATE\tschema=1
//!   rows:    font_id \t group_id \t class-key \t observed \t baseline_pred
//! The sidecar sha256 is recorded in the receipt. Missing or invalid
//! sidecar => Cold; never a guessed group, never a zero baseline.
//!
//! Learned targets are spacing pair objectives only: never kern values,
//! never training labels for kerning. Measured and derived-lane pair
//! targets are never re-targeted (consumer contract), so exported kerning
//! is never a learned label. Degrade paths (declared style override,
//! natural-population fallback, population floor) carry no solve, so no
//! learned pass runs on them.
//!
//! Every Cold reason is a receipt row; Cold always ships the frozen
//! solution untouched.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use kni_learning::prior::Cell;
use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::{FontContext, SpacingPolicy, SpacingSolution};
use kni_pipeline::learned_priors::{self, Learned};

/// The parsed, path-joined opt-in declaration. `parse_manifest` refuses a
/// half declaration, so a declared store always pairs with its evidence.
pub struct Declared {
    pub store_path: PathBuf,
    pub store_pin: String,
    pub evidence_path: PathBuf,
}

/// Reads the opt-in declaration; both keys absent => None (Cold default).
pub fn declared(m: &crate::Manifest) -> Option<Declared> {
    match (&m.learned_store, &m.learned_gate_evidence) {
        (Some((p, pin)), Some(ev)) => Some(Declared {
            store_path: p.clone(),
            store_pin: pin.clone(),
            evidence_path: ev.clone(),
        }),
        _ => None,
    }
}

/// Parsed gate-evidence sidecar: certified held-out cells per font and the
/// family/group id per font, plus the file sha256 for the receipt.
pub struct GateEvidence {
    cells: BTreeMap<String, Vec<Cell>>,
    groups: BTreeMap<String, String>,
    pub sha256: String,
    pub rows: usize,
}

pub fn load_evidence(path: &Path) -> Result<GateEvidence, String> {
    let bytes = std::fs::read(path)
        .map_err(|e| format!("gate evidence unreadable ({}): {e}", path.display()))?;
    let sha = kni_core::cff_reader::sha256_hex(&bytes);
    let text = String::from_utf8(bytes).map_err(|_| "gate evidence is not UTF-8".to_string())?;
    let mut lines = text.lines();
    if lines.next() != Some("KNI-LEARN-GATE\tschema=1") {
        return Err("gate evidence: bad header (want KNI-LEARN-GATE\\tschema=1)".into());
    }
    let mut cells: BTreeMap<String, Vec<Cell>> = BTreeMap::new();
    let mut groups: BTreeMap<String, String> = BTreeMap::new();
    let mut seen: BTreeSet<(String, String)> = BTreeSet::new();
    let mut rows = 0usize;
    for (i, line) in lines.enumerate() {
        if line.is_empty() {
            continue;
        }
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() != 5 {
            return Err(format!("gate evidence row {}: want 5 tab fields, got {}", i + 2, f.len()));
        }
        for (j, field) in f.iter().enumerate() {
            if field.is_empty() {
                return Err(format!("gate evidence row {}: empty field {}", i + 2, j + 1));
            }
            if *field != field.trim() {
                return Err(format!(
                    "gate evidence row {}: field {} has leading or trailing whitespace",
                    i + 2,
                    j + 1
                ));
            }
        }
        let observed: f64 = f[3].parse().map_err(|_| format!("gate evidence row {}: bad observed", i + 2))?;
        let baseline_pred: f64 = f[4].parse().map_err(|_| format!("gate evidence row {}: bad baseline_pred", i + 2))?;
        if !observed.is_finite() || !baseline_pred.is_finite() {
            return Err(format!("gate evidence row {}: non-finite value", i + 2));
        }
        if !seen.insert((f[0].to_string(), f[2].to_string())) {
            return Err(format!(
                "gate evidence row {}: duplicate cell for font {} key {}",
                i + 2,
                f[0],
                f[2]
            ));
        }
        match groups.insert(f[0].to_string(), f[1].to_string()) {
            Some(prev) if prev != f[1] => {
                return Err(format!("gate evidence row {}: font {} maps to two groups", i + 2, f[0]));
            }
            _ => {}
        }
        cells.entry(f[0].to_string()).or_default().push(Cell {
            key: vec![("class".to_string(), f[2].to_string())],
            observed,
            baseline_pred,
        });
        rows += 1;
    }
    if rows == 0 {
        return Err("gate evidence: no rows".into());
    }
    Ok(GateEvidence { cells, groups, sha256: sha, rows })
}

/// Result of the learned pass over one frozen solution.
pub enum Outcome {
    /// Gate-open priors applied: the re-targeted solution and its rows.
    Warm { solution: SpacingSolution, rows: String },
    /// Any refusal: the frozen solution ships untouched; the rows say why.
    Cold(String),
}

/// Applies the learned pass to a successful frozen solve. The returned
/// Warm solution differs from the input only on the pair rows the
/// consumer's report lists as applied; anything else closes Cold.
pub fn apply(
    decl: &Declared,
    profiles: &[OutlineProfile],
    ctx: &FontContext,
    policy: &SpacingPolicy,
    solved: &SpacingSolution,
) -> Outcome {
    let ev = match load_evidence(&decl.evidence_path) {
        Ok(ev) => ev,
        Err(e) => return Outcome::Cold(format!("learned_spacing\tstate\tcold\treason\t{}\n", sanitize(&e))),
    };
    let cells_of = |font_id: &str| ev.cells.get(font_id).cloned().unwrap_or_default();
    let group_of = |font_id: &str| ev.groups.get(font_id).cloned();
    let store_str = decl.store_path.to_string_lossy().into_owned();
    let active = match learned_priors::load_and_gate(&store_str, Some(&decl.store_pin), &cells_of, &group_of) {
        Learned::Active(a) => a,
        Learned::Cold(reason) => {
            return Outcome::Cold(format!("learned_spacing\tstate\tcold\treason\t{}\n", sanitize(&reason)));
        }
    };
    let ls = match learned_priors::solve_with_priors(profiles, Some(ctx), policy, Some(active.priors())) {
        Ok(ls) => ls,
        Err(e) => {
            return Outcome::Cold(format!("learned_spacing\tstate\tcold\treason\tconsumer re-solve refused: {e:?}\n"));
        }
    };
    if !identity_ok(solved, &ls.solution, &ls.report) {
        return Outcome::Cold(
            "learned_spacing\tstate\tcold\treason\tidentity check failed: consumer solve diverged outside applied rows\n".into(),
        );
    }
    let r = &ls.report;
    let mut rows = String::new();
    rows.push_str("learned_spacing\tstate\twarm\n");
    rows.push_str(&format!("learned_spacing\tstore\t{}\tpin\t{}\n", decl.store_path.display(), decl.store_pin));
    rows.push_str(&format!(
        "learned_spacing\tgate_evidence\t{}\tsha256\t{}\trows\t{}\n",
        decl.evidence_path.display(),
        ev.sha256,
        ev.rows
    ));
    rows.push_str(&format!("learned_spacing\tgroups_open\t{}\n", active.groups().len()));
    rows.push_str(&format!(
        "learned_spacing\tapplied\t{}\tskipped_measured_or_derived\t{}\tskipped_unseen\t{}\tkept_after_refusal\t{}\tkept_below_epsilon\t{}\n",
        r.applied.len(), r.skipped_measured_or_derived, r.skipped_unseen, r.kept_after_refusal, r.kept_below_epsilon
    ));
    rows.push_str("learned_spacing\ttargets\tspacing_pair_objectives_only\tnever_kern_values\n");
    Outcome::Warm { solution: ls.solution, rows }
}

fn sanitize(s: &str) -> String {
    s.replace(['\t', '\n'], " ")
}

/// The consumer's underlying solve must reproduce the frozen solve exactly
/// outside the rows its report lists as applied: same glyphs, same
/// baseline/heights, same pair order, and bit-identical origin_distance on
/// every non-applied pair. Any drift closes the pass Cold.
fn identity_ok(base: &SpacingSolution, learned: &SpacingSolution, report: &learned_priors::LearnedReport) -> bool {
    if base.glyphs.len() != learned.glyphs.len() || base.pairs.len() != learned.pairs.len() {
        return false;
    }
    if base.baseline != learned.baseline || base.x_height != learned.x_height || base.cap_height != learned.cap_height {
        return false;
    }
    for (a, b) in base.glyphs.iter().zip(learned.glyphs.iter()) {
        if a.glyph_id != b.glyph_id || a.lsb != b.lsb || a.rsb != b.rsb || a.advance != b.advance {
            return false;
        }
    }
    let applied: BTreeSet<(&str, &str)> =
        report.applied.iter().map(|p| (p.left.as_str(), p.right.as_str())).collect();
    for (a, b) in base.pairs.iter().zip(learned.pairs.iter()) {
        if a.left != b.left || a.right != b.right {
            return false;
        }
        if applied.contains(&(a.left.as_str(), a.right.as_str())) {
            continue;
        }
        if a.origin_distance != b.origin_distance {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write_tmp(name: &str, body: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("kni-learned-driver-test-{name}"));
        let mut f = std::fs::File::create(&p).unwrap();
        f.write_all(body.as_bytes()).unwrap();
        p
    }

    #[test]
    fn evidence_parses_cells_and_groups() {
        let p = write_tmp("good.tsv", "KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tRound->Round\t12.5\t388.0\nfont-a\tgrp-1\tRound->Straight\t9.0\t388.0\nfont-b\tgrp-2\tRound->Round\t11.0\t388.0\n");
        let ev = load_evidence(&p).unwrap();
        assert_eq!(ev.rows, 3);
        assert_eq!(ev.cells["font-a"].len(), 2);
        assert_eq!(ev.cells["font-b"].len(), 1);
        assert_eq!(ev.groups["font-a"], "grp-1");
        assert_eq!(ev.groups["font-b"], "grp-2");
        assert_eq!(ev.cells["font-a"][0].key, vec![("class".to_string(), "Round->Round".to_string())]);
        assert_eq!(ev.cells["font-a"][0].observed, 12.5);
        assert_eq!(ev.cells["font-a"][0].baseline_pred, 388.0);
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_bad_header() {
        let p = write_tmp("bad-header.tsv", "schema=1\nfont-a\tgrp-1\tk\t1.0\t2.0\n");
        assert!(load_evidence(&p).err().unwrap().contains("bad header"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_bad_field_count() {
        let p = write_tmp("bad-fields.tsv", "KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tk\t1.0\n");
        assert!(load_evidence(&p).err().unwrap().contains("5 tab fields"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_non_finite() {
        let p = write_tmp("bad-nan.tsv", "KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tk\tNaN\t2.0\n");
        assert!(load_evidence(&p).err().unwrap().contains("non-finite"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_group_conflict() {
        let p = write_tmp("bad-group.tsv", "KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tk\t1.0\t2.0\nfont-a\tgrp-9\tk2\t1.0\t2.0\n");
        assert!(load_evidence(&p).err().unwrap().contains("two groups"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_empty() {
        let p = write_tmp("empty.tsv", "KNI-LEARN-GATE\tschema=1\n");
        assert!(load_evidence(&p).err().unwrap().contains("no rows"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_empty_fields() {
        for (name, row) in [
            ("font", "\tgrp-1\tk\t1.0\t2.0\n"),
            ("group", "font-a\t\tk\t1.0\t2.0\n"),
            ("key", "font-a\tgrp-1\t\t1.0\t2.0\n"),
        ] {
            let p = write_tmp(
                &format!("bad-empty-{name}.tsv"),
                &format!("KNI-LEARN-GATE\tschema=1\n{row}"),
            );
            assert!(load_evidence(&p).err().unwrap().contains("empty field"), "{name}");
            std::fs::remove_file(&p).ok();
        }
    }

    #[test]
    fn evidence_refuses_whitespace_padded_fields() {
        // A padded font id must not evade the group-conflict check by
        // spelling the same font two ways.
        let p = write_tmp(
            "bad-pad.tsv",
            "KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tk\t1.0\t2.0\nfont-a \tgrp-9\tk2\t1.0\t2.0\n",
        );
        assert!(load_evidence(&p).err().unwrap().contains("whitespace"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_duplicate_cell() {
        let p = write_tmp(
            "bad-dup.tsv",
            "KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tk\t1.0\t2.0\nfont-a\tgrp-1\tk\t3.0\t4.0\n",
        );
        assert!(load_evidence(&p).err().unwrap().contains("duplicate cell"));
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn evidence_refuses_non_finite_spellings() {
        for (name, v) in [
            ("nan", "nan"),
            ("nan-caps", "NAN"),
            ("inf", "inf"),
            ("neg-inf", "-inf"),
            ("infinity", "Infinity"),
            ("overflow", "1e999"),
        ] {
            let p = write_tmp(
                &format!("bad-nf-{name}.tsv"),
                &format!("KNI-LEARN-GATE\tschema=1\nfont-a\tgrp-1\tk\t{v}\t2.0\n"),
            );
            assert!(load_evidence(&p).err().unwrap().contains("non-finite"), "{name}");
            std::fs::remove_file(&p).ok();
        }
    }

    #[test]
    fn evidence_refuses_near_miss_headers() {
        for (name, head) in [
            ("space", "KNI-LEARN-GATE schema=1\n"),
            ("schema2", "KNI-LEARN-GATE\tschema=2\n"),
            ("trailing", "KNI-LEARN-GATE\tschema=1 \n"),
            ("bom", "\u{feff}KNI-LEARN-GATE\tschema=1\n"),
            ("blank-first", "\nKNI-LEARN-GATE\tschema=1\n"),
        ] {
            let p = write_tmp(
                &format!("bad-head-{name}.tsv"),
                &format!("{head}font-a\tgrp-1\tk\t1.0\t2.0\n"),
            );
            assert!(load_evidence(&p).err().unwrap().contains("bad header"), "{name}");
            std::fs::remove_file(&p).ok();
        }
    }
}

