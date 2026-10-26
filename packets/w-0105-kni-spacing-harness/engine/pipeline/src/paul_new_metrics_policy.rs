//! Paul New metrics policy (engine/pipeline/src/paul_new_metrics_policy.rs).
//! Separate explicit policy module: NOT the generic signed post-step in post_metrics, and never
//! mixed with it. Owner-declared 2026-10-18 03:05/03:06 (supersedes the 2026-10-17 declaration):
//! the 2 px tile frame is a source artifact, never design; default sidebearings are lsb = -1 and
//! rsb = -1 on edge-reaching glyphs, margin - 1 per side on margin glyphs, and the advance is the
//! frame-stripped em box (population median ink xMax - 1), derived per run - not a fixed constant.
//! The anatomy is never scaled, stretched, or shifted to reach a metric target.
//!
//! Physical constraint (why this module MEASURES instead of editing): an OTF has no independent
//! RSB field. With the em origin at the declared lsb 0, RSB = advance - ink xMax. With the advance
//! fixed at 696 and the ink fixed by the anatomy, the achieved RSB is whatever the anatomy gives.
//! A target the anatomy cannot reach is a TYPED WARNING row in the receipt, never a silent
//! geometry, advance, or bearing change.

// Cross-reference to the anchor's declared advance: the equality with this module's declared
// fixed advance is pinned by the test below (no second source of truth may drift).
#[allow(unused_imports)]
use crate::paul_new_anchor::PAUL_NEW_ADVANCE_UNITS;
use crate::post_metrics::tsv_escape;

/// The 2026-10-17 fixed advance (em-box raw width, the K_X basis). No longer the shipped
/// advance: since the 2026-10-18 frame ruling the shipped advance is derived per run (population
/// median ink xMax + PAUL_NEW_TARGET_RSB) and passed to evaluate_glyph as a parameter.
#[allow(dead_code)] // K_X basis documentation; pinned against the anchor constant in tests
pub const PAUL_NEW_EM_BOX_WIDTH: i64 = 696;
/// Declared default left sidebearing (owner 2026-10-17): the em origin is x = 0.
pub const PAUL_NEW_DECLARED_LSB: i64 = 0;
/// Declared default right sidebearing TARGET (owner 2026-10-17). A target, not an edit: the
/// achieved RSB follows the physical constraint above and is reported per glyph.
pub const PAUL_NEW_TARGET_RSB: i64 = -1;

/// Typed warning vocabulary (stable strings; receipts match on them).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PolicyWarning {
    /// advance != the declared fixed 696 (fixed-advance policy broken before any bearing verdict).
    AdvanceOffPolicy,
    /// achieved RSB != the declared target -1 (physical constraint; anatomy is left untouched).
    RsbTargetMiss,
}
impl PolicyWarning {
    pub fn code(self) -> &'static str {
        match self {
            Self::AdvanceOffPolicy => "advance_off_policy",
            Self::RsbTargetMiss => "rsb_target_miss",
        }
    }
}

/// One glyph's measured metrics against the policy. Pure data: nothing here mutates a font.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GlyphVerdict {
    pub glyph_id: String,
    pub advance: i64,
    /// achieved LSB = ink xMin - declared em origin (0). Interior whitespace stays anatomy: a
    /// glyph whose ink starts right of x = 0 reports that distance, it is never pulled to 0.
    /// None for inkless glyphs (space/.notdef: no ink, no bearing verdict).
    pub achieved_lsb: Option<i64>,
    /// achieved RSB = advance - ink xMax. None for inkless glyphs.
    pub achieved_rsb: Option<i64>,
    pub warnings: Vec<PolicyWarning>,
}

/// Evaluate one glyph against the policy. `ink_bounds_x` = (xMin, xMax) of the FINAL outline in
/// output units, None when the glyph has no ink. `declared_advance` = the run's derived
/// frame-stripped advance (population rule; see module header). Pure: reads measured values,
/// never changes them.
pub fn evaluate_glyph(glyph_id: &str, advance: i64, ink_bounds_x: Option<(i64, i64)>, declared_advance: i64) -> GlyphVerdict {
    let mut warnings = Vec::new();
    if advance != declared_advance {
        warnings.push(PolicyWarning::AdvanceOffPolicy);
    }
    let (achieved_lsb, achieved_rsb) = match ink_bounds_x {
        Some((xmin, xmax)) => {
            let rsb = advance - xmax;
            if rsb != PAUL_NEW_TARGET_RSB {
                warnings.push(PolicyWarning::RsbTargetMiss);
            }
            (Some(xmin - PAUL_NEW_DECLARED_LSB), Some(rsb))
        }
        None => (None, None),
    };
    GlyphVerdict { glyph_id: glyph_id.to_string(), advance, achieved_lsb, achieved_rsb, warnings }
}

/// Typed receipt (TSV): a policy header (declared values + the physical RSB formula), one row per
/// glyph with its measured achievements and warning codes, and a summary row. Stable vocabulary;
/// every free-text cell goes through the post_metrics TSV escape.
pub fn receipt_tsv(verdicts: &[GlyphVerdict], declared_advance: i64) -> String {
    let mut s = format!(
        "# paul_new_metrics_policy\tdeclared_advance\t{declared_advance}\tdeclared_lsb\t{PAUL_NEW_DECLARED_LSB}\ttarget_rsb\t{PAUL_NEW_TARGET_RSB}\trsb_formula\tadvance-ink_xmax\tsemantics\tmeasured_not_enforced\n"
    );
    s.push_str("glyph_id\tadvance\tachieved_lsb\tachieved_rsb\twarning\n");
    let (mut met, mut miss, mut off) = (0usize, 0usize, 0usize);
    for v in verdicts {
        if v.achieved_rsb == Some(PAUL_NEW_TARGET_RSB) {
            met += 1;
        }
        if v.warnings.contains(&PolicyWarning::RsbTargetMiss) {
            miss += 1;
        }
        if v.warnings.contains(&PolicyWarning::AdvanceOffPolicy) {
            off += 1;
        }
        let warn: Vec<&str> = v.warnings.iter().map(|w| w.code()).collect();
        s.push_str(&format!(
            "{}\t{}\t{}\t{}\t{}\n",
            tsv_escape(&v.glyph_id),
            v.advance,
            v.achieved_lsb.map_or("no_ink".to_string(), |x| x.to_string()),
            v.achieved_rsb.map_or("no_ink".to_string(), |x| x.to_string()),
            warn.join(","),
        ));
    }
    s.push_str(&format!(
        "# summary\tglyphs\t{}\ttarget_rsb_met\t{}\trsb_target_miss\t{}\tadvance_off_policy\t{}\n",
        verdicts.len(),
        met,
        miss,
        off,
    ));
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn em_box_width_matches_the_anchor_constant() {
        assert_eq!(PAUL_NEW_EM_BOX_WIDTH as f64, PAUL_NEW_ADVANCE_UNITS);
    }

    #[test]
    fn anatomy_unreachable_target_is_a_typed_warning_not_an_edit() {
        // ink fills the whole em: achieved rsb 0, target -1 cannot be reached without stretching
        let v = evaluate_glyph("A", 696, Some((0, 696)), 696);
        assert_eq!((v.achieved_lsb, v.achieved_rsb), (Some(0), Some(0)));
        assert_eq!(v.warnings, vec![PolicyWarning::RsbTargetMiss]);
        // ink reaching 1 unit past the em right edge achieves the target exactly: no warning
        let v = evaluate_glyph("B", 696, Some((1, 697)), 696);
        assert_eq!((v.achieved_lsb, v.achieved_rsb), (Some(1), Some(-1)));
        assert!(v.warnings.is_empty());
        // interior whitespace is anatomy: ink starting at 50 reports achieved lsb 50, never pulled to 0
        let v = evaluate_glyph("C", 696, Some((50, 690)), 696);
        assert_eq!(v.achieved_lsb, Some(50));
        assert_eq!(v.achieved_rsb, Some(6));
        assert_eq!(v.warnings, vec![PolicyWarning::RsbTargetMiss]);
    }

    #[test]
    fn off_policy_advance_and_inkless_glyphs_are_typed() {
        let v = evaluate_glyph("D", 695, Some((0, 695)), 696);
        assert!(v.warnings.contains(&PolicyWarning::AdvanceOffPolicy));
        let v = evaluate_glyph("space", 696, None, 696);
        assert_eq!((v.achieved_lsb, v.achieved_rsb), (None, None));
        assert!(v.warnings.is_empty(), "an inkless glyph has no bearing verdict");
    }

    #[test]
    fn receipt_is_typed_and_escaped() {
        let vs = vec![
            evaluate_glyph("A", 696, Some((0, 696)), 696),
            evaluate_glyph("B", 696, Some((1, 697)), 696),
            evaluate_glyph("space", 696, None, 696),
            evaluate_glyph("bad\tx", 695, Some((0, 695)), 696),
        ];
        let t = receipt_tsv(&vs, 696);
        assert!(t.contains("# paul_new_metrics_policy\tdeclared_advance\t696\tdeclared_lsb\t0\ttarget_rsb\t-1\trsb_formula\tadvance-ink_xmax\tsemantics\tmeasured_not_enforced"), "{t}");
        assert!(t.contains("A\t696\t0\t0\trsb_target_miss\n"), "{t}");
        assert!(t.contains("B\t696\t1\t-1\t\n"), "{t}");
        assert!(t.contains("space\t696\tno_ink\tno_ink\t\n"), "{t}");
        assert!(t.contains("bad\\tx\t695\t0\t0\tadvance_off_policy,rsb_target_miss\n"), "{t}");
        assert!(t.contains("# summary\tglyphs\t4\ttarget_rsb_met\t1\trsb_target_miss\t2\tadvance_off_policy\t1\n"), "{t}");
    }
}
