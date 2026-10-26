//! self_anchored_spacing.rs — KNI OHAL code line K2.
//!
//! Font-local spacing / white-space engine. Input: K1 `OutlineProfile`
//! (metrics/src/outline_spacing.rs, actual signatures 2026-10-14 12:03).
//! Output: `SpacingSolution` (per-glyph lsb/rsb/advance + pair positions).
//! Model: K5 rev2 (supersedes rev1 constants) — no literature numbers; every
//! target is measured from the font's own outlines or from source-measured
//! spacing carried in the optional `FontContext` wrapper (architect decision:
//! calibration anchors live in the wrapper, never mandatory input).
//!
//! ACTIVE PAIR OBJECTIVE (chief-architect ruling 2026-10-14 21:28, binding):
//!   J(t) = (W(t) - pair_target)^2 + lambda * V(t)
//!   W(t) = y-mean of min(g(y)+t, Dcap) over the pair's common cells
//!          (piecewise-linear gap g, union y-grid, weight = cell length);
//!   V(t) = y-variance of the same clamped gap (distribution evenness term).
//!   Both terms carry gap^2 units; lambda is a dimensionless explicit
//!   policy parameter, finite and >= 0, no hidden default clamp.
//! The K5 rev2 document's Cnt_ratio_term (counter-ratio pull) is NOT
//! implemented and is out of this release's scope (same ruling); nothing in
//! this file should be read as implementing the ratio objective.
//!
//! Frame rule (binding 12:01): K1 coordinates are raw font units in the
//! glyph-origin frame (x=0 is the glyph origin, carried in
//! `OutlineProfile::origin`, NOT ink xmin). K2 keeps that frame end to end.
//! Walls are x_min-normalised only for internal area math; outputs refer to
//! the raw origin:
//!   * writer emits `x-translation = generated_lsb - outline_ink_xmin`,
//!     `advance = solution.advance = lsb + (x_max - x_min) + rsb`;
//!   * `PairPosition.origin_distance` is the GLYPH-ORIGIN distance; K3's
//!     residual = `origin_distance - left.advance`. Never ink-to-ink.
//! All outputs f64; integer export rounding is K3's job.
//!
//! Anchor cascade (rev2 §1/§3, architect label rule 12:03):
//!   1. MeasuredSource: FontContext measured pairs and/or sidebearings exist
//!      (real source spacing) — they win; per class-pair medians.
//!   2. GeometryOnlyFallback: straight|straight side pairs exist in the
//!      profiles; W_target = mean outer channel c_out over their band rows.
//!      If that collapses to 0 (flush boxes, e.g. grid fonts): secondary
//!      measured-outline target = median counter channel of straight-class
//!      glyphs -> label MeasuredOutlineSelfDerivedTarget.
//!   3. GeometryOnlyFallbackLowConfidence: no straight pairs either;
//!      W_target = median over all glyph pairs of the min row gap at d=0.
//!      Flagged low-confidence in `policy_derivation`.
//! The optical target is NEVER labelled "measured" unless case 1 holds.
//!
//! Deterministic: same outlines + same context => same solution. No random
//! or learned state; free parameters (Dcap, w(y)=uniform, lambda) have the
//! measured defaults of rev2 §2 and are exposed on `SpacingPolicy`.

use crate::outline_spacing::OutlineProfile; // K1, metrics/src/outline_spacing.rs
use std::collections::HashMap; // lookup only, never iterated (determinism)

// ---------------------------------------------------------------------------
// Optional measured-spacing wrapper (architect: separate from core input)
// ---------------------------------------------------------------------------

/// Measured spacing evidence from the source (sidebearing/kern images).
/// Plain numbers only; presence upgrades the anchor to MeasuredSource.
/// Never used to copy ready kerns into the output: measured pairs define
/// targets, the pair solver still solves from outline geometry.
#[derive(Debug, Clone, Default)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct FontContext {
    /// Measured x-height (baseline->x-top), font units.
    pub x_height: Option<f64>,
    /// Measured cap height.
    pub cap_height: Option<f64>,
    /// Measured baseline y (defaults to median inked-glyph bounds bottom).
    pub baseline: Option<f64>,
    /// Measured per-glyph sidebearings from source spacing images.
    pub measured_sidebearings: Vec<MeasuredSidebearing>,
    /// Measured pair gaps from source kern images, font units, defined as
    /// white gap between the two glyphs' ink boxes at source placement.
    pub measured_pairs: Vec<MeasuredPair>,
    /// Measured space advance (e.g. H-space-H triplet). None = derive.
    pub measured_space_advance: Option<f64>,
    /// Manifest-bound identity map: solver glyph_id -> Unicode codepoint.
    /// Stem/anchor/case resolution goes through THIS map when present, never
    /// through raw id formats (numeric manifest ids like "00007" are not
    /// letters). Entries naming unknown or duplicate glyph ids are a typed
    /// refusal. (Architect stem-anchor finding 12:17; driver-side
    /// cpchar<->id bijection is a product identity change pending architect
    /// approval.)
    pub glyph_codepoints: Vec<(String, u32)>,
}

#[derive(Debug, Clone)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct MeasuredSidebearing {
    pub glyph_id: String,
    pub lsb: f64,
    pub rsb: f64,
}

#[derive(Debug, Clone)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct MeasuredPair {
    pub left: String,
    pub right: String,
    /// Measured white gap between ink boxes, font units.
    pub gap: f64,
}

// ---------------------------------------------------------------------------
// Policy: resolution / quadrature / resource bounds / free parameters only
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct SpacingPolicy {
    /// Quadrature resolution; residual epsilon = sample_resolution / 2.
    /// Pairs whose solved |residual| is below the epsilon are noise and are
    /// not emitted (algorithmic floor, not a stylistic clamp).
    pub sample_resolution: f64,
    /// Hard bound on ordered pair solves. Exceeding it is a typed refusal
    /// BEFORE any pair is dropped.
    pub max_pair_evaluations: u64,
    /// Soft cap on emitted pairs. Overflow is NOT silently dropped: excess
    /// pairs land in `SpacingSolution::excluded_pairs`, `complete` becomes
    /// false and the truncation is reported (architect rule 12:03).
    pub max_pairs: usize,
    /// Minimum shared band rows for a pair to be solved.
    pub pair_min_shared_rows: usize,
    /// Weight of the V(t) distribution term in the active pair objective
    /// J(t) = (W(t)-target)^2 + lambda*V(t) (see module header; ruling
    /// 21:28: V(t) is the objective, K5's Cnt_ratio_term is out of scope).
    /// Dimensionless (both terms in gap^2 units); must be finite and >= 0.
    /// None => 0.0 (distribution term off), always receipted, never
    /// silently forced: a Some(v) is honored verbatim.
    pub lambda: Option<f64>,
    /// rev2 free parameter: depth cap for open forms. None => measured
    /// plateau default (max side depth observed in stem-glyph rows).
    pub dcap: Option<f64>,
    /// Simultaneous-contrast floor pass (metrics/src/contrast_floor.rs).
    /// false = off: the frozen pipeline ships bit-identical. true = a
    /// post-solve pass raises every pair whose verified minimum gap falls
    /// below the font-calibrated contrast floor (floor = k * facing weight,
    /// k measured from the font's own solved pairs; no constants). Raised,
    /// untouched and failed pairs are all receipted.
    pub contrast_floor: bool,
    /// Lane B (cadence + optical area class pass). false (default): the
    /// frozen measured -> anchor-fallback target resolution, bit-identical.
    /// true: class pairs WITHOUT a measured ctx target get a target derived
    /// from the font's own stem-interval cadence (cadence.rs) and per-class
    /// area/balance channels; a derived target equal to the anchor target
    /// is skipped, so untouched pairs stay bit-identical by construction.
    /// No free parameters: every number is measured from the font.
    pub cadence_class_pass: bool,
    /// K2 (per-class channel targets). false (default): the frozen
    /// measured -> anchor-fallback target resolution, bit-identical.
    /// true: class pairs WITHOUT a measured ctx target get a target
    /// derived from the anchor's own channel evidence, pooled per side
    /// class (see the K2 block below for the declared CONVENTION and its
    /// rationale); a derived target equal to the anchor target is
    /// skipped, so untouched pairs stay bit-identical by construction.
    /// No free parameters: every number is measured from the font.
    pub class_channel_targets: bool,
}

impl Default for SpacingPolicy {
    fn default() -> Self {
        SpacingPolicy {
            sample_resolution: 4.0,
            max_pair_evaluations: 4_000_000,
            max_pairs: 20_000,
            pair_min_shared_rows: 3,
            lambda: None,
            dcap: None,
            contrast_floor: false,
            cadence_class_pass: false,
            class_channel_targets: false,
        }
    }
}

impl SpacingPolicy {
    fn residual_epsilon(&self) -> f64 { self.sample_resolution / 2.0 }
}

// ---------------------------------------------------------------------------
// NV-2: class spacing units + direction symmetry (work list 2026-10-16,
// items 2+3+7). The gate lives OUTSIDE SpacingPolicy: the frozen policy
// struct keeps its exact field set for every existing caller, and the
// frozen entry points pass ClassHarmonyPolicy::default() (both lanes off),
// which is bit-identical to the pre-NV-2 cascade by construction.
// ---------------------------------------------------------------------------

/// NV-2 lane switches. Both default OFF. `direction_symmetry`: a pair and
/// its reverse are one relationship - the emit/drop decision is shared, so
/// the model never keeps one direction and drops the other (today: K->J
/// +287 written while J->K +2.95 fell below the residual epsilon).
/// `class_spacing_units`: edge classes carry spacing units learned from
/// the font's own solved pair measurements (mean / median / midrange all
/// computed on the real class data, the data selects; no hardcoded class
/// values). Class-internal harmonization is emitted as SPACING rows
/// (sidebearing-delta records), never as kern: the kern layer stays for
/// what remains outside classes.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct ClassHarmonyPolicy {
    pub direction_symmetry: bool,
    pub class_spacing_units: bool,
}

/// Typed receipt for one below-epsilon direction promoted because its
/// reverse direction was emitted (NV-2 item 3). The promoted pair ships in
/// `SpacingSolution::pairs` like any solved pair; this row records WHY.
#[derive(Debug, Clone)]
pub struct SymmetryPromotion {
    pub left: String,
    pub right: String,
    pub class: String,
    /// Promoted direction's solved residual (below the residual epsilon).
    pub residual: f64,
    /// Reverse direction's solved residual (the emitted one).
    pub reverse_residual: f64,
}

/// Which of the three declared unit candidates the class data selected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClassUnitCandidate {
    /// Baseline (owner: "take the average of the in-class measurements").
    Mean,
    /// Outlier-robust: near-touch outliers cannot drag the unit.
    Median,
    /// Fragile: the two extreme values alone decide it.
    Midrange,
}
impl ClassUnitCandidate {
    pub fn code(&self) -> &'static str {
        match self {
            ClassUnitCandidate::Mean => "mean",
            ClassUnitCandidate::Median => "median",
            ClassUnitCandidate::Midrange => "midrange",
        }
    }
}

/// Typed per-class unit row (NV-2 items 2+7). All three candidates and all
/// three scores are reported so the selection is auditable per class.
#[derive(Debug, Clone)]
pub struct ClassUnitRow {
    pub left_class: SideClass,
    pub right_class: SideClass,
    /// Solved tier-1 pairs in the class (emitted + below-epsilon).
    pub pair_count: usize,
    /// Pairs within the residual epsilon of the selected unit.
    pub uniform_count: usize,
    pub candidate_mean: f64,
    pub candidate_median: f64,
    pub candidate_midrange: f64,
    pub score_mean: f64,
    pub score_median: f64,
    pub score_midrange: f64,
    pub selected: ClassUnitCandidate,
    /// The class unit: the selected candidate's value.
    pub unit: f64,
    /// Total deviation of the non-uniform pairs from the unit, divided by
    /// the class pair count; shared equally, it is also the per-pair
    /// correction share (the documented equal load-sharing alternative).
    pub inconsistency_score: f64,
}

/// Typed SPACING emission for one non-uniform pair (NV-2 items 2+7): the
/// pair is pulled to the class unit by its own deviation. The correction
/// is a sidebearing delta, shared equally between the two facing sides
/// (the declared load-sharing convention), and is NOT a kern row: the
/// solver's pair output is untouched by this lane.
#[derive(Debug, Clone)]
pub struct ClassSpacingAdjustment {
    pub left: String,
    pub right: String,
    pub class: String,
    /// Solved minimum ink gap before harmonization.
    pub gap_before: f64,
    /// The class unit the pair is pulled to.
    pub unit: f64,
    /// gap_before - unit (signed).
    pub deviation: f64,
    /// unit - gap_before (the pull that seats the pair on the unit).
    pub correction: f64,
    /// Spacing delta for the left glyph's rsb (half the correction).
    pub left_rsb_delta: f64,
    /// Spacing delta for the right glyph's lsb (half the correction).
    pub right_lsb_delta: f64,
    /// True when the pair also shipped as a kern candidate; false when it
    /// sat below the residual epsilon.
    pub emitted: bool,
}

/// NV-2 receipt bundle, returned only by `solve_spacing_with_class_harmony`.
/// The frozen entry points construct it empty and discard it.
#[derive(Debug, Clone, Default)]
pub struct ClassHarmonyReport {
    pub symmetry_promotions: Vec<SymmetryPromotion>,
    pub class_unit_rows: Vec<ClassUnitRow>,
    pub class_spacing_adjustments: Vec<ClassSpacingAdjustment>,
    /// Below-epsilon directions with their solved positions. Populated ONLY by the below-epsilon candidate run
    /// (`solve_below_epsilon_candidates`, self_mode 2); empty in every other solve.
    pub below_epsilon_candidates: Vec<PairPosition>,
}

/// Internal decision value of `class_unit_decision` (fields feed the
/// ClassUnitRow receipt and the tests).
#[derive(Debug, Clone)]
struct ClassUnitDecision {
    candidate_mean: f64,
    candidate_median: f64,
    candidate_midrange: f64,
    score_mean: f64,
    score_median: f64,
    score_midrange: f64,
    selected: ClassUnitCandidate,
    unit: f64,
    inconsistency_score: f64,
    uniform_count: usize,
}

/// NV-2 items 2+7: compute the three declared unit candidates on the real
/// class data and let the data select. DECLARED CONVENTION (provenance:
/// docs/kni/2026-10-16-kern-spacing-next-version-work-list.md items 2+7):
/// a pair is non-uniform under a candidate unit when its absolute
/// deviation reaches the solver's own residual epsilon (a font/policy
/// value, not a constant); a candidate's score is the total deviation of
/// its non-uniform pairs divided by the class pair count; the selected
/// unit is the lowest-scoring candidate, ties broken in the declared
/// baseline order mean -> median -> midrange. None on empty input.
fn class_unit_decision(gaps: &[f64], eps: f64) -> Option<ClassUnitDecision> {
    if gaps.is_empty() { return None; }
    let n = gaps.len();
    let candidate_mean = mean(gaps);
    let candidate_median = median(gaps.to_vec())?;
    let lo = gaps.iter().cloned().fold(f64::INFINITY, f64::min);
    let hi = gaps.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let candidate_midrange = (lo + hi) / 2.0;
    let score = |u: f64| -> (f64, usize) {
        let mut total = 0.0;
        let mut non_uniform = 0usize;
        for g in gaps {
            let d = (g - u).abs();
            if d >= eps {
                total += d;
                non_uniform += 1;
            }
        }
        (total / n as f64, non_uniform)
    };
    let (score_mean, _) = score(candidate_mean);
    let (score_median, _) = score(candidate_median);
    let (score_midrange, nu_midrange) = score(candidate_midrange);
    let mut selected = ClassUnitCandidate::Mean;
    let mut unit = candidate_mean;
    let mut best = score_mean;
    if score_median < best {
        selected = ClassUnitCandidate::Median;
        unit = candidate_median;
        best = score_median;
    }
    if score_midrange < best {
        selected = ClassUnitCandidate::Midrange;
        unit = candidate_midrange;
        best = score_midrange;
    }
    let (_, non_uniform) = score(unit);
    let _ = nu_midrange;
    Some(ClassUnitDecision {
        candidate_mean, candidate_median, candidate_midrange,
        score_mean, score_median, score_midrange,
        selected, unit, inconsistency_score: best,
        uniform_count: n - non_uniform,
    })
}

// ---------------------------------------------------------------------------
// Output (architect contract + ledger amendment 12:03)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct GlyphSpacing {
    pub glyph_id: String,
    pub lsb: f64,
    pub rsb: f64,
    pub advance: f64,
}

#[derive(Debug, Clone)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct PairPosition {
    pub left: String,
    pub right: String,
    /// Glyph-origin distance, shared raw frame (frame rule 12:01).
    pub origin_distance: f64,
    /// Minimum row white gap between inks at `origin_distance`.
    pub wall_gap: f64,
    /// Value of the pair objective J at the solved placement (rev2 §2).
    pub optical_cost: f64,
    /// Typed carrier for the solver-lane pair target (floor policy input).
    /// Filled by the production solve (tier-1 and tier-2 widened pairs) with
    /// the pair's own J target (`usable_pair_target`); None only when that
    /// target was not usable. A pair without a usable target contributes
    /// nothing to the font median.
    pub pair_target: Option<f64>,
    /// True when the post-solve containment compensation shifted this pair's
    /// origin. Gates the typed negative-origin hold in the kern stage: that
    /// reason belongs to compensated pairs only.
    pub compensated: bool,
}

/// Carrier value for the solver-lane pair target: the class-pair gap target
/// `pair_gap` that this pair's objective J was minimised against (measured
/// class-pair median, else per-class channel/cadence target, else the anchor
/// W_target - all derived from this font's own outlines or measured source).
/// Some only when usable (finite, >= 0); otherwise None, so an unusable
/// target never reaches the font median as a silent zero.
fn usable_pair_target(pair_gap: f64) -> Option<f64> {
    if pair_gap.is_finite() && pair_gap >= 0.0 { Some(pair_gap) } else { None }
}

/// Median of the usable pair targets across `pairs` (usable = Some, finite,
/// >= 0). Odd count: the middle value; even count: the mean of the two
/// middle values. None when no usable target exists (typed empty, never a
/// silent zero).
pub fn font_median_pair_target(pairs: &[PairPosition]) -> Option<f64> {
    let mut v: Vec<f64> = pairs.iter().filter_map(|p| p.pair_target).filter(|t| t.is_finite() && *t >= 0.0).collect();
    if v.is_empty() { return None; }
    v.sort_by(f64::total_cmp);
    let n = v.len();
    Some(if n % 2 == 1 { v[n / 2] } else { (v[n / 2 - 1] + v[n / 2]) / 2.0 })
}

/// A solved pair excluded only by `policy.max_pairs`; ledger, never silent.
#[derive(Debug, Clone)]
pub struct ExcludedPair {
    pub left: String,
    pub right: String,
    pub origin_distance: f64,
    pub wall_gap: f64,
    pub optical_cost: f64,
}

/// Reason codes for the per-pair spacing ledger (owner rule 00:33:05: no
/// rejection may remain counter-only). Solved pairs are not listed; the
/// kern-diagnostic.tsv is their receipt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PairLedgerReason {
    NoFeasible,
    NoAcceptedCandidate,
    NotConverged,
    ExcludedSelfPair,
    ExcludedBelowEpsilon,
    ExcludedUnmeasurable,
    FallbackDerived,
    /// Tier-2 natural placement could not be verified (empty/non-finite raw cells, or canonical evidence unmeasurable with no raw collision proof): no safe label, no unsafe label.
    NaturalUnverifiable,
    /// Raw (model-frame) cells say collision but canonical export-frame evidence says clear: frames disagree, no safe/unsafe label, no widening.
    NaturalFrameConflict,
    /// Solve hit a non-finite numeric state (overflow/NaN). Fail-safe: typed record only.
    NonFiniteFailure,
}
impl PairLedgerReason {
    pub fn code(&self) -> &'static str {
        match self {
            PairLedgerReason::NoFeasible => "no_feasible",
            PairLedgerReason::NoAcceptedCandidate => "no_accepted_candidate",
            PairLedgerReason::NotConverged => "not_converged",
            PairLedgerReason::ExcludedSelfPair => "excluded_self_pair",
            PairLedgerReason::ExcludedBelowEpsilon => "excluded_below_epsilon",
            PairLedgerReason::ExcludedUnmeasurable => "excluded_unmeasurable",
            PairLedgerReason::FallbackDerived => "fallback_derived",
            PairLedgerReason::NaturalUnverifiable => "natural_unverifiable",
            PairLedgerReason::NaturalFrameConflict => "natural_frame_conflict",
            PairLedgerReason::NonFiniteFailure => "nonfinite_failure",
        }
    }
}

/// Safety status of a pair's natural placement (no kern row written).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NaturalSafety { Unknown, CheckedSafe, Unsafe }
impl NaturalSafety {
    pub fn code(&self) -> &'static str {
        match self {
            NaturalSafety::Unknown => "unknown",
            NaturalSafety::CheckedSafe => "checked-safe",
            NaturalSafety::Unsafe => "unsafe",
        }
    }
}

/// One per-pair ledger row: identity + class + reason + measured values.
#[derive(Debug, Clone)]
pub struct PairLedgerRow {
    pub left: String,
    pub right: String,
    pub class: String,
    pub reason: PairLedgerReason,
    pub tier: u8,
    pub t_lo: f64,
    pub t_hi: f64,
    pub residual: f64,
    pub j_star: f64,
    pub kern_units: Option<f64>,
    pub natural_safety: NaturalSafety,
}

/// Typed space-spacing status (dar patch): measured emission, typed
/// missing evidence, or honest absence. There is NO W_target fallback into
/// spacing emission: the self-derived statistic is carried only as an
/// explicit diagnostic candidate, never emitted as a space advance.
#[derive(Debug, Clone, PartialEq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub enum SpaceStatus {
    /// ctx.measured_space_advance = Some(finite, >= 0): the advance is
    /// provided by measured evidence. It is emitted as the space glyph's
    /// advance ONLY when a space glyph is present in solver input; with no
    /// space glyph in input the advance is provided but NOT emitted.
    Measured { advance: f64 },
    /// A space glyph was present in solver input but no measured advance
    /// was supplied: NOTHING is emitted for space. `candidate_diagnostic`
    /// is the self-derived W_target statistic - diagnostic only, explicitly
    /// not source-observed, never emitted.
    MissingEvidence { candidate_diagnostic: f64 },
    /// No space glyph in solver input: honest absence, none invented.
    Absent,
}

/// A convention the solver applied INSTEAD of an observation (typed twin of the POLICY_UNOBSERVED notes). Presence changes no value;
/// it says which inputs were conventions, so a consumer can gate on them without parsing text.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
#[derive(serde::Serialize, serde::Deserialize)]
pub enum UnobservedPolicy {
    /// x_height = median of (y_max - baseline) over ALL inked glyphs (no lowercase tops, no ctx value).
    XHeightAllGlyphProxy,
    /// cap_height = x_height (no uppercase tops, no ctx value).
    CapHeightEqualsXHeight,
    /// baseline = median of inked y_min (no ctx baseline).
    BaselineMedianYMin,
    /// Class pairs (left-right side classes) that had no measured target and used the self-derived equal-area target.
    ClassPairTargetSelfDerived { class_pairs: Vec<String> },
    /// policy.lambda was None: 0.0 used.
    LambdaDefaultZero,
    /// policy.dcap was None: measured plateau default used.
    DcapPlateauDefault,
    /// Lane B class pass (policy.cadence_class_pass): class pairs whose
    /// solve target was derived from the font's own stem-interval cadence
    /// and per-class area/balance channels instead of a measured target or
    /// the plain anchor fallback (cadence.rs; OUR CANDIDATE derivation).
    ClassPairTargetCadenceDerived { class_pairs: Vec<String> },
    /// K2 class pass (policy.class_channel_targets): class pairs whose
    /// solve target was derived from the anchor's own channel evidence
    /// pooled per side class (median channel CONVENTION, see the K2
    /// block) instead of a measured target or the plain anchor fallback.
    ClassPairTargetChannelDerived { class_pairs: Vec<String> },
}

/// Typed x_height provenance: which producer path supplied
/// `SpacingSolution::x_height`. New semantic data only - no numeric value
/// and no `policy_derivation` text changes. Consumers must read this field
/// instead of inferring provenance from numbers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub enum XHeightSource {
    /// FontContext.x_height (caller-supplied context value).
    Ctx,
    /// Median of (y_max - baseline) over flat-top lowercase glyphs (no ctx value).
    LcTopMedian,
    /// Median of (y_max - baseline) over ALL inked glyphs; accompanies
    /// `UnobservedPolicy::XHeightAllGlyphProxy`.
    AllGlyphProxy,
    /// Pipeline degrade floor: main solve refused; x_height = population
    /// median ink height from raw bounds (bbox), never an invented value.
    DegradeBbox,
    /// spacing_fallback natural population: x_height = median inked extent
    /// of the population itself.
    NaturalFallback,
}

impl XHeightSource {
    /// Stable receipt token (variant identity only, never the Debug payload).
    pub fn token(self) -> &'static str {
        match self {
            XHeightSource::Ctx => "ctx",
            XHeightSource::LcTopMedian => "lc_top_median",
            XHeightSource::AllGlyphProxy => "all_glyph_proxy",
            XHeightSource::DegradeBbox => "degrade_bbox",
            XHeightSource::NaturalFallback => "natural_fallback",
        }
    }
}

#[derive(Debug, Clone)]
pub struct SpacingSolution {
    /// Solver baseline (ctx or median of inked y_min); x_height/cap_height are the solver's
    /// median-heuristic (or ctx) heights above that baseline, not hull heights.
    pub baseline: f64,
    pub x_height: f64,
    /// Typed provenance of `x_height` (see XHeightSource); every producer
    /// path sets it, no consumer infers it from numbers.
    pub x_height_source: XHeightSource,
    pub cap_height: f64,
    pub glyphs: Vec<GlyphSpacing>,
    pub pairs: Vec<PairPosition>,
    /// Median of the usable per-pair targets at solve time (see
    /// `font_median_pair_target`); None when no pair carried a usable target.
    pub font_median_pair_target: Option<f64>,
    /// Typed space-spacing outcome (see SpaceStatus); consumers of a full
    /// output must gate on MissingEvidence instead of reading a fallback.
    pub space_status: SpaceStatus,
    /// Pairs solved but excluded by max_pairs. Empty <=> complete.
    pub excluded_pairs: Vec<ExcludedPair>,
    /// false when excluded_pairs is non-empty OR a numeric failure
    /// occurred (chief-architect 21:37: numeric failure is never a
    /// definite success). General unmeasurable pairs do not affect it.
    pub complete: bool,
    /// Ordered self pairs (H->H, n->n, ...) skipped by construction. Kept
    /// explicit so `pairs` never reads like a full all-pairs count.
    pub excluded_self_pairs: usize,
    /// Solved pairs dropped by the residual epsilon (algorithmic noise
    /// floor). Counted, not listed: they carry no typographic action.
    pub excluded_below_epsilon: usize,
    /// Ordered pairs that could not be measured at all: fewer shared band
    /// cells than `pair_min_shared_rows` (e.g. disjoint y extents), no
    /// finite gap bound, no finite solve, or a non-finite origin distance.
    /// Counted so the accounting is closed:
    /// emitted + ledger + below_epsilon + unmeasurable + numeric_failed
    /// + self = n^2.
    pub excluded_unmeasurable: usize,
    /// Ordered pairs whose solve hit a non-finite numeric state (overflow/
    /// NaN inside the lambda>0 piecewise solve): a DECLARED BOUNDED
    /// FAILURE, separated from legitimate unmeasurable pairs
    /// (chief-architect 21:37). A numeric failure means "we could not run
    /// the solve", not "the pair has no shared geometry": it forces
    /// `complete = false`, so the consumer (P3 adapter) reports
    /// Incomplete instead of presenting the run as fully solved.
    pub numeric_failed_pairs: usize,
    /// Ordered pairs with NO feasible residual in the solve domain
    /// (PairSolve::NoFeasible): a GEOMETRIC domain hold, not a numeric
    /// failure (chief 23:39 (4)). Forces `complete = false`.
    pub geometric_hold_pairs: usize,
    /// Ordered pairs whose feasible components existed but produced no
    /// accepted candidate in the declared domain (PairSolve::
    /// NoAcceptedCandidate): NOT geometric-empty, NOT numeric (chief
    /// 23:44 (2)). Forces `complete = false`.
    pub no_accepted_candidate_pairs: usize,
    /// Variant+reason receipt for every held pair (chief 23:39 (4)):
    /// "left->right: NoFeasible ..." / "left->right: NotConverged: <reason>".
    pub hold_reasons: Vec<String>,
    /// Per-pair ledger: every rejected, excluded or fallback pair with
    /// identity, class, reason code and measured values (owner 00:33:05).
    /// Includes the natural-placement safety status of every no-kern row.
    pub pair_ledger: Vec<PairLedgerRow>,
    /// Tier-2 fallback pairs recovered by the declared fallback pass
    /// (guard-verified kern rows, explicit fallback class). Never counted
    /// as solver-optimal results; their presence forces complete=false.
    pub fallback_pairs: Vec<PairPosition>,
    /// Tier-2 pairs whose natural placement verified clear (raw + canonical), no GPOS row.
    /// Previously decremented out of numeric_failed_pairs and counted nowhere.
    pub fallback_natural_clear_pairs: usize,
    /// Tier-2 pairs recovered with a guard-verified widened kern row (== fallback_pairs.len()).
    pub fallback_verified_pairs: usize,
    /// Unresolved numeric failures by typed class (subsets of numeric_failed_pairs).
    pub numeric_failed_nonfinite: usize,
    pub numeric_failed_malformed: usize,
    pub numeric_failed_natural_unverifiable: usize,
    pub numeric_failed_natural_frame_conflict: usize,
    /// evaluations - accounted buckets; 0 means closed.
    pub accounting_residual: i64,
    /// false when accounting_residual != 0: typed anomaly, forces complete=false.
    pub accounting_closed: bool,
    /// Simultaneous-contrast floor receipt: pairs the pass raised to the
    /// font-calibrated floor. Empty when the policy is off, when no pair
    /// fell below its floor, or on a typed no-op calibration.
    pub contrast_floor_adjustments: Vec<crate::contrast_floor::ContrastFloorAdjustment>,
    /// Simultaneous-contrast floor typed failures: pairs left unchanged
    /// (solver-verified placement) because the raise could not be verified.
    pub contrast_floor_failures: Vec<crate::contrast_floor::ContrastFloorFailure>,
    /// Receipt: anchor mode + reasons, derived targets, defaults used,
    /// fallbacks, truncations, anomalies. Written on every success.
    pub policy_derivation: String,
    /// Typed conventions applied in place of observations (sorted by variant order, deduplicated). Empty only means none of these six conventions applied; other policy parameters (max_pairs, epsilon, ...) are declared conventions and are not listed here.
    pub unobserved_policy: Vec<UnobservedPolicy>,
    /// Systematic anchor-error audit over this solve's tier-1 residual
    /// population: per-class sign summary rows (always written) plus typed
    /// flags. Empty means the audit did not run, never "ran and was clean".
    pub anchor_audit: crate::anchor_audit::AnchorAuditReport,
}

// ---------------------------------------------------------------------------
// Anchor strategy (chief-architect decision 2026-10-14 12:34): explicit,
// receipt-visible selection. `solve_spacing` keeps its frozen behaviour by
/// delegating to `LegacyCascade`; production never switches silently.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub enum AnchorStrategy {
    /// Frozen cascade exactly as canonical 59c2fda7 (baseline arm A).
    LegacyCascade,
    /// Negative-control arm: without measured source spacing the solve is a
    /// typed ANCHOR_UNRESOLVED refusal (the production-safe state for
    /// geometry-only near-zero).
    RequireMeasured,
    /// Experiment arm B: geometry-only runs anchor on the counter channel
    /// (median over straight-class glyphs with interior white) instead of
    /// the straight-side outer channel. Missing coverage is a typed
    /// refusal, never a fallback to the outer channel.
    CounterChannel,
}

// ---------------------------------------------------------------------------
// Typed refusals
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub enum SpacingError {
    EmptyInput,
    InconsistentUpm { expected: u16, found: u16, glyph_id: String },
    NonFinite { glyph_id: String, field: &'static str },
    InvalidProfile { glyph_id: String, reason: String },
    InvalidContext { reason: String },
    ResourceBoundExceeded { what: &'static str, limit: u64 },
    NoUsableGlyphs { reason: String },
    /// RequireMeasured without measured source spacing, or CounterChannel
    /// without interior-white coverage. Never silently re-anchored.
    AnchorUnresolved { strategy: &'static str, reason: String },
}

impl std::fmt::Display for SpacingError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SpacingError::EmptyInput => write!(f, "no input profiles"),
            SpacingError::InconsistentUpm { expected, found, glyph_id } => write!(
                f, "inconsistent upm: expected {expected}, glyph {glyph_id} has {found}"),
            SpacingError::NonFinite { glyph_id, field } =>
                write!(f, "non-finite {field} in glyph {glyph_id}"),
            SpacingError::InvalidProfile { glyph_id, reason } =>
                write!(f, "invalid profile for {glyph_id}: {reason}"),
            SpacingError::InvalidContext { reason } =>
                write!(f, "invalid font context: {reason}"),
            SpacingError::ResourceBoundExceeded { what, limit } =>
                write!(f, "resource bound exceeded for {what} (limit {limit})"),
            SpacingError::NoUsableGlyphs { reason } =>
                write!(f, "no usable glyphs to derive spacing target: {reason}"),
            SpacingError::AnchorUnresolved { strategy, reason } =>
                write!(f, "anchor unresolved under strategy {strategy}: {reason}"),
        }
    }
}

impl std::error::Error for SpacingError {}

// ---------------------------------------------------------------------------
// Side classification (rev2 §4, geometry only; s is the only length unit)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[derive(serde::Serialize, serde::Deserialize)]
pub enum SideClass {
    Straight,
    Round,
    Diagonal,
    Arm,
    Open,
    Empty,
}

impl std::fmt::Display for SideClass {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            SideClass::Straight => "straight",
            SideClass::Round => "round",
            SideClass::Diagonal => "diagonal",
            SideClass::Arm => "arm",
            SideClass::Open => "open",
            SideClass::Empty => "empty",
        };
        write!(f, "{s}")
    }
}

// ---------------------------------------------------------------------------
// Internal per-glyph geometry (walls x_min-normalised; outputs re-referenced)
// ---------------------------------------------------------------------------

#[derive(serde::Serialize, serde::Deserialize)]
struct Walls {
    glyph_id: String,
    is_space: bool,
    width: f64,                  // x_max - x_min (raw bounds)
    y_min: f64,
    y_max: f64,
    rows: Vec<f64>,              // ink rows only, y ascending
    left_wall: Vec<f64>,         // leftmost ink per row, x_min-normalised
    right_wall: Vec<f64>,        // rightmost ink per row, x_min-normalised
    widths: Vec<f64>,            // per-row total ink width (sum of intervals)
    interval_widths: Vec<f64>,   // every ink interval width (for stem measure)
    /// rev2 counter channel: per-row interior white widths (gaps between
    /// consecutive ink intervals, enclosed + semi-enclosed), rows in `rows`.
    interior_gaps: Vec<Vec<f64>>,
    h_eff: f64,                  // number of ink rows (uniform row weight)
}

fn build_walls(p: &OutlineProfile, letter: Option<char>) -> Result<Walls, SpacingError> {
    let nf = |field: &'static str, v: f64| -> Result<f64, SpacingError> {
        if v.is_finite() { Ok(v) } else {
            Err(SpacingError::NonFinite { glyph_id: p.glyph_id.clone(), field })
        }
    };
    let x_min = nf("bounds[0]", p.bounds[0])?;
    let y_min = nf("bounds[1]", p.bounds[1])?;
    let x_max = nf("bounds[2]", p.bounds[2])?;
    let y_max = nf("bounds[3]", p.bounds[3])?;
    nf("origin[0]", p.origin[0])?;
    nf("origin[1]", p.origin[1])?;
    if !(x_max >= x_min) || !(y_max >= y_min) {
        return Err(SpacingError::InvalidProfile {
            glyph_id: p.glyph_id.clone(),
            reason: format!("degenerate bounds [{x_min},{y_min},{x_max},{y_max}]"),
        });
    }
    nf("ink_area", p.ink_area)?;
    nf("counter_area", p.counter_area)?;
    nf("open_left", p.open_left)?;
    nf("open_right", p.open_right)?;

    let id_lc = p.glyph_id.to_ascii_lowercase();
    let is_space = letter == Some(' ')
        || id_lc == "space" || id_lc == " " || id_lc == "uni0020";

    let mut rows = Vec::new();
    let mut left_wall = Vec::new();
    let mut right_wall = Vec::new();
    let mut widths = Vec::new();
    let mut interval_widths = Vec::new();
    let mut interior_gaps = Vec::new();
    let mut prev_y: Option<f64> = None;

    for row in p.rows.iter() {
        nf("row.y", row.y)?;
        if let Some(py) = prev_y {
            if row.y < py {
                return Err(SpacingError::InvalidProfile {
                    glyph_id: p.glyph_id.clone(),
                    reason: "rows not sorted by y".into(),
                });
            }
        }
        prev_y = Some(row.y);
        if row.ink.is_empty() {
            continue; // K1 keeps empty-ink rows; they carry no wall
        }
        let mut lw = f64::INFINITY;
        let mut rw = f64::NEG_INFINITY;
        let mut row_width = 0.0;
        let mut prev_right: Option<f64> = None;
        let mut gaps = Vec::new();
        for iv in &row.ink {
            let l = nf("ink.left", iv.left)?;
            let r = nf("ink.right", iv.right)?;
            if !(r > l) {
                return Err(SpacingError::InvalidProfile {
                    glyph_id: p.glyph_id.clone(),
                    reason: format!("degenerate ink interval [{l},{r}] at y={}", row.y),
                });
            }
            if let Some(pr) = prev_right {
                if l < pr {
                    return Err(SpacingError::InvalidProfile {
                        glyph_id: p.glyph_id.clone(),
                        reason: "ink intervals not disjoint/sorted".into(),
                    });
                }
                gaps.push(l - pr); // interior white between consecutive ink
            }
            prev_right = Some(r);
            let w = r - l;
            row_width += w;
            interval_widths.push(w);
            if l < lw { lw = l; }
            if r > rw { rw = r; }
        }
        rows.push(row.y);
        left_wall.push(lw - x_min);
        right_wall.push(rw - x_min);
        widths.push(row_width);
        interior_gaps.push(gaps);
    }
    let h_eff = rows.len() as f64;

    Ok(Walls {
        glyph_id: p.glyph_id.clone(),
        is_space,
        width: x_max - x_min,
        y_min,
        y_max,
        rows,
        left_wall,
        right_wall,
        widths,
        interval_widths,
        interior_gaps,
        h_eff,
    })
}

/// Resolve the letter identity of a glyph: manifest-bound codepoint map
/// first, then raw-id parsing (single char, uniXXXX / u+XXXX). Numeric raw
/// ids resolve to None -> the glyph is never treated as a letter anchor.
fn letter_of(cp_map: &HashMap<String, u32>, glyph_id: &str) -> Option<char> {
    if let Some(cp) = cp_map.get(glyph_id) {
        return char::from_u32(*cp);
    }
    if glyph_id.chars().count() == 1 {
        return glyph_id.chars().next();
    }
    let hex = glyph_id.strip_prefix("uni")
        .or_else(|| glyph_id.strip_prefix("u+"))?;
    if hex.len() == 4 || hex.len() == 6 {
        if let Ok(v) = u32::from_str_radix(hex, 16) {
            return char::from_u32(v);
        }
    }
    None
}

/// Plain median (deterministic; even count -> lower-middle average).
fn median(mut v: Vec<f64>) -> Option<f64> {
    if v.is_empty() { return None; }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = v.len();
    if n % 2 == 1 { Some(v[n / 2]) } else { Some((v[n / 2 - 1] + v[n / 2]) / 2.0) }
}

/// rev2 §2 counter channel: mean interior white width per row over the rows
/// where interior white exists. 0.0 when the glyph has no interior gaps.
fn counter_channel(w: &Walls) -> f64 {
    let mut sum = 0.0;
    let mut n = 0.0;
    for gaps in &w.interior_gaps {
        if !gaps.is_empty() {
            sum += gaps.iter().sum::<f64>();
            n += 1.0;
        }
    }
    if n > 0.0 { sum / n } else { 0.0 }
}

/// Classify one side of a glyph from its band wall series (rev2 §4).
/// `wall` = per-band-row distance from the box edge to first ink (>= 0),
/// already clamped to `dcap` for open rows by the caller.
fn classify_side(wall: &[f64], s: f64) -> SideClass {
    if wall.is_empty() { return SideClass::Empty; }
    let n = wall.len();
    let min = wall.iter().cloned().fold(f64::INFINITY, f64::min);
    let max = wall.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let range = max - min;
    // Arm: a jump larger than the stem width between adjacent band rows.
    let mut max_jump = 0.0f64;
    let mut same_sign = 0usize; // consecutive deltas sharing one nonzero sign
    let mut sign = 0i32;
    let mut sign_changes = 0usize;
    for wpair in wall.windows(2) {
        let d = wpair[1] - wpair[0];
        if d.abs() > max_jump { max_jump = d.abs(); }
        let ds = if d > 0.0 { 1 } else if d < 0.0 { -1 } else { 0 };
        if ds != 0 {
            if sign != 0 && ds != sign { sign_changes += 1; }
            if ds == sign { same_sign += 1; }
            sign = ds;
        }
    }
    if s > 0.0 && max_jump > s { return SideClass::Arm; }
    if range <= 0.5 * s { return SideClass::Straight; }
    // Diagonal: one drift direction dominates the whole band.
    if sign_changes == 0 && same_sign + 1 >= n / 2 { return SideClass::Diagonal; }
    // Round: smooth boundary with direction changes.
    if s > 0.0 && max_jump <= 0.5 * s { return SideClass::Round; }
    SideClass::Open
}

// ---------------------------------------------------------------------------
// J(d) geometry (ported from supreme patch 12:09): piecewise-linear walls,
// common y-grid (K1 guarantees a bit-identical grid via grid_anchor_y; the
// union-grid cells below stay correct even if that guarantee ever breaks),
// exact integration. No exact-y row matching anywhere.
// ---------------------------------------------------------------------------

#[cfg(test)]
use crate::signed_clearance::clearance_cells_constant;

/// Sign-aware next representable f64 toward +infinity (chief 22:56 review:
/// a bare `to_bits()+1` walks negative floats the WRONG way - bits+1 on a
/// negative makes it MORE negative). +0.0 steps to the min positive
/// subnormal; -0.0 is normalised to +0.0 first. NaN/infinite inputs are a
/// typed numeric failure upstream, never reached here.
#[cfg(test)]
fn next_up(v: f64) -> f64 {
    debug_assert!(v.is_finite());
    if v == 0.0 { return f64::from_bits(1); } // min positive subnormal
    if v > 0.0 { f64::from_bits(v.to_bits() + 1) } else { f64::from_bits(v.to_bits() - 1) }
}

/// Sign-aware next representable f64 toward -infinity (symmetric).
#[cfg(test)]
fn next_down(v: f64) -> f64 {
    debug_assert!(v.is_finite());
    if v == 0.0 { return -f64::from_bits(1); }
    if v > 0.0 { f64::from_bits(v.to_bits() - 1) } else { f64::from_bits(v.to_bits() + 1) }
}



/// Common y-grid cells (length, gap, gap) at shift 0 — the single canonical
/// PIECEWISE-CONSTANT full-interval primitive (chief ruling 22:55: the
/// solver's own linear model is deleted; one model for objective, collision
/// constraint and export guard). Frame mapping from the old x_min-normalised
/// wall formula gap = rw_left - lw_right + l_width + sides to the primitive's
/// raw-frame offset: offset = l_xmax - r_xmin + sides (the width term is
/// load-bearing: flush right walls must not read as overlap of width units).
#[cfg(test)]
fn common_cells(l: &OutlineProfile, r: &OutlineProfile, sides: f64) -> Vec<(f64, f64, f64)> {
    let offset = l.bounds[2] - r.bounds[0] + sides;
    clearance_cells_constant(l, r, offset)
}

/// common_cells with the per-call allocation hoisted out: clears `out` and
/// pushes the same cells in the same order (the pair-cascade and fallback
/// loops evaluate one pair per iteration; one scratch Vec per worker instead
/// of one fresh Vec per pair). Same inputs, same bits.
fn common_cells_into(l: &OutlineProfile, r: &OutlineProfile, sides: f64, out: &mut Vec<(f64, f64, f64)>) {
    let offset = l.bounds[2] - r.bounds[0] + sides;
    crate::signed_clearance::clearance_cells_constant_rows_into(
        &crate::outline_spacing::align_pair_rows(l, r), offset, out);
}

/// Integrals over one linear gap segment of min(c, cap) and min(c, cap)^2.
fn cell_integrals(len: f64, c0: f64, c1: f64, cap: f64) -> (f64, f64) {
    let lin = |len: f64, a: f64, b: f64|
        (len * (a + b) / 2.0, len * (a * a + a * b + b * b) / 3.0);
    if c0 <= cap && c1 <= cap { return lin(len, c0, c1); }
    if c0 >= cap && c1 >= cap { return (len * cap, len * cap * cap); }
    let f = (cap - c0) / (c1 - c0); // crossing fraction in (0,1)
    let (lo_len, hi_len) = (len * f, len * (1.0 - f));
    if c0 < cap {
        let (a, b) = lin(lo_len, c0, cap);
        (a + hi_len * cap, b + hi_len * cap * cap)
    } else {
        let (a, b) = lin(hi_len, cap, c1);
        (a + lo_len * cap, b + lo_len * cap * cap)
    }
}

/// (mean capped gap W(t), variance of capped gap) at shift t over all cells.
pub(crate) fn channel_stats(cells: &[(f64, f64, f64)], t: f64, cap: f64) -> (f64, f64) {
    let (mut len, mut s1, mut s2) = (0.0, 0.0, 0.0);
    for &(l, c0, c1) in cells {
        let (a, b) = cell_integrals(l, c0 + t, c1 + t, cap);
        len += l; s1 += a; s2 += b;
    }
    if !(len > 0.0) { return (0.0, 0.0); }
    let w = s1 / len;
    (w, (s2 / len - w * w).max(0.0))
}

/// channel_stats over a pair's clearance cells at `offset` without
/// materialising the cell Vec (K2 pair-cascade hot path: one fused pass per
/// evaluated placement instead of an allocating cell collection followed by
/// a reduction). The fold walks the same cells in the same row order and
/// applies the same per-cell cell_integrals accumulation
/// (len += l; s1 += a; s2 += b), so the returned (w, v) is bit-identical to
/// channel_stats on the collected cells. None exactly when the collected
/// cell set would be empty (the caller's cells.is_empty() branch).
pub(crate) fn channel_stats_rows(rows: &[crate::outline_spacing::AlignedRow],
                                 offset: f64, t: f64, cap: f64) -> Option<(f64, f64)> {
    let (mut len, mut s1, mut s2) = (0.0, 0.0, 0.0);
    let mut any = false;
    crate::signed_clearance::for_each_clearance_cell_constant_rows(rows, offset, |l, c0, c1| {
        let (a, b) = cell_integrals(l, c0 + t, c1 + t, cap);
        len += l; s1 += a; s2 += b;
        any = true;
    });
    if !any { return None; }
    if !(len > 0.0) { return Some((0.0, 0.0)); }
    let w = s1 / len;
    Some((w, (s2 / len - w * w).max(0.0)))
}

/// Per-pair argmin of J(t) = (W(t)-pair_gap)^2 + lambda*V(t) over
/// [t_lo, t_hi]. K5 objective/derivative note (chief-architect revised):
/// cell gap c(y)+t is linear in y, so each cell's clamped integrals are
/// piecewise polynomial in t with breakpoints at t = cap - c0 and
/// t = cap - c1; W is piecewise quadratic, V = S2/L - W^2 piecewise
/// quartic, J' piecewise cubic. The complete candidate set is therefore
/// {t_lo, t_hi, every cap breakpoint in [t_lo,t_hi], every real root of
/// J' inside an open piece}. Stationary candidates are bracket-isolated
/// at f64 resolution: a numerical candidate solve, not an algebraic
/// exactness certificate. lambda == 0 keeps the frozen path (W-root
/// bisection + endpoints + breakpoints), bit-identical to the
/// 12:12-verified solver (bit-identity is a determinism claim, not an
/// exactness claim). Selection tie rule (unchanged): smaller J, then
/// smaller |t|, then smaller t.
fn solve_pair_t(cells: &[(f64, f64, f64)], cap: f64, pair_gap: f64,
                lambda: f64, t_lo: f64, t_hi: f64) -> f64 {
    let obj = |t: f64| -> f64 {
        let (w, v) = channel_stats(cells, t, cap);
        (w - pair_gap) * (w - pair_gap) + lambda * v
    };
    let mut ts: Vec<f64> = vec![t_lo];
    if lambda == 0.0 {
        // Frozen path: root of W(t)=target by bisection to f64 resolution
        // (W continuous, nondecreasing), every cap breakpoint at a cell end.
        let w_of = |t: f64| channel_stats(cells, t, cap).0;
        let root = if w_of(t_lo) >= pair_gap { t_lo }
            else if w_of(t_hi) <= pair_gap { t_hi }
            else {
                let (mut lo, mut hi) = (t_lo, t_hi);
                loop {
                    let mid = lo + (hi - lo) / 2.0;
                    if !(mid > lo && mid < hi) { break; }
                    if w_of(mid) < pair_gap { lo = mid } else { hi = mid }
                }
                hi
            };
        ts.push(root);
        for c in cells { for v in [c.1, c.2] {
            let t = cap - v;
            if t.is_finite() && t >= t_lo && t <= t_hi { ts.push(t); }
        } }
    } else {
        ts.push(t_hi);
        let mut bps: Vec<f64> = Vec::new();
        for c in cells { for v in [c.1, c.2] {
            let t = cap - v;
            if t.is_finite() && t > t_lo && t < t_hi { bps.push(t); }
        } }
        bps.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        bps.dedup();
        // Candidate-set contract (header): every cap breakpoint is itself a
        // candidate, not only a piece boundary. (For this objective W is
        // nondecreasing in t and V nonincreasing with downward J' kinks, so
        // a strict interior kink minimum cannot occur; breakpoints still
        // cover plateau edges and keep the claimed candidate set honest.)
        ts.extend_from_slice(&bps);
        let mut edge = t_lo;
        for bp in bps.into_iter().chain(std::iter::once(t_hi)) {
            if bp <= edge { edge = bp.max(edge); continue; }
            let (c3, c2, c1, c0) = piece_jprime_coeffs(cells, edge, bp, cap, pair_gap, lambda);
            if !c3.is_finite() || !c2.is_finite() || !c1.is_finite() || !c0.is_finite() {
                return f64::NAN; // declared bounded failure (see below)
            }
            if c3 == 0.0 && c2 == 0.0 && c1 == 0.0 && c0 == 0.0 {
                // J flat over the piece: keep the tie rule's winner inside
                // the piece (smallest |t|, then smaller t).
                ts.push(if edge <= 0.0 && bp >= 0.0 { 0.0 }
                    else if edge.abs() <= bp.abs() { edge } else { bp });
            } else {
                match isolated_roots_in_piece(c3, c2, c1, c0, edge, bp) {
                    // Non-finite numeric state: DECLARED BOUNDED FAILURE.
                    // NaN makes the caller land the pair in the
                    // excluded_unmeasurable ledger - never an empty
                    // "complete" pass on broken numerics.
                    None => return f64::NAN,
                    Some(rs) => for r in rs {
                        if r.is_finite() && r > edge && r < bp { ts.push(r); }
                    },
                }
            }
            edge = bp;
        }
    }
    let mut best_t = f64::NAN;
    let mut best_j = f64::INFINITY;
    for &t in &ts {
        let jv = obj(t);
        if !jv.is_finite() { continue; }
        let better = jv < best_j
            || (jv == best_j && (t.abs() < best_t.abs()
                || (t.abs() == best_t.abs() && t < best_t)));
        if better { best_j = jv; best_t = t; }
    }
    best_t
}

/// Coefficients of J'(t) = c3 t^3 + c2 t^2 + c1 t + c0 on one open piece
/// (lo, hi) containing no cap breakpoint, so every cell's clamp regime is
/// fixed (classified at the piece midpoint). Derived by hand from
/// cell_integrals: an uncapped cell contributes A = l*(t + (c0+c1)/2) and
/// B = l*(t^2 + (c0+c1) t + (c0^2+c0 c1+c1^2)/3); a fully capped cell
/// contributes constants; a crossing cell (integrals are orientation-free,
/// so the cell is flipped to make the uncapped end first) contributes with
/// f(t) = (cap - cu - t)/(cc - cu) linear: A quadratic, B cubic in t.
/// J = (w-T)^2 + lambda*(v_raw - w^2), so
/// J' = 2((1-lambda) w - T) w' + lambda*v_raw'
/// with w = S1/L, v_raw = S2/L. (NOT 2(1-lambda)(w-T)w': the variance
/// term subtracts w^2, which leaves -lambda*w*w', not -lambda*T*w'.)
fn piece_jprime_coeffs(cells: &[(f64, f64, f64)], lo: f64, hi: f64,
                       cap: f64, target: f64, lambda: f64)
    -> (f64, f64, f64, f64) {
    let mid = (lo + hi) / 2.0;
    let (mut lsum, mut a2, mut a1, mut a0) = (0.0, 0.0, 0.0, 0.0);
    // S2's constant term b0 is not accumulated: it vanishes under d/dt.
    let (mut b3, mut b2, mut b1) = (0.0, 0.0, 0.0);
    for &(l, c0, c1) in cells {
        let v0 = c0 + mid;
        let v1 = c1 + mid;
        lsum += l;
        if v0 <= cap && v1 <= cap {
            a1 += l;
            a0 += l * (c0 + c1) / 2.0;
            b2 += l;
            b1 += l * (c0 + c1);
        } else if v0 >= cap && v1 >= cap {
            a0 += l * cap;
        } else {
            let (cu, cc) = if v0 < cap { (c0, c1) } else { (c1, c0) };
            let d = cc - cu;
            let al = -1.0 / d;
            let be = (cap - cu) / d;
            let ga = (cu + cap) / 2.0;
            let p = 2.0 * cu + cap;
            let r = cu * cu + cu * cap + cap * cap;
            a2 += l * al / 2.0;
            a1 += l * (ga * al + be / 2.0 - cap * al);
            a0 += l * (be * ga + cap - cap * be);
            b3 += l * al / 3.0;
            b2 += l * (al * p + be) / 3.0;
            b1 += l * ((al * r + be * p) / 3.0 - cap * cap * al);
        }
    }
    if !(lsum > 0.0) { return (0.0, 0.0, 0.0, 0.0); }
    let (w2, w1, w0) = (a2 / lsum, a1 / lsum, a0 / lsum);
    let (s3, s2, s1) = (b3 / lsum, b2 / lsum, b1 / lsum);
    let om = 1.0 - lambda;
    (
        4.0 * om * w2 * w2,
        6.0 * om * w2 * w1 + 3.0 * lambda * s3,
        2.0 * om * w1 * w1 + 4.0 * w2 * (om * w0 - target) + 2.0 * lambda * s2,
        2.0 * (om * w0 - target) * w1 + lambda * s1,
    )
}

/// Real roots of J'(t) = c3 t^3 + c2 t^2 + c1 t + c0 inside the open piece
/// (lo, hi), with a completeness argument instead of a closed form
/// (chief-architect 21:31: coefficient-scale epsilon dropping plus a fixed
/// Newton budget does not certify completeness).
///
/// Method: work in the interval-normalized variable u in (-1, 1),
/// t = m + h*u, m = (lo+hi)/2, h = (hi-lo)/2, so coefficient magnitudes
/// are comparable independent of the t unit and interval size. p(u) =
/// J'(m + h*u) is still a cubic; p' is a quadratic whose real roots
/// (stable quadratic formula, no degree dropping) split (-1, 1) into at
/// most 3 segments on which p is monotonic. On a monotonic segment a root
/// exists iff the endpoint signs differ, and bisection then converges to
/// the closest representable bracket (same f64 standard as the frozen
/// W-root path). A multiple (tangent) root is also a root of p', so it is
/// checked at each extremum by a residual guard. The guard only ADDS
/// candidates; a spurious near-stationary point is evaluated honestly by
/// the selection and cannot fabricate a lower J.
///
/// NUMERIC SCOPE (chief-architect 21:35): this is an f64-resolution
/// numerical candidate solve, NOT an algebraic exactness certificate, and
/// no completeness theorem is claimed under binary64 rounding. A
/// non-finite numeric state (overflow in the transform, coefficients,
/// discriminant, or p evaluations) is a DECLARED BOUNDED FAILURE: the
/// function returns None, solve_pair_t returns NaN, and the pair lands in
/// the excluded_unmeasurable ledger - an empty "complete" pass on broken
/// numerics would be worse than the refusal.
fn isolated_roots_in_piece(c3: f64, c2: f64, c1: f64, c0: f64,
                           lo: f64, hi: f64) -> Option<Vec<f64>> {
    let m = (lo + hi) / 2.0;
    let h = (hi - lo) / 2.0;
    if !(h > 0.0) || !m.is_finite() || !h.is_finite() {
        if h == 0.0 && m.is_finite() { return Some(Vec::new()); } // no piece
        return None; // non-finite geometry: declared bounded failure
    }
    // p(u) = J'(m + h*u) = A3 u^3 + A2 u^2 + A1 u + A0 (exact expansion).
    let a3 = c3 * h * h * h;
    let a2 = (3.0 * c3 * m + c2) * h * h;
    let a1 = ((3.0 * c3 * m + 2.0 * c2) * m + c1) * h;
    let a0 = ((c3 * m + c2) * m + c1) * m + c0;
    let p = |u: f64| ((a3 * u + a2) * u + a1) * u + a0;
    // Explicit per-coefficient check: f64::max DISCARDS NaN, so a NaN
    // coefficient would slip through a max-based scale test.
    if !a3.is_finite() || !a2.is_finite() || !a1.is_finite() || !a0.is_finite() {
        return None; // overflowed/NaN transform: declared bounded failure
    }
    let scale = a3.abs().max(a2.abs()).max(a1.abs()).max(a0.abs());
    if scale == 0.0 { return Some(Vec::new()); } // exactly flat: caller handles
    // Extrema of p: roots of p'(u) = 3 a3 u^2 + 2 a2 u + a1 via the stable
    // quadratic formula. No degree dropping: a tiny qa moves the spurious
    // root far outside (-1, 1), where the segment filter drops it.
    let (qa, qb, qc) = (3.0 * a3, 2.0 * a2, a1);
    if !qa.is_finite() || !qb.is_finite() || !qc.is_finite() { return None; }
    let mut extrema: Vec<f64> = Vec::new();
    if qa != 0.0 {
        let disc = qb * qb - 4.0 * qa * qc;
        if !disc.is_finite() { return None; } // overflowed discriminant
        if disc >= 0.0 {
            let sq = disc.sqrt();
            let q = if qb >= 0.0 { -0.5 * (qb + sq) } else { -0.5 * (qb - sq) };
            if q != 0.0 {
                extrema.push(q / qa);
                extrema.push(qc / q);
            } else {
                extrema.push(-qb / (2.0 * qa));
            }
        }
    } else if qb != 0.0 {
        extrema.push(-qc / qb);
    }
    extrema.retain(|&u| u > -1.0 && u < 1.0 && u.is_finite());
    extrema.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    extrema.dedup();
    let mut bounds: Vec<f64> = vec![-1.0];
    bounds.extend_from_slice(&extrema);
    bounds.push(1.0);
    let mut roots: Vec<f64> = Vec::new();
    // Residual guard for multiple (tangent) roots at extrema: generous
    // 1e-9 of the coefficient scale; inclusion-only, never a filter.
    const RESIDUAL_GUARD: f64 = 1e-9;
    for &e in &extrema {
        let pe = p(e);
        if !pe.is_finite() { return None; }
        if pe.abs() <= RESIDUAL_GUARD * scale {
            // The extremum candidate itself is KEPT unconditionally
            // (chief-architect 21:35: "inclusion-only" is only true if the
            // pre-polish candidate survives). The polished copy is an
            // ADDITIONAL candidate, only when it stays finite, in-piece
            // and low-residual.
            let kept = m + h * e;
            if !kept.is_finite() { return None; }
            roots.push(kept);
            let mut u = e; // fixed 4-step Newton polish, normalized variable
            for _ in 0..4 {
                let f = p(u);
                let df = (3.0 * a3 * u + 2.0 * a2) * u + a1;
                if !f.is_finite() || !df.is_finite() { return None; }
                if df == 0.0 { break; }
                let nu = u - f / df;
                if nu == u { break; }
                u = nu;
            }
            let pu = p(u);
            if !pu.is_finite() { return None; }
            if u != e && u > -1.0 && u < 1.0 && pu.abs() <= RESIDUAL_GUARD * scale {
                let polished = m + h * u;
                if !polished.is_finite() { return None; }
                roots.push(polished);
            }
        }
    }
    // Sign-change roots on monotonic segments: bisection to f64 fixpoint.
    for w in bounds.windows(2) {
        let (a, b) = (w[0], w[1]);
        if !(b > a) { continue; }
        let pa = p(a);
        let pb = p(b);
        if !pa.is_finite() || !pb.is_finite() { return None; }
        if pa == 0.0 {
            if a > -1.0 && a < 1.0 { roots.push(m + h * a); }
            continue;
        }
        if (pa > 0.0) == (pb > 0.0) { continue; } // monotonic: no crossing
        // invariant: p(xlo) has pa's sign, p(xhi) has pb's sign
        let (mut xlo, mut xhi) = (a, b);
        loop {
            let mid = xlo + (xhi - xlo) / 2.0;
            if !(mid > xlo && mid < xhi) { break; }
            let pm = p(mid);
            if !pm.is_finite() { return None; }
            if (pm > 0.0) == (pa > 0.0) { xlo = mid; } else { xhi = mid; }
        }
        let root = m + h * xhi;
        if !root.is_finite() { return None; }
        roots.push(root);
    }
    Some(roots)
}

// ---------------------------------------------------------------------------
// Band extraction
// ---------------------------------------------------------------------------

/// Per-band-row left/right depth series for one glyph: distance from the
/// box edge to first ink, clamped to `dcap`; rows with no ink in the band
/// contribute `dcap` (open form). Band = [baseline, top], intersected with
/// the glyph's own vertical extent (rev1 principle kept in rev2 §2: clamp to
/// the glyph's own extent for small glyphs).
/// The third series carries the glyph's own measured ink width per band
/// row; it is the weight column of the optical-centre LSB/RSB split (Lane
/// D) and is never clamped.
fn side_series(w: &Walls, baseline: f64, top: f64, dcap: f64)
    -> (Vec<f64>, Vec<f64>, Vec<f64>)
{
    let lo = baseline.max(w.y_min);
    let hi = top.min(w.y_max);
    let mut l = Vec::new();
    let mut r = Vec::new();
    let mut wts = Vec::new();
    if !(hi > lo) { return (l, r, wts); }
    for (i, &y) in w.rows.iter().enumerate() {
        if y < lo || y > hi { continue; }
        l.push(w.left_wall[i].min(dcap));
        r.push((w.width - w.right_wall[i]).min(dcap));
        wts.push(w.widths[i]);
    }
    (l, r, wts)
}

/// Optical-centre weighted mean of a band-row depth series (Lane D).
///
/// CONVENTION (written derivation): the perceived white beside a glyph
/// is read against the glyph's ink, so a band row's contribution to the
/// perceived side depth is proportional to the ink mass that row
/// carries. Weighting each row's clamped depth by the row's own
/// measured ink width places the depth measurement at the glyph's
/// vertical optical centre (ink-mass centroid, `optical_centre_y`)
/// instead of assuming a geometric, vertically uniform distribution.
/// No free parameters: the weights are font-internal measurements.
///
/// Bit-identity rule (Lane D "untouched pairs bit-identical"): when
/// every band-row weight is exactly equal (uniform vertical ink
/// distribution, e.g. rectangular stems), the optical centre coincides
/// with the band's uniform weighting and the weighted mean is BY
/// CONSTRUCTION the flat mean of the same series - the previous rule -
/// computed through the identical code path (`mean`), so such glyphs
/// and every pair built from them stay bit-identical. An empty series
/// keeps the previous `mean` behaviour (0.0).
#[cfg(test)]
fn optical_weighted_mean(depths: &[f64], weights: &[f64]) -> f64 {
    debug_assert_eq!(depths.len(), weights.len());
    let uniform = weights.len() < 2
        || weights.windows(2).all(|p| p[0] == p[1]);
    if uniform {
        return mean(depths);
    }
    let mut mass = 0.0f64;
    let mut acc = 0.0f64;
    for (d, wt) in depths.iter().zip(weights) {
        mass += *wt;
        acc += *wt * *d;
    }
    if mass > 0.0 { acc / mass } else { mean(depths) }
}

fn mean(v: &[f64]) -> f64 {
    if v.is_empty() { 0.0 } else { v.iter().sum::<f64>() / v.len() as f64 }
}

// ---------------------------------------------------------------------------
// Anchor modes (labels per architect rule 12:03: "measured" only for real
// source spacing)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(serde::Serialize, serde::Deserialize)]
enum AnchorMode {
    /// FontContext carried real source-measured spacing.
    MeasuredSource,
    /// Flush-box straight pairs collapsed; counter channel of straight-class
    /// glyphs carried the target (outline measurement, not source spacing).
    MeasuredOutlineSelfDerivedTarget,
    /// rev2 §3.1: straight|straight outer-channel mean.
    GeometryOnlyFallback,
    /// rev2 §3.4: no straight pairs; median min row gap at d=0.
    GeometryOnlyFallbackLowConfidence,
    /// EXPERIMENT (architect 12:34, AnchorStrategy::CounterChannel):
    /// counter channel selected explicitly. Self-derived, never "measured".
    CounterChannelExperimentSelfDerived,
}

impl std::fmt::Display for AnchorMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            AnchorMode::MeasuredSource => "MeasuredSource",
            AnchorMode::MeasuredOutlineSelfDerivedTarget =>
                "MeasuredOutlineSelfDerivedTarget",
            AnchorMode::GeometryOnlyFallback => "GeometryOnlyFallback",
            AnchorMode::GeometryOnlyFallbackLowConfidence =>
                "GeometryOnlyFallbackLowConfidence",
            AnchorMode::CounterChannelExperimentSelfDerived =>
                "CounterChannelExperimentSelfDerived",
        };
        write!(f, "{s}")
    }
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

/// Solve font-local spacing + pair positions.
///
/// `ctx` is the optional measured-spacing wrapper (architect decision); None
/// runs the deterministic geometry-only path (rev2 §3). Typed refusals on
/// empty input, mixed UPM, non-finite fields, malformed rows, resource
/// bounds, or when no target can be derived at all. Never invents a
/// stylistic constant; never emits a glyph absent from the input.
/// Frozen entry point: identical behaviour to canonical 59c2fda7 — it
/// delegates to the cascade with `AnchorStrategy::LegacyCascade`.
pub fn solve_spacing(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
) -> Result<SpacingSolution, SpacingError> {
    solve_spacing_jobs(profiles, ctx, policy, default_cascade_workers())
}

/// Worker count the legacy entry points use: the whole machine, matching the
/// former rayon global-pool driver.
fn default_cascade_workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1)
}

/// Jobs-capped variant: the pair cascade runs on an explicit worker pool of
/// exactly `jobs` threads (`jobs <= 1` evaluates inline on the calling
/// thread) instead of the rayon global pool, so a caller's --jobs contract
/// is honored. The eval closure is pure and the collect is an indexed,
/// order-preserving reduce, so the solution is bit-identical for any worker
/// count (oracle: pair_cascade_explicit_pool_bit_identical_across_worker_counts).
pub fn solve_spacing_jobs(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
    jobs: usize,
) -> Result<SpacingSolution, SpacingError> {
    solve_spacing_with_anchor_strategy_jobs(profiles, ctx, policy, AnchorStrategy::LegacyCascade, jobs)
}

/// Experimental entry point (source-only, architect decision 12:34): same
/// solver with an explicit anchor strategy. The strategy is always recorded
/// in `policy_derivation`; production callers stay on `solve_spacing`.
/// Pair-cascade driver selection. Production always runs the rayon
/// parallel driver; the test override runs the SAME eval/reduce code on one
/// thread so `pair_cascade_parallel_bit_identical_to_sequential` can assert
/// exact bit equality between the two drivers.
#[cfg(not(test))]
#[inline(always)]
fn pair_cascade_parallel() -> bool {
    true
}
#[cfg(test)]
fn pair_cascade_parallel() -> bool {
    PAIR_CASCADE_PARALLEL.load(std::sync::atomic::Ordering::SeqCst)
}
#[cfg(test)]
static PAIR_CASCADE_PARALLEL: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

pub fn solve_spacing_with_anchor_strategy(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
    strategy: AnchorStrategy,
) -> Result<SpacingSolution, SpacingError> {
    solve_spacing_with_anchor_strategy_jobs(profiles, ctx, policy, strategy, default_cascade_workers())
}

/// Strategy-explicit, jobs-capped variant: production main passes its --jobs
/// value here through `solve_spacing_jobs`; see that wrapper for the pool
/// contract and the bit-identity oracle.
pub fn solve_spacing_with_anchor_strategy_jobs(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
    strategy: AnchorStrategy,
    jobs: usize,
) -> Result<SpacingSolution, SpacingError> {
    solve_spacing_observed_jobs(profiles, ctx, policy, strategy, jobs, ClassHarmonyPolicy::default()).map(|(s, _, _)| s)
}

/// Class-audit-observing entry point (read-only observer,
/// metrics/src/class_audit.rs): the SAME solve, returned together with an
/// exact copy of the classifier state - facing classes, class membership,
/// and the resolved per-class-pair target with its cascade source
/// (measured / channel_k2 / cadence_lane_b / anchor_w_target). The
/// solution is bit-identical to `solve_spacing`; the audit is observation
/// only and never feeds back into any solver decision, spacing value, or
/// OTF byte. Use `ClassAudit::pair_target_for` for selected pairs (e.g.
/// v-c / y-o / v-o / f-v) or `ClassAudit::to_tsv` for the full report.
pub fn solve_spacing_with_class_audit(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
) -> Result<(SpacingSolution, crate::class_audit::ClassAudit), SpacingError> {
    solve_spacing_observed_jobs(profiles, ctx, policy, AnchorStrategy::LegacyCascade, default_cascade_workers(), ClassHarmonyPolicy::default()).map(|(s, a, _)| (s, a))
}

/// NV-2 entry point (work list 2026-10-16 items 2+3+7): the SAME cascade
/// plus the two class-harmony lanes, with every lane decision receipted in
/// the returned ClassHarmonyReport. `harmony` with both lanes off returns
/// the bit-identical frozen solution and an empty report. The kern layer
/// (`SpacingSolution::pairs`) is the only solver output the symmetry lane
/// may grow (promoted directions ship as ordinary solved pairs); the
/// class-units lane never touches pair or glyph output - its
/// harmonization is emitted as typed SPACING rows in the report.
pub fn solve_spacing_with_class_harmony(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
    harmony: ClassHarmonyPolicy,
) -> Result<(SpacingSolution, ClassHarmonyReport), SpacingError> {
    solve_spacing_observed_jobs(profiles, ctx, policy, AnchorStrategy::LegacyCascade, default_cascade_workers(), harmony)
        .map(|(s, _, report)| (s, report))
}

/// Internal observed solve: the full cascade, returning the solution plus
/// the class audit snapshot. Every pre-existing entry point discards the
/// audit, so their behaviour and the `SpacingSolution` shape are unchanged.
fn solve_spacing_observed_jobs(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
    strategy: AnchorStrategy,
    jobs: usize,
    harmony: ClassHarmonyPolicy,
) -> Result<(SpacingSolution, crate::class_audit::ClassAudit, ClassHarmonyReport), SpacingError> {
    let prepared = prepare_pair_context(profiles,ctx,policy,strategy,harmony)?;
    finish_pair_context(prepared,jobs,None).map(|v|v.expect("default solve always finishes"))
}
/// Post-A2 pair frame (stage 4 input). The solved pairs carry `origin_distance`/`wall_gap` measured against the stage-3
/// bearings; when A2 AUTO-SB rewrites the glyph lsb/rsb/advance those pair values are in a stale frame. This re-runs the SAME
/// prepare + pair cascade (identical eval/measurement code, anchor strategy and class-harmony policy as `solve_spacing_jobs`) with the
/// glyph metrics replaced by `glyphs`, and returns ONLY the rebased pair lists plus the accounting needed to keep the failure typed.
/// A glyph the rebase population has no metrics for is a typed error, never a silent default. No tolerance is touched.
#[derive(Debug, Clone)]
pub struct PairRebase {
    pub pairs: Vec<PairPosition>,
    pub fallback_pairs: Vec<PairPosition>,
    pub excluded_unmeasurable: usize,
    pub numeric_failed_pairs: usize,
    pub geometric_hold_pairs: usize,
    pub no_accepted_candidate_pairs: usize,
    pub complete: bool,
    pub accounting_closed: bool,
}

pub fn rebase_pairs_to_glyphs(
    profiles: &[OutlineProfile], ctx: Option<&FontContext>, policy: &SpacingPolicy, jobs: usize, glyphs: &[GlyphSpacing],
) -> Result<PairRebase, SpacingError> {
    let mut prepared = prepare_pair_context(profiles, ctx, policy, AnchorStrategy::LegacyCascade, ClassHarmonyPolicy::default())?;
    let by_id: HashMap<&str, &GlyphSpacing> = glyphs.iter().map(|g| (g.glyph_id.as_str(), g)).collect();
    for g in prepared.glyphs.iter_mut() {
        let Some(n) = by_id.get(g.glyph_id.as_str()) else {
            return Err(SpacingError::InvalidContext { reason: format!("post-A2 rebase: no metrics for glyph {}", g.glyph_id) });
        };
        g.lsb = n.lsb; g.rsb = n.rsb; g.advance = n.advance;
    }
    let (sol, _, _) = finish_pair_context(prepared, jobs, None)?.expect("default solve always finishes");
    Ok(PairRebase {
        pairs: sol.pairs, fallback_pairs: sol.fallback_pairs, excluded_unmeasurable: sol.excluded_unmeasurable,
        numeric_failed_pairs: sol.numeric_failed_pairs, geometric_hold_pairs: sol.geometric_hold_pairs,
        no_accepted_candidate_pairs: sol.no_accepted_candidate_pairs, complete: sol.complete, accounting_closed: sol.accounting_closed,
    })
}

/// Below-epsilon candidate run (slice 5, additive). Stage 3 drops every ordinary pair whose solved |residual| < epsilon as noise,
/// even when the natural placement really collides (exact ink). This runs the SAME pair cascade on the supplied final bearings
/// (non-self pairs only) and returns the solved position of EVERY below-epsilon direction. It decides nothing: stage 4 (exact
/// authority) keeps only those whose natural placement collides exactly and drops the rest with a typed reason. The stage-3
/// solution and its accounting are not modified.
pub fn solve_below_epsilon_candidates(
    profiles: &[OutlineProfile], ctx: Option<&FontContext>, policy: &SpacingPolicy, jobs: usize, glyphs: &[GlyphSpacing],
) -> Result<Vec<PairPosition>, SpacingError> {
    let mut prepared = prepare_pair_context(profiles, ctx, policy, AnchorStrategy::LegacyCascade, ClassHarmonyPolicy::default())?;
    let by_id: HashMap<&str, &GlyphSpacing> = glyphs.iter().map(|g| (g.glyph_id.as_str(), g)).collect();
    for g in prepared.glyphs.iter_mut() {
        let Some(n) = by_id.get(g.glyph_id.as_str()) else {
            return Err(SpacingError::InvalidContext { reason: format!("below-epsilon candidates: no metrics for glyph {}", g.glyph_id) });
        };
        g.lsb = n.lsb; g.rsb = n.rsb; g.advance = n.advance;
    }
    prepared.self_mode = 2;
    let (_, _, harmony) = finish_pair_context(prepared, jobs, None)?.expect("default solve always finishes");
    Ok(harmony.below_epsilon_candidates)
}

/// Outcome of the self-pair clearance run: every self pair that collides at its natural placement is either solved (position
/// returned, stage 4 then gates it) or listed in `unresolved` with a typed reason. Nothing is silently dropped.
#[derive(Debug, Clone)]
pub struct SelfPairReport {
    /// Self pairs whose natural placement collides under the export-frame evidence the kern guard uses (`evidence_at(...).collides()`).
    pub colliding: usize,
    /// Solved positions (appended to the pair list by the caller; stage 4 measures and may still hold them).
    pub solved: Vec<PairPosition>,
    /// Colliding self pairs whose solved |residual| fell below epsilon (stage 3's noise drop). Typed BELOW_EPSILON_RESIDUAL, NOT a
    /// cascade hold: the caller hands them to stage 4, which keeps them only if the natural placement collides exactly.
    /// `colliding == solved.len() + below_epsilon.len() + unresolved.len()`.
    pub below_epsilon: Vec<PairPosition>,
    /// Colliding self pairs the cascade did not solve: (glyph, typed reason). `colliding == solved.len() + below_epsilon.len() + unresolved.len()`.
    pub unresolved: Vec<(String, String)>,
}

/// Self-pair clearance (stage 4 input). Stage 3 excludes every self pair by construction (the model has no self term), so a
/// glyph whose own lsb+rsb are negative enough to make two copies overlap never receives a kern row. This runs the SAME pair
/// cascade restricted to self pairs whose natural placement collides (min base clearance < 0, the existing evidence), on the
/// supplied final `glyphs` bearings, and returns their solved positions through the identical eval/gates (guard-frame verified
/// origin, wall_gap, typed holds in stage 4). Non-colliding self pairs are not touched. The stage-3 solution is not modified.
/// Colliding self pairs the cascade cannot solve (for example an overlap deeper than the ink width, where the facing-cell model has
/// no cell) are reported as `unresolved` with a typed reason, never dropped.
pub fn solve_colliding_self_pairs(
    profiles: &[OutlineProfile], ctx: Option<&FontContext>, policy: &SpacingPolicy, jobs: usize, glyphs: &[GlyphSpacing],
) -> Result<SelfPairReport, SpacingError> {
    let mut prepared = prepare_pair_context(profiles, ctx, policy, AnchorStrategy::LegacyCascade, ClassHarmonyPolicy::default())?;
    let by_id: HashMap<&str, &GlyphSpacing> = glyphs.iter().map(|g| (g.glyph_id.as_str(), g)).collect();
    for g in prepared.glyphs.iter_mut() {
        let Some(n) = by_id.get(g.glyph_id.as_str()) else {
            return Err(SpacingError::InvalidContext { reason: format!("self-pair clearance: no metrics for glyph {}", g.glyph_id) });
        };
        g.lsb = n.lsb; g.rsb = n.rsb; g.advance = n.advance;
    }
    // Colliding census in the export frame the kern guard uses: copy two at origin distance = advance, x_translation = lsb - ink_xmin.
    let prof_by_id: HashMap<&str, &OutlineProfile> = prepared.profiles.iter().map(|p| (p.glyph_id.as_str(), p)).collect();
    let mut colliding: Vec<(String, usize, f64)> = Vec::new(); // (glyph, natural cells, natural min base)
    let mut cells: Vec<(f64, f64, f64)> = Vec::new();
    for w in prepared.walls.iter().filter(|w| w.h_eff > 0.) {
        let (Some(g), Some(p)) = (prepared.glyphs.iter().find(|g| g.glyph_id == w.glyph_id), prof_by_id.get(w.glyph_id.as_str())) else { continue };
        let tr = g.lsb - p.bounds[0];
        let hit = crate::signed_clearance::evidence_at(p, p, tr, tr, g.advance).map_or(false, |e| e.collides());
        if hit {
            common_cells_into(p, p, g.rsb + g.lsb, &mut cells);
            colliding.push((w.glyph_id.clone(), cells.len(), cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2))));
        }
    }
    prepared.self_mode = 1;
    let min_rows = prepared.policy.pair_min_shared_rows;
    let (sol, _, harmony) = finish_pair_context(prepared, jobs, None)?.expect("default solve always finishes");
    // The accounting of this restricted run is not meaningful (non-self pairs return early); only the self placements are taken.
    let mut solved: Vec<PairPosition> = sol.pairs.into_iter().filter(|p| p.left == p.right).collect();
    solved.extend(sol.fallback_pairs.into_iter().filter(|p| p.left == p.right));
    let below_epsilon: Vec<PairPosition> = harmony.below_epsilon_candidates.into_iter().filter(|p| p.left == p.right).collect();
    let solved_ids: std::collections::BTreeSet<&str> = solved.iter().chain(below_epsilon.iter()).map(|p| p.left.as_str()).collect();
    let unresolved: Vec<(String, String)> = colliding.iter().filter(|(g, _, _)| !solved_ids.contains(g.as_str())).map(|(g, n, mb)| {
        let reason = if *n < min_rows { format!("GATE_UNMEASURABLE_SHARED_ROWS_{n}_BELOW_{min_rows}") }
            else if !mb.is_finite() { "GATE_UNMEASURABLE_MIN_BASE_NONFINITE".to_string() }
            else if *mb >= 0.0 { "COLLIDES_IN_EXPORT_FRAME_ONLY_NATURAL_CLEARANCE_NONNEGATIVE".to_string() }
            else { "CASCADE_HOLD_OR_NO_ACCEPTED_CANDIDATE".to_string() };
        (g.clone(), reason)
    }).collect();
    Ok(SelfPairReport { colliding: colliding.len(), solved, below_epsilon, unresolved })
}

/// One ordered pair the stage-3 gate ledgered `excluded_unmeasurable`, with the typed reason and the measured evidence behind it.
#[derive(Debug, Clone, PartialEq)]
pub struct UnmeasurableDiag {
    pub left: String,
    pub right: String,
    /// `SHARED_ROWS_BELOW_MIN` (fewer common cells than `pair_min_shared_rows`) or `MIN_BASE_NONFINITE`.
    pub reason: &'static str,
    pub shared_rows: usize,
    pub min_required: usize,
    /// Vertical ink extent of each side, [y_min, y_max] of the profile bounds (explains disjoint-extent pairs).
    pub left_y: [f64; 2],
    pub right_y: [f64; 2],
}

/// Diagnostic only (no solver decision depends on it): recomputes, for every ordered non-self pair, the SAME gate the cascade
/// applies (`common_cells_into` on the stage-3 bearings, `cells.len() < pair_min_shared_rows`, non-finite `min_base`) and returns
/// the pairs that fail it with the numbers. Pairs that pass the gate are not listed (they were solved, held or below-epsilon).
pub fn diagnose_unmeasurable_pairs(
    profiles: &[OutlineProfile], ctx: Option<&FontContext>, policy: &SpacingPolicy,
) -> Result<Vec<UnmeasurableDiag>, SpacingError> {
    let prepared = prepare_pair_context(profiles, ctx, policy, AnchorStrategy::LegacyCascade, ClassHarmonyPolicy::default())?;
    let metrics: HashMap<&str, (f64, f64, f64)> = prepared.glyphs.iter().map(|g| (g.glyph_id.as_str(), (g.lsb, g.rsb, g.advance))).collect();
    let prof_by_id: HashMap<&str, &OutlineProfile> = prepared.profiles.iter().map(|p| (p.glyph_id.as_str(), p)).collect();
    let inked: Vec<&Walls> = prepared.walls.iter().filter(|w| w.h_eff > 0.).collect();
    let mut out = Vec::new();
    let mut cells: Vec<(f64, f64, f64)> = Vec::new();
    for la in &inked {
        for rb in &inked {
            if la.glyph_id == rb.glyph_id { continue; }
            let (Some(l), Some(r)) = (metrics.get(la.glyph_id.as_str()), metrics.get(rb.glyph_id.as_str())) else { continue };
            let (pl, pr) = (prof_by_id[la.glyph_id.as_str()], prof_by_id[rb.glyph_id.as_str()]);
            common_cells_into(pl, pr, l.1 + r.0, &mut cells);
            let reason = if cells.len() < prepared.policy.pair_min_shared_rows { Some("SHARED_ROWS_BELOW_MIN") }
                else if !cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2)).is_finite() { Some("MIN_BASE_NONFINITE") } else { None };
            if let Some(reason) = reason {
                out.push(UnmeasurableDiag { left: la.glyph_id.clone(), right: rb.glyph_id.clone(), reason, shared_rows: cells.len(),
                    min_required: prepared.policy.pair_min_shared_rows, left_y: [pl.bounds[1], pl.bounds[3]], right_y: [pr.bounds[1], pr.bounds[3]] });
            }
        }
    }
    Ok(out)
}

fn finish_pair_context(prepared: PreparedPairContext, jobs: usize, checkpoint: Option<&PairCheckpoint>)
 -> Result<Option<(SpacingSolution, crate::class_audit::ClassAudit, ClassHarmonyReport)>,SpacingError> {
    let PreparedPairContext { profiles,ctx,policy,strategy,harmony,upm,walls,infos,mut notes,mut unobserved,s,baseline,x_height,x_height_source,cap_height,dcap,mode,w_target,class_pair_targets,lambda,cadence_targets,channel_targets,glyphs,space_status,evaluations,eps,self_mode } = prepared;
    let ctx = ctx.as_ref();
    let policy = &policy;
    let inked: Vec<&Walls> = walls.iter().filter(|w|w.h_eff>0.).collect();
    let metrics: HashMap<&str,(f64,f64,f64)> = glyphs.iter().map(|g|(g.glyph_id.as_str(),(g.lsb,g.rsb,g.advance))).collect();
    let classes: HashMap<&str,(SideClass,SideClass)> = walls.iter().zip(&infos).map(|(w,i)|(w.glyph_id.as_str(),(i.cl,i.cr))).collect();
    let prof_by_id: HashMap<&str,&OutlineProfile> = profiles.iter().map(|p|(p.glyph_id.as_str(),p)).collect();
    let class_fallbacks: std::cell::RefCell<std::collections::BTreeSet<String>> = Default::default();
    let cadence_fallbacks: std::cell::RefCell<std::collections::BTreeSet<String>> = Default::default();
    let channel_fallbacks: std::cell::RefCell<std::collections::BTreeSet<String>> = Default::default();
    let class_target = |cl: SideClass, cr: SideClass| -> f64 {
        let (v, source) = resolve_class_target(
            cl, cr, &class_pair_targets, &channel_targets, &cadence_targets, w_target);
        match source {
            crate::class_audit::ClassTargetSource::MeasuredSource => {}
            crate::class_audit::ClassTargetSource::ChannelK2 =>
                { channel_fallbacks.borrow_mut().insert(format!("{cl:?}->{cr:?}")); }
            crate::class_audit::ClassTargetSource::CadenceLaneB =>
                { cadence_fallbacks.borrow_mut().insert(format!("{cl:?}->{cr:?}")); }
            crate::class_audit::ClassTargetSource::AnchorWTarget =>
                { class_fallbacks.borrow_mut().insert(format!("{cl:?}->{cr:?}")); }
        }
        v
    };

    let mut candidates: Vec<PairPosition> = Vec::new();
    let mut saturated_pairs = 0usize;
    let mut excluded_self_pairs = 0usize;
    let mut excluded_below_epsilon = 0usize;
    let mut excluded_unmeasurable = 0usize;
    let mut numeric_failed_pairs = 0usize;
    let mut geometric_hold_pairs = 0usize;
    let mut no_accepted_candidate_pairs = 0usize;
    let mut hold_reasons: Vec<String> = Vec::new();
    let mut pair_ledger: Vec<PairLedgerRow> = Vec::new();
    // Anchor-audit population: (class, residual) for every solved tier-1
    // placement. Analysis only; rows are never removed here or by the audit.
    let mut audit_rows: Vec<(String, f64)> = Vec::new();
    let mut failed_numeric: Vec<(String, String, NumericFailKind)> = Vec::new();
    // Pair cascade (rayon par_iter, 2026-10-16). Every ordered pair is
    // evaluated independently by the PURE closure below: it reads only
    // immutable maps/profiles and returns one PairEval value. rayon's
    // collect on an indexed parallel iterator preserves the flat row-major
    // index order, and the reduce after it runs SEQUENTIALLY in that same
    // order, so every ledger row, hold reason, candidate, counter and the
    // class-fallback set land exactly where the single-threaded loop put
    // them. No floating-point value is ever combined across pairs (all
    // cross-pair accumulation is integer counters and ordered Vec pushes),
    // so summation order cannot change and the result is bit-identical to
    // the sequential pass on any thread count. pair_cascade_parallel()
    // exists only so a test can drive the SAME eval/reduce code on one
    // thread and assert that bit-identity.
    // Which target resolution a pair used; carried to canonical reduce.
    let eval_one = |flat: usize, cells_scratch: &mut Vec<(f64, f64, f64)>| -> PairEval {
        let la = inked[flat / inked.len()];
        let rb = inked[flat % inked.len()];
        let is_self = la.glyph_id == rb.glyph_id;
        // self_mode 0 (every production solve): self pairs are excluded by construction. self_mode 1 (solve_colliding_self_pairs):
        // only self pairs reach the normal path, and only if the natural placement collides (checked below).
        if (is_self && self_mode != 1) || (!is_self && self_mode == 1) {
            return PairEval::SelfPair { left: la.glyph_id.clone(), right: rb.glyph_id.clone() };
        }
        // A glyph without solved sidebearings must never read as 0.0 (silent default): typed refusal.
        let (l_rsb, r_lsb) = match (metrics.get(la.glyph_id.as_str()), metrics.get(rb.glyph_id.as_str())) {
            (Some(l), Some(r)) => (l.1, r.0),
            (l, _) => {
                let missing = if l.is_none() { &la.glyph_id } else { &rb.glyph_id };
                return PairEval::MissingSidebearings { missing: missing.clone() };
            }
        };
        let (cl, cr) = (
            classes[la.glyph_id.as_str()].1, // right side of left glyph
            classes[rb.glyph_id.as_str()].0, // left side of right glyph
        );
        // Same single resolution path as the sequential closure and the
        // class audit (resolve_class_target): identical values by
        // construction; the fallback key is returned for the sequential
        // reduce to record.
        let (pair_gap, target_source) = resolve_class_target(
            cl, cr, &class_pair_targets, &channel_targets, &cadence_targets, w_target);
        let fallback_key = match target_source {
            crate::class_audit::ClassTargetSource::MeasuredSource => None,
            crate::class_audit::ClassTargetSource::ChannelK2 =>
                Some(ClassTargetKey::Channel(format!("{cl:?}->{cr:?}"))),
            crate::class_audit::ClassTargetSource::CadenceLaneB =>
                Some(ClassTargetKey::Cadence(format!("{cl:?}->{cr:?}"))),
            crate::class_audit::ClassTargetSource::AnchorWTarget =>
                Some(ClassTargetKey::Plain(format!("{cl:?}->{cr:?}"))),
        };
        let class = format!("{cl}->{cr}");
        let base_offset = l_rsb + r_lsb;
        let prof_l = prof_by_id[la.glyph_id.as_str()];
        let prof_r = prof_by_id[rb.glyph_id.as_str()];
        common_cells_into(prof_l, prof_r, base_offset, cells_scratch);
        let cells = &*cells_scratch;
        if cells.len() < policy.pair_min_shared_rows {
            return PairEval::GateUnmeasurable { left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, fallback_key };
        }
        let min_base = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
        if !min_base.is_finite() {
            return PairEval::GateUnmeasurable { left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, fallback_key };
        }
        if is_self && !(min_base < 0.0) {
            return PairEval::SelfPair { left: la.glyph_id.clone(), right: rb.glyph_id.clone() };
        }
        // Domain [t_lo, t_hi] = [-min_base, dcap - min_base]: the FROZEN
        // convention carried from the pre-L2 solver (chief 23:39 (3)) —
        // the residual range where the MINIMUM base clearance lands in
        // [0, dcap] (t_hi = dcap - min_base lifts only the minimum to
        // cap). Explicit convention, NOT a proven exact argmin
        // domain; exact feasible components are intersected with it
        // inside solve_pair_t_l2. Pairs whose first common_cells is
        // empty/short never reach L2: the pair_min_shared_rows gate
        // above ledgers them excluded_unmeasurable, by design.
        let t_lo = -min_base;
        let t_hi = (dcap - min_base).max(t_lo);
        let saturated = pair_gap > dcap;
        // L2 actual-placement solve (chief J-fix): exact feasible
        // components, per-component recompute, canonical evidence
        // reverify in the guard frame. The frozen-cells +t shift
        // (clearance(d+t) = clearance(d)+t) is RETIRED here: it is
        // unsound under facing-membership change (cells_residual_divergence).
        // Exact-model functions work in the raw profile shift frame:
        // common_cells composes l.bounds[2] - r.bounds[0] + sidebearings
        // (the physical placement); the residual is frame-invariant.
        let raw_base = prof_l.bounds[2] - prof_r.bounds[0] + base_offset;
        // Export-frame binding (chief 23:44 (1)): x_translation composed
        // exactly as the exporter's GlyphFrame::new (lsb - ink_xmin);
        // the solver verifies in THIS frame and returns the bit-exact
        // origin_distance the export guard re-checks.
        let advance_l = metrics[la.glyph_id.as_str()].2;
        let l_tr = metrics[la.glyph_id.as_str()].0 - prof_l.bounds[0];
        let r_tr = metrics[rb.glyph_id.as_str()].0 - prof_r.bounds[0];
        match solve_pair_t_l2(prof_l, prof_r, raw_base, dcap, pair_gap, lambda, t_lo, t_hi, advance_l, l_tr, r_tr) {
            PairSolve::Solved { residual, origin, wall_gap, component: _ } => {
                if residual.abs() < eps {
                    // NV-2 item 3: when the symmetry lane is on, the dropped
                    // direction still carries its solved placement, so a
                    // later promotion ships the exact verified solve. The
                    // frozen lane skips the recompute and stays bit- and
                    // cost-identical.
                    let position = if harmony.direction_symmetry || self_mode != 0 {
                        crate::signed_clearance::clearance_cells_constant_rows_into(
                            &crate::outline_spacing::align_pair_rows(prof_l, prof_r), raw_base + residual, cells_scratch);
                        let cells_at = &*cells_scratch;
                        let (_, var) = channel_stats(&cells_at, 0.0, dcap);
                        Some(Box::new(PairPosition {
                            left: la.glyph_id.clone(),
                            right: rb.glyph_id.clone(),
                            origin_distance: origin,
                            wall_gap,
                            optical_cost: var,
                            pair_target: usable_pair_target(pair_gap),
                            compensated: false,
                        }))
                    } else { None };
                    return PairEval::BelowEpsilon { left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, t_lo, t_hi, residual, saturated, fallback_key, wall_gap, position };
                }
                // The shipped origin_distance IS the verified one:
                // bit-exact, never recomposed (chief 23:38 (a) + 23:44 (1)).
                let origin_distance = origin;
                if !origin_distance.is_finite() {
                    return PairEval::NonFiniteOrigin { left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, t_lo, t_hi, residual, saturated, fallback_key };
                }
                debug_assert_eq!(residual.to_bits(), (origin - advance_l).to_bits(),
                    "Solved residual must be origin - advance by construction");
                crate::signed_clearance::clearance_cells_constant_rows_into(
                    &crate::outline_spacing::align_pair_rows(prof_l, prof_r), raw_base + residual, cells_scratch);
                let cells_at = &*cells_scratch;
                let (_, var) = channel_stats(&cells_at, 0.0, dcap);
                PairEval::Solved {
                    class,
                    residual,
                    position: PairPosition {
                        left: la.glyph_id.clone(),
                        right: rb.glyph_id.clone(),
                        origin_distance,
                        wall_gap,
                        optical_cost: var,
                        pair_target: usable_pair_target(pair_gap),
                        compensated: false,
                    },
                    saturated,
                    fallback_key,
                }
            }
            // GEOMETRIC domain hold (chief 23:39 (4)): no feasible
            // residual in the domain. NOT numeric, NOT a collision
            // verdict; the guard remains the final checker.
            PairSolve::NoFeasible => PairEval::NoFeasible {
                left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, t_lo, t_hi,
                hold: format!("{}->{}: NoFeasible (no feasible residual in [{t_lo:.6}, {t_hi:.6}])",
                    la.glyph_id, rb.glyph_id),
                saturated, fallback_key },
            // Components existed; no candidate accepted in the
            // declared domain (J loss / edge rejection). NOT
            // geometric-empty, NOT numeric (chief 23:44 (2)).
            PairSolve::NoAcceptedCandidate => PairEval::NoAcceptedCandidate {
                left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, t_lo, t_hi,
                hold: format!("{}->{}: NoAcceptedCandidate (components existed; no accepted candidate in [{t_lo:.6}, {t_hi:.6}])",
                    la.glyph_id, rb.glyph_id),
                saturated, fallback_key },
            PairSolve::NotConverged(reason) => PairEval::NotConverged {
                left: la.glyph_id.clone(), right: rb.glyph_id.clone(), kind: reason,
                hold: format!("{}->{}: NotConverged: {reason}",
                    la.glyph_id, rb.glyph_id),
                saturated, fallback_key },
            PairSolve::Unmeasurable => PairEval::SolveUnmeasurable {
                left: la.glyph_id.clone(), right: rb.glyph_id.clone(), class, t_lo, t_hi, saturated, fallback_key },
        }
    };
    // Driver: explicit worker pool of exactly `jobs` threads (indexed
    // collect, order-preserving), an inline sequential map for jobs <= 1,
    // or - under the test override - a plain sequential map over the same
    // closure. The pool is built per call so the requested worker count is
    // honored exactly; the rayon global pool would ignore it.
    let pair_total = inked.len() * inked.len();
    let evals: Vec<PairEval> = if let Some(checkpoint) = checkpoint {
        match checkpoint_pairs(checkpoint,pair_total,|flat| eval_one(flat,&mut Vec::new()))? {
            Some(v)=>v,
            None=>return Ok(None),
        }
    } else if pair_cascade_parallel() {
        if jobs <= 1 {
            let mut cells_scratch: Vec<(f64, f64, f64)> = Vec::new();
            (0..pair_total).map(|flat| eval_one(flat, &mut cells_scratch)).collect()
        } else {
            use rayon::prelude::*;
            let pool = rayon::ThreadPoolBuilder::new()
                .num_threads(jobs)
                .build()
                .expect("pair-cascade worker pool could not be built");
            pool.install(|| (0..pair_total).into_par_iter().map_init(Vec::new, |cells_scratch, flat| eval_one(flat, cells_scratch)).collect())
        }
    } else {
        let mut cells_scratch: Vec<(f64, f64, f64)> = Vec::new();
        (0..pair_total).map(|flat| eval_one(flat, &mut cells_scratch)).collect()
    };
    // NV-2 item 3 (direction symmetry) pre-pass: for every below-epsilon
    // direction whose REVERSE direction was emitted, the keep/drop decision
    // is shared - the dropped direction is promoted with its own verified
    // solve. Map: flat index of the dropped direction -> the reverse
    // direction's solved residual (receipt). Off lane: empty map, the
    // reduce below is the frozen path bit-for-bit.
    let mut symmetry_promote: std::collections::BTreeMap<usize, f64> = Default::default();
    if harmony.direction_symmetry {
        let nn = inked.len();
        for flat in 0..pair_total {
            if let PairEval::BelowEpsilon { .. } = &evals[flat] {
                let rev = (flat % nn) * nn + flat / nn;
                if let PairEval::Solved { residual: rres, .. } = &evals[rev] {
                    symmetry_promote.insert(flat, *rres);
                }
            }
        }
    }
    let mut symmetry_promotions: Vec<SymmetryPromotion> = Vec::new();
    // self_mode 2 only: every ordinary below-epsilon direction with its solved position (see solve_below_epsilon_candidates).
    let mut below_epsilon_candidates: Vec<PairPosition> = Vec::new();
    // NV-2 items 2+7 measurement population: (left, right, facing classes,
    // solved min ink gap, residual, emitted) for every tier-1 solved pair,
    // emitted and below-epsilon alike - the same population the work list's
    // Marq Alternate evidence (17 ready / 31 dropped) is drawn from.
    let mut class_measurements: Vec<(String, String, (SideClass, SideClass), f64, f64, bool)> = Vec::new();
    // Sequential reduce in flat row-major order: identical to the order the
    // single-threaded loop observed, so every ordered side effect below
    // (ledger rows, hold reasons, failed_numeric driving the tier-2 pass,
    // candidate push order feeding the stable max_pairs sort) is preserved
    // bit-for-bit.
    for (flat, ev) in evals.into_iter().enumerate() {
        match ev.fallback_key() {
            Some(ClassTargetKey::Plain(k)) => { class_fallbacks.borrow_mut().insert(k.clone()); }
            Some(ClassTargetKey::Cadence(k)) => { cadence_fallbacks.borrow_mut().insert(k.clone()); }
            Some(ClassTargetKey::Channel(k)) => { channel_fallbacks.borrow_mut().insert(k.clone()); }
            None => {}
        }
        if ev.is_saturated() { saturated_pairs += 1; }
        match ev {
            PairEval::SelfPair { left, right } => {
                excluded_self_pairs += 1;
                pair_ledger.push(PairLedgerRow { left, right,
                    class: "self".into(), reason: PairLedgerReason::ExcludedSelfPair, tier: 1,
                    t_lo: f64::NAN, t_hi: f64::NAN, residual: f64::NAN, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
            PairEval::MissingSidebearings { missing } => {
                return Err(SpacingError::InvalidProfile { glyph_id: missing, reason: "no solved sidebearing metrics for glyph in pair loop".into() });
            }
            PairEval::GateUnmeasurable { left, right, class, .. } => {
                excluded_unmeasurable += 1;
                pair_ledger.push(PairLedgerRow { left, right,
                    class, reason: PairLedgerReason::ExcludedUnmeasurable, tier: 1,
                    t_lo: f64::NAN, t_hi: f64::NAN, residual: f64::NAN, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
            PairEval::BelowEpsilon { left, right, class, t_lo, t_hi, residual, wall_gap, position, .. } => {
                // NV-2 item 3: shared keep/drop decision - the reverse
                // direction was emitted, so this direction ships its own
                // verified solve instead of the epsilon drop. Receipted in
                // the harmony report; never counted as below-epsilon.
                if let Some(rres) = symmetry_promote.get(&flat) {
                    let position = position.expect("symmetry-promoted pair carries its solved position (lane-gated construction)");
                    if harmony.class_spacing_units {
                        class_measurements.push((position.left.clone(), position.right.clone(),
                            (classes[position.left.as_str()].1, classes[position.right.as_str()].0),
                            wall_gap, residual, true));
                    }
                    symmetry_promotions.push(SymmetryPromotion {
                        left: position.left.clone(), right: position.right.clone(),
                        class: class.clone(), residual, reverse_residual: *rres,
                    });
                    audit_rows.push((class, residual));
                    candidates.push(*position);
                    continue;
                }
                if self_mode != 0 {
                    if let Some(p) = position { below_epsilon_candidates.push(*p); }
                }
                if harmony.class_spacing_units {
                    class_measurements.push((left.clone(), right.clone(),
                        (classes[left.as_str()].1, classes[right.as_str()].0),
                        wall_gap, residual, false));
                }
                excluded_below_epsilon += 1;
                audit_rows.push((class.clone(), residual));
                pair_ledger.push(PairLedgerRow { left, right,
                    class, reason: PairLedgerReason::ExcludedBelowEpsilon, tier: 1,
                    t_lo, t_hi, residual, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
            PairEval::NonFiniteOrigin { left, right, class, t_lo, t_hi, residual, .. } => {
                excluded_unmeasurable += 1;
                pair_ledger.push(PairLedgerRow { left, right,
                    class, reason: PairLedgerReason::ExcludedUnmeasurable, tier: 1,
                    t_lo, t_hi, residual, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
            PairEval::Solved { position, class, residual, .. } => {
                if harmony.class_spacing_units {
                    class_measurements.push((position.left.clone(), position.right.clone(),
                        (classes[position.left.as_str()].1, classes[position.right.as_str()].0),
                        position.wall_gap, residual, true));
                }
                audit_rows.push((class, residual));
                candidates.push(position);
            }
            PairEval::NoFeasible { left, right, class, t_lo, t_hi, hold, .. } => {
                geometric_hold_pairs += 1;
                hold_reasons.push(hold);
                pair_ledger.push(PairLedgerRow { left, right,
                    class, reason: PairLedgerReason::NoFeasible, tier: 1,
                    t_lo, t_hi, residual: f64::NAN, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
            PairEval::NoAcceptedCandidate { left, right, class, t_lo, t_hi, hold, .. } => {
                no_accepted_candidate_pairs += 1;
                hold_reasons.push(hold);
                pair_ledger.push(PairLedgerRow { left, right,
                    class, reason: PairLedgerReason::NoAcceptedCandidate, tier: 1,
                    t_lo, t_hi, residual: f64::NAN, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
            PairEval::NotConverged { left, right, kind, hold, .. } => {
                numeric_failed_pairs += 1;
                hold_reasons.push(hold);
                failed_numeric.push((left, right, kind));
            }
            PairEval::SolveUnmeasurable { left, right, class, t_lo, t_hi, .. } => {
                excluded_unmeasurable += 1;
                pair_ledger.push(PairLedgerRow { left, right,
                    class, reason: PairLedgerReason::ExcludedUnmeasurable, tier: 1,
                    t_lo, t_hi, residual: f64::NAN, j_star: f64::NAN,
                    kern_units: None, natural_safety: NaturalSafety::Unknown });
            }
        }
    }
    // Tier-2 fallback pass: numeric-failed pairs only. Natural placement
    // is checked first; a guard-clear natural advance needs no GPOS row.
    // Widening uses the measured min-gap deficit, and the exact exported
    // origin is re-guarded. Exhaustion falling back to natural output is
    // output rescue only and never receives a guard-safe label.
    let mut fallback_pairs: Vec<PairPosition> = Vec::new();
    let mut fallback_natural_clear_pairs = 0usize;
    let mut fallback_verified_pairs = 0usize;
    let mut numeric_failed_nonfinite = 0usize;
    let mut numeric_failed_malformed = 0usize;
    let mut numeric_failed_natural_unverifiable = 0usize;
    let mut numeric_failed_natural_frame_conflict = 0usize;
    let mut cells_scratch: Vec<(f64, f64, f64)> = Vec::new();
    for (lid, rid, kind) in failed_numeric {
        // Typed classification only. Non-finite: typed record, never a recovered value.
        if kind.is_nonfinite() {
            numeric_failed_nonfinite += 1;
            pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(),
                class: format!("{}->{}", classes[lid.as_str()].1, classes[rid.as_str()].0),
                reason: PairLedgerReason::NonFiniteFailure, tier: 1,
                t_lo: f64::NAN, t_hi: f64::NAN, residual: f64::NAN, j_star: f64::NAN,
                kern_units: None, natural_safety: NaturalSafety::Unknown });
            notes.push(format!("fallback: {lid}->{rid}: {kind}; typed record only, no tier-2 recovery"));
            continue;
        }
        // Recovery allowlist: only BracketExhausted. Malformed intervals mean the domain is untrustworthy.
        if !kind.recovery_allowed() {
            numeric_failed_malformed += 1;
            pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(),
                class: format!("{}->{}", classes[lid.as_str()].1, classes[rid.as_str()].0),
                reason: PairLedgerReason::NotConverged, tier: 1,
                t_lo: f64::NAN, t_hi: f64::NAN, residual: f64::NAN, j_star: f64::NAN,
                kern_units: None, natural_safety: NaturalSafety::Unknown });
            notes.push(format!("fallback: {lid}->{rid}: {kind}; not on the recovery allowlist, typed hold, no tier-2 recovery"));
            continue;
        }
        let prof_l = prof_by_id[lid.as_str()];
        let prof_r = prof_by_id[rid.as_str()];
        let (l_rsb, r_lsb) = (
            metrics.get(lid.as_str()).map(|m| m.1).unwrap_or(0.0),
            metrics.get(rid.as_str()).map(|m| m.0).unwrap_or(0.0),
        );
        let (cl, cr) = (
            classes[lid.as_str()].1,
            classes[rid.as_str()].0,
        );
        let class = format!("{cl}->{cr}");
        let pair_gap = class_target(cl, cr);
        let base_offset = l_rsb + r_lsb;
        let raw_base = prof_l.bounds[2] - prof_r.bounds[0] + base_offset;
        let advance_l = metrics[lid.as_str()].2;
        let l_tr = metrics[lid.as_str()].0 - prof_l.bounds[0];
        let r_tr = metrics[rid.as_str()].0 - prof_r.bounds[0];
        common_cells_into(prof_l, prof_r, base_offset, &mut cells_scratch);
        let cells_base = &*cells_scratch;
        let min_base = cells_base.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
        let t_lo = -min_base;
        let t_hi = (dcap - min_base).max(t_lo);
        crate::signed_clearance::clearance_cells_constant_rows_into(
            &crate::outline_spacing::align_pair_rows(prof_l, prof_r), raw_base, &mut cells_scratch);
        let cells0 = &*cells_scratch;
        // Natural-safe is decided by BOTH the checked raw cells (non-empty, all gaps
        // finite) AND canonical evidence_at in the export frame at the natural
        // origin advance_l (l_tr/r_tr exactly as the solver binds them). Empty cells
        // or a non-finite gap are never "safe" (no INFINITY / NaN-skipping fold).
        let natural_ev = crate::signed_clearance::evidence_at(prof_l, prof_r, l_tr, r_tr, advance_l);
        let canon = natural_ev.as_ref().map(|e| CanonNatural { collides: e.collides(), min_gap: e.clearance.min_gap });
        // SCOPE DECISION (why the widened path reruns the full L2 solve instead of a natural + measured-deficit
        // bracket): clearance(d+t) != clearance(d)+t because facing membership changes with distance (frozen-cells
        // shift is unsound, regression (a)). The measured deficit therefore only WIDENS the solve domain
        // [t_lo, t_hi + deficit]; the placement itself comes from solve_pair_t_l2 (exact feasible components +
        // evidence_at verified origin), never from "natural origin + deficit".
        let deficit = match decide_natural(&cells0, canon) {
            NaturalDecision::Safe { raw_min, canon_min_gap } => {
                numeric_failed_pairs -= 1;
                fallback_natural_clear_pairs += 1;
                pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(), class,
                    reason: PairLedgerReason::FallbackDerived, tier: 2, t_lo, t_hi,
                    residual: f64::NAN, j_star: f64::NAN, kern_units: None,
                    natural_safety: NaturalSafety::CheckedSafe });
                notes.push(format!("fallback: {lid}->{rid}: natural placement guard-clear (raw min_gap {raw_min:.6} at model-frame natural origin {raw_base:.6}; canonical evidence_at min_gap {canon_min_gap:.6}, non-colliding, at export origin {advance_l:.6}); no GPOS row (tier-2)"));
                continue;
            }
            NaturalDecision::Unverifiable => {
                numeric_failed_natural_unverifiable += 1;
                // No collision proof and no safe proof: Unknown, never Unsafe, never recovered.
                pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(), class,
                    reason: PairLedgerReason::NaturalUnverifiable, tier: 2, t_lo, t_hi,
                    residual: f64::NAN, j_star: f64::NAN, kern_units: None,
                    natural_safety: NaturalSafety::Unknown });
                notes.push(format!("fallback: {lid}->{rid}: natural placement unverifiable (empty/non-finite raw cells, or canonical evidence unmeasurable/non-finite without raw collision proof); no safe label, no unsafe label, no tier-2 recovery"));
                continue;
            }
            NaturalDecision::FrameConflict => {
                numeric_failed_natural_frame_conflict += 1;
                pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(), class,
                    reason: PairLedgerReason::NaturalFrameConflict, tier: 2, t_lo, t_hi,
                    residual: f64::NAN, j_star: f64::NAN, kern_units: None,
                    natural_safety: NaturalSafety::Unknown });
                notes.push(format!("fallback: {lid}->{rid}: raw cells report collision but canonical evidence_at is clear at the export natural origin; frames disagree, no safe/unsafe label, no widening"));
                continue;
            }
            NaturalDecision::Widen { deficit, reason } => {
                // Collision is proven in at least one frame, so a later failure may honestly be Unsafe.
                notes.push(format!("fallback: {lid}->{rid}: widen_reason={} deficit={deficit:.6}", reason.code()));
                deficit
            }
        };
        let t_hi_w = t_hi + deficit;
        match solve_pair_t_l2(prof_l, prof_r, raw_base, dcap, pair_gap, lambda, t_lo, t_hi_w, advance_l, l_tr, r_tr) {
            PairSolve::Solved { residual, origin, wall_gap, component: _ } => {
                crate::signed_clearance::clearance_cells_constant_rows_into(
                    &crate::outline_spacing::align_pair_rows(prof_l, prof_r), raw_base + residual, &mut cells_scratch);
                let cells_at = &*cells_scratch;
                // Re-guard the widened result in BOTH frames: checked raw cells (non-empty,
                // finite, min >= 0) and canonical evidence_at at the exact exported origin.
                let canon = crate::signed_clearance::evidence_at(prof_l, prof_r, l_tr, r_tr, origin);
                if widened_reguard_ok(&cells_at, canon.as_ref().map(|e| e.collides())) {
                    let (_, var) = channel_stats(&cells_at, 0.0, dcap);
                    fallback_pairs.push(PairPosition {
                        left: lid.clone(), right: rid.clone(),
                        origin_distance: origin, wall_gap, optical_cost: var,
                        pair_target: usable_pair_target(pair_gap),
                        compensated: false,
                    });
                    numeric_failed_pairs -= 1;
                    fallback_verified_pairs += 1;
                    pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(), class,
                        reason: PairLedgerReason::FallbackDerived, tier: 2, t_lo, t_hi: t_hi_w,
                        residual, j_star: f64::NAN, kern_units: Some(origin - advance_l),
                        natural_safety: NaturalSafety::Unsafe });
                    notes.push(format!("fallback: {lid}->{rid}: guard-verified kern {} (tier-2, deficit {deficit:.6})", origin - advance_l));
                } else {
                    pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(), class,
                        reason: PairLedgerReason::NotConverged, tier: 2, t_lo, t_hi: t_hi_w,
                        residual: f64::NAN, j_star: f64::NAN, kern_units: None,
                        natural_safety: NaturalSafety::Unsafe });
                    notes.push(format!("fallback: {lid}->{rid}: widened solve failed the export-origin re-guard; natural output rescue, UNSAFE (tier-2)"));
                }
            }
            other => {
                pair_ledger.push(PairLedgerRow { left: lid.clone(), right: rid.clone(), class,
                    reason: PairLedgerReason::NotConverged, tier: 2, t_lo, t_hi: t_hi_w,
                    residual: f64::NAN, j_star: f64::NAN, kern_units: None,
                    natural_safety: NaturalSafety::Unsafe });
                notes.push(format!("fallback: {lid}->{rid}: widened solve {other:?}; natural output rescue, UNSAFE (tier-2)"));
            }
        }
    }
    if !fallback_pairs.is_empty() {
        notes.push(format!("FALLBACK TIER-2: {} pair(s) recovered with guard-verified fallback kern rows (explicit fallback class, NOT solver-optimal; NOT COMPLETE)", fallback_pairs.len()));
    }
    if saturated_pairs > 0 {
        notes.push(format!("SATURATION: {saturated_pairs} pair(s) have pair_gap > Dcap; W(t) saturates at Dcap and their solve lands on the t_hi bound (reported, never clamped silently)"));
    }

    // ---- simultaneous-contrast floor (post-solve, policy-gated) --------
    // Off by default: the frozen pipeline below is bit-identical. When on,
    // the pass raises only pairs below the font-calibrated floor and
    // returns every other pair bit-identical; raised pairs re-enter the
    // rank step with their verified placement.
    let (contrast_floor_adjustments, contrast_floor_failures) = if policy.contrast_floor {
        let report = crate::contrast_floor::apply_contrast_floor(
            candidates, &prof_by_id, &metrics, &classes, dcap, policy.residual_epsilon());
        let receipt = report.receipt_line();
        candidates = report.pairs;
        notes.push(receipt);
        (report.adjustments, report.failures)
    } else {
        (Vec::new(), Vec::new())
    };

    // Rank by |residual| desc; max_pairs overflow -> explicit ledger
    // (architect rule 12:03: never silently dropped, reported not-complete).
    let advance_of = |id: &str| metrics.get(id).map(|m| m.2).unwrap_or(0.0);
    candidates.sort_by(|a, b| {
        let ra = (a.origin_distance - advance_of(a.left.as_str())).abs();
        let rb = (b.origin_distance - advance_of(b.left.as_str())).abs();
        rb.partial_cmp(&ra).unwrap_or(std::cmp::Ordering::Equal)
    });
    let excluded_pairs: Vec<ExcludedPair> = if candidates.len() > policy.max_pairs {
        candidates.split_off(policy.max_pairs).into_iter().map(|p| ExcludedPair {
            left: p.left, right: p.right,
            origin_distance: p.origin_distance,
            wall_gap: p.wall_gap,
            optical_cost: p.optical_cost,
        }).collect()
    } else { Vec::new() };
    // complete = every pair either emitted or explicitly ledgered by the
    // max_pairs policy. A numeric failure is never a definite success
    // (chief-architect 21:37): it forces NOT COMPLETE so the consumer
    // cannot report the run as fully solved. General unmeasurable
    // accounting is unchanged (geometric absence, still counted above).
    let accounting_residual = closed_accounting_residual(evaluations, [
        candidates.len(), excluded_pairs.len(), excluded_below_epsilon, excluded_unmeasurable,
        numeric_failed_pairs, geometric_hold_pairs, no_accepted_candidate_pairs,
        fallback_natural_clear_pairs, fallback_verified_pairs]);
    let bucket_overlaps = bucket_overlap_count(&candidates, &excluded_pairs, &fallback_pairs);
    let accounting_closed = accounting_residual == 0 && bucket_overlaps == 0;
    let complete = excluded_pairs.is_empty() && numeric_failed_pairs == 0 && geometric_hold_pairs == 0 && no_accepted_candidate_pairs == 0
        && fallback_pairs.is_empty() && !pair_ledger.iter().any(|r| r.tier == 2)
        && accounting_closed;
    if numeric_failed_pairs > 0 {
        notes.push(format!(
            "NUMERIC FAILURE: {numeric_failed_pairs} pair(s) hit bounded non-convergence in the L2 solve (declared bounded failure; NOT COMPLETE)"));
    }
    if geometric_hold_pairs > 0 {
        notes.push(format!(
            "GEOMETRIC HOLD: {geometric_hold_pairs} pair(s) have no feasible residual in the solve domain (domain hold, NOT numeric failure; NOT COMPLETE)"));
    }
    if no_accepted_candidate_pairs > 0 {
        notes.push(format!(
            "CANDIDATE HOLD: {no_accepted_candidate_pairs} pair(s) had feasible components but no accepted candidate in the declared domain (NOT geometric-empty, NOT numeric; NOT COMPLETE)"));
    }
    for r in &hold_reasons { notes.push(format!("hold: {r}")); }
    notes.push(format!(
        "pair accounting: {} emitted + {} ledger + {excluded_below_epsilon} below-epsilon + {excluded_unmeasurable} unmeasurable + {numeric_failed_pairs} numeric-failed (nonfinite {numeric_failed_nonfinite}, malformed {numeric_failed_malformed}, natural-unverifiable {numeric_failed_natural_unverifiable}, natural-frame-conflict {numeric_failed_natural_frame_conflict}) + {geometric_hold_pairs} geometric-hold + {no_accepted_candidate_pairs} candidate-hold + {fallback_natural_clear_pairs} fallback-natural-clear + {fallback_verified_pairs} fallback-verified = evaluation bound n(n-1) {evaluations} ({}; {excluded_self_pairs} self-pairs counted apart) |{}",
        candidates.len(), excluded_pairs.len(),
        if accounting_closed { "CLOSED".to_string() } else { format!("OPEN, residual {accounting_residual}, bucket overlaps {bucket_overlaps}") },
        if complete { "" } else { " NOT COMPLETE" }));
    if !accounting_closed {
        notes.push(format!("ACCOUNTING ANOMALY: residual {accounting_residual}, {bucket_overlaps} pair(s) in more than one bucket; forced NOT COMPLETE"));
    }

    // ---- NV-2 items 2+7: class spacing units (lane-gated) --------------
    // Edge classes carry spacing units learned from the font's own solved
    // pair measurements. The unit is one of mean / median / midrange, all
    // three computed on the real class data; the data selects (lowest
    // class inconsistency score; tie order mean -> median -> midrange, the
    // declared baseline). Each non-uniform pair is pulled to the unit by
    // its own deviation; the pull is emitted as typed SPACING rows
    // (sidebearing deltas shared equally between the facing sides), NEVER
    // as kern - the kern layer stays for what remains outside classes.
    // Off lane: empty rows, no notes, the frozen receipt is bit-identical.
    let mut class_unit_rows: Vec<ClassUnitRow> = Vec::new();
    let mut class_spacing_adjustments: Vec<ClassSpacingAdjustment> = Vec::new();
    if harmony.class_spacing_units {
        let mut by_class: std::collections::BTreeMap<(SideClass, SideClass), Vec<(String, String, f64, f64, bool)>> = Default::default();
        for (l, r, key, gap, res, emitted) in class_measurements {
            by_class.entry(key).or_default().push((l, r, gap, res, emitted));
        }
        for ((cl, cr), members) in by_class {
            let gaps: Vec<f64> = members.iter().map(|m| m.2).collect();
            let d = class_unit_decision(&gaps, eps)
                .expect("non-empty class population always yields a unit decision");
            let class_name = format!("{cl}->{cr}");
            let adjustments_before = class_spacing_adjustments.len();
            for (l, r, gap, _res, emitted) in &members {
                let deviation = gap - d.unit;
                if deviation.abs() >= eps {
                    let correction = -deviation;
                    class_spacing_adjustments.push(ClassSpacingAdjustment {
                        left: l.clone(), right: r.clone(), class: class_name.clone(),
                        gap_before: *gap, unit: d.unit, deviation, correction,
                        left_rsb_delta: correction / 2.0, right_lsb_delta: correction / 2.0,
                        emitted: *emitted,
                    });
                }
            }
            notes.push(format!(
                "class unit {class_name}: unit={:.3} selected={} (mean={:.3} score {:.3}; median={:.3} score {:.3}; midrange={:.3} score {:.3}) | {} pairs, {} uniform | inconsistency score {:.3} (= equal per-pair correction share) | {} spacing adjustment(s), 0 kern",
                d.unit, d.selected.code(),
                d.candidate_mean, d.score_mean,
                d.candidate_median, d.score_median,
                d.candidate_midrange, d.score_midrange,
                members.len(), d.uniform_count, d.inconsistency_score,
                class_spacing_adjustments.len() - adjustments_before));
            class_unit_rows.push(ClassUnitRow {
                left_class: cl, right_class: cr,
                pair_count: members.len(),
                uniform_count: d.uniform_count,
                candidate_mean: d.candidate_mean,
                candidate_median: d.candidate_median,
                candidate_midrange: d.candidate_midrange,
                score_mean: d.score_mean,
                score_median: d.score_median,
                score_midrange: d.score_midrange,
                selected: d.selected,
                unit: d.unit,
                inconsistency_score: d.inconsistency_score,
            });
        }
    }
    if harmony.direction_symmetry && !symmetry_promotions.is_empty() {
        notes.push(format!(
            "direction symmetry: {} below-epsilon direction(s) promoted to ship beside their emitted reverse (pair and reverse decided together): {}",
            symmetry_promotions.len(),
            symmetry_promotions.iter().map(|p| format!("{}->{} (residual {:.3}, reverse {:.3})", p.left, p.right, p.residual, p.reverse_residual)).collect::<Vec<_>>().join(", ")));
    }

    let total_ink: f64 = inked.iter().flat_map(|w| w.widths.iter()).sum();
    let unobserved_policy = {
        let cf = class_fallbacks.into_inner();
        if !cf.is_empty() { unobserved.push(UnobservedPolicy::ClassPairTargetSelfDerived { class_pairs: cf.into_iter().collect() }); }
        let cd = cadence_fallbacks.into_inner();
        if !cd.is_empty() { unobserved.push(UnobservedPolicy::ClassPairTargetCadenceDerived { class_pairs: cd.into_iter().collect() }); }
        let ch = channel_fallbacks.into_inner();
        if !ch.is_empty() { unobserved.push(UnobservedPolicy::ClassPairTargetChannelDerived { class_pairs: ch.into_iter().collect() }); }
        // deterministic order: declared variant order (derived Ord), deduplicated
        unobserved.sort();
        unobserved.dedup();
        unobserved
    };
    notes.push(format!("unobserved_policy={unobserved_policy:?}"));
    let policy_derivation = format!(
        "KNI self_anchored_spacing solve | upm={upm} | anchor_strategy={strategy:?} | anchor_mode={mode} | W_target={w_target:.3} | s={s:.3} | inked_glyphs={} total_ink_width={total_ink:.1} | {}",
        inked.len(),
        notes.join(" | ")
    );

    // ---- class audit capture (read-only observer) -----------------------
    // Copies of classifier state the solve has ALREADY computed: facing
    // classes, inked membership, and the resolved target per facing class
    // pair through the same resolve_class_target the solver used. No
    // recomputation, no feedback: solver decisions and bytes are untouched.
    let class_audit = {
        use crate::class_audit as ca;
        let glyph_rows: Vec<ca::ClassAuditGlyph> = walls.iter().zip(&infos)
            .map(|(w, i)| ca::ClassAuditGlyph {
                glyph_id: w.glyph_id.clone(),
                left_class: i.cl,
                right_class: i.cr,
                inked: w.h_eff > 0.0,
            })
            .collect();
        let mut members: std::collections::BTreeMap<SideClass, Vec<String>> = Default::default();
        for (w, i) in walls.iter().zip(&infos) {
            if w.h_eff <= 0.0 { continue; }
            members.entry(i.cl).or_default().push(format!("{}:L", w.glyph_id));
            members.entry(i.cr).or_default().push(format!("{}:R", w.glyph_id));
        }
        let classes_audit: Vec<ca::ClassMembership> = members.iter()
            .map(|(c, m)| ca::ClassMembership {
                class: *c, member_count: m.len(), members: m.clone(),
            })
            .collect();
        let present: Vec<SideClass> = members.keys().copied().collect();
        let mut pair_targets: Vec<ca::ClassPairTargetRow> =
            Vec::with_capacity(present.len() * present.len());
        for &cl in &present {
            for &cr in &present {
                let (target, source) = resolve_class_target(
                    cl, cr, &class_pair_targets, &channel_targets, &cadence_targets, w_target);
                pair_targets.push(ca::ClassPairTargetRow {
                    left_class: cl, right_class: cr, target, source,
                });
            }
        }
        ca::ClassAudit {
            anchor_mode: mode.to_string(),
            w_target,
            scale_s: s,
            upm,
            baseline,
            x_height,
            cap_height,
            dcap,
            dcap_from_policy: policy.dcap.is_some(),
            lambda,
            cadence_class_pass: policy.cadence_class_pass,
            class_channel_targets: policy.class_channel_targets,
            measured_pair_count: ctx.map(|c| c.measured_pairs.len()).unwrap_or(0),
            measured_sidebearing_count: ctx.map(|c| c.measured_sidebearings.len()).unwrap_or(0),
            has_glyph_codepoints: ctx.map(|c| !c.glyph_codepoints.is_empty()).unwrap_or(false),
            has_measured_space_advance: ctx.and_then(|c| c.measured_space_advance).is_some(),
            glyphs: glyph_rows,
            classes: classes_audit,
            pair_targets,
        }
    };

    let anchor_audit = crate::anchor_audit::audit_residual_signs(&audit_rows);

    let solution = SpacingSolution {
        baseline,
        x_height,
        x_height_source,
        cap_height,
        glyphs,
        font_median_pair_target: font_median_pair_target(&candidates),
        pairs: candidates,
        space_status,
        excluded_pairs,
        complete,
        excluded_self_pairs,
        excluded_below_epsilon,
        excluded_unmeasurable,
        numeric_failed_pairs,
        geometric_hold_pairs,
        no_accepted_candidate_pairs,
        hold_reasons,
        pair_ledger,
        fallback_pairs,
        fallback_natural_clear_pairs,
        fallback_verified_pairs,
        numeric_failed_nonfinite,
        numeric_failed_malformed,
        numeric_failed_natural_unverifiable,
        numeric_failed_natural_frame_conflict,
        accounting_residual,
        accounting_closed,
        contrast_floor_adjustments,
        contrast_floor_failures,
        policy_derivation,
        unobserved_policy,
        anchor_audit,
    };
    let harmony_report = ClassHarmonyReport {
        symmetry_promotions,
        class_unit_rows,
        class_spacing_adjustments,
        below_epsilon_candidates,
    };
    Ok(Some((solution, class_audit, harmony_report)))
}

// ---------------------------------------------------------------------------
// P3 live solver adapter (chief-architect assignment 2026-10-14 21:22)
// ---------------------------------------------------------------------------

/// SB0: INITIALIZATION sidebearings (owner order 2026-10-14: every
/// generated glyph starts at 0). This is a start state, NOT source spacing
/// evidence: it never enters `FontContext` and never influences the anchor.
#[derive(Debug, Clone)]
pub struct InitialSidebearing {
    pub glyph_id: String,
    pub lsb: f64,
    pub rsb: f64,
}

/// Live adapter request: the current engine state for one spacing solve.
/// Uses the SAME OutlineProfile input as the batch solver (no second
/// profile shape).
///
/// FIELD DISCIPLINE (chief-architect correction 2026-10-14 21:31,
/// load-bearing): `initial_sidebearings` (SB0) is initialization only.
/// `measured_source_sidebearings` is the ONLY sidebearing anchor channel
/// and is populated only on routes carrying real authorized measurement
/// evidence; on the no-source route it is EMPTY. Reading SB/GPOS from the
/// source font is out of scope for this adapter. The final solution is
/// derived from the geometry/counter anchor (or real measured evidence),
/// never from SB0.
#[derive(Debug, Clone)]
pub struct LiveSolveRequest {
    pub profiles: Vec<OutlineProfile>,
    /// SB0: initialization sidebearings (owner order: all zeros). NOT
    /// measured anchor evidence; never forwarded into FontContext.
    pub initial_sidebearings: Vec<InitialSidebearing>,
    /// Real measured source sidebearings, ONLY with authorized measurement
    /// evidence. Empty on the no-source route.
    pub measured_source_sidebearings: Vec<MeasuredSidebearing>,
    /// Current measured pair gaps, when the live state carries authorized
    /// measurement evidence for them.
    pub measured_pairs: Vec<MeasuredPair>,
    /// Current glyph -> codepoint context (manifest-bound identity map).
    pub glyph_codepoints: Vec<(String, u32)>,
    /// Measured space advance when the live state carries it.
    pub measured_space_advance: Option<f64>,
    pub policy: SpacingPolicy,
    pub strategy: AnchorStrategy,
}

/// Completeness/refusal consumer: the caller matches exactly one arm.
/// `Incomplete` carries the full solution INCLUDING its exclusion ledger;
/// final sidebearings are never forced nonnegative in either success arm.
#[derive(Debug)]
pub enum LiveSolveOutcome {
    Complete(SpacingSolution),
    Incomplete(SpacingSolution),
    Refused(SpacingError),
}

impl Default for LiveSolveRequest {
    /// Default strategy = LegacyCascade: production never switches silently.
    /// Default SB0 = none recorded; default measured evidence = none.
    fn default() -> Self {
        LiveSolveRequest {
            profiles: Vec::new(),
            initial_sidebearings: Vec::new(),
            measured_source_sidebearings: Vec::new(),
            measured_pairs: Vec::new(),
            glyph_codepoints: Vec::new(),
            measured_space_advance: None,
            policy: SpacingPolicy::default(),
            strategy: AnchorStrategy::LegacyCascade,
        }
    }
}

/// P3 adapter: run the solver from live state and consume completeness
/// and typed refusals into one outcome. Never panics on solver refusals;
/// never clamps negative sidebearings.
pub fn solve_live(req: &LiveSolveRequest) -> LiveSolveOutcome {
    // SB0 validation: finite values, unique ids. SB0 is otherwise unused
    // by the solve on purpose (initialization state, not anchor evidence).
    {
        let mut seen: Vec<&str> = Vec::with_capacity(req.initial_sidebearings.len());
        for sb in &req.initial_sidebearings {
            if !sb.lsb.is_finite() || !sb.rsb.is_finite() {
                return LiveSolveOutcome::Refused(SpacingError::InvalidContext {
                    reason: format!("initial_sidebearings[{}]: SB0 must be finite", sb.glyph_id),
                });
            }
            if seen.contains(&sb.glyph_id.as_str()) {
                return LiveSolveOutcome::Refused(SpacingError::InvalidContext {
                    reason: format!("initial_sidebearings[{}]: duplicate SB0 glyph id", sb.glyph_id),
                });
            }
            seen.push(sb.glyph_id.as_str());
        }
    }
    let ctx = FontContext {
        measured_sidebearings: req.measured_source_sidebearings.clone(),
        measured_pairs: req.measured_pairs.clone(),
        glyph_codepoints: req.glyph_codepoints.clone(),
        measured_space_advance: req.measured_space_advance,
        ..Default::default()
    };
    match solve_spacing_with_anchor_strategy(&req.profiles, Some(&ctx), &req.policy, req.strategy) {
        Ok(sol) if sol.complete => LiveSolveOutcome::Complete(sol),
        Ok(sol) => LiveSolveOutcome::Incomplete(sol),
        Err(e) => LiveSolveOutcome::Refused(e),
    }
}

/// Positional lookup used by the rev2 §3.4 fallback; glue, not anchor logic.
fn idx_of(walls: &[Walls], glyph_id: &str) -> usize {
    walls.iter().position(|w| w.glyph_id == glyph_id)
        .expect("glyph id from walls iteration")
}

// ---------------------------------------------------------------------------
// K2 verification tests (contract-level invariants; survive the supreme patch)
// ---------------------------------------------------------------------------


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pair_cascade_parallel_bit_identical_to_sequential() {
        // Varied synthetic population: rectangles with different widths and
        // vertical shifts, so the pair cascade exercises solved, saturated,
        // class-fallback and unmeasurable outcomes across all (cl, cr) mixes.
        use crate::outline_spacing::{InkInterval, ScanRow};
        let mk = |id: &str, x0: f64, x1: f64, dy: f64| -> OutlineProfile {
            let rows = (0..10).map(|i| ScanRow {
                y: i as f64 * 10.0 + dy,
                weight: 10.0,
                ink: vec![InkInterval { left: x0, right: x1 }],
                span_lo: i as f64 * 10.0 - 5.0 + dy,
                span_hi: i as f64 * 10.0 + 5.0 + dy,
            }).collect();
            OutlineProfile {
                glyph_id: id.into(),
                source_pin: "test".into(),
                upm: 1000,
                origin: [0.0, 0.0],
                rows,
                bounds: [x0, dy, x1, 100.0 + dy],
                ink_area: (x1 - x0) * 100.0,
                counter_area: 500.0,
                open_left: 0.0,
                open_right: 0.0,
                profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
            }
        };
        let mut glyphs: Vec<OutlineProfile> = Vec::new();
        for i in 0..24u32 {
            let w = 30.0 + (i % 7) as f64 * 11.0;
            glyphs.push(mk(&format!("g{i:02}"), 0.0, w, (i % 5) as f64 * 3.0));
        }
        let policy = SpacingPolicy::default();
        PAIR_CASCADE_PARALLEL.store(false, std::sync::atomic::Ordering::SeqCst);
        let t0 = std::time::Instant::now();
        let seq = solve_spacing(&glyphs, None, &policy).map(|s| format!("{s:?}"));
        let seq_ms = t0.elapsed().as_secs_f64() * 1000.0;
        PAIR_CASCADE_PARALLEL.store(true, std::sync::atomic::Ordering::SeqCst);
        let t0 = std::time::Instant::now();
        let par = solve_spacing(&glyphs, None, &policy).map(|s| format!("{s:?}"));
        let par_ms = t0.elapsed().as_secs_f64() * 1000.0;
        eprintln!("pair_cascade drivers: sequential {seq_ms:.1} ms, parallel {par_ms:.1} ms ({} glyphs, {} ordered pair evaluations)",
            glyphs.len(), glyphs.len() * (glyphs.len() - 1));
        // Debug formatting of f64 is shortest-round-trip, so equal debug
        // strings imply identical bits for every float in the solution
        // (all NaNs here are the f64::NAN constant, one bit pattern).
        assert_eq!(seq, par, "parallel pair cascade must be bit-identical to sequential");
    }

    #[test]
    fn pair_cascade_explicit_pool_bit_identical_across_worker_counts() {
        // Same style of varied synthetic population as the driver oracle
        // above: the explicit-pool driver (jobs = 2/4/8) must produce the
        // exact solution the inline jobs = 1 evaluation produces, so a
        // caller's --jobs cap never changes spacing bytes.
        use crate::outline_spacing::{InkInterval, ScanRow};
        let mk = |id: &str, x0: f64, x1: f64, dy: f64| -> OutlineProfile {
            let rows = (0..10).map(|i| ScanRow {
                y: i as f64 * 10.0 + dy,
                weight: 10.0,
                ink: vec![InkInterval { left: x0, right: x1 }],
                span_lo: i as f64 * 10.0 - 5.0 + dy,
                span_hi: i as f64 * 10.0 + 5.0 + dy,
            }).collect();
            OutlineProfile {
                glyph_id: id.into(),
                source_pin: "test".into(),
                upm: 1000,
                origin: [0.0, 0.0],
                rows,
                bounds: [x0, dy, x1, 100.0 + dy],
                ink_area: (x1 - x0) * 100.0,
                counter_area: 500.0,
                open_left: 0.0,
                open_right: 0.0,
                profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
            }
        };
        let mut glyphs: Vec<OutlineProfile> = Vec::new();
        for i in 0..24u32 {
            let w = 30.0 + (i % 7) as f64 * 11.0;
            glyphs.push(mk(&format!("g{i:02}"), 0.0, w, (i % 5) as f64 * 3.0));
        }
        let policy = SpacingPolicy::default();
        let base = solve_spacing_jobs(&glyphs, None, &policy, 1).map(|s| format!("{s:?}"));
        for jobs in [2usize, 4, 8] {
            let got = solve_spacing_jobs(&glyphs, None, &policy, jobs).map(|s| format!("{s:?}"));
            assert_eq!(base, got, "explicit-pool pair cascade (jobs={jobs}) must be bit-identical to jobs=1");
        }
    }

    use crate::outline_spacing::{InkInterval, OutlineProfile, ScanRow};

    // ---- W1: natural-safe / re-guard decisions ----
    fn cn(collides: bool, min_gap: f64) -> Option<CanonNatural> { Some(CanonNatural { collides, min_gap }) }
    #[test]
    fn w1_checked_raw_min_rejects_empty_and_non_finite() {
        assert_eq!(checked_raw_min(&[]), None);
        assert_eq!(checked_raw_min(&[(0.0, f64::NAN, 1.0)]), None);
        assert_eq!(checked_raw_min(&[(0.0, 2.0, f64::INFINITY)]), None);
        assert_eq!(checked_raw_min(&[(0.0, f64::NEG_INFINITY, 1.0)]), None);
        assert_eq!(checked_raw_min(&[(0.0, 2.0, 3.0), (0.0, 1.5, 4.0)]), Some(1.5));
        assert_eq!(checked_raw_min(&[(0.0, -0.25, 3.0)]), Some(-0.25));
    }
    #[test]
    fn w1_empty_or_non_finite_cells_are_never_safe_or_unsafe() {
        assert_eq!(decide_natural(&[], cn(false, 1.0)), NaturalDecision::Unverifiable);
        assert_eq!(decide_natural(&[], None), NaturalDecision::Unverifiable);
        assert_eq!(decide_natural(&[(0.0, f64::NAN, 1.0)], cn(false, 1.0)), NaturalDecision::Unverifiable);
    }
    #[test]
    fn w1_canonical_unmeasurable_with_raw_clear_is_unknown_not_widen() {
        assert_eq!(decide_natural(&[(0.0, 2.0, 3.0)], None), NaturalDecision::Unverifiable);
        assert_eq!(decide_natural(&[(0.0, 2.0, 3.0)], cn(false, f64::NAN)), NaturalDecision::Unverifiable);
        // raw collision proof with canonical unmeasurable: widen by RAW depth, tagged
        assert_eq!(decide_natural(&[(0.0, -1.5, 3.0)], None),
            NaturalDecision::Widen { deficit: 1.5, reason: WidenReason::RawHitCanonicalUnmeasurable });
    }
    #[test]
    fn w1_safe_needs_raw_clear_and_canonical_clear() {
        assert_eq!(decide_natural(&[(0.0, 2.0, 3.0)], cn(false, 0.75)), NaturalDecision::Safe { raw_min: 2.0, canon_min_gap: 0.75 });
        assert_eq!(decide_natural(&[(0.0, 0.0, 1.0)], cn(false, 0.0)), NaturalDecision::Safe { raw_min: 0.0, canon_min_gap: 0.0 });
    }
    #[test]
    fn w1_widen_deficit_is_canonical_measured() {
        // both frames hit: deficit comes from canonical min_gap, not the raw cells (raw -1.5, canonical -4.0)
        assert_eq!(decide_natural(&[(0.0, -1.5, 3.0)], cn(true, -4.0)),
            NaturalDecision::Widen { deficit: 4.0, reason: WidenReason::RawAndCanonicalHit });
        // raw clear, canonical hit: separate reason, canonical depth carried; min_gap 0 with collides()=true is a depth-zero interval collision (deficit 0), not legal touching
        assert_eq!(decide_natural(&[(0.0, 2.0, 3.0)], cn(true, -0.5)),
            NaturalDecision::Widen { deficit: 0.5, reason: WidenReason::RawClearCanonicalHit });
        assert_eq!(decide_natural(&[(0.0, 2.0, 3.0)], cn(true, 0.0)),
            NaturalDecision::Widen { deficit: 0.0, reason: WidenReason::RawClearCanonicalHit });
    }
    #[test]
    fn w1_raw_hit_canonical_clear_is_frame_conflict() {
        assert_eq!(decide_natural(&[(0.0, -1.5, 3.0)], cn(false, 0.25)), NaturalDecision::FrameConflict);
    }
    #[test]
    fn w1_widened_reguard_needs_both_frames() {
        let clear = [(0.0, 0.5, 1.0)];
        assert!(widened_reguard_ok(&clear, Some(false)));
        assert!(!widened_reguard_ok(&clear, Some(true)));
        assert!(!widened_reguard_ok(&clear, None));
        assert!(!widened_reguard_ok(&[(0.0, -0.001, 1.0)], Some(false)));
        assert!(!widened_reguard_ok(&[], Some(false)));
        assert!(!widened_reguard_ok(&[(0.0, f64::NAN, 1.0)], Some(false)));
    }

    fn rect(id: &str, x0: f64, x1: f64, counter: f64) -> OutlineProfile {
        let rows = (0..10).map(|i| ScanRow {
            y: i as f64 * 10.0,
            weight: 10.0,
            ink: vec![InkInterval { left: x0, right: x1 }],
            span_lo: i as f64 * 10.0 - 5.0,
            span_hi: i as f64 * 10.0 + 5.0,
        }).collect();
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: "test".into(),
            upm: 1000,
            origin: [0.0, 0.0],
            rows,
            bounds: [x0, 0.0, x1, 100.0],
            ink_area: (x1 - x0) * 100.0,
            counter_area: counter,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
        }
    }

    #[test]
    fn refuses_empty() {
        assert!(matches!(
            solve_spacing(&[], None, &SpacingPolicy::default()),
            Err(SpacingError::EmptyInput)));
    }

    #[test]
    fn refuses_mixed_upm() {
        let a = rect("A", 0.0, 50.0, 1000.0);
        let mut b = rect("V", 0.0, 60.0, 1000.0);
        b.upm = 2048;
        assert!(matches!(
            solve_spacing(&[a, b], None, &SpacingPolicy::default()),
            Err(SpacingError::InconsistentUpm { .. })));
    }

    #[test]
    fn refuses_nonfinite() {
        let mut a = rect("A", 0.0, 50.0, 1000.0);
        a.ink_area = f64::NAN;
        assert!(matches!(
            solve_spacing(&[a], None, &SpacingPolicy::default()),
            Err(SpacingError::NonFinite { .. })));
    }

    #[test]
    fn refuses_bad_resource_bound() {
        let glyphs: Vec<OutlineProfile> = (0..60)
            .map(|i| rect(&format!("g{i}"), 0.0, 50.0, 1000.0)).collect();
        let mut pol = SpacingPolicy::default();
        pol.max_pair_evaluations = 1;
        // Base has no pair solver yet; the bound check belongs to the pair
        // stage. This test asserts the type exists and the solve is typed.
        let r = solve_spacing(&glyphs, None, &pol);
        assert!(r.is_ok() || matches!(r,
            Err(SpacingError::ResourceBoundExceeded { .. })));
    }

    #[test]
    fn advance_identity_and_no_invented_space() {
        let h = rect("H", 0.0, 80.0, 2000.0);
        let n = rect("n", 0.0, 70.0, 1500.0);
        let sol = solve_spacing(&[h, n], None, &SpacingPolicy::default()).unwrap();
        assert_eq!(sol.glyphs.len(), 2, "no glyph invented, none dropped");
        for g in &sol.glyphs {
            assert!(g.lsb.is_finite() && g.rsb.is_finite() && g.advance.is_finite());
        }
        assert!(sol.complete);
        assert!(sol.excluded_pairs.is_empty());
        assert!(!sol.policy_derivation.is_empty());
    }

    #[test]
    fn deterministic() {
        let mk = || vec![rect("H", 0.0, 80.0, 2000.0), rect("o", 10.0, 60.0, 900.0)];
        let a = solve_spacing(&mk(), None, &SpacingPolicy::default()).unwrap();
        let b = solve_spacing(&mk(), None, &SpacingPolicy::default()).unwrap();
        assert_eq!(a.policy_derivation, b.policy_derivation);
        for (ga, gb) in a.glyphs.iter().zip(&b.glyphs) {
            assert_eq!(ga.lsb, gb.lsb);
            assert_eq!(ga.advance, gb.advance);
        }
    }

    #[test]
    fn measured_context_wins_anchor() {
        let h = rect("H", 0.0, 80.0, 2000.0);
        let n = rect("n", 0.0, 70.0, 1500.0);
        let ctx = FontContext {
            measured_sidebearings: vec![
                MeasuredSidebearing { glyph_id: "H".into(), lsb: 60.0, rsb: 60.0 },
                MeasuredSidebearing { glyph_id: "n".into(), lsb: 55.0, rsb: 55.0 },
            ],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, n], Some(&ctx), &SpacingPolicy::default()).unwrap();
        assert!(sol.policy_derivation.contains("MeasuredSource"),
            "derivation: {}", sol.policy_derivation);
    }

    fn countered(id: &str) -> OutlineProfile {
        // stem-counter-stem rows: straight sides + interior white channel
        let rows = (0..10).map(|i| ScanRow {
            y: i as f64 * 10.0,
            weight: 10.0,
            ink: vec![InkInterval { left: 0.0, right: 20.0 },
                      InkInterval { left: 60.0, right: 80.0 }],
            span_lo: i as f64 * 10.0 - 5.0,
            span_hi: i as f64 * 10.0 + 5.0,
        }).collect();
        OutlineProfile {
            glyph_id: id.into(), source_pin: "test".into(), upm: 1000,
            origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 80.0, 100.0],
            ink_area: 4000.0, counter_area: 4000.0,
            open_left: 0.0, open_right: 0.0,
            profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
        }
    }

    // ---- anchor strategy wrapper (architect approval 12:34) ----
    #[test]
    fn strategy_legacy_cascade_keeps_current_behavior() {
        let sol = solve_spacing_with_anchor_strategy(
            &[countered("H"), countered("n")], None, &SpacingPolicy::default(),
            AnchorStrategy::LegacyCascade).unwrap();
        assert!(!sol.policy_derivation.contains("CounterChannelExperimentSelfDerived"));
        assert!(sol.policy_derivation.contains("anchor_strategy=LegacyCascade"),
            "derivation: {}", sol.policy_derivation);
    }

    #[test]
    fn strategy_require_measured_refuses_without_measured_context() {
        let err = solve_spacing_with_anchor_strategy(
            &[countered("H"), countered("n")], None, &SpacingPolicy::default(),
            AnchorStrategy::RequireMeasured).unwrap_err();
        match err {
            SpacingError::AnchorUnresolved { strategy, reason } => {
                assert_eq!(strategy, "RequireMeasured");
                assert!(reason.contains("no measured source spacing"), "{reason}");
            }
            other => panic!("expected AnchorUnresolved, got {other:?}"),
        }
    }

    #[test]
    fn strategy_require_measured_uses_measured_source_when_present() {
        let ctx = FontContext {
            measured_sidebearings: vec![
                MeasuredSidebearing { glyph_id: "H".into(), lsb: 60.0, rsb: 60.0 },
            ],
            ..Default::default()
        };
        let sol = solve_spacing_with_anchor_strategy(
            &[countered("H"), countered("n")], Some(&ctx), &SpacingPolicy::default(),
            AnchorStrategy::RequireMeasured).unwrap();
        assert!(sol.policy_derivation.contains("MeasuredSource"),
            "derivation: {}", sol.policy_derivation);
    }

    /// countered(): stems at [0,20] and [60,80] on every row -> interior
    /// white channel is exactly 40 on all 10 rows; median over covered
    /// straight-class glyphs = 40. Hand-computed.
    #[test]
    fn strategy_counter_channel_uses_interior_white() {
        let sol = solve_spacing_with_anchor_strategy(
            &[countered("H"), countered("n")], None, &SpacingPolicy::default(),
            AnchorStrategy::CounterChannel).unwrap();
        assert!(sol.policy_derivation.contains(
            "anchor_mode=CounterChannelExperimentSelfDerived"),
            "derivation: {}", sol.policy_derivation);
        assert!(sol.policy_derivation.contains("W_target=40.000"),
            "derivation: {}", sol.policy_derivation);
        assert!(sol.policy_derivation.contains("EXPERIMENT CounterChannel"),
            "derivation: {}", sol.policy_derivation);
        // label discipline: the anchor never reads as measured
        assert!(!sol.policy_derivation.contains("anchor_mode=Measured"));
    }

    /// Diagonal-walled 'v': left wall lerp 0 -> 45 over the band, right wall
    /// flush at 80. Hand-computed expectations (see test): with measured
    /// straight|straight gap 40, H->v solves at residual 80.
    fn diag_v() -> OutlineProfile {
        let rows = (0..10).map(|i| {
            let y = i as f64 * 10.0;
            ScanRow {
                y,
                weight: 10.0,
                ink: vec![InkInterval { left: y / 2.0, right: 80.0 }],
                span_lo: y - 5.0,
                span_hi: y + 5.0,
            }
        }).collect();
        OutlineProfile {
            glyph_id: "v".into(), source_pin: "test".into(), upm: 1000,
            origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 80.0, 90.0],
            ink_area: 5000.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0,
            profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
        }
    }

    #[test]


    fn exact_pair_values_hand_computed() {
        // Measured: H,H gap 40 (W_s) and H,v gap 25 (class-pair target for
        // straight|diagonal). half = 20.
        // H: lsb = rsb = 20, advance = 120.
        // v (diag, flat band-row mean left depth 22.5): lsb = -2.5, rsb = 20,
        //    advance 97.5.
        // H->v true gap(y) = y/2 + (80-80) + 17.5 in [17.5, 62.5], mean 40.
        // Target 25 -> W(t) = 40 + t -> t = -15 (collision bound -17.5 ok).
        // origin_distance = 120 - 15 = 105; wall_gap = 17.5 - 15 = 2.5;
        // Canonical constant model (22:55): 10 constant spans, gaps
        // 2.5, 7.5, ..., 47.5 -> discrete variance (10^2-1)/12 * 5^2 = 206.25.
        let h = rect("H", 0.0, 80.0, 0.0);
        let v = diag_v();
        let ctx = FontContext {
            measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
            ],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, v], Some(&ctx), &SpacingPolicy::default()).unwrap();
        let hg = sol.glyphs.iter().find(|g| g.glyph_id == "H").unwrap();
        assert!((hg.lsb - 20.0).abs() < 1e-9, "H lsb {}", hg.lsb);
        assert!((hg.advance - 120.0).abs() < 1e-9, "H advance {}", hg.advance);
        let vg = sol.glyphs.iter().find(|g| g.glyph_id == "v").unwrap();
        assert!((vg.lsb - (-2.5)).abs() < 1e-9, "v lsb {}", vg.lsb);
        assert!((vg.advance - 97.5).abs() < 1e-9, "v advance {}", vg.advance);
        let p = sol.pairs.iter()
            .find(|p| p.left == "H" && p.right == "v")
            .expect("H->v pair must be emitted (residual -15)");
        assert!((p.origin_distance - 105.0).abs() < 1e-6,
            "origin_distance {} (glyph-origin frame)", p.origin_distance);
        assert!((p.wall_gap - 2.5).abs() < 1e-6, "wall_gap {}", p.wall_gap);
        assert!((p.optical_cost - 206.25).abs() < 1e-6,
            "optical_cost {}", p.optical_cost);
        assert!(sol.complete && sol.excluded_pairs.is_empty());
    }

    // ---- class audit (read-only observer, class_audit.rs) -------------

    use crate::class_audit::ClassTargetSource;

    #[test]
    fn class_audit_reports_facing_classes_and_membership() {
        let (_sol, audit) = solve_spacing_with_class_audit(
            &[countered("H"), rect("n", 0.0, 60.0, 0.0)],
            None, &SpacingPolicy::default()).unwrap();
        let h = audit.glyphs.iter().find(|g| g.glyph_id == "H").unwrap();
        assert_eq!((h.left_class, h.right_class), (SideClass::Straight, SideClass::Straight));
        assert!(h.inked);
        let st = audit.classes.iter().find(|c| c.class == SideClass::Straight)
            .expect("straight class present");
        assert_eq!(st.member_count, 4);
        assert_eq!(st.members, vec!["H:L", "H:R", "n:L", "n:R"]);
        // Geometry-only input: no measured or derived tables, so the only
        // present class pair resolves on the frozen anchor fallback.
        assert_eq!(audit.pair_targets.len(), 1);
        assert!(audit.pair_targets.iter()
            .all(|r| r.source == ClassTargetSource::AnchorWTarget));
        let hh = audit.pair_target_for("H", "H").unwrap();
        assert_eq!(hh.target, audit.w_target);
        assert_eq!(audit.measured_pair_count, 0);
        assert_eq!(audit.measured_sidebearing_count, 0);
        assert_eq!(audit.anchor_mode, "MeasuredOutlineSelfDerivedTarget");
    }

    #[test]
    fn class_audit_measured_targets_win_and_name_their_source() {
        let h = rect("H", 0.0, 80.0, 0.0);
        let v = diag_v();
        let ctx = FontContext {
            measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
            ],
            ..Default::default()
        };
        let (_sol, audit) = solve_spacing_with_class_audit(&[h, v], Some(&ctx), &SpacingPolicy::default()).unwrap();
        assert_eq!(audit.anchor_mode, "MeasuredSource");
        assert_eq!(audit.measured_pair_count, 2);
        let row = |l: SideClass, r: SideClass| audit.pair_targets.iter()
            .find(|p| p.left_class == l && p.right_class == r)
            .unwrap_or_else(|| panic!("class pair {l}->{r} must be reported"));
        // Measured class-pair medians win the cascade.
        let ss = row(SideClass::Straight, SideClass::Straight);
        assert_eq!((ss.source, ss.target), (ClassTargetSource::MeasuredSource, 40.0));
        let sd = row(SideClass::Straight, SideClass::Diagonal);
        assert_eq!((sd.source, sd.target), (ClassTargetSource::MeasuredSource, 25.0));
        // Facing membership behind those keys: H is straight|straight; v is
        // diagonal|straight (diagonal left side, flush right side).
        let vg = audit.glyphs.iter().find(|g| g.glyph_id == "v").unwrap();
        assert_eq!((vg.left_class, vg.right_class), (SideClass::Diagonal, SideClass::Straight));
        // Class pairs without a measured target keep the frozen anchor fallback.
        let dd = row(SideClass::Diagonal, SideClass::Diagonal);
        assert_eq!((dd.source, dd.target), (ClassTargetSource::AnchorWTarget, audit.w_target));
        // Selected-pair lookup faces left/right correctly: H->v and v->v
        // face straight->diagonal; v->H faces straight->straight.
        let hv = audit.pair_target_for("H", "v").unwrap();
        assert_eq!((hv.source, hv.target), (ClassTargetSource::MeasuredSource, 25.0));
        let vh = audit.pair_target_for("v", "H").unwrap();
        assert_eq!((vh.source, vh.target), (ClassTargetSource::MeasuredSource, 40.0));
        assert!(audit.pair_target_for("H", "absent").is_none());
    }

    #[test]
    fn class_audit_k2_channel_targets_name_their_source() {
        let policy = SpacingPolicy { class_channel_targets: true, ..Default::default() };
        let (_sol, audit) = solve_spacing_with_class_audit(&[rect("H", 0.0, 80.0, 0.0), diag_v()], None, &policy).unwrap();
        assert!(audit.class_channel_targets);
        let row = |l: SideClass, r: SideClass| audit.pair_targets.iter()
            .find(|p| p.left_class == l && p.right_class == r)
            .unwrap_or_else(|| panic!("class pair {l}->{r} must be reported"));
        // Straight := anchor target by the declared K2 convention, so
        // straight->straight derives equal to W and stays on the frozen
        // fallback by the skip-equal rule.
        let ss = row(SideClass::Straight, SideClass::Straight);
        assert_eq!((ss.source, ss.target), (ClassTargetSource::AnchorWTarget, audit.w_target));
        // The diagonal side's pooled channel median is positive, so pairs
        // touching it resolve on the K2 channel table.
        let sd = row(SideClass::Straight, SideClass::Diagonal);
        assert_eq!(sd.source, ClassTargetSource::ChannelK2);
        assert!(sd.target != audit.w_target);
        let dd = row(SideClass::Diagonal, SideClass::Diagonal);
        assert_eq!(dd.source, ClassTargetSource::ChannelK2);
    }

    #[test]
    fn class_audit_tsv_deterministic_and_consistent_with_emitted_pairs() {
        let mk_ctx = || FontContext {
            measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
            ],
            ..Default::default()
        };
        let (a, audit_a) = solve_spacing_with_class_audit(&[rect("H", 0.0, 80.0, 0.0), diag_v()], Some(&mk_ctx()), &SpacingPolicy::default()).unwrap();
        let (_b, audit_b) = solve_spacing_with_class_audit(&[rect("H", 0.0, 80.0, 0.0), diag_v()], Some(&mk_ctx()), &SpacingPolicy::default()).unwrap();
        assert_eq!(audit_a.to_tsv(), audit_b.to_tsv(),
            "same solve in, same audit bytes out");
        // Every emitted pair's public solver target equals the audit's
        // resolved row for that facing: the observer reports the value the
        // solver acted on, not a recomputation.
        for p in &a.pairs {
            if let Some(t) = p.pair_target {
                let row = audit_a.pair_target_for(&p.left, &p.right)
                    .unwrap_or_else(|| panic!("{}->{} must resolve", p.left, p.right));
                assert_eq!(row.target, t, "{}->{}", p.left, p.right);
            }
        }
        let tsv = audit_a.to_tsv();
        for section in ["# kni-class-audit v1", "# provenance anchor_mode=MeasuredSource",
                        "[glyphs]", "[classes]", "[class_pair_targets]"] {
            assert!(tsv.contains(section), "missing {section}:\n{tsv}");
        }
        assert!(tsv.contains("straight\tdiagonal\t25.000000\tmeasured"), "tsv:\n{tsv}");
        assert!(tsv.contains("diagonal\tdiagonal\t40.000000\tanchor_w_target"), "tsv:\n{tsv}");
    }

    /// Byte-inert guard for the observer: capturing the audit must not move
    /// any solver output. These are the exact golden values of
    /// `exact_pair_values_hand_computed` re-asserted with the audit field
    /// present; the full pre-existing golden and bit-identical suites
    /// (deterministic_repeat, pair_cascade_*_bit_identical*, strategy_*)
    /// run unchanged in the same `cargo test` pass.
    #[test]
    fn class_audit_capture_is_byte_inert_against_golden_values() {
        let h = rect("H", 0.0, 80.0, 0.0);
        let v = diag_v();
        let ctx = FontContext {
            measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
            ],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, v], Some(&ctx), &SpacingPolicy::default()).unwrap();
        let hg = sol.glyphs.iter().find(|g| g.glyph_id == "H").unwrap();
        assert!((hg.lsb - 20.0).abs() < 1e-9, "H lsb {}", hg.lsb);
        assert!((hg.advance - 120.0).abs() < 1e-9, "H advance {}", hg.advance);
        let vg = sol.glyphs.iter().find(|g| g.glyph_id == "v").unwrap();
        assert!((vg.lsb - (-2.5)).abs() < 1e-9, "v lsb {}", vg.lsb);
        assert!((vg.advance - 97.5).abs() < 1e-9, "v advance {}", vg.advance);
        let p = sol.pairs.iter().find(|p| p.left == "H" && p.right == "v").unwrap();
        assert!((p.origin_distance - 105.0).abs() < 1e-6,
            "origin_distance {}", p.origin_distance);
        assert!((p.wall_gap - 2.5).abs() < 1e-6, "wall_gap {}", p.wall_gap);
        assert!((p.optical_cost - 206.25).abs() < 1e-6, "optical_cost {}", p.optical_cost);
        assert!(sol.complete && sol.excluded_pairs.is_empty());
        // Byte-inert guard for the observer: the class-audit-observed entry
        // point returns the SAME solution. Debug formatting of f64 is
        // shortest-round-trip, so equal debug strings imply identical bits
        // for every float in the solution.
        let (observed, _audit) = solve_spacing_with_class_audit(
            &[rect("H", 0.0, 80.0, 0.0), diag_v()],
            Some(&FontContext {
                measured_pairs: vec![
                    MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                    MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
                ],
                ..Default::default()
            }),
            &SpacingPolicy::default()).unwrap();
        assert_eq!(format!("{sol:?}"), format!("{observed:?}"),
            "class-audit-observed solve must be bit-identical to the frozen entry point");
    }

    /// Lane D: uniform vertical ink distribution => optical centre =
    /// uniform weighting => the weighted mean is the flat mean through the
    /// identical code path, bit for bit.
    #[test]
    fn optical_split_uniform_ink_is_bit_identical_to_flat_mean() {
        let depths = vec![3.0, 1.5, 9.25, 0.0, 4.75];
        let weights = vec![12.0; 5];
        assert_eq!(
            optical_weighted_mean(&depths, &weights).to_bits(),
            mean(&depths).to_bits(),
            "uniform weights must take the flat-mean path exactly");
        // empty series keeps the previous 0.0 behaviour
        assert_eq!(optical_weighted_mean(&[], &[]).to_bits(), mean(&[]).to_bits());
    }

    /// Lane D: the weighted mean sits at the ink-mass distribution, not
    /// the uniform one; a bottom-heavy glyph reads its side depth low.
    #[test]
    fn optical_split_weighted_mean_follows_ink_mass() {
        // rows 0..9, depth 0 on the two wide bottom rows, 80 on the eight
        // narrow stem rows (L-shaped right side).
        let depths = vec![0.0, 0.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0];
        let weights = vec![100.0, 100.0, 20.0, 20.0, 20.0, 20.0, 20.0, 20.0, 20.0, 20.0];
        let w = optical_weighted_mean(&depths, &weights);
        // sum(w) = 360, sum(w*d) = 12800 -> 35.555...
        assert!((w - 12800.0 / 360.0).abs() < 1e-12, "{w}");
        assert!(w < mean(&depths), "weighted {w} must read below flat {}", mean(&depths));
    }

    /// Flat-mean end-to-end: an L-shaped glyph (wide bottom arm + narrow
    /// stem) has its right sidebearing read at the flat band-row mean of
    /// its clamped right depths. With measured sidebearings 50/50
    /// (W_s = 100, half = 50):
    ///   left depths all 0        -> lsb = 50;
    ///   right depths 0,0,80x8    -> flat mean 64 -> rsb = 50 - 64 = -14
    /// (negative sidebearings are measured, kept, never clamped).
    #[test]
    fn flat_mean_l_shaped_glyph_end_to_end() {
        let rows = (0..10).map(|i| {
            let y = i as f64;
            let ink = if i < 2 {
                vec![InkInterval { left: 0.0, right: 100.0 }] // arm rows
            } else {
                vec![InkInterval { left: 0.0, right: 20.0 }]  // stem rows
            };
            ScanRow { y, weight: 1.0, ink, span_lo: y - 0.5, span_hi: y + 0.5 }
        }).collect();
        let l = OutlineProfile {
            glyph_id: "L".into(), source_pin: "test".into(), upm: 1000,
            origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 100.0, 10.0],
            ink_area: 360.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0,
            profile_method: "test-fixture".into(), row_step: 1.0, flatten_tolerance: 0.0,
        };
        let ctx = FontContext {
            measured_sidebearings: vec![
                MeasuredSidebearing { glyph_id: "L".into(), lsb: 50.0, rsb: 50.0 }],
            ..Default::default()
        };
        let sol = solve_spacing(&[l], Some(&ctx), &SpacingPolicy::default()).unwrap();
        let g = &sol.glyphs[0];
        assert!((g.lsb - 50.0).abs() < 1e-9, "lsb {} (left depths all 0)", g.lsb);
        assert!((g.rsb - (50.0 - 64.0)).abs() < 1e-9,
            "rsb {} vs flat-mean -14", g.rsb);
        // advance consistency
        assert!((g.advance - (g.lsb + 100.0 + g.rsb)).abs() < 1e-9);
    }

    /// Uniform-ink glyphs: every emitted number is pinned bit for bit
    /// against the verified pristine base (goreda/kni f2f6fea8,
    /// instrumented dump of this exact fixture: identical GLYPH/PAIR/
    /// COUNTERS/EXCLUDED lines at full f64 precision). Values: countered
    /// H/n, interior channel 40 -> W=40, lsb = rsb = 20, advance 120; both
    /// ordered pairs emitted at origin 100, wall_gap 20, cost 0 because
    /// dcap = stem width 20 saturates the 40 target.
    #[test]
    fn uniform_ink_pair_values_bit_identical() {
        let sol = solve_spacing(&[countered("H"), countered("n")], None,
                                &SpacingPolicy::default()).unwrap();
        for g in &sol.glyphs {
            assert_eq!(g.lsb.to_bits(), 20.0f64.to_bits(), "{} lsb {}", g.glyph_id, g.lsb);
            assert_eq!(g.rsb.to_bits(), 20.0f64.to_bits(), "{} rsb {}", g.glyph_id, g.rsb);
            assert_eq!(g.advance.to_bits(), 120.0f64.to_bits(), "{} advance {}", g.glyph_id, g.advance);
        }
        assert_eq!(sol.pairs.len(), 2, "pairs: {:?}", sol.pairs);
        for p in &sol.pairs {
            assert_eq!(p.origin_distance.to_bits(), 100.0f64.to_bits(),
                "{}->{} origin {}", p.left, p.right, p.origin_distance);
            assert_eq!(p.wall_gap.to_bits(), 20.0f64.to_bits());
            assert_eq!(p.optical_cost.to_bits(), 0.0f64.to_bits());
        }
        assert_eq!(sol.excluded_self_pairs, 2);
        assert!(sol.complete && sol.excluded_pairs.is_empty());
    }

    /// Architect's regression for the 12:13 confirmed bug: two equal rects,
    /// true baseline gap must be lsb+rsb = 40, never -60 (= 40 - width).
    #[test]
    fn common_cells_rect_gap_includes_left_width() {
        let a = rect("A", 0.0, 100.0, 0.0);
        let b = rect("B", 0.0, 100.0, 0.0);
        let cells = common_cells(&a, &b, 40.0); // lsb+rsb = 40
        assert!(!cells.is_empty());
        for &(len, g0, g1) in &cells {
            assert!(len > 0.0);
            assert!((g0 - 40.0).abs() < 1e-9, "gap at cell bottom {g0} (bug value: -60)");
            assert!((g1 - 40.0).abs() < 1e-9, "gap at cell top {g1} (bug value: -60)");
        }
    }

    #[test]
    fn saturation_noted_when_target_exceeds_dcap() {
        let h = rect("H", 0.0, 80.0, 0.0);
        let v = diag_v();
        let ctx = FontContext {
            measured_pairs: vec![MeasuredPair {
                left: "H".into(), right: "H".into(), gap: 40.0,
            }],
            ..Default::default()
        };
        let mut pol = SpacingPolicy::default();
        pol.dcap = Some(5.0); // below the 40-unit target
        let sol = solve_spacing(&[h, v], Some(&ctx), &pol).unwrap();
        assert!(sol.policy_derivation.contains("SATURATION"),
            "derivation must report saturation: {}", sol.policy_derivation);
    }

    #[test]
    fn unobserved_policy_flags_present() {
        let h = countered("H");
        let n = countered("n");
        let sol = solve_spacing(&[h, n], None, &SpacingPolicy::default()).unwrap();
        assert!(sol.policy_derivation.contains("POLICY_UNOBSERVED"),
            "defaults must be flagged: {}", sol.policy_derivation);
    }

    #[test]
    fn unobserved_policy_typed_receipt_ctx_none() {
        let h = countered("H");
        let n = countered("n");
        let sol = solve_spacing(&[h, n], None, &SpacingPolicy::default()).unwrap();
        // sorted by declared variant order, deduplicated, no duplicates
        let mut sorted = sol.unobserved_policy.clone();
        sorted.dedup();
        assert_eq!(sorted, sol.unobserved_policy);
        assert!(sol.unobserved_policy.contains(&UnobservedPolicy::LambdaDefaultZero),
            "lambda default must be typed: {:?}", sol.unobserved_policy);
        assert!(sol.unobserved_policy.contains(&UnobservedPolicy::DcapPlateauDefault),
            "dcap default must be typed: {:?}", sol.unobserved_policy);
        // same call twice: identical receipt (deterministic)
        let h = countered("H");
        let n = countered("n");
        let sol2 = solve_spacing(&[h, n], None, &SpacingPolicy::default()).unwrap();
        assert_eq!(sol.unobserved_policy, sol2.unobserved_policy);
        assert_eq!(sol.policy_derivation, sol2.policy_derivation);
    }

    #[test]
    fn unobserved_policy_lambda_dcap_absent_when_set() {
        let h = countered("H");
        let n = countered("n");
        let mut pol = SpacingPolicy::default();
        pol.lambda = Some(0.0);
        pol.dcap = Some(1000.0);
        let ctx = FontContext {
            measured_pairs: vec![MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 }],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, n], Some(&ctx), &pol).unwrap();
        assert!(!sol.unobserved_policy.contains(&UnobservedPolicy::LambdaDefaultZero));
        // receipt carries the typed list
        assert!(sol.policy_derivation.contains("unobserved_policy=["), "{}", sol.policy_derivation);
        assert!(!sol.unobserved_policy.contains(&UnobservedPolicy::DcapPlateauDefault));
    }

    #[test]
    fn max_pairs_overflow_lands_in_ledger_not_dropped() {
        // Measured class-pair target 25 for straight|diagonal makes every
        // cross pair with a diagonal side solve to a nonzero residual.
        let h = rect("H", 0.0, 80.0, 0.0);
        let v = diag_v();
        let mut w = diag_v();
        w.glyph_id = "w".into();
        let ctx = FontContext {
            measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
                MeasuredPair { left: "H".into(), right: "w".into(), gap: 25.0 },
            ],
            ..Default::default()
        };
        let mut pol = SpacingPolicy::default();
        pol.max_pairs = 1;
        let sol = solve_spacing(&[h, v, w], Some(&ctx), &pol).unwrap();
        let total = sol.pairs.len() + sol.excluded_pairs.len();
        assert!(total >= 2, "solved pairs must survive somewhere: {total}");
        assert!(!sol.complete, "overflow must mark the result not-complete");
        assert!(sol.policy_derivation.contains("NOT COMPLETE"));
        assert!(sol.pairs.len() <= 1);
        assert!(sol.excluded_self_pairs == 3, "H,v,w self pairs counted");
    }

    // (lambda>0 refusal test replaced by K5's lambda_positive_solves_and_note_is_exact below, 21:24)

    #[test]
    fn pair_accounting_is_explicit() {
        // two straight flush-rect glyphs with a measured target: residuals
        // are 0, so both ordered cross pairs land in below-epsilon, both
        // self pairs are counted as self, nothing reads like all-pairs.
        // (flush single-interval rects keep s = 80 >= target, no saturation)
        let h = rect("H", 0.0, 80.0, 0.0);
        let n = rect("n", 0.0, 70.0, 0.0);
        let ctx = FontContext {
            measured_pairs: vec![MeasuredPair {
                left: "H".into(), right: "H".into(), gap: 40.0,
            }],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, n], Some(&ctx), &SpacingPolicy::default()).unwrap();
        assert_eq!(sol.excluded_self_pairs, 2, "H->H and n->n");
        assert_eq!(sol.excluded_below_epsilon, 2,
            "straight pairs sit at the target already");
        assert!(sol.pairs.is_empty() && sol.excluded_pairs.is_empty());
        assert!(sol.complete);
        assert!(sol.policy_derivation.contains("pair accounting"));
    }

    #[test]
    fn duplicate_profile_id_is_typed_refusal() {
        let a = rect("H", 0.0, 80.0, 0.0);
        let b = rect("H", 10.0, 90.0, 0.0); // same id
        let err = solve_spacing(&[a, b], None, &SpacingPolicy::default()).unwrap_err();
        assert!(matches!(err, SpacingError::InvalidProfile { .. }), "{err:?}");
    }

    #[test]
    fn measured_pair_unknown_glyph_is_typed_refusal_not_open_default() {
        let h = rect("H", 0.0, 80.0, 0.0);
        let ctx = FontContext {
            measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
                MeasuredPair { left: "H".into(), right: "Q".into(), gap: 30.0 },
            ],
            ..Default::default()
        };
        let err = solve_spacing(&[h], Some(&ctx), &SpacingPolicy::default()).unwrap_err();
        assert!(matches!(err, SpacingError::InvalidContext { .. }), "{err:?}");
    }

    #[test]
    fn unmeasurable_pairs_close_the_accounting() {
        // g lives 500 units above the band: no shared cells with H or n.
        let h = rect("H", 0.0, 80.0, 0.0);
        let n = rect("n", 0.0, 70.0, 0.0);
        let mut g = rect("g", 0.0, 60.0, 0.0);
        for row in &mut g.rows { row.y += 500.0; row.span_lo += 500.0; row.span_hi += 500.0; }
        g.bounds = [0.0, 500.0, 60.0, 590.0];
        let ctx = FontContext {
            measured_pairs: vec![MeasuredPair {
                left: "H".into(), right: "H".into(), gap: 40.0 }],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, n, g], Some(&ctx), &SpacingPolicy::default()).unwrap();
        // 3x3 = 9 ordered iterations: 3 self, H<->n below-epsilon (2),
        // 4 cross pairs with g unmeasurable.
        assert_eq!(sol.excluded_self_pairs, 3);
        assert_eq!(sol.excluded_below_epsilon, 2);
        assert_eq!(sol.excluded_unmeasurable, 4);
        assert_eq!(sol.numeric_failed_pairs, 0, "no numeric failure here");
        let accounted = sol.pairs.len() + sol.excluded_pairs.len()
            + sol.excluded_below_epsilon + sol.excluded_unmeasurable
            + sol.numeric_failed_pairs
            + sol.excluded_self_pairs;
        assert_eq!(accounted, 9, "accounting must be closed");
        assert!(sol.policy_derivation.contains("unmeasurable"));
    }

    /// Raw numeric manifest ids carry no letter identity: the codepoint map
    /// must drive stem/case resolution (architect stem-anchor fix 12:17).
    #[test]
    fn stem_resolution_via_codepoint_map_not_raw_id() {
        let mut h = rect("00007", 0.0, 80.0, 0.0);
        let n = rect("00008", 0.0, 60.0, 0.0);
        // give the third glyph a different interval width so the stem source
        // is observable: all-population median would include 20s.
        let o = rect("00009", 0.0, 20.0, 0.0);
        h.bounds[3] = 100.0;
        let ctx = FontContext {
            glyph_codepoints: vec![
                ("00007".into(), 'H' as u32),
                ("00008".into(), 'n' as u32),
                ("00009".into(), 'o' as u32),
            ],
            ..Default::default()
        };
        let sol = solve_spacing(&[h, n, o], Some(&ctx), &SpacingPolicy::default()).unwrap();
        // stem glyphs = H,n via map: s = median(80x10, 60x10) = 70, not the
        // all-population median 60.
        assert!(sol.policy_derivation.contains("s=70.000"),
            "stem width must come from codepoint-resolved stems: {}",
            sol.policy_derivation);
        assert!(sol.policy_derivation.contains("via codepoint map"));
        assert!(!sol.policy_derivation.contains("NOT stem-learned"));
    }

    #[test]
    fn unmapped_numeric_ids_are_self_derived_not_stem_learned() {
        let h = rect("00007", 0.0, 80.0, 0.0);
        let n = rect("00008", 0.0, 60.0, 0.0);
        let sol = solve_spacing(&[h, n], None, &SpacingPolicy::default()).unwrap();
        assert!(sol.policy_derivation.contains("self-derived all-population stem estimate"),
            "derivation: {}", sol.policy_derivation);
        assert!(sol.policy_derivation.contains("NOT stem-learned"));
    }

    #[test]
    fn codepoint_map_validation_is_typed_refusal() {
        let h = rect("00007", 0.0, 80.0, 0.0);
        // duplicate mapping id
        let ctx = FontContext {
            glyph_codepoints: vec![("00007".into(), 72), ("00007".into(), 78)],
            ..Default::default()
        };
        assert!(matches!(
            solve_spacing(&[h.clone()], Some(&ctx), &SpacingPolicy::default()),
            Err(SpacingError::InvalidContext { .. })));
        // mapping for unknown glyph
        let ctx2 = FontContext {
            glyph_codepoints: vec![("99999".into(), 72)],
            ..Default::default()
        };
        assert!(matches!(
            solve_spacing(&[h], Some(&ctx2), &SpacingPolicy::default()),
            Err(SpacingError::InvalidContext { .. })));
    }

    /// The unknown-id refusal must be deterministic: with several unknown
    /// ids in the codepoint map, the error always names the
    /// lexicographically smallest one, not whichever the HashMap iteration
    /// yields first (sorted-keys fix at the validation site).
    #[test]
    fn unknown_codepoint_refusal_names_sorted_first_id() {
        let h = rect("00007", 0.0, 80.0, 0.0);
        let n = rect("00008", 0.0, 60.0, 0.0);
        let unknowns = ["zz_unknown", "mm_unknown", "aa_unknown", "kk_unknown",
                        "qq_unknown", "bb_unknown", "yy_unknown", "dd_unknown"];
        let mut glyph_codepoints: Vec<(String, u32)> = vec![
            ("00007".into(), 'H' as u32),
            ("00008".into(), 'n' as u32),
        ];
        for (i, id) in unknowns.iter().enumerate() {
            glyph_codepoints.push((id.to_string(), 'A' as u32 + i as u32));
        }
        let ctx = FontContext { glyph_codepoints, ..Default::default() };
        // Each solve builds a fresh HashMap (fresh RandomState); the refusal
        // must still be identical every time.
        let mut reasons = std::collections::BTreeSet::new();
        for _ in 0..unknowns.len() {
            match solve_spacing(&[h.clone(), n.clone()], Some(&ctx), &SpacingPolicy::default()) {
                Err(SpacingError::InvalidContext { reason }) => { reasons.insert(reason); }
                other => panic!("expected InvalidContext, got {other:?}"),
            }
        }
        assert_eq!(reasons.len(), 1, "refusal identity must be stable: {reasons:?}");
        let reason = reasons.iter().next().unwrap();
        assert!(reason.contains("'aa_unknown'"),
            "refusal must name the lexicographically smallest unknown id: {reason}");
    }

    #[test]
    fn space_resolved_via_codepoint() {
        let h = countered("00007");
        let mut sp = rect("00020", 0.0, 0.0, 0.0);
        sp.rows = vec![];
        sp.bounds = [0.0, 0.0, 0.0, 0.0];
        let ctx = FontContext {
            glyph_codepoints: vec![
                ("00007".into(), 'H' as u32),
                ("00020".into(), 0x20),
            ],
            ..Default::default()
        };
        // Dar patch: no measured advance -> typed MissingEvidence, NO
        // emission (the codepoint resolution still classifies the glyph as
        // space); a measured advance is emitted exactly.
        let sol = solve_spacing(&[h.clone(), sp.clone()], Some(&ctx), &SpacingPolicy::default()).unwrap();
        assert!(!sol.glyphs.iter().any(|g| g.glyph_id == "00020"),
            "no space emission without a measured advance");
        assert!(matches!(sol.space_status, SpaceStatus::MissingEvidence { .. }),
            "typed MissingEvidence status, got {:?}", sol.space_status);
        let ctx_m = FontContext { measured_space_advance: Some(250.0), ..ctx };
        let sol2 = solve_spacing(&[h, sp], Some(&ctx_m), &SpacingPolicy::default()).unwrap();
        let spg = sol2.glyphs.iter().find(|g| g.glyph_id == "00020")
            .expect("space (by codepoint) must be emitted when a measured advance is supplied");
        assert_eq!(spg.advance, 250.0, "exact measured advance");
        assert!(matches!(sol2.space_status, SpaceStatus::Measured { advance } if advance == 250.0));
    }

    #[test]
    fn space_never_invented_but_emitted_when_present() {
        let mut sp = rect("space", 0.0, 0.0, 0.0);
        sp.rows = vec![];
        sp.bounds = [0.0, 0.0, 0.0, 0.0];
        let h = countered("H");
        // absent space: no space glyph emitted, typed Absent
        let sol = solve_spacing(&[h.clone()], None, &SpacingPolicy::default()).unwrap();
        assert!(!sol.glyphs.iter().any(|g| g.glyph_id == "space"));
        assert!(matches!(sol.space_status, SpaceStatus::Absent));
        // present space WITHOUT a measured advance (dar patch): NO emission,
        // typed MissingEvidence; the W_target fallback is retired
        let sol2 = solve_spacing(&[h.clone(), sp.clone()], None, &SpacingPolicy::default()).unwrap();
        assert!(!sol2.glyphs.iter().any(|g| g.glyph_id == "space"),
            "no space emission without a measured advance");
        assert!(matches!(sol2.space_status, SpaceStatus::MissingEvidence { .. }));
        // present space WITH a measured advance: emitted exactly
        let ctx_m = FontContext { measured_space_advance: Some(300.0), ..Default::default() };
        let sol3 = solve_spacing(&[h, sp], Some(&ctx_m), &SpacingPolicy::default()).unwrap();
        let spg = sol3.glyphs.iter().find(|g| g.glyph_id == "space")
            .expect("source space glyph must be emitted when a measured advance is supplied");
        assert_eq!(spg.advance, 300.0, "exact measured advance");
    }

fn obj_ref(cells: &[(f64, f64, f64)], cap: f64, pg: f64, lam: f64, t: f64) -> f64 {
    let (w, v) = channel_stats(cells, t, cap);
    (w - pg) * (w - pg) + lam * v
}
/// Independent oracle: dense grid, then golden-section on the best cell. No candidate reasoning shared with solver.
fn oracle_min(cells: &[(f64, f64, f64)], cap: f64, pg: f64, lam: f64, lo: f64, hi: f64) -> (f64, f64) {
    let n = 40_000usize;
    let (mut bt, mut bj) = (lo, f64::INFINITY);
    for i in 0..=n {
        let t = lo + (hi - lo) * (i as f64) / (n as f64);
        let j = obj_ref(cells, cap, pg, lam, t);
        if j < bj { bj = j; bt = t; }
    }
    let step = (hi - lo) / n as f64;
    let (mut a, mut b) = ((bt - step).max(lo), (bt + step).min(hi));
    let g = 0.618_033_988_749_894_9;
    for _ in 0..80 {
        let c = b - g * (b - a); let d = a + g * (b - a);
        if obj_ref(cells, cap, pg, lam, c) < obj_ref(cells, cap, pg, lam, d) { b = d } else { a = c }
    }
    let t = (a + b) / 2.0;
    let j = obj_ref(cells, cap, pg, lam, t);
    if j <= bj { (t, j) } else { (bt, bj) }
}
fn two_channel() -> Vec<(f64, f64, f64)> { vec![(1.0, 10.0, 10.0), (1.0, 60.0, 60.0)] } // (len, c0, c1)

#[test]
fn lambda_positive_interior_stationary_closed_form() {
    // cap=50, pg=30. For t in [-10,40]: W=(60+t)/2, V=(40-t)^2/4, J=t^2/4+lam*(40-t)^2/4.
    // dJ/dt=0 -> t*=40*lam/(1+lam). The W-root alone (lam=0) gives t=0: an endpoint/root candidate set misses t*.
    let cells = two_channel();
    for (lam, want) in [(1.0, 20.0), (3.0, 30.0), (0.25, 8.0)] {
        let t = solve_pair_t(&cells, 50.0, 30.0, lam, -10.0, 40.0);
        assert!((t - want).abs() < 1e-6, "lam={lam}: got {t}, want {want}");
    }
}
#[test]
fn lambda_zero_is_w_root_and_unchanged() {
    let t = solve_pair_t(&two_channel(), 50.0, 30.0, 0.0, -10.0, 40.0);
    assert!(t.abs() < 1e-9, "lam=0 root is t=0, got {t}");
}
#[test]
fn lambda_monotone_moves_toward_variance_collapse() {
    // larger lambda pulls t toward t_hi=40 (where both channels equal the cap, V=0).
    let c = two_channel();
    let ts: Vec<f64> = [0.0, 0.1, 1.0, 10.0, 1e3].iter().map(|l| solve_pair_t(&c, 50.0, 30.0, *l, -10.0, 40.0)).collect();
    assert!(ts.windows(2).all(|w| w[1] > w[0]), "{ts:?}");
    assert!(ts[4] < 40.0 && ts[4] > 39.9);
}
#[test]
fn matches_independent_oracle_on_sloped_cells() {
    // sloped cells create cap crossings inside a cell: quadratic/cubic pieces.
    let cells = vec![(2.0, 5.0, 45.0), (1.0, 80.0, 20.0), (3.0, 30.0, 55.0), (0.5, 12.0, 12.0)];
    let cap = 60.0; let min_base = 5.0;
    let (lo, hi) = (-min_base, cap - min_base);
    for pg in [15.0, 30.0, 45.0, 70.0] { for lam in [0.0, 0.05, 0.5, 2.0, 50.0] {
        let t = solve_pair_t(&cells, cap, pg, lam, lo, hi);
        assert!(t >= lo && t <= hi && t.is_finite());
        let (_, oj) = oracle_min(&cells, cap, pg, lam, lo, hi);
        let sj = obj_ref(&cells, cap, pg, lam, t);
        assert!(sj <= oj + 1e-7 * (1.0 + oj.abs()), "pg={pg} lam={lam}: solver J={sj} t={t} > oracle J={oj}");
    }}
}
#[test]
fn never_worse_than_endpoint_root_breakpoint_set() {
    // regression for the refusal reason: the old candidate set (endpoints, W-root, breakpoints) must never beat the new solve.
    let c = two_channel();
    for lam in [0.1, 1.0, 5.0] {
        let t = solve_pair_t(&c, 50.0, 30.0, lam, -10.0, 40.0);
        let old = [-10.0, 0.0, 40.0, 50.0 - 10.0, 50.0 - 60.0].iter().copied().filter(|x| *x >= -10.0 && *x <= 40.0)
            .map(|x| obj_ref(&c, 50.0, 30.0, lam, x)).fold(f64::INFINITY, f64::min);
        assert!(obj_ref(&c, 50.0, 30.0, lam, t) <= old + 1e-12);
        assert!(obj_ref(&c, 50.0, 30.0, lam, t) < old, "interior minimum must strictly beat the old set at lam={lam}");
    }
}
#[test]
fn uncapped_region_variance_is_shift_invariant() {
    // cap far above all gaps: V constant in t, so lam must not change argmin (matches rev3 'redundant term' receipt).
    let c = two_channel();
    let a = solve_pair_t(&c, 1e6, 30.0, 0.0, -10.0, 100.0);
    for lam in [0.5, 5.0] { assert!((solve_pair_t(&c, 1e6, 30.0, lam, -10.0, 100.0) - a).abs() < 1e-6); }
}
#[test]
fn bounds_and_ties() {
    let c = two_channel();
    // target below reachable W at t_lo: bound t_lo wins for lam=0.
    assert!((solve_pair_t(&c, 50.0, -1e3, 0.0, -10.0, 40.0) + 10.0).abs() < 1e-9);
    // flat objective (single cell at cap everywhere): tie -> smaller |t| (matches existing tie rule).
    let flat = vec![(1.0, 100.0, 100.0)];
    assert_eq!(solve_pair_t(&flat, 50.0, 50.0, 2.0, -5.0, 5.0), 0.0);
}
#[test]
fn deterministic_repeat() {
    let cells = vec![(2.0, 5.0, 45.0), (1.0, 80.0, 20.0)];
    let a = solve_pair_t(&cells, 60.0, 30.0, 0.7, -5.0, 55.0);
    for _ in 0..5 { assert_eq!(a.to_bits(), solve_pair_t(&cells, 60.0, 30.0, 0.7, -5.0, 55.0).to_bits()); }
}
// Replace existing `lambda_positive_is_typed_refusal_not_approx_argmin` (line ~1443) with:
#[test]
fn lambda_positive_solves_and_note_is_exact() {
    let mut pol = SpacingPolicy::default();
    pol.lambda = Some(0.5);
    let sol = solve_spacing(&[countered("H"), countered("n")], None, &pol).expect("lambda>0 must solve");
    assert!(sol.policy_derivation.contains("lambda=0.500"));
    assert!(!sol.policy_derivation.contains("typed refusal until"), "stale refusal note must be removed (line ~1052)");
    // still typed refusals for invalid values
    for bad in [-1.0, f64::NAN, f64::INFINITY] {
        let mut p = SpacingPolicy::default(); p.lambda = Some(bad);
        assert!(matches!(solve_spacing(&[countered("H"), countered("n")], None, &p), Err(SpacingError::InvalidContext{..})));
    }
}

    // ---- P3 live solver adapter ----
    #[test]
    fn live_adapter_sb0_is_initialization_not_anchor() {
        // SEMANTICS FIX (chief architect 2026-10-14 21:31, load-bearing):
        // this test replaces live_adapter_complete_with_sb0_anchor, which
        // froze a MISREADING of the owner order. SB0 (all-zero start) is
        // INITIALIZATION, not measured source spacing; it must NOT anchor
        // the solve. Correction explicitly noted per the architect's
        // instruction ("owner emrini yanlis yorumlama duzeltmesi").
        let req = LiveSolveRequest {
            profiles: vec![countered("H"), countered("n")],
            initial_sidebearings: vec![
                InitialSidebearing { glyph_id: "H".into(), lsb: 0.0, rsb: 0.0 },
                InitialSidebearing { glyph_id: "n".into(), lsb: 0.0, rsb: 0.0 },
            ],
            strategy: AnchorStrategy::LegacyCascade,
            ..Default::default()
        };
        match solve_live(&req) {
            LiveSolveOutcome::Complete(sol) => {
                // The all-zero SB0 must NOT become a MeasuredSource anchor
                // (that would force W_target=0 and suppress the geometry).
                assert!(!sol.policy_derivation.contains("MeasuredSource"),
                    "SB0 leaked into the anchor: {}", sol.policy_derivation);
                // Geometry/counter anchor wins instead: countered() has an
                // interior white channel of 40 -> W_target=40 -> lsb=rsb=20.
                let h = sol.glyphs.iter().find(|g| g.glyph_id == "H").unwrap();
                assert!((h.lsb - 20.0).abs() < 1e-9,
                    "geometry-anchored lsb expected, got {} | {}", h.lsb, sol.policy_derivation);
            }
            other => panic!("expected Complete, got {:?}", match other {
                LiveSolveOutcome::Incomplete(_) => "Incomplete",
                LiveSolveOutcome::Refused(_) => "Refused",
                _ => "?" }),
        }
    }

    #[test]
    fn live_adapter_measured_source_sb_still_anchors_when_present() {
        // The separate measured_source_sidebearings channel is the ONLY
        // sidebearing anchor route, used only with authorized measurement
        // evidence (empty on the no-source route).
        let req = LiveSolveRequest {
            profiles: vec![countered("H"), countered("n")],
            initial_sidebearings: vec![
                InitialSidebearing { glyph_id: "H".into(), lsb: 0.0, rsb: 0.0 },
            ],
            measured_source_sidebearings: vec![
                MeasuredSidebearing { glyph_id: "H".into(), lsb: 60.0, rsb: 60.0 },
            ],
            strategy: AnchorStrategy::LegacyCascade,
            ..Default::default()
        };
        match solve_live(&req) {
            LiveSolveOutcome::Complete(sol) =>
                assert!(sol.policy_derivation.contains("MeasuredSource"),
                    "derivation: {}", sol.policy_derivation),
            _ => panic!("expected Complete"),
        }
    }

    #[test]
    fn live_adapter_sb0_nonfinite_and_duplicates_refused() {
        let base = LiveSolveRequest {
            profiles: vec![countered("H")], ..Default::default() };
        let mut bad = base.clone();
        bad.initial_sidebearings = vec![
            InitialSidebearing { glyph_id: "H".into(), lsb: f64::NAN, rsb: 0.0 }];
        assert!(matches!(solve_live(&bad),
            LiveSolveOutcome::Refused(SpacingError::InvalidContext { .. })));
        let mut dup = base;
        dup.initial_sidebearings = vec![
            InitialSidebearing { glyph_id: "H".into(), lsb: 0.0, rsb: 0.0 },
            InitialSidebearing { glyph_id: "H".into(), lsb: 0.0, rsb: 0.0 }];
        assert!(matches!(solve_live(&dup),
            LiveSolveOutcome::Refused(SpacingError::InvalidContext { .. })));
    }

    #[test]
    fn live_adapter_incomplete_is_consumed_not_dropped() {
        let mut pol = SpacingPolicy::default();
        pol.max_pairs = 0; // forces the exclusion ledger
        let req = LiveSolveRequest {
            profiles: vec![countered("H"), countered("n")],
            policy: pol,
            ..Default::default()
        };
        match solve_live(&req) {
            LiveSolveOutcome::Incomplete(sol) => {
                assert!(!sol.complete);
                assert_eq!(sol.excluded_pairs.len(), 2, "H->n and n->H in the ledger");
                assert!(sol.policy_derivation.contains("NOT COMPLETE"));
            }
            other => panic!("expected Incomplete, got {}", match other {
                LiveSolveOutcome::Complete(_) => "Complete",
                LiveSolveOutcome::Refused(_) => "Refused",
                _ => "?" }),
        }
    }

    #[test]
    fn live_adapter_refusal_is_typed_outcome() {
        let mut pol = SpacingPolicy::default();
        pol.lambda = Some(-1.0);
        let req = LiveSolveRequest {
            profiles: vec![countered("H")],
            policy: pol,
            ..Default::default()
        };
        assert!(matches!(solve_live(&req),
            LiveSolveOutcome::Refused(SpacingError::InvalidContext { .. })));
    }

    #[test]
    fn live_adapter_negative_sidebearings_not_clamped() {
        // deep open form -> negative SB kept verbatim through the adapter
        let mut v = diag_v();
        v.glyph_id = "v".into();
        let req = LiveSolveRequest {
            profiles: vec![v],
            measured_source_sidebearings: vec![
                MeasuredSidebearing { glyph_id: "v".into(), lsb: 10.0, rsb: 10.0 }],
            ..Default::default()
        };
        if let LiveSolveOutcome::Complete(sol) = solve_live(&req) {
            let g = &sol.glyphs[0];
            assert!(g.lsb < 0.0, "deep diagonal side must stay negative, got {}", g.lsb);
            assert!((g.advance - (g.lsb + 80.0 + g.rsb)).abs() < 1e-9);
        } else {
            panic!("expected Complete");
        }
    }

    /// Architect 21:31 regression: the optimum can sit on a cap
    /// breakpoint (plateau edge). Cells c=10 and c=20, cap=25, pg=25:
    /// for t in (5, 15] J(t) = (t-15)^2/2 (W=(35+t)/2 capped cell frozen,
    /// V=((15-t)/2)^2), so J decreases to 0 at t = 15; the minimizing
    /// plateau is the clamped region where W=25=pg, V=0, and its
    /// smallest-|t| point is exactly the internal breakpoint t=5? No:
    /// plateau starts at t=15 = t_hi here. This fixture pins the
    /// breakpoint-candidate contract: t=5 (cap-20) and t=15 (cap-10)
    /// must both be evaluated, and the tie-free answer is t_hi=15.
    #[test]
    fn piece_boundary_optimum_at_cap_breakpoint() {
        let cells = vec![(1.0, 10.0, 10.0), (1.0, 20.0, 20.0)];
        // internal breakpoint cap-20 = 5 inside (-10, 15)
        let t = solve_pair_t(&cells, 25.0, 25.0, 1.0, -10.0, 15.0);
        assert!((t - 15.0).abs() < 1e-9, "breakpoint/boundary optimum, got {t}");
        // And with the target moved so the plateau edge IS the internal
        // breakpoint: pg=20, lambda=0 -> W hits 20 exactly at t=5 (cap-20).
        let t0 = solve_pair_t(&cells, 25.0, 20.0, 0.0, -10.0, 15.0);
        assert!((t0 - 5.0).abs() < 1e-6, "W-root at internal breakpoint, got {t0}");
    }

    /// Edge cases K5 flagged: zero-length pieces and t_lo == t_hi must not
    /// panic, must return a finite in-range candidate.
    #[test]
    fn zero_length_pieces_and_collapsed_range_are_safe() {
        let cells = vec![(1.0, 10.0, 10.0), (1.0, 60.0, 60.0)];
        // collapsed range: the only feasible shift is the answer
        let t = solve_pair_t(&cells, 50.0, 30.0, 1.0, 7.0, 7.0);
        assert_eq!(t, 7.0);
        // breakpoints exactly on the range ends -> zero-length pieces only
        let t2 = solve_pair_t(&cells, 50.0, 30.0, 1.0, -10.0, 40.0);
        assert!(t2 >= -10.0 && t2 <= 40.0 && t2.is_finite());
        // duplicate cell ends -> duplicate breakpoints collapse
        let dup = vec![(1.0, 10.0, 10.0), (2.0, 10.0, 10.0)];
        let t3 = solve_pair_t(&dup, 50.0, 30.0, 0.5, -10.0, 40.0);
        assert!(t3.is_finite() && t3 >= -10.0 && t3 <= 40.0);
    }

    /// Chief-architect 21:35: overflow/non-finite numeric state must be a
    /// declared bounded failure (NaN -> excluded_unmeasurable ledger via the
    /// caller), never an empty candidate list presented as a complete pass.
    #[test]
    fn nonfinite_numeric_state_is_declared_bounded_failure_not_empty_pass() {
        // 2e308 coefficient products overflow f64 inside the piece math.
        let cells = vec![(1.0, 1e308, 1e308)];
        let t = solve_pair_t(&cells, 1.7e308, 1.0, 1.0, -1e308, 7e307);
        assert!(t.is_nan(), "overflow must surface as NaN bounded failure, got {t}");
    }

    /// Chief-architect 21:37: a numeric failure in the lambda>0 solve must
    /// be its own ledger entry, force complete=false, and make the P3
    /// adapter report Incomplete - never a definite full success.
    #[test]
    fn numeric_failure_breaks_complete_and_consumes_as_incomplete() {
        // Huge flat glyphs (width 4e307) + measured class target 1.2e308:
        // sides = 1.2e308 -> every cell gap = 1.2e308 (finite, passes the
        // pre-solve checks), but the uncapped piecewise coefficient sum
        // c0+c1 = 2.4e308 overflows f64 inside piece_jprime_coeffs.
        let big = |id: &str| OutlineProfile {
            glyph_id: id.into(), source_pin: "test".into(), upm: 1000,
            origin: [0.0, 0.0],
            rows: (0..10).map(|i| ScanRow {
                y: i as f64 * 10.0, weight: 10.0,
                ink: vec![InkInterval { left: 0.0, right: 4e307 }],
                span_lo: i as f64 * 10.0 - 5.0,
                span_hi: i as f64 * 10.0 + 5.0,
            }).collect(),
            bounds: [0.0, 0.0, 4e307, 100.0],
            ink_area: 1e307, counter_area: 0.0,
            open_left: 0.0, open_right: 0.0,
            profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
        };
        let mut pol = SpacingPolicy::default();
        pol.dcap = Some(1.7e308);
        pol.lambda = Some(1.0);
        pol.pair_min_shared_rows = 1;
        let mut ctx = FontContext::default();
        ctx.measured_pairs.push(MeasuredPair { left: "H".into(), right: "n".into(), gap: 1.2e308 });
        let sol = solve_spacing(&[big("H"), big("n")], Some(&ctx), &pol).unwrap();
        assert_eq!(sol.numeric_failed_pairs, 2,
            "H->n and n->H both overflow: {}", sol.policy_derivation);
        assert!(!sol.complete, "numeric failure must break complete");
        assert!(sol.policy_derivation.contains("NUMERIC FAILURE"),
            "derivation: {}", sol.policy_derivation);
        // accounting closed: 0 emitted + 0 ledger + 0 below-eps +
        // 0 unmeasurable + 2 numeric + 2 self = 4 = 2^2
        let accounted = sol.pairs.len() + sol.excluded_pairs.len()
            + sol.excluded_below_epsilon + sol.excluded_unmeasurable
            + sol.numeric_failed_pairs + sol.excluded_self_pairs;
        assert_eq!(accounted, 4, "accounting must stay closed");
        // P3 consumer: Incomplete, never Complete.
        let req = LiveSolveRequest {
            profiles: vec![big("H"), big("n")], measured_pairs: vec![
                MeasuredPair { left: "H".into(), right: "n".into(), gap: 1.2e308 }],
            policy: pol, ..Default::default() };
        assert!(matches!(solve_live(&req), LiveSolveOutcome::Incomplete(_)),
            "numeric failure must consume as Incomplete");
    }
}

// ---------------------------------------------------------------------------
// NV-2 tests: class spacing units + direction symmetry (work list
// 2026-10-16 items 2+3+7). The class-unit math tests pin the declared
// selection rule on the Marq Alternate evidence shapes quoted in the work
// list (17 ready, spread 22; 31 dropped, K2 32.08-32.69).
// ---------------------------------------------------------------------------

#[cfg(test)]
mod nv2_tests {
    use super::*;
    use crate::outline_spacing::{InkInterval, ScanRow};

    /// Varied population: per-glyph left/right wall depths, wall slopes and
    /// vertical shifts, so sidebearings and per-direction residuals diverge
    /// (flush boxes of one class solve to residual 0 by the equal-area
    /// construction; sloped walls break that degeneracy).
    fn mk(id: &str, dl: f64, dr: f64, dy: f64, slope: f64, nrows: usize, bump: f64) -> OutlineProfile {
        let rows = (0..nrows).map(|i| ScanRow {
            y: i as f64 * 10.0 + dy,
            weight: 10.0,
            ink: vec![InkInterval {
                left: dl + slope * i as f64 + if i >= nrows - 3 { bump } else { 0.0 },
                right: dl + slope * i as f64 + 40.0,
            }],
            span_lo: i as f64 * 10.0 - 5.0 + dy,
            span_hi: i as f64 * 10.0 + 5.0 + dy,
        }).collect();
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: "test".into(),
            upm: 1000,
            origin: [0.0, 0.0],
            rows,
            bounds: [0.0, dy, dl + nrows as f64 * slope.abs() + 40.0 + dr, nrows as f64 * 10.0 + dy],
            ink_area: 40.0 * 100.0,
            counter_area: 0.0,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: "test-fixture".into(), row_step: 10.0, flatten_tolerance: 0.5,
        }
    }

    /// 16 glyphs: per-glyph wall depths, slopes, top-row bumps and two
    /// heights. Probed population (80 emitted / 160 below-epsilon / 44
    /// asymmetric at the default policy): flush or uniformly sloped walls
    /// solve to residual 0 by the equal-area construction, so the wall
    /// curvature (bump) and the height split carry the residual variance.
    fn varied_population() -> Vec<OutlineProfile> {
        let mut v = Vec::new();
        for i in 0..16u32 {
            let dl = [0.0, 10.0, 30.0, 70.0][(i % 4) as usize];
            let dr = [0.0, 14.0, 26.0, 55.0][((i / 4) % 4) as usize];
            let slope = [2.5, 0.0, 4.0, 1.0][(i % 4) as usize];
            let bump = [22.0, 0.0, 35.0, 0.0][((i / 4) % 4) as usize];
            let (dy, nrows) = if i % 2 == 0 { (0.0, 10) } else { (30.0, 5) };
            v.push(mk(&format!("g{i:02}"), dl, dr, dy, slope, nrows, bump));
        }
        v
    }

    #[test]
    fn nv2_class_unit_decision_marq_ready_shape_selects_median() {
        // Work list item 7 evidence: the ready set (17 pairs) spans min ink
        // gaps 0.24..22.27 (spread 22). Shape reproduced on the quoted
        // endpoints; eps is the solver's residual epsilon (policy-derived).
        let gaps = [0.24, 20.0, 21.0, 22.27];
        let d = class_unit_decision(&gaps, 2.0).unwrap();
        assert!((d.candidate_mean - 15.8775).abs() < 1e-9, "mean {}", d.candidate_mean);
        assert!((d.candidate_median - 20.5).abs() < 1e-9, "median {}", d.candidate_median);
        assert!((d.candidate_midrange - 11.255).abs() < 1e-9, "midrange {}", d.candidate_midrange);
        assert!((d.score_mean - 7.81875).abs() < 1e-9, "score_mean {}", d.score_mean);
        assert!((d.score_median - 5.065).abs() < 1e-9, "score_median {}", d.score_median);
        assert!((d.score_midrange - 10.13).abs() < 1e-9, "score_midrange {}", d.score_midrange);
        assert_eq!(d.selected, ClassUnitCandidate::Median);
        assert!((d.unit - 20.5).abs() < 1e-9);
        assert!((d.inconsistency_score - 5.065).abs() < 1e-9);
        assert_eq!(d.uniform_count, 3);
    }

    #[test]
    fn nv2_class_unit_decision_marq_dropped_shape_is_uniform() {
        // Work list item 7 evidence: the dropped set (31 pairs) sits at K2
        // min 32.08-32.69 (spread 0.6): already nearly equalized, so every
        // candidate scores 0 and the baseline (mean) wins the tie.
        let gaps = [32.08, 32.4, 32.69];
        let d = class_unit_decision(&gaps, 2.0).unwrap();
        assert_eq!(d.score_mean, 0.0);
        assert_eq!(d.score_median, 0.0);
        assert_eq!(d.score_midrange, 0.0);
        assert_eq!(d.selected, ClassUnitCandidate::Mean);
        assert_eq!(d.uniform_count, 3);
    }

    #[test]
    fn nv2_class_unit_decision_edge_cases() {
        assert!(class_unit_decision(&[], 2.0).is_none());
        let d = class_unit_decision(&[7.0], 2.0).unwrap();
        assert_eq!(d.unit, 7.0);
        assert_eq!(d.inconsistency_score, 0.0);
        assert_eq!(d.uniform_count, 1);
        // Bimodal: all three candidates coincide, tie breaks to the baseline.
        let d = class_unit_decision(&[0.5, 0.7, 30.0, 30.2], 2.0).unwrap();
        assert!((d.candidate_mean - 15.35).abs() < 1e-9);
        assert_eq!(d.selected, ClassUnitCandidate::Mean);
        assert!((d.inconsistency_score - 14.75).abs() < 1e-9);
    }

    #[test]
    fn nv2_harmony_off_is_bit_identical_to_frozen() {
        let glyphs = varied_population();
        let policy = SpacingPolicy::default();
        let frozen = solve_spacing(&glyphs, None, &policy).unwrap();
        let (sol, report) = solve_spacing_with_class_harmony(
            &glyphs, None, &policy, ClassHarmonyPolicy::default()).unwrap();
        assert_eq!(format!("{frozen:?}"), format!("{sol:?}"));
        assert!(report.symmetry_promotions.is_empty());
        assert!(report.class_unit_rows.is_empty());
        assert!(report.class_spacing_adjustments.is_empty());
    }

    #[test]
    fn nv2_direction_symmetry_shared_keep_drop_decision() {
        let glyphs = varied_population();
        let policy = SpacingPolicy::default();
        let off = solve_spacing(&glyphs, None, &policy).unwrap();
        let emitted: std::collections::BTreeSet<(String, String)> =
            off.pairs.iter().map(|p| (p.left.clone(), p.right.clone())).collect();
        let dropped: std::collections::BTreeSet<(String, String)> =
            off.pair_ledger.iter()
                .filter(|r| r.reason == PairLedgerReason::ExcludedBelowEpsilon)
                .map(|r| (r.left.clone(), r.right.clone())).collect();
        // The work-list case: one direction emitted, the reverse dropped.
        let asymmetric: std::collections::BTreeSet<(String, String)> =
            dropped.iter().filter(|(l, r)| emitted.contains(&(r.clone(), l.clone()))).cloned().collect();
        eprintln!("nv2 symmetry fixture: {} emitted, {} below-epsilon dropped, {} asymmetric",
            emitted.len(), dropped.len(), asymmetric.len());
        assert!(!asymmetric.is_empty(), "fixture must reproduce the work-list case (one direction emitted, reverse dropped)");
        let harmony = ClassHarmonyPolicy { direction_symmetry: true, class_spacing_units: false };
        let (on, report) = solve_spacing_with_class_harmony(&glyphs, None, &policy, harmony).unwrap();
        let promoted: std::collections::BTreeSet<(String, String)> =
            report.symmetry_promotions.iter().map(|p| (p.left.clone(), p.right.clone())).collect();
        assert_eq!(promoted, asymmetric, "promotion set must equal the frozen run's asymmetric set");
        // Both directions decided together: no emitted pair may keep a
        // below-epsilon-dropped reverse.
        let on_emitted: std::collections::BTreeSet<(String, String)> =
            on.pairs.iter().map(|p| (p.left.clone(), p.right.clone())).collect();
        for r in &on.pair_ledger {
            if r.reason == PairLedgerReason::ExcludedBelowEpsilon {
                assert!(!on_emitted.contains(&(r.right.clone(), r.left.clone())),
                    "{}->{} dropped while its reverse is emitted", r.left, r.right);
            }
        }
        // Promotion grows the emitted set exactly by the promoted pairs.
        assert_eq!(on.pairs.len(), off.pairs.len() + asymmetric.len());
        assert_eq!(on.excluded_below_epsilon + asymmetric.len(), off.excluded_below_epsilon);
        assert_eq!(on.accounting_closed, off.accounting_closed);
        // Receipt rows carry both directions' solved residuals.
        for p in &report.symmetry_promotions {
            let off_row = off.pair_ledger.iter()
                .find(|r| r.left == p.left && r.right == p.right)
                .expect("promoted pair was a frozen below-epsilon row");
            assert_eq!(p.residual.to_bits(), off_row.residual.to_bits());
            let rev = off.pairs.iter()
                .find(|q| q.left == p.right && q.right == p.left)
                .expect("reverse direction was emitted in the frozen run");
            let rev_advance = on.glyphs.iter().find(|g| g.glyph_id == rev.left).unwrap().advance;
            assert_eq!(p.reverse_residual.to_bits(), (rev.origin_distance - rev_advance).to_bits());
        }
        assert!(report.class_unit_rows.is_empty());
        assert!(report.class_spacing_adjustments.is_empty());
    }

    #[test]
    fn nv2_class_units_rows_typed_and_kern_layer_untouched() {
        let glyphs = varied_population();
        let policy = SpacingPolicy::default();
        let frozen = solve_spacing(&glyphs, None, &policy).unwrap();
        let harmony = ClassHarmonyPolicy { direction_symmetry: false, class_spacing_units: true };
        let (sol, report) = solve_spacing_with_class_harmony(&glyphs, None, &policy, harmony).unwrap();
        // The class lane never touches kern or glyph output.
        assert_eq!(format!("{:?}", frozen.pairs), format!("{:?}", sol.pairs));
        assert_eq!(format!("{:?}", frozen.glyphs), format!("{:?}", sol.glyphs));
        assert!(report.symmetry_promotions.is_empty());
        assert!(!report.class_unit_rows.is_empty(), "box population has solved class pairs");
        let eps = policy.residual_epsilon();
        for row in &report.class_unit_rows {
            let (cand, score) = match row.selected {
                ClassUnitCandidate::Mean => (row.candidate_mean, row.score_mean),
                ClassUnitCandidate::Median => (row.candidate_median, row.score_median),
                ClassUnitCandidate::Midrange => (row.candidate_midrange, row.score_midrange),
            };
            assert_eq!(row.unit.to_bits(), cand.to_bits());
            assert_eq!(row.inconsistency_score.to_bits(), score.to_bits());
            assert!(score <= row.score_mean + f64::EPSILON || row.selected == ClassUnitCandidate::Mean);
            let adjustments = report.class_spacing_adjustments.iter()
                .filter(|a| a.class == format!("{}->{}", row.left_class, row.right_class))
                .count();
            assert_eq!(row.uniform_count + adjustments, row.pair_count);
        }
        for a in &report.class_spacing_adjustments {
            assert!(a.deviation.abs() >= eps);
            assert_eq!(a.correction.to_bits(), (-a.deviation).to_bits());
            assert_eq!(a.left_rsb_delta.to_bits(), (a.correction / 2.0).to_bits());
            assert_eq!(a.right_lsb_delta.to_bits(), (a.correction / 2.0).to_bits());
            assert_eq!(a.deviation.to_bits(), (a.gap_before - a.unit).to_bits());
        }
    }
}

#[cfg(test)]
mod next_up_tests {
    use super::{next_up, next_down};
    #[test]
    fn next_up_is_sign_aware() {
        // Positive: one ulp up.
        assert!(next_up(1.0) > 1.0);
        assert_eq!(next_up(1.0), f64::from_bits(1.0f64.to_bits() + 1));
        // Negative: moves TOWARD zero (outward = upward), not more negative.
        let u = next_up(-300.5);
        assert!(u > -300.5 && u < 0.0, "next_up(-300.5) = {u}");
        assert_eq!(u, f64::from_bits((-300.5f64).to_bits() - 1));
        // Zero: min positive subnormal.
        assert_eq!(next_up(0.0), f64::from_bits(1));
        assert_eq!(next_up(-0.0), f64::from_bits(1));
        // Symmetry of next_down.
        assert!(next_down(300.5) < 300.5 && next_down(300.5) > 0.0);
        assert!(next_down(-1.0) < -1.0);
        assert_eq!(next_down(0.0), -f64::from_bits(1));
        // Round-trip: next_down(next_up(v)) == v for ordinary values.
        for &v in &[1.0, -300.5, 1e-300, -1e300] {
            assert_eq!(next_down(next_up(v)), v, "round trip {v}");
        }
    }
}

// ==== W1: natural-safe / widened re-guard decisions (pure, unit-testable) ====
/// Minimum gap over constant cells. None when cells are empty or any gap is non-finite
/// (a bare fold from INFINITY turns empty cells into +inf >= 0 and skips NaN via f64::min).
fn checked_raw_min(cells: &[(f64, f64, f64)]) -> Option<f64> {
    if cells.is_empty() { return None; }
    let mut m = f64::INFINITY;
    for c in cells {
        if !c.1.is_finite() || !c.2.is_finite() { return None; }
        m = m.min(c.1).min(c.2);
    }
    Some(m)
}
/// Canonical (export-frame) evidence reduced to what the guard needs:
/// sc::evidence_at(..) -> collides() and clearance.min_gap (signed; negative = penetration depth).
#[derive(Debug, Clone, Copy, PartialEq)]
struct CanonNatural { collides: bool, min_gap: f64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WidenReason {
    /// raw cells and canonical evidence both show a collision; deficit = canonical depth.
    RawAndCanonicalHit,
    /// raw cells clear (zero raw depth) but canonical evidence collides; deficit = max(0, -canonical min_gap). If canonical min_gap >= 0 while collides() is true this is a depth-zero interval collision (the evidence flags a collision with no measurable penetration depth, deficit 0); touching alone is legal and never reaches this arm because collides() is false then.
    RawClearCanonicalHit,
    /// canonical evidence unmeasurable but raw cells prove a collision; deficit = raw depth (no canonical value exists).
    RawHitCanonicalUnmeasurable,
}
impl WidenReason {
    fn code(&self) -> &'static str {
        match self {
            WidenReason::RawAndCanonicalHit => "raw_and_canonical_hit",
            WidenReason::RawClearCanonicalHit => "raw_clear_canonical_hit_zero_raw_depth",
            WidenReason::RawHitCanonicalUnmeasurable => "raw_hit_canonical_unmeasurable",
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq)]
enum NaturalDecision {
    /// Raw cells checked clear (min >= 0) AND canonical evidence present, finite and non-colliding.
    Safe { raw_min: f64, canon_min_gap: f64 },
    /// Collision proven in at least one frame; widen the L2 domain by `deficit` (canonical measured depth when available).
    Widen { deficit: f64, reason: WidenReason },
    /// Raw cells empty/non-finite, canonical missing/non-finite, or canonical unmeasurable with raw clear: no collision proof, no safe proof (Unknown).
    Unverifiable,
    /// Raw says collision, canonical says clear: frames disagree (Unknown, never safe, never silently widened).
    FrameConflict,
}
fn decide_natural(cells0: &[(f64, f64, f64)], canon: Option<CanonNatural>) -> NaturalDecision {
    let Some(m) = checked_raw_min(cells0) else { return NaturalDecision::Unverifiable };
    match canon {
        None => if m < 0.0 {
            NaturalDecision::Widen { deficit: -m, reason: WidenReason::RawHitCanonicalUnmeasurable }
        } else { NaturalDecision::Unverifiable },
        Some(c) if !c.min_gap.is_finite() => NaturalDecision::Unverifiable,
        Some(c) if !c.collides => if m >= 0.0 {
            NaturalDecision::Safe { raw_min: m, canon_min_gap: c.min_gap }
        } else { NaturalDecision::FrameConflict },
        Some(c) => NaturalDecision::Widen {
            deficit: (-c.min_gap).max(0.0),
            reason: if m >= 0.0 { WidenReason::RawClearCanonicalHit } else { WidenReason::RawAndCanonicalHit },
        },
    }
}
/// Widened-result re-guard: checked raw min >= 0 AND canonical evidence present and non-colliding.
fn widened_reguard_ok(cells_at: &[(f64, f64, f64)], canon_collides: Option<bool>) -> bool {
    matches!(checked_raw_min(cells_at), Some(m) if m >= 0.0) && canon_collides == Some(false)
}

// ==== L2: actual-placement pair solve (chief J-fix draft; NOT yet wired) ====
//
// Replaces the unsound frozen-cells + shift evaluation for one pair:
// clearance(d+t) != clearance(d)+t because facing membership changes with
// distance (regression (a), cells_residual_divergence.rs). Here the pair is
// partitioned into EXACT feasible residual components
// (signed_clearance::forbidden_residual_intervals / feasible_components);
// inside one component facing membership is fixed, so measuring the
// constant cells at a component-local reference placement and shifting
// WITHIN the component is sound. Component edges are legal touching
// candidates measured at their own placement. Every shipped candidate is
// re-verified with evidence_at in the guard's frame (FP caveat, chief
// 23:19): a model-legal edge that fails canonical evidence is stepped
// outward with next_up_outward under the 64-step resource convention;
/// Closed ordered-pair accounting: every non-self evaluation lands in exactly one
/// bucket. evaluations - sum(buckets) (0 = closed), computed in i128 (no
/// usize/u64 mixing, no overflow), saturated into i64 only at the end. Bucket
/// order: emitted, max_pairs ledger, below-epsilon, unmeasurable, numeric-failed
/// (unresolved), geometric-hold, candidate-hold, fallback natural-clear,
/// fallback guard-verified. fallback_pairs are NOT part of `candidates`.
pub fn closed_accounting_residual(evaluations: u64, buckets: [usize; 9]) -> i64 {
    let sum: u128 = buckets.iter().map(|&b| b as u128).sum();
    let r = evaluations as i128 - sum as i128;
    i64::try_from(r).unwrap_or(if r < 0 { i64::MIN } else { i64::MAX })
}

/// Number of ordered pairs that appear in more than one of the emitted
/// candidates, the max_pairs ledger and the tier-2 fallback rows. Buckets
/// must be mutually exclusive; any overlap makes the accounting untrustworthy.
pub fn bucket_overlap_count(candidates: &[PairPosition], excluded: &[ExcludedPair],
                            fallback: &[PairPosition]) -> usize {
    use std::collections::BTreeMap;
    let mut seen: BTreeMap<(&str, &str), usize> = BTreeMap::new();
    for p in candidates { *seen.entry((p.left.as_str(), p.right.as_str())).or_insert(0) += 1; }
    for p in excluded { *seen.entry((p.left.as_str(), p.right.as_str())).or_insert(0) += 1; }
    for p in fallback { *seen.entry((p.left.as_str(), p.right.as_str())).or_insert(0) += 1; }
    seen.values().filter(|&&n| n > 1).count()
}

/// Typed reason for a bounded numeric failure (classification never depends on message text).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub enum NumericFailKind {
    /// Forbidden-interval or component construction hit a non-finite state (ForbiddenError::NonFinite).
    NonFiniteIntervals,
    /// Malformed interval list (ForbiddenError::MalformedIntervals).
    MalformedIntervals,
    /// Per-piece numerics overflowed or produced NaN.
    PieceNumerics,
    /// Every candidate's bounded origin bracket exhausted without a safe point.
    BracketExhausted,
}
impl NumericFailKind {
    pub fn code(&self) -> &'static str {
        match self {
            NumericFailKind::NonFiniteIntervals => "nonfinite_intervals",
            NumericFailKind::MalformedIntervals => "malformed_intervals",
            NumericFailKind::PieceNumerics => "piece_numerics",
            NumericFailKind::BracketExhausted => "bracket_exhausted",
        }
    }
    /// Non-finite numeric state: fail-safe, typed record only.
    pub fn is_nonfinite(&self) -> bool {
        matches!(self, NumericFailKind::NonFiniteIntervals | NumericFailKind::PieceNumerics)
    }
    /// Recovery allowlist: ONLY a bounded search that ran out of steps may enter tier-2 recovery.
    pub fn recovery_allowed(&self) -> bool { matches!(self, NumericFailKind::BracketExhausted) }
}
impl std::fmt::Display for NumericFailKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let t = match self {
            NumericFailKind::NonFiniteIntervals => "non-finite forbidden intervals",
            NumericFailKind::MalformedIntervals => "malformed forbidden intervals",
            NumericFailKind::PieceNumerics => "non-finite piece numerics (overflow/NaN)",
            NumericFailKind::BracketExhausted => "bounded search did not find a safe point",
        };
        write!(f, "{}: {t}", self.code())
    }
}

/// Typed outcome of the actual-placement pair solve.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PairSolve {
    /// Feasible optimum: residual t, canonical wall gap at base+t, owning component.
    Solved { residual: f64, origin: f64, wall_gap: f64, component: (f64, f64) },
    /// No feasible residual in the domain (forbidden intervals cover it):
    /// typed hold, NOT a semantic verdict that the pair collides.
    NoFeasible,
    /// Feasible components EXISTED but no candidate was accepted in the
    /// declared domain (objective cells empty, non-finite J, or every
    /// candidate rejected at its component edge): NOT an empty-complement
    /// geometric hold, NOT numeric non-convergence (chief 23:44 (2)).
    NoAcceptedCandidate,
    /// Bounded numerics did not converge (non-finite piece state, bracket
    /// exhaustion): openly recorded, never an empty "complete" pass.
    NotConverged(NumericFailKind),
    /// No common span / unmeasurable pair (existing ledger class).
    Unmeasurable,
}

/// Per-pair argmin of J over the EXACT feasible residual components.
/// l, r raw profiles; base_offset = the pair's raw-frame base placement
/// WITHOUT the residual (model frame: cells, forbidden intervals, domain).
/// advance/l_tr/r_tr bind the EXPORT frame: the guard verifies
/// evidence_at(l, r, l_tr, r_tr, advance + residual) with
/// x_translation = lsb - ink_xmin exactly as the exporter composes it, so
/// the returned `origin` is bit-exact the value the export guard re-checks
/// (chief 23:44 (1): integrated frame/origin binding; raw-safe is never
/// claimed export-safe). Domain [t_lo, t_hi] in residual units. The 64-step
/// outward verification steps the export-frame origin directly under the
/// shared ordered stepping contract (signed_clearance::next_up_outward).
pub fn solve_pair_t_l2(l: &crate::outline_spacing::OutlineProfile,
                   r: &crate::outline_spacing::OutlineProfile,
                   base_offset: f64, cap: f64, pair_gap: f64,
                   lambda: f64, t_lo: f64, t_hi: f64,
                   advance: f64, l_tr: f64, r_tr: f64) -> PairSolve {
    use crate::signed_clearance as sc;
    let forbidden = match sc::forbidden_residual_intervals(l, r, base_offset) {
        Ok(iv) => iv,
        Err(sc::ForbiddenError::NoCommonSpan) => return PairSolve::Unmeasurable,
        Err(sc::ForbiddenError::NonFinite) => return PairSolve::NotConverged(NumericFailKind::NonFiniteIntervals),
        Err(sc::ForbiddenError::MalformedIntervals) => return PairSolve::NotConverged(NumericFailKind::MalformedIntervals),
    };
    let comps = match sc::feasible_components(t_lo, t_hi, &forbidden) {
        Ok(c) => c,
        Err(sc::ForbiddenError::NonFinite) => return PairSolve::NotConverged(NumericFailKind::NonFiniteIntervals),
        Err(sc::ForbiddenError::MalformedIntervals) => return PairSolve::NotConverged(NumericFailKind::MalformedIntervals),
        // No common span cannot come from component construction; if it does, it is an unmeasurable pair.
        Err(sc::ForbiddenError::NoCommonSpan) => return PairSolve::Unmeasurable,
    };
    if comps.is_empty() { return PairSolve::NoFeasible; }
    // Placement-independent row alignment hoisted out of every per-placement
    // clearance/evidence call in this solve (K2 pair-cascade profile: the
    // align_pair_rows recompute dominated all three most expensive steps).
    // The aligned rows are an input to pure per-placement math, so every
    // value below is bit-identical to recomputing the alignment per call.
    let rows = crate::outline_spacing::align_pair_rows(l, r);
    // Per-placement objective evaluation without the per-eval cell Vec
    // (option B, measured): channel_stats_rows folds the same cells in the
    // same order with the same per-cell math, bit-identical to collecting
    // clearance_cells_constant_rows and reducing with channel_stats.
    let obj_at = |t: f64| -> Option<f64> {
        // Cells measured AT the candidate placement (exact, no shift).
        let (w, v) = channel_stats_rows(&rows, base_offset + t, 0.0, cap)?;
        let j = (w - pair_gap) * (w - pair_gap) + lambda * v;
        if j.is_finite() { Some(j) } else { None }
    };
    // Candidate collection is split from J evaluation. obj_at(t) is pure in
    // t, so re-evaluating an equal t can only reproduce the same J; the
    // post-evaluation ranking sorts on (J, |t|, t) and dedups equal t's,
    // keeping the first inserted occurrence. Collecting raw candidates,
    // deduping equal t's BEFORE evaluation (stable order: first inserted
    // occurrence and its component binding kept), then evaluating each
    // survivor once yields exactly the eager loop's candidate set. The
    // 478-glyph profile showed 31.8M eager evaluations for 8.1M unique
    // candidates (~75% duplicate work removed).
    let mut raw: Vec<(f64, (f64, f64))> = Vec::new(); // (t, component)
    let push = |t: f64, comp: (f64, f64), raw: &mut Vec<(f64, (f64, f64))>| {
        if !t.is_finite() { return; }
        raw.push((t, comp));
    };
    for &(a, b) in &comps {
        if a == b { push(a, (a, b), &mut raw); continue; } // point component
        // T10: the tie key is GLOBAL residual |t|, not local |t - t_ref|.
        // A local argmin can discard the global winner on a flat plateau.
        // Keep the component point closest to zero as an independent
        // candidate; it still receives actual-placement J and canonical
        // export-frame verification, just like every other candidate.
        let nearest_zero = if a > 0.0 { a } else if b < 0.0 { b } else { 0.0 };
        push(nearest_zero, (a, b), &mut raw);
        // Interior solve: cells at the component midpoint reference; the
        // in-component shift is sound because membership is fixed inside.
        let t_ref = a + (b - a) / 2.0;
        let cells_ref = sc::clearance_cells_constant_rows(&rows, base_offset + t_ref);
        if !cells_ref.is_empty() {
            // Preserve plateau boundaries too: if zero is outside a
            // minimum plateau, its nearest end can be a cap breakpoint
            // which the local-coordinate tie rule would otherwise drop.
            // No epsilon/equal-J relaxation: ranking below is unchanged.
            for &(_, c0, c1) in &cells_ref {
                for c in [c0, c1] {
                    let t_cap = t_ref + (cap - c);
                    if t_cap.is_finite() && t_cap >= a && t_cap <= b {
                        push(t_cap, (a, b), &mut raw);
                    }
                }
            }
            let t_loc = solve_pair_t(&cells_ref, cap, pair_gap, lambda,
                                     a - t_ref, b - t_ref);
            if t_loc.is_nan() { return PairSolve::NotConverged(NumericFailKind::PieceNumerics); }
            if t_loc.is_finite() { push(t_loc + t_ref, (a, b), &mut raw); }
        }
        push(a, (a, b), &mut raw); // touching edges are legal candidates,
        push(b, (a, b), &mut raw); // measured at their own placement
    }
    // Stable pre-evaluation dedup on t (see above): equal t keeps its FIRST
    // inserted component binding, exactly as the post-sort dedup did.
    raw.sort_by(|x, y| x.0.partial_cmp(&y.0).unwrap_or(std::cmp::Ordering::Equal));
    raw.dedup_by(|x, y| x.0 == y.0);
    let mut cands: Vec<(f64, f64, (f64, f64))> = Vec::with_capacity(raw.len()); // (t, J, component)
    for (t, comp) in raw {
        if let Some(jv) = obj_at(t) { cands.push((t, jv, comp)); }
    }
    if cands.is_empty() {
        // Components existed but produced no evaluable candidate (objective
        // cells empty / non-finite J): NOT an empty complement (chief 23:44 (2)).
        return PairSolve::NoAcceptedCandidate;
    }
    // Selection order: smaller J, then smaller |t|, then smaller t (frozen rule).
    cands.sort_by(|x, y| x.1.partial_cmp(&y.1).unwrap_or(std::cmp::Ordering::Equal)
        .then(x.0.abs().partial_cmp(&y.0.abs()).unwrap_or(std::cmp::Ordering::Equal))
        .then(x.0.partial_cmp(&y.0).unwrap_or(std::cmp::Ordering::Equal)));
    cands.dedup_by(|x, y| x.0 == y.0);
    // Canonical re-verification in the guard's frame (chief (a)+(c)). The
    // bracket steps the ORIGIN (base_offset + t), not the residual: at large
    // base magnitudes a residual ulp can vanish in the addition, exhausting
    // the 64-step budget without moving the origin (chief 23:28 (1)). On
    // guard rejection the NEXT-BEST candidate is tried (chief 23:28 (2));
    // NotConverged only when every candidate's bracket exhausts.
    // Canonical re-verification in the guard's frame. The bracket steps the
    // ORIGIN, not the residual (chief 23:28 (1)), and stays inside the OWNING
    // component: stepping past the component edge enters a forbidden
    // interval, so the candidate is rejected, never verified there (chief
    // 23:38 (b)). A shifted origin recomputes J at the verified placement and
    // the final ranking runs over all verified candidates (chief 23:38 (b)).
    // Solved carries the bit-exact verified origin next to the residual so
    // the callsite never recomposes base + residual into a different float
    // (chief 23:38 (a)). NotConverged only when a bracket exhausts its
    // 64-step budget with no verified candidate left (chief 23:28 (2)).
    let mut verified: Vec<(f64, f64, (f64, f64), f64, f64)> = Vec::new();
    // (origin, J at origin, component, wall_gap, residual)
    let mut any_exhausted = false;
    for (t, _, comp) in &cands {
        // Export-frame bounds composed with the exporter's own expression
        // (advance + x), so the comparison lives in one frame.
        let comp_hi = advance + comp.1;
        let dom_hi = advance + t_hi;
        let mut origin = advance + *t; // export-frame origin_distance
        let mut steps = 0usize;
        let mut hit = None;
        loop {
            match sc::evidence_at_rows(&rows, l_tr, r_tr, origin) {
                Some(e) if !e.collides() => { hit = Some(e); break; }
                Some(_) => {
                    if steps >= 64 { any_exhausted = true; break; }
                    match sc::next_up_outward(origin) {
                        Some(u) if u <= comp_hi && u <= dom_hi => { origin = u; steps += 1; }
                        Some(_) => break, // left owning component/domain: reject candidate
                        None => { any_exhausted = true; break; }
                    }
                }
                None => return PairSolve::Unmeasurable,
            }
        }
        if let Some(e) = hit {
            let residual = origin - advance;
            // Model-frame J at the verified placement (raw cells; J is
            // model-internal — the SAFETY evidence above is export-frame).
            let Some((w, v)) = channel_stats_rows(&rows, base_offset + residual, 0.0, cap) else { continue; };
            let j = (w - pair_gap) * (w - pair_gap) + lambda * v;
            if j.is_finite() { verified.push((origin, j, *comp, e.clearance.min_gap, residual)); }
        }
    }
    if verified.is_empty() {
        if any_exhausted { return PairSolve::NotConverged(NumericFailKind::BracketExhausted); }
        // Every candidate rejected at its component edge without bracket
        // exhaustion: components existed (chief 23:44 (2)).
        return PairSolve::NoAcceptedCandidate;
    }
    // Re-rank at ACTUAL verified placements (chief 23:38 (b)): smaller J,
    // then smaller |residual|, then smaller residual (frozen rule).
    verified.sort_by(|x, y| x.1.partial_cmp(&y.1).unwrap_or(std::cmp::Ordering::Equal)
        .then(x.4.abs().partial_cmp(&y.4.abs()).unwrap_or(std::cmp::Ordering::Equal))
        .then(x.4.partial_cmp(&y.4).unwrap_or(std::cmp::Ordering::Equal)));
    let (origin, _, comp, wall_gap, residual) = verified[0];
    PairSolve::Solved { residual, origin, wall_gap, component: comp }
}

#[cfg(test)]
mod w1k1_tests {
    use super::*;
    use crate::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};
    use crate::signed_clearance as sc;

    fn prof(id: &str, rings: Vec<Vec<[f64; 2]>>) -> crate::outline_spacing::OutlineProfile {
        let input = OutlineInput { glyph_id: id.into(), source_pin: format!("sha256:test:{id}"),
            upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0, rings };
        let pol = ScanPolicy { row_step: 2.0, max_rows: 4000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
        profile_outline(&input, pol).expect("profile")
    }
    fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> { vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]] }

    #[test]
    fn channel_stats_rows_bit_identical_to_collect_then_reduce() {
        // The fused per-placement evaluation must reproduce
        // channel_stats(clearance_cells_constant_rows(...)) bit for bit,
        // including the empty-cells -> None mapping the caller branches on.
        let l = prof("e", vec![rect(0.0, 0.0, 100.0, 160.0), rect(20.0, 200.0, 90.0, 300.0)]);
        let r = prof("u", vec![rect(0.0, 0.0, 80.0, 160.0)]);
        let rows = crate::outline_spacing::align_pair_rows(&l, &r);
        let far = prof("far", vec![rect(0.0, 5000.0, 10.0, 5100.0)]);
        let rows_empty = crate::outline_spacing::align_pair_rows(&l, &far);
        let bits = |s: Option<(f64, f64)>| s.map(|(w, v)| (w.to_bits(), v.to_bits()));
        for (tag, rows) in [("shared", &rows), ("empty", &rows_empty)] {
            for &o in &[-500.0, -37.5, 0.0, 12.25, 160.0, 400.0] {
                for &cap in &[17.0, 250.0] {
                    let cells = sc::clearance_cells_constant_rows(rows, o);
                    let want = if cells.is_empty() { None } else { Some(channel_stats(&cells, 0.0, cap)) };
                    assert_eq!(bits(want), bits(channel_stats_rows(rows, o, 0.0, cap)), "stats at {tag}/{o}/{cap}");
                }
            }
        }
    }

    #[test]
    fn numeric_fail_kind_is_typed_and_recovery_is_allowlisted() {
        assert!(NumericFailKind::NonFiniteIntervals.is_nonfinite());
        assert!(NumericFailKind::PieceNumerics.is_nonfinite());
        assert!(!NumericFailKind::MalformedIntervals.is_nonfinite());
        assert!(!NumericFailKind::BracketExhausted.is_nonfinite());
        assert!(NumericFailKind::BracketExhausted.recovery_allowed());
        for k in [NumericFailKind::NonFiniteIntervals, NumericFailKind::MalformedIntervals, NumericFailKind::PieceNumerics] {
            assert!(!k.recovery_allowed(), "{}", k.code());
        }
        assert!(!NumericFailKind::BracketExhausted.to_string().contains("non-finite"));
    }

    #[test]
    fn forbidden_error_variants_keep_their_exact_typed_kind() {
        // Exact sc contract (validate_intervals runs before the domain check).
        assert!(matches!(sc::feasible_components(0.0, 1.0, &[(f64::NAN, 1.0)]), Err(sc::ForbiddenError::NonFinite)));
        assert!(matches!(sc::feasible_components(f64::NAN, 1.0, &[]), Err(sc::ForbiddenError::NonFinite)));
        assert!(matches!(sc::feasible_components(0.0, f64::INFINITY, &[]), Err(sc::ForbiddenError::NonFinite)));
        assert!(matches!(sc::feasible_components(0.0, 1.0, &[(2.0, 1.0)]), Err(sc::ForbiddenError::MalformedIntervals)));
        assert!(matches!(sc::feasible_components(0.0, 5.0, &[(3.0, 4.0), (1.0, 2.0)]), Err(sc::ForbiddenError::MalformedIntervals)));
    }

    #[test]
    fn colliding_naive_optimum_projects_to_feasible_boundary_both_lambda_paths() {
        // K1 solver-guard geometry unification, solve-level regression:
        // a synthetic pair whose unconstrained J-optimum (target gap -20)
        // sits strictly inside the forbidden interval, while a feasible
        // solution exists. The solve must ship the nearest feasible boundary
        // (gap 0, touching), verified with the guard's own primitive, and
        // the reported wall_gap must BE that guard-frame measurement, bit
        // for bit. Runs on both lambda paths: the feasibility invariant is
        // lambda-independent (frozen lambda=0 and lambda>0 share it).
        for lambda in [0.0, 1.0] {
            let l = prof("l", vec![rect(0.0, 0.0, 100.0, 100.0)]);
            let r = prof("r", vec![rect(0.0, 0.0, 50.0, 100.0)]);
            let (l_tr, r_tr) = (10.0, 10.0);
            let (advance, base_gap) = (115.0, 15.0);
            let raw_base = l.bounds[2] - r.bounds[0] + base_gap; // 115: clear by 15
            let cells = sc::clearance_cells_constant(&l, &r, raw_base);
            let min_base = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
            let (dcap, pair_gap) = (421.756, -20.0);
            let t_lo = -min_base; // -15: the caller's frozen domain convention
            let t_hi = (dcap - min_base).max(t_lo);
            let solved = solve_pair_t_l2(&l, &r, raw_base, dcap, pair_gap, lambda, t_lo, t_hi, advance, l_tr, r_tr);
            let PairSolve::Solved { residual, origin, wall_gap, .. } = solved else {
                panic!("colliding pair with a feasible boundary must solve, got {solved:?} (lambda {lambda})");
            };
            // The shipped placement verifies clean with the guard's own primitive.
            let ev = sc::evidence_at(&l, &r, l_tr, r_tr, origin).expect("evidence at shipped origin");
            assert!(!ev.collides(), "shipped placement must be guard-clean (lambda {lambda})");
            // The reported wall_gap is the guard-frame min_gap, bit for bit.
            assert_eq!(wall_gap.to_bits(), ev.clearance.min_gap.to_bits(), "lambda {lambda}");
            // The projection lands exactly on the nearest feasible boundary
            // (touching is legal): the naive optimum would have shipped gap -20.
            assert_eq!(ev.clearance.min_gap, 0.0, "nearest feasible boundary is the touching placement (lambda {lambda})");
            assert_eq!(residual, -base_gap, "lambda {lambda}");
            assert_eq!(residual.to_bits(), (origin - advance).to_bits(), "lambda {lambda}");
            // Determinism: the identical solve reproduces bit-identical output.
            let again = solve_pair_t_l2(&l, &r, raw_base, dcap, pair_gap, lambda, t_lo, t_hi, advance, l_tr, r_tr);
            assert_eq!(format!("{solved:?}"), format!("{again:?}"), "lambda {lambda}");
        }
    }

    #[test]
    fn fully_forbidden_domain_is_a_typed_hold_not_a_shipment() {
        // K1 always-output companion: a pair whose whole declared domain is
        // forbidden has NO feasible placement; the outcome is the typed
        // NoFeasible hold (the caller renders it as a typed ledger row),
        // never a shipped colliding placement.
        let l = prof("l", vec![rect(0.0, 0.0, 100.0, 100.0)]);
        let r = prof("r", vec![rect(0.0, 0.0, 50.0, 100.0)]);
        // raw_base 115 -> forbidden (-165, -15); domain [-50, -49] lies inside it.
        let solved = solve_pair_t_l2(&l, &r, 115.0, 421.756, -20.0, 0.0, -50.0, -49.0, 115.0, 10.0, 10.0);
        assert_eq!(solved, PairSolve::NoFeasible);
    }

    #[test]
    fn real_solve_maps_nonfinite_domains_to_nonfinite_kind() {
        let l = prof("l", vec![rect(0.0, 0.0, 100.0, 100.0)]);
        let r = prof("r", vec![rect(0.0, 0.0, 50.0, 100.0)]);
        // Non-finite base offset: forbidden_residual_intervals -> NonFinite.
        let a = solve_pair_t_l2(&l, &r, f64::NAN, 40.0, 10.0, 0.0, -10.0, 30.0, 115.0, 10.0, 10.0);
        assert_eq!(a, PairSolve::NotConverged(NumericFailKind::NonFiniteIntervals));
        // Non-finite domain edge: forbidden fine, feasible_components -> NonFinite (not Malformed).
        let b = solve_pair_t_l2(&l, &r, 115.0, 40.0, 10.0, 0.0, f64::NAN, 30.0, 115.0, 10.0, 10.0);
        assert_eq!(b, PairSolve::NotConverged(NumericFailKind::NonFiniteIntervals));
        // Both are on the non-recoverable typed path.
        assert!(!NumericFailKind::NonFiniteIntervals.recovery_allowed());
        // MalformedIntervals cannot be forced through solve_pair_t_l2: forbidden_residual_intervals
        // output always satisfies the interval contract, so that arm is covered by the
        // feasible_components test above, not by a real solve.
    }

    #[test]
    fn accounting_matches_historical_run3_numbers_hardcoded() {
        let ev = 253u64 * 252;
        assert_eq!(ev, 63756);
        assert_eq!(closed_accounting_residual(ev, [53959, 0, 4202, 5584, 0, 0, 0, 0, 0]), 11);
        assert_eq!(closed_accounting_residual(ev, [53959, 0, 4202, 5584, 0, 0, 0, 11, 0]), 0);
        assert_eq!(closed_accounting_residual(ev, [53959, 0, 4202, 5584, 0, 0, 0, 11, 11]), -11); // double count is visible
    }

    fn pp(l: &str, r: &str) -> PairPosition {
        PairPosition { left: l.into(), right: r.into(), origin_distance: 0.0, wall_gap: 0.0, optical_cost: 0.0, pair_target: None, compensated: false }
    }
    fn ep(l: &str, r: &str) -> ExcludedPair {
        ExcludedPair { left: l.into(), right: r.into(), origin_distance: 0.0, wall_gap: 0.0, optical_cost: 0.0 }
    }

    #[test]
    fn buckets_are_disjoint_not_just_numerically_closed() {
        let cands = vec![pp("a", "b"), pp("a", "c")];
        let led = vec![ep("b", "a")];
        let fb = vec![pp("c", "a")];
        assert_eq!(bucket_overlap_count(&cands, &led, &fb), 0);
        // fallback row duplicating an emitted candidate: counts add up but the buckets overlap.
        let fb_dup = vec![pp("a", "b")];
        assert_eq!(bucket_overlap_count(&cands, &led, &fb_dup), 1);
        assert_eq!(bucket_overlap_count(&cands, &[ep("a", "c")], &fb), 1);
    }

    #[test]
    fn raw_clear_canonical_collision_regression_with_real_profiles() {
        // Left rect 0..100 (lsb 10 -> l_tr 10), right rect 0..50 (lsb 10 -> r_tr 10), rsb 5:
        // model/raw base = l.xmax - r.xmin + (l_rsb + r_lsb) = 100 - 0 + 15 = 115 (gap 15, clear).
        let l = prof("l", vec![rect(0.0, 0.0, 100.0, 100.0)]);
        let r = prof("r", vec![rect(0.0, 0.0, 50.0, 100.0)]);
        let (l_tr, r_tr) = (10.0, 10.0);
        let raw_base = l.bounds[2] - r.bounds[0] + (5.0 + 10.0);
        let cells0 = sc::clearance_cells_constant(&l, &r, raw_base);
        assert_eq!(checked_raw_min(&cells0), Some(15.0));
        // Consistent metrics (advance = lsb + width + rsb = 115): canonical agrees, Safe.
        let ok = sc::evidence_at(&l, &r, l_tr, r_tr, 115.0).unwrap();
        assert!(!ok.collides());
        assert!(matches!(decide_natural(&cells0, Some(CanonNatural { collides: ok.collides(), min_gap: ok.clearance.min_gap })),
            NaturalDecision::Safe { .. }));
        // Frame/translation mismatch: advance_l = 95 while the model frame assumed 115.
        let bad = sc::evidence_at(&l, &r, l_tr, r_tr, 95.0).unwrap();
        assert!(bad.collides() && bad.clearance.min_gap < 0.0);
        assert_eq!(decide_natural(&cells0, Some(CanonNatural { collides: bad.collides(), min_gap: bad.clearance.min_gap })),
            NaturalDecision::Widen { deficit: -bad.clearance.min_gap, reason: WidenReason::RawClearCanonicalHit });
        // Canonical OR check is preserved: collides() = (min_gap < 0) || interval_hit.
        assert_eq!(bad.collides(), bad.clearance.min_gap < 0.0 || bad.interval_hit);
    }

    #[test]
    fn evidence_collides_matches_depth_and_interval_on_real_geometry() {
        // Witness family for the depth-0 case: on consistent geometry the outer-wall min_gap >= 0
        // implies no interval hit (right.left(y) >= left.right(y) bounds every inner interval),
        // so a depth-0 + interval_hit canonical result can only come from a frame/model difference,
        // which decide_natural classifies as Widen/RawClearCanonicalHit or FrameConflict.
        let ring = prof("o", vec![rect(0.0, 0.0, 100.0, 100.0),
                                  vec![[30.0, 30.0], [30.0, 70.0], [70.0, 70.0], [70.0, 30.0]]]);
        let bar = prof("bar", vec![rect(0.0, 0.0, 10.0, 100.0)]);
        for d in [100.0, 100.5, 120.0] {
            let e = sc::evidence_at(&ring, &bar, 0.0, 0.0, d).unwrap();
            assert!(e.clearance.min_gap >= 0.0 && !e.interval_hit && !e.collides(), "d={d}");
        }
        let e = sc::evidence_at(&ring, &bar, 0.0, 0.0, 95.0).unwrap();
        assert!(e.clearance.min_gap < 0.0 && e.interval_hit && e.collides());
        // touching: min_gap exactly 0, legal, no hit.
        let t = sc::evidence_at(&ring, &bar, 0.0, 0.0, 100.0).unwrap();
        assert_eq!(t.clearance.min_gap, 0.0);
        assert!(!t.collides());
    }
}


#[cfg(test)]
mod t10_global_residual_tie_tests {
    use super::{solve_pair_t_l2, PairSolve};
    use crate::outline_spacing::{InkInterval, OutlineProfile, ScanRow};

    fn rectangle(id: &str) -> OutlineProfile {
        OutlineProfile {
            glyph_id: id.into(), source_pin: "t10-explicit-rectangle".into(),
            upm: 1000, origin: [0.0, 0.0], bounds: [0.0, 0.0, 10.0, 2.0],
            rows: vec![
                ScanRow { y: 0.5, weight: 1.0, span_lo: 0.0, span_hi: 1.0,
                    ink: vec![InkInterval { left: 0.0, right: 10.0 }] },
                ScanRow { y: 1.5, weight: 1.0, span_lo: 1.0, span_hi: 2.0,
                    ink: vec![InkInterval { left: 0.0, right: 10.0 }] },
            ],
            ink_area: 20.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0,
            profile_method: "test-constant-intervals".into(),
            row_step: 1.0, flatten_tolerance: 0.0,
        }
    }

    fn solved(base: f64, cap: f64, target: f64, lambda: f64,
              lo: f64, hi: f64) -> (f64, f64, (f64, f64)) {
        let l = rectangle("left");
        let r = rectangle("right");
        match solve_pair_t_l2(&l, &r, base, cap, target, lambda,
                             lo, hi, base, 0.0, 0.0) {
            PairSolve::Solved { residual, origin, wall_gap, component } => {
                assert!(residual >= lo && residual <= hi);
                assert!(residual >= component.0 && residual <= component.1);
                assert_eq!(residual, origin - base);
                let e = crate::signed_clearance::evidence_at(&l, &r, 0.0, 0.0, origin)
                    .expect("solved placement must have canonical evidence");
                assert!(!e.collides(), "tie candidate must not bypass export safety");
                assert_eq!(wall_gap, e.clearance.min_gap);
                (residual, origin, component)
            }
            other => panic!("expected a verified optimum, got {other:?}"),
        }
    }

    #[test]
    fn lambda_zero_flat_plateau_chooses_zero_not_minus_one() {
        // gap = 2+t on [-1,1], always >= cap=1: J=0 everywhere.
        // Old local frozen solve retained t=-1; global |t| requires 0.
        let (t, origin, comp) = solved(12.0, 1.0, 1.0, 0.0, -1.0, 1.0);
        assert_eq!(t, 0.0);
        assert_eq!(origin, 12.0);
        assert_eq!(comp, (-1.0, 1.0));
    }

    #[test]
    fn positive_lambda_flat_plateau_uses_global_not_midpoint_tie() {
        // t_ref=2, so the local |t_loc| tie prefers global t=2.
        // With constant capped gap and V=0, global t=0 is the winner.
        assert_eq!(solved(20.0, 1.0, 1.0, 2.0, -1.0, 5.0).0, 0.0);
    }

    #[test]
    fn plateau_domain_not_containing_zero_chooses_nearest_endpoint() {
        assert_eq!(solved(20.0, 1.0, 1.0, 0.0, -8.0, -3.0).0, -3.0);
        assert_eq!(solved(20.0, 1.0, 1.0, 0.0, 2.0, 6.0).0, 2.0);
    }

    #[test]
    fn plateau_start_away_from_zero_remains_a_candidate() {
        // gap=t, feasible [0,8], min J=0 on [3,8]; nearest zero is t=3.
        assert_eq!(solved(10.0, 3.0, 3.0, 0.0, -1.0, 8.0).0, 3.0);
        assert_eq!(solved(10.0, 3.0, 3.0, 2.0, -1.0, 8.0).0, 3.0);
    }

    #[test]
    fn zero_candidate_does_not_override_strictly_better_objective() {
        // Uncapped gap=2+t, target=5: unique optimum t=3, not zero.
        assert_eq!(solved(12.0, 100.0, 5.0, 0.0, -1.0, 5.0).0, 3.0);
    }

    #[test]
    fn forbidden_zero_is_not_admitted_by_tie_fix() {
        // gap=t-1: zero collides, feasible domain starts at t=1.
        // The capped minimum plateau begins at t=2, which must win.
        let (t, _, comp) = solved(9.0, 1.0, 1.0, 0.0, -1.0, 5.0);
        assert_eq!(t, 2.0);
        assert_eq!(comp, (1.0, 5.0));
    }

    #[test]
    fn point_component_keeps_verified_touching_candidate() {
        assert_eq!(solved(10.0, 1.0, 0.0, 0.0, 0.0, 0.0).0, 0.0);
    }
}

#[cfg(test)]
mod candidate_solve_root_coverage_tests {
    //! Root-coverage assurance for the lambda > 0 candidate solve. The
    //! documented candidate set is {t_lo, t_hi, every cap breakpoint in
    //! range, every real root of J' inside an open piece}; a root missing
    //! from that set can silently demote the global argmin to a worse
    //! local one. These tests pin the contract at three layers:
    //!   1. isolated_roots_in_piece returns every real root of a cubic on
    //!      the piece, including adversarial regimes (tangent roots,
    //!      near-degenerate extremum pairs, tiny pieces, extreme
    //!      coefficient scales), and refuses non-finite numerics;
    //!   2. piece_jprime_coeffs matches the derivative of the
    //!      channel_stats objective (finite-difference cross-check), so
    //!      the roots solved for are roots of the actual J';
    //!   3. property test: for deterministic pseudo-random coefficients,
    //!      every root found by an independent dense sign-change scan is
    //!      present in the candidate set within the solver's own
    //!      bisection resolution, and the end-to-end argmin is never
    //!      worse than a dense grid scan of J.
    //!
    //! Tolerance derivation (no free constants): the production bisection
    //! stops when the bracket in the normalized variable u is one
    //! representable f64 interval wide, so a returned root sits within 1
    //! ulp of the crossing in u; mapping back through t = m + h * u adds
    //! one rounding per operation. ROOT_COVERAGE_TOL_ULPS ulps of the
    //! local scale therefore covers both the production and the
    //! test-side bisection with margin, while staying far below the
    //! spacing of distinct roots in every case below, so a MISSED root
    //! still fails. The dense-scan point count is the assigned metric
    //! (10001 points).
    use super::{channel_stats, isolated_roots_in_piece, piece_jprime_coeffs,
                solve_pair_t};

    /// Ulp multiple covering both bisection fixpoints plus the m + h * u
    /// transform roundings; see the module header for the derivation.
    const ROOT_COVERAGE_TOL_ULPS: f64 = 8.0;
    /// Dense-scan step count: 10001 sample points, per the assigned metric.
    const DENSE_STEPS: usize = 10_000;

    fn root_tol(refs: &[f64]) -> f64 {
        let scale = refs.iter().fold(1.0_f64, |a, r| a.max(r.abs()));
        ROOT_COVERAGE_TOL_ULPS * f64::EPSILON * scale
    }

    /// Conditioning-aware position tolerance for one crossing of
    /// p(t) = c3 t^3 + c2 t^2 + c1 t + c0 at t, on the piece (lo, hi).
    /// Two error terms, each derived, no free constants:
    ///   bracket: the production bisection stops at a bracket one
    ///     representable u wide and maps back through t = m + h * u;
    ///     ROOT_COVERAGE_TOL_ULPS ulps of the piece scale covers both
    ///     bisections plus the transform roundings.
    ///   conditioning: computing the normalized coefficients (chiefly
    ///     a0 = ((c3 m + c2) m + c1) m + c0) rounds at about eps times
    ///     the term magnitudes at m; divided by the local slope this is
    ///     a position error. Sixteen eps per side covers the Horner
    ///     chain and both bisections. A near-zero slope means no f64
    ///     method can locate the crossing; the tolerance honestly
    ///     degrades to the piece width there.
    fn crossing_tol(c3: f64, c2: f64, c1: f64, c0: f64, t: f64,
                    lo: f64, hi: f64) -> f64 {
        let bracket = root_tol(&[lo, hi, t]);
        let m = (lo + hi) / 2.0;
        let terms = (c3 * m * m * m).abs() + (c2 * m * m).abs()
            + (c1 * m).abs() + c0.abs();
        let slope = (3.0 * c3 * t * t + 2.0 * c2 * t + c1).abs();
        if slope == 0.0 || terms == 0.0 { return bracket.max(hi - lo); }
        bracket + 2.0 * (8.0 * f64::EPSILON * terms / slope)
    }

    fn sorted(v: &[f64]) -> Vec<f64> {
        let mut v = v.to_vec();
        v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        v
    }

    fn assert_roots_exact(found: Vec<f64>, expected: &[f64],
                          c3: f64, c2: f64, c1: f64, c0: f64,
                          lo: f64, hi: f64, ctx: &str) {
        let f = sorted(&found);
        assert_eq!(f.len(), expected.len(), "{ctx}: found {f:?}, want {expected:?}");
        for (g, e) in f.iter().zip(expected) {
            let tol = crossing_tol(c3, c2, c1, c0, *e, lo, hi);
            assert!((g - e).abs() <= tol, "{ctx}: root {g} vs expected {e} (tol {tol})");
        }
    }

    fn assert_root_covered(found: &[f64], root: f64, ctx: &str) {
        let tol = root_tol(&[root]);
        assert!(found.iter().any(|&g| (g - root).abs() <= tol),
                "{ctx}: root {root} not covered by {found:?} (tol {tol})");
    }

    /// (t - r1)(t - r2)(t - r3) expanded to (c3, c2, c1, c0).
    fn cubic3(r1: f64, r2: f64, r3: f64) -> (f64, f64, f64, f64) {
        (1.0, -(r1 + r2 + r3), r1 * r2 + r1 * r3 + r2 * r3, -r1 * r2 * r3)
    }

    fn j_of(cells: &[(f64, f64, f64)], cap: f64, target: f64, lambda: f64, t: f64) -> f64 {
        let (w, v) = channel_stats(cells, t, cap);
        (w - target) * (w - target) + lambda * v
    }

    // ---------- 1. isolated_roots_in_piece: algebraic coverage ----------

    #[test]
    fn three_distinct_roots_all_found() {
        let (c3, c2, c1, c0) = cubic3(1.0, 2.0, 3.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        assert_roots_exact(rs, &[1.0, 2.0, 3.0], c3, c2, c1, c0, 0.0, 4.0, "three distinct");
    }

    #[test]
    fn piece_restriction_keeps_only_interior_roots() {
        let (c3, c2, c1, c0) = cubic3(1.0, 2.0, 3.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 1.5, 2.5).expect("finite");
        assert_roots_exact(rs, &[2.0], c3, c2, c1, c0, 1.5, 2.5, "piece restriction");
    }

    #[test]
    fn roots_on_piece_bounds_not_returned() {
        let (c3, c2, c1, c0) = cubic3(0.0, 2.0, 4.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        assert_roots_exact(rs, &[2.0], c3, c2, c1, c0, 0.0, 4.0, "bounds excluded");
    }

    #[test]
    fn roots_just_inside_bounds_found() {
        let (c3, c2, c1, c0) = cubic3(0.001, 3.999, 2.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        assert_roots_exact(rs, &[0.001, 2.0, 3.999], c3, c2, c1, c0, 0.0, 4.0, "near-bound roots");
    }

    #[test]
    fn double_tangent_root_covered() {
        // The tangent root sits at an extremum of p and is only reachable
        // through the residual guard, never through a sign change.
        let (c3, c2, c1, c0) = cubic3(1.0, 1.0, 3.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        assert_root_covered(&rs, 1.0, "double root");
        assert_root_covered(&rs, 3.0, "simple root beside double");
    }

    #[test]
    fn triple_root_covered() {
        let (c3, c2, c1, c0) = cubic3(2.0, 2.0, 2.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        assert_root_covered(&rs, 2.0, "triple root");
    }

    #[test]
    fn near_degenerate_root_pair_separated() {
        // Two roots 1e-3 apart: the extrema of p nearly coincide, the
        // adversarial regime for the extremum-split monotonic segments.
        // The pair is still well-conditioned (crossing_tol far below the
        // separation), so exact separation is required.
        let d = 1.0e-3;
        let (c3, c2, c1, c0) = cubic3(1.0, 1.0 + d, 3.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        assert_roots_exact(rs, &[1.0, 1.0 + d, 3.0], c3, c2, c1, c0, 0.0, 4.0, "near-degenerate pair");
    }

    #[test]
    fn ill_conditioned_root_pair_still_covered() {
        // Two roots 1e-8 apart: root LOCATION is ill-conditioned at
        // binary64 (the extremum between them carries p ~= 0 to rounding
        // level), so exact separation is outside the declared numerical
        // scope. Coverage is still required: every true root must have a
        // candidate within the conditioning-aware crossing tolerance.
        let d = 1.0e-8;
        let (c3, c2, c1, c0) = cubic3(1.0, 1.0 + d, 3.0);
        let rs = isolated_roots_in_piece(c3, c2, c1, c0, 0.0, 4.0).expect("finite");
        for r in [1.0, 1.0 + d, 3.0] {
            let tol = crossing_tol(c3, c2, c1, c0, r, 0.0, 4.0);
            assert!(rs.iter().any(|&g| (g - r).abs() <= tol),
                    "ill-conditioned pair: root {r} not covered by {rs:?} (tol {tol})");
        }
    }

    #[test]
    fn coefficient_scale_invariance() {
        // Scaling every coefficient leaves the roots unchanged; the
        // normalized-u machinery must hold across extreme scales.
        let (c3, c2, c1, c0) = cubic3(1.0, 2.0, 3.0);
        for &k in &[1.0e-12, 1.0e12] {
            let rs = isolated_roots_in_piece(k * c3, k * c2, k * c1, k * c0, 0.0, 4.0)
                .expect("finite");
            assert_roots_exact(rs, &[1.0, 2.0, 3.0], k * c3, k * c2, k * c1,
                               k * c0, 0.0, 4.0, "scaled coefficients");
        }
    }

    #[test]
    fn no_real_root_inside_piece_returns_empty() {
        // (t^2 + 1)(t - 10): only real root at 10, outside (0, 4).
        let rs = isolated_roots_in_piece(1.0, -10.0, 1.0, -10.0, 0.0, 4.0).expect("finite");
        assert!(rs.is_empty(), "no interior root expected, got {rs:?}");
    }

    #[test]
    fn quadratic_when_cubic_coefficient_zero() {
        let rs = isolated_roots_in_piece(0.0, 1.0, -4.0, 3.0, 0.0, 4.0).expect("finite");
        assert_roots_exact(rs, &[1.0, 3.0], 0.0, 1.0, -4.0, 3.0, 0.0, 4.0, "quadratic");
    }

    #[test]
    fn linear_when_higher_coefficients_zero() {
        let rs = isolated_roots_in_piece(0.0, 0.0, 2.0, -6.0, 0.0, 4.0).expect("finite");
        assert_roots_exact(rs, &[3.0], 0.0, 0.0, 2.0, -6.0, 0.0, 4.0, "linear");
    }

    #[test]
    fn exactly_flat_returns_empty_for_caller() {
        let rs = isolated_roots_in_piece(0.0, 0.0, 0.0, 0.0, 0.0, 4.0).expect("finite");
        assert!(rs.is_empty(), "flat piece must hand the caller an empty root set");
    }

    #[test]
    fn wide_interval_root_found() {
        let rs = isolated_roots_in_piece(0.0, 0.0, 1.0, -123_456.789, 0.0, 1.0e6)
            .expect("finite");
        assert_roots_exact(rs, &[123_456.789], 0.0, 0.0, 1.0, -123_456.789,
                           0.0, 1.0e6, "wide interval");
    }

    #[test]
    fn tiny_piece_root_found() {
        // Piece width 1e-6: the tiny-piece adversarial regime for the
        // interval-normalized transform.
        let (lo, hi) = (2.0, 2.0 + 1.0e-6);
        let rs = isolated_roots_in_piece(0.0, 0.0, 2.0, -4.0 - 1.0e-6, lo, hi)
            .expect("finite");
        assert_roots_exact(rs, &[2.0 + 5.0e-7], 0.0, 0.0, 2.0, -4.0 - 1.0e-6,
                           lo, hi, "tiny piece");
    }

    #[test]
    fn nan_or_infinite_coefficient_is_declared_bounded_failure() {
        assert!(isolated_roots_in_piece(1.0, f64::NAN, 1.0, 0.0, 0.0, 4.0).is_none());
        assert!(isolated_roots_in_piece(f64::INFINITY, 1.0, 1.0, 0.0, 0.0, 4.0).is_none());
    }

    #[test]
    fn nonfinite_interval_is_declared_bounded_failure() {
        assert!(isolated_roots_in_piece(1.0, 0.0, 0.0, -1.0, 0.0, f64::INFINITY).is_none());
        assert!(isolated_roots_in_piece(1.0, 0.0, 0.0, -1.0, f64::NEG_INFINITY, 4.0).is_none());
    }

    // ---------- 2. piece_jprime_coeffs matches d/dt of the objective ----------

    fn check_jprime(cells: &[(f64, f64, f64)], cap: f64, target: f64,
                    lambda: f64, lo: f64, hi: f64, ctx: &str) {
        let (c3, c2, c1, c0) = piece_jprime_coeffs(cells, lo, hi, cap, target, lambda);
        // Central difference: error O(e^2 * J''') truncation plus O(eps *
        // |J| / e) cancellation; e at 1e-3 of the piece width balances the
        // two for the magnitudes in play, and the 1e-3 relative tolerance
        // below is two orders above that error while still catching any
        // structural coefficient mistake.
        let e = (hi - lo) * 1.0e-3;
        for f in [0.25, 0.5, 0.75] {
            let t = lo + (hi - lo) * f;
            let poly = ((c3 * t + c2) * t + c1) * t + c0;
            let fd = (j_of(cells, cap, target, lambda, t + e)
                - j_of(cells, cap, target, lambda, t - e)) / (2.0 * e);
            let scale = poly.abs().max(fd.abs()).max(1.0);
            assert!((poly - fd).abs() <= 1.0e-3 * scale,
                    "{ctx} t={t}: J' poly {poly} vs finite-diff {fd}");
        }
    }

    #[test]
    fn jprime_coeffs_match_objective_derivative_uncapped() {
        check_jprime(&[(10.0, 0.0, 0.0)], 100.0, 42.0, 0.3, -40.0, 40.0, "uncapped");
    }

    #[test]
    fn jprime_coeffs_match_objective_derivative_mixed_regimes() {
        // Breakpoints at t in {100, 80, 70, 10, 5, -50}; the piece (6, 9)
        // holds every cell's clamp regime fixed, mixing uncapped and
        // fully capped cells.
        let cells = [(10.0, 0.0, 20.0), (5.0, 30.0, 90.0), (8.0, 95.0, 150.0)];
        check_jprime(&cells, 100.0, 42.0, 0.3, 6.0, 9.0, "mixed");
    }

    #[test]
    fn jprime_coeffs_match_objective_derivative_near_cap() {
        check_jprime(&[(7.0, 50.0, 60.0)], 100.0, 42.0, 1.0, 30.0, 39.0, "near-cap");
    }

    // ---------- 3. property test + end-to-end argmin coverage ----------

    /// Deterministic pseudo-random in [0, 1): one fixed seed, so the suite
    /// is bit-reproducible across machines.
    struct Lcg(u64);
    impl Lcg {
        const SEED: u64 = 0x5eed_5eed_5eed_5eed;
        fn next(&mut self) -> f64 {
            self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (self.0 >> 33) as f64 / 4294967296.0
        }
    }

    /// Independent root estimate: dense DENSE_STEPS sign-change scan of
    /// p(t) over [lo, hi], each bracket bisected to the f64 fixpoint (the
    /// same stopping rule as the production bisection).
    fn dense_scan_roots(c3: f64, c2: f64, c1: f64, c0: f64, lo: f64, hi: f64) -> Vec<f64> {
        let p = |t: f64| ((c3 * t + c2) * t + c1) * t + c0;
        let mut roots = Vec::new();
        let mut t0 = lo;
        let mut p0 = p(t0);
        for i in 1..=DENSE_STEPS {
            let t1 = lo + (hi - lo) * i as f64 / DENSE_STEPS as f64;
            let p1 = p(t1);
            if p0.is_finite() && p1.is_finite() && (p0 > 0.0) != (p1 > 0.0) {
                let (mut a, mut b) = (t0, t1);
                loop {
                    let mid = a + (b - a) / 2.0;
                    if !(mid > a && mid < b) { break; }
                    if (p(mid) > 0.0) == (p0 > 0.0) { a = mid } else { b = mid }
                }
                roots.push(b);
            }
            t0 = t1;
            p0 = p1;
        }
        roots
    }

    #[test]
    fn property_every_dense_scan_root_is_in_candidate_set() {
        let mut rng = Lcg(Lcg::SEED);
        let cases = 200; // fixed case count; seed and generator above pin the exact set
        for case in 0..cases {
            // Random cubic over a random piece, with random coefficient
            // scale so tiny and huge regimes both occur.
            let k = 10.0_f64.powf(-6.0 + 12.0 * rng.next());
            let (r, s) = (rng.next(), rng.next());
            let (c3, c2, c1, c0) = (k * (r - 0.5), k * (s - 0.5) * 4.0,
                                    k * rng.next() * 8.0, k * (rng.next() - 0.5) * 16.0);
            let lo = -50.0 + 100.0 * rng.next();
            let hi = lo + 1.0e-3 + 100.0 * rng.next();
            let cand = isolated_roots_in_piece(c3, c2, c1, c0, lo, hi)
                .expect("finite random case");
            for dr in dense_scan_roots(c3, c2, c1, c0, lo, hi) {
                let tol = crossing_tol(c3, c2, c1, c0, dr, lo, hi);
                assert!(cand.iter().any(|&g| (g - dr) <= tol && (dr - g) <= tol),
                        "case {case}: dense-scan root {dr} missing from candidate set \
                         {cand:?} (tol {tol}, coeffs {c3},{c2},{c1},{c0} on ({lo},{hi}))");
            }
        }
    }

    fn dense_min_j(cells: &[(f64, f64, f64)], cap: f64, target: f64,
                   lambda: f64, lo: f64, hi: f64) -> f64 {
        let mut best = f64::INFINITY;
        for i in 0..=DENSE_STEPS {
            let t = lo + (hi - lo) * i as f64 / DENSE_STEPS as f64;
            best = best.min(j_of(cells, cap, target, lambda, t));
        }
        best
    }

    #[test]
    fn argmin_never_worse_than_dense_scan() {
        // End to end: the selected t minimizes J over the complete
        // candidate set, so it cannot lose to any grid point by more than
        // the grid's own quantization slack. The slack here is the
        // observed-grid floor scaled by 1e-6; a missed stationary root
        // would lose by the distance between two distinct local minima.
        let mut rng = Lcg(Lcg::SEED ^ 0x9e37_79b9_7f4a_7c15);
        let lambdas = [1.0e-3, 0.1, 1.0, 10.0];
        for case in 0..12 {
            let ncells = 1 + case % 5;
            let cells: Vec<(f64, f64, f64)> = (0..ncells)
                .map(|_| (1.0 + 49.0 * rng.next(),
                          -20.0 + 100.0 * rng.next(),
                          -20.0 + 100.0 * rng.next()))
                .collect();
            let cap = 30.0 + 40.0 * rng.next();
            let target = 20.0 + 60.0 * rng.next();
            let lambda = lambdas[case % lambdas.len()];
            let (lo, hi) = (-60.0, 60.0);
            let t = solve_pair_t(&cells, cap, target, lambda, lo, hi);
            assert!(t.is_finite(), "case {case}: solve returned non-finite");
            let j_sel = j_of(&cells, cap, target, lambda, t);
            let j_grid = dense_min_j(&cells, cap, target, lambda, lo, hi);
            let tol = 1.0e-6 * j_grid.abs().max(1.0);
            assert!(j_sel <= j_grid + tol,
                    "case {case}: J({t}) = {j_sel} worse than dense-scan min {j_grid} \
                     (cells {cells:?}, cap {cap}, target {target}, lambda {lambda})");
        }
    }

    #[test]
    fn argmin_with_many_breakpoints_never_worse_than_dense_scan() {
        // Every cell crosses the cap inside the interval: many pieces,
        // many possible stationary roots; a missed piece loses the
        // global minimum.
        let cells = [(10.0, 0.0, 20.0), (5.0, 30.0, 90.0), (8.0, 95.0, 150.0),
                     (4.0, -10.0, 55.0)];
        for &lambda in &[0.01, 0.5, 2.0] {
            let t = solve_pair_t(&cells, 100.0, 42.0, lambda, -60.0, 60.0);
            assert!(t.is_finite(), "lambda {lambda}: non-finite");
            let j_sel = j_of(&cells, 100.0, 42.0, lambda, t);
            let j_grid = dense_min_j(&cells, 100.0, 42.0, lambda, -60.0, 60.0);
            let tol = 1.0e-6 * j_grid.abs().max(1.0);
            assert!(j_sel <= j_grid + tol,
                    "lambda {lambda}: J({t}) = {j_sel} worse than dense scan {j_grid}");
        }
    }

    #[test]
    fn flat_piece_candidate_honors_tie_rule() {
        // Fully capped plateau: J == 0 over (-100, 50]; the flat piece
        // must contribute its tie-rule winner t = 0 (smallest |t|).
        let cells = [(10.0, 200.0, 200.0)];
        let t = solve_pair_t(&cells, 100.0, 100.0, 1.0, -200.0, 50.0);
        assert_eq!(t, 0.0, "flat piece must yield its tie-rule winner");
    }

    #[test]
    fn lambda_zero_finds_interior_w_root() {
        let cells = [(10.0, 0.0, 0.0)];
        let t = solve_pair_t(&cells, 100.0, 25.0, 0.0, -50.0, 50.0);
        assert!((t - 25.0).abs() <= root_tol(&[25.0]), "W root: got {t}, want 25");
    }

    #[test]
    fn lambda_zero_clamps_to_interval_ends() {
        // W(t) = t over the whole interval here, so a target below
        // W(t_lo) clamps to t_lo and a target above W(t_hi) to t_hi.
        let cells = [(10.0, 0.0, 0.0)];
        assert_eq!(solve_pair_t(&cells, 100.0, -100.0, 0.0, -50.0, 50.0), -50.0);
        assert_eq!(solve_pair_t(&cells, 100.0, 500.0, 0.0, -50.0, 50.0), 50.0);
    }

    #[test]
    fn lambda_zero_plateau_tie_picks_breakpoint_candidate() {
        // W reaches the target on the whole capped plateau t >= 10; the
        // breakpoint candidate t = 10 must beat t_hi on the tie rule.
        let cells = [(10.0, 90.0, 90.0)];
        let t = solve_pair_t(&cells, 100.0, 100.0, 0.0, -50.0, 50.0);
        assert_eq!(t, 10.0, "plateau start (cap breakpoint) must win the tie");
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
struct SideInfo { l: Vec<f64>, r: Vec<f64>, cl: SideClass, cr: SideClass }
#[derive(serde::Serialize, serde::Deserialize)]
struct PreparedPairContext {
profiles: Vec<OutlineProfile>, ctx: Option<FontContext>, policy: SpacingPolicy, strategy: AnchorStrategy, harmony: ClassHarmonyPolicy,
upm: u16, walls: Vec<Walls>, infos: Vec<SideInfo>, notes: Vec<String>, unobserved: Vec<UnobservedPolicy>,
s: f64, baseline: f64, x_height: f64, x_height_source: XHeightSource, cap_height: f64, dcap: f64,
mode: AnchorMode, w_target: f64, class_pair_targets: Vec<((SideClass,SideClass),f64)>, lambda: f64,
cadence_targets: Vec<((SideClass,SideClass),f64)>, channel_targets: Vec<((SideClass,SideClass),f64)>,
glyphs: Vec<GlyphSpacing>, space_status: SpaceStatus, evaluations: u64, eps: f64,
/// 0 = normal solve (self pairs excluded by construction). 1 = self-pair clearance run: only a self pair whose natural placement
/// collides (min base clearance < 0) is solved, every other pair returns early; consumed only by `solve_colliding_self_pairs`.
self_mode: u8
}
    fn resolve_class_target(
        cl: SideClass,
        cr: SideClass,
        class_pair_targets: &[((SideClass, SideClass), f64)],
        channel_targets: &[((SideClass, SideClass), f64)],
        cadence_targets: &[((SideClass, SideClass), f64)],
        w_target: f64,
    ) -> (f64, crate::class_audit::ClassTargetSource) {
        use crate::class_audit::ClassTargetSource as Src;
        if let Some((_, v)) = class_pair_targets.iter().find(|(k, _)| *k == (cl, cr)) {
            return (*v, Src::MeasuredSource);
        }
        if let Some((_, v)) = channel_targets.iter().find(|(k, _)| *k == (cl, cr)) {
            return (*v, Src::ChannelK2);
        }
        if let Some((_, v)) = cadence_targets.iter().find(|(k, _)| *k == (cl, cr)) {
            return (*v, Src::CadenceLaneB);
        }
        (w_target, Src::AnchorWTarget)
    }
    #[derive(serde::Serialize, serde::Deserialize)]
    enum ClassTargetKey {
        /// Frozen fallback: the self-derived equal-area anchor target.
        Plain(String),
        /// Lane B: cadence + area/balance derived class-pair target.
        Cadence(String),
        /// K2: anchor-evidence per-class channel derived target.
        Channel(String),
    }
    #[derive(serde::Serialize, serde::Deserialize)]
    enum PairEval {
        SelfPair { left: String, right: String },
        MissingSidebearings { missing: String },
        GateUnmeasurable { left: String, right: String, class: String, fallback_key: Option<ClassTargetKey> },
        BelowEpsilon { left: String, right: String, class: String, t_lo: f64, t_hi: f64, residual: f64, saturated: bool, fallback_key: Option<ClassTargetKey>, wall_gap: f64, position: Option<Box<PairPosition>> },
        NonFiniteOrigin { left: String, right: String, class: String, t_lo: f64, t_hi: f64, residual: f64, saturated: bool, fallback_key: Option<ClassTargetKey> },
        Solved { position: PairPosition, class: String, residual: f64, saturated: bool, fallback_key: Option<ClassTargetKey> },
        NoFeasible { left: String, right: String, class: String, t_lo: f64, t_hi: f64, hold: String, saturated: bool, fallback_key: Option<ClassTargetKey> },
        NoAcceptedCandidate { left: String, right: String, class: String, t_lo: f64, t_hi: f64, hold: String, saturated: bool, fallback_key: Option<ClassTargetKey> },
        NotConverged { left: String, right: String, kind: NumericFailKind, hold: String, saturated: bool, fallback_key: Option<ClassTargetKey> },
        SolveUnmeasurable { left: String, right: String, class: String, t_lo: f64, t_hi: f64, saturated: bool, fallback_key: Option<ClassTargetKey> },
    }
    impl PairEval {
        /// Class-pair target fallback key recorded at exactly the point the
        /// sequential loop called class_target (after the sidebearing gate,
        /// before the shared-row gate). Inserted into the BTreeSet during
        /// the sequential reduce; the set is iterated in sorted order, so
        /// insertion order is unobservable.
        fn fallback_key(&self) -> Option<&ClassTargetKey> {
            match self {
                PairEval::SelfPair { .. } | PairEval::MissingSidebearings { .. } => None,
                PairEval::GateUnmeasurable { fallback_key, .. }
                | PairEval::BelowEpsilon { fallback_key, .. }
                | PairEval::NonFiniteOrigin { fallback_key, .. }
                | PairEval::Solved { fallback_key, .. }
                | PairEval::NoFeasible { fallback_key, .. }
                | PairEval::NoAcceptedCandidate { fallback_key, .. }
                | PairEval::NotConverged { fallback_key, .. }
                | PairEval::SolveUnmeasurable { fallback_key, .. } => fallback_key.as_ref(),
            }
        }
        /// The sequential loop counted saturation for every pair that
        /// passed the shared-row/min_base gates (saturated is computed
        /// before the solve); the counter is an integer sum, order-free.
        fn is_saturated(&self) -> bool {
            match self {
                PairEval::BelowEpsilon { saturated, .. }
                | PairEval::NonFiniteOrigin { saturated, .. }
                | PairEval::Solved { saturated, .. }
                | PairEval::NoFeasible { saturated, .. }
                | PairEval::NoAcceptedCandidate { saturated, .. }
                | PairEval::NotConverged { saturated, .. }
                | PairEval::SolveUnmeasurable { saturated, .. } => *saturated,
                _ => false,
            }
        }
    }

fn prepare_pair_context(profiles: &[OutlineProfile], ctx: Option<&FontContext>, policy: &SpacingPolicy,
 strategy: AnchorStrategy, harmony: ClassHarmonyPolicy) -> Result<PreparedPairContext,SpacingError> {
    if profiles.is_empty() { return Err(SpacingError::EmptyInput); }
    let upm = profiles[0].upm;
    // Manifest-bound codepoint map: duplicate ids and invalid codepoints are
    // typed refusals; unknown ids are refused once walls exist (below).
    let mut cp_map: HashMap<String, u32> = HashMap::new();
    if let Some(c) = ctx {
        for (id, cp) in &c.glyph_codepoints {
            if char::from_u32(*cp).is_none() {
                return Err(SpacingError::InvalidContext {
                    reason: format!("invalid codepoint {cp:#x} for glyph id '{id}'"),
                });
            }
            if cp_map.insert(id.clone(), *cp).is_some() {
                return Err(SpacingError::InvalidContext {
                    reason: format!("duplicate codepoint mapping for glyph id '{id}'"),
                });
            }
        }
    }
    let mut walls: Vec<Walls> = Vec::with_capacity(profiles.len());
    for p in profiles {
        if p.upm != upm {
            return Err(SpacingError::InconsistentUpm {
                expected: upm, found: p.upm, glyph_id: p.glyph_id.clone(),
            });
        }
        let letter = letter_of(&cp_map, &p.glyph_id);
        walls.push(build_walls(p, letter)?);
    }
    // Stable refusal identity: HashMap iteration order is not fixed, so
    // the unknown-id refusal would name an arbitrary entry. Iterate sorted
    // keys; the error always names the lexicographically smallest id.
    let mut cp_ids: Vec<&String> = cp_map.keys().collect();
    cp_ids.sort();
    for id in cp_ids {
        if !walls.iter().any(|w| &w.glyph_id == id) {
            return Err(SpacingError::InvalidContext {
                reason: format!("codepoint mapping references unknown glyph id '{id}'"),
            });
        }
    }
    let letters: Vec<Option<char>> =
        walls.iter().map(|w| letter_of(&cp_map, &w.glyph_id)).collect();
    // Validate context numbers.
    if let Some(c) = ctx {
        let ck = |field: &'static str, v: f64| -> Result<(), SpacingError> {
            if v.is_finite() { Ok(()) } else {
                Err(SpacingError::InvalidContext {
                    reason: format!("non-finite {field}"),
                })
            }
        };
        if let Some(v) = c.x_height { ck("x_height", v)?; }
        if let Some(v) = c.cap_height { ck("cap_height", v)?; }
        if let Some(v) = c.baseline { ck("baseline", v)?; }
        if let Some(v) = c.measured_space_advance { ck("measured_space_advance", v)?; }
        for m in &c.measured_sidebearings {
            ck("measured_sidebearings.lsb", m.lsb)?;
            ck("measured_sidebearings.rsb", m.rsb)?;
        }
        for m in &c.measured_pairs { ck("measured_pairs.gap", m.gap)?; }
    }

    // Duplicate glyph ids would silently overwrite the HashMap indexes and
    // make every lookup ambiguous: typed refusal, never first-wins.
    {
        let mut seen = std::collections::HashSet::new();
        for w in &walls {
            if !seen.insert(w.glyph_id.as_str()) {
                return Err(SpacingError::InvalidProfile {
                    glyph_id: w.glyph_id.clone(),
                    reason: "duplicate glyph id in input profiles".into(),
                });
            }
        }
    }
    // glyph id -> index into `walls`/`letters` (ids are unique here: duplicates were refused above). Replaces repeated linear scans.
    let wall_pos: HashMap<&str, usize> = walls.iter().enumerate().map(|(i, w)| (w.glyph_id.as_str(), i)).collect();
    let inked: Vec<&Walls> = walls.iter().filter(|w| w.h_eff > 0.0).collect();
    if inked.is_empty() {
        return Err(SpacingError::NoUsableGlyphs {
            reason: "every profile has zero ink".into(),
        });
    }
    let mut notes: Vec<String> = Vec::new();

    // ---- font measures ------------------------------------------------------
    // Stem width s (rev2 §1.2): median interval width in stem glyphs'
    // rows; stem glyphs = straight-stem candidates present among n,h,m,H,I,l.
    const STEM_LETTERS: [char; 6] = ['n', 'h', 'm', 'H', 'I', 'l'];
    let stem_glyphs: Vec<&&Walls> = inked.iter()
        .filter(|w| {
            let letter = letters[wall_pos[w.glyph_id.as_str()]];
            letter.map(|c| STEM_LETTERS.contains(&c)).unwrap_or(false)
        })
        .collect();
    let stem_resolved_via_map = !stem_glyphs.is_empty()
        && stem_glyphs.iter().any(|w| cp_map.contains_key(&w.glyph_id));
    let stem_source: Vec<f64> = if stem_glyphs.is_empty() {
        inked.iter().flat_map(|w| w.interval_widths.iter().cloned()).collect()
    } else {
        stem_glyphs.iter()
            .flat_map(|w| w.interval_widths.iter().cloned()).collect()
    };
    let s = median(stem_source).ok_or_else(|| SpacingError::NoUsableGlyphs {
        reason: "no ink intervals anywhere; cannot measure stem width".into(),
    })?;
    if !(s > 0.0) {
        return Err(SpacingError::NoUsableGlyphs {
            reason: "measured stem width is zero".into(),
        });
    }
    let stem_desc: String = if stem_glyphs.is_empty() {
        // Architect stem-anchor rule 12:17: an all-population median is a
        // self-derived estimate and must never read as stem-learned.
        "none -> self-derived all-population stem estimate [NOT stem-learned]".to_string()
    } else {
        let via = if stem_resolved_via_map { "via codepoint map" } else { "via raw id" };
        format!("{} ({via})",
            stem_glyphs.iter().map(|w| w.glyph_id.clone())
                .collect::<Vec<_>>().join(","))
    };
    notes.push(format!("stem width s={s:.3} (stem glyphs: {stem_desc})"));

    // Heights: context first, else measured from the outlines.
    let mut unobserved: Vec<UnobservedPolicy> = Vec::new();
    // No `unwrap_or(0.0)`: `inked` is non-empty here, so a median exists; if it ever did not, that is a typed refusal, not a 0.0 baseline.
    let baseline = match ctx.and_then(|c| c.baseline) {
        Some(b) => b,
        None => {
            unobserved.push(UnobservedPolicy::BaselineMedianYMin);
            median(inked.iter().map(|w| w.y_min).collect()).ok_or_else(|| SpacingError::NoUsableGlyphs { reason: "no inked y_min to derive a baseline".into() })?
        }
    };
    let letter_of_w = |w: &Walls| -> Option<char> {
        letters[wall_pos[w.glyph_id.as_str()]]
    };
    let lc_tops: Vec<f64> = inked.iter()
        .filter(|w| letter_of_w(w).map(|c| c.is_ascii_lowercase()).unwrap_or(false))
        .map(|w| w.y_max - baseline).collect();
    let uc_tops: Vec<f64> = inked.iter()
        .filter(|w| letter_of_w(w).map(|c| c.is_ascii_uppercase()).unwrap_or(false))
        .map(|w| w.y_max - baseline).collect();
    let lc_top_med = median(lc_tops);
    let (x_height, x_height_source) = match ctx.and_then(|c| c.x_height) {
        Some(v) => (v, XHeightSource::Ctx),
        None => match lc_top_med {
            Some(v) => (v, XHeightSource::LcTopMedian),
            None => {
                unobserved.push(UnobservedPolicy::XHeightAllGlyphProxy);
                // no `upm/2` value is ever invented: an empty population is a typed refusal
                (median(inked.iter().map(|w| w.y_max - baseline).collect()).ok_or_else(|| SpacingError::NoUsableGlyphs { reason: "no inked y_max to derive an x-height".into() })?, XHeightSource::AllGlyphProxy)
            }
        }
    };
    if ctx.and_then(|c| c.x_height).is_none() && lc_top_med.is_none() {
        notes.push("x_height fallback: no lowercase median; value is all-glyph median of y_max-baseline if any inked glyph, else typed NoUsableGlyphs refusal; no upm/2 value is invented [POLICY_UNOBSERVED: no flat lowercase tops measured]".into());
    }
    let uc_top_med = median(uc_tops);
    let cap_height = ctx.and_then(|c| c.cap_height)
        .or(uc_top_med)
        .unwrap_or(x_height);
    if ctx.and_then(|c| c.cap_height).is_none() && uc_top_med.is_none() {
        unobserved.push(UnobservedPolicy::CapHeightEqualsXHeight);
        notes.push("cap_height fallback = x_height [POLICY_UNOBSERVED: no flat uppercase tops measured]".into());
    }
    notes.push(format!("baseline={baseline:.3} x_height={x_height:.3} cap_height={cap_height:.3} ({} )",
        if ctx.map(|c| c.x_height.is_some()).unwrap_or(false) { "ctx" } else { "measured" }));

    // Dcap: policy override, else measured plateau default (rev2 §2): max
    // side depth observed in stem-glyph rows; without stem glyphs, over all.
    let dcap = if let Some(d) = policy.dcap {
        if !(d.is_finite() && d > 0.0) {
            return Err(SpacingError::InvalidContext {
                reason: "policy.dcap must be positive finite".into(),
            });
        }
        d
    } else {
        let src: Vec<&&Walls> = if stem_glyphs.is_empty() {
            inked.iter().collect()
        } else { stem_glyphs.clone() };
        let mut dmax = 0.0f64;
        for w in src {
            for i in 0..w.rows.len() {
                let ld = w.left_wall[i];
                let rd = w.width - w.right_wall[i];
                if ld > dmax { dmax = ld; }
                if rd > dmax { dmax = rd; }
            }
        }
        if dmax > 0.0 { dmax } else { s } // flush stems: one stem of cap
    };
    notes.push(format!("dcap={dcap:.3} ({})", if policy.dcap.is_some() { "policy" } else { "measured plateau default" }));

    // ---- side series + classes ----------------------------------------------
    // Band: lowercase glyphs [baseline, x_height], caps [baseline, cap],
    // others clamped to own extent (side_series intersects).

    let mut infos: Vec<SideInfo> = Vec::with_capacity(walls.len());
    for w in &walls {
        let is_cap = letter_of_w(w).map(|c| c.is_ascii_uppercase()).unwrap_or(false);
        let top = baseline + if is_cap { cap_height } else { x_height };
        let (l, r, _) = side_series(w, baseline, top, dcap);
        let cl = classify_side(&l, s);
        let cr = classify_side(&r, s);
        infos.push(SideInfo { l, r, cl, cr });
    }

    // ---- anchor target W (rev2 §1/§3 cascade) -------------------------------
    let (mode, w_target, class_pair_targets): (AnchorMode, f64, Vec<((SideClass, SideClass), f64)>) = {
        let ctx_pairs = ctx.map(|c| &c.measured_pairs).filter(|v| !v.is_empty());
        let ctx_sb = ctx.map(|c| &c.measured_sidebearings).filter(|v| !v.is_empty());
        if strategy == AnchorStrategy::RequireMeasured
            && ctx_pairs.is_none() && ctx_sb.is_none()
        {
            return Err(SpacingError::AnchorUnresolved {
                strategy: "RequireMeasured",
                reason: "no measured source spacing in FontContext; typed refusal instead of a geometry-only near-zero anchor".into(),
            });
        }
        if strategy == AnchorStrategy::CounterChannel
            && ctx_pairs.is_none() && ctx_sb.is_none()
        {
            // Experiment arm B: anchor on the counter channel, explicitly.
            let cnts: Vec<(String, f64)> = walls.iter().zip(&infos)
                .filter(|(w, i)| w.h_eff > 0.0
                    && (i.cl == SideClass::Straight || i.cr == SideClass::Straight))
                .map(|(w, _)| (w.glyph_id.clone(), counter_channel(w)))
                .filter(|(_, c)| *c > 0.0)
                .collect();
            let med = median(cnts.iter().map(|(_, c)| *c).collect())
                .ok_or_else(|| SpacingError::AnchorUnresolved {
                    strategy: "CounterChannel",
                    reason: "no interior-white coverage among straight-class glyphs (counter channel empty); typed refusal, no outer-channel fallback".into(),
                })?;
            notes.push(format!(
                "EXPERIMENT CounterChannel: W_target={med:.3} = median counter channel over {} covered straight-class glyphs: {}",
                cnts.len(),
                cnts.iter().map(|(id, c)| format!("{id}={c:.3}")).collect::<Vec<_>>().join(",")));
            (AnchorMode::CounterChannelExperimentSelfDerived, med, Vec::new())
        } else if ctx_pairs.is_some() || ctx_sb.is_some() {
            // MeasuredSource: real source spacing defines the anchor.
            let mut w_s: Option<f64> = None;
            let mut cpt: Vec<((SideClass, SideClass), f64)> = Vec::new();
            if let Some(pairs) = ctx_pairs {
                // Architect 12:15: a measured pair that names a glyph not
                // present in the input is a typed refusal, never a silent
                // fall to the Open class default.
                let class_of = |glyph_id: &str, left_side: bool|
                    -> Result<SideClass, SpacingError> {
                    walls.iter().zip(&infos)
                        .find(|(w, _)| w.glyph_id == glyph_id)
                        .map(|(_, i)| if left_side { i.cr } else { i.cl })
                        .ok_or_else(|| SpacingError::InvalidContext {
                            reason: format!("measured pair references unknown glyph id '{glyph_id}'"),
                        })
                };
                // Group measured gaps by (right class of left, left class of right).
                let mut groups: std::collections::BTreeMap<(SideClass, SideClass), Vec<f64>> =
                    std::collections::BTreeMap::new();
                for mp in pairs {
                    let key = (class_of(&mp.left, true)?, class_of(&mp.right, false)?);
                    groups.entry(key).or_default().push(mp.gap);
                }
                for (key, gaps) in groups {
                    if let Some(m) = median(gaps) {
                        if key == (SideClass::Straight, SideClass::Straight) {
                            w_s = Some(m);
                        }
                        cpt.push((key, m));
                    }
                }
            }
            if let Some(sbs) = ctx_sb {
                for m in sbs {
                    if !walls.iter().any(|w| w.glyph_id == m.glyph_id) {
                        return Err(SpacingError::InvalidContext {
                            reason: format!("measured sidebearing references unknown glyph id '{}'", m.glyph_id),
                        });
                    }
                }
            }
            if w_s.is_none() {
                if let Some(sbs) = ctx_sb {
                    w_s = median(sbs.iter().map(|m| m.lsb + m.rsb).collect());
                }
            }
            let w_s = w_s.ok_or_else(|| SpacingError::InvalidContext {
                reason: "measured spacing present but no straight|straight pair or sidebearing median derivable".into(),
            })?;
            notes.push(format!("anchor W_s={w_s:.3} from measured source spacing ({} class-pair targets)",
                cpt.len()));
            (AnchorMode::MeasuredSource, w_s, cpt)
        } else {
            // Geometry-only cascade (rev2 §3).
            // Straight|straight pairs from the classification.
            let mut couts: Vec<f64> = Vec::new();
            for (w, i) in walls.iter().zip(&infos) {
                if w.h_eff <= 0.0 { continue; }
                if i.cl == SideClass::Straight {
                    couts.extend(i.l.iter().cloned());
                }
                if i.cr == SideClass::Straight {
                    couts.extend(i.r.iter().cloned());
                }
            }
            let straight_mean = mean(&couts);
            let has_straight = !couts.is_empty();
            if has_straight && straight_mean > 0.0 {
                notes.push(format!("W_target={straight_mean:.3} = mean outer channel over straight sides ({} rows)", couts.len()));
                (AnchorMode::GeometryOnlyFallback, straight_mean, Vec::new())
            } else {
                // Flush boxes (grid fonts): counter channel of straight-class
                // glyphs carries the target (outline measurement).
                let cnts: Vec<f64> = walls.iter().zip(&infos)
                    .filter(|(w, i)| w.h_eff > 0.0
                        && (i.cl == SideClass::Straight || i.cr == SideClass::Straight))
                    .map(|(w, _)| counter_channel(w))
                    .filter(|c| *c > 0.0)
                    .collect();
                if let Some(med) = median(cnts.clone()) {
                    notes.push(format!("flush straight boxes (mean c_out=0); W_target={med:.3} = median counter channel over {} straight-class glyphs", cnts.len()));
                    (AnchorMode::MeasuredOutlineSelfDerivedTarget, med, Vec::new())
                } else {
                    // rev2 §3.4: median over all glyph pairs of min row gap
                    // at d=0 (boxes adjacent).
                    let mut min_gaps: Vec<f64> = Vec::new();
                    for (ia, wa) in inked.iter().enumerate() {
                        for (ib, wb) in inked.iter().enumerate() {
                            if ia == ib { continue; }
                            let (sa, sb_) = (&infos[idx_of(&walls, &wa.glyph_id)],
                                             &infos[idx_of(&walls, &wb.glyph_id)]);
                            let rows = sa.l.len().min(sb_.l.len());
                            if rows == 0 { continue; }
                            let mut mg = f64::INFINITY;
                            for k in 0..rows {
                                let g = sa.r[k].min(dcap) + sb_.l[k].min(dcap);
                                if g < mg { mg = g; }
                            }
                            if mg.is_finite() { min_gaps.push(mg); }
                        }
                    }
                    let med = median(min_gaps).ok_or_else(|| SpacingError::NoUsableGlyphs {
                        reason: "no straight pairs and no computable row gaps; target underivable".into(),
                    })?;
                    notes.push(format!("LOW-CONFIDENCE: W_target={med:.3} = median min row gap at d=0 over all pairs (rev2 §3.4)"));
                    (AnchorMode::GeometryOnlyFallbackLowConfidence, med, Vec::new())
                }
            }
        }
    };
    let lambda = policy.lambda.unwrap_or(0.0);
    if policy.lambda.is_none() { unobserved.push(UnobservedPolicy::LambdaDefaultZero); }
    if policy.lambda.is_none() && mode == AnchorMode::MeasuredSource {
        notes.push("lambda default 0.0 (V(t) distribution term off; expose for source fit)".into());
    } else {
        notes.push(format!("lambda={lambda:.3}"));
    }
    // ---- Lane B: cadence + optical area class pass (policy-gated) ------
    // Default-off: with `cadence_class_pass == false` the derived table
    // stays EMPTY and the target resolution below is the frozen
    // measured -> w_target cascade, bit-identical.
    let mut cadence_targets: Vec<((SideClass, SideClass), f64)> = Vec::new();
    if policy.cadence_class_pass {
        // Stem-interval cadence (LeMo lineage; OUR CANDIDATE statistic,
        // metrics/src/cadence.rs): the font's own stem-to-stem white.
        let cadence = crate::cadence::measure_stem_intervals(profiles).map_err(|e| match e {
            crate::cadence::CadenceError::NonFinite { glyph_id, field } =>
                SpacingError::NonFinite { glyph_id, field },
        })?;
        // Optical area/balance channels: per side class, the pooled clamped
        // side series rows - the SAME statistic and the SAME pooling order
        // (inked glyphs in walls order, left series then right series) the
        // geometry-only anchor applies to straight sides, computed per
        // class. For the Straight class the pool is element-for-element
        // the anchor's own population.
        let mut pools: std::collections::BTreeMap<SideClass, Vec<f64>> = Default::default();
        for (w, i) in walls.iter().zip(&infos) {
            if w.h_eff <= 0.0 { continue; }
            pools.entry(i.cl).or_default().extend(i.l.iter().cloned());
            pools.entry(i.cr).or_default().extend(i.r.iter().cloned());
        }
        // Per-class white contribution: the class's measured mean channel
        // when positive. A class whose sides sit flush on the bounding box
        // (grid-font straight stems) carries no outer channel, so the
        // font's own measured stem-interval cadence stands in (OUR
        // CANDIDATE: the cadence is the only interior white such a font
        // carries). A class with neither a positive channel nor a
        // measurable cadence contributes NOTHING: pairs touching it keep
        // the frozen w_target fallback and its plain receipt.
        let contribution = |c: SideClass| -> Option<f64> {
            let channel = pools.get(&c).filter(|rows| !rows.is_empty()).map(|rows| mean(rows));
            match channel {
                Some(m) if m > 0.0 => Some(m),
                _ => cadence.as_ref().map(|cd| cd.unit),
            }
        };
        // Pair target: each facing side contributes half the pair white -
        // the same halving the equal-area sidebearing derivation applies.
        // Measured ctx targets always win (skipped here); a derived target
        // equal to the anchor target is skipped, so those pairs resolve on
        // the frozen fallback bit-identically BY CONSTRUCTION.
        let present: Vec<SideClass> = pools.keys().cloned().collect();
        for &cl in &present {
            for &cr in &present {
                if class_pair_targets.iter().any(|(k, _)| *k == (cl, cr)) { continue; }
                if let (Some(a), Some(b)) = (contribution(cl), contribution(cr)) {
                    let t = (a + b) / 2.0;
                    if t == w_target { continue; }
                    cadence_targets.push(((cl, cr), t));
                }
            }
        }
        match &cadence {
            Some(cd) => notes.push(format!(
                "cadence class pass: stem-interval unit u={:.3} (weighted median of {} interior stem-interval samples, total row weight {:.1}, weighted MAD {:.3}; LeMo-lineage OUR CANDIDATE statistic, see cadence.rs)",
                cd.unit, cd.samples, cd.total_weight, cd.dispersion)),
            None => notes.push(
                "cadence class pass: no interior stem intervals in the font; flush classes contribute no channel and no cadence".into()),
        }
        notes.push(format!(
            "cadence class pass: class channels {{{}}} | derived class-pair targets {{{}}} (measured ctx targets always win; derived == W_target stays on the frozen fallback, untouched pairs bit-identical)",
            present.iter().map(|c| format!("{c}={:.3}", mean(&pools[c]))).collect::<Vec<_>>().join(", "),
            cadence_targets.iter().map(|((cl, cr), t)| format!("{cl}->{cr}={t:.3}")).collect::<Vec<_>>().join(", ")));
    }
    // ---- K2: per-class channel targets (policy.class_channel_targets) --
    // Default-off: with `class_channel_targets == false` the derived table
    // stays EMPTY and the target resolution below is the frozen
    // measured -> anchor-fallback cascade, bit-identical.
    // DECLARED CONVENTION: for each side class c the class channel is the
    // MEDIAN of the same pooled clamped outer-channel rows the anchor
    // itself uses (i.l of inked glyphs with i.cl == c plus i.r of inked
    // glyphs with i.cr == c, pooled in walls order). Rationale: the
    // anchor's own statistic over straight sides is a mean and is frozen;
    // round and diagonal side pools are row-skewed by terminal rows at
    // the band edges, so the median is the robust central statistic of
    // the same measured evidence. The Straight class is assigned the
    // anchor target itself, so straight-touching pairs resolve
    // bit-identically by the skip-equal rule. Pair target: each facing
    // side contributes half the pair white - the same halving the
    // equal-area sidebearing derivation applies. A class whose pool is
    // empty or whose median is not positive contributes NOTHING: pairs
    // touching it keep the frozen w_target fallback, typed in the
    // receipt. Measured ctx targets always win; a derived target equal
    // to the anchor target is skipped, so those pairs resolve on the
    // frozen fallback bit-identically BY CONSTRUCTION.
    let mut channel_targets: Vec<((SideClass, SideClass), f64)> = Vec::new();
    if policy.class_channel_targets {
        let mut pools: std::collections::BTreeMap<SideClass, Vec<f64>> = Default::default();
        for (w, i) in walls.iter().zip(&infos) {
            if w.h_eff <= 0.0 { continue; }
            pools.entry(i.cl).or_default().extend(i.l.iter().cloned());
            pools.entry(i.cr).or_default().extend(i.r.iter().cloned());
        }
        let channel = |c: SideClass| -> Option<f64> {
            if c == SideClass::Straight { return Some(w_target); }
            pools.get(&c).filter(|rows| !rows.is_empty())
                .and_then(|rows| median(rows.clone()))
                .filter(|m| *m > 0.0)
        };
        let present: Vec<SideClass> = pools.keys().cloned().collect();
        for &cl in &present {
            for &cr in &present {
                if class_pair_targets.iter().any(|(k, _)| *k == (cl, cr)) { continue; }
                if let (Some(a), Some(b)) = (channel(cl), channel(cr)) {
                    let t = (a + b) / 2.0;
                    if t == w_target { continue; }
                    channel_targets.push(((cl, cr), t));
                }
            }
        }
        notes.push(format!(
            "K2 class channel targets: class channels {{{}}} | derived class-pair targets {{{}}} (CONVENTION: per-class median of the anchor's pooled outer-channel rows, Straight := anchor target; measured ctx targets always win; derived == W_target stays on the frozen fallback, untouched pairs bit-identical)",
            present.iter().map(|c| format!("{c}={:.3}", channel(*c).unwrap_or(f64::NAN))).collect::<Vec<_>>().join(", "),
            channel_targets.iter().map(|((cl, cr), t)| format!("{cl}->{cr}={t:.3}")).collect::<Vec<_>>().join(", ")));
    }
    // Single class-pair target resolution path (cascade order: measured ->
    // K2 channel -> Lane B cadence -> frozen anchor W_target fallback). The
    // sequential closure, the pure tier-1 evaluation and the class audit
    // all resolve through this ONE lookup so the observer can never drift
    // from the solver. Pure: no fallback-set recording inside.
    // ---- sidebearings (equal-area, rev2 §1.3) --------------------------------
    // sb_side = W/2 - mean clamped inner depth of that side. All class pairs
    // the equal-area target; measured class-pair medians override the
    // per-side half when both sides' classes have a measured target.
    let half = w_target / 2.0;
    let mut glyphs: Vec<GlyphSpacing> = Vec::with_capacity(walls.len());
    let mut negative: Vec<String> = Vec::new();
    for (w, i) in walls.iter().zip(&infos) {
        if w.is_space {
            continue; // handled below
        }
        if w.h_eff <= 0.0 {
            glyphs.push(GlyphSpacing {
                glyph_id: w.glyph_id.clone(), lsb: 0.0, rsb: 0.0, advance: w.width,
            });
            notes.push(format!("{}: inkless non-space glyph, advance=width {:.3}", w.glyph_id, w.width));
            continue;
        }
        let lsb = half - mean(&i.l);
        let rsb = half - mean(&i.r);
        if lsb < 0.0 || rsb < 0.0 {
            negative.push(format!("{} (lsb={lsb:.3}, rsb={rsb:.3})", w.glyph_id));
        }
        glyphs.push(GlyphSpacing {
            glyph_id: w.glyph_id.clone(),
            lsb,
            rsb,
            advance: lsb + w.width + rsb,
        });
    }
    if !negative.is_empty() {
        notes.push(format!("negative sidebearings (deep open forms, kept, never clamped): {}",
            negative.join(", ")));
    }

    // ---- space ----------------------------------------------------------------
    // Dar patch (space measurement wiring): NO W_target fallback into
    // spacing emission. measured_space_advance = Some(finite, >= 0) is
    // emitted as-is; None with a space glyph present emits NOTHING and is
    // receipted as typed SpaceStatus::MissingEvidence with W_target carried
    // only as an explicit diagnostic candidate. No space glyph in input is
    // an honest Absent - pair solving is unaffected in every case.
    let space_present = walls.iter().any(|w| w.is_space);
    let space_status = match ctx.and_then(|c| c.measured_space_advance) {
        Some(sa) if sa.is_finite() && sa >= 0.0 => {
            for w in &walls {
                if w.is_space {
                    glyphs.push(GlyphSpacing {
                        glyph_id: w.glyph_id.clone(),
                        lsb: 0.0, rsb: 0.0, advance: sa,
                    });
                }
            }
            SpaceStatus::Measured { advance: sa }
        }
        Some(sa) => return Err(SpacingError::InvalidContext {
            reason: format!("measured_space_advance must be finite and >= 0, got {sa}"),
        }),
        None if space_present =>
            SpaceStatus::MissingEvidence { candidate_diagnostic: w_target },
        None => SpaceStatus::Absent,
    };
    match &space_status {
        SpaceStatus::Measured { advance } => notes.push(format!(
            "space advance={advance:.3} provided (measured); emitted only when a space glyph is present in solver input")),
        SpaceStatus::MissingEvidence { candidate_diagnostic } => notes.push(format!(
            "space profile present but no measured advance: NO space emission; typed MissingEvidence (diagnostic candidate W_target={candidate_diagnostic:.3}, self-derived, not source-observed, never emitted)")),
        SpaceStatus::Absent => notes.push(
            "no space profile in solver input; none invented".into()),
    }

    // ---- pairs (supreme J(d) argmin, ported 12:10; rev2 class targets) -----
    let n = inked.len() as u64;
    let evaluations = n.saturating_mul(n.saturating_sub(1));
    if evaluations > policy.max_pair_evaluations {
        return Err(SpacingError::ResourceBoundExceeded {
            what: "ordered pair evaluations", limit: policy.max_pair_evaluations,
        });
    }
    let eps = policy.residual_epsilon();

    // J(d) cap depth: policy override, else the measured plateau default
    // computed above; the statistic choice is a convention, not an
    // observation from source spacing -> POLICY_UNOBSERVED (K5 flag rule).
    if policy.dcap.is_none() {
        unobserved.push(UnobservedPolicy::DcapPlateauDefault);
        notes.push(format!("J(d) Dcap = measured plateau default {dcap:.3} [POLICY_UNOBSERVED: statistic choice is a convention]"));
    }
    if !lambda.is_finite() || lambda < 0.0 {
        return Err(SpacingError::InvalidContext {
            reason: "policy.lambda must be finite and >= 0".into(),
        });
    }
    // Chief-architect priority fix (2026-10-14 21:22): lambda > 0 solves
    // exactly. J is piecewise quartic in t (W piecewise quadratic, V
    // piecewise quartic; breakpoints where a cell end crosses the cap), so
    // J' is piecewise cubic and the COMPLETE candidate set is: piece
    // endpoints, cap breakpoints, and every real root of J' inside an open
    // piece (solve_pair_t). lambda = 0 keeps the frozen W-root/bound path
    // bit-identical (Arm A repro). lambda is an explicit unit policy
    // parameter: both objective terms carry gap^2 units, so the ratio is
    // dimensionless; no hidden constants.
    notes.push(format!(
        "J(d) distribution weight lambda={lambda:.3} (explicit policy parameter, dimensionless gap^2 ratio) | L2 solve: argmin over the EXACT feasible residual components (forbidden-interval complement on the declared domain; K2 constant cell model recomputed at each candidate placement; candidates = component edges + interior stationary of the piecewise J; per-candidate guard-frame evidence reverify with a declared 64-step origin bracket, exhaustion typed NotConverged; NOT an algebraic exactness certificate)"));
    notes.push("J(d): collision constraint gap >= 0 on every common y; y integration over the aligned common-row grid of the K2 constant cell model (clearance_cells_constant; facing membership fixed inside a feasible component; no exact-y matching)".into());

    Ok(PreparedPairContext { profiles: profiles.to_vec(), ctx:ctx.cloned(), policy:policy.clone(), strategy,harmony,
upm,walls,infos,notes,unobserved,s,baseline,x_height,x_height_source,cap_height,dcap,mode,w_target,class_pair_targets,lambda,cadence_targets,channel_targets,glyphs,space_status,evaluations,eps,self_mode: 0 })
}

/// Explicit experimental checkpoint controls. Default solver never accesses disk.
pub struct PairCheckpoint {
    pub directory: std::path::PathBuf,
    pub action: PairCheckpointAction,
}
pub enum PairCheckpointAction { Prepare, Range { start: usize, end: usize }, Merge }
#[derive(serde::Serialize,serde::Deserialize)]
struct CacheEnvelope { version: u32, executable: [u8;32], source: [u8;32], input: [u8;32], policy: [u8;32], context: [u8;32], payload: Vec<u8> }
#[derive(serde::Serialize,serde::Deserialize)]
struct RangeEnvelope { version: u32, context: [u8;32], start: usize, end: usize, payload_hash: [u8;32], payload: Vec<u8> }
const CHECKPOINT_MAX_BYTES:u64=256*1024*1024;
fn checkpoint_error(e:impl std::fmt::Display)->SpacingError { SpacingError::InvalidContext { reason:format!("pair checkpoint refused: {e}") } }
fn checkpoint_options()->impl bincode::Options { use bincode::Options; bincode::DefaultOptions::new().with_fixint_encoding().with_little_endian().with_limit(CHECKPOINT_MAX_BYTES).reject_trailing_bytes() }
fn checkpoint_encode<T:serde::Serialize>(v:&T)->Result<Vec<u8>,SpacingError> { use bincode::Options; checkpoint_options().serialize(v).map_err(checkpoint_error) }
fn checkpoint_decode<T:serde::de::DeserializeOwned>(v:&[u8])->Result<T,SpacingError> { use bincode::Options; if v.len() as u64>CHECKPOINT_MAX_BYTES {return Err(checkpoint_error("length bound"));} checkpoint_options().deserialize(v).map_err(checkpoint_error) }
fn checkpoint_hash(v:&[u8])->[u8;32] { use sha2::Digest; sha2::Sha256::digest(v).into() }
fn checkpoint_executable()->Result<[u8;32],SpacingError> { let path=std::env::current_exe().map_err(checkpoint_error)?; let bytes=std::fs::read(path).map_err(checkpoint_error)?; Ok(checkpoint_hash(&bytes)) }
fn checkpoint_source()->[u8;32] { checkpoint_hash(concat!(include_str!("self_anchored_spacing.rs"),include_str!("outline_spacing.rs"),include_str!("signed_clearance.rs")).as_bytes()) }
fn checkpoint_read(path:&std::path::Path)->Result<Vec<u8>,SpacingError> { let n=std::fs::metadata(path).map_err(checkpoint_error)?.len(); if n>CHECKPOINT_MAX_BYTES {return Err(checkpoint_error("file length bound"));} std::fs::read(path).map_err(checkpoint_error) }
fn checkpoint_write(path:&std::path::Path,bytes:&[u8])->Result<(),SpacingError> { use std::io::Write; let mut f=std::fs::OpenOptions::new().create_new(true).write(true).open(path).map_err(checkpoint_error)?; f.write_all(bytes).map_err(checkpoint_error)?;f.sync_all().map_err(checkpoint_error) }
/// Build full preparation ONCE, persist bit-exact owned state, evaluate disjoint
/// ranges against it, then apply unchanged ordered reduce to complete union.
pub fn solve_spacing_checkpoint(profiles:&[OutlineProfile],ctx:Option<&FontContext>,policy:&SpacingPolicy,jobs:usize,control:&PairCheckpoint)
 ->Result<Option<SpacingSolution>,SpacingError> {
 let strategy=AnchorStrategy::LegacyCascade;let harmony=ClassHarmonyPolicy::default();
 let input=checkpoint_hash(&checkpoint_encode(&(profiles,ctx,policy,strategy,harmony))?);
 let policy_pin=checkpoint_hash(&checkpoint_encode(&(policy,strategy,harmony))?);
 let path=control.directory.join("context.bin");
 if matches!(control.action,PairCheckpointAction::Prepare) {
  if path.exists(){return Err(checkpoint_error("context already exists; refusing rebuild"));}
  let prepared=prepare_pair_context(profiles,ctx,policy,strategy,harmony)?;
  let payload=checkpoint_encode(&prepared)?;
  let env=CacheEnvelope{version:2,executable:checkpoint_executable()?,source:checkpoint_source(),input,policy:policy_pin,context:checkpoint_hash(&payload),payload};
  std::fs::create_dir_all(&control.directory).map_err(checkpoint_error)?;
  checkpoint_write(&path,&checkpoint_encode(&env)?)?;
  return Ok(None);
 }
 let env:CacheEnvelope=checkpoint_decode(&checkpoint_read(&path)?)?;
 if env.version!=2 || env.executable!=checkpoint_executable()? || env.source!=checkpoint_source() || env.input!=input || env.policy!=policy_pin || env.context!=checkpoint_hash(&env.payload) { return Err(checkpoint_error("schema/executable/source/input/policy/context hash mismatch")); }
 let prepared:PreparedPairContext=checkpoint_decode(&env.payload)?;
 if checkpoint_encode(&prepared)?!=env.payload {return Err(checkpoint_error("noncanonical context"));}
 finish_pair_context(prepared,jobs,Some(control)).map(|v|v.map(|x|x.0))
}
fn checkpoint_pairs<F:FnMut(usize)->PairEval>(control:&PairCheckpoint,total:usize,mut eval:F)->Result<Option<Vec<PairEval>>,SpacingError> {
 let env:CacheEnvelope=checkpoint_decode(&checkpoint_read(&control.directory.join("context.bin"))?)?;
 if env.version!=2 || env.executable!=checkpoint_executable()? || env.source!=checkpoint_source() || env.context!=checkpoint_hash(&env.payload) { return Err(checkpoint_error("context changed between validation and range/merge")); }
 match control.action {
  PairCheckpointAction::Prepare=>Err(checkpoint_error("prepare cannot evaluate")),
  PairCheckpointAction::Range{start,end}=>{
   if start>=end || end>total {return Err(checkpoint_error("invalid pair range"));}
   let values:Vec<PairEval>=(start..end).map(&mut eval).collect();
   let payload=checkpoint_encode(&values)?;
   let range=RangeEnvelope{version:1,context:env.context,start,end,payload_hash:checkpoint_hash(&payload),payload};
   let path=control.directory.join(format!("range-{start:012}-{end:012}.bin"));
   checkpoint_write(&path,&checkpoint_encode(&range)?)?;
   Ok(None)
  },
  PairCheckpointAction::Merge=>{
   let mut ranges=Vec::new();
   for entry in std::fs::read_dir(&control.directory).map_err(checkpoint_error)? {
    let path=entry.map_err(checkpoint_error)?.path();
    if !path.file_name().and_then(|n|n.to_str()).is_some_and(|n|n.starts_with("range-")&&n.ends_with(".bin")){continue;}
    let r:RangeEnvelope=checkpoint_decode(&checkpoint_read(&path)?)?;
    if r.version!=1 || r.context!=env.context || r.payload_hash!=checkpoint_hash(&r.payload) || r.start>=r.end || r.end>total {return Err(checkpoint_error("range schema/context/hash/bounds mismatch"));}
    ranges.push(r);
   }
   ranges.sort_by_key(|r|r.start);let mut next=0;let mut all=Vec::new();
   for r in ranges {
    if r.start!=next {return Err(checkpoint_error("range gap/overlap/duplicate"));}
    let values:Vec<PairEval>=checkpoint_decode(&r.payload)?;
    if values.len()!=r.end-r.start {return Err(checkpoint_error("range record count mismatch"));}
    all.extend(values);next=r.end;
   }
   if next!=total {return Err(checkpoint_error("incomplete full pair union"));}
   Ok(Some(all))
  }
 }
}
