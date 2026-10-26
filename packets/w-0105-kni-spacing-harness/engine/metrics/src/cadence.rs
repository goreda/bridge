//! cadence.rs - Lane B: stem-interval cadence + optical area/balance measure.
//!
//! LeMo-lineage (Blokland Letter Modeler) stem-interval cadence: the
//! rhythmic unit of a typeface is the white interval BETWEEN its stems
//! inside its own glyphs (the 'n' counter family). This module measures
//! that interval from the font's own K1 scanline profiles and nothing
//! else: every number below is a font measurement. No published LeMo
//! equation exists in this crate; the weighted-median cadence statistic is
//! OUR CANDIDATE, labeled as such, never presented as published.
//!
//! CONVENTION (declared, derivation written):
//! - Sample: every interior white gap between two consecutive NONZERO ink
//!   intervals on one scan row (the stem-to-stem white the raster actually
//!   carries). Aperture whites open to the bounds edge are not interior
//!   and are not sampled; K1 marks them via open_left/open_right, which
//!   the class pass reads separately. Zero-width contacts (intervals
//!   touching) are not stem intervals and are skipped.
//! - Weight: the row's quadrature weight (K1 contract: area integrals
//!   MUST be weight-multiplied; a cadence built from unweighted rows
//!   would let the scan pitch choose the rhythm).
//! - Statistic: weighted median (the same robust-location doctrine the
//!   solver already applies to stem widths and counter channels), plus
//!   the weighted median absolute deviation as the dispersion receipt.
//!   Both are pure order statistics of font measurements: no constant
//!   enters anywhere.
//!
//! Consumers: self_anchored_spacing's policy-gated class pass
//! (SpacingPolicy::cadence_class_pass). This module never reads source
//! spacing, never writes output, and cannot change any solution by
//! itself.

use crate::outline_spacing::OutlineProfile; // K1, metrics/src/outline_spacing.rs

/// The font's own stem-interval cadence, measured (OUR CANDIDATE
/// statistics; see module docs for the declared conventions).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StemIntervalMeasure {
    /// Weighted median interior stem-to-stem white, font units.
    pub unit: f64,
    /// Weighted median absolute deviation around `unit`, font units.
    pub dispersion: f64,
    /// Number of sampled interior stem intervals (rows can carry several).
    pub samples: usize,
    /// Total quadrature weight behind the samples (== summed row weights).
    pub total_weight: f64,
}

/// Typed refusal: the cadence measure never papers over bad input.
#[derive(Debug, Clone, PartialEq)]
pub enum CadenceError {
    NonFinite { glyph_id: String, field: &'static str },
}

impl std::fmt::Display for CadenceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CadenceError::NonFinite { glyph_id, field } =>
                write!(f, "non-finite {field} in glyph {glyph_id}"),
        }
    }
}
impl std::error::Error for CadenceError {}

/// Weighted median of (value, weight) pairs, weights > 0, values finite:
/// the value at which the cumulative weight first reaches half the total
/// weight (lower weighted median; deterministic under ties, no
/// interpolation convention that would invent unmeasured values).
/// None on empty input.
fn weighted_median(samples: &[(f64, f64)]) -> Option<f64> {
    if samples.is_empty() { return None; }
    let total: f64 = samples.iter().map(|(_, w)| w).sum();
    let half = total / 2.0;
    let mut acc = 0.0;
    for &(v, w) in samples {
        acc += w;
        if acc >= half { return Some(v); }
    }
    samples.last().map(|&(v, _)| v)
}

/// Measure the stem-interval cadence of the font carried in `profiles`.
/// Returns Ok(None) when no glyph carries any interior stem interval
/// (single-stem and flush-box fonts): an honest absence the caller turns
/// into a typed receipt, never an invented unit.
pub fn measure_stem_intervals(
    profiles: &[OutlineProfile],
) -> Result<Option<StemIntervalMeasure>, CadenceError> {
    let mut samples: Vec<(f64, f64)> = Vec::new();
    for p in profiles {
        for row in &p.rows {
            if !row.weight.is_finite() || !(row.weight >= 0.0) {
                return Err(CadenceError::NonFinite {
                    glyph_id: p.glyph_id.clone(), field: "row.weight",
                });
            }
            if row.weight == 0.0 || row.ink.len() < 2 { continue; }
            for w in row.ink.windows(2) {
                let gap = w[1].left - w[0].right;
                if !gap.is_finite() {
                    return Err(CadenceError::NonFinite {
                        glyph_id: p.glyph_id.clone(), field: "ink interval",
                    });
                }
                if gap > 0.0 {
                    samples.push((gap, row.weight));
                }
            }
        }
    }
    if samples.is_empty() { return Ok(None); }
    samples.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    let total_weight = samples.iter().map(|(_, w)| w).sum();
    let count = samples.len();
    let unit = weighted_median(&samples).expect("non-empty samples have a weighted median");
    let mut dev: Vec<(f64, f64)> = samples.iter()
        .map(|&(v, w)| ((v - unit).abs(), w)).collect();
    dev.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    let dispersion = weighted_median(&dev).expect("non-empty samples have a weighted median");
    Ok(Some(StemIntervalMeasure { unit, dispersion, samples: count, total_weight }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outline_spacing::{InkInterval, ScanRow};

    fn profile(id: &str, rows: Vec<(f64, f64, Vec<(f64, f64)>)>) -> OutlineProfile {
        // rows: (y, weight, [(ink_left, ink_right), ...])
        let rows: Vec<ScanRow> = rows.into_iter().map(|(y, w, ink)| ScanRow {
            y,
            weight: w,
            ink: ink.into_iter().map(|(left, right)| InkInterval { left, right }).collect(),
            span_lo: y - w / 2.0,
            span_hi: y + w / 2.0,
        }).collect();
        let (mut x0, mut y0) = (f64::INFINITY, f64::INFINITY);
        let (mut x1, mut y1) = (f64::NEG_INFINITY, f64::NEG_INFINITY);
        for r in &rows {
            y0 = y0.min(r.span_lo); y1 = y1.max(r.span_hi);
            for iv in &r.ink { x0 = x0.min(iv.left); x1 = x1.max(iv.right); }
        }
        if !x0.is_finite() { x0 = 0.0; x1 = 0.0; y0 = 0.0; y1 = 0.0; }
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: "test".into(),
            upm: 1000,
            origin: [0.0, 0.0],
            rows,
            bounds: [x0, y0, x1, y1],
            ink_area: 0.0,
            counter_area: 0.0,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: "test-fixture".into(),
            row_step: 10.0,
            flatten_tolerance: 0.5,
        }
    }

    #[test]
    fn uniform_intervals_recover_their_width() {
        // Every row: two stems with a 46-unit white between them.
        let p = profile("n", (0..10).map(|i|
            (i as f64 * 10.0, 10.0, vec![(0.0, 20.0), (66.0, 86.0)])).collect());
        let m = measure_stem_intervals(&[p]).unwrap().unwrap();
        assert_eq!(m.unit, 46.0);
        assert_eq!(m.dispersion, 0.0);
        assert_eq!(m.samples, 10);
        assert_eq!(m.total_weight, 100.0);
    }

    #[test]
    fn row_weights_move_the_median() {
        // Same gaps, different row weights: the quadrature weight, not the
        // row count, picks the cadence unit.
        let light = profile("a", vec![(0.0, 1.0, vec![(0.0, 10.0), (50.0, 60.0)])]); // gap 40, w 1
        let heavy = profile("b", vec![
            (0.0, 10.0, vec![(0.0, 10.0), (80.0, 90.0)]), // gap 70, w 10
            (10.0, 10.0, vec![(0.0, 10.0), (80.0, 90.0)]), // gap 70, w 10
        ]);
        let m = measure_stem_intervals(&[light, heavy]).unwrap().unwrap();
        assert_eq!(m.unit, 70.0, "weights 20 vs 1: the heavy rows' interval is the cadence");
    }

    #[test]
    fn single_stem_and_flush_glyphs_give_no_cadence() {
        let solid = profile("i", (0..10).map(|i|
            (i as f64 * 10.0, 10.0, vec![(0.0, 20.0)])).collect());
        assert_eq!(measure_stem_intervals(&[solid]).unwrap(), None);
    }

    #[test]
    fn touching_intervals_are_not_stem_intervals() {
        // gap 0 between touching intervals: skipped, not sampled as rhythm.
        let p = profile("x", vec![(0.0, 10.0, vec![(0.0, 20.0), (20.0, 40.0)])]);
        assert_eq!(measure_stem_intervals(&[p]).unwrap(), None);
    }

    #[test]
    fn non_finite_weight_is_a_typed_refusal() {
        let p = profile("bad", vec![(0.0, f64::NAN, vec![(0.0, 20.0), (30.0, 50.0)])]);
        assert!(matches!(
            measure_stem_intervals(&[p]),
            Err(CadenceError::NonFinite { glyph_id, field: "row.weight" }) if glyph_id == "bad"
        ));
    }

    #[test]
    fn deterministic_repeat() {
        let p = profile("n", (0..10).map(|i|
            (i as f64 * 10.0, 10.0, vec![(0.0, 20.0), (66.0, 86.0)])).collect());
        let q = profile("o", (0..10).map(|i|
            (i as f64 * 10.0, 10.0, vec![(5.0, 25.0), (85.0, 105.0)])).collect());
        let a = measure_stem_intervals(&[p.clone(), q.clone()]).unwrap();
        let b = measure_stem_intervals(&[p, q]).unwrap();
        assert_eq!(a, b);
    }
}
