//! Systematic anchor-error detector.
//!
//! A wrong spacing anchor does not move one pair; it shifts every pair whose
//! target came from that anchor in one direction. No per-pair check can see
//! that, because each placement is still internally consistent. This module
//! detects the two systematic signatures of a wrong anchor over residuals a
//! solve already produced:
//!
//! 1. Per-class residual sign imbalance. Under a correct anchor the residual
//!    of a pair is as likely to be positive as negative, so among the n
//!    nonzero residuals of one class the count of positives follows
//!    Binomial(n, 1/2). A positive share outside the three-sigma band of
//!    that null is a typed flag: the class is systematically shifted. The
//!    flag never drops or alters the pair; it is a ledger row naming the
//!    anomaly with its measured values.
//! 2. Cross-style target consistency. The same class asks for a similar
//!    target across styles of one family. A class whose per-style median
//!    target deviates from the family grand median by more than the declared
//!    multiple of the median absolute deviation is a typed flag.
//!
//! Both checks are pure analysis over rows the caller already holds. They
//! emit typed flag rows plus an always-written summary, and they never
//! remove data.

use std::collections::BTreeMap;
use std::fmt::Write as _;

/// CONVENTION (declared): the sign-imbalance band half-width in standard
/// deviations of the Binomial(n, 1/2) null. Three sigmas is the two-sided
/// normal band containing about 99.73% of a null population, so a class of
/// unbiased residuals crosses it by chance with probability ~0.0027.
pub const SIGN_TEST_SIGMAS: f64 = 3.0;

/// CONVENTION (declared): minimum nonzero-residual count before the sign
/// test applies to a class. Derivation: the normal approximation to
/// Binomial(n, p) is accepted once n*p*(1-p) >= 9; at p = 1/2 that bound is
/// n >= 36. Below it the three-sigma band is no longer the claimed tail and
/// the class is reported as below the minimum sample instead of flagged.
pub const SIGN_TEST_MIN_PAIRS: usize = 36;

/// CONVENTION (declared): a per-style class target median is an outlier when
/// its distance from the grand median exceeds this multiple of the median
/// absolute deviation across styles.
pub const CROSS_STYLE_MAD_FACTOR: f64 = 2.0;

/// CONVENTION (derived): minimum number of styles for the cross-style check.
/// With k = 2 styles the two deviations are equal and the MAD equals that
/// common deviation, so every ratio is exactly 1 and the check can never
/// flag; the smallest population in which a flag is possible is k = 3.
pub const CROSS_STYLE_MIN_STYLES: usize = 3;


/// CONVENTION (declared): maximum kern hold share of the pair population
/// before the run flags. In a healthy run the solver places the population
/// inside its feasible region, so held pairs (the export could not place
/// them safely at the solver's answer) are a small tail; one pair in five
/// failing to place means the population was pushed outside the feasible
/// region, which is the signature of a wrong anchor rather than of a few
/// difficult pairs. The value is a declared starting threshold, not a
/// measured one.
pub const HOLD_RATE_MAX: f64 = 0.20;

/// Which tail the sign imbalance fell into: the direction the class is
/// systematically shifted towards.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignImbalanceDirection {
    /// Positive residuals dominate: the class is shifted towards widening.
    Positive,
    /// Negative residuals dominate: the class is shifted towards tightening.
    Negative,
}

/// One typed anomaly row. Flags are emitted alongside the always-written
/// summary; they never remove or change any pair.
#[derive(Debug, Clone, PartialEq)]
pub enum AnchorAuditFlag {
    /// A class whose residual sign share is outside the declared
    /// three-sigma Binomial(n, 1/2) band.
    ClassResidualSignImbalance {
        class: String,
        nonzero_residuals: usize,
        zero_residuals: usize,
        positive_residuals: usize,
        positive_share: f64,
        sigma_lower: f64,
        sigma_upper: f64,
        direction: SignImbalanceDirection,
    },
    /// A class whose per-style median target deviates from the family grand
    /// median by more than the declared multiple of the MAD.
    CrossStyleTargetOutlier {
        class: String,
        style: String,
        style_median: f64,
        grand_median: f64,
        median_absolute_deviation: f64,
        /// |style_median - grand_median| / MAD; infinite when the MAD is
        /// zero and the deviation is not.
        deviation_over_mad: f64,
    },
    /// The held share of the kern population exceeded the declared maximum.
    KernHoldRateExceeded {
        pairs: usize,
        held_pairs: usize,
        hold_rate: f64,
        max_rate: f64,
        collision_at_origin: usize,
        gap_disagree: usize,
        no_safe_integer: usize,
        negative_origin: usize,
        unclassified: usize,
    },
}

/// Always-written per-class sign row: the full accounting behind any flag,
/// written for every class whether it flags or not.
#[derive(Debug, Clone, PartialEq)]
pub struct ClassSignSummary {
    pub class: String,
    /// Every row handed to the audit for this class.
    pub residuals: usize,
    /// Rows excluded from sign counting because the residual was not finite.
    pub nonfinite_residuals: usize,
    /// Rows excluded from the binomial count because the residual was
    /// exactly zero: a zero carries no sign and would dilute the share.
    pub zero_residuals: usize,
    pub positive_residuals: usize,
    pub negative_residuals: usize,
    /// positive / nonzero, present only when the class reached the declared
    /// minimum sample; `None` marks below-minimum, not zero.
    pub positive_share: Option<f64>,
    /// True when this class produced a `ClassResidualSignImbalance` flag.
    pub flagged: bool,
}

/// Audit output: the typed flags plus the always-written per-class summary.
/// `classes` is sorted by class name; `flags` follows that same class order.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AnchorAuditReport {
    pub flags: Vec<AnchorAuditFlag>,
    pub classes: Vec<ClassSignSummary>,
}

impl AnchorAuditReport {
    /// The empty report written by constructors that never ran a solve:
    /// empty means "not measured", never "measured and clean".
    pub fn not_run() -> Self {
        Self { flags: Vec::new(), classes: Vec::new() }
    }
}

fn median(sorted: &[f64]) -> f64 {
    let n = sorted.len();
    if n % 2 == 1 { sorted[n / 2] } else { (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0 }
}

/// Per-class residual sign imbalance over `(class, residual)` rows from one
/// solve. The caller decides the population; this function never filters
/// beyond the declared zero/non-finite exclusions, which stay visible in the
/// summary rows.
pub fn audit_residual_signs(rows: &[(String, f64)]) -> AnchorAuditReport {
    let mut by_class: BTreeMap<&str, Vec<f64>> = BTreeMap::new();
    for (class, residual) in rows {
        by_class.entry(class.as_str()).or_default().push(*residual);
    }
    let mut report = AnchorAuditReport::not_run();
    for (class, residuals) in by_class {
        let total = residuals.len();
        let nonfinite = residuals.iter().filter(|r| !r.is_finite()).count();
        let zeros = residuals.iter().filter(|r| r.is_finite() && **r == 0.0).count();
        let positives = residuals.iter().filter(|r| r.is_finite() && **r > 0.0).count();
        let negatives = residuals.iter().filter(|r| r.is_finite() && **r < 0.0).count();
        let nonzero = positives + negatives;
        let share = if nonzero >= SIGN_TEST_MIN_PAIRS { Some(positives as f64 / nonzero as f64) } else { None };
        let mut flagged = false;
        if let Some(share) = share {
            // sigma of the Binomial(n, 1/2) share: sqrt(p(1-p)/n) = 1/(2*sqrt(n)).
            let sigma = 0.5 / (nonzero as f64).sqrt();
            let lower = 0.5 - SIGN_TEST_SIGMAS * sigma;
            let upper = 0.5 + SIGN_TEST_SIGMAS * sigma;
            if share < lower || share > upper {
                flagged = true;
                report.flags.push(AnchorAuditFlag::ClassResidualSignImbalance {
                    class: class.to_string(),
                    nonzero_residuals: nonzero,
                    zero_residuals: zeros,
                    positive_residuals: positives,
                    positive_share: share,
                    sigma_lower: lower,
                    sigma_upper: upper,
                    direction: if share < lower { SignImbalanceDirection::Negative } else { SignImbalanceDirection::Positive },
                });
            }
        }
        report.classes.push(ClassSignSummary {
            class: class.to_string(),
            residuals: total,
            nonfinite_residuals: nonfinite,
            zero_residuals: zeros,
            positive_residuals: positives,
            negative_residuals: negatives,
            positive_share: share,
            flagged,
        });
    }
    report
}

/// One style's observed class targets: `(class, target)` rows, any number of
/// observations per class. The audit reduces them to the per-style median
/// per class before comparing across styles.
#[derive(Debug, Clone, PartialEq)]
pub struct StyleClassTargets {
    pub style: String,
    pub class_targets: Vec<(String, f64)>,
}

/// Cross-style target consistency: for every class observed in at least one
/// style, compare each style's median target against the grand median of the
/// per-style medians, flagged past the declared MAD multiple. Returns no
/// rows below `CROSS_STYLE_MIN_STYLES` styles (see its derivation: with two
/// styles the ratio is exactly 1 for every class and the check cannot flag).
pub fn audit_cross_style_targets(styles: &[StyleClassTargets]) -> Vec<AnchorAuditFlag> {
    if styles.len() < CROSS_STYLE_MIN_STYLES {
        return Vec::new();
    }
    // class -> [(style_index, per-style median target)]
    let mut by_class: BTreeMap<&str, Vec<(usize, f64)>> = BTreeMap::new();
    for (style_index, style) in styles.iter().enumerate() {
        let mut own: BTreeMap<&str, Vec<f64>> = BTreeMap::new();
        for (class, target) in &style.class_targets {
            if target.is_finite() {
                own.entry(class.as_str()).or_default().push(*target);
            }
        }
        for (class, mut targets) in own {
            targets.sort_by(f64::total_cmp);
            by_class.entry(class).or_default().push((style_index, median(&targets)));
        }
    }
    let mut flags = Vec::new();
    for (class, medians) in by_class {
        let mut values: Vec<f64> = medians.iter().map(|(_, m)| *m).collect();
        values.sort_by(f64::total_cmp);
        let grand = median(&values);
        let mut deviations: Vec<f64> = values.iter().map(|v| (v - grand).abs()).collect();
        deviations.sort_by(f64::total_cmp);
        let mad = median(&deviations);
        for (style_index, style_median) in medians {
            let deviation = (style_median - grand).abs();
            // MAD == 0 means the family agrees exactly on this class; any
            // nonzero deviation is then a flag, and the ratio is infinite.
            let ratio = if mad == 0.0 {
                if deviation == 0.0 { 0.0 } else { f64::INFINITY }
            } else {
                deviation / mad
            };
            if ratio > CROSS_STYLE_MAD_FACTOR {
                flags.push(AnchorAuditFlag::CrossStyleTargetOutlier {
                    class: class.to_string(),
                    style: styles[style_index].style.clone(),
                    style_median,
                    grand_median: grand,
                    median_absolute_deviation: mad,
                    deviation_over_mad: ratio,
                });
            }
        }
    }
    flags
}


/// Always-written kern hold-reason summary: the whole kern population of a
/// run by note class. `ready` and `fallback_ready` are successful placements
/// (fallback rows carry their recovery label but did place); the other three
/// classes are held pairs.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct HoldReasonSummary {
    pub pairs: usize,
    pub ready: usize,
    pub fallback_ready: usize,
    pub collision_at_origin: usize,
    pub gap_disagree: usize,
    pub no_safe_integer: usize,
    /// Held pairs of the declared CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN
    /// class: the post-compensation origin fell below zero and the pair
    /// ships kernless.
    pub negative_origin: usize,
    /// Held pairs whose note matched no declared producer shape: counted
    /// here so a held pair is never invisible; a nonzero count says the
    /// taxonomy is behind the producers.
    pub unclassified: usize,
}

impl HoldReasonSummary {
    /// Pairs the export could not place safely at the solver's answer.
    pub fn held(&self) -> usize {
        self.collision_at_origin + self.gap_disagree + self.no_safe_integer
            + self.negative_origin + self.unclassified
    }
}

/// Typed classification of one held kern pair's note. Total by design:
/// every held pair lands in exactly one class; a note shape this version
/// does not know is `Unclassified` - counted and visible, never guessed,
/// never silently dropped.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HoldNoteClass {
    CollisionAtOrigin,
    GapDisagree,
    NoSafeInteger,
    /// The declared CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN class.
    NegativeOrigin,
    Unclassified,
}

/// Classify the note of one pair from the kern overlap-hold bucket. The
/// covered shapes are the four hold producers in
/// `crate::generated_outline_kern`; anything else is `Unclassified`, so a
/// new producer surfaces as a count instead of breaking the run.
pub fn classify_hold_note(note: &str) -> HoldNoteClass {
    if note.starts_with("collision at exact solver placement") {
        HoldNoteClass::CollisionAtOrigin
    } else if note.starts_with("solver wall_gap") && note.contains("disagree") {
        HoldNoteClass::GapDisagree
    } else if note.starts_with("no verified safe integer distance") {
        HoldNoteClass::NoSafeInteger
    } else if note.starts_with(crate::generated_outline_kern::CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN) {
        HoldNoteClass::NegativeOrigin
    } else {
        HoldNoteClass::Unclassified
    }
}

/// Build the always-written hold summary from the kern buckets the caller
/// already holds: the ready and fallback-ready bucket sizes plus the note
/// of every held pair. The population is exactly the pairs the export gate
/// resolved; rejected pairs are a separate typed bucket (clamps and
/// coverage refusals, already ledgered elsewhere) and never enter here.
pub fn summarize_holds<'a>(ready: usize, fallback_ready: usize, hold_notes: impl IntoIterator<Item = &'a str>) -> HoldReasonSummary {
    let mut summary = HoldReasonSummary { ready, fallback_ready, ..HoldReasonSummary::default() };
    for note in hold_notes {
        match classify_hold_note(note) {
            HoldNoteClass::CollisionAtOrigin => summary.collision_at_origin += 1,
            HoldNoteClass::GapDisagree => summary.gap_disagree += 1,
            HoldNoteClass::NoSafeInteger => summary.no_safe_integer += 1,
            HoldNoteClass::NegativeOrigin => summary.negative_origin += 1,
            HoldNoteClass::Unclassified => summary.unclassified += 1,
        }
    }
    summary.pairs = summary.ready + summary.fallback_ready + summary.held();
    summary
}

/// Kern hold-rate check over one run's always-written summary. An empty
/// population carries no rate and is reported, never flagged. The flag is a
/// typed row; no pair is dropped or altered.
pub fn audit_hold_reasons(summary: &HoldReasonSummary) -> Vec<AnchorAuditFlag> {
    if summary.pairs == 0 {
        return Vec::new();
    }
    let held = summary.held();
    let rate = held as f64 / summary.pairs as f64;
    if rate > HOLD_RATE_MAX {
        vec![AnchorAuditFlag::KernHoldRateExceeded {
            pairs: summary.pairs,
            held_pairs: held,
            hold_rate: rate,
            max_rate: HOLD_RATE_MAX,
            collision_at_origin: summary.collision_at_origin,
            gap_disagree: summary.gap_disagree,
            no_safe_integer: summary.no_safe_integer,
            negative_origin: summary.negative_origin,
            unclassified: summary.unclassified,
        }]
    } else {
        Vec::new()
    }
}

/// The always-written hold-reason summary row: one line per run with every
/// class counted, whether or not the run flagged.
pub fn render_hold_summary_tsv(summary: &HoldReasonSummary) -> String {
    let rate = if summary.pairs == 0 { "not_measured".to_string() } else { format!("{:.6}", summary.held() as f64 / summary.pairs as f64) };
    format!(
        "pairs\tready\tfallback_ready\tcollision_at_origin\tgap_disagree\tno_safe_integer\tnegative_origin\tunclassified\thold_rate\n{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{rate}\n",
        summary.pairs, summary.ready, summary.fallback_ready,
        summary.collision_at_origin, summary.gap_disagree, summary.no_safe_integer,
        summary.negative_origin, summary.unclassified)
}

/// Typed ledger rows, one per flag, with the measured values the flag was
/// derived from. Rendering only: no value is recomputed here.
pub fn render_flags_tsv(flags: &[AnchorAuditFlag]) -> String {
    let mut out = String::from("flag\tclass\tdetail\n");
    for flag in flags {
        match flag {
            AnchorAuditFlag::ClassResidualSignImbalance {
                class, nonzero_residuals, zero_residuals, positive_residuals,
                positive_share, sigma_lower, sigma_upper, direction,
            } => {
                let _ = writeln!(out,
                    "class_residual_sign_imbalance\t{class}\tdirection={direction:?} positive_share={positive_share:.6} band=[{sigma_lower:.6},{sigma_upper:.6}] positive={positive_residuals} nonzero={nonzero_residuals} zero={zero_residuals}");
            }
            AnchorAuditFlag::KernHoldRateExceeded {
                pairs, held_pairs, hold_rate, max_rate,
                collision_at_origin, gap_disagree, no_safe_integer,
                negative_origin, unclassified,
            } => {
                let _ = writeln!(out,
                    "kern_hold_rate_exceeded\tkern\thold_rate={hold_rate:.6} max_rate={max_rate:.6} held={held_pairs} pairs={pairs} collision_at_origin={collision_at_origin} gap_disagree={gap_disagree} no_safe_integer={no_safe_integer} negative_origin={negative_origin} unclassified={unclassified}");
            }
            AnchorAuditFlag::CrossStyleTargetOutlier {
                class, style, style_median, grand_median,
                median_absolute_deviation, deviation_over_mad,
            } => {
                let _ = writeln!(out,
                    "cross_style_target_outlier\t{class}\tstyle={style} style_median={style_median:.6} grand_median={grand_median:.6} mad={median_absolute_deviation:.6} deviation_over_mad={deviation_over_mad:.6}");
            }
        }
    }
    out
}

/// The always-written per-class sign summary: every audited class appears
/// whether it flagged or not.
pub fn render_sign_summary_tsv(classes: &[ClassSignSummary]) -> String {
    let mut out = String::from("class\tresiduals\tnonfinite\tzero\tpositive\tnegative\tpositive_share\tflag\n");
    for c in classes {
        let share = c.positive_share.map(|s| format!("{s:.6}")).unwrap_or_else(|| "below_minimum_sample".to_string());
        let _ = writeln!(out,
            "{}\t{}\t{}\t{}\t{}\t{}\t{share}\t{}",
            c.class, c.residuals, c.nonfinite_residuals, c.zero_residuals,
            c.positive_residuals, c.negative_residuals, c.flagged);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rows(class: &str, residuals: &[f64]) -> Vec<(String, f64)> {
        residuals.iter().map(|r| (class.to_string(), *r)).collect()
    }

    fn balanced(n: usize) -> Vec<f64> {
        (0..n).map(|i| if i % 2 == 0 { 1.0 } else { -1.0 }).collect()
    }

    #[test]
    fn balanced_class_never_flags() {
        let report = audit_residual_signs(&rows("straight->round", &balanced(100)));
        assert!(report.flags.is_empty());
        let c = &report.classes[0];
        assert_eq!(c.positive_share, Some(0.5));
        assert!(!c.flagged);
    }

    #[test]
    fn shifted_class_flags_with_direction() {
        // Synthetic shifted data: every residual negative, the signature of
        // a target anchored too wide for this class.
        let report = audit_residual_signs(&rows("straight->round", &vec![-1.0; 60]));
        assert_eq!(report.flags.len(), 1);
        match &report.flags[0] {
            AnchorAuditFlag::ClassResidualSignImbalance { class, positive_share, direction, nonzero_residuals, .. } => {
                assert_eq!(class, "straight->round");
                assert_eq!(*positive_share, 0.0);
                assert_eq!(*nonzero_residuals, 60);
                assert_eq!(*direction, SignImbalanceDirection::Negative);
            }
            other => panic!("unexpected flag {other:?}"),
        }
        assert!(report.classes[0].flagged);
    }

    #[test]
    fn positive_shift_flags_positive_direction() {
        let report = audit_residual_signs(&rows("round->round", &vec![1.0; 60]));
        match &report.flags[0] {
            AnchorAuditFlag::ClassResidualSignImbalance { direction, .. } => {
                assert_eq!(*direction, SignImbalanceDirection::Positive);
            }
            other => panic!("unexpected flag {other:?}"),
        }
    }

    #[test]
    fn below_minimum_sample_never_flags() {
        // n = 35 is one below the derived minimum even at the extreme share.
        let report = audit_residual_signs(&rows("straight->round", &vec![-1.0; 35]));
        assert!(report.flags.is_empty());
        assert_eq!(report.classes[0].positive_share, None);
    }

    #[test]
    fn minimum_sample_is_tested() {
        // n = 36 reaches the derived minimum; an extreme share must flag.
        let report = audit_residual_signs(&rows("straight->round", &vec![-1.0; 36]));
        assert_eq!(report.flags.len(), 1);
    }

    #[test]
    fn share_exactly_on_the_band_edge_does_not_flag() {
        // n = 36 gives sigma = 1/12, so the lower band edge is 0.25 exactly.
        // The test is strictly outside the band: the edge itself is clean.
        let mut v = vec![-1.0; 27];
        v.extend(vec![1.0; 9]);
        let report = audit_residual_signs(&rows("straight->round", &v));
        assert!(report.flags.is_empty());
        assert_eq!(report.classes[0].positive_share, Some(0.25));
    }

    #[test]
    fn one_past_the_band_edge_flags() {
        let mut v = vec![-1.0; 28];
        v.extend(vec![1.0; 8]);
        let report = audit_residual_signs(&rows("straight->round", &v));
        assert_eq!(report.flags.len(), 1);
    }

    #[test]
    fn zeros_are_excluded_from_the_count_and_recorded() {
        let mut v = balanced(40);
        v.extend(vec![0.0; 25]);
        let report = audit_residual_signs(&rows("straight->round", &v));
        assert!(report.flags.is_empty());
        let c = &report.classes[0];
        assert_eq!(c.residuals, 65);
        assert_eq!(c.zero_residuals, 25);
        assert_eq!(c.positive_share, Some(0.5));
    }

    #[test]
    fn nonfinite_rows_are_excluded_and_recorded() {
        let mut v = balanced(40);
        v.extend([f64::NAN, f64::INFINITY, f64::NEG_INFINITY]);
        let report = audit_residual_signs(&rows("straight->round", &v));
        assert!(report.flags.is_empty());
        assert_eq!(report.classes[0].nonfinite_residuals, 3);
    }

    #[test]
    fn only_the_shifted_class_flags() {
        let mut input = rows("straight->round", &vec![-1.0; 60]);
        input.extend(rows("round->round", &balanced(100)));
        let report = audit_residual_signs(&input);
        assert_eq!(report.flags.len(), 1);
        assert_eq!(report.classes.len(), 2);
        assert!(report.classes[0].flagged ^ report.classes[1].flagged);
    }

    fn style(name: &str, targets: &[(&str, f64)]) -> StyleClassTargets {
        StyleClassTargets {
            style: name.to_string(),
            class_targets: targets.iter().map(|(c, t)| (c.to_string(), *t)).collect(),
        }
    }

    #[test]
    fn cross_style_outlier_flags_with_zero_mad() {
        // One style shifted far from an otherwise agreeing family: MAD is 0
        // and any deviation flags.
        let styles = vec![
            style("regular", &[("straight->round", 10.0)]),
            style("bold", &[("straight->round", 10.0)]),
            style("light", &[("straight->round", 10.0)]),
            style("condensed", &[("straight->round", 20.0)]),
        ];
        let flags = audit_cross_style_targets(&styles);
        assert_eq!(flags.len(), 1);
        match &flags[0] {
            AnchorAuditFlag::CrossStyleTargetOutlier { class, style, deviation_over_mad, .. } => {
                assert_eq!(class, "straight->round");
                assert_eq!(style, "condensed");
                assert!(deviation_over_mad.is_infinite());
            }
            other => panic!("unexpected flag {other:?}"),
        }
    }

    #[test]
    fn cross_style_outlier_flags_with_nonzero_mad() {
        let styles = vec![
            style("regular", &[("straight->round", 10.0)]),
            style("bold", &[("straight->round", 11.0)]),
            style("light", &[("straight->round", 12.0)]),
            style("condensed", &[("straight->round", 30.0)]),
        ];
        let flags = audit_cross_style_targets(&styles);
        assert_eq!(flags.len(), 1);
    }

    #[test]
    fn cross_style_consistent_family_does_not_flag() {
        let styles = vec![
            style("regular", &[("straight->round", 10.0)]),
            style("bold", &[("straight->round", 10.1)]),
            style("light", &[("straight->round", 9.9)]),
            style("condensed", &[("straight->round", 10.0)]),
        ];
        assert!(audit_cross_style_targets(&styles).is_empty());
    }

    #[test]
    fn cross_style_two_styles_never_flags() {
        // With two styles the ratio is exactly 1 for every class by
        // construction, so even a large disagreement cannot flag.
        let styles = vec![
            style("regular", &[("straight->round", 10.0)]),
            style("condensed", &[("straight->round", 100.0)]),
        ];
        assert!(audit_cross_style_targets(&styles).is_empty());
    }

    #[test]
    fn cross_style_per_style_median_is_used() {
        // Multiple observations per style reduce to the per-style median
        // before the family comparison.
        let styles = vec![
            style("regular", &[("straight->round", 9.0), ("straight->round", 10.0), ("straight->round", 11.0)]),
            style("bold", &[("straight->round", 10.0)]),
            style("light", &[("straight->round", 10.0)]),
        ];
        assert!(audit_cross_style_targets(&styles).is_empty());
    }

    #[test]
    fn render_rows_are_typed_and_carry_the_measured_values() {
        let report = audit_residual_signs(&rows("straight->round", &vec![-1.0; 60]));
        let tsv = render_flags_tsv(&report.flags);
        assert!(tsv.contains("class_residual_sign_imbalance\tstraight->round\tdirection=Negative"));
        let summary = render_sign_summary_tsv(&report.classes);
        assert!(summary.contains("straight->round\t60\t0\t0\t0\t60\t0.000000\ttrue"));
    }

    fn hold_summary(pairs: usize, ready: usize, collision: usize, disagree: usize) -> HoldReasonSummary {
        HoldReasonSummary { pairs, ready, collision_at_origin: collision, gap_disagree: disagree,
            ..HoldReasonSummary::default() }
    }

    #[test]
    fn hold_rate_below_the_threshold_does_not_flag() {
        // Synthetic holds: 1,000 of 10,000 pairs held (10%).
        assert!(audit_hold_reasons(&hold_summary(10_000, 9_000, 600, 400)).is_empty());
    }

    #[test]
    fn hold_rate_above_the_threshold_flags() {
        // Synthetic holds: 3,000 of 10,000 pairs held (30%).
        let flags = audit_hold_reasons(&hold_summary(10_000, 7_000, 1_800, 1_200));
        assert_eq!(flags.len(), 1);
        match &flags[0] {
            AnchorAuditFlag::KernHoldRateExceeded { hold_rate, held_pairs, max_rate, .. } => {
                assert_eq!(*held_pairs, 3_000);
                assert!((hold_rate - 0.30).abs() < 1e-12);
                assert_eq!(*max_rate, HOLD_RATE_MAX);
            }
            other => panic!("unexpected flag {other:?}"),
        }
    }

    #[test]
    fn hold_rate_exactly_at_the_threshold_does_not_flag() {
        // The test is strictly above the declared maximum: the edge is clean.
        assert!(audit_hold_reasons(&hold_summary(10_000, 8_000, 1_000, 1_000)).is_empty());
    }

    #[test]
    fn fallback_ready_rows_are_not_holds() {
        let s = HoldReasonSummary { pairs: 10_000, ready: 7_000, fallback_ready: 3_000,
            ..HoldReasonSummary::default() };
        assert!(audit_hold_reasons(&s).is_empty());
    }

    #[test]
    fn empty_population_is_reported_not_flagged() {
        let s = HoldReasonSummary::default();
        assert!(audit_hold_reasons(&s).is_empty());
        assert!(render_hold_summary_tsv(&s).contains("not_measured"));
    }

    #[test]
    fn hold_note_classifier_covers_every_declared_producer() {
        // The four note shapes generated_outline_kern emits into the
        // overlap-hold bucket, verbatim in shape.
        assert_eq!(classify_hold_note(
            "collision at exact solver placement (origin 12.500000): min_gap -3.250000, depth 3.250000, interval_hit=true"),
            HoldNoteClass::CollisionAtOrigin);
        assert_eq!(classify_hold_note(
            "solver wall_gap 4.000000 vs measured 9.500000 disagree beyond fp tolerance 1.000e-6"),
            HoldNoteClass::GapDisagree);
        assert_eq!(classify_hold_note(
            "no verified safe integer distance near 12.500000"),
            HoldNoteClass::NoSafeInteger);
        assert_eq!(classify_hold_note(
            "containment_compensation_negative_origin: origin_distance -2.000000 below zero after containment compensation (held, never clamped; pair ships kernless); probe refused"),
            HoldNoteClass::NegativeOrigin);
    }

    #[test]
    fn unknown_hold_note_is_unclassified_never_guessed() {
        assert_eq!(classify_hold_note("some future hold producer"), HoldNoteClass::Unclassified);
        assert_eq!(classify_hold_note(""), HoldNoteClass::Unclassified);
    }

    #[test]
    fn summarize_holds_counts_the_whole_population() {
        let s = summarize_holds(7_000, 2_000, [
            "collision at exact solver placement (origin 1.000000): min_gap -1.000000, depth 1.000000, interval_hit=true",
            "solver wall_gap 1.000000 vs measured 2.000000 disagree beyond fp tolerance 1.000e-6",
            "no verified safe integer distance near 1.000000",
            "containment_compensation_negative_origin: origin_distance -1.000000 below zero after containment compensation (held, never clamped; pair ships kernless); probe refused",
            "unrecognized producer shape",
        ].into_iter());
        assert_eq!(s.ready, 7_000);
        assert_eq!(s.fallback_ready, 2_000);
        assert_eq!(s.collision_at_origin, 1);
        assert_eq!(s.gap_disagree, 1);
        assert_eq!(s.no_safe_integer, 1);
        assert_eq!(s.negative_origin, 1);
        assert_eq!(s.unclassified, 1);
        // Every held pair counts toward held(): none is invisible.
        assert_eq!(s.held(), 5);
        assert_eq!(s.pairs, 9_005);
    }

    #[test]
    fn negative_origin_holds_count_toward_the_hold_rate() {
        // Synthetic: 3,000 negative-origin holds of 10,000 pairs (30%).
        let notes = vec![
            "containment_compensation_negative_origin: origin_distance -1.000000 below zero after containment compensation (held, never clamped; pair ships kernless); probe refused";
            3_000];
        let s = summarize_holds(7_000, 0, notes.into_iter());
        let flags = audit_hold_reasons(&s);
        assert_eq!(flags.len(), 1);
        match &flags[0] {
            AnchorAuditFlag::KernHoldRateExceeded { held_pairs, negative_origin, .. } => {
                assert_eq!(*held_pairs, 3_000);
                assert_eq!(*negative_origin, 3_000);
            }
            other => panic!("unexpected flag {other:?}"),
        }
    }

    #[test]
    fn hold_summary_render_carries_the_full_taxonomy() {
        let s = summarize_holds(1, 2, ["unrecognized producer shape"].into_iter());
        let tsv = render_hold_summary_tsv(&s);
        assert!(tsv.contains("pairs	ready	fallback_ready	collision_at_origin	gap_disagree	no_safe_integer	negative_origin	unclassified	hold_rate"));
        assert!(tsv.contains("4	1	2	0	0	0	0	1	0.250000"));
    }
}
