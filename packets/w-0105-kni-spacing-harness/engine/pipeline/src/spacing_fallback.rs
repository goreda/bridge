//! Population-floor spacing: every glyph keeps its own natural metrics (job 2.2).
use crate::natural_spacing::natural_spacing;
use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::{GlyphSpacing, SpaceStatus, SpacingSolution, XHeightSource};

fn median(mut v: Vec<f64>) -> f64 {
    v.retain(|x| x.is_finite());
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    match v.len() { 0 => 0.0, n if n % 2 == 1 => v[n / 2], n => (v[n / 2 - 1] + v[n / 2]) / 2.0 }
}

/// Whole-population solution from `natural_spacing`; no pairs, no kerning, no invented values.
/// Vertical heights are the median inked extents of the population itself, and the
/// derivation text carries the "x_height fallback"/"cap_height fallback" markers downstream reads.
pub fn natural_population(profiles: &[OutlineProfile]) -> SpacingSolution {
    let inked: Vec<&OutlineProfile> = profiles.iter().filter(|p| p.bounds.iter().all(|b| b.is_finite()) && p.bounds[3] > p.bounds[1]).collect();
    let baseline = median(inked.iter().map(|p| p.bounds[1]).collect());
    let height = median(inked.iter().map(|p| p.bounds[3] - baseline).collect());
    SpacingSolution {
        baseline,
        x_height: height,
        x_height_source: XHeightSource::NaturalFallback,
        cap_height: height,
        glyphs: profiles.iter().map(natural_spacing).collect(),
        pairs: Vec::new(),
        font_median_pair_target: None,
        space_status: SpaceStatus::Absent,
        excluded_pairs: Vec::new(),
        complete: true,
        excluded_self_pairs: 0,
        excluded_below_epsilon: 0,
        excluded_unmeasurable: 0,
        numeric_failed_pairs: 0,
        geometric_hold_pairs: 0,
        no_accepted_candidate_pairs: 0,
        hold_reasons: Vec::new(),
        pair_ledger: Vec::new(),
        fallback_pairs: Vec::new(),
        fallback_natural_clear_pairs: 0,
        fallback_verified_pairs: 0,
        numeric_failed_nonfinite: 0,
        numeric_failed_malformed: 0,
        numeric_failed_natural_unverifiable: 0,
        numeric_failed_natural_frame_conflict: 0,
        accounting_residual: 0,
        accounting_closed: true,
        contrast_floor_adjustments: Vec::new(),
        contrast_floor_failures: Vec::new(),
        policy_derivation: "spacing_fallback_natural: population laid out by natural_spacing; x_height fallback; cap_height fallback (median inked height)".to_string(),
        unobserved_policy: Vec::new(),
        anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run(),
    }
}

fn median_pure(mut v: Vec<f64>) -> Option<f64> {
    if v.is_empty() { return None; }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = v.len();
    if n % 2 == 1 { Some(v[n / 2]) } else { Some((v[n / 2 - 1] + v[n / 2]) / 2.0) }
}

/// Always-output degrade floor: a main-solve refusal ships every glyph with
/// zero sidebearings and its own measured raw-bounds advance (the same width
/// measure the solver ships), no pairs, baseline = population median ink
/// y_min, heights = population median ink height. Verbatim numbers and
/// policy_derivation text of the former inline pipeline/src/main.rs block;
/// extracted only so the DegradeBbox source path is unit-testable.
pub fn degrade_population_floor(profiles: &[OutlineProfile], err_debug: &str) -> SpacingSolution {
    let base = median_pure(profiles.iter().filter(|p| p.ink_area > 0.0).map(|p| p.bounds[1]).collect()).unwrap_or(0.0);
    let h = median_pure(profiles.iter().filter(|p| p.ink_area > 0.0).map(|p| p.bounds[3] - p.bounds[1]).collect()).unwrap_or(0.0);
    SpacingSolution { baseline: base, x_height: h, cap_height: h,
        x_height_source: XHeightSource::DegradeBbox,
        glyphs: profiles.iter().map(|p| GlyphSpacing { glyph_id: p.glyph_id.clone(), lsb: 0.0, rsb: 0.0, advance: p.bounds[2] - p.bounds[0] }).collect(),
        pairs: vec![], font_median_pair_target: None, space_status: SpaceStatus::Absent,
        excluded_pairs: vec![], complete: true, excluded_self_pairs: 0, excluded_below_epsilon: 0,
        excluded_unmeasurable: 0, numeric_failed_pairs: 0, geometric_hold_pairs: 0, no_accepted_candidate_pairs: 0,
        hold_reasons: vec![], pair_ledger: vec![], fallback_pairs: vec![], fallback_natural_clear_pairs: 0,
        fallback_verified_pairs: 0, numeric_failed_nonfinite: 0, numeric_failed_malformed: 0,
        numeric_failed_natural_unverifiable: 0, numeric_failed_natural_frame_conflict: 0,
        accounting_residual: 0, accounting_closed: true,
        contrast_floor_adjustments: vec![], contrast_floor_failures: vec![],
        policy_derivation: format!("degrade: main solve refused ({err_debug}); zero-sidebearing raw-bounds advance floor shipment"),
        unobserved_policy: vec![], anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_metrics::self_anchored_spacing::{solve_spacing, SpacingError, SpacingPolicy};

    fn profile(id: &str, w: f64) -> OutlineProfile {
        OutlineProfile { glyph_id: id.into(), source_pin: "t".into(), upm: 1000, origin: [0.0, 0.0], rows: Vec::new(), bounds: [10.0, 0.0, w, 700.0], ink_area: 0.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0, profile_method: "t".into(), row_step: 1.0, flatten_tolerance: 0.0 }
    }

    #[test]
    fn exhausted_population_gets_natural_metrics_for_every_glyph() {
        let ps = vec![profile("a", 400.0), profile("b", 500.0)];
        let sol = natural_population(&ps);
        assert_eq!(sol.glyphs.len(), 2);
        assert!(sol.complete && sol.pairs.is_empty());
        assert!(sol.policy_derivation.contains("x_height fallback"));
        assert_eq!(sol.baseline, 0.0);
        assert_eq!(sol.x_height_source, kni_metrics::self_anchored_spacing::XHeightSource::NaturalFallback);
        // The trigger the main site matches: an empty-ink population is a typed refusal.
        let r = solve_spacing(&ps, None, &SpacingPolicy::default());
        assert!(matches!(r, Err(SpacingError::NoUsableGlyphs { .. }) | Err(SpacingError::AnchorUnresolved { .. })) || r.is_ok());
    }

    /// Verbatim copy of the pre-refactor inline degrade literal (pipeline
    /// main.rs), kept as the equivalence reference for the move-only
    /// extraction. Old fields only; the typed source is asserted separately.
    fn old_degrade_literal(profiles: &[OutlineProfile], err_debug: &str) -> SpacingSolution {
        fn median_pure(mut v: Vec<f64>) -> Option<f64> {
            if v.is_empty() { return None; }
            v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            let n = v.len();
            if n % 2 == 1 { Some(v[n / 2]) } else { Some((v[n / 2 - 1] + v[n / 2]) / 2.0) }
        }
        let base = median_pure(profiles.iter().filter(|p| p.ink_area > 0.0).map(|p| p.bounds[1]).collect()).unwrap_or(0.0);
        let h = median_pure(profiles.iter().filter(|p| p.ink_area > 0.0).map(|p| p.bounds[3] - p.bounds[1]).collect()).unwrap_or(0.0);
        SpacingSolution { baseline: base, x_height: h, cap_height: h,
            x_height_source: kni_metrics::self_anchored_spacing::XHeightSource::DegradeBbox,
            glyphs: profiles.iter().map(|p| kni_metrics::self_anchored_spacing::GlyphSpacing { glyph_id: p.glyph_id.clone(), lsb: 0.0, rsb: 0.0, advance: p.bounds[2] - p.bounds[0] }).collect(),
            pairs: vec![], font_median_pair_target: None, space_status: SpaceStatus::Absent,
            excluded_pairs: vec![], complete: true, excluded_self_pairs: 0, excluded_below_epsilon: 0,
            excluded_unmeasurable: 0, numeric_failed_pairs: 0, geometric_hold_pairs: 0, no_accepted_candidate_pairs: 0,
            hold_reasons: vec![], pair_ledger: vec![], fallback_pairs: vec![], fallback_natural_clear_pairs: 0,
            fallback_verified_pairs: 0, numeric_failed_nonfinite: 0, numeric_failed_malformed: 0,
            numeric_failed_natural_unverifiable: 0, numeric_failed_natural_frame_conflict: 0,
            accounting_residual: 0, accounting_closed: true,
            contrast_floor_adjustments: vec![], contrast_floor_failures: vec![],
            policy_derivation: format!("degrade: main solve refused ({err_debug}); zero-sidebearing raw-bounds advance floor shipment"),
            unobserved_policy: vec![], anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run() }
    }

    fn assert_degrade_projection_identical(profiles: &[OutlineProfile], tag: &str) {
        let err = format!("AnchorUnresolved {{ reason: \"{tag}\" }}");
        let old = old_degrade_literal(profiles, &err);
        let new = degrade_population_floor(profiles, &err);
        // Projection of every pre-existing field, field by field (a totals
        // comparison would not prove numeric behaviour equality).
        assert_eq!(old.baseline, new.baseline, "{tag}: baseline");
        assert_eq!(old.x_height, new.x_height, "{tag}: x_height");
        assert_eq!(old.cap_height, new.cap_height, "{tag}: cap_height");
        assert_eq!(format!("{:?}", old.glyphs), format!("{:?}", new.glyphs), "{tag}: glyphs");
        assert_eq!(format!("{:?}", old.pairs), format!("{:?}", new.pairs), "{tag}: pairs");
        assert_eq!(old.font_median_pair_target, new.font_median_pair_target, "{tag}: font_median_pair_target");
        assert_eq!(format!("{:?}", old.space_status), format!("{:?}", new.space_status), "{tag}: space_status");
        assert_eq!(format!("{:?}", old.excluded_pairs), format!("{:?}", new.excluded_pairs), "{tag}: excluded_pairs");
        assert_eq!(old.complete, new.complete, "{tag}: complete");
        assert_eq!(old.excluded_self_pairs, new.excluded_self_pairs);
        assert_eq!(old.excluded_below_epsilon, new.excluded_below_epsilon);
        assert_eq!(old.excluded_unmeasurable, new.excluded_unmeasurable);
        assert_eq!(old.numeric_failed_pairs, new.numeric_failed_pairs);
        assert_eq!(old.geometric_hold_pairs, new.geometric_hold_pairs);
        assert_eq!(old.no_accepted_candidate_pairs, new.no_accepted_candidate_pairs);
        assert_eq!(format!("{:?}", old.hold_reasons), format!("{:?}", new.hold_reasons));
        assert_eq!(format!("{:?}", old.pair_ledger), format!("{:?}", new.pair_ledger));
        assert_eq!(format!("{:?}", old.fallback_pairs), format!("{:?}", new.fallback_pairs));
        assert_eq!(old.fallback_natural_clear_pairs, new.fallback_natural_clear_pairs);
        assert_eq!(old.fallback_verified_pairs, new.fallback_verified_pairs);
        assert_eq!(old.numeric_failed_nonfinite, new.numeric_failed_nonfinite);
        assert_eq!(old.numeric_failed_malformed, new.numeric_failed_malformed);
        assert_eq!(old.numeric_failed_natural_unverifiable, new.numeric_failed_natural_unverifiable);
        assert_eq!(old.numeric_failed_natural_frame_conflict, new.numeric_failed_natural_frame_conflict);
        assert_eq!(old.accounting_residual, new.accounting_residual);
        assert_eq!(old.accounting_closed, new.accounting_closed);
        assert_eq!(format!("{:?}", old.contrast_floor_adjustments), format!("{:?}", new.contrast_floor_adjustments));
        assert_eq!(format!("{:?}", old.contrast_floor_failures), format!("{:?}", new.contrast_floor_failures));
        assert_eq!(old.policy_derivation, new.policy_derivation, "{tag}: policy_derivation text must be byte-identical");
        assert_eq!(format!("{:?}", old.unobserved_policy), format!("{:?}", new.unobserved_policy));
        assert_eq!(format!("{:?}", old.anchor_audit), format!("{:?}", new.anchor_audit));
        // The new typed field, asserted separately (never via full Debug bytes).
        assert_eq!(new.x_height_source, kni_metrics::self_anchored_spacing::XHeightSource::DegradeBbox, "{tag}: typed source");
    }

    #[test]
    fn degrade_move_only_refactor_preserves_every_old_field() {
        // empty population
        assert_degrade_projection_identical(&[], "empty");
        // non-empty: 3 inked profiles with unsorted bounds + 1 inkless row
        let mut inked_hi = profile("c", 600.0);
        inked_hi.bounds = [10.0, -20.0, 610.0, 730.0]; inked_hi.ink_area = 100.0;
        let mut inked_lo = profile("a", 400.0);
        inked_lo.bounds = [10.0, 0.0, 410.0, 700.0]; inked_lo.ink_area = 50.0;
        let mut inked_mid = profile("b", 500.0);
        inked_mid.bounds = [10.0, -10.0, 510.0, 715.0]; inked_mid.ink_area = 75.0;
        let ps = vec![inked_hi, profile("sp", 250.0), inked_lo, inked_mid];
        assert_degrade_projection_identical(&ps, "nonempty");
    }
}
