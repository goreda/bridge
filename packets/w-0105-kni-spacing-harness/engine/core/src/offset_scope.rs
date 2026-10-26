//! Neutral offset/scope types (new file: engine/core/src/offset_scope.rs). std + scale_context only. Types only: this module
//! applies nothing. The post-step that moves real glyph rings (the export path) uses these types; there is no second
//! computation here. Offsets are user-declared, `Dimension::DeclaredOutputUnits`, finite and integral. Two types:
//! `SideBearingOffset` is the strict nonnegative contract (>= 0, unchanged); `SignedSideBearingOffset` allows negative
//! values (owner directive 2026-10-17: negative offsets are legitimate - a negative LSB offset translates the ink left,
//! a negative RSB offset shrinks the advance; the nonnegative-only refusal was an engine limitation). Scope is explicit:
//! no Default impl, every class is stated by the caller.
use crate::scale_context::{DimParam, Dimension};

#[derive(Clone, Debug, PartialEq)]
pub enum OffsetError { WrongDimension { name: String }, InvalidOffset { name: String }, /// lsb + rsb (the facing-gap delta) overflows to a non-finite value although both operands are finite.
    NonFiniteSum }

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SideBearingOffset { lsb: f64, rsb: f64 }
impl SideBearingOffset {
    pub fn none() -> Self { SideBearingOffset { lsb: 0.0, rsb: 0.0 } }
    pub fn from_params(lsb: &DimParam, rsb: &DimParam) -> Result<Self, OffsetError> {
        let o = SideBearingOffset { lsb: Self::units(lsb)?, rsb: Self::units(rsb)? };
        if !(o.lsb + o.rsb).is_finite() { return Err(OffsetError::NonFiniteSum); }
        Ok(o)
    }
    fn units(p: &DimParam) -> Result<f64, OffsetError> {
        if p.dimension() != Dimension::DeclaredOutputUnits { return Err(OffsetError::WrongDimension { name: p.name().to_string() }); }
        let v = p.value();
        if !(v.is_finite() && v >= 0.0 && v.fract() == 0.0) { return Err(OffsetError::InvalidOffset { name: p.name().to_string() }); }
        Ok(v)
    }
    pub fn lsb(&self) -> f64 { self.lsb }
    pub fn rsb(&self) -> f64 { self.rsb }
    pub fn is_noop(&self) -> bool { self.lsb == 0.0 && self.rsb == 0.0 }
    /// Change of the facing gap of any kern pair: left glyph RSB_add + right glyph LSB_add.
    pub fn facing_gap_delta(&self) -> f64 { self.rsb + self.lsb }
}

/// SIGNED sidebearing offset: same domain and dimension rules as `SideBearingOffset`
/// (`Dimension::DeclaredOutputUnits`, finite, integral) but ANY sign. Semantics at the post-step:
/// L < 0 translates the ink left (geometry translate), R < 0 shrinks the advance (advance
/// adjustment); the ink shape (translation aside) is byte/geometry identical. The strict
/// nonnegative type above is unchanged; callers that need the old proof domain keep it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SignedSideBearingOffset { lsb: f64, rsb: f64 }
impl SignedSideBearingOffset {
    pub fn none() -> Self { SignedSideBearingOffset { lsb: 0.0, rsb: 0.0 } }
    pub fn from_params(lsb: &DimParam, rsb: &DimParam) -> Result<Self, OffsetError> {
        let o = SignedSideBearingOffset { lsb: Self::units(lsb)?, rsb: Self::units(rsb)? };
        if !(o.lsb + o.rsb).is_finite() { return Err(OffsetError::NonFiniteSum); }
        Ok(o)
    }
    fn units(p: &DimParam) -> Result<f64, OffsetError> {
        if p.dimension() != Dimension::DeclaredOutputUnits { return Err(OffsetError::WrongDimension { name: p.name().to_string() }); }
        let v = p.value();
        if !(v.is_finite() && v.fract() == 0.0) { return Err(OffsetError::InvalidOffset { name: p.name().to_string() }); }
        Ok(v)
    }
    pub fn lsb(&self) -> f64 { self.lsb }
    pub fn rsb(&self) -> f64 { self.rsb }
    pub fn is_noop(&self) -> bool { self.lsb == 0.0 && self.rsb == 0.0 }
    /// Change of the facing gap of any kern pair: left glyph RSB_add + right glyph LSB_add (signed).
    pub fn facing_gap_delta(&self) -> f64 { self.rsb + self.lsb }
    /// True when both components are >= 0: the gap-monotonicity proof domain. A pass with a
    /// negative component MEASURES the signed gap deltas instead of proving monotonicity.
    pub fn is_nonnegative(&self) -> bool { self.lsb >= 0.0 && self.rsb >= 0.0 }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GlyphClass { Base, Space, Notdef, Mark }

/// Class flags plus the typed `KerningLetters` selection (manifest token `kerning_letters`): Base ∩ Unicode L* ∩ glyphs that take part in a
/// nonzero emitted GPOS pair-kern. `kerning_letters` is a REFINEMENT of Base but it is a separate flag: it does not set `base`, so
/// `includes(Base)` stays false for it (fail-closed: a consumer that does not implement the letters/kern filter shifts nothing).
/// The filter itself lives in the post-step (post_metrics); this type only carries the selection.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct ScopePolicy { pub base: bool, pub space: bool, pub notdef: bool, pub mark: bool, pub kerning_letters: bool }
impl std::fmt::Debug for ScopePolicy {
    /// Identical to the former derived Debug while `kerning_letters` is false (receipts of existing scopes do not change).
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut d = f.debug_struct("ScopePolicy");
        d.field("base", &self.base).field("space", &self.space).field("notdef", &self.notdef).field("mark", &self.mark);
        if self.kerning_letters { d.field("kerning_letters", &true); }
        d.finish()
    }
}
impl ScopePolicy {
    pub fn includes(&self, c: GlyphClass) -> bool { match c { GlyphClass::Base => self.base, GlyphClass::Space => self.space, GlyphClass::Notdef => self.notdef, GlyphClass::Mark => self.mark } }
    /// True when the Base-class glyphs must additionally pass the KerningLetters filter.
    pub fn selects_kerning_letters(&self) -> bool { self.kerning_letters }
    pub fn is_empty(&self) -> bool { !(self.base || self.space || self.notdef || self.mark || self.kerning_letters) }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn p(n: &str, v: f64) -> DimParam { DimParam::new(n, v, Dimension::DeclaredOutputUnits, "t").unwrap() }
    #[test]
    fn offsets_must_be_declared_nonnegative_integral() {
        let px = DimParam::new("lsb", 20.0, Dimension::Pixels, "px").unwrap();
        assert_eq!(SideBearingOffset::from_params(&px, &p("rsb", 0.0)), Err(OffsetError::WrongDimension { name: "lsb".into() }));
        assert_eq!(SideBearingOffset::from_params(&p("lsb", -1.0), &p("rsb", 0.0)), Err(OffsetError::InvalidOffset { name: "lsb".into() }));
        assert_eq!(SideBearingOffset::from_params(&p("lsb", 0.0), &p("rsb", 2.5)), Err(OffsetError::InvalidOffset { name: "rsb".into() }));
        // finite operands, non-finite derived value: refused at construction
        assert_eq!(SideBearingOffset::from_params(&p("lsb", 1e308), &p("rsb", 1e308)), Err(OffsetError::NonFiniteSum));
        assert!(SideBearingOffset::from_params(&p("lsb", 1e308), &p("rsb", 0.0)).is_ok());
        assert!(SideBearingOffset::none().is_noop());
        let o = SideBearingOffset::from_params(&p("lsb", 25.0), &p("rsb", 25.0)).unwrap();
        assert_eq!((o.lsb(), o.rsb(), o.facing_gap_delta()), (25.0, 25.0, 50.0));
    }
    #[test]
    fn signed_offsets_accept_negative_and_refuse_fraction_nonfinite() {
        let o = SignedSideBearingOffset::from_params(&p("lsb", -1.0), &p("rsb", -25.0)).unwrap();
        assert_eq!((o.lsb(), o.rsb(), o.facing_gap_delta()), (-1.0, -25.0, -26.0));
        assert!(!o.is_nonnegative());
        let m = SignedSideBearingOffset::from_params(&p("lsb", -1.0), &p("rsb", 25.0)).unwrap();
        assert!(!m.is_nonnegative());
        let pos = SignedSideBearingOffset::from_params(&p("lsb", 25.0), &p("rsb", 0.0)).unwrap();
        assert!(pos.is_nonnegative());
        assert!(SignedSideBearingOffset::none().is_noop() && SignedSideBearingOffset::none().is_nonnegative());
        // fraction / non-finite refused, any sign
        assert_eq!(SignedSideBearingOffset::from_params(&p("lsb", -0.5), &p("rsb", 0.0)), Err(OffsetError::InvalidOffset { name: "lsb".into() }));
        // NaN/infinity never reach this constructor: DimParam::new refuses non-finite values one
        // layer up (scale_context tests cover that); the is_finite check in units() stays as the
        // defensive second wall.
        assert_eq!(SignedSideBearingOffset::from_params(&p("lsb", -1e308), &p("rsb", -1e308)), Err(OffsetError::NonFiniteSum));
        assert_eq!(SignedSideBearingOffset::from_params(&p("lsb", 1e308), &p("rsb", 1e308)), Err(OffsetError::NonFiniteSum));
        // (pixels are a nonnegative domain: DimParam itself refuses a negative pixel value, so the
        // wrong-dimension probe uses a positive one)
        let px = DimParam::new("lsb", 1.0, Dimension::Pixels, "px").unwrap();
        assert_eq!(SignedSideBearingOffset::from_params(&px, &p("rsb", 0.0)), Err(OffsetError::WrongDimension { name: "lsb".into() }));
        // the strict nonnegative type still refuses negatives (old contract intact)
        assert_eq!(SideBearingOffset::from_params(&p("lsb", -1.0), &p("rsb", 0.0)), Err(OffsetError::InvalidOffset { name: "lsb".into() }));
    }
    #[test]
    fn scope_is_explicit_per_class() {
        let s = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false };
        assert!(s.includes(GlyphClass::Base) && !s.includes(GlyphClass::Mark) && !s.is_empty());
        assert!(ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false }.is_empty());
    }
    #[test]
    fn kerning_letters_is_separate_nonempty_and_fail_closed() {
        let k = ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: true };
        assert!(!k.is_empty() && k.selects_kerning_letters() && !k.includes(GlyphClass::Base));
        let b = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false };
        assert!(!b.selects_kerning_letters());
        assert_eq!(format!("{:?}", b), "ScopePolicy { base: true, space: false, notdef: false, mark: false }");
        assert!(format!("{:?}", k).contains("kerning_letters: true"));
    }
}
