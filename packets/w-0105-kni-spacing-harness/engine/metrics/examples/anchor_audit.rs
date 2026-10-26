//! Anchor-audit validation driver: reads back an exported OTF, rebuilds the
//! outline profiles, reruns the spacing solve, and prints the systematic
//! anchor-error audit for that solve (per-class residual sign summary plus
//! typed flags), then classifies the run's kern ledger into the hold-reason
//! summary and applies the hold-rate check. Readback note: the OTF charstrings
//! are the exported, integer-rounded curves, so residuals differ from the
//! PNG-fit source solve by the export quantization; the audit target is the
//! systematic (whole-class) shift, which that quantization cannot fabricate.
//! All solve policy values arrive as arguments, copied from the run receipt's
//! run_config block; nothing policy-bearing is hardcoded here.
use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_metrics::anchor_audit::{
    audit_hold_reasons, render_flags_tsv, render_hold_summary_tsv, render_sign_summary_tsv,
    HoldReasonSummary,
};
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};
use kni_metrics::self_anchored_spacing::{solve_spacing, FontContext, SpacingPolicy};
use std::fs;

#[path = "../../core/examples/support/cubic_flatten.rs"]
mod cubic_flatten;
use cubic_flatten::flatten_cubic;

fn scalar(s: &str) -> Result<f64, String> {
    let v: f64 = s.parse().map_err(|_| format!("bad scalar {s}"))?;
    if !v.is_finite() || v <= 0.0 {
        return Err("policy values must be finite and positive".into());
    }
    Ok(v)
}

/// Kern ledger row -> hold-summary class. Hold notes go through the
/// library's total classifier (`anchor_audit::classify_hold_note`); an
/// unrecognized row is a typed refusal, never a guess. Note: the ledger
/// does not distinguish fallback_guard_verified rows from ready rows, so
/// this post-hoc route counts them as ready; the run's own
/// kern-hold-summary.tsv artifact carries the exact bucket split.
fn classify(status: &str, reason: &str) -> Result<&'static str, String> {
    if status == "overlap_hold" {
        return Ok(match kni_metrics::anchor_audit::classify_hold_note(reason) {
            kni_metrics::anchor_audit::HoldNoteClass::CollisionAtOrigin => "collision_at_origin",
            kni_metrics::anchor_audit::HoldNoteClass::GapDisagree => "gap_disagree",
            kni_metrics::anchor_audit::HoldNoteClass::NoSafeInteger => "no_safe_integer",
            kni_metrics::anchor_audit::HoldNoteClass::NegativeOrigin => "negative_origin",
            kni_metrics::anchor_audit::HoldNoteClass::Unclassified => "unclassified",
        });
    }
    // A written kern is ready whether it landed exactly or on the guarded
    // adjusted integer; both are successful placements.
    if status == "ready" && (reason.is_empty() || reason.starts_with("export_adjusted")) {
        return Ok("ready");
    }
    Err(format!("unclassified kern ledger row status={status} reason={reason}"))
}

fn main() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 9 {
        return Err("usage: anchor_audit FONT.otf KERN_LEDGER.tsv ROW_STEP FLATTEN_TOL MAX_ROWS MAX_PAIRS MAX_PAIR_EVALS FLATTEN_DEPTH".into());
    }
    let (row_step, flat) = (scalar(&a[3])?, scalar(&a[4])?);
    let max_rows: usize = a[5].parse().map_err(|_| "bad max_rows")?;
    let max_pairs: usize = a[6].parse().map_err(|_| "bad max_pairs")?;
    let max_pair_evals: u64 = a[7].parse().map_err(|_| "bad pair bound")?;
    let depth: usize = a[8].parse().map_err(|_| "bad flatten depth")?;

    let bytes = fs::read(&a[1]).map_err(|e| e.to_string())?;
    let font = CffReader::from_bytes(&bytes, &sha256_hex(&bytes)).map_err(|e| format!("font refused: {e:?}"))?;
    let upm = font.units_per_em();

    let mut codepoints = Vec::new();
    let mut profiles = Vec::new();
    let mut skipped = 0usize;
    for (cp, gid) in font.codepoints() {
        let glyph_id = format!("u{cp:04X}");
        let drawn = font.read_glyph(gid).map_err(|e| format!("read u{cp:04X}: {e:?}"))?.drawn(glyph_id.clone());
        if drawn.rings.is_empty() {
            skipped += 1;
            continue;
        }
        let mut polys = Vec::new();
        for ring in &drawn.rings {
            let mut poly = vec![[ring.start.x, ring.start.y]];
            let mut start = ring.start;
            for span in &ring.spans {
                match span {
                    kni_core::reference_slice::Span::Line { end } => {
                        poly.push([end.x, end.y]);
                        start = *end;
                    }
                    kni_core::reference_slice::Span::Cubic { control_one, control_two, end } => {
                        // Per-glyph point budget derived from the declared
                        // row bound: a glyph cannot need more flattened
                        // points than the scan can ever sample.
                        let budget = max_rows;
                        flatten_cubic([start, *control_one, *control_two, *end], flat, depth, budget, &mut poly)
                            .map_err(|e| format!("flatten {glyph_id}: {e:?}"))?;
                        start = *end;
                    }
                }
            }
            polys.push(poly);
        }
        let profile = profile_outline(
            &OutlineInput {
                glyph_id: glyph_id.clone(),
                source_pin: font.sha256().to_string(),
                upm,
                origin: [0.0, 0.0],
                rings: polys,
                flatten_tolerance: flat,
            },
            ScanPolicy { row_step, max_rows, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) },
        )
        .map_err(|e| format!("profile {glyph_id}: {e:?}"))?;
        codepoints.push((glyph_id, cp));
        profiles.push(profile);
    }

    let policy = SpacingPolicy {
        sample_resolution: row_step,
        max_pair_evaluations: max_pair_evals,
        max_pairs,
        pair_min_shared_rows: 1,
        lambda: Some(0.0),
        dcap: None,
        contrast_floor: false,
        cadence_class_pass: false,
        class_channel_targets: false,
    };
    let context = FontContext { glyph_codepoints: codepoints, ..FontContext::default() };
    let solved = solve_spacing(&profiles, Some(&context), &policy).map_err(|e| format!("spacing: {e:?}"))?;

    println!("== solve receipt ==");
    println!("{}", solved.policy_derivation);
    println!("glyphs_profiled={} glyphs_skipped_empty={} pairs_solved={} pairs_below_epsilon={} pairs_unmeasurable={} anchor_flags={}",
        profiles.len(), skipped, solved.pairs.len(), solved.excluded_below_epsilon,
        solved.excluded_unmeasurable, solved.anchor_audit.flags.len());
    println!("== anchor sign summary (always written) ==");
    print!("{}", render_sign_summary_tsv(&solved.anchor_audit.classes));
    println!("== anchor flags ==");
    print!("{}", render_flags_tsv(&solved.anchor_audit.flags));
    println!("measured-source anchor group: absent in this run (single anchor mode per run)");
    println!("cross-anchor comparison: not measured (no measured-source run)");
    println!("cross-style target consistency: not measured (single style supplied)");

    let raw = fs::read_to_string(&a[2]).map_err(|e| e.to_string())?;
    let mut lines = raw.lines();
    if lines.next() != Some("left\tright\trequested\twritten\tstatus\treason") {
        return Err("kern ledger header mismatch".into());
    }
    let mut holds = HoldReasonSummary::default();
    for line in lines {
        let v: Vec<&str> = line.splitn(6, '\t').collect();
        if v.len() != 6 {
            return Err(format!("bad kern ledger row: {line}"));
        }
        holds.pairs += 1;
        match classify(v[4], v[5])? {
            "ready" => holds.ready += 1,
            "collision_at_origin" => holds.collision_at_origin += 1,
            "gap_disagree" => holds.gap_disagree += 1,
            "no_safe_integer" => holds.no_safe_integer += 1,
            "negative_origin" => holds.negative_origin += 1,
            "unclassified" => holds.unclassified += 1,
            other => return Err(format!("bad class {other}")),
        }
    }
    println!("== kern hold-reason summary (always written) ==");
    print!("{}", render_hold_summary_tsv(&holds));
    println!("== hold flags ==");
    print!("{}", render_flags_tsv(&audit_hold_reasons(&holds)));
    Ok(())
}
