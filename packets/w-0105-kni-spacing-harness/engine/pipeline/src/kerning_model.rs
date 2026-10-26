//! Model side of the pair-image observation: the distance the CURRENT generated-outline model (solve_spacing) gives for a pair,
//! and the comparison against an observed source distance. Read-only: it never edits `SpacingSolution.pairs`, never writes GPOS,
//! never invents a model value. An incomplete solution or an absent pair is a typed "no model", not a default.
//!
//! Frame: `PairPosition.origin_distance` is the glyph-origin distance in the solver's shared raw frame; the observed distance from
//! `kerning_measure` is in the units of the Frame the caller used to rasterise the SAME outlines the solver profiles came from
//! (origin at the outline's x=0). That equality of frames is a CALLER-ASSERTED precondition recorded in the receipt row
//! (`frame_assertion`), not something this module can verify.
use kni_metrics::self_anchored_spacing::SpacingSolution;

#[derive(Debug, Clone, PartialEq)]
pub enum ModelError {
    /// `complete == false` (excluded/held/numeric-failed pairs): no model is read from an incomplete solution.
    IncompleteSolution,
    /// The pair has no row (self pair, below-epsilon, unmeasurable, held, or excluded): there is no model value.
    NoModelForPair(String, String),
    DuplicatePairRow(String, String),
    NoGlyph(String),
    NonFinite,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ModelDistance { pub model_distance_units: f64, pub left_advance_units: f64 }

pub fn model_distance(sol: &SpacingSolution, left: &str, right: &str) -> Result<ModelDistance, ModelError> {
    if !sol.complete { return Err(ModelError::IncompleteSolution); }
    let mut rows = sol.pairs.iter().filter(|p| p.left == left && p.right == right);
    let row = rows.next().ok_or_else(|| ModelError::NoModelForPair(left.into(), right.into()))?;
    if rows.next().is_some() { return Err(ModelError::DuplicatePairRow(left.into(), right.into())); }
    let adv = sol.glyphs.iter().find(|g| g.glyph_id == left).ok_or_else(|| ModelError::NoGlyph(left.into()))?.advance;
    if !row.origin_distance.is_finite() || !adv.is_finite() { return Err(ModelError::NonFinite); }
    Ok(ModelDistance { model_distance_units: row.origin_distance, left_advance_units: adv })
}

/// Receipt row of one research observation candidate against the model. `residual_vs_advance` is the kern-shaped value
/// (observed origin distance - left advance, the same definition `generated_outline_kern` uses for the model residual);
/// `delta_vs_model` is observed - model distance. Neither is a GPOS value or training truth.
#[derive(Debug, Clone, PartialEq)]
pub struct PairComparison { pub left: String, pub right: String, pub observed_distance_units: f64, pub model_distance_units: f64, pub delta_vs_model: f64, pub residual_vs_advance: f64, pub image_sha256: String }

pub fn compare(sol: &SpacingSolution, left: &str, right: &str, obs: &crate::kerning_measure::PairObservation) -> Result<PairComparison, ModelError> {
    let m = model_distance(sol, left, right)?;
    let (delta, resid) = (obs.observed_distance_units - m.model_distance_units, obs.observed_distance_units - m.left_advance_units);
    if !delta.is_finite() || !resid.is_finite() { return Err(ModelError::NonFinite); }
    Ok(PairComparison { left: left.into(), right: right.into(), observed_distance_units: obs.observed_distance_units, model_distance_units: m.model_distance_units, delta_vs_model: delta, residual_vs_advance: resid, image_sha256: obs.image_sha256.clone() })
}

impl PairComparison {
    pub fn receipt_row(&self, frame_assertion: &str) -> String {
        format!("kern_observation_candidate\t{}\t{}\tobserved\t{:e}\tmodel\t{:e}\tdelta\t{:e}\tresidual_vs_advance\t{:e}\timage_sha256\t{}\tframe_assertion\t{}\tstatus\tRESEARCH_CANDIDATE_NOT_TRAINING_NOT_GPOS\n",
            self.left, self.right, self.observed_distance_units, self.model_distance_units, self.delta_vs_model, self.residual_vs_advance, self.image_sha256, frame_assertion)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kerning_measure::PairObservation;
    use kni_metrics::self_anchored_spacing::{GlyphSpacing, PairPosition, SpaceStatus};
    fn sol(complete: bool, pairs: Vec<PairPosition>) -> SpacingSolution {
        SpacingSolution { baseline: 0.0, x_height: 0.0, x_height_source: kni_metrics::self_anchored_spacing::XHeightSource::Ctx, cap_height: 0.0, font_median_pair_target: None,
            glyphs: vec![GlyphSpacing { glyph_id: "H".into(), lsb: 10.0, rsb: 10.0, advance: 700.0 }, GlyphSpacing { glyph_id: "o".into(), lsb: 5.0, rsb: 5.0, advance: 500.0 }],
            pairs, space_status: SpaceStatus::Absent, excluded_pairs: vec![], complete,
            excluded_self_pairs: 0, excluded_below_epsilon: 0, excluded_unmeasurable: 0, numeric_failed_pairs: 0, geometric_hold_pairs: 0, no_accepted_candidate_pairs: 0, hold_reasons: Vec::new(), pair_ledger: Vec::new(), fallback_pairs: Vec::new(), fallback_natural_clear_pairs: 0, fallback_verified_pairs: 0, numeric_failed_nonfinite: 0, numeric_failed_malformed: 0, numeric_failed_natural_unverifiable: 0, numeric_failed_natural_frame_conflict: 0, accounting_residual: 0, accounting_closed: true, contrast_floor_adjustments: vec![], contrast_floor_failures: vec![], policy_derivation: String::new(), unobserved_policy: Vec::new(), anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run() }
    }
    fn pp(l: &str, r: &str, d: f64) -> PairPosition { PairPosition { left: l.into(), right: r.into(), origin_distance: d, wall_gap: 0.0, optical_cost: 0.0, pair_target: None, compensated: false } }
    fn obs(v: f64) -> PairObservation { PairObservation { left: 0x48, right: 0x6F, observed_distance_units: v, model_distance_units: 0.0, residual_units: 0.0, iou: 1.0, image_sha256: "s".into() } }
    #[test]
    fn compares_without_touching_the_solution_and_refuses_to_invent() {
        let s = sol(true, vec![pp("H", "o", 690.0)]);
        let c = compare(&s, "H", "o", &obs(700.0)).unwrap();
        assert_eq!((c.model_distance_units, c.delta_vs_model, c.residual_vs_advance), (690.0, 10.0, 0.0));
        assert!(c.receipt_row("caller").contains("RESEARCH_CANDIDATE_NOT_TRAINING_NOT_GPOS"));
        assert_eq!(s.pairs.len(), 1);
        assert_eq!(compare(&s, "o", "H", &obs(1.0)), Err(ModelError::NoModelForPair("o".into(), "H".into())));
        assert_eq!(compare(&sol(false, vec![pp("H", "o", 690.0)]), "H", "o", &obs(1.0)), Err(ModelError::IncompleteSolution));
        assert!(matches!(compare(&sol(true, vec![pp("H", "o", 1.0), pp("H", "o", 2.0)]), "H", "o", &obs(1.0)), Err(ModelError::DuplicatePairRow(..))));
        assert_eq!(compare(&sol(true, vec![pp("X", "o", 1.0)]), "X", "o", &obs(1.0)), Err(ModelError::NoGlyph("X".into())));
        assert_eq!(compare(&sol(true, vec![pp("H", "o", f64::NAN)]), "H", "o", &obs(1.0)), Err(ModelError::NonFinite));
        assert_eq!(compare(&s, "H", "o", &obs(f64::MAX * 2.0 / 2.0 + f64::MAX)), Err(ModelError::NonFinite));
    }
}
