//! SCALE CONTEXT v10c (new file: engine/core/src/scale_context.rs). UNRUN SOURCE, std only. Does not touch the solver.
//! TARGET DESIGN (not a statement about current consumers): ONE verified scale variable per run, `units_per_px`
//! (output units per source pixel), bound at run start from a ReferenceCalibrated record (or an explicitly named
//! convention), immutable (private fields, no setters, no override path). Consumers (glyph fit, .notdef, space, profiles,
//! IoU, export, cache) are meant to take it from here; none is wired yet, so nothing here proves that they do.
//! Identity: the binding is the EXACT length-prefixed canonical record (no hash). FNV-1a64 is a non-cryptographic audit tag
//! only; std has no SHA-256, so a caller that needs a digest hashes the exact record outside. No scale literal here.
//! Stamping is only as strong as its callers: `stamp` marks a value the producer created under this context; it cannot
//! detect an old unwrapped geometry that someone stamps again. Scale-dependent output-unit values must be created through
//! `bind_units` (typed ScaleBoundUnits); scale-independent declared font-unit constants are a separate explicit class.
//! Scope: this module handles a single isotropic LENGTH scale only. It has no origin translation, rotation or
//! coordinate-system transform; SourceTransform is a length-scale record, not a coordinate transform.
use crate::canonical_scale_calibration::{CalibrationStatus, ReferenceCalibration};

#[derive(Clone, Debug, PartialEq)]
pub enum ContextError {
    EmptyId,
    EmptyCohort,
    EmptyFrameBinding,
    InvalidScale,
    InvalidTargetUpm,
    CalibrationNotSelected,
    ScopeMismatch,
    ForeignScaleBinding { expected: String, found: String },
    EmptyProvenance { param: String },
    InvalidValue { name: String },
    InvalidTransform,
    NumericRange,
    /// SourceLength carries a different source id/frame than the transform.
    SourceMismatch,
    /// A cache entry has no ScaleContext record (legacy, scale only as a bare value): typed incompatible, no silent unit guess.
    LegacyCacheIncompatible,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ScaleBasis {
    /// exact canonical record of the ReferenceCalibrated calibration it was bound from.
    Calibration { canonical_record: String },
    /// explicit canonical convention (candidate status is the caller's record); `convention_id` names it.
    Convention { convention_id: String },
}

#[derive(Clone, Debug, PartialEq)]
pub struct ScaleContext {
    id: String, units_per_px: f64, target_upm: f64, basis: ScaleBasis, cohort: String, frame_binding: String,
    /// exact length-prefixed canonical record; THE identity.
    record: String,
}
/// Length-prefixed field: "<byte length>:<bytes>;" so no delimiter inside a field can shift a boundary.
fn lp(s: &str) -> String { format!("{}:{};", s.len(), s) }
fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r") }
fn finite_pos(x: f64) -> bool { x.is_finite() && x > 0.0 }
fn fnv1a64(s: &str) -> u64 { let mut h: u64 = 0xcbf29ce484222325; for b in s.bytes() { h ^= u64::from(b); h = h.wrapping_mul(0x100000001b3); } h }

impl ScaleContext {
    /// Bind from a ReferenceCalibrated record; cohort and frame binding are checked against it.
    pub fn from_calibration(id: &str, cal: &ReferenceCalibration, cohort: &str, frame_binding: &str) -> Result<Self, ContextError> {
        if cal.status() != CalibrationStatus::ReferenceCalibrated { return Err(ContextError::CalibrationNotSelected); }
        let k = cal.scale_for(cohort, frame_binding).map_err(|_| ContextError::ScopeMismatch)?;
        Self::build(id, k, cal.target_upm(), ScaleBasis::Calibration { canonical_record: cal.canonical_record() }, cohort, frame_binding)
    }
    pub fn from_convention(id: &str, convention_id: &str, units_per_px: f64, target_upm: f64, cohort: &str, frame_binding: &str) -> Result<Self, ContextError> {
        if convention_id.is_empty() { return Err(ContextError::EmptyId); }
        Self::build(id, units_per_px, target_upm, ScaleBasis::Convention { convention_id: convention_id.to_string() }, cohort, frame_binding)
    }
    fn build(id: &str, k: f64, target_upm: f64, basis: ScaleBasis, cohort: &str, frame_binding: &str) -> Result<Self, ContextError> {
        if id.is_empty() { return Err(ContextError::EmptyId); }
        if cohort.is_empty() { return Err(ContextError::EmptyCohort); }
        if frame_binding.is_empty() { return Err(ContextError::EmptyFrameBinding); }
        if !finite_pos(k) { return Err(ContextError::InvalidScale); }
        if !finite_pos(target_upm) { return Err(ContextError::InvalidTargetUpm); }
        let basis_s = match &basis { ScaleBasis::Calibration { canonical_record } => format!("C{}", lp(canonical_record)), ScaleBasis::Convention { convention_id } => format!("V{}", lp(convention_id)) };
        // every variable field is length-prefixed; scale/UPM enter by exact bits
        let record = format!("scale_context_v9;{}{}{}{}{}{}", lp(id), lp(&format!("{:016x}", k.to_bits())), lp(&format!("{:016x}", target_upm.to_bits())), basis_s, lp(cohort), lp(frame_binding));
        Ok(ScaleContext { id: id.to_string(), units_per_px: k, target_upm, basis, cohort: cohort.to_string(), frame_binding: frame_binding.to_string(), record })
    }
    pub fn id(&self) -> &str { &self.id }
    pub fn units_per_px(&self) -> f64 { self.units_per_px }
    pub fn target_upm(&self) -> f64 { self.target_upm }
    pub fn basis(&self) -> &ScaleBasis { &self.basis }
    pub fn cohort(&self) -> &str { &self.cohort }
    pub fn frame_binding(&self) -> &str { &self.frame_binding }
    /// Exact canonical record = the binding identity. Equal records <=> same context.
    pub fn binding_record(&self) -> &str { &self.record }
    /// NON-cryptographic audit tag of the record; never the sole basis of any cache identity.
    pub fn audit_tag(&self) -> u64 { fnv1a64(&self.record) }
    /// Component every cache key / unit-based metric-policy identity must embed (the exact record, length-prefixed).
    pub fn cache_identity_component(&self) -> String { format!("scale_ctx[{}]", lp(&self.record)) }

    pub fn px_to_units(&self, px: f64) -> Result<f64, ContextError> {
        let v = px * self.units_per_px;
        if px.is_finite() && v.is_finite() && !(px != 0.0 && v == 0.0) { Ok(v) } else { Err(ContextError::NumericRange) }
    }
    pub fn units_to_px(&self, units: f64) -> Result<f64, ContextError> {
        let v = units / self.units_per_px;
        if units.is_finite() && v.is_finite() && !(units != 0.0 && v == 0.0) { Ok(v) } else { Err(ContextError::NumericRange) }
    }
    /// Stamp a producer-created value with this binding (see module note on limits).
    pub fn stamp<T>(&self, value: T) -> Stamped<T> { Stamped { value, record: self.record.clone() } }
    pub fn accept<'a, T>(&self, s: &'a Stamped<T>) -> Result<&'a T, ContextError> {
        if s.record == self.record { Ok(&s.value) } else { Err(ContextError::ForeignScaleBinding { expected: self.record.clone(), found: s.record.clone() }) }
    }
    /// Create a scale-dependent output-unit value bound to this context.
    pub fn bind_units(&self, name: &str, units: f64) -> Result<ScaleBoundUnits, ContextError> {
        if name.is_empty() || !units.is_finite() { return Err(ContextError::InvalidValue { name: name.to_string() }); }
        Ok(ScaleBoundUnits { name: name.to_string(), units, record: self.record.clone() })
    }
    /// Scale-dependent output-unit^2 value bound to this context (kept apart from lengths).
    pub fn bind_area(&self, name: &str, units2: f64) -> Result<ScaleBoundArea, ContextError> {
        if name.is_empty() || !units2.is_finite() { return Err(ContextError::InvalidValue { name: name.to_string() }); }
        Ok(ScaleBoundArea { name: name.to_string(), units2, record: self.record.clone() })
    }
    pub fn area_of(&self, b: &ScaleBoundArea) -> Result<f64, ContextError> {
        if b.record == self.record { Ok(b.units2) } else { Err(ContextError::ForeignScaleBinding { expected: self.record.clone(), found: b.record.clone() }) }
    }
    /// Cache identity check: `stored` = the ScaleContext record stored with the entry. None (legacy entry) is typed
    /// incompatible; a different record is ForeignScaleBinding. This adds to, and never replaces, any existing bare-scale check.
    pub fn check_cache_record(&self, stored: Option<&str>) -> Result<(), ContextError> {
        match stored {
            None => Err(ContextError::LegacyCacheIncompatible),
            Some(r) if r == self.record => Ok(()),
            Some(r) => Err(ContextError::ForeignScaleBinding { expected: self.record.clone(), found: r.to_string() }),
        }
    }
    /// Read a scale-bound value: only under the SAME binding; a value computed under another K is refused.
    pub fn units_of(&self, b: &ScaleBoundUnits) -> Result<f64, ContextError> {
        if b.record == self.record { Ok(b.units) } else { Err(ContextError::ForeignScaleBinding { expected: self.record.clone(), found: b.record.clone() }) }
    }
    /// Convert a declared-dimension parameter into output units. The result is TYPED: a dimensionless value is never
    /// returned with a units label.
    pub fn param_to_units(&self, p: &DimParam) -> Result<Converted, ContextError> {
        match p.dim {
            Dimension::SquaredPixels => Ok(Converted::SquaredOutputUnits(self.sq_factor(p.value, true)?)),
            Dimension::DeclaredSquaredOutputUnits => Ok(Converted::SquaredOutputUnits(p.value)),
            Dimension::Pixels => Ok(Converted::OutputUnits(self.px_to_units(p.value)?)),
            Dimension::DeclaredOutputUnits => Ok(Converted::OutputUnits(p.value)),
            Dimension::Dimensionless => Ok(Converted::Plain(p.value)),
        }
    }
    pub fn param_to_px(&self, p: &DimParam) -> Result<Converted, ContextError> {
        match p.dim {
            Dimension::SquaredPixels => Ok(Converted::SquaredPixels(p.value)),
            Dimension::DeclaredSquaredOutputUnits => Ok(Converted::SquaredPixels(self.sq_factor(p.value, false)?)),
            Dimension::Pixels => Ok(Converted::Pixels(p.value)),
            Dimension::DeclaredOutputUnits => Ok(Converted::Pixels(self.units_to_px(p.value)?)),
            Dimension::Dimensionless => Ok(Converted::Plain(p.value)),
        }
    }
    /// px^2 -> units^2 (multiply by K^2) or units^2 -> px^2 (divide by K^2); non-finite intermediates are refused.
    fn sq_factor(&self, v: f64, to_units: bool) -> Result<f64, ContextError> {
        let k2 = self.units_per_px * self.units_per_px;
        let r = if to_units { v * k2 } else { v / k2 };
        // underflow of a non-zero input to 0 is a typed refusal (precision loss), not a silent success
        if k2.is_finite() && k2 > 0.0 && v.is_finite() && r.is_finite() && !(v != 0.0 && r == 0.0) { Ok(r) } else { Err(ContextError::NumericRange) }
    }
    pub fn receipt_row(&self) -> String {
        format!("scale_context\t{}\tunits_per_px={:?}\ttarget_upm={:?}\tbasis={}\tcohort={}\tframe_binding={}\taudit_tag_noncrypto={:016x}\trecord={}\n",
            esc(&self.id), self.units_per_px, self.target_upm,
            match &self.basis { ScaleBasis::Calibration { .. } => "calibration".to_string(), ScaleBasis::Convention { convention_id } => format!("convention:{}", esc(convention_id)) },
            esc(&self.cohort), esc(&self.frame_binding), self.audit_tag(), esc(&self.record))
    }
}
/// Describes a binding change between two contexts for a receipt; no values are rewritten.
pub fn binding_change_row(old: &ScaleContext, new: &ScaleContext) -> String {
    format!("scale_binding_change\t{}\told_record={}\tnew_record={}\tsame={}\n", esc(new.id()), esc(old.binding_record()), esc(new.binding_record()), old.binding_record() == new.binding_record())
}

#[derive(Clone, Debug, PartialEq)]
pub struct Stamped<T> { value: T, record: String }
impl<T> Stamped<T> { pub fn record(&self) -> &str { &self.record } }

/// Scale-DEPENDENT output-unit value (e.g. a length computed with a K): readable only under the same binding.
#[derive(Clone, Debug, PartialEq)]
pub struct ScaleBoundUnits { name: String, units: f64, record: String }

/// Scale-dependent output-unit^2 value (area / squared error computed with a K): readable only under the same binding.
#[derive(Clone, Debug, PartialEq)]
pub struct ScaleBoundArea { name: String, units2: f64, record: String }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dimension {
    Pixels,
    /// Scale-INDEPENDENT constant declared directly in output (font) units. Anything computed with a K is NOT this: it
    /// must be a ScaleBoundUnits.
    DeclaredOutputUnits,
    Dimensionless,
    /// px^2 (e.g. a squared fit error measured in pixels); converts with K^2. A squared quantity must NEVER be declared as
    /// Pixels (that would convert with K, not K^2).
    SquaredPixels,
    /// scale-independent declared constant in output-unit^2.
    DeclaredSquaredOutputUnits,
}
/// NOTE for callers: a stored `Converted::OutputUnits` (length) is scale-dependent; store it via `bind_units`; a stored
/// `Converted::SquaredOutputUnits` (area) via `bind_area`
/// (or re-derive from the DimParam under the right context) or it loses its binding.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Converted { Pixels(f64), OutputUnits(f64), SquaredPixels(f64), SquaredOutputUnits(f64), Plain(f64) }

/// A tolerance/threshold/metric parameter with explicit dimension and provenance.
#[derive(Clone, Debug, PartialEq)]
pub struct DimParam { name: String, value: f64, dim: Dimension, provenance: String }
impl DimParam {
    pub fn new(name: &str, value: f64, dim: Dimension, provenance: &str) -> Result<Self, ContextError> {
        if name.is_empty() || !value.is_finite() { return Err(ContextError::InvalidValue { name: name.to_string() }); }
        if provenance.is_empty() { return Err(ContextError::EmptyProvenance { param: name.to_string() }); }
        Ok(DimParam { name: name.to_string(), value, dim, provenance: provenance.to_string() })
    }
    pub fn name(&self) -> &str { &self.name }
    pub fn dimension(&self) -> Dimension { self.dim }
    pub fn value(&self) -> f64 { self.value }
    pub fn provenance(&self) -> &str { &self.provenance }
}

/// Explicit LENGTH-SCALE record from a source with another native pixel density into a specific run context.
/// Not a coordinate transform: no origin translation, rotation or per-axis scale; coordinates are unsupported.
/// Bound to the source id/frame AND the target context binding: applying it under another context is refused.
#[derive(Clone, Debug, PartialEq)]
pub struct SourceTransform { source_id: String, source_frame: String, run_px_per_source_px: f64, provenance: String, target_record: String }
impl SourceTransform {
    pub fn new(source_id: &str, source_frame: &str, run_px_per_source_px: f64, provenance: &str, target: &ScaleContext) -> Result<Self, ContextError> {
        if source_id.is_empty() || source_frame.is_empty() || provenance.is_empty() || !finite_pos(run_px_per_source_px) { return Err(ContextError::InvalidTransform); }
        Ok(SourceTransform { source_id: source_id.to_string(), source_frame: source_frame.to_string(), run_px_per_source_px, provenance: provenance.to_string(), target_record: target.record.clone() })
    }
    /// Length (not coordinate) in source px -> length in run px, only under the bound target context.
    pub fn length_to_run_px(&self, target: &ScaleContext, source_len_px: f64) -> Result<f64, ContextError> {
        if target.record != self.target_record { return Err(ContextError::ForeignScaleBinding { expected: self.target_record.clone(), found: target.record.clone() }); }
        let v = source_len_px * self.run_px_per_source_px;
        if source_len_px.is_finite() && v.is_finite() && !(source_len_px != 0.0 && v == 0.0) { Ok(v) } else { Err(ContextError::NumericRange) }
    }
    /// Runtime-checked variant: the length carries its own source id/frame; a mismatch is refused (the scalar API above
    /// relies on the caller to have verified the source).
    pub fn source_length_to_run_px(&self, target: &ScaleContext, l: &SourceLength) -> Result<f64, ContextError> {
        if l.source_id != self.source_id || l.source_frame != self.source_frame { return Err(ContextError::SourceMismatch); }
        self.length_to_run_px(target, l.px)
    }
    pub fn source_id(&self) -> &str { &self.source_id }
    pub fn source_frame(&self) -> &str { &self.source_frame }
    pub fn provenance(&self) -> &str { &self.provenance }
}

/// A native-source pixel length stamped with its source id and frame.
#[derive(Clone, Debug, PartialEq)]
pub struct SourceLength { source_id: String, source_frame: String, px: f64 }
impl SourceLength {
    pub fn new(source_id: &str, source_frame: &str, px: f64) -> Result<Self, ContextError> {
        if source_id.is_empty() || source_frame.is_empty() || !px.is_finite() { return Err(ContextError::InvalidTransform); }
        Ok(SourceLength { source_id: source_id.to_string(), source_frame: source_frame.to_string(), px })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::canonical_scale_calibration::{calibrate, Axis, ReferenceMatch};
    // fixture values are TEST INPUTS (stand-ins for owner CSV / font numbers), not engine constants
    fn cal(px: f64) -> ReferenceCalibration {
        let m = ReferenceMatch::new("H", Axis::Vertical, 1333.0, px, 1.0, px - 0.5, px + 0.5, "conditional test bound", "tile-sha", "thr128", "frame-A").unwrap();
        calibrate("font-sha", 2048.0, 1000.0, "owner", "cohort-1", vec![m]).unwrap()
    }
    fn ctx(px: f64) -> ScaleContext { ScaleContext::from_calibration("run-ctx", &cal(px), "cohort-1", "frame-A").unwrap() }
    fn conv(k: f64) -> ScaleContext { ScaleContext::from_convention("r", "c", k, 1000.0, "cohort", "frame").unwrap() }

    #[test]
    fn binds_exactly_the_calibrated_value_with_calibration_basis() {
        let c = ctx(267.0);
        assert_eq!(c.units_per_px(), cal(267.0).primary_estimate());
        assert_eq!(c.target_upm(), 1000.0);
        assert!(matches!(c.basis(), ScaleBasis::Calibration { .. }));
        assert_eq!(c.cohort(), "cohort-1");
        assert_eq!(c.frame_binding(), "frame-A");
        assert!(c.receipt_row().contains("basis=calibration") && c.receipt_row().ends_with('\n'));
    }
    #[test]
    fn different_scale_is_a_different_binding_and_cache_identity() {
        let a = ctx(267.0); let b = ctx(268.0);
        assert_ne!(a.binding_record(), b.binding_record());
        assert_ne!(a.cache_identity_component(), b.cache_identity_component());
        assert_eq!(a.binding_record(), ctx(267.0).binding_record());
        assert!(binding_change_row(&a, &b).contains("same=false"));
        assert!(binding_change_row(&a, &ctx(267.0)).contains("same=true"));
    }
    #[test]
    fn pipe_and_delimiter_boundaries_cannot_collide() {
        let a = ScaleContext::from_convention("r", "c", 2.0, 1000.0, "a|b", "c").unwrap();
        let b = ScaleContext::from_convention("r", "c", 2.0, 1000.0, "a", "b|c").unwrap();
        assert_ne!(a.binding_record(), b.binding_record());
        assert_ne!(a.cache_identity_component(), b.cache_identity_component());
        // convention id vs cohort boundary, and ';' ':' digits inside fields
        let c1 = ScaleContext::from_convention("r", "c1:3;x", 2.0, 1000.0, "s", "f").unwrap();
        let c2 = ScaleContext::from_convention("r", "c1", 2.0, 1000.0, "3;xs", "f").unwrap();
        assert_ne!(c1.binding_record(), c2.binding_record());
        let i1 = ScaleContext::from_convention("a;1:b", "c", 2.0, 1000.0, "s", "f").unwrap();
        let i2 = ScaleContext::from_convention("a", "1:b;c", 2.0, 1000.0, "s", "f").unwrap();
        assert_ne!(i1.binding_record(), i2.binding_record());
    }
    #[test]
    fn old_geometry_is_refused_under_a_new_scale() {
        let a = ctx(267.0); let b = ctx(268.0);
        let g = a.stamp(vec![1.0_f64, 2.0]);
        assert_eq!(a.accept(&g), Ok(&vec![1.0, 2.0]));
        assert_eq!(b.accept(&g), Err(ContextError::ForeignScaleBinding { expected: b.binding_record().to_string(), found: a.binding_record().to_string() }));
    }
    #[test]
    fn scope_and_status_gates() {
        assert_eq!(ScaleContext::from_calibration("r", &cal(267.0), "cohort-2", "frame-A"), Err(ContextError::ScopeMismatch));
        assert_eq!(ScaleContext::from_calibration("r", &cal(267.0), "cohort-1", "frame-B"), Err(ContextError::ScopeMismatch));
        let m1 = ReferenceMatch::new("a", Axis::Vertical, 100.0, 10.0, 2.0, 9.0, 11.0, "b", "t1", "thr", "frame-A").unwrap();
        let m2 = ReferenceMatch::new("b", Axis::Vertical, 11.0, 1.0, 0.0, 1.0, 1.0, "b", "t2", "thr", "frame-A").unwrap();
        let bad = calibrate("f", 1.0, 1.0, "o", "cohort-1", vec![m1, m2]).unwrap();
        assert_eq!(ScaleContext::from_calibration("r", &bad, "cohort-1", "frame-A"), Err(ContextError::CalibrationNotSelected));
        assert_eq!(ScaleContext::from_calibration("", &cal(267.0), "cohort-1", "frame-A"), Err(ContextError::EmptyId));
    }
    #[test]
    fn convention_basis_and_input_validation() {
        let c = conv(2.0);
        assert_eq!(c.basis(), &ScaleBasis::Convention { convention_id: "c".into() });
        for k in [0.0, -1.0, f64::NAN, f64::INFINITY] {
            assert_eq!(ScaleContext::from_convention("r", "c", k, 1000.0, "s", "f"), Err(ContextError::InvalidScale));
        }
        assert_eq!(ScaleContext::from_convention("r", "c", 2.0, 0.0, "s", "f"), Err(ContextError::InvalidTargetUpm));
        assert_eq!(ScaleContext::from_convention("r", "c", 2.0, 1000.0, "", "f"), Err(ContextError::EmptyCohort));
        assert_eq!(ScaleContext::from_convention("r", "c", 2.0, 1000.0, "s", ""), Err(ContextError::EmptyFrameBinding));
        assert_eq!(ScaleContext::from_convention("r", "", 2.0, 1000.0, "s", "f"), Err(ContextError::EmptyId));
    }
    #[test]
    fn conversions_round_trip_and_overflow_is_typed() {
        let c = conv(2.5);
        assert_eq!(c.px_to_units(4.0), Ok(10.0));
        assert_eq!(c.units_to_px(10.0), Ok(4.0));
        let big = conv(f64::MAX);
        assert_eq!(big.px_to_units(2.0), Err(ContextError::NumericRange));
        assert_eq!(c.px_to_units(f64::NAN), Err(ContextError::NumericRange));
    }
    #[test]
    fn parameters_convert_only_by_declared_dimension_with_typed_results() {
        let c = conv(2.0);
        let px = DimParam::new("tol_px", 3.0, Dimension::Pixels, "measured in tile px").unwrap();
        let un = DimParam::new("tol_units", 3.0, Dimension::DeclaredOutputUnits, "declared scale-independent font-unit constant").unwrap();
        let dl = DimParam::new("ratio", 0.25, Dimension::Dimensionless, "ratio").unwrap();
        assert_eq!(c.param_to_units(&px), Ok(Converted::OutputUnits(6.0)));
        assert_eq!(c.param_to_units(&un), Ok(Converted::OutputUnits(3.0))); // not multiplied as pixels
        assert_eq!(c.param_to_px(&un), Ok(Converted::Pixels(1.5)));
        assert_eq!(c.param_to_px(&px), Ok(Converted::Pixels(3.0)));
        assert_eq!(c.param_to_units(&dl), Ok(Converted::Plain(0.25))); // never labelled as units
        assert_eq!(c.param_to_px(&dl), Ok(Converted::Plain(0.25)));
        assert_eq!(DimParam::new("x", 1.0, Dimension::Pixels, ""), Err(ContextError::EmptyProvenance { param: "x".into() }));
        assert_eq!(DimParam::new("x", f64::NAN, Dimension::Pixels, "p"), Err(ContextError::InvalidValue { name: "x".into() }));
        assert_eq!(DimParam::new("", 1.0, Dimension::Pixels, "p"), Err(ContextError::InvalidValue { name: "".into() }));
    }
    #[test]
    fn scale_dependent_units_are_bound_to_their_context() {
        let a = ctx(267.0); let b = ctx(268.0);
        let v = a.bind_units("tol", a.px_to_units(3.0).unwrap()).unwrap();
        assert_eq!(a.units_of(&v), Ok(a.px_to_units(3.0).unwrap()));
        assert_eq!(b.units_of(&v), Err(ContextError::ForeignScaleBinding { expected: b.binding_record().to_string(), found: a.binding_record().to_string() }));
        assert_eq!(a.bind_units("", 1.0), Err(ContextError::InvalidValue { name: "".into() }));
        assert_eq!(a.bind_units("t", f64::NAN), Err(ContextError::InvalidValue { name: "t".into() }));
    }
    #[test]
    fn source_transform_is_bound_to_source_frame_and_target_context() {
        let a = conv(2.0); let b = conv(3.0);
        let t = SourceTransform::new("styleB", "frameB", 0.5, "native density half of run frame", &a).unwrap();
        assert_eq!(t.length_to_run_px(&a, 8.0), Ok(4.0));
        assert_eq!(t.length_to_run_px(&b, 8.0), Err(ContextError::ForeignScaleBinding { expected: a.binding_record().to_string(), found: b.binding_record().to_string() }));
        assert_eq!(SourceTransform::new("", "f", 0.5, "p", &a), Err(ContextError::InvalidTransform));
        assert_eq!(SourceTransform::new("s", "", 0.5, "p", &a), Err(ContextError::InvalidTransform));
        assert_eq!(SourceTransform::new("s", "f", 0.0, "p", &a), Err(ContextError::InvalidTransform));
        assert_eq!(SourceTransform::new("s", "f", 1.0, "", &a), Err(ContextError::InvalidTransform));
        let huge = SourceTransform::new("s", "f", f64::MAX, "p", &a).unwrap();
        assert_eq!(huge.length_to_run_px(&a, 2.0), Err(ContextError::NumericRange));
    }
    #[test]
    fn receipt_row_escapes_and_is_single_line() {
        let c = ScaleContext::from_convention("r\td", "c\n1", 2.0, 1000.0, "s\t", "f\r").unwrap();
        let r = c.receipt_row();
        assert_eq!(r.matches('\n').count(), 1);
        assert!(r.contains("scale_context\tr\\td\t") && r.contains("convention:c\\n1") && r.contains("audit_tag_noncrypto="));
    }
    #[test]
    fn squared_dimensions_convert_with_k_squared_not_k() {
        let c = conv(2.0);
        let p2 = DimParam::new("fit_se_px2", 3.0, Dimension::SquaredPixels, "measured variance px^2").unwrap();
        let u2 = DimParam::new("fit_se_u2", 12.0, Dimension::DeclaredSquaredOutputUnits, "declared constant").unwrap();
        assert_eq!(c.param_to_units(&p2), Ok(Converted::SquaredOutputUnits(12.0))); // 3 * 2^2, not 3 * 2
        assert_eq!(c.param_to_units(&u2), Ok(Converted::SquaredOutputUnits(12.0)));
        assert_eq!(c.param_to_px(&u2), Ok(Converted::SquaredPixels(3.0)));
        assert_eq!(c.param_to_px(&p2), Ok(Converted::SquaredPixels(3.0)));
        let big = conv(f64::MAX);
        assert_eq!(big.param_to_units(&p2), Err(ContextError::NumericRange)); // K^2 overflows
        let tiny = conv(f64::MIN_POSITIVE);
        assert_eq!(tiny.param_to_px(&u2), Err(ContextError::NumericRange)); // K^2 underflows to 0
    }
    #[test]
    fn source_length_is_checked_against_transform_source_and_frame() {
        let a = conv(2.0);
        let t = SourceTransform::new("styleB", "frameB", 0.5, "p", &a).unwrap();
        let ok = SourceLength::new("styleB", "frameB", 8.0).unwrap();
        assert_eq!(t.source_length_to_run_px(&a, &ok), Ok(4.0));
        assert_eq!(t.source_length_to_run_px(&a, &SourceLength::new("styleC", "frameB", 8.0).unwrap()), Err(ContextError::SourceMismatch));
        assert_eq!(t.source_length_to_run_px(&a, &SourceLength::new("styleB", "frameC", 8.0).unwrap()), Err(ContextError::SourceMismatch));
        assert_eq!(SourceLength::new("", "f", 1.0), Err(ContextError::InvalidTransform));
        assert_eq!(SourceLength::new("s", "f", f64::NAN), Err(ContextError::InvalidTransform));
    }
    #[test]
    fn scale_bound_area_is_separate_from_length_and_bound() {
        let a = ctx(267.0); let b = ctx(268.0);
        let v = a.bind_area("fit_se", 12.0).unwrap();
        assert_eq!(a.area_of(&v), Ok(12.0));
        assert_eq!(b.area_of(&v), Err(ContextError::ForeignScaleBinding { expected: b.binding_record().to_string(), found: a.binding_record().to_string() }));
        assert_eq!(a.bind_area("", 1.0), Err(ContextError::InvalidValue { name: "".into() }));
        assert_eq!(a.bind_area("x", f64::INFINITY), Err(ContextError::InvalidValue { name: "x".into() }));
    }
    #[test]
    fn cache_record_check_types_legacy_and_foreign_entries() {
        let a = ctx(267.0); let b = ctx(268.0);
        assert_eq!(a.check_cache_record(Some(a.binding_record())), Ok(()));
        assert_eq!(a.check_cache_record(None), Err(ContextError::LegacyCacheIncompatible));
        assert_eq!(a.check_cache_record(Some(b.binding_record())), Err(ContextError::ForeignScaleBinding { expected: a.binding_record().to_string(), found: b.binding_record().to_string() }));
    }
    #[test]
    fn underflow_of_nonzero_input_to_zero_is_refused_zero_stays_zero() {
        let c = conv(1e-150);
        let p2 = DimParam::new("tiny_px2", 1e-200, Dimension::SquaredPixels, "p").unwrap();
        assert_eq!(c.param_to_units(&p2), Err(ContextError::NumericRange)); // 1e-200 * 1e-300 underflows to 0
        let z = DimParam::new("zero_px2", 0.0, Dimension::SquaredPixels, "p").unwrap();
        assert_eq!(c.param_to_units(&z), Ok(Converted::SquaredOutputUnits(0.0)));
        assert_eq!(c.px_to_units(1e-200), Err(ContextError::NumericRange));
        assert_eq!(c.px_to_units(0.0), Ok(0.0));
        let big = conv(1e150);
        assert_eq!(big.units_to_px(1e-200), Err(ContextError::NumericRange));
    }
    #[test]
    fn source_transform_length_underflow_is_refused() {
        let a = conv(2.0);
        let t = SourceTransform::new("s", "f", 1e-200, "p", &a).unwrap();
        assert_eq!(t.length_to_run_px(&a, 1e-200), Err(ContextError::NumericRange));
        assert_eq!(t.length_to_run_px(&a, 0.0), Ok(0.0));
    }
}
