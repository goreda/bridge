//! Calibrated apply lane for the existing gen predictor, not a new optical model.
//! Concrete pair rows are primary. Source zeros remain distinct from absence.
//! Font-local empirical policies are proposals, not universal optical laws.

use crate::export_gpos::PairTarget;
use crate::gen::{self, GenerationInputs};
use std::collections::{BTreeMap, BTreeSet};

/// Binding of data and evaluation to one immutable font/model revision.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Binding {
    pub font_revision: String,
    pub model_revision: String,
    pub context: String,
}

/// Resolved concrete pair, after source lookup/class/exception resolution.
/// The caller must not create a zero row merely because a pair is absent.
#[derive(Debug, Clone)]
pub struct SourcePair {
    pub left: u16,
    pub right: u16,
    pub kern: i32,
    pub evidence: String,
}

/// A held-out evaluation, not a training residual or repeated training pair.
/// Error and uncertainty are font units, never pixels silently reused as units.
#[derive(Debug, Clone)]
pub struct Holdout {
    pub left: u16,
    pub right: u16,
    pub absolute_error: f64,
    pub measurement_uncertainty: f64,
    pub evidence: String,
}

/// Per-pair independent acceptance, bound to the exact post-rounding value.
/// Geometry evidence must cover ALL positioned contours, including marks.
/// Raster clear, body-wall clear, and name-based inheritance are insufficient.
/// Any intended overlap needs a source-grounded exception in that evidence.
#[derive(Debug, Clone)]
pub struct Verification {
    pub binding: Binding,
    pub left: u16,
    pub right: u16,
    pub kern: i32,
    pub measured_residual: f64,
    pub calibrated_uncertainty: f64,
    pub uncertainty_evidence: String,
    pub optical_evidence: String,
    pub full_geometry_evidence: String,
}

/// A font-local policy. Private fields prevent uncalibrated policy literals.
#[derive(Debug, Clone)]
pub struct Calibration {
    binding: Binding,
    noise: f64,
    lower: i32,
    upper: i32,
    anchor_evidence: Vec<String>,
    holdout_evidence: Vec<String>,
}

impl Calibration {
    /// CONVENTION: empirical signed source envelope; do not extrapolate/clamp.
    /// CONVENTION: worst held-out error or measurement uncertainty is the
    /// noise floor. This deterministic conservative rule is not a calibrated
    /// probability or a claim about unseen-cell/family generalization.
    pub fn fit(binding: Binding, anchors: &[SourcePair], holdouts: &[Holdout]) -> Result<Self, String> {
        validate_binding(&binding)?;
        if anchors.is_empty() || holdouts.is_empty() {
            return Err("UNVERIFIABLE: source anchors and held-out evaluation required".into());
        }
        let mut keys = BTreeSet::new();
        for p in anchors {
            nonempty(&p.evidence, "anchor evidence")?;
            if !keys.insert((p.left, p.right)) {
                return Err("duplicate resolved source pair".into());
            }
        }
        let mut held = BTreeSet::new();
        let mut noise = 0.0_f64;
        for h in holdouts {
            nonempty(&h.evidence, "holdout evidence")?;
            if keys.contains(&(h.left, h.right)) {
                return Err("holdout leakage: evaluated pair is a training anchor".into());
            }
            if !held.insert((h.left, h.right)) {
                return Err("duplicate held-out pair".into());
            }
            for value in [h.absolute_error, h.measurement_uncertainty] {
                if !value.is_finite() || value < 0.0 {
                    return Err("non-finite or negative holdout error/uncertainty".into());
                }
                noise = noise.max(value);
            }
        }
        let lower = anchors.iter().map(|p| p.kern).min().unwrap();
        let upper = anchors.iter().map(|p| p.kern).max().unwrap();
        let mut anchor_evidence: Vec<_> = anchors.iter().map(|p| p.evidence.clone()).collect();
        let mut holdout_evidence: Vec<_> = holdouts.iter().map(|p| p.evidence.clone()).collect();
        anchor_evidence.sort();
        holdout_evidence.sort();
        Ok(Self { binding, noise, lower, upper, anchor_evidence, holdout_evidence })
    }
    pub fn noise_floor(&self) -> f64 { self.noise }
    pub fn signed_envelope(&self) -> (i32, i32) { (self.lower, self.upper) }
    pub fn anchor_evidence(&self) -> &[String] { &self.anchor_evidence }
    pub fn holdout_evidence(&self) -> &[String] { &self.holdout_evidence }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// Exact concrete source value, including explicit zero, not yet accepted.
    SourceUnverified,
    /// Model suggestion only. No independent optical/full-outline acceptance.
    Unverifiable,
    Verified,
    RejectedNoise,
    RejectedExtrapolation,
    MissingPrediction,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PairRow {
    pub left: u16,
    pub right: u16,
    /// None means unpredicted, not an implicit zero.
    pub kern: Option<i32>,
    pub state: State,
    pub provenance: String,
    /// Source vs existing model lane, not an independent measurement verdict.
    pub tier: String,
    pub mechanism: String,
    /// Signed independently measured error, absent if no pair observation.
    pub residual: Option<f64>,
    /// Font-local empirical error floor, NOT pair-calibrated confidence.
    pub uncertainty: Option<f64>,
    pub uncertainty_method: String,
    pub refusal_reason: Option<String>,
    pub abstain: bool,
    pub constant_sources: String,
    pub optical_evidence: Option<String>,
    pub full_geometry_evidence: Option<String>,
}

/// Immutable rows plus the policy and revision binding needed to replay them.
#[derive(Debug, Clone)]
pub struct ConcreteTable {
    rows: Vec<PairRow>,
    pub binding: Binding,
    pub calibration: Calibration,
}

impl ConcreteTable {
    pub fn rows(&self) -> &[PairRow] { &self.rows }
    /// Apply the external caller's verified-wall boundary even to populated
    /// cells. No glyph-name or raster-wall heuristic can supply this evidence.
    pub fn require_verified_walls(&mut self, verified: &BTreeSet<u16>) {
        for r in &mut self.rows {
            if !verified.contains(&r.left) || !verified.contains(&r.right) {
                r.state = if r.tier == "direct-source" { State::SourceUnverified } else { State::Unverifiable };
                r.abstain = true;
                r.refusal_reason = Some("glyph lacks verified walls".into());
                r.optical_evidence = None;
                r.full_geometry_evidence = None;
            }
        }
    }
    /// Adapter only, no compression, GPOS bytes, font insertion, or write.
    /// All returned rows are locked to preserve source/zero/exception values.
    /// CONVENTION: reject values outside OpenType int16, never saturate them.
    pub fn verified_targets(&self) -> Result<Vec<PairTarget>, String> {
        self.rows.iter().filter(|r| r.state == State::Verified).map(|r| {
            let kern = r.kern.ok_or("verified row missing value")?;
            i16::try_from(kern).map_err(|_| "verified kern outside OpenType int16")?;
            Ok(PairTarget { left: r.left, right: r.right, kern, locked: true })
        }).collect()
    }
    /// Canonical TSV: sorted glyph IDs; no fabricated zero for unknown rows.
    pub fn to_tsv(&self) -> String {
        let mut out = String::from("left_gid\tright_gid\tkern_u\tstate\ttier\tmechanism\tresidual_u\tuncertainty_u\tuncertainty_method\tabstain\trefusal_reason\tconstant_sources\tprovenance\toptical_evidence\tfull_geometry_evidence\n");
        for row in &self.rows {
            let value = row.kern.map(|k| k.to_string()).unwrap_or_default();
            let residual = row.residual.map(|v| v.to_string()).unwrap_or_default();
            let uncertainty = row.uncertainty.map(|v| v.to_string()).unwrap_or_default();
            out.push_str(&format!("{}\t{}\t{}\t{:?}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                row.left, row.right, value, row.state, row.tier, row.mechanism, residual,
                uncertainty, row.uncertainty_method, row.abstain, row.refusal_reason.as_deref().unwrap_or(""),
                row.constant_sources, row.provenance, row.optical_evidence.as_deref().unwrap_or(""),
                row.full_geometry_evidence.as_deref().unwrap_or("")));
        }
        out
    }
}

fn nonempty(s: &str, label: &str) -> Result<(), String> {
    if s.trim().is_empty() || s.chars().any(|c| matches!(c, '\t' | '\n' | '\r')) {
        return Err(format!("empty or TSV-unsafe {label}"));
    }
    Ok(())
}
fn validate_binding(b: &Binding) -> Result<(), String> {
    nonempty(&b.font_revision, "font revision")?;
    nonempty(&b.model_revision, "model revision")?;
    nonempty(&b.context, "shaping context")
}

/// Apply the existing predictor to every concrete combination. No quotas,
/// glyph-name tiers, per-font numeric overrides, or silent restorations.
/// Source values bypass generation thresholds and are always preserved.
/// Calibration and verification must match this exact binding. Receipt
/// references are supplied by upstream measurement/validation, not minted here.
/// The model may still use edge-only features; optical acceptance is separate.
pub fn generate(
    binding: &Binding,
    inp: &GenerationInputs,
    glyph_ids: &BTreeMap<String, u16>,
    source: &[SourcePair],
    calibration: &Calibration,
    verifications: &[Verification],
) -> Result<ConcreteTable, String> {
    validate_binding(binding)?;
    if binding != &calibration.binding { return Err("calibration revision/context mismatch".into()); }
    if !inp.restore.is_empty() { return Err("restorations require explicit concrete source resolution upstream".into()); }
    let mut names = BTreeSet::new();
    let mut ids = BTreeMap::new();
    for name in &inp.glyphs {
        if !names.insert(name.as_str()) { return Err("duplicate glyph name".into()); }
        let id = *glyph_ids.get(name).ok_or("missing concrete glyph ID")?;
        if ids.insert(id, name).is_some() { return Err("duplicate concrete glyph ID".into()); }
    }
    let mut resolved = BTreeMap::new();
    for p in source {
        nonempty(&p.evidence, "source evidence")?;
        if !ids.contains_key(&p.left) || !ids.contains_key(&p.right) {
            return Err("source pair references unknown glyph ID".into());
        }
        if resolved.insert((p.left, p.right), p).is_some() { return Err("duplicate resolved source pair".into()); }
    }
    // A predictor-side protected table must agree with the concrete input.
    // It cannot hide an existing pair or disagree on explicit zero.
    for ((l, r), v) in &inp.existing {
        let li = glyph_ids.get(l).ok_or("existing left glyph has no ID")?;
        let ri = glyph_ids.get(r).ok_or("existing right glyph has no ID")?;
        match resolved.get(&(*li, *ri)) {
            Some(p) if p.kern == *v => {},
            _ => return Err("existing table conflicts with resolved concrete source".into()),
        }
    }
    // Prevent the old predictor's float-to-int conversion from saturating or
    // turning NaN into a plausible kern. No new rounding law is introduced.
    for v in inp.targets.cell_median.values().chain(inp.targets.stratum_mingap.values())
        .chain(std::iter::once(&inp.targets.global_mingap)) {
        if !v.is_finite() || *v < f64::from(i32::MIN) || *v > f64::from(i32::MAX) {
            return Err("non-finite or unrepresentable target".into());
        }
    }
    for wall in inp.walls.values() {
        if !wall.advance.is_finite() || wall.advance < 0.0 || wall.rows.values()
            .any(|(l, r)| !l.is_finite() || !r.is_finite() || l > r) {
            return Err("invalid wall geometry or advance".into());
        }
    }
    let mut accepted = BTreeMap::new();
    for v in verifications {
        if &v.binding != binding { return Err("verification revision/context mismatch".into()); }
        nonempty(&v.uncertainty_evidence, "pair uncertainty evidence")?;
        if !v.measured_residual.is_finite() || !v.calibrated_uncertainty.is_finite() || v.calibrated_uncertainty < 0.0 {
            return Err("invalid pair residual/uncertainty".into());
        }
        nonempty(&v.optical_evidence, "independent optical evidence")?;
        nonempty(&v.full_geometry_evidence, "complete positioned outline evidence")?;
        if !ids.contains_key(&v.left) || !ids.contains_key(&v.right) {
            return Err("verification references unknown glyph ID".into());
        }
        if accepted.insert((v.left, v.right), v).is_some() { return Err("duplicate verification".into()); }
    }
    let mut rows = Vec::new();
    for (&left, l) in &ids {
        for (&right, r) in &ids {
            let pair = (left, right);
            let (kern, mut state, provenance) = if let Some(p) = resolved.get(&pair) {
                (Some(p.kern), State::SourceUnverified, format!("source:{}", p.evidence))
            } else {
                // For the geometric lane, check the unrounded expression as
                // well, because target minus gap may overflow despite each
                // input being representable. Cell output uses existing logic.
                let raw = raw_prediction(inp, l, r)?;
                match raw {
                    None => (None, State::MissingPrediction, "missing-model-or-geometry".into()),
                    Some((k, tag)) => {
                        let state = if k < calibration.lower || k > calibration.upper { State::RejectedExtrapolation }
                            else if f64::from(k).abs() < calibration.noise { State::RejectedNoise }
                            else { State::Unverifiable };
                        (Some(k), state, format!("model:{tag}"))
                    }
                }
            };
            let is_source = resolved.contains_key(&pair);
            let tier = if is_source { "direct-source" } else { "model-derived" }.to_string();
            let mechanism = provenance.clone();
            let mut residual = None;
            let mut uncertainty = if is_source { None } else { Some(calibration.noise) };
            let mut uncertainty_method = if is_source { "unknown-source-uncertainty" } else { "font-global-heldout-envelope-not-pair-confidence" }.to_string();
            let mut optical_evidence = None;
            let mut full_geometry_evidence = None;
            if let Some(v) = accepted.get(&pair) {
                if kern != Some(v.kern) { return Err("verification does not bind exact output kern".into()); }
                if matches!(state, State::SourceUnverified | State::Unverifiable) {
                    state = State::Verified;
                    residual = Some(v.measured_residual);
                    uncertainty = Some(v.calibrated_uncertainty);
                    uncertainty_method = format!("pair-independent:{}", v.uncertainty_evidence);
                    optical_evidence = Some(v.optical_evidence.clone());
                    full_geometry_evidence = Some(v.full_geometry_evidence.clone());
                }
            }
            let refusal_reason = match state {
                State::Verified => None,
                State::SourceUnverified => Some("independent optical/full-outline acceptance absent".into()),
                State::Unverifiable => Some("model prediction lacks independent optical/full-outline acceptance".into()),
                State::RejectedNoise => Some("below font-local empirical noise".into()),
                State::RejectedExtrapolation => Some("outside font-local signed source envelope".into()),
                State::MissingPrediction => Some("missing model coverage or shared geometry".into()),
            };
            rows.push(PairRow { left, right, kern, state, provenance, tier, mechanism, residual,
                uncertainty, uncertainty_method, refusal_reason, abstain: state != State::Verified,
                constant_sources: format!("MIN_ABS_KERN=derived:max-heldout-error-or-uncertainty:{};CLAMP_LO=derived:min-source-anchor:{};CLAMP_HI=derived:max-source-anchor:{};GENERATION_TARGET=CONVENTION:no-quota;ROUNDING=CONVENTION:ties-to-even;INT16=CONVENTION:OpenType-format",
                    calibration.noise, calibration.lower, calibration.upper),
                optical_evidence, full_geometry_evidence });
        }
    }
    Ok(ConcreteTable { rows, binding: binding.clone(), calibration: calibration.clone() })
}

fn raw_prediction(inp: &GenerationInputs, l: &str, r: &str) -> Result<Option<(i32, &'static str)>, String> {
    let (kl, kr) = match (inp.knowledge.get(l), inp.knowledge.get(r)) {
        (Some(a), Some(b)) => (a, b), _ => return Ok(None),
    };
    let cell = (kl.right_class, kr.left_class, kl.case, kr.case);
    if !inp.targets.cell_median.contains_key(&cell) {
        let (wl, wr) = match (inp.walls.get(l), inp.walls.get(r)) {
            (Some(a), Some(b)) => (a, b), _ => return Ok(None),
        };
        let gap = match gen::min_gap0(wl, wr) { Some(g) => g, None => return Ok(None) };
        let target = inp.targets.stratum_mingap.get(&(kl.case, kr.case)).copied().unwrap_or(inp.targets.global_mingap);
        let raw = target - gap;
        if !raw.is_finite() || raw < f64::from(i32::MIN) || raw > f64::from(i32::MAX) {
            return Err("non-finite or unrepresentable geometric prediction".into());
        }
    }
    // No priors are used: prior integration is not validated.
    Ok(gen::predict_with(inp, l, r, None))
}
