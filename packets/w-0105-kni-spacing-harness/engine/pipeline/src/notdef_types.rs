//! Shared evidence types and codepoint grammar used by producer and validator.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BadNotdef {
    Grammar,
    Duplicate,
    MissingEvidence,
    Ambiguous,
    MissingPixelEvidence,
    AmbiguousPixelCandidate,
    InvalidSourceImage,
    // Typed refusal for a blank cell without a space-advance binding; no construction site yet (lint: variant never constructed).
    BlankCellMissingSpaceAdvance,
    ShaMismatch,
    Io,
    ContextMismatch,
    // Typed refusal for an audit mismatch; reserved for the audit route, no construction site yet.
    AuditMismatch,
    // Typed refusal for a tile mismatch; reserved for the validation route, no construction site yet.
    TileMismatch,
    // Typed refusal for an invalid tile; reserved for the validation route, no construction site yet.
    InvalidTile,
    ReservedCodepoint,
    InvalidCodepoint,
    ResourceLimit,
    // Typed refusal for a missing run identity; reserved for the run-identity check, no construction site yet.
    MissingRunIdentity,
    // Typed refusal constructed only by UnavailableDecoder, itself never constructed; per the BoundedDecoder doc the pending shared-core bounded decoder is the production route.
    DecoderUnavailable,
}
impl std::fmt::Display for BadNotdef {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "bad_notdef::{self:?}")
    }
}
impl std::error::Error for BadNotdef {}

/// Pixel role only, never a claim about an unavailable original font's cmap.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PixelNotdefKind { RepeatedForm, BlankCell }
impl PixelNotdefKind {
    pub fn token(self) -> &'static str {
        match self { Self::RepeatedForm => "repeated-form", Self::BlankCell => "blank-cell" }
    }
    pub fn parse(token: &str) -> Result<Self, BadNotdef> {
        match token {
            "repeated-form" => Ok(Self::RepeatedForm),
            "blank-cell" => Ok(Self::BlankCell),
            _ => Err(BadNotdef::Grammar),
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct PixelContext {
    pub style: String,
    pub frame: String,
    pub units_per_px: f64,
    pub source_sha256: String,
    pub ink_model: String,
}
/// Shared by run validation and exact unit regressions, including space's route.
pub fn validate_codepoint(cp: u32) -> Result<(), BadNotdef> {
    if cp == 0 {
        Err(BadNotdef::ReservedCodepoint)
    } else if char::from_u32(cp).is_none() {
        Err(BadNotdef::InvalidCodepoint)
    } else {
        Ok(())
    }
}
