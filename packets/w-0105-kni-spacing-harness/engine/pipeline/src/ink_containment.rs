//! ink_containment.rs — glyph-frame containment guard (K3 pre-export tweak).
//!
//! Rule: shipped ink stays inside the glyph's own [0, advance] box. In the
//! K2/K3 frame (advance = lsb + ink_width + rsb, x-translation = lsb -
//! ink_xmin) a violation is exactly `lsb < 0` (ink escapes left of the
//! origin) or `rsb < 0` (ink escapes past the advance). Both are measured
//! defects, not design: negative bearings render as pair-level ink overlap
//! (measured on shipped fonts: HI gap -111, OO gap -119/-123 at upm 1000).
//!
//! Correction floor: one shared T2 floor per glyph when typed pair evidence
//! exists. T2 is half of the glyph's own ready-pair target, read from
//! `PairPosition.pair_target` and never recomputed or parsed from receipt
//! text. Multiple incident targets use the same median definition as the
//! font median. A glyph with pair_target `None` uses the legacy median
//! sidebearing floor so shipped metrics stay byte-identical on that path.
//! A glyph with no pair evidence falls back to the typed font median / 2;
//! with no pair evidence and no font median the floor is 0.0 and declared.
//! Every floor receipt row carries the mandatory `tier` field (T2).
//! Corrections GROW the advance only: a left fix translates ink right and
//! preserves the right sidebearing; a right fix widens the advance. Pair
//! gaps therefore never decrease (monotone, same direction as the
//! post-metrics gap certificate). A left fix therefore SHIFTS the pair
//! frame of every pair the glyph participates in (the ink moved, the origins
//! did not): callers MUST run `compensate_pair_origins` on the solved pairs
//! afterwards so the frame gap equals the solver wall gap again. Design
//! precondition: the pair-gap invariants are stated with spacing_oohh OFF,
//! where the solver wall gap and the kern guard's re-measured gap agree to
//! fp tolerance; the spacing_oohh interaction is out of scope for this pass.
//! The export_frame derivation channel is unchanged here; pair-frame
//! compensation is the only frame repair.
//!
//! Always-output: the guard never stops the run. Every correction is a typed
//! receipt row plus one summary warning; a glyph without a matching profile
//! is left untouched and named. A run with no violations applies nothing, so
//! untouched populations keep bit-identical metrics.

use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::{GlyphSpacing, PairPosition};

/// The mandatory tier value on every floor receipt row.
pub const FLOOR_TIER: &str = "T2";

/// Token printed in place of an unavailable floor value.
const NONE_TOKEN: &str = "unavailable";

/// Typed floor evidence, bound at the callsite from the solver's typed
/// result. The per-pair target rides the pairs themselves; this struct
/// carries only the run-level fallback. This module never parses receipt
/// text.
#[derive(Debug, Clone, Copy)]
pub struct FloorEvidence {
    /// The FONT median pair target over the run's ready pairs, when any
    /// ready pair exists. Rejected when non-finite or negative (typed
    /// note, fallback path taken).
    pub font_median_pair_target: Option<f64>,
}

/// Which floor source corrected a glyph (receipt routing only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FloorSource {
    /// T2 = (glyph's own ready-pair pair_target) / 2.
    PairTargetOver2,
    /// Fallback: FONT median pair_target / 2 (typed per-glyph row).
    FontMedianOver2,
    /// Legacy sidebearing medians for the pair_target=None path.
    LegacyMedian,
    /// No usable pair-target path supplied a floor.
    NoReadyPairsZero,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum GlyphFloor {
    Shared(f64),
    Legacy { lsb: f64, rsb: f64 },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Adjustment {
    pub glyph_id: String,
    pub lsb_before: f64,
    pub lsb_after: f64,
    pub rsb_before: f64,
    pub rsb_after: f64,
    pub advance_before: f64,
    pub advance_after: f64,
}

/// A typed floor note: machine subject plus the context it names (the
/// pair whose target was rejected, or `run` for the font median).
#[derive(Debug, Clone, PartialEq)]
pub struct FloorNote {
    pub subject: String,
    pub context: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ContainmentOutcome {
    pub adjustments: Vec<Adjustment>,
    pub skipped_no_profile: Vec<String>,
    /// The fallback floor applied to violating glyphs with no ready pair
    /// or no usable pair target: FONT median pair_target / 2.
    pub floor_font_median_over_2: Option<f64>,
    /// Per-glyph fallback corrections: (glyph, applied floor); each becomes
    /// a typed `ink_containment_floor_fallback` row.
    pub fallback_glyphs: Vec<(String, f64)>,
    /// True when no ready pair existed and the floor was 0.0 with the
    /// typed `ink_containment_floor_zero` note.
    pub no_ready_pairs_zero: bool,
    /// Violating glyphs whose typed Some(target) path produced a 0.0 floor;
    /// each becomes a typed `zero_floor_no_fallback` row. The legacy
    /// pair_target=None path never appears here.
    pub zero_floor_glyphs: Vec<String>,
    /// Violating glyphs corrected with the legacy sidebearing medians.
    pub legacy_floor_glyphs: Vec<String>,
    /// Legacy sidebearing floors used by the pair_target=None path.
    pub floor_lsb: f64,
    pub floor_rsb: f64,
    /// Floor base sizes: how many non-violating inked glyphs the lsb / rsb
    /// floor medians are computed over. Reported on the receipt; a small
    /// base makes the floor statistically fragile.
    pub floor_lsb_count: usize,
    pub floor_rsb_count: usize,
    /// Typed notes (e.g. a rejected pair or font-median target); each
    /// becomes an `ink_containment_floor_note` row.
    pub floor_notes: Vec<FloorNote>,
    /// Mandatory tier on every floor receipt row.
    pub tier: &'static str,
    /// Solved glyphs with a matching ink profile (informational; not a
    /// floor base - the floor no longer derives from a population).
    pub population: usize,
}

fn median(mut xs: Vec<f64>) -> Option<f64> {
    if xs.is_empty() {
        return None;
    }
    xs.sort_by(|a, b| a.partial_cmp(b).expect("finite"));
    let n = xs.len();
    if n % 2 == 1 {
        Some(xs[n / 2])
    } else {
        Some((xs[n / 2 - 1] + xs[n / 2]) / 2.0)
    }
}

/// A glyph's shared T2 target from its ready incident pairs: the median of
/// its usable (finite, >= 0) incident pair_targets. Callers pass only usable
/// targets; `floor_for` divides the result by 2.
fn aggregate_incident_pair_targets(targets: &[f64]) -> Option<f64> {
    median(targets.to_vec())
}

fn optv(x: Option<f64>) -> String {
    x.map(|v| v.to_string()).unwrap_or_else(|| NONE_TOKEN.into())
}

/// Apply the guard in place. `glyphs` are the solved metrics; `profiles`
/// carry the ink evidence (only glyphs with a profile and positive ink area
/// are corrected); `pairs` are the run's READY (solver-optimal) pairs and
/// decide which glyphs carry pair evidence; `floor_ev` is the typed floor
/// evidence bound at the callsite (see FloorEvidence).
pub fn apply(
    glyphs: &mut [GlyphSpacing],
    profiles: &[OutlineProfile],
    pairs: &[PairPosition],
    floor_ev: &FloorEvidence,
) -> ContainmentOutcome {
    let inked: std::collections::BTreeSet<&str> = profiles
        .iter()
        .filter(|p| p.ink_area > 0.0)
        .map(|p| p.glyph_id.as_str())
        .collect();
    // Floor population: solved glyphs that are inked and non-violating.
    let lsb_pool: Vec<f64> = glyphs
        .iter()
        .filter(|g| inked.contains(g.glyph_id.as_str()) && g.lsb >= 0.0)
        .map(|g| g.lsb)
        .collect();
    let rsb_pool: Vec<f64> = glyphs
        .iter()
        .filter(|g| inked.contains(g.glyph_id.as_str()) && g.rsb >= 0.0)
        .map(|g| g.rsb)
        .collect();
    let floor_lsb = median(lsb_pool.clone()).unwrap_or(0.0);
    let floor_rsb = median(rsb_pool.clone()).unwrap_or(0.0);
    let population = glyphs
        .iter()
        .filter(|g| inked.contains(g.glyph_id.as_str()))
        .count();

    let mut floor_notes: Vec<FloorNote> = Vec::new();
    let mut pair_targets: std::collections::BTreeMap<(String, String), Option<f64>> =
        std::collections::BTreeMap::new();
    for p in pairs {
        pair_targets
            .entry((p.left.clone(), p.right.clone()))
            .or_insert(p.pair_target);
    }
    let mut incident_targets: std::collections::BTreeMap<&str, Vec<f64>> =
        std::collections::BTreeMap::new();
    let mut legacy_glyphs: std::collections::BTreeSet<&str> = std::collections::BTreeSet::new();
    for ((left, right), target) in &pair_targets {
        match target {
            Some(v) if v.is_finite() && *v >= 0.0 => {
                incident_targets.entry(left.as_str()).or_default().push(*v);
                if right != left {
                    incident_targets.entry(right.as_str()).or_default().push(*v);
                }
            }
            Some(_) => floor_notes.push(FloorNote {
                subject: "pair_target_unusable".to_string(),
                context: format!("pair={left}+{right}"),
            }),
            None => {
                legacy_glyphs.insert(left.as_str());
                legacy_glyphs.insert(right.as_str());
            }
        }
    }
    let floor_font_median_over_2 = match floor_ev.font_median_pair_target {
        Some(v) if v.is_finite() && v >= 0.0 => Some(v / 2.0),
        Some(_) => {
            floor_notes.push(FloorNote {
                subject: "font_median_pair_target_unusable".to_string(),
                context: "run".to_string(),
            });
            None
        }
        None => None,
    };
    let no_ready_pairs_zero = pairs.is_empty() && floor_font_median_over_2.is_none();
    let floor_for = |glyph_id: &str| -> (GlyphFloor, FloorSource) {
        if let Some(t) = aggregate_incident_pair_targets(
            incident_targets.get(glyph_id).map(Vec::as_slice).unwrap_or(&[]),
        ) {
            return (GlyphFloor::Shared(t / 2.0), FloorSource::PairTargetOver2);
        }
        if legacy_glyphs.contains(glyph_id) {
            return (
                GlyphFloor::Legacy { lsb: floor_lsb, rsb: floor_rsb },
                FloorSource::LegacyMedian,
            );
        }
        if let Some(f) = floor_font_median_over_2 {
            return (GlyphFloor::Shared(f), FloorSource::FontMedianOver2);
        }
        (GlyphFloor::Shared(0.0), FloorSource::NoReadyPairsZero)
    };

    let mut adjustments = Vec::new();
    let mut fallback_glyphs: Vec<(String, f64)> = Vec::new();
    let mut zero_floor_glyphs: Vec<String> = Vec::new();
    let mut legacy_floor_glyphs: Vec<String> = Vec::new();
    let mut skipped = Vec::new();
    for g in glyphs.iter_mut() {
        if g.lsb >= 0.0 && g.rsb >= 0.0 {
            continue;
        }
        if !inked.contains(g.glyph_id.as_str()) {
            skipped.push(g.glyph_id.clone());
            continue;
        }
        let (floor, source) = floor_for(g.glyph_id.as_str());
        let (lsb_floor, rsb_floor) = match floor {
            GlyphFloor::Shared(v) => (v, v),
            GlyphFloor::Legacy { lsb, rsb } => (lsb, rsb),
        };
        match source {
            FloorSource::FontMedianOver2 => fallback_glyphs.push((g.glyph_id.clone(), lsb_floor)),
            FloorSource::LegacyMedian => legacy_floor_glyphs.push(g.glyph_id.clone()),
            FloorSource::PairTargetOver2 if lsb_floor == 0.0 && rsb_floor == 0.0 => {
                zero_floor_glyphs.push(g.glyph_id.clone());
            }
            _ => {}
        }
        let adj = Adjustment {
            glyph_id: g.glyph_id.clone(),
            lsb_before: g.lsb,
            lsb_after: if g.lsb < 0.0 { lsb_floor } else { g.lsb },
            rsb_before: g.rsb,
            rsb_after: if g.rsb < 0.0 { rsb_floor } else { g.rsb },
            advance_before: g.advance,
            advance_after: {
                let mut adv = g.advance;
                if g.lsb < 0.0 {
                    // Translate ink right: advance grows, rsb preserved.
                    adv += lsb_floor - g.lsb;
                }
                if g.rsb < 0.0 {
                    adv += rsb_floor - g.rsb;
                }
                adv
            },
        };
        g.lsb = adj.lsb_after;
        g.rsb = adj.rsb_after;
        g.advance = adj.advance_after;
        adjustments.push(adj);
    }
    ContainmentOutcome {
        adjustments,
        skipped_no_profile: skipped,
        floor_font_median_over_2,
        fallback_glyphs,
        no_ready_pairs_zero,
        zero_floor_glyphs,
        legacy_floor_glyphs,
        floor_lsb,
        floor_rsb,
        floor_lsb_count: lsb_pool.len(),
        floor_rsb_count: rsb_pool.len(),
        floor_notes,
        tier: FLOOR_TIER,
        population,
    }
}

/// Typed receipt rendering: one summary warning + one row per adjustment.
/// Every floor row carries the mandatory `tier` field (FLOOR_TIER). New
/// canonical rows (stage `containment`): `ink_containment_floor_fallback`
/// per fallback-corrected glyph, `ink_containment_floor_zero` when the run
/// had no ready pairs, `ink_containment_floor_note` per rejected input.
/// Registry row shapes land in the same diff (registry lane coordinated).
pub fn receipt(out: &ContainmentOutcome) -> String {
    let mut s = String::new();
    if out.adjustments.is_empty()
        && out.skipped_no_profile.is_empty()
        && out.fallback_glyphs.is_empty()
        && out.zero_floor_glyphs.is_empty()
        && out.floor_notes.is_empty()
    {
        return s;
    }
    s.push_str(&format!(
        "warning\tink_containment_adjusted\tcount\t{}\tskipped_no_profile\t{}\tfloor_font_median_over_2\t{}\tpopulation\t{}\ttier\t{}\tpolicy\tshipped_ink_within_advance\n",
        out.adjustments.len(),
        out.skipped_no_profile.len(),
        optv(out.floor_font_median_over_2),
        out.population,
        out.tier
    ));
    s.push_str(&format!(
        "ink_containment_floor\tfont_median_pair_target_over_2\t{}\ttier\t{}\tfloor_lsb_n\t{}\tfloor_rsb_n\t{}\n",
        optv(out.floor_font_median_over_2),
        out.tier,
        out.floor_lsb_count,
        out.floor_rsb_count
    ));
    if out.no_ready_pairs_zero {
        s.push_str(&format!(
            "containment\tink_containment_floor_zero\trun\tfloor=0.0; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}; no ready pairs; containment only, declared, nothing invented\n",
            NONE_TOKEN,
            optv(out.floor_font_median_over_2),
            out.tier
        ));
    }
    for (glyph, floor) in &out.fallback_glyphs {
        s.push_str(&format!(
            "containment\tink_containment_floor_fallback\t{glyph}\tfloor={floor}; source=font_median_pair_target_over_2; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}; pair target unavailable or glyph has no ready pair\n",
            NONE_TOKEN,
            optv(out.floor_font_median_over_2),
            out.tier
        ));
    }
    for glyph in &out.zero_floor_glyphs {
        s.push_str(&format!(
            "containment\tink_containment_floor_note\tzero_floor_no_fallback\tglyph={glyph}; floor=0.0; pair_target_over_2={}; font_median_pair_target_over_2={}; typed target path produced floor=0.0; tier={}\n",
            NONE_TOKEN,
            optv(out.floor_font_median_over_2),
            out.tier
        ));
    }
    for note in &out.floor_notes {
        s.push_str(&format!(
            "containment\tink_containment_floor_note\t{}\t{}; value rejected (non-finite or negative); fallback path taken; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}\n",
            note.subject,
            note.context,
            NONE_TOKEN,
            optv(out.floor_font_median_over_2),
            out.tier
        ));
    }
    for a in &out.adjustments {
        s.push_str(&format!(
            "ink_containment\t{}\tlsb_before\t{}\tlsb_after\t{}\trsb_before\t{}\trsb_after\t{}\tadvance_before\t{}\tadvance_after\t{}\ttier\t{}\n",
            a.glyph_id, a.lsb_before, a.lsb_after, a.rsb_before, a.rsb_after, a.advance_before, a.advance_after, out.tier
        ));
    }
    for name in &out.skipped_no_profile {
        s.push_str(&format!("ink_containment_skipped\t{}\treason\tno_ink_profile\ttier\t{}\n", name, out.tier));
    }
    s
}

/// Outcome of the pair-frame compensation pass, receipted verbatim.
pub struct CompensationOutcome {
    /// Pairs whose origin moved (d(left) - d(right) != 0).
    pub pairs_shifted: usize,
    /// Pairs left bit-identical: no containment translation on either side,
    /// or translations cancelling exactly. No arithmetic touches them.
    pub pairs_untouched: usize,
    /// Shifted pairs the compensation pushed below zero origin (untouched
    /// pairs are never counted: they keep the solver's own verdict path).
    /// NOT clamped: the kern stage holds each with the typed reason
    /// `containment_compensation_negative_origin` and ships it kernless.
    pub negative_origin_pairs: Vec<(String, String)>,
}

/// Post-solve pair-frame compensation for the containment guard.
///
/// A left containment fix on glyph g translates its ink right by
/// d(g) = lsb_after - lsb_before (a right fix widens the advance only and
/// moves no ink). For a pair (L, R) the frame gap
/// `gap = origin_distance + lsb_R - (advance_L - rsb_L)` therefore shifts by
/// d(R) - d(L); adding d(L) - d(R) to origin_distance restores the solver
/// wall gap exactly, so the kern stage's guard re-measurement agrees with
/// the solver to fp tolerance by construction. Deterministic: BTreeMap
/// lookups, caller-owned pair order, no re-solve.
pub fn compensate_pair_origins(
    pairs: &mut [PairPosition],
    fallback_pairs: &mut [PairPosition],
    adjustments: &[Adjustment],
) -> CompensationOutcome {
    let delta: std::collections::BTreeMap<&str, f64> = adjustments
        .iter()
        .filter(|a| a.lsb_after != a.lsb_before)
        .map(|a| (a.glyph_id.as_str(), a.lsb_after - a.lsb_before))
        .collect();
    let mut out = CompensationOutcome { pairs_shifted: 0, pairs_untouched: 0, negative_origin_pairs: Vec::new() };
    for pair in pairs.iter_mut().chain(fallback_pairs.iter_mut()) {
        let d = delta.get(pair.left.as_str()).copied().unwrap_or(0.0)
            - delta.get(pair.right.as_str()).copied().unwrap_or(0.0);
        if d != 0.0 {
            pair.origin_distance += d;
            pair.compensated = true;
            out.pairs_shifted += 1;
            if pair.origin_distance < 0.0 {
                out.negative_origin_pairs.push((pair.left.clone(), pair.right.clone()));
            }
        } else {
            out.pairs_untouched += 1;
        }
    }
    out
}

/// Typed receipt rendering: one summary row; the kern ledger names the held
/// pairs, they are not repeated here.
pub fn compensation_receipt(out: &CompensationOutcome) -> String {
    format!(
        "containment_compensation\tpairs_shifted\t{}\tpairs_untouched\t{}\tnegative_origin_pairs\t{}\n",
        out.pairs_shifted, out.pairs_untouched, out.negative_origin_pairs.len()
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_metrics::outline_spacing::OutlineProfile;

    fn gs(id: &str, lsb: f64, rsb: f64, advance: f64) -> GlyphSpacing {
        GlyphSpacing { glyph_id: id.into(), lsb, rsb, advance }
    }
    fn prof(id: &str) -> OutlineProfile {
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: String::new(),
            upm: 1000,
            origin: [0.0, 0.0],
            rows: vec![],
            bounds: [0.0, 0.0, 10.0, 10.0],
            ink_area: 1.0,
            counter_area: 0.0,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: String::new(),
            row_step: 1.0,
            flatten_tolerance: 0.5,
        }
    }
    fn ev(font_median_pair_target: Option<f64>) -> FloorEvidence {
        FloorEvidence { font_median_pair_target }
    }
    fn ready_pair(left: &str, right: &str, origin: f64, pair_target: Option<f64>) -> PairPosition {
        PairPosition { left: left.into(), right: right.into(), origin_distance: origin, wall_gap: 0.0, optical_cost: 1.0, pair_target, compensated: false }
    }

    #[test]
    fn no_violation_is_bit_identical() {
        // Zero-violator fallback regression.
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("N", 19.0, 19.0, 525.0)];
        let before: Vec<(String, f64, f64, f64)> = g.iter().map(|x| (x.glyph_id.clone(), x.lsb, x.rsb, x.advance)).collect();
        let out = apply(&mut g, &[prof("H"), prof("N")], &[], &ev(None));
        let after: Vec<(String, f64, f64, f64)> = g.iter().map(|x| (x.glyph_id.clone(), x.lsb, x.rsb, x.advance)).collect();
        assert_eq!(after, before, "untouched population must keep bit-identical metrics");
        assert!(out.adjustments.is_empty());
        assert!(receipt(&out).is_empty());
    }

    #[test]
    fn left_escape_translates_and_preserves_right() {
        // T2 = pair_target/2 (40/2 = 20), not the population median lsb (19).
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("I", -130.0, 19.0, 525.0), gs("N", 19.0, 19.0, 525.0)];
        let pairs = vec![ready_pair("I", "H", 600.0, Some(40.0))];
        let out = apply(&mut g, &[prof("H"), prof("I"), prof("N")], &pairs, &ev(None));
        assert_eq!(out.adjustments.len(), 1);
        let i = &g[1];
        assert_eq!(i.lsb, 20.0, "floor is T2 = pair_target/2");
        assert_eq!(i.rsb, 19.0, "right sidebearing preserved");
        assert_eq!(i.advance, 525.0 + 150.0, "advance grows by the translation");
        assert_eq!(out.tier, "T2");
    }

    #[test]
    fn right_escape_widens_advance() {
        // Mechanics unchanged; the shared T2 floor (20) applies to the
        // right side too (side asymmetry removed).
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("O", 19.0, -60.0, 548.0)];
        let pairs = vec![ready_pair("H", "O", 600.0, Some(40.0))];
        let out = apply(&mut g, &[prof("H"), prof("O")], &pairs, &ev(None));
        assert_eq!(out.adjustments.len(), 1);
        assert_eq!(g[1].rsb, 20.0, "same T2 floor on the right side");
        assert_eq!(g[1].advance, 548.0 + 80.0);
        assert_eq!(g[1].lsb, 19.0);
    }

    #[test]
    fn both_sides_escape_grows_monotonically() {
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("O", -59.0, -60.0, 548.0)];
        let pairs = vec![ready_pair("H", "O", 600.0, Some(40.0))];
        let out = apply(&mut g, &[prof("H"), prof("O")], &pairs, &ev(None));
        assert_eq!(g[1].lsb, 20.0);
        assert_eq!(g[1].rsb, 20.0, "one shared floor value for both sides");
        assert_eq!(g[1].advance, 548.0 + 79.0 + 80.0);
        assert!(out.adjustments[0].advance_after > out.adjustments[0].advance_before);
    }

    #[test]
    fn glyph_without_profile_is_skipped_and_named() {
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("ghost", -5.0, 3.0, 100.0)];
        let pairs = vec![ready_pair("H", "ghost", 600.0, Some(40.0))];
        let out = apply(&mut g, &[prof("H")], &pairs, &ev(None));
        assert_eq!(out.skipped_no_profile, vec!["ghost".to_string()]);
        assert_eq!(g[1].lsb, -5.0, "untouched when no ink evidence exists");
        assert!(receipt(&out).contains("ink_containment_skipped\tghost"));
    }

    #[test]
    fn no_ready_pairs_falls_back_to_zero_with_typed_note() {
        // With no ready pairs and no font median the floor is 0.0 plus the typed zero note.
        let mut g = vec![gs("A", -5.0, -5.0, 100.0)];
        let out = apply(&mut g, &[prof("A")], &[], &ev(None));
        assert_eq!(g[0].lsb, 0.0, "containment only, nothing invented");
        assert_eq!(g[0].rsb, 0.0);
        assert!(out.no_ready_pairs_zero);
        let r = receipt(&out);
        assert!(r.contains("containment\tink_containment_floor_zero\trun\tfloor=0.0; pair_target_over_2=unavailable; font_median_pair_target_over_2=unavailable; tier=T2; no ready pairs"), "receipt: {r}");
    }

    #[test]
    fn glyph_with_no_ready_pair_gets_font_median_fallback_with_typed_row() {
        // I has a ready pair (T2 = 40/2 = 20); J violates but has no ready
        // pair, so J falls back to the FONT median pair_target/2 (30/2 = 15)
        // with a typed ink_containment_floor_fallback row.
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("I", -130.0, 19.0, 525.0), gs("J", -5.0, 3.0, 100.0)];
        let pairs = vec![ready_pair("I", "H", 600.0, Some(40.0))];
        let out = apply(&mut g, &[prof("H"), prof("I"), prof("J")], &pairs, &ev(Some(30.0)));
        assert_eq!(g[1].lsb, 20.0);
        assert_eq!(g[2].lsb, 15.0, "fallback floor is font median pair_target/2");
        assert_eq!(out.fallback_glyphs, vec![("J".to_string(), 15.0)]);
        let r = receipt(&out);
        assert!(r.contains("containment\tink_containment_floor_fallback\tJ\tfloor=15; source=font_median_pair_target_over_2; pair_target_over_2=unavailable; font_median_pair_target_over_2=15; tier=T2"), "receipt: {r}");
        assert!(!r.contains("ink_containment_floor_fallback\tI\t"), "paired glyph never takes the fallback");
    }

    #[test]
    fn unusable_pair_target_is_rejected_with_typed_note() {
        let mut g = vec![gs("I", -130.0, 19.0, 525.0)];
        let pairs = vec![ready_pair("I", "I", 600.0, Some(f64::NAN))];
        let out = apply(&mut g, &[prof("I")], &pairs, &ev(Some(30.0)));
        assert_eq!(g[0].lsb, 15.0, "rejected target takes the fallback path");
        assert_eq!(out.floor_notes, vec![FloorNote { subject: "pair_target_unusable".to_string(), context: "pair=I+I".to_string() }]);
        let r = receipt(&out);
        assert!(r.contains("containment\tink_containment_floor_note\tpair_target_unusable\tpair=I+I; value rejected"), "receipt: {r}");
    }

    #[test]
    fn zero_floor_is_reported_only_on_some_target_path() {
        let mut g = vec![gs("V", -5.0, 3.0, 100.0)];
        let pairs = vec![ready_pair("V", "V", 600.0, Some(0.0))];
        let out = apply(&mut g, &[prof("V")], &pairs, &ev(None));
        assert_eq!(g[0].lsb, 0.0);
        assert_eq!(out.zero_floor_glyphs, vec!["V".to_string()]);
        let r = receipt(&out);
        assert!(r.contains("containment	ink_containment_floor_note	zero_floor_no_fallback	glyph=V; floor=0.0"), "receipt: {r}");
    }

    #[test]
    fn self_pair_target_is_deduplicated_by_pair_identity() {
        let mut g = vec![gs("I", -10.0, 3.0, 100.0)];
        let pairs = vec![
            ready_pair("I", "I", 600.0, Some(40.0)),
            ready_pair("I", "H", 700.0, Some(60.0)),
        ];
        let out = apply(&mut g, &[prof("I")], &pairs, &ev(None));
        assert_eq!(g[0].lsb, 25.0, "expected floor(median(40, 60) / 2)");
        assert!(out.floor_notes.is_empty());
    }

    #[test]
    fn none_pair_target_uses_legacy_sidebearing_floor() {
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("I", -130.0, 19.0, 525.0), gs("N", 19.0, 19.0, 525.0)];
        let pairs = vec![ready_pair("I", "H", 600.0, None)];
        let out = apply(&mut g, &[prof("H"), prof("I"), prof("N")], &pairs, &ev(None));
        assert_eq!(g[1].lsb, 19.0);
        assert_eq!(g[1].rsb, 19.0);
        assert_eq!(g[1].advance, 525.0 + 149.0);
        assert_eq!(out.legacy_floor_glyphs, vec!["I".to_string()]);
        assert!(out.zero_floor_glyphs.is_empty());
        assert!(!receipt(&out).contains("zero_floor_no_fallback"));
    }

    #[test]
    fn empty_pairs_with_font_median_uses_fallback_not_zero_row() {
        let mut g = vec![gs("A", -5.0, -5.0, 100.0)];
        let out = apply(&mut g, &[prof("A")], &[], &ev(Some(30.0)));
        assert_eq!(g[0].lsb, 15.0, "expected floor(median / 2) with median derived from the fixture");
        assert!(!out.no_ready_pairs_zero);
        let r = receipt(&out);
        assert!(r.contains("ink_containment_floor_fallback	A	floor=15"));
        assert!(!r.contains("ink_containment_floor_zero"));
    }

    #[test]
    fn rejected_target_notes_survive_without_adjustments() {
        let mut g = vec![gs("H", 19.0, 19.0, 525.0)];
        let pairs = vec![ready_pair("H", "H", 600.0, Some(f64::NAN))];
        let out = apply(&mut g, &[prof("H")], &pairs, &ev(None));
        assert!(out.adjustments.is_empty());
        let r = receipt(&out);
        assert!(r.contains("pair_target_unusable	pair=H+H"), "receipt: {r}");
    }

    #[test]
    fn incident_target_aggregation_is_the_ruled_median() {
        // Median of the glyph's usable incident pair_targets; odd count uses the middle, even count uses the mean of the two middles.
        assert_eq!(aggregate_incident_pair_targets(&[]), None);
        assert_eq!(aggregate_incident_pair_targets(&[40.0]), Some(40.0));
        assert_eq!(aggregate_incident_pair_targets(&[60.0, 40.0]), Some(50.0));
        assert_eq!(aggregate_incident_pair_targets(&[60.0, 20.0, 40.0]), Some(40.0));
    }

    #[test]
    fn glyph_with_differing_incident_targets_uses_the_median_over_2() {
        // I has two ready incident pairs with targets 40 and 60: its floor
        // is median(40, 60)/2 = 25.
        let mut g = vec![gs("I", -130.0, 19.0, 525.0)];
        let pairs = vec![
            ready_pair("I", "H", 600.0, Some(40.0)),
            ready_pair("I", "O", 700.0, Some(60.0)),
        ];
        let out = apply(&mut g, &[prof("I")], &pairs, &ev(None));
        assert_eq!(g[0].lsb, 25.0, "floor is the ruled incident median/2");
        assert!(out.fallback_glyphs.is_empty(), "usable incident targets never take the fallback");
    }

    #[test]
    fn receipt_rows_are_typed_and_tiered() {
        let mut g = vec![gs("H", 19.0, 19.0, 525.0), gs("I", -130.0, 19.0, 525.0)];
        let pairs = vec![ready_pair("I", "H", 600.0, Some(40.0))];
        let out = apply(&mut g, &[prof("H"), prof("I")], &pairs, &ev(None));
        let r = receipt(&out);
        assert!(r.starts_with("warning\tink_containment_adjusted\tcount\t1\t"));
        assert!(r.contains("ink_containment_floor\tfont_median_pair_target_over_2\tunavailable\ttier\tT2\tfloor_lsb_n\t"));
        assert!(r.contains("ink_containment\tI\tlsb_before\t-130\tlsb_after\t20\t"));
        // Mandatory tier field on EVERY floor row (key-value rows carry
        // `tier\tT2`; canonical rows embed `tier=T2`).
        for line in r.lines() {
            assert!(line.contains("tier\tT2") || line.contains("tier=T2"), "untiered floor row: {line}");
        }
    }

    fn adj(id: &str, lsb_before: f64, lsb_after: f64) -> Adjustment {
        Adjustment {
            glyph_id: id.into(),
            lsb_before,
            lsb_after,
            rsb_before: 19.0,
            rsb_after: 19.0,
            advance_before: 525.0,
            advance_after: 525.0 + (lsb_after - lsb_before),
        }
    }
    fn pp(left: &str, right: &str, origin: f64) -> PairPosition {
        PairPosition { left: left.into(), right: right.into(), origin_distance: origin, wall_gap: 0.0, optical_cost: 1.0, pair_target: None, compensated: false }
    }

    #[test]
    fn compensation_restores_the_frame_gap_exactly() {
        // H untouched (19/19/525); I left-fixed -130 -> 19 (d = 149, advance
        // 525 -> 674, rsb preserved). Both pair directions restore the
        // pre-containment frame gap: these integer-valued fixtures hold bit
        // equality; fractional bearings are asserted to fp (ulp-scale)
        // tolerance in fractional_bearings_restore_the_gap_to_tolerance.
        let adjs = vec![adj("I", -130.0, 19.0)];
        // Frame gap before: origin + lsb_R - (advance_L - rsb_L).
        let gap_before_ih: f64 = 600.0 + 19.0 - (525.0 - 19.0);
        let gap_before_hi: f64 = 700.0 + (-130.0) - (525.0 - 19.0);
        let mut pairs = vec![pp("I", "H", 600.0), pp("H", "I", 700.0)];
        let out = compensate_pair_origins(&mut pairs, &mut [], &adjs);
        assert_eq!(out.pairs_shifted, 2);
        assert_eq!(pairs[0].origin_distance, 600.0 + 149.0);
        assert_eq!(pairs[1].origin_distance, 700.0 - 149.0);
        let gap_after_ih = pairs[0].origin_distance + 19.0 - (674.0 - 19.0);
        let gap_after_hi = pairs[1].origin_distance + 19.0 - (525.0 - 19.0);
        assert_eq!(gap_after_ih.to_bits(), gap_before_ih.to_bits());
        assert_eq!(gap_after_hi.to_bits(), gap_before_hi.to_bits());
        assert!(out.negative_origin_pairs.is_empty());
    }

    #[test]
    fn untouched_pairs_keep_exact_bits() {
        let adjs = vec![adj("I", -130.0, 19.0)];
        let mut pairs = vec![pp("H", "N", 600.5)];
        let before = pairs[0].origin_distance.to_bits();
        let out = compensate_pair_origins(&mut pairs, &mut [], &adjs);
        assert_eq!(out.pairs_untouched, 1);
        assert_eq!(pairs[0].origin_distance.to_bits(), before, "no arithmetic on untouched pairs");
    }

    #[test]
    fn right_fix_only_glyph_contributes_no_delta() {
        // A right fix moves no ink: the glyph must not appear in the delta map.
        let a = Adjustment {
            glyph_id: "O".into(),
            lsb_before: 19.0,
            lsb_after: 19.0,
            rsb_before: -60.0,
            rsb_after: 19.0,
            advance_before: 548.0,
            advance_after: 627.0,
        };
        let mut pairs = vec![pp("H", "O", 600.5), pp("O", "H", 600.5)];
        let out = compensate_pair_origins(&mut pairs, &mut [], &[a]);
        assert_eq!(out.pairs_untouched, 2);
        assert_eq!(pairs[0].origin_distance.to_bits(), 600.5f64.to_bits());
        assert_eq!(pairs[1].origin_distance.to_bits(), 600.5f64.to_bits());
    }

    #[test]
    fn fractional_bearings_restore_the_gap_to_tolerance() {
        // Fractional-bearing fixture: the restore is one f64 add, so the
        // frame gap agrees to fp tolerance rather than bit equality.
        let adjs = vec![adj("I", -130.25, 19.5)];
        let gap_before: f64 = 600.125 + 19.0 - (525.0 - 19.0);
        let mut pairs = vec![pp("I", "H", 600.125)];
        let out = compensate_pair_origins(&mut pairs, &mut [], &adjs);
        assert_eq!(out.pairs_shifted, 1);
        let gap_after = pairs[0].origin_distance + 19.0 - (674.75 - 19.0);
        let tol = gap_before.abs() * 1e-12 + f64::EPSILON;
        assert!(
            (gap_after - gap_before).abs() <= tol,
            "frame gap must restore to fp tolerance: {gap_after} vs {gap_before}"
        );
    }

    #[test]
    fn untouched_negative_origin_pairs_are_neither_flagged_nor_counted() {
        // A pair the delta map never touches keeps the solver's own verdict
        // path: the compensation pass does not flag it and does not count it
        // as a negative-origin pair.
        let adjs = vec![adj("I", -130.0, 19.0)];
        let mut pairs = vec![pp("H", "N", -5.0)];
        let out = compensate_pair_origins(&mut pairs, &mut [], &adjs);
        assert_eq!(out.pairs_untouched, 1);
        assert!(out.negative_origin_pairs.is_empty());
        assert!(!pairs[0].compensated);
        assert_eq!(pairs[0].origin_distance.to_bits(), (-5.0f64).to_bits());
    }

    #[test]
    fn negative_origin_is_reported_never_clamped_and_fallback_is_compensated() {
        let adjs = vec![adj("I", -130.0, 19.0)];
        let mut pairs = vec![pp("H", "I", 100.0)];
        let mut fallback = vec![pp("I", "H", 600.0)];
        let out = compensate_pair_origins(&mut pairs, &mut fallback, &adjs);
        assert_eq!(pairs[0].origin_distance, 100.0 - 149.0, "negative value written through, no clamp");
        assert!(pairs[0].compensated);
        assert_eq!(out.negative_origin_pairs, vec![("H".to_string(), "I".to_string())]);
        assert_eq!(fallback[0].origin_distance, 600.0 + 149.0, "fallback pairs compensate too");
        let r = compensation_receipt(&out);
        assert!(r.starts_with("containment_compensation\tpairs_shifted\t2\tpairs_untouched\t0\tnegative_origin_pairs\t1\n"));
    }
}
