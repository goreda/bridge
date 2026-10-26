//! Simultaneous-contrast gap floor (post-solve spacing pass).
//!
//! Simultaneous contrast: equal white gaps read unequal when the ink mass
//! bordering the gap differs. A gap flanked by two heavy stems reads
//! tighter than the same gap flanked by thin strokes, so a solver that
//! equalizes the geometric gap alone ships optically unequal spacing.
//! This pass raises, per pair, a minimum gap floor calibrated from the
//! font's own render measurements and widens only the pairs that fall
//! below it. Pairs already at or above their floor are returned
//! bit-identical; every raise and every typed failure is receipted.
//!
//! CONVENTION declarations (no hidden numbers):
//!
//! 1. FACING WEIGHT. The contrast stimulus of a gap is the ink mass
//!    immediately bordering it. It is measured from the font's own
//!    render plane (the scanline profiles): on every row where both
//!    sides carry ink, the facing intervals are the left glyph's
//!    rightmost interval left of the gap and the right glyph's leftmost
//!    interval right of the gap; the row's facing weight is the mean of
//!    the two interval widths, aggregated over rows by row weight (an
//!    area-weighted mean). Stroke widths are translation-invariant, so
//!    the measure reads the render plane directly.
//!
//! 2. CALIBRATION. The floor slope k is measured, never set:
//!    k = median(wall_gap / facing_weight) over the solved straight-side
//!    to straight-side pairs - the font's own canonical spacing evidence
//!    (the same side class the anchor cascade derives its target from).
//!    When no straight-to-straight solved pair exists, the population
//!    falls back to all solved pairs with positive gap and facing
//!    weight, receipted as AllPairs. When no pair carries usable
//!    evidence at all, the pass is a typed no-op (population None), not
//!    an invented constant.
//!
//! 3. FLOOR. floor_i = k * facing_weight_i. A pair is raised only when
//!    its verified minimum gap at the solved placement is strictly
//!    below its floor; the new placement is the smallest verified origin
//!    whose measured minimum gap reaches the floor, found by an
//!    invariant bisection (gap(lo) < floor <= gap(hi)) to the declared
//!    tolerance - the spacing policy's residual epsilon, already a
//!    declared policy value, reused here so this pass introduces no
//!    numeric parameter of its own.
//!
//! 4. SEARCH BOUND. The outward walk is bounded by the pair itself:
//!    origin + deficit + sum of the two ink widths + 1 unit (the same
//!    pair-derived bound shape as the integer export guard). The
//!    ulp-step verification budget at the bisection boundary is 64
//!    steps, matching the solver's declared origin-bracket budget.
//!
//! Frame rule: all verification runs in the export frame through
//! signed_clearance::evidence_at with the exporter's own translations
//! (x_translation = lsb - ink_xmin), so a verified raise is safe exactly
//! where the export guard re-checks it. Fallback/tier-2 pairs are out
//! of scope: they are collision rescues, not optical placements, and
//! stay untouched.

use std::collections::HashMap;

use crate::outline_spacing::{align_pair_rows, OutlineProfile};
use crate::self_anchored_spacing::{channel_stats, PairPosition, SideClass};
use crate::signed_clearance as sc;

/// Declared ulp-step budget at the verified boundary (convention 4).
const STEP_BUDGET: usize = 64;

/// One pair raised to the measured contrast floor (typed receipt row).
#[derive(Debug, Clone)]
pub struct ContrastFloorAdjustment {
    pub left: String,
    pub right: String,
    /// Verified minimum gap at the solved placement (before).
    pub gap_before: f64,
    /// Verified minimum gap at the raised placement (after).
    pub gap_after: f64,
    /// The measured floor applied: k * facing_weight.
    pub floor: f64,
    /// Area-weighted mean width of the intervals bordering the gap.
    pub facing_weight: f64,
    pub origin_before: f64,
    pub origin_after: f64,
}

/// Why a pair could not be raised to its floor (typed; the pair ships
/// unchanged with its solver-verified placement).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContrastFloorFailKind {
    /// Export-frame evidence unmeasurable at a queried placement.
    EvidenceUnmeasurable,
    /// The measured gap never reached the floor inside the pair-derived
    /// search bound.
    FloorUnreachable,
    /// The declared ulp-step budget was exhausted at the verification
    /// boundary.
    StepBudgetExhausted,
    /// A solver-internal lookup (profile, metrics, classes) was missing:
    /// typed, never a panic.
    MissingGeometry,
}

impl ContrastFloorFailKind {
    pub fn code(&self) -> &'static str {
        match self {
            ContrastFloorFailKind::EvidenceUnmeasurable => "evidence_unmeasurable",
            ContrastFloorFailKind::FloorUnreachable => "floor_unreachable",
            ContrastFloorFailKind::StepBudgetExhausted => "step_budget_exhausted",
            ContrastFloorFailKind::MissingGeometry => "missing_geometry",
        }
    }
}

/// One pair the floor pass left unchanged under a typed failure.
#[derive(Debug, Clone)]
pub struct ContrastFloorFailure {
    pub left: String,
    pub right: String,
    pub kind: ContrastFloorFailKind,
}

/// Which population calibrated the floor slope k (typed receipt).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalibrationPopulation {
    /// Solved straight-side to straight-side pairs (canonical evidence).
    StraightStraight,
    /// All solved pairs with positive gap and facing weight (fallback).
    AllPairs,
    /// No usable evidence: the pass is a typed no-op.
    None,
}

impl CalibrationPopulation {
    pub fn code(&self) -> &'static str {
        match self {
            CalibrationPopulation::StraightStraight => "straight-straight",
            CalibrationPopulation::AllPairs => "all-pairs",
            CalibrationPopulation::None => "none",
        }
    }
}

/// The measured calibration behind every floor in one run.
#[derive(Debug, Clone)]
pub struct ContrastFloorCalibration {
    /// k = median(wall_gap / facing_weight) over the population.
    /// None exactly when population is None.
    pub k: Option<f64>,
    pub population: CalibrationPopulation,
    /// Number of pair ratios in the calibration population.
    pub population_pairs: usize,
}

/// Full typed outcome of the pass.
#[derive(Debug, Clone)]
pub struct ContrastFloorReport {
    /// The candidate pairs, raises applied, input order preserved.
    pub pairs: Vec<PairPosition>,
    pub adjustments: Vec<ContrastFloorAdjustment>,
    pub failures: Vec<ContrastFloorFailure>,
    pub calibration: ContrastFloorCalibration,
    /// Pairs verified at or above their floor and returned bit-identical.
    pub untouched: usize,
}

impl ContrastFloorReport {
    /// One deterministic receipt line for policy_derivation.
    pub fn receipt_line(&self) -> String {
        match self.calibration.k {
            Some(k) => format!(
                "contrast-floor: k={k:.6} = median(wall_gap/facing_weight) over {} ({} pair ratios) [CONVENTION: floor = k * facing_weight, simultaneous contrast measured from the font's own render plane] | {} raised, {} at/above floor unchanged, {} typed failure(s)",
                self.calibration.population.code(),
                self.calibration.population_pairs,
                self.adjustments.len(),
                self.untouched,
                self.failures.len(),
            ),
            None => format!(
                "contrast-floor: typed no-op (calibration population {}); no pair touched",
                self.calibration.population.code(),
            ),
        }
    }
}

/// Median with the engine's own convention (sorted, mean of the two
/// middle values on even counts). NaN-free input by construction.
fn median(mut v: Vec<f64>) -> Option<f64> {
    if v.is_empty() { return None; }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = v.len();
    if n % 2 == 1 { Some(v[n / 2]) } else { Some((v[n / 2 - 1] + v[n / 2]) / 2.0) }
}

/// Area-weighted mean width of the intervals bordering the pair's gap at
/// the given placement (convention 1). None when no row carries facing
/// intervals on both sides.
fn facing_weight(
    l: &OutlineProfile,
    r: &OutlineProfile,
    l_tr: f64,
    r_tr: f64,
    origin: f64,
) -> Option<f64> {
    let (mut acc, mut wsum) = (0.0_f64, 0.0_f64);
    for row in &align_pair_rows(l, r) {
        if row.left.is_empty() || row.right.is_empty() { continue; }
        let right_leftmost = row.right.iter().map(|ri| ri.left).fold(f64::INFINITY, f64::min) + r_tr + origin;
        let left_rightmost = row.left.iter().map(|li| li.right).fold(f64::NEG_INFINITY, f64::max) + l_tr;
        let facing_l = row.left.iter()
            .filter(|li| li.left + l_tr < right_leftmost)
            .max_by(|a, b| a.right.partial_cmp(&b.right).unwrap_or(std::cmp::Ordering::Equal));
        let facing_r = row.right.iter()
            .filter(|ri| ri.right + r_tr + origin > left_rightmost)
            .min_by(|a, b| a.left.partial_cmp(&b.left).unwrap_or(std::cmp::Ordering::Equal));
        if let (Some(fl), Some(fr)) = (facing_l, facing_r) {
            let w_row = ((fl.right - fl.left) + (fr.right - fr.left)) / 2.0;
            if w_row.is_finite() && row.weight.is_finite() && row.weight > 0.0 {
                acc += row.weight * w_row;
                wsum += row.weight;
            }
        }
    }
    if wsum > 0.0 { Some(acc / wsum) } else { None }
}

/// Verified minimum gap at one placement in the export frame.
fn gap_at(
    l: &OutlineProfile,
    r: &OutlineProfile,
    l_tr: f64,
    r_tr: f64,
    origin: f64,
) -> Result<f64, ContrastFloorFailKind> {
    sc::evidence_at(l, r, l_tr, r_tr, origin)
        .map(|e| e.clearance.min_gap)
        .ok_or(ContrastFloorFailKind::EvidenceUnmeasurable)
}

/// Smallest verified origin at/above `origin` whose measured minimum gap
/// reaches `floor`. Invariant bisection: gap(lo) < floor <= gap(hi); the
/// invariant, not monotonicity, is what the result relies on (the facing
/// set can change with distance, so the gap is not proven monotone).
fn widen_to_floor(
    l: &OutlineProfile,
    r: &OutlineProfile,
    l_tr: f64,
    r_tr: f64,
    origin: f64,
    gap0: f64,
    floor: f64,
    tolerance: f64,
) -> Result<(f64, f64), ContrastFloorFailKind> {
    let deficit = floor - gap0;
    if !(deficit.is_finite() && deficit > 0.0) {
        return Ok((origin, gap0)); // nothing to raise (defensive; caller filters)
    }
    // Pair-derived search bound (convention 4): the first-order estimate
    // plus the pair's own ink span.
    let span = (l.bounds[2] - l.bounds[0]) + (r.bounds[2] - r.bounds[0]);
    let limit = origin + deficit + span.ceil() + 1.0;
    let mut lo = origin; // gap(lo) < floor by the caller's measurement
    let mut hi = origin + deficit;
    // Walk out until the high end verifies at/above the floor.
    let mut gap_hi = gap_at(l, r, l_tr, r_tr, hi)?;
    while gap_hi < floor {
        hi += deficit;
        if hi > limit || !hi.is_finite() {
            return Err(ContrastFloorFailKind::FloorUnreachable);
        }
        gap_hi = gap_at(l, r, l_tr, r_tr, hi)?;
    }
    // Invariant bisection to the declared tolerance.
    while hi - lo > tolerance {
        let mid = lo + (hi - lo) / 2.0;
        if !(mid > lo && mid < hi) { break; } // f64 resolution reached
        if gap_at(l, r, l_tr, r_tr, mid)? >= floor { hi = mid; } else { lo = mid; }
    }
    // Verify the result at the boundary; step outward on ulp-scale
    // violations under the declared budget.
    let mut d = hi;
    let mut gap_d = gap_at(l, r, l_tr, r_tr, d)?;
    let mut steps = 0usize;
    while gap_d < floor {
        d = sc::next_up_outward(d).ok_or(ContrastFloorFailKind::StepBudgetExhausted)?;
        steps += 1;
        if steps > STEP_BUDGET {
            return Err(ContrastFloorFailKind::StepBudgetExhausted);
        }
        gap_d = gap_at(l, r, l_tr, r_tr, d)?;
    }
    Ok((d, gap_d))
}

/// Apply the simultaneous-contrast floor to the solved candidate pairs.
///
/// `profiles`, `metrics` (id -> (lsb, rsb, advance)) and `classes`
/// (id -> (left side class, right side class)) are the solver's own
/// lookup maps; `dcap` is the solved objective's depth cap, reused only
/// to recompute the optical-cost receipt of raised pairs; `tolerance` is
/// the spacing policy's residual epsilon (convention 3). Input order is
/// preserved; untouched pairs keep every field bit-identical.
pub fn apply_contrast_floor(
    pairs: Vec<PairPosition>,
    profiles: &HashMap<&str, &OutlineProfile>,
    metrics: &HashMap<&str, (f64, f64, f64)>,
    classes: &HashMap<&str, (SideClass, SideClass)>,
    dcap: f64,
    tolerance: f64,
) -> ContrastFloorReport {
    let noop = |pairs: Vec<PairPosition>, population: CalibrationPopulation| ContrastFloorReport {
        pairs,
        adjustments: Vec::new(),
        failures: Vec::new(),
        calibration: ContrastFloorCalibration { k: None, population, population_pairs: 0 },
        untouched: 0,
    };
    // A non-positive or non-finite tolerance makes the bisection
    // meaningless: typed no-op, never an invented value.
    if !(tolerance.is_finite() && tolerance > 0.0) {
        return noop(pairs, CalibrationPopulation::None);
    }

    // Per-pair geometry at the solved placement.
    struct Measured {
        l_tr: f64,
        r_tr: f64,
        gap: f64,
        facing: f64,
    }
    let mut measured: Vec<Option<Measured>> = Vec::with_capacity(pairs.len());
    let mut pre_failures: Vec<ContrastFloorFailure> = Vec::new();
    for p in &pairs {
        let row = (|| -> Result<Measured, ContrastFloorFailKind> {
            let prof_l = profiles.get(p.left.as_str()).ok_or(ContrastFloorFailKind::MissingGeometry)?;
            let prof_r = profiles.get(p.right.as_str()).ok_or(ContrastFloorFailKind::MissingGeometry)?;
            let m_l = metrics.get(p.left.as_str()).ok_or(ContrastFloorFailKind::MissingGeometry)?;
            let m_r = metrics.get(p.right.as_str()).ok_or(ContrastFloorFailKind::MissingGeometry)?;
            let l_tr = m_l.0 - prof_l.bounds[0];
            let r_tr = m_r.0 - prof_r.bounds[0];
            let gap = gap_at(prof_l, prof_r, l_tr, r_tr, p.origin_distance)?;
            let facing = facing_weight(prof_l, prof_r, l_tr, r_tr, p.origin_distance)
                .ok_or(ContrastFloorFailKind::EvidenceUnmeasurable)?;
            Ok(Measured { l_tr, r_tr, gap, facing })
        })();
        match row {
            Ok(m) => measured.push(Some(m)),
            Err(kind) => {
                pre_failures.push(ContrastFloorFailure { left: p.left.clone(), right: p.right.clone(), kind });
                measured.push(None);
            }
        }
    }

    // Calibration (convention 2): straight-straight ratios first.
    let ratio_of = |i: usize| -> Option<f64> {
        let m = measured[i].as_ref()?;
        if m.gap > 0.0 && m.facing > 0.0 { Some(m.gap / m.facing) } else { None }
    };
    let straight_ratios: Vec<f64> = pairs.iter().enumerate().filter_map(|(i, p)| {
        let cl = classes.get(p.left.as_str())?.1;
        let cr = classes.get(p.right.as_str())?.0;
        if cl == SideClass::Straight && cr == SideClass::Straight { ratio_of(i) } else { None }
    }).collect();
    let (k, population, ratios) = match median(straight_ratios.clone()) {
        Some(k) => (k, CalibrationPopulation::StraightStraight, straight_ratios),
        None => {
            let all: Vec<f64> = (0..pairs.len()).filter_map(ratio_of).collect();
            match median(all.clone()) {
                Some(k) => (k, CalibrationPopulation::AllPairs, all),
                None => return ContrastFloorReport {
                    pairs,
                    adjustments: Vec::new(),
                    failures: pre_failures,
                    calibration: ContrastFloorCalibration { k: None, population: CalibrationPopulation::None, population_pairs: 0 },
                    untouched: 0,
                },
            }
        }
    };

    // Raise the pairs below their measured floor (convention 3).
    let mut out: Vec<PairPosition> = Vec::with_capacity(pairs.len());
    let mut adjustments: Vec<ContrastFloorAdjustment> = Vec::new();
    let mut failures: Vec<ContrastFloorFailure> = pre_failures;
    let mut untouched = 0usize;
    let mut cells_scratch: Vec<(f64, f64, f64)> = Vec::new();
    for (i, p) in pairs.into_iter().enumerate() {
        let m = match measured[i].take() {
            Some(m) => m,
            None => { out.push(p); continue; } // already receipted as failure
        };
        let floor = k * m.facing;
        if !(floor.is_finite() && floor > m.gap) {
            untouched += 1;
            out.push(p); // at/above floor: bit-identical
            continue;
        }
        let prof_l = profiles[p.left.as_str()];
        let prof_r = profiles[p.right.as_str()];
        match widen_to_floor(prof_l, prof_r, m.l_tr, m.r_tr, p.origin_distance, m.gap, floor, tolerance) {
            Ok((new_origin, new_gap)) => {
                // Optical-cost receipt recomputed exactly as the solve
                // callsite does: variance of the capped gap over the
                // constant cells at the verified placement.
                let advance_l = metrics[p.left.as_str()].2;
                let raw_base = prof_l.bounds[2] - prof_r.bounds[0]
                    + metrics[p.left.as_str()].1 + metrics[p.right.as_str()].0;
                let residual = new_origin - advance_l;
                sc::clearance_cells_constant_rows_into(
                    &crate::outline_spacing::align_pair_rows(prof_l, prof_r), raw_base + residual, &mut cells_scratch);
                let cells = &*cells_scratch;
                let (_, var) = channel_stats(&cells, 0.0, dcap);
                adjustments.push(ContrastFloorAdjustment {
                    left: p.left.clone(),
                    right: p.right.clone(),
                    gap_before: m.gap,
                    gap_after: new_gap,
                    floor,
                    facing_weight: m.facing,
                    origin_before: p.origin_distance,
                    origin_after: new_origin,
                });
                out.push(PairPosition {
                    left: p.left,
                    right: p.right,
                    origin_distance: new_origin,
                    wall_gap: new_gap,
                    optical_cost: var,
                    pair_target: p.pair_target,
                    compensated: false,
                });
            }
            Err(kind) => {
                failures.push(ContrastFloorFailure { left: p.left.clone(), right: p.right.clone(), kind });
                out.push(p); // unchanged, solver-verified placement
            }
        }
    }
    ContrastFloorReport {
        pairs: out,
        adjustments,
        failures,
        calibration: ContrastFloorCalibration { k: Some(k), population, population_pairs: ratios.len() },
        untouched,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};
    use crate::self_anchored_spacing::PairPosition;

    fn prof(id: &str, rings: Vec<Vec<[f64; 2]>>) -> OutlineProfile {
        let input = OutlineInput {
            glyph_id: id.to_string(), source_pin: format!("sha256:test:{id}"),
            upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0, rings,
        };
        let pol = ScanPolicy { row_step: 2.0, max_rows: 4000, merge_guard: MERGE_GUARD_UNITS,
                               grid_anchor_y: Some(0.0) };
        profile_outline(&input, pol).expect("profile")
    }
    fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
        vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    }

    /// Two-stem heavy glyph (H-like) and one-stem light glyph (l-like).
    fn heavy(id: &str) -> OutlineProfile {
        prof(id, vec![rect(0.0, 0.0, 100.0, 700.0), rect(300.0, 0.0, 400.0, 700.0)])
    }
    fn light(id: &str) -> OutlineProfile {
        prof(id, vec![rect(0.0, 0.0, 20.0, 700.0)])
    }

    struct Fixture {
        profiles: HashMap<&'static str, OutlineProfile>,
        metrics: HashMap<&'static str, (f64, f64, f64)>,
        classes: HashMap<&'static str, (SideClass, SideClass)>,
    }
    impl Fixture {
        fn prof_refs(&self) -> HashMap<&str, &OutlineProfile> {
            self.profiles.iter().map(|(k, v)| (*k, v)).collect()
        }
    }

    /// H (heavy straight sides), l (light straight sides). Advances carry
    /// the glyphs' own widths plus sidebearings; lsbs/rsbs are zero so
    /// the natural origin equals the advance.
    fn two_glyph_fixture() -> Fixture {
        let mut profiles = HashMap::new();
        profiles.insert("H", heavy("H"));
        profiles.insert("l", light("l"));
        let mut metrics = HashMap::new();
        metrics.insert("H", (0.0, 0.0, 400.0));
        metrics.insert("l", (0.0, 0.0, 20.0));
        let mut classes = HashMap::new();
        classes.insert("H", (SideClass::Straight, SideClass::Straight));
        classes.insert("l", (SideClass::Straight, SideClass::Straight));
        Fixture { profiles, metrics, classes }
    }

    fn pair(l: &str, r: &str, origin: f64) -> PairPosition {
        PairPosition { left: l.into(), right: r.into(),
            origin_distance: origin, wall_gap: 0.0, optical_cost: 0.0, pair_target: None, compensated: false }
    }

    #[test]
    fn heavy_pair_is_raised_light_pair_untouched_bit_identical() {
        let fx = two_glyph_fixture();
        let prefs = fx.prof_refs();
        // H->l solved tight (gap 40 at origin 440), l->H loose (gap 400).
        let tight = pair("H", "l", 440.0);
        let loose = pair("l", "H", 420.0);
        // Sanity: measured gaps at those placements.
        let g_tight = gap_at(prefs["H"], prefs["l"], 0.0, 0.0, 440.0).unwrap();
        let g_loose = gap_at(prefs["l"], prefs["H"], 0.0, 0.0, 420.0).unwrap();
        assert!((g_tight - 40.0).abs() < 1e-9, "tight gap {g_tight}");
        assert!((g_loose - 400.0).abs() < 1e-9, "loose gap {g_loose}");
        let loose_before = loose.clone();
        let report = apply_contrast_floor(
            vec![tight, loose], &prefs,
            &fx.metrics.iter().map(|(k, v)| (*k, *v)).collect(),
            &fx.classes.iter().map(|(k, v)| (*k, *v)).collect(),
            1000.0, 2.0,
        );
        // Calibration: straight-straight, both pairs in the population.
        assert_eq!(report.calibration.population, CalibrationPopulation::StraightStraight);
        assert_eq!(report.calibration.population_pairs, 2);
        let k = report.calibration.k.unwrap();
        // Ratios: 40/((100+20)/2)=0.666..., 400/60=6.666... -> k = median.
        let expected_k = (40.0 / 60.0 + 400.0 / 60.0) / 2.0;
        assert!((k - expected_k).abs() < 1e-9, "k {k} vs {expected_k}");
        // Tight pair: floor = k*60 = 220 > 40 -> raised and verified.
        assert_eq!(report.adjustments.len(), 1);
        let adj = &report.adjustments[0];
        assert_eq!((adj.left.as_str(), adj.right.as_str()), ("H", "l"));
        assert!((adj.floor - 220.0).abs() < 1e-9, "floor {}", adj.floor);
        assert!(adj.gap_after >= adj.floor, "raised gap {} >= floor {}", adj.gap_after, adj.floor);
        assert!(adj.origin_after > adj.origin_before);
        // The raised pair's shipped fields match the adjustment receipt.
        let raised = report.pairs.iter().find(|p| p.left == "H" && p.right == "l").unwrap();
        assert_eq!(raised.origin_distance.to_bits(), adj.origin_after.to_bits());
        assert_eq!(raised.wall_gap.to_bits(), adj.gap_after.to_bits());
        // Loose pair: floor 220 < 400 -> untouched, every field bit-identical.
        let unt = report.pairs.iter().find(|p| p.left == "l" && p.right == "H").unwrap();
        assert_eq!(unt.origin_distance.to_bits(), loose_before.origin_distance.to_bits());
        assert_eq!(unt.wall_gap.to_bits(), loose_before.wall_gap.to_bits());
        assert_eq!(unt.optical_cost.to_bits(), loose_before.optical_cost.to_bits());
        assert_eq!(unt.left, loose_before.left);
        assert_eq!(unt.right, loose_before.right);
        assert!(report.failures.is_empty());
    }

    #[test]
    fn all_pairs_fallback_when_no_straight_straight() {
        let fx = two_glyph_fixture();
        let prefs = fx.prof_refs();
        // Mark every side Round: no straight-straight population exists.
        let classes: HashMap<&str, (SideClass, SideClass)> = [
            ("H", (SideClass::Round, SideClass::Round)),
            ("l", (SideClass::Round, SideClass::Round)),
        ].into_iter().collect();
        let report = apply_contrast_floor(
            vec![pair("H", "l", 440.0)], &prefs,
            &fx.metrics.iter().map(|(k, v)| (*k, *v)).collect(),
            &classes, 1000.0, 2.0,
        );
        assert_eq!(report.calibration.population, CalibrationPopulation::AllPairs);
        assert_eq!(report.calibration.population_pairs, 1);
        // Single ratio: k = gap/facing; floor == measured gap -> untouched.
        assert!(report.adjustments.is_empty());
        assert_eq!(report.untouched, 1);
    }

    #[test]
    fn no_evidence_is_a_typed_noop() {
        let fx = two_glyph_fixture();
        let prefs = fx.prof_refs();
        // Origin where the gap is zero (touching): ratio population empty.
        let touching = pair("H", "l", 400.0);
        let g = gap_at(prefs["H"], prefs["l"], 0.0, 0.0, 400.0).unwrap();
        assert!(g.abs() < 1e-9, "touching gap {g}");
        let before = touching.clone();
        let report = apply_contrast_floor(
            vec![touching], &prefs,
            &fx.metrics.iter().map(|(k, v)| (*k, *v)).collect(),
            &fx.classes.iter().map(|(k, v)| (*k, *v)).collect(),
            1000.0, 2.0,
        );
        assert_eq!(report.calibration.population, CalibrationPopulation::None);
        assert_eq!(report.calibration.k, None);
        assert!(report.adjustments.is_empty());
        let after = &report.pairs[0];
        assert_eq!(after.origin_distance.to_bits(), before.origin_distance.to_bits());
        assert!(report.receipt_line().contains("typed no-op"));
    }

    #[test]
    fn disjoint_heights_fail_typed_and_ship_unchanged() {
        let mut fx = two_glyph_fixture();
        // A glyph whose ink shares no y with H: evidence unmeasurable.
        fx.profiles.insert("dot", prof("dot", vec![rect(0.0, 900.0, 30.0, 1000.0)]));
        fx.metrics.insert("dot", (0.0, 0.0, 30.0));
        fx.classes.insert("dot", (SideClass::Straight, SideClass::Straight));
        let prefs = fx.prof_refs();
        let report = apply_contrast_floor(
            vec![pair("H", "l", 440.0), pair("H", "dot", 430.0)], &prefs,
            &fx.metrics.iter().map(|(k, v)| (*k, *v)).collect(),
            &fx.classes.iter().map(|(k, v)| (*k, *v)).collect(),
            1000.0, 2.0,
        );
        let kinds: Vec<_> = report.failures.iter().map(|f| f.kind).collect();
        assert_eq!(kinds, vec![ContrastFloorFailKind::EvidenceUnmeasurable]);
        let dot = report.pairs.iter().find(|p| p.right == "dot").unwrap();
        assert_eq!(dot.origin_distance.to_bits(), 430.0_f64.to_bits());
    }

    #[test]
    fn deterministic_across_runs() {
        let run = || {
            let fx = two_glyph_fixture();
            let prefs = fx.prof_refs();
            let r = apply_contrast_floor(
                vec![pair("H", "l", 440.0), pair("l", "H", 420.0)], &prefs,
                &fx.metrics.iter().map(|(k, v)| (*k, *v)).collect(),
                &fx.classes.iter().map(|(k, v)| (*k, *v)).collect(),
                1000.0, 2.0,
            );
            r.pairs.iter().map(|p| (p.origin_distance.to_bits(), p.wall_gap.to_bits(), p.optical_cost.to_bits())).collect::<Vec<_>>()
        };
        assert_eq!(run(), run());
    }

    #[test]
    fn invalid_tolerance_is_a_typed_noop() {
        let fx = two_glyph_fixture();
        let prefs = fx.prof_refs();
        let report = apply_contrast_floor(
            vec![pair("H", "l", 440.0)], &prefs,
            &fx.metrics.iter().map(|(k, v)| (*k, *v)).collect(),
            &fx.classes.iter().map(|(k, v)| (*k, *v)).collect(),
            1000.0, 0.0,
        );
        assert_eq!(report.calibration.population, CalibrationPopulation::None);
        assert_eq!(report.pairs[0].origin_distance.to_bits(), 440.0_f64.to_bits());
    }

    /// End-to-end through solve_spacing with a measured-pair anchor
    /// (fixture shape mirrors the engine's hand-computed pair test): two
    /// stems of different weights next to a diagonal v solve to equal
    /// minimum gaps, and simultaneous contrast demands the heavier pair
    /// sit wider. The pass must raise exactly the heavy pair, receipt it,
    /// and leave the light pair bit-identical to the flag-off run.
    #[test]
    fn solve_spacing_raises_heavy_pair_light_pair_bit_identical() {
        use crate::outline_spacing::{InkInterval, ScanRow};
        use crate::self_anchored_spacing::{solve_spacing, FontContext, MeasuredPair, SpacingPolicy};
        let rect = |id: &str, x1: f64| -> OutlineProfile {
            let rows = (0..10).map(|i| {
                let y = i as f64 * 10.0;
                ScanRow { y, weight: 10.0, ink: vec![InkInterval { left: 0.0, right: x1 }],
                    span_lo: y - 5.0, span_hi: y + 5.0 }
            }).collect();
            OutlineProfile { glyph_id: id.into(), source_pin: "t".into(), upm: 1000,
                origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, x1, 90.0],
                ink_area: 5000.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0,
                profile_method: "t".into(), row_step: 10.0, flatten_tolerance: 0.5 }
        };
        let diag_v = || -> OutlineProfile {
            let rows = (0..10).map(|i| {
                let y = i as f64 * 10.0;
                ScanRow { y, weight: 10.0, ink: vec![InkInterval { left: y / 2.0, right: 80.0 }],
                    span_lo: y - 5.0, span_hi: y + 5.0 }
            }).collect();
            OutlineProfile { glyph_id: "v".into(), source_pin: "t".into(), upm: 1000,
                origin: [0.0, 0.0], rows, bounds: [0.0, 0.0, 80.0, 90.0],
                ink_area: 5000.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0,
                profile_method: "t".into(), row_step: 10.0, flatten_tolerance: 0.5 }
        };
        let glyphs = vec![rect("H", 80.0), rect("M", 200.0), diag_v()];
        let ctx = FontContext { measured_pairs: vec![
            MeasuredPair { left: "H".into(), right: "H".into(), gap: 40.0 },
            MeasuredPair { left: "M".into(), right: "M".into(), gap: 40.0 },
            MeasuredPair { left: "H".into(), right: "v".into(), gap: 25.0 },
            MeasuredPair { left: "M".into(), right: "v".into(), gap: 25.0 },
        ], ..Default::default() };

        let off = solve_spacing(&glyphs, Some(&ctx), &SpacingPolicy::default()).unwrap();
        assert!(off.contrast_floor_adjustments.is_empty());
        assert!(off.contrast_floor_failures.is_empty());
        assert!(!off.policy_derivation.contains("contrast-floor"),
            "flag off: no receipt, frozen pipeline");

        let policy = SpacingPolicy { contrast_floor: true, ..Default::default() };
        let on = solve_spacing(&glyphs, Some(&ctx), &policy).unwrap();
        assert!(on.policy_derivation.contains("contrast-floor: k="),
            "flag on: calibration receipt in policy_derivation");
        assert!(on.contrast_floor_failures.is_empty(), "clean fixture: no typed failures");

        // Exactly the heavy pair (M->v, the larger facing weight) is raised.
        assert_eq!(on.contrast_floor_adjustments.len(), 1);
        let adj = &on.contrast_floor_adjustments[0];
        assert_eq!((adj.left.as_str(), adj.right.as_str()), ("M", "v"));
        assert!(adj.gap_before < adj.floor, "raise only below the floor");
        assert!(adj.gap_after >= adj.floor, "verified at/above floor");
        assert!(adj.origin_after > adj.origin_before, "raises widen");

        // The raised pair ships the receipted placement.
        let mv = on.pairs.iter().find(|p| p.left == "M" && p.right == "v").unwrap();
        assert_eq!(mv.origin_distance.to_bits(), adj.origin_after.to_bits());
        assert_eq!(mv.wall_gap.to_bits(), adj.gap_after.to_bits());

        // The light pair (H->v) is untouched: every field bit-identical to
        // the flag-off run.
        let hv_off = off.pairs.iter().find(|p| p.left == "H" && p.right == "v").unwrap();
        let hv_on = on.pairs.iter().find(|p| p.left == "H" && p.right == "v").unwrap();
        assert_eq!(hv_on.origin_distance.to_bits(), hv_off.origin_distance.to_bits());
        assert_eq!(hv_on.wall_gap.to_bits(), hv_off.wall_gap.to_bits());
        assert_eq!(hv_on.optical_cost.to_bits(), hv_off.optical_cost.to_bits());
    }

    #[test]
    fn widen_respects_floor_exactly_at_boundary() {
        let fx = two_glyph_fixture();
        let prefs = fx.prof_refs();
        // Ask for a floor far above the current gap: the walk-out +
        // bisection must land on a verified gap >= floor, within the
        // pair-derived bound.
        let (d, g) = widen_to_floor(prefs["H"], prefs["l"], 0.0, 0.0, 440.0, 40.0, 500.0, 2.0).unwrap();
        assert!(g >= 500.0, "verified gap {g}");
        assert!(d <= 440.0 + 460.0 + 420.0 + 1.0, "within pair-derived bound {d}");
        // And it must not overshoot wildly: first-order estimate is 460.
        assert!(d < 440.0 + 460.0 + 4.0, "tight raise {d}");
    }
}
