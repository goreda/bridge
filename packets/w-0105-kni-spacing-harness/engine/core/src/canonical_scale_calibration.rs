//! SOURCE-FONT REFERENCE CALIBRATION v8 (new file: engine/core/src/canonical_scale_calibration.rs). UNRUN SOURCE, std only.
//! Separate from the vertical-envelope convention in canonical_scale.rs: that one is a candidate canonical convention
//! (B); this is a calibration against an independent source font (A). They are different things and never merged.
//! Not renderer metadata: the record carries its own provenance (font pin, tile pin, glyph, axis, threshold, frame,
//! declaring party) and is scoped to the declared render cohort only. Applying it to other styles is an owner
//! declaration recorded in `render_cohort`, never a measured fact, and is only exposed through `scale_for`, which checks
//! cohort id and frame binding. Old scale values (legacy cache / receipts) are never relabeled by this module.
//! scale (output units per pixel) = target_upm / source_upm * source_glyph_extent_units / pixel_extent.
//! MEASUREMENT UNCERTAINTY: `pixel_quantum` is resolution information only, NOT an error bound. The error bound is the
//! explicit, caller-stated [px_lo, px_hi] with a `bound_basis` text. The resulting scale interval is CONDITIONAL on those
//! stated bounds (not physical certainty). Isotropy (one scale for both axes) is an assumption, recorded in the receipt.
//! Nothing here hardcodes a font, glyph height or K.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Axis { Vertical, Horizontal }

#[derive(Clone, Debug, PartialEq)]
pub enum CalibrationError {
    InvalidTargetUpm,
    InvalidSourceUpm,
    EmptyFontPin,
    EmptyDeclaringParty,
    EmptyRenderCohort,
    NoMatches,
    EmptyField { glyph: String, field: &'static str },
    InvalidExtent { glyph: String, field: &'static str },
    /// px_lo/px_hi must satisfy 0 < px_lo <= pixels <= px_hi (all finite).
    InvalidBounds { glyph: String },
    /// A computed scale (estimate or interval end) is not finite and > 0 (overflow, underflow or zero).
    NumericRange { glyph: String },
    DuplicateMatch { glyph: String, axis: Axis, threshold: String },
    /// Matches carry different frame bindings: one calibration, one binding.
    FrameBindingMismatch { glyph: String },
    /// Two matches' conditional scale intervals do not intersect: reported, never averaged.
    /// `contributors` = every match ("glyph|axis|threshold") already folded into the running consensus; `current` = the match
    /// whose interval does not intersect it. The conflict is with the accumulated consensus, not only the first match.
    Conflict { contributors: Vec<String>, current: String },
    /// scale_for was asked for another cohort or frame binding than the one declared.
    ScopeMismatch,
    /// scale_for on a record whose primary estimate lies outside the consensus interval.
    PrimaryOutsideConsensus,
}

/// One glyph matched between the reference font and a capture tile.
#[derive(Clone, Debug, PartialEq)]
pub struct ReferenceMatch {
    glyph: String, axis: Axis, units: f64, pixels: f64, pixel_quantum: f64, px_lo: f64, px_hi: f64, bound_basis: String,
    tile_sha: String, threshold: String, frame_binding: String,
}
impl ReferenceMatch {
    /// `pixel_quantum`: resolution information (e.g. 1.0 for an integer bbox), not an error bound.
    /// `px_lo..=px_hi`: the caller's stated measurement bounds; `bound_basis` says how they were obtained
    /// (e.g. "conditional: +-0.5 px if the bbox edge is exact" or "observed spread across thresholds").
    pub fn new(glyph: &str, axis: Axis, units: f64, pixels: f64, pixel_quantum: f64, px_lo: f64, px_hi: f64, bound_basis: &str,
               tile_sha: &str, threshold: &str, frame_binding: &str) -> Result<Self, CalibrationError> {
        for (v, f) in [(glyph, "glyph"), (bound_basis, "bound_basis"), (tile_sha, "tile_sha"), (threshold, "threshold"), (frame_binding, "frame_binding")] {
            if v.is_empty() { return Err(CalibrationError::EmptyField { glyph: glyph.to_string(), field: f }); }
        }
        if !(units.is_finite() && units > 0.0) { return Err(CalibrationError::InvalidExtent { glyph: glyph.to_string(), field: "units" }); }
        if !(pixels.is_finite() && pixels > 0.0) { return Err(CalibrationError::InvalidExtent { glyph: glyph.to_string(), field: "pixels" }); }
        if !(pixel_quantum.is_finite() && pixel_quantum >= 0.0) { return Err(CalibrationError::InvalidExtent { glyph: glyph.to_string(), field: "pixel_quantum" }); }
        if !(px_lo.is_finite() && px_hi.is_finite() && px_lo > 0.0 && px_lo <= pixels && pixels <= px_hi) {
            return Err(CalibrationError::InvalidBounds { glyph: glyph.to_string() });
        }
        Ok(ReferenceMatch { glyph: glyph.to_string(), axis, units, pixels, pixel_quantum, px_lo, px_hi, bound_basis: bound_basis.to_string(),
                            tile_sha: tile_sha.to_string(), threshold: threshold.to_string(), frame_binding: frame_binding.to_string() })
    }
    pub fn glyph(&self) -> &str { &self.glyph }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CalibrationStatus {
    /// primary estimate lies inside the conditional consensus interval.
    ReferenceCalibrated,
    /// matches are mutually compatible but the primary estimate is outside their consensus: no scale is selected
    /// (no clamp, no average); the caller must choose a primary or fix the data.
    ReferencePrimaryOutsideConsensus,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReferenceCalibration {
    status: CalibrationStatus,
    font_pin: String, source_upm: f64, target_upm: f64,
    declaring_party: String, render_cohort: String, frame_binding: String,
    matches: Vec<ReferenceMatch>,
    /// unrounded estimate of the FIRST (designated primary) match.
    primary_estimate: f64,
    /// intersection of all matches' CONDITIONAL intervals.
    interval_lo: f64, interval_hi: f64,
}
/// Checked scale: finite and > 0, else NumericRange. ACCEPTED DOMAIN LIMIT: intermediate ratios (target/source, units/px)
/// may overflow or underflow even when the final product would be finite; such inputs are refused conservatively as
/// NumericRange rather than recomputed in a wider form. Inputs outside the ordinary range are not supported.
fn checked_scale(target: f64, source: f64, units: f64, px: f64, glyph: &str) -> Result<f64, CalibrationError> {
    let s = (target / source) * (units / px);
    if s.is_finite() && s > 0.0 { Ok(s) } else { Err(CalibrationError::NumericRange { glyph: glyph.to_string() }) }
}

pub fn calibrate(font_pin: &str, source_upm: f64, target_upm: f64, declaring_party: &str, render_cohort: &str, matches: Vec<ReferenceMatch>) -> Result<ReferenceCalibration, CalibrationError> {
    if !(target_upm.is_finite() && target_upm > 0.0) { return Err(CalibrationError::InvalidTargetUpm); }
    if !(source_upm.is_finite() && source_upm > 0.0) { return Err(CalibrationError::InvalidSourceUpm); }
    if font_pin.is_empty() { return Err(CalibrationError::EmptyFontPin); }
    if declaring_party.is_empty() { return Err(CalibrationError::EmptyDeclaringParty); }
    if render_cohort.is_empty() { return Err(CalibrationError::EmptyRenderCohort); }
    if matches.is_empty() { return Err(CalibrationError::NoMatches); }
    let frame_binding = matches[0].frame_binding.clone();
    for (i, m) in matches.iter().enumerate() {
        if m.frame_binding != frame_binding { return Err(CalibrationError::FrameBindingMismatch { glyph: m.glyph.clone() }); }
        if matches[..i].iter().any(|p| p.glyph == m.glyph && p.axis == m.axis && p.threshold == m.threshold) {
            return Err(CalibrationError::DuplicateMatch { glyph: m.glyph.clone(), axis: m.axis, threshold: m.threshold.clone() });
        }
    }
    // larger pixel extent => smaller scale; every end must itself be finite and > 0
    let iv = |m: &ReferenceMatch| -> Result<(f64, f64), CalibrationError> {
        checked_scale(target_upm, source_upm, m.units, m.pixels, &m.glyph)?;
        Ok((checked_scale(target_upm, source_upm, m.units, m.px_hi, &m.glyph)?, checked_scale(target_upm, source_upm, m.units, m.px_lo, &m.glyph)?))
    };
    let (mut lo, mut hi) = iv(&matches[0])?;
    let id_of = |m: &ReferenceMatch| format!("{}|{:?}|{}", m.glyph, m.axis, m.threshold);
    let mut contributors: Vec<String> = vec![id_of(&matches[0])];
    for m in &matches[1..] {
        let (l, h) = iv(m)?;
        if l > hi || h < lo { return Err(CalibrationError::Conflict { contributors, current: id_of(m) }); }
        contributors.push(id_of(m));
        lo = lo.max(l); hi = hi.min(h);
    }
    let primary_estimate = checked_scale(target_upm, source_upm, matches[0].units, matches[0].pixels, &matches[0].glyph)?;
    let status = if primary_estimate >= lo && primary_estimate <= hi { CalibrationStatus::ReferenceCalibrated } else { CalibrationStatus::ReferencePrimaryOutsideConsensus };
    Ok(ReferenceCalibration { status, font_pin: font_pin.to_string(), source_upm, target_upm, declaring_party: declaring_party.to_string(),
        render_cohort: render_cohort.to_string(), frame_binding, matches, primary_estimate, interval_lo: lo, interval_hi: hi })
}

impl ReferenceCalibration {
    pub fn status(&self) -> CalibrationStatus { self.status }
    /// Full-precision primary estimate (never rounded). Present whatever the status; it is not "selected" unless
    /// the status is ReferenceCalibrated.
    pub fn primary_estimate(&self) -> f64 { self.primary_estimate }
    /// Conditional consensus interval (conditional on the matches' stated bounds, not physical certainty).
    pub fn conditional_interval(&self) -> (f64, f64) { (self.interval_lo, self.interval_hi) }
    pub fn match_count(&self) -> usize { self.matches.len() }
    pub fn target_upm(&self) -> f64 { self.target_upm }
    pub fn render_cohort(&self) -> &str { &self.render_cohort }
    pub fn frame_binding(&self) -> &str { &self.frame_binding }
    /// Exact canonical record (receipt row + every match row): the identity to bind, not a hash.
    pub fn canonical_record(&self) -> String {
        let mut all = self.receipt_row();
        for r in self.match_records() { all.push_str(&r); }
        all
    }
    /// FNV-1a 64 over receipt_row + match_records (non-cryptographic integrity tag of the full calibration record).
    pub fn record_tag(&self) -> u64 {
        let mut h: u64 = 0xcbf29ce484222325;
        let mut all = self.receipt_row();
        for r in self.match_records() { all.push_str(&r); }
        for b in all.bytes() { h ^= u64::from(b); h = h.wrapping_mul(0x100000001b3); }
        h
    }
    /// Report-only rounding; never feed this back into geometry.
    pub fn display(&self, decimals: usize) -> String { format!("{:.*}", decimals, self.primary_estimate) }
    /// Selected scale for a render cohort + frame binding. Refuses another cohort/binding, and a record whose primary
    /// estimate is outside the consensus. Cohort sharing is the owner declaration recorded at calibration time.
    pub fn scale_for(&self, cohort: &str, frame_binding: &str) -> Result<f64, CalibrationError> {
        if cohort != self.render_cohort || frame_binding != self.frame_binding { return Err(CalibrationError::ScopeMismatch); }
        if self.status != CalibrationStatus::ReferenceCalibrated { return Err(CalibrationError::PrimaryOutsideConsensus); }
        Ok(self.primary_estimate)
    }
    /// Whether an externally supplied scale (e.g. a legacy cache/receipt value) lies in the conditional interval.
    /// Reports containment only; does not rewrite or rebind the legacy value.
    pub fn interval_contains(&self, other: f64) -> bool { other.is_finite() && other >= self.interval_lo && other <= self.interval_hi }
    /// Threshold-sensitivity record: one escaped row per measured threshold (glyph, axis, threshold, pixels, min, max)
    /// for every (glyph, axis) measured at more than one threshold. Pure record: a spread is neither an error nor hidden; whether it exceeds a stated bound is
    /// visible by comparing with the matches' px_lo/px_hi.
    pub fn threshold_sensitivity(&self) -> Vec<String> {
        let mut keys: Vec<(&str, Axis)> = vec![];
        for m in &self.matches { if !keys.iter().any(|k| k.0 == m.glyph && k.1 == m.axis) { keys.push((m.glyph.as_str(), m.axis)); } }
        let mut out = vec![];
        for (g, a) in keys {
            let v: Vec<&ReferenceMatch> = self.matches.iter().filter(|m| m.glyph == g && m.axis == a).collect();
            if v.len() < 2 { continue; }
            let mn = v.iter().map(|m| m.pixels).fold(f64::INFINITY, f64::min);
            let mx = v.iter().map(|m| m.pixels).fold(f64::NEG_INFINITY, f64::max);
            for m in v {
                out.push(format!("reference_calibration_threshold_sensitivity\t{}\t{:?}\t{}\t{:?}\t{:?}\t{:?}\n", esc(g), a, esc(&m.threshold), m.pixels, mn, mx));
            }
        }
        out
    }
    /// Per-match records, one TSV row each, strings escaped.
    pub fn match_records(&self) -> Vec<String> {
        self.matches.iter().map(|m| format!("reference_calibration_match\t{}\t{}\t{:?}\t{:?}\t{:?}\t{:?}\t{:?}\t{:?}\t{}\t{}\t{}\t{}\n",
            esc(&self.font_pin), esc(&m.glyph), m.axis, m.units, m.pixels, m.pixel_quantum, m.px_lo, m.px_hi, esc(&m.bound_basis),
            esc(&m.tile_sha), esc(&m.threshold), esc(&m.frame_binding))).collect()
    }
    pub fn receipt_row(&self) -> String {
        format!("reference_calibration\t{:?}\tfont_pin={}\tsource_upm={:?}\ttarget_upm={:?}\tprimary_estimate={:?}\tconditional_lo={:?}\tconditional_hi={:?}\tmatches={}\tdeclared_by={}\trender_cohort={}\tframe_binding={}\tisotropy=assumed\n",
            self.status, esc(&self.font_pin), self.source_upm, self.target_upm, self.primary_estimate, self.interval_lo, self.interval_hi,
            self.matches.len(), esc(&self.declaring_party), esc(&self.render_cohort), esc(&self.frame_binding))
    }
}
fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r") }

#[cfg(test)]
mod tests {
    use super::*;
    // fixture numbers are TEST INPUTS only (owner CSV / decoded font), not engine constants
    fn m(g: &str, a: Axis, u: f64, p: f64, lo: f64, hi: f64, thr: &str) -> ReferenceMatch {
        ReferenceMatch::new(g, a, u, p, 1.0, lo, hi, "conditional test bound", "tile-sha", thr, "frame-A").unwrap()
    }
    fn mh() -> ReferenceMatch { m("H", Axis::Vertical, 1333.0, 267.0, 266.5, 267.5, "thr128") }
    fn cal(v: Vec<ReferenceMatch>) -> Result<ReferenceCalibration, CalibrationError> { calibrate("font-sha", 2048.0, 1000.0, "owner", "cohort-1", v) }

    #[test]
    fn estimate_follows_formula_full_precision_and_rounding_is_report_only() {
        let c = cal(vec![mh()]).unwrap();
        assert_eq!(c.primary_estimate(), 1000.0 / 2048.0 * (1333.0 / 267.0));
        assert_eq!(c.status(), CalibrationStatus::ReferenceCalibrated);
        assert_ne!(c.display(3).parse::<f64>().unwrap(), c.primary_estimate());
        let (lo, hi) = c.conditional_interval();
        assert!(lo < c.primary_estimate() && c.primary_estimate() < hi);
    }
    #[test]
    fn x_is_vertical_1119_intervals_intersect_but_primary_may_fall_outside() {
        // x glyph height 1119 (raw x width would be 1120: not used). Bounds [222,224] = observed thr64..thr128 spread.
        // Intervals intersect ([t*1119/224, t*1119/267-side...] non-empty) yet the H estimate lies BELOW the consensus:
        // the status says so; nothing is clamped or averaged.
        let x = m("x", Axis::Vertical, 1119.0, 224.0, 222.0, 224.0, "thr128");
        let c = cal(vec![mh(), x]).unwrap();
        let (lo, hi) = c.conditional_interval();
        assert!(lo <= hi);
        assert_eq!(c.status(), CalibrationStatus::ReferencePrimaryOutsideConsensus);
        assert!(c.primary_estimate() < lo);
    }
    #[test]
    fn disjoint_conditional_intervals_are_a_typed_conflict_not_an_average() {
        let o = m("O", Axis::Vertical, 1333.0, 300.0, 299.5, 300.5, "thr128");
        assert_eq!(cal(vec![mh(), o]), Err(CalibrationError::Conflict { contributors: vec!["H|Vertical|thr128".into()], current: "O|Vertical|thr128".into() }));
    }
    #[test]
    fn primary_outside_consensus_selects_nothing() {
        // target=source: m1 units100 px10 (+-1) -> estimate 10, [9.0909.., 11.111..]; m2 units11 px1 exact -> [11,11]
        let m1 = ReferenceMatch::new("a", Axis::Vertical, 100.0, 10.0, 2.0, 9.0, 11.0, "b", "t1", "thr", "frame-A").unwrap();
        let m2 = ReferenceMatch::new("b", Axis::Vertical, 11.0, 1.0, 0.0, 1.0, 1.0, "b", "t2", "thr", "frame-A").unwrap();
        let c = calibrate("f", 1.0, 1.0, "owner", "cohort-1", vec![m1, m2]).unwrap();
        assert_eq!(c.status(), CalibrationStatus::ReferencePrimaryOutsideConsensus);
        assert_eq!(c.primary_estimate(), 10.0);
        assert_eq!(c.conditional_interval(), (11.0, 11.0));
        assert_eq!(c.scale_for("cohort-1", "frame-A"), Err(CalibrationError::PrimaryOutsideConsensus));
    }
    #[test]
    fn scale_for_checks_cohort_and_frame_binding() {
        let c = cal(vec![mh()]).unwrap();
        assert_eq!(c.scale_for("cohort-1", "frame-A"), Ok(c.primary_estimate()));
        assert_eq!(c.scale_for("cohort-2", "frame-A"), Err(CalibrationError::ScopeMismatch));
        assert_eq!(c.scale_for("cohort-1", "frame-B"), Err(CalibrationError::ScopeMismatch));
    }
    #[test]
    fn mixed_frame_bindings_are_refused() {
        let other = ReferenceMatch::new("O", Axis::Vertical, 1333.0, 267.0, 1.0, 266.5, 267.5, "b", "t", "thr128", "frame-B").unwrap();
        assert_eq!(cal(vec![mh(), other]), Err(CalibrationError::FrameBindingMismatch { glyph: "O".into() }));
    }
    #[test]
    fn numeric_extremes_are_typed() {
        // overflow: huge units over tiny pixels
        let big = ReferenceMatch::new("H", Axis::Vertical, f64::MAX, 1e-300, 0.0, 1e-300, 1e-300, "b", "t", "thr", "frame-A").unwrap();
        assert_eq!(calibrate("f", 1.0, 1.0, "o", "c", vec![big]), Err(CalibrationError::NumericRange { glyph: "H".into() }));
        // underflow to 0: tiny units over huge pixels
        let tiny = ReferenceMatch::new("H", Axis::Vertical, f64::MIN_POSITIVE, f64::MAX, 0.0, f64::MAX, f64::MAX, "b", "t", "thr", "frame-A").unwrap();
        assert_eq!(calibrate("f", 1.0, 1.0, "o", "c", vec![tiny]), Err(CalibrationError::NumericRange { glyph: "H".into() }));
        // px_hi large enough that the lower interval end underflows to 0 while the estimate is finite
        let edge = ReferenceMatch::new("H", Axis::Vertical, f64::MIN_POSITIVE, 1.0, 0.0, 1.0, f64::MAX, "b", "t", "thr", "frame-A").unwrap();
        assert_eq!(calibrate("f", 1.0, 1.0, "o", "c", vec![edge]), Err(CalibrationError::NumericRange { glyph: "H".into() }));
        // overflow through the upm ratio
        assert_eq!(calibrate("f", f64::MIN_POSITIVE, f64::MAX, "o", "c", vec![mh()]), Err(CalibrationError::NumericRange { glyph: "H".into() }));
    }
    #[test]
    fn typed_failures() {
        let ok = || vec![mh()];
        assert_eq!(calibrate("f", 2048.0, 0.0, "o", "c", ok()), Err(CalibrationError::InvalidTargetUpm));
        assert_eq!(calibrate("f", f64::NAN, 1000.0, "o", "c", ok()), Err(CalibrationError::InvalidSourceUpm));
        assert_eq!(calibrate("", 2048.0, 1000.0, "o", "c", ok()), Err(CalibrationError::EmptyFontPin));
        assert_eq!(calibrate("f", 2048.0, 1000.0, "", "c", ok()), Err(CalibrationError::EmptyDeclaringParty));
        assert_eq!(calibrate("f", 2048.0, 1000.0, "o", "", ok()), Err(CalibrationError::EmptyRenderCohort));
        assert_eq!(calibrate("f", 2048.0, 1000.0, "o", "c", vec![]), Err(CalibrationError::NoMatches));
        let dup = vec![mh(), mh()];
        assert_eq!(cal(dup), Err(CalibrationError::DuplicateMatch { glyph: "H".into(), axis: Axis::Vertical, threshold: "thr128".into() }));
        let n = |u: f64, p: f64, lo: f64, hi: f64| ReferenceMatch::new("H", Axis::Vertical, u, p, 1.0, lo, hi, "b", "t", "th", "fr");
        assert_eq!(n(f64::NAN, 267.0, 266.0, 268.0), Err(CalibrationError::InvalidExtent { glyph: "H".into(), field: "units" }));
        assert_eq!(n(1333.0, 0.0, 0.0, 1.0), Err(CalibrationError::InvalidExtent { glyph: "H".into(), field: "pixels" }));
        assert_eq!(n(1333.0, 267.0, 268.0, 269.0), Err(CalibrationError::InvalidBounds { glyph: "H".into() })); // lo > pixels
        assert_eq!(n(1333.0, 267.0, 266.0, 266.5), Err(CalibrationError::InvalidBounds { glyph: "H".into() })); // hi < pixels
        assert_eq!(n(1333.0, 267.0, 0.0, 268.0), Err(CalibrationError::InvalidBounds { glyph: "H".into() }));
        assert_eq!(n(1333.0, 267.0, 266.0, f64::INFINITY), Err(CalibrationError::InvalidBounds { glyph: "H".into() }));
        assert_eq!(ReferenceMatch::new("H", Axis::Vertical, 1333.0, 267.0, 1.0, 266.0, 268.0, "", "t", "th", "fr"), Err(CalibrationError::EmptyField { glyph: "H".into(), field: "bound_basis" }));
        assert_eq!(ReferenceMatch::new("", Axis::Vertical, 1333.0, 267.0, 1.0, 266.0, 268.0, "b", "t", "th", "fr"), Err(CalibrationError::EmptyField { glyph: "".into(), field: "glyph" }));
    }
    #[test]
    fn same_glyph_other_axis_or_threshold_is_not_a_duplicate_and_sensitivity_is_recorded() {
        let h64 = m("H", Axis::Vertical, 1333.0, 267.0, 266.5, 267.5, "thr64");
        let x128 = m("x", Axis::Vertical, 1119.0, 224.0, 221.5, 224.5, "thr128");
        let x64 = m("x", Axis::Vertical, 1119.0, 222.0, 221.5, 224.5, "thr64");
        let hw = m("H", Axis::Horizontal, 999.0, 200.0, 199.5, 200.5, "thr128");
        let c = cal(vec![mh(), h64, x128, x64, hw]).unwrap();
        let s = c.threshold_sensitivity();
        assert_eq!(s.len(), 4); // H vertical x2 and x vertical x2; H horizontal is a single measurement
        assert!(s.contains(&"reference_calibration_threshold_sensitivity\tx\tVertical\tthr64\t222.0\t222.0\t224.0\n".to_string()));
        assert!(s.contains(&"reference_calibration_threshold_sensitivity\tH\tVertical\tthr128\t267.0\t267.0\t267.0\n".to_string()));
        assert!(s.iter().all(|r| r.matches('\t').count() == 6 && r.matches('\n').count() == 1));
    }
    #[test]
    fn receipt_is_escaped_and_carries_provenance_interval_and_assumptions() {
        let c = calibrate("f\tx", 2048.0, 1000.0, "ow\nner", "cohort\t1", vec![mh()]).unwrap();
        let r = c.receipt_row();
        assert_eq!(r.matches('\n').count(), 1);
        assert!(r.starts_with("reference_calibration\tReferenceCalibrated\t"));
        assert!(r.contains("font_pin=f\\tx") && r.contains("declared_by=ow\\nner") && r.contains("render_cohort=cohort\\t1")
            && r.contains("conditional_lo=") && r.contains("isotropy=assumed") && r.contains("frame_binding=frame-A"));
        let rows = c.match_records();
        assert_eq!(rows.len(), 1);
        assert!(rows[0].contains("conditional test bound") && rows[0].contains("thr128") && rows[0].contains("tile-sha"));
    }
    #[test]
    fn conflict_names_accumulated_contributors_and_hostile_thresholds_stay_one_row() {
        let o = m("O", Axis::Vertical, 1333.0, 267.0, 266.5, 267.5, "thr128");
        let far = m("x", Axis::Vertical, 1119.0, 300.0, 299.5, 300.5, "thr128");
        assert_eq!(cal(vec![mh(), o, far]), Err(CalibrationError::Conflict {
            contributors: vec!["H|Vertical|thr128".into(), "O|Vertical|thr128".into()], current: "x|Vertical|thr128".into() }));
        let a = m("H", Axis::Vertical, 1333.0, 267.0, 266.5, 267.5, "t;=\t1");
        let b = m("H", Axis::Vertical, 1333.0, 267.0, 266.5, 267.5, "t2\n");
        let c = cal(vec![a, b]).unwrap();
        let rows = c.threshold_sensitivity();
        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|r| r.matches('\t').count() == 6 && r.matches('\n').count() == 1 && r.ends_with('\n')));
    }
}
