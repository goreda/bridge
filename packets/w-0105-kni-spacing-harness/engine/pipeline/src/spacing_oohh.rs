//! SP-OOHH: vertical stem-adjacency consistency, a fine-tuning layer on top of
//! the solved spacing output.
//!
//! Owner direction (brief W7): "OO ile HH gibi temel ikililikler; vertical
//! stemleri yanyana gelen farkli harflerde spacing tutarli olmali; mevcut
//! hesap sistemini bozma, iyilestir." Pairs whose facing sides are both
//! vertical stems (H-H, H-n, O-side bearings do not apply - 'O' has no flat
//! stem) should sit at a consistent white gap across the font. The existing
//! solve is NOT replaced: this layer reads the solver's per-glyph lsb/rsb and
//! the glyphs' own ink (OutlineProfile side edges), measures every stem-stem
//! ordered pair's gap from that ink, derives the class target as the class
//! median, and nudges sidebearings toward it. Pair placements the solver
//! explicitly solved are preserved: the residual kern layer recomputes
//! `residual = origin_distance - left.advance` from the adjusted solution, so
//! a kerned pair keeps its placement (up to the pre-existing advance
//! rounding); only natural (unkerned) placements move.
//!
//! Policy gate: `OohhPolicy::enabled == false` (the default; CLI flag
//! `--spacing-oohh` turns it on) returns a typed `Off` report and mutates
//! NOTHING, so a gated-off run is bit-identical to a run without this module.
//!
//! Frame (chief-architect frame rule, same as outline_spacing): shipped ink is
//! translated by `x_translation = lsb - ink_xmin`; a glyph's left ink edge
//! lands at `lsb`, its right ink edge at `advance - rsb`. All gap arithmetic
//! below is in that shipped frame.
//!
//! Corrections change sidebearings without breaking the solver's invariant
//! `advance = ink_bounds_width + lsb + rsb`:
//!   right-side move dr: rsb += dr, advance += dr (ink unmoved; right gaps += dr)
//!   left-side move  dl: lsb += dl, advance += dl (ink shifts with its origin;
//!     right-side gaps unchanged: the right edge and the advance move together)
//! No bearing is ever pushed below 0 (negative sidebearings are measured
//! defects, per the ink-containment guard that runs after this layer).

use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::SpacingSolution;
use std::collections::BTreeMap;

/// CLI policy flag (parsed at the call site; NOT an env var).
pub const FLAG: &str = "--spacing-oohh";

/// CONVENTION: a vertical stem inks essentially every row of the body band;
/// boundary-row clipping and small serifs can remove a few rows. 0.8 admits
/// real stems (e.g. an 'I' whose band rows are all inked) while excluding
/// forms whose side exists only over part of the band (e.g. 'c' apertures).
pub const COVER_MIN_FRAC: f64 = 0.8;

/// CONVENTION: a stem edge is flat: virtually all inked band rows place the
/// side edge within one scan pitch (the profile's own `row_step`, the
/// measurement's native resolution - font-derived, not a fixed number) of the
/// median edge. 0.9 tolerates a few serif/overshoot rows on an otherwise flat
/// stem.
pub const FLAT_MIN_FRAC: f64 = 0.9;

/// CONVENTION: the class statistic is a median over ordered stem-stem pairs;
/// a median over fewer than 4 observations is a pair count, not a class.
pub const MIN_CLASS_PAIRS: usize = 4;

/// CONVENTION: one consistency pass moves a sidebearing by at most half the
/// class target gap. A larger required move means the side was misclassified
/// (not a stem) or the solve is far off; both are for the solver/owner, not
/// for a fine-tuning layer. The floor of the clamp is the class's own largest
/// scan pitch, so a sub-pixel class can still move by its own resolution.
pub const MAX_MOVE_FRAC_OF_TARGET: f64 = 0.5;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OohhPolicy {
    pub enabled: bool,
}

impl OohhPolicy {
    /// Gate from the CLI flag (parsed by the caller; no env reads here).
    pub fn from_flag(flag_present: bool) -> OohhPolicy {
        OohhPolicy { enabled: flag_present }
    }
}

impl Default for OohhPolicy {
    /// Default OFF: a run that does not pass the flag is bit-identical to a
    /// run without this module.
    fn default() -> Self {
        OohhPolicy { enabled: false }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OohhStatus {
    /// Gate closed; nothing was measured or mutated.
    Off,
    /// Solution metrics are unusable for banding (non-finite or non-positive
    /// x_height/cap_height, or x_height == cap_height so bands cannot be
    /// told apart). Nothing mutated.
    NotApplicable(&'static str),
    /// Fewer than MIN_CLASS_PAIRS ordered stem-stem pairs: there is no class
    /// to be consistent with. Nothing mutated.
    InsufficientPopulation,
    /// Class measured and corrections applied (possibly zero when the class
    /// was already consistent).
    Applied,
}

impl OohhStatus {
    pub fn code(&self) -> &'static str {
        match self {
            OohhStatus::Off => "off",
            OohhStatus::NotApplicable(_) => "not_applicable",
            OohhStatus::InsufficientPopulation => "insufficient_population",
            OohhStatus::Applied => "applied",
        }
    }
}

#[derive(Clone, Debug)]
pub struct OohhReport {
    pub status: OohhStatus,
    pub stem_right: usize,
    pub stem_left: usize,
    pub class_pairs: usize,
    pub target_gap: Option<f64>,
    pub glyphs_adjusted: usize,
    pub max_applied_delta: f64,
    /// Font-derived minimum positive bbox gap for stem-class pairs: no
    /// adjusted bearing may push a stem-stem bbox gap below this. Measured
    /// per style, never a constant (see edge_white_gaps).
    pub min_bbox_gap: Option<f64>,
    pub min_bbox_gap_basis: &'static str,
}

impl OohhReport {
    /// Receipt row. The OFF gate writes NOTHING (empty string): with the
    /// gate closed the whole run - font bytes and receipt bytes - is
    /// bit-identical to a tree without this module (SP-PROOF contract).
    pub fn receipt_line(&self) -> String {
        if self.status == OohhStatus::Off {
            return String::new();
        }
        let detail = match &self.status {
            OohhStatus::NotApplicable(reason) => format!("\treason\t{}", reason),
            _ => String::new(),
        };
        let target = self
            .target_gap
            .map(|t| format!("{:e}", t))
            .unwrap_or_else(|| "none".to_string());
        format!(
            "spacing_oohh\tstatus\t{}{}\tstem_right\t{}\tstem_left\t{}\tclass_pairs\t{}\ttarget_gap\t{}\tglyphs_adjusted\t{}\tmax_applied_delta\t{:e}\tmin_bbox_gap\t{}\tmin_bbox_gap_basis\t{}\n",
            self.status.code(),
            detail,
            self.stem_right,
            self.stem_left,
            self.class_pairs,
            target,
            self.glyphs_adjusted,
            self.max_applied_delta,
            self.min_bbox_gap.map(|v| format!("{:e}", v)).unwrap_or_else(|| "none".to_string()),
            self.min_bbox_gap_basis
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct StemSide {
    /// Median side-edge x over the inked band rows, raw profile frame.
    median_edge: f64,
}

/// Which side of the glyph faces the pair partner.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Side {
    Left,
    Right,
}

/// Median of a non-empty slice: sorted copy, exact two-middle average.
/// Deterministic for a fixed input order.
fn median(values: &mut [f64]) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = values.len();
    if n % 2 == 1 {
        Some(values[n / 2])
    } else {
        Some((values[n / 2 - 1] + values[n / 2]) / 2.0)
    }
}

/// Body band of the glyph: [baseline, baseline + cap_height) for
/// cap-height forms, [baseline, baseline + x_height) for x-height forms,
/// clipped to the glyph's own ink bounds. Heights come from the solved
/// metrics (the font's own measurement), never from a fixed number.
/// None when the solution metrics cannot support banding or the band is
/// thinner than two scan pitches (nothing to measure at the profile's own
/// resolution).
fn body_band(sol: &SpacingSolution, p: &OutlineProfile) -> Option<(f64, f64)> {
    let (base, xh, ch) = (sol.baseline, sol.x_height, sol.cap_height);
    if !(base.is_finite() && xh.is_finite() && ch.is_finite() && xh > 0.0 && ch > 0.0) {
        return None;
    }
    if (ch - xh).abs() <= f64::EPSILON {
        return None; // bands cannot be told apart (e.g. degraded population floor)
    }
    let height_above = p.bounds[3] - base;
    if !height_above.is_finite() || height_above <= 0.0 {
        return None;
    }
    let band_h = if height_above >= (xh + ch) / 2.0 { ch } else { xh };
    let lo = base.max(p.bounds[1]);
    let hi = (base + band_h).min(p.bounds[3]);
    if !(hi > lo) || hi - lo < 2.0 * p.row_step {
        return None;
    }
    Some((lo, hi))
}

/// Classify one side of one glyph over its body band. A side is a stem when
/// it inks >= COVER_MIN_FRAC of the band rows and its edge stays within one
/// scan pitch of the median edge on >= FLAT_MIN_FRAC of the inked rows. Rows
/// are selected by covered-span intersection (ScanRow::span_lo/span_hi, per
/// the profile contract), never by grid-midpoint arithmetic.
fn classify_side(p: &OutlineProfile, band: (f64, f64), side: Side) -> Option<StemSide> {
    let band_rows: Vec<&kni_metrics::outline_spacing::ScanRow> = p
        .rows
        .iter()
        .filter(|r| r.span_hi > band.0 && r.span_lo < band.1)
        .collect();
    if band_rows.is_empty() {
        return None;
    }
    let mut edges: Vec<f64> = band_rows
        .iter()
        .filter_map(|r| match side {
            Side::Left => r.ink.first().map(|iv| iv.left),
            Side::Right => r.ink.last().map(|iv| iv.right),
        })
        .collect();
    if edges.is_empty() {
        return None;
    }
    let coverage = edges.len() as f64 / band_rows.len() as f64;
    let m = median(&mut edges)?;
    let flat = edges.iter().filter(|e| (m - **e).abs() <= p.row_step).count() as f64
        / edges.len() as f64;
    if coverage >= COVER_MIN_FRAC && flat >= FLAT_MIN_FRAC && m.is_finite() {
        Some(StemSide { median_edge: m })
    } else {
        None
    }
}

/// Vertical white gaps measured AT the stem edge: over the glyph's body
/// band, the runs of rows where the side edge falls back more than one scan
/// pitch from the median edge, bracketed by rows where the edge is present.
/// For dashed styles (MCA U) this is the style's own dash gap; for solid
/// stems it is empty. Font-measured, never a constant.
fn edge_white_gaps(
    p: &OutlineProfile,
    band: (f64, f64),
    side: Side,
    median_edge: f64,
) -> Vec<f64> {
    let band_rows: Vec<&kni_metrics::outline_spacing::ScanRow> = p
        .rows
        .iter()
        .filter(|r| r.span_hi > band.0 && r.span_lo < band.1)
        .collect();
    let mut gaps = Vec::new();
    let mut cur = 0.0_f64;
    let mut seen = false;
    for r in band_rows {
        let edge = match side {
            Side::Left => r.ink.first().map(|iv| iv.left),
            Side::Right => r.ink.last().map(|iv| iv.right),
        };
        let at_edge = edge.map(|e| (e - median_edge).abs() <= p.row_step).unwrap_or(false);
        if at_edge {
            if seen && cur > 0.0 {
                gaps.push(cur);
            }
            cur = 0.0;
            seen = true;
        } else if seen {
            cur += r.weight;
        }
    }
    gaps
}

/// Apply the layer. With the gate closed this is a pure no-op (bit-identical
/// downstream). With the gate open, `solution.glyphs` sidebearings/advances
/// are nudged toward stem-stem class consistency as described in the module
/// docs; every other solution field is untouched.
pub fn apply(
    solution: &mut SpacingSolution,
    profiles: &[OutlineProfile],
    policy: &OohhPolicy,
) -> OohhReport {
    let mut report = OohhReport {
        status: OohhStatus::Off,
        stem_right: 0,
        stem_left: 0,
        class_pairs: 0,
        target_gap: None,
        glyphs_adjusted: 0,
        max_applied_delta: 0.0,
        min_bbox_gap: None,
        min_bbox_gap_basis: "none",
    };
    if !policy.enabled {
        return report;
    }
    // Solved-metric sanity: without usable heights there is no band to
    // measure over (the degraded population floor ships x_height ==
    // cap_height == median ink height, which this refuses).
    if !(solution.baseline.is_finite()
        && solution.x_height.is_finite()
        && solution.cap_height.is_finite()
        && solution.x_height > 0.0
        && solution.cap_height > 0.0)
    {
        report.status = OohhStatus::NotApplicable("solution heights non-finite or non-positive");
        return report;
    }
    if (solution.cap_height - solution.x_height).abs() <= f64::EPSILON {
        report.status = OohhStatus::NotApplicable("x_height == cap_height: bands indistinguishable");
        return report;
    }

    // Per-glyph stem sides, keyed by glyph id (BTreeMap: stable iteration).
    // Zero-ink glyphs (space) and .notdef are excluded: space has no stem by
    // construction and .notdef is never typed, so letter-adjacency
    // consistency must not tune its box.
    let mut right: BTreeMap<String, StemSide> = BTreeMap::new();
    let mut left: BTreeMap<String, StemSide> = BTreeMap::new();
    let solved_ids: std::collections::BTreeSet<&str> =
        solution.glyphs.iter().map(|g| g.glyph_id.as_str()).collect();
    for p in profiles {
        if p.glyph_id == ".notdef" || p.ink_area <= 0.0 || !solved_ids.contains(p.glyph_id.as_str()) {
            continue;
        }
        let Some(band) = body_band(solution, p) else { continue };
        if let Some(s) = classify_side(p, band, Side::Right) {
            right.insert(p.glyph_id.clone(), s);
        }
        if let Some(s) = classify_side(p, band, Side::Left) {
            left.insert(p.glyph_id.clone(), s);
        }
    }
    report.stem_right = right.len();
    report.stem_left = left.len();

    // Pair gaps measured from the pair's OWN ink: at the natural placement
    // (right origin at left.advance) the shipped-frame band gap is
    //   gap = rsb(L) + lsb(R) + (ink_xmax(L) - stem_edge(L))
    //       + (stem_edge(R) - ink_xmin(R))
    // i.e. the sidebearing sum corrected by each side's measured median stem
    // edge, not by the bbox extreme (a 1-unit stair or serif tip does not
    // define the stem wall). Self pairs (H-H) are included: they are the
    // canonical stem-adjacency test pairs.
    let bearings: BTreeMap<&str, (f64, f64)> = solution
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.as_str(), (g.lsb, g.rsb)))
        .collect();
    let prof: BTreeMap<&str, &OutlineProfile> =
        profiles.iter().map(|p| (p.glyph_id.as_str(), p)).collect();
    let mut gaps: Vec<f64> = Vec::new();
    // (left id, right id, gap) kept for the desired-bearing medians below.
    let mut rows: Vec<(&str, &str, f64, f64, f64)> = Vec::new(); // l, r, gap, res_l, res_r
    for (lid, ls) in &right {
        let lp = match prof.get(lid.as_str()) {
            Some(p) => p,
            None => continue,
        };
        let (_l_lsb, l_rsb) = match bearings.get(lid.as_str()) {
            Some(b) => *b,
            None => continue,
        };
        let res_l = lp.bounds[2] - ls.median_edge;
        for (rid, rs) in &left {
            let rp = match prof.get(rid.as_str()) {
                Some(p) => p,
                None => continue,
            };
            let (r_lsb, _) = match bearings.get(rid.as_str()) {
                Some(b) => *b,
                None => continue,
            };
            let res_r = rs.median_edge - rp.bounds[0];
            let gap = l_rsb + r_lsb + res_l + res_r;
            if !gap.is_finite() {
                continue;
            }
            gaps.push(gap);
            rows.push((lid.as_str(), rid.as_str(), gap, res_l, res_r));
        }
    }
    report.class_pairs = gaps.len();
    if gaps.len() < MIN_CLASS_PAIRS {
        report.status = OohhStatus::InsufficientPopulation;
        return report;
    }
    let Some(target) = median(&mut gaps) else {
        report.status = OohhStatus::InsufficientPopulation;
        return report;
    };
    report.target_gap = Some(target);

    // Desired bearings from the CURRENT bearings of the partners (one
    // simultaneous step): rsb'(L) = median over partners R of
    // target - lsb(R) - res_l(L) - res_r(R); lsb'(R) symmetrically.
    let mut desired_rsb: BTreeMap<String, f64> = BTreeMap::new();
    let mut desired_lsb: BTreeMap<String, f64> = BTreeMap::new();
    for lid in right.keys() {
        let mut wants: Vec<f64> = rows
            .iter()
            .filter(|r| r.0 == lid.as_str())
            .map(|r| target - bearings[r.1].0 - r.3 - r.4)
            .collect();
        if let Some(m) = median(&mut wants) {
            desired_rsb.insert(lid.clone(), m);
        }
    }
    for rid in left.keys() {
        let mut wants: Vec<f64> = rows
            .iter()
            .filter(|r| r.1 == rid.as_str())
            .map(|r| target - bearings[r.0].1 - r.3 - r.4)
            .collect();
        if let Some(m) = median(&mut wants) {
            desired_lsb.insert(rid.clone(), m);
        }
    }

    // Clamp: at most MAX_MOVE_FRAC_OF_TARGET of the class target per pass,
    // floored at the class's own largest scan pitch (font-derived) so a
    // near-zero target still permits resolution-scale tuning; and never
    // below a zero bearing.
    let max_pitch = profiles
        .iter()
        .filter(|p| right.contains_key(&p.glyph_id) || left.contains_key(&p.glyph_id))
        .map(|p| p.row_step)
        .fold(0.0_f64, f64::max);
    let bound = (MAX_MOVE_FRAC_OF_TARGET * target.abs()).max(max_pitch);

    // Minimum positive bbox gap for stem-class pairs: the style's own
    // median stem-edge white gap (dash gap for
    // dashed styles), floored at the class's largest scan pitch (the
    // measurement's own resolution at this font's scale). No constants.
    let mut white: Vec<f64> = Vec::new();
    for p in profiles {
        let Some(band) = body_band(solution, p) else { continue };
        if let Some(s) = right.get(&p.glyph_id) {
            white.extend(edge_white_gaps(p, band, Side::Right, s.median_edge));
        }
        if let Some(s) = left.get(&p.glyph_id) {
            white.extend(edge_white_gaps(p, band, Side::Left, s.median_edge));
        }
    }
    let dash_gap = median(&mut white).unwrap_or(0.0);
    // The floor is the class's own scan pitch, NOT the
    // dash gap. Measured on MCA U the dash gap is 120 units = 3.4x the
    // natural stem gap (34.9): flooring at dash-gap scale re-spaced the
    // whole font to 60/60 bearings (median shift + containment cascade),
    // which is a redesign, not a contact guard. The contact guard only
    // needs a gap the style's own measurement can still resolve: one scan
    // pitch at this font's scale. dash_gap stays measured and receipted
    // for provenance.
    let min_gap = max_pitch;
    let min_basis = "max-stem-class-scan-pitch(resolution floor; dash_gap measured separately)";
    let half_floor = min_gap / 2.0;
    report.min_bbox_gap = Some(min_gap);
    report.min_bbox_gap_basis = min_basis;
    eprintln!("oohh_debug\ttarget\t{}\tbound\t{}\tdash_gap\t{}\tmin_bbox_gap\t{}\tbasis\t{}", target, bound, dash_gap, min_gap, min_basis);

    let mut adjusted = 0usize;
    let mut max_delta = 0.0_f64;
    for g in solution.glyphs.iter_mut() {
        // Floor applies only to stem-class glyphs the layer is actually
        // moving: their final bearings stay at or above half the
        // style-derived minimum positive bbox gap, so two adjusted bboxes
        // always keep at least min_bbox_gap of white between them (no
        // zero/negative contact), and never below zero. Non-stem glyphs
        // (space, punctuation, anything without a class partner) stay
        // untouched.
        // Partial retraction on a negative desired move only: downward
        // moves stop at half the style-derived minimum positive bbox gap
        // (never at zero/contact); upward and zero moves are untouched, so
        // the floor can never re-space a glyph the layer did not want to
        // lower (an unconditional floor forced ALL stem bearings up to
        // dash_gap/2).
        let dr = desired_rsb
            .get(&g.glyph_id)
            .map(|d| {
                let raw = (*d - g.rsb).clamp(-bound, bound);
                if raw < 0.0 { raw.max(half_floor - g.rsb).max(-g.rsb) } else { raw }
            })
            .unwrap_or(0.0);
        let dl = desired_lsb
            .get(&g.glyph_id)
            .map(|d| {
                let raw = (*d - g.lsb).clamp(-bound, bound);
                if raw < 0.0 { raw.max(half_floor - g.lsb).max(-g.lsb) } else { raw }
            })
            .unwrap_or(0.0);
        if dr != 0.0 || dl != 0.0 {
            eprintln!("oohh_debug\tglyph\t{}\tdesired_rsb\t{:?}\tdesired_lsb\t{:?}\tbound\t{}\thalf_floor\t{}\tdr\t{}\tdl\t{}", g.glyph_id, desired_rsb.get(&g.glyph_id), desired_lsb.get(&g.glyph_id), bound, half_floor, dr, dl);
            g.rsb += dr;
            g.lsb += dl;
            g.advance += dr + dl; // invariant: advance = ink width + lsb + rsb
            adjusted += 1;
            max_delta = max_delta.max(dr.abs()).max(dl.abs());
        }
    }
    report.glyphs_adjusted = adjusted;
    report.max_applied_delta = max_delta;
    report.status = OohhStatus::Applied;
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
    use kni_metrics::self_anchored_spacing::{GlyphSpacing, SpaceStatus};

    const STEP: f64 = 10.0;

    /// Rect-ish synthetic glyph: rows y in [0, height) at STEP pitch; each
    /// row's ink is [left_edge(y), right_edge(y)). Edges are closures so a
    /// stem is a constant and a bowl is a curve.
    fn profile(
        id: &str,
        height: f64,
        left_edge: &dyn Fn(f64) -> f64,
        right_edge: &dyn Fn(f64) -> f64,
    ) -> OutlineProfile {
        let n = (height / STEP) as usize;
        let mut rows = Vec::new();
        let (mut min_x, mut max_x) = (f64::MAX, f64::MIN);
        for i in 0..n {
            let y = i as f64 * STEP;
            let (l, r) = (left_edge(y), right_edge(y));
            min_x = min_x.min(l);
            max_x = max_x.max(r);
            rows.push(ScanRow {
                y,
                weight: STEP,
                ink: vec![InkInterval { left: l, right: r }],
                span_lo: y,
                span_hi: y + STEP,
            });
        }
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: String::new(),
            upm: 1000,
            origin: [0.0, 0.0],
            rows,
            bounds: [min_x, 0.0, max_x, height],
            ink_area: 1.0,
            counter_area: 0.0,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: "test".into(),
            row_step: STEP,
            flatten_tolerance: 0.0,
        }
    }

    /// Stem rectangle: constant sides. H/I/n shapes for the consistency class.
    fn stem_glyph(id: &str, height: f64, x0: f64, x1: f64) -> OutlineProfile {
        profile(id, height, &move |_| x0, &move |_| x1)
    }

    /// Bowl: sides swing far beyond one scan pitch across the band.
    fn bowl_glyph(id: &str, height: f64) -> OutlineProfile {
        profile(
            id,
            height,
            &move |y| 40.0 + 60.0 * (std::f64::consts::PI * y / height).sin(),
            &move |y| 400.0 - 60.0 * (std::f64::consts::PI * y / height).sin(),
        )
    }

    fn empty_solution() -> SpacingSolution {
        SpacingSolution {
            baseline: 0.0,
            x_height: 500.0,
            x_height_source: kni_metrics::self_anchored_spacing::XHeightSource::Ctx,
            cap_height: 700.0,
            glyphs: vec![],
            pairs: vec![],
            font_median_pair_target: None,
            space_status: SpaceStatus::Absent,
            excluded_pairs: vec![],
            complete: true,
            excluded_self_pairs: 0,
            excluded_below_epsilon: 0,
            excluded_unmeasurable: 0,
            numeric_failed_pairs: 0,
            geometric_hold_pairs: 0,
            no_accepted_candidate_pairs: 0,
            hold_reasons: vec![],
            pair_ledger: vec![],
            fallback_pairs: vec![],
            fallback_natural_clear_pairs: 0,
            fallback_verified_pairs: 0,
            numeric_failed_nonfinite: 0,
            numeric_failed_malformed: 0,
            numeric_failed_natural_unverifiable: 0,
            numeric_failed_natural_frame_conflict: 0,
            accounting_residual: 0,
            accounting_closed: true,
            policy_derivation: String::new(),
            unobserved_policy: vec![],
            anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run(),
            contrast_floor_adjustments: vec![],
            contrast_floor_failures: vec![],
        }
    }

    fn glyph(id: &str, lsb: f64, rsb: f64, ink_width: f64) -> GlyphSpacing {
        GlyphSpacing { glyph_id: id.into(), lsb, rsb, advance: ink_width + lsb + rsb }
    }

    fn spacing_eq(a: &SpacingSolution, b: &SpacingSolution) -> bool {
        a.glyphs.len() == b.glyphs.len()
            && a.glyphs.iter().zip(b.glyphs.iter()).all(|(x, y)| {
                x.glyph_id == y.glyph_id && x.lsb == y.lsb && x.rsb == y.rsb && x.advance == y.advance
            })
    }

    /// Three stem glyphs (H, I, n) + one bowl (o). Stem ink width 400
    /// ([0,400]). Bearings deliberately inconsistent: right side 10/40/70.
    fn fixture() -> (SpacingSolution, Vec<OutlineProfile>) {
        let mut sol = empty_solution();
        sol.glyphs = vec![
            glyph("H", 20.0, 10.0, 400.0),
            glyph("I", 20.0, 40.0, 400.0),
            glyph("n", 20.0, 70.0, 400.0),
            glyph("o", 20.0, 20.0, 420.0),
        ];
        let profiles = vec![
            stem_glyph("H", 700.0, 0.0, 400.0),
            stem_glyph("I", 700.0, 0.0, 400.0),
            stem_glyph("n", 500.0, 0.0, 400.0),
            bowl_glyph("o", 500.0),
        ];
        (sol, profiles)
    }

    fn on() -> OohhPolicy {
        OohhPolicy { enabled: true }
    }

    /// Own-ink stem-stem gap of an ordered pair at current bearings
    /// (residuals are zero for the synthetic rectangles).
    fn pair_gap(sol: &SpacingSolution, l: &str, r: &str) -> f64 {
        let gl = sol.glyphs.iter().find(|g| g.glyph_id == l).unwrap();
        let gr = sol.glyphs.iter().find(|g| g.glyph_id == r).unwrap();
        gl.rsb + gr.lsb
    }

    #[test]
    fn disabled_gate_is_bit_identical() {
        let (mut sol, profiles) = fixture();
        let before = sol.clone();
        let rep = apply(&mut sol, &profiles, &OohhPolicy::from_flag(false));
        assert_eq!(rep.status, OohhStatus::Off);
        assert!(spacing_eq(&sol, &before));
        assert!(rep.receipt_line().is_empty(), "off gate writes no receipt bytes");
    }

    #[test]
    fn stem_sides_classified_and_bowl_excluded() {
        let (mut sol, profiles) = fixture();
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::Applied);
        // H, I, n are stems on both sides; the bowl 'o' is neither.
        assert_eq!((rep.stem_right, rep.stem_left), (3, 3));
        // 3x3 ordered stem-stem pairs (self pairs included: HH, II, nn).
        assert_eq!(rep.class_pairs, 9);
    }

    #[test]
    fn gaps_converge_toward_class_median_without_breaking_invariants() {
        let (mut sol, profiles) = fixture();
        // Before: gaps span rsb {10,40,70} + lsb 20 => 30..90.
        let spread_before = pair_gap(&sol, "n", "H") - pair_gap(&sol, "H", "H");
        assert_eq!(spread_before, 60.0);
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::Applied);
        let target = rep.target_gap.unwrap();
        // Class gaps: values 30..90 step ~6.7, median = 60 (30+... target is a class median).
        assert!(target > 30.0 && target < 90.0);
        // After: every stem-stem gap strictly inside the old spread.
        for l in ["H", "I", "n"] {
            for r in ["H", "I", "n"] {
                let g = pair_gap(&sol, l, r);
                assert!(g > 30.0 && g < 90.0, "gap {l}{r} = {g}");
            }
        }
        // Invariant advance = ink width + lsb + rsb holds for every glyph.
        for (g, w) in [("H", 400.0), ("I", 400.0), ("n", 400.0), ("o", 420.0)] {
            let gs = sol.glyphs.iter().find(|x| x.glyph_id == g).unwrap();
            assert_eq!(gs.advance, w + gs.lsb + gs.rsb);
            assert!(gs.lsb >= 0.0 && gs.rsb >= 0.0);
        }
        // The bowl is untouched (not a stem).
        let o = sol.glyphs.iter().find(|x| x.glyph_id == "o").unwrap();
        assert_eq!((o.lsb, o.rsb, o.advance), (20.0, 20.0, 460.0));
        assert!(rep.glyphs_adjusted > 0 && rep.max_applied_delta > 0.0);
    }

    #[test]
    fn already_consistent_class_is_a_noop_pass() {
        let (mut sol, profiles) = fixture();
        for g in sol.glyphs.iter_mut() {
            if g.glyph_id != "o" {
                g.lsb = 20.0;
                g.rsb = 40.0;
                g.advance = 400.0 + 60.0;
            }
        }
        let before = sol.clone();
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::Applied);
        assert_eq!(rep.glyphs_adjusted, 0);
        assert_eq!(rep.max_applied_delta, 0.0);
        assert!(spacing_eq(&sol, &before));
        assert_eq!(rep.target_gap, Some(60.0));
    }

    #[test]
    fn move_is_clamped_and_bearing_never_negative() {
        let (mut sol, profiles) = fixture();
        // One wild outlier: I's rsb 400 pushes the class spread far out.
        sol.glyphs.iter_mut().find(|g| g.glyph_id == "I").unwrap().rsb = 400.0;
        sol.glyphs.iter_mut().find(|g| g.glyph_id == "I").unwrap().advance = 400.0 + 20.0 + 400.0;
        let before_i = sol.glyphs.iter().find(|g| g.glyph_id == "I").unwrap().clone();
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::Applied);
        let bound = (MAX_MOVE_FRAC_OF_TARGET * rep.target_gap.unwrap().abs()).max(STEP);
        let after_i = sol.glyphs.iter().find(|g| g.glyph_id == "I").unwrap();
        assert!((after_i.rsb - before_i.rsb).abs() <= bound + 1e-9);
        for g in &sol.glyphs {
            assert!(g.lsb >= 0.0 && g.rsb >= 0.0);
        }
    }

    #[test]
    fn insufficient_population_refuses_without_touching() {
        let mut sol = empty_solution();
        sol.glyphs = vec![glyph("H", 20.0, 10.0, 400.0)];
        let profiles = vec![stem_glyph("H", 700.0, 0.0, 400.0)];
        let before = sol.clone();
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::InsufficientPopulation);
        assert_eq!(rep.class_pairs, 1); // only H-H
        assert!(spacing_eq(&sol, &before));
    }

    #[test]
    fn degenerate_solution_metrics_are_not_applicable() {
        let (mut sol, profiles) = fixture();
        let before = sol.clone();
        sol.x_height = 0.0; // degraded population floor shape
        sol.cap_height = 0.0;
        let rep = apply(&mut sol, &profiles, &on());
        assert!(matches!(rep.status, OohhStatus::NotApplicable(_)));
        assert!(spacing_eq(&sol, &before));
        let (mut sol2, profiles2) = fixture();
        let before2 = sol2.clone();
        sol2.x_height = 700.0; // == cap_height: bands indistinguishable
        let rep2 = apply(&mut sol2, &profiles2, &on());
        assert!(matches!(rep2.status, OohhStatus::NotApplicable(_)));
        assert!(spacing_eq(&sol2, &before2));
    }

    #[test]
    fn notdef_and_zero_ink_glyphs_are_excluded() {
        let (mut sol, mut profiles) = fixture();
        sol.glyphs.push(glyph(".notdef", 20.0, 20.0, 500.0));
        profiles.push(stem_glyph(".notdef", 700.0, 0.0, 500.0));
        let mut space_p = stem_glyph("space", 700.0, 0.0, 400.0);
        space_p.rows.clear();
        space_p.ink_area = 0.0;
        space_p.bounds = [0.0, 0.0, 0.0, 0.0];
        sol.glyphs.push(glyph("space", 0.0, 0.0, 250.0));
        profiles.push(space_p);
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::Applied);
        assert_eq!((rep.stem_right, rep.stem_left), (3, 3));
        let nd = sol.glyphs.iter().find(|g| g.glyph_id == ".notdef").unwrap();
        assert_eq!((nd.lsb, nd.rsb, nd.advance), (20.0, 20.0, 540.0));
        let sp = sol.glyphs.iter().find(|g| g.glyph_id == "space").unwrap();
        assert_eq!((sp.lsb, sp.rsb, sp.advance), (0.0, 0.0, 250.0));
    }

    #[test]
    fn lowercase_and_uppercase_bands_both_classify() {
        // n is x-height, H cap-height; both must land in the class (the
        // owner's H-n style cross-case stem pairs depend on it).
        let (mut sol, profiles) = fixture();
        let rep = apply(&mut sol, &profiles, &on());
        assert_eq!(rep.status, OohhStatus::Applied);
        assert!(rep.receipt_line().contains("stem_right\t3"));
    }

    #[test]
    fn receipt_line_is_single_stable_row() {
        let (mut sol, profiles) = fixture();
        let rep = apply(&mut sol, &profiles, &on());
        let line = rep.receipt_line();
        assert!(line.starts_with("spacing_oohh\tstatus\tapplied\t"));
        assert!(line.ends_with('\n') && line.matches('\n').count() == 1);
        assert!(line.contains("class_pairs\t9") && line.contains("target_gap\t"));
    }
}
