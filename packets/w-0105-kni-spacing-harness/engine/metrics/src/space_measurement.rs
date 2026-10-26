//! kni-space-measurement/v2.3
//!
//! Measures the advance width of the space glyph from a source tile triplet.
//!
//! Rule (owner + chief): `space_advance = G(HsH) - rsb(H) - lsb(H)`.
//! `G(HsH)` is the clear horizontal gap between the right ink edge of the
//! first H and the left ink edge of the second H in the HsH tile.
//!
//! Where rsb(H) + lsb(H) comes from (typed, no default):
//! - `HhhTile`: the gap of two adjacent Hs equals `rsb + lsb + k` where `k` is
//!   the HH pair kern. Equal gaps in HHH do NOT show k = 0 (a repeated pair
//!   kern k shifts every gap by the same amount). So an HHH tile is accepted
//!   only together with explicit kern evidence in the same frame: kern known
//!   to be zero (capture feature off, or verified source font pair kern 0), or
//!   a known source HH kern which is subtracted. Without it:
//!   `SpaceError::UnverifiedHHSpacing`.
//! - `Explicit`: lsb/rsb in source px, bound to style + frame + reference.
//! HHH symmetry alone is never sufficient.
//!
//! The HsH gap is contextual: G = rsb(H) + space.advance + lsb(H)
//! + kern(H,space) + kern(space,H) + letter-spacing contributions. Without
//! evidence that those extra terms are zero or known, `G - SB` is a contextual
//! space gap, not a nominal advance. v2.1 therefore requires:
//! - `HsHKernEvidence` (ZeroVerified | KnownSumPx | Unverified); a known sum
//!   (negative allowed) is subtracted;
//! - `CaptureShapingEvidence`: a record of the capture text-shaping settings
//!   (ligatures off, letter-spacing 0, pair kerning state) with a ref, bound to
//!   the style + frame and to the sha of every tile it covers. Same style and
//!   frame alone are not enough.
//!
//! No invented number and no fallback number. Scale is never assumed: it must
//! carry a `ScaleStatus` bound to the same style. `PinnedConsistent` means a
//! pinned scale record agrees with the manifest scale and a source tile; it is
//! NOT an independent calibration and this module makes no calibration claim.
//! Legacy constants (Marq / Alternate 1.710) are `Unverified` and are refused.
//!
//! Sidebearing domain is explicit (`SidebearingPolicy`): negative sidebearings
//! are legitimate in type design, so there is no silent ban; the caller picks.
//! Default is `AllowNegativeFinite` (finite values only, finite results).
//!
//! Pixel edge quantisation (1 px per edge) is a NOMINAL REPORT BOUND written
//! to the ledger. It is a resolution statement, not evidence that two readings
//! are the same value and not an acceptance gate.
//!
//! Status: source-only, 2026-10-16. Unit tests are UNRUN.
//! Wiring: `pub mod space_measurement;` in `engine/metrics/src/lib.rs`.

use crate::plane::{GrayImage, INK_THRESHOLD};
use kni_learning::sha256::sha256_hex;

pub const MODULE_ID: &str = "kni-space-measurement/v2.3";

/// Nominal per-edge resolution bound, px. Reported, never used as a gate.
pub const NOMINAL_EDGE_BOUND_PX: i64 = 1;

/// Style + frame identity. Both fields must be non-empty.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceFrame {
    pub style_id: String,
    pub frame_id: String,
}

/// A source tile with its identity.
#[derive(Debug, Clone)]
pub struct SourceTile {
    /// sha256 (hex) of the original tile file bytes, supplied by the caller.
    pub source_sha256: String,
    /// Frame the tile was captured in. `None` is MissingFrameEvidence.
    pub frame: Option<SourceFrame>,
    /// Reference showing the tile content is the glyph sequence named (H s H
    /// or H H H) with fixed capture framing (e.g. capture manifest row).
    /// Cluster width similarity is not accepted as identity evidence.
    pub glyph_identity_ref: String,
    pub image: GrayImage,
}

/// Status of the scale binding.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScaleStatus {
    /// No pinned record backs the scale (e.g. a legacy constant).
    Unverified,
    /// A pinned scale record (sha256) was checked consistent with the manifest
    /// scale, the style/frame and a loaded source tile. Not independent
    /// calibration evidence.
    PinnedConsistent(ScaleConsistencyProof),
}

/// Typed refusal from [`ScaleConsistencyProof::check`].
#[derive(Debug, Clone, PartialEq)]
pub enum ScaleProofError {
    ShaPinMismatch { declared: String, actual: String },
    FrameMismatch { record: String, request: String },
    UnitsMismatch { record_bits: u64, manifest_bits: u64 },
    SourceNotLoadedTile,
}

/// Proof that a scale record passed every consistency check. The only way to
/// build one is `check`; the field is private, so a caller cannot assert
/// `PinnedConsistent` without running the checks. Not independent calibration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScaleConsistencyProof {
    record_sha256: String,
}

impl ScaleConsistencyProof {
    #[allow(clippy::too_many_arguments)]
    pub fn check(
        declared_sha256: &str,
        actual_sha256: &str,
        record_frame: &SourceFrame,
        request_frame: &SourceFrame,
        record_units_per_px: f64,
        manifest_units_per_px: f64,
        calibration_source_sha256: &str,
        loaded_tile_sha256: &[String],
    ) -> Result<Self, ScaleProofError> {
        if declared_sha256 != actual_sha256 {
            return Err(ScaleProofError::ShaPinMismatch { declared: declared_sha256.into(), actual: actual_sha256.into() });
        }
        if record_frame.style_id != request_frame.style_id || record_frame.frame_id != request_frame.frame_id {
            return Err(ScaleProofError::FrameMismatch {
                record: format!("{}/{}", record_frame.style_id, record_frame.frame_id),
                request: format!("{}/{}", request_frame.style_id, request_frame.frame_id),
            });
        }
        if record_units_per_px.to_bits() != manifest_units_per_px.to_bits() {
            return Err(ScaleProofError::UnitsMismatch {
                record_bits: record_units_per_px.to_bits(),
                manifest_bits: manifest_units_per_px.to_bits(),
            });
        }
        if !loaded_tile_sha256.iter().any(|t| t == calibration_source_sha256) {
            return Err(ScaleProofError::SourceNotLoadedTile);
        }
        Ok(Self { record_sha256: actual_sha256.to_string() })
    }

    pub fn record_sha256(&self) -> &str {
        &self.record_sha256
    }
}

/// Scale evidence: font units per source px, bound to one style.
#[derive(Debug, Clone)]
pub struct ScaleEvidence {
    pub style_id: String,
    pub units_per_px: f64,
    pub evidence_ref: String,
    /// Binding status. Only `PinnedConsistent` is accepted; it is a
    /// consistency claim about pinned records, not a validated calibration.
    pub status: ScaleStatus,
}

/// HH pair kern evidence for an HHH tile, in the same frame.
#[derive(Debug, Clone)]
pub enum HhKernEvidence {
    /// Kern known to be zero: capture feature off, or verified source font
    /// pair kern 0.
    ZeroVerified { frame: Option<SourceFrame>, evidence_ref: String },
    /// Known source HH kern in px (may be nonzero); subtracted from the HH gap.
    KnownPx { frame: Option<SourceFrame>, kern_px: f64, evidence_ref: String },
    /// No kern evidence. Always refused.
    Unverified,
}

/// Source of rsb(H) + lsb(H).
#[derive(Debug, Clone)]
pub enum HhSpacingEvidence {
    HhhTile { tile: SourceTile, kern: HhKernEvidence },
    Explicit { frame: Option<SourceFrame>, lsb_px: f64, rsb_px: f64, evidence_ref: String },
}

/// Explicit domain choice for sidebearing values.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SidebearingPolicy {
    /// Finite values, negative allowed (default; legitimate in type design).
    AllowNegativeFinite,
    /// Finite and non-negative only.
    RequireNonNegative,
}

impl Default for SidebearingPolicy {
    fn default() -> Self {
        SidebearingPolicy::AllowNegativeFinite
    }
}

/// Kern around the space in the HsH tile: kern(H,space) + kern(space,H), px.
#[derive(Debug, Clone)]
pub enum HsHKernEvidence {
    /// Both pair kerns known to be zero (capture feature off, or verified
    /// source font pairs).
    ZeroVerified { frame: Option<SourceFrame>, evidence_ref: String },
    /// Known sum of both kerns in px (negative allowed); subtracted.
    KnownSumPx { frame: Option<SourceFrame>, sum_px: f64, evidence_ref: String },
    /// No evidence. Always refused.
    Unverified,
}

/// Record of the capture's text-shaping settings.
#[derive(Debug, Clone)]
pub struct CaptureShapingEvidence {
    pub frame: Option<SourceFrame>,
    /// Reference to the capture settings record (manifest row, settings file).
    pub settings_ref: String,
    /// Ligature substitution disabled in the capture.
    pub ligatures_disabled: bool,
    /// Letter-spacing applied by the capture, px. Must be 0.0; a nonzero
    /// value is refused as a contextual gap (not modelled here).
    pub letter_spacing_px: f64,
    /// sha256 of every tile this record covers (HsH tile and HHH tile).
    pub covers_tile_sha256: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct SpaceRequest {
    pub frame: SourceFrame,
    pub hsh_tile: Option<SourceTile>,
    pub hh_spacing: Option<HhSpacingEvidence>,
    pub hsh_kern: Option<HsHKernEvidence>,
    pub capture_shaping: Option<CaptureShapingEvidence>,
    pub scale: Option<ScaleEvidence>,
    pub sidebearing_policy: SidebearingPolicy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MissingKind {
    HshTile,
    HhSpacing,
    HsHKern,
    CaptureShaping,
    Scale,
    InkModel,
    Limits,
}

impl MissingKind {
    fn label(self) -> &'static str {
        match self {
            MissingKind::HshTile => "hsh_tile",
            MissingKind::HhSpacing => "hh_spacing",
            MissingKind::HsHKern => "hsh_kern",
            MissingKind::InkModel => "ink_model",
            MissingKind::Limits => "slope_limits",
            MissingKind::CaptureShaping => "capture_shaping",
            MissingKind::Scale => "scale",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum SpaceError {
    MissingSpaceEvidence { style_id: String, missing: MissingKind },
    /// A frame is absent where one is required. `what` names the item.
    MissingFrameEvidence { what: String },
    /// A required identity or reference string is empty.
    EmptyField { field: String },
    FrameMismatch { what: String, expected: SourceFrame, found: SourceFrame },
    /// Scale evidence is bound to another style.
    ScaleStyleMismatch { expected: String, found: String },
    ScaleNotPinnedConsistent { style_id: String, evidence_ref: String },
    InvalidScale { style_id: String },
    /// HHH tile without usable kern evidence, or kern value not finite.
    UnverifiedHHSpacing { reason: String },
    /// HsH gap is contextual: no kern evidence around the space, ligatures not
    /// disabled, letter-spacing nonzero, or shaping record does not cover a tile.
    UnverifiedHsHContext { reason: String },
    /// Width*height overflow, zero size, or px length disagrees.
    BadImage { source_sha256: String },
    EmptyTile { source_sha256: String },
    UnexpectedClusterCount { source_sha256: String, expected: usize, found: usize },
    /// Explicit sidebearing value not finite, or violates the chosen policy.
    InvalidSidebearing { reason: String },
    /// Sum or product is not finite.
    NonFiniteResult { what: String },
    /// Computed space advance is negative. Reported, never clamped.
    NegativeSpace { gap_px: f64, sidebearing_sum_px: f64 },
    /// Slope route: two tiles with different space counts have identical bytes.
    AliasedSlopeTiles { source_sha256: String, spaces_a: usize, spaces_b: usize },
    /// Slope route: two tiles claim the same space count.
    DuplicateSpaceCount { spaces: usize },
    /// Slope route: space count zero or fewer tiles than a residual needs.
    TooFewSlopePoints { found: usize, needed: usize },
    /// Slope route: tiles differ in pixel dimensions (capture frame drift).
    SlopeGeometryDrift { source_sha256: String, expected_wh: (u32, u32), found_wh: (u32, u32) },
    /// Slope route: the result is not exportable (status in `reason`).
    SlopeNotExportable { reason: String },
    ArithmeticOverflow { what: String },
    SpacesNotStrictlyIncreasing { spaces_a: usize, spaces_b: usize },
    SlopeNotPositive { slope_px: f64 },
    BackgroundAmbiguous { source_sha256: String, median: u8 },
    ResourceLimit { what: String, limit: u128, found: u128 },
    
}

impl std::fmt::Display for SpaceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SpaceError::MissingSpaceEvidence { style_id, missing } => {
                write!(f, "missing space evidence for style {style_id}: {}", missing.label())
            }
            SpaceError::MissingFrameEvidence { what } => write!(f, "missing frame evidence: {what}"),
            SpaceError::EmptyField { field } => write!(f, "empty required field: {field}"),
            SpaceError::FrameMismatch { what, expected, found } => write!(
                f,
                "frame mismatch ({what}): expected {}/{}, found {}/{}",
                expected.style_id, expected.frame_id, found.style_id, found.frame_id
            ),
            SpaceError::ScaleStyleMismatch { expected, found } => {
                write!(f, "scale evidence is for style {found}, request is for {expected}")
            }
            SpaceError::ScaleNotPinnedConsistent { style_id, evidence_ref } => {
                write!(f, "scale for style {style_id} has no pinned-consistent record (ref {evidence_ref})")
            }
            SpaceError::InvalidScale { style_id } => {
                write!(f, "scale for style {style_id} is not a positive finite number")
            }
            SpaceError::UnverifiedHHSpacing { reason } => write!(f, "unverified HH spacing: {reason}"),
            SpaceError::UnverifiedHsHContext { reason } => write!(f, "unverified HsH context: {reason}"),
            SpaceError::BadImage { source_sha256 } => write!(f, "tile {source_sha256}: bad image dimensions"),
            SpaceError::EmptyTile { source_sha256 } => write!(f, "tile {source_sha256} has no ink"),
            SpaceError::UnexpectedClusterCount { source_sha256, expected, found } => {
                write!(f, "tile {source_sha256}: expected {expected} ink clusters, found {found}")
            }
            SpaceError::InvalidSidebearing { reason } => write!(f, "invalid sidebearing: {reason}"),
            SpaceError::NonFiniteResult { what } => write!(f, "non-finite result: {what}"),
            SpaceError::NegativeSpace { gap_px, sidebearing_sum_px } => write!(
                f,
                "negative space: HsH gap {gap_px} px < sidebearing sum {sidebearing_sum_px} px"
            ),
            SpaceError::AliasedSlopeTiles { source_sha256, spaces_a, spaces_b } => write!(
                f,
                "slope tiles with {spaces_a} and {spaces_b} spaces have identical bytes ({source_sha256}); slope is unmeasurable"
            ),
            SpaceError::DuplicateSpaceCount { spaces } => write!(f, "two slope tiles claim {spaces} spaces"),
            SpaceError::TooFewSlopePoints { found, needed } => {
                write!(f, "slope route needs {needed} tiles with distinct space counts >= 1, found {found}")
            }
            SpaceError::SlopeGeometryDrift { source_sha256, expected_wh, found_wh } => write!(
                f,
                "slope tile {source_sha256} is {}x{} px, expected {}x{} (capture frame drift)",
                found_wh.0, found_wh.1, expected_wh.0, expected_wh.1
            ),
            SpaceError::SlopeNotExportable { reason } => write!(f, "slope result not exportable: {reason}"),
            SpaceError::BackgroundAmbiguous { source_sha256, median } => write!(f, "tile {source_sha256}: a corner differs from the border median {median} by more than the ink delta; background ambiguous"),
            SpaceError::ArithmeticOverflow { what } => write!(f, "arithmetic overflow in {what}"),
            SpaceError::ResourceLimit { what, limit, found } => write!(f, "resource limit: {what} {found} exceeds {limit}"),
            SpaceError::SpacesNotStrictlyIncreasing { spaces_a, spaces_b } => write!(f, "space counts must strictly increase ({spaces_a} then {spaces_b})"),
            SpaceError::SlopeNotPositive { slope_px } => write!(f, "slope {slope_px} px per space is not positive"),
        }
    }
}

impl std::error::Error for SpaceError {}

/// Outcome the spacing solver consumes. There is no fallback variant: when the
/// measurement is missing, the space is not emitted and nothing substitutes
/// for it (the solver must not publish its own W_target as a space advance).
#[derive(Debug, Clone, PartialEq)]
pub enum SpaceOutcome {
    Measured(SpaceMeasurement),
    /// Slope route, exportable only (ConsistentWithinBound).
    SlopeMeasured(SpaceSlopeMeasurement),
    MissingEvidence(SpaceError),
}

impl SpaceOutcome {
    pub fn from_request(req: &SpaceRequest) -> Self {
        match measure_space_advance(req) {
            Ok(m) => SpaceOutcome::Measured(m),
            Err(e) => SpaceOutcome::MissingEvidence(e),
        }
    }

    /// Slope route: exportable result becomes `SlopeMeasured`; anything else is typed
    /// missing evidence (the descriptive numbers stay with the caller's measurement).
    pub fn from_slope_result(r: Result<SpaceSlopeMeasurement, SpaceError>) -> Self {
        match r {
            Ok(m) => match m.exportable_advance_units() {
                Ok(_) => SpaceOutcome::SlopeMeasured(m),
                Err(e) => SpaceOutcome::MissingEvidence(e),
            },
            Err(e) => SpaceOutcome::MissingEvidence(e),
        }
    }

    /// Advance in font units to emit for the space glyph, or the typed error
    /// for the full output contract (`SpaceMissingEvidence`).
    pub fn emitted_advance_units(&self) -> Result<f64, &SpaceError> {
        match self {
            SpaceOutcome::Measured(m) => Ok(m.space_advance_units),
            SpaceOutcome::SlopeMeasured(m) => Ok(m.space_advance_units),
            SpaceOutcome::MissingEvidence(e) => Err(e),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SpaceMeasurement {
    pub module: &'static str,
    pub style_id: String,
    pub frame_id: String,
    /// Space advance in source px (field name fixed by the lane contract).
    pub space_advance_px_slope: f64,
    /// Same value in font units with a pinned-consistent per-style scale.
    pub space_advance_units: f64,
    pub hsh_gap_px: f64,
    /// rsb(H) + lsb(H), after any known HH kern was subtracted.
    pub rsb_plus_lsb_px: f64,
    /// HH kern used, px (0 when ZeroVerified or explicit sidebearings).
    pub hh_kern_px: f64,
    /// kern(H,space)+kern(space,H) subtracted, px.
    pub hsh_kern_sum_px: f64,
    pub capture_shaping_ref: String,
    pub capture_letter_spacing_px: f64,
    pub capture_ligatures_disabled: bool,
    /// HHH gaps (empty for explicit sidebearings).
    pub hhh_gaps_px: Vec<i64>,
    /// Spread of the HHH gaps. Reported only.
    pub hhh_gap_spread_px: i64,
    pub units_per_px: f64,
    pub ink_threshold: u8,
    pub nominal_edge_bound_px: i64,
    pub hsh_tile_sha256: String,
    pub hsh_pixels_sha256: String,
    pub hhh_tile_sha256: String,
    pub hhh_pixels_sha256: String,
    pub hsh_glyph_identity_ref: String,
    pub hhh_glyph_identity_ref: String,
    pub hsh_cluster_widths_px: Vec<i64>,
    pub hh_spacing_source: String,
    pub scale_ref: String,
    /// `pinned_consistent:<record sha>` (not an independent calibration).
    pub scale_status: String,
}

fn nonempty(field: &str, v: &str) -> Result<(), SpaceError> {
    if v.trim().is_empty() {
        Err(SpaceError::EmptyField { field: field.to_string() })
    } else {
        Ok(())
    }
}

fn validate_frame(what: &str, f: &SourceFrame) -> Result<(), SpaceError> {
    nonempty(&format!("{what}.style_id"), &f.style_id)?;
    nonempty(&format!("{what}.frame_id"), &f.frame_id)
}

fn require_frame(what: &str, expected: &SourceFrame, found: &Option<SourceFrame>) -> Result<(), SpaceError> {
    let f = found
        .as_ref()
        .ok_or_else(|| SpaceError::MissingFrameEvidence { what: what.to_string() })?;
    validate_frame(what, f)?;
    if f != expected {
        return Err(SpaceError::FrameMismatch {
            what: what.to_string(),
            expected: expected.clone(),
            found: f.clone(),
        });
    }
    Ok(())
}

/// Dimensions are checked with checked multiplication before any indexing.
fn validate_image(tile: &SourceTile) -> Result<(), SpaceError> {
    let img = &tile.image;
    let bad = || SpaceError::BadImage { source_sha256: tile.source_sha256.clone() };
    if img.width == 0 || img.height == 0 {
        return Err(bad());
    }
    let n = (img.width as u64).checked_mul(img.height as u64).ok_or_else(bad)?;
    if n != img.px.len() as u64 {
        return Err(bad());
    }
    Ok(())
}

fn validate_tile(what: &str, tile: &SourceTile, expected_frame: &SourceFrame) -> Result<(), SpaceError> {
    nonempty(&format!("{what}.source_sha256"), &tile.source_sha256)?;
    nonempty(&format!("{what}.glyph_identity_ref"), &tile.glyph_identity_ref)?;
    require_frame(&format!("{what}.frame"), expected_frame, &tile.frame)?;
    validate_image(tile)
}

/// Maximal runs of consecutive ink columns as inclusive (first, last).
fn ink_column_runs(img: &GrayImage) -> Vec<(i64, i64)> {
    ink_column_runs_by(img, &|v| v < INK_THRESHOLD)
}

/// Background = median of the border frame (first/last row and column). The four
/// corners must each be within `delta` of it, otherwise the background is ambiguous
/// (differs from the old producer, which trusted the top-left pixel alone).
fn border_background(img: &GrayImage, delta: u8, sha: &str) -> Result<u8, SpaceError> {
    let (w, h) = (img.width as usize, img.height as usize);
    if w == 0 || h == 0 || img.px.len() != w.saturating_mul(h) {
        return Err(SpaceError::EmptyTile { source_sha256: sha.to_string() });
    }
    let mut frame: Vec<u8> = Vec::with_capacity(w.saturating_add(h).saturating_mul(1 + 1));
    frame.extend_from_slice(&img.px[..w]);
    frame.extend_from_slice(&img.px[(h - 1) * w..]);
    for y in 0..h {
        frame.push(img.px[y * w]);
        frame.push(img.px[y * w + w - 1]);
    }
    frame.sort_unstable();
    let bg = frame[frame.len() / (1 + 1)];
    let corners = [img.px[0], img.px[w - 1], img.px[(h - 1) * w], img.px[h * w - 1]];
    if corners.iter().any(|c| c.abs_diff(bg) > delta) {
        return Err(SpaceError::BackgroundAmbiguous { source_sha256: sha.to_string(), median: bg });
    }
    Ok(bg)
}

fn ink_column_runs_by(img: &GrayImage, is_ink: &dyn Fn(u8) -> bool) -> Vec<(i64, i64)> {
    let w = img.width as usize;
    let h = img.height as usize;
    let mut runs = Vec::new();
    let mut start: Option<i64> = None;
    for x in 0..w {
        let mut has_ink = false;
        for y in 0..h {
            if is_ink(img.px[y * w + x]) {
                has_ink = true;
                break;
            }
        }
        match (has_ink, start) {
            (true, None) => start = Some(x as i64),
            (false, Some(s)) => {
                runs.push((s, x as i64 - 1));
                start = None;
            }
            _ => {}
        }
    }
    if let Some(s) = start {
        runs.push((s, w as i64 - 1));
    }
    runs
}

fn runs_expect(tile: &SourceTile, expected: usize) -> Result<Vec<(i64, i64)>, SpaceError> {
    let runs = ink_column_runs(&tile.image);
    if runs.is_empty() {
        return Err(SpaceError::EmptyTile { source_sha256: tile.source_sha256.clone() });
    }
    if runs.len() != expected {
        return Err(SpaceError::UnexpectedClusterCount {
            source_sha256: tile.source_sha256.clone(),
            expected,
            found: runs.len(),
        });
    }
    Ok(runs)
}

/// Glyph strings of the two source tiles; run counts derive from them.
const TRIPLET_HSH: &str = "HsH";
const TRIPLET_HHH: &str = "HHH";

fn gaps(runs: &[(i64, i64)]) -> Vec<i64> {
    runs.iter().zip(runs.iter().skip(1)).map(|(a, b)| b.0 - a.1 - 1).collect()
}

fn finite(what: &str, v: f64) -> Result<f64, SpaceError> {
    if v.is_finite() {
        Ok(v)
    } else {
        Err(SpaceError::NonFiniteResult { what: what.to_string() })
    }
}

fn check_sb(policy: SidebearingPolicy, name: &str, v: f64) -> Result<(), SpaceError> {
    if !v.is_finite() {
        return Err(SpaceError::InvalidSidebearing { reason: format!("{name} not finite") });
    }
    if policy == SidebearingPolicy::RequireNonNegative && v < 0.0 {
        return Err(SpaceError::InvalidSidebearing { reason: format!("{name} negative under RequireNonNegative") });
    }
    Ok(())
}

/// Measure the space advance. Pure: no I/O, no global state.
pub fn measure_space_advance(req: &SpaceRequest) -> Result<SpaceMeasurement, SpaceError> {
    validate_frame("request.frame", &req.frame)?;
    let style = req.frame.style_id.clone();
    let missing = |m: MissingKind| SpaceError::MissingSpaceEvidence { style_id: style.clone(), missing: m };

    let hsh = req.hsh_tile.as_ref().ok_or_else(|| missing(MissingKind::HshTile))?;
    let hh = req.hh_spacing.as_ref().ok_or_else(|| missing(MissingKind::HhSpacing))?;
    let scale = req.scale.as_ref().ok_or_else(|| missing(MissingKind::Scale))?;

    // Scale: bound to this style, pinned-consistent, usable.
    nonempty("scale.style_id", &scale.style_id)?;
    nonempty("scale.evidence_ref", &scale.evidence_ref)?;
    if scale.style_id != req.frame.style_id {
        return Err(SpaceError::ScaleStyleMismatch {
            expected: req.frame.style_id.clone(),
            found: scale.style_id.clone(),
        });
    }
    if !matches!(scale.status, ScaleStatus::PinnedConsistent(_)) {
        return Err(SpaceError::ScaleNotPinnedConsistent {
            style_id: style.clone(),
            evidence_ref: scale.evidence_ref.clone(),
        });
    }
    if !(scale.units_per_px.is_finite() && scale.units_per_px > 0.0) {
        return Err(SpaceError::InvalidScale { style_id: style.clone() });
    }

    // Capture shaping record and HsH kern evidence.
    let shaping = req.capture_shaping.as_ref().ok_or_else(|| missing(MissingKind::CaptureShaping))?;
    let hsh_kern = req.hsh_kern.as_ref().ok_or_else(|| missing(MissingKind::HsHKern))?;
    nonempty("capture_shaping.settings_ref", &shaping.settings_ref)?;
    require_frame("capture_shaping.frame", &req.frame, &shaping.frame)?;
    if !shaping.ligatures_disabled {
        return Err(SpaceError::UnverifiedHsHContext { reason: "ligatures not disabled in capture".into() });
    }
    if !shaping.letter_spacing_px.is_finite() || shaping.letter_spacing_px != 0.0 {
        return Err(SpaceError::UnverifiedHsHContext { reason: "capture letter-spacing is not zero".into() });
    }
    let (hsh_kern_sum, hsh_kern_src) = match hsh_kern {
        HsHKernEvidence::Unverified => {
            return Err(SpaceError::UnverifiedHsHContext {
                reason: "no evidence for kern(H,space)+kern(space,H); G - SB is a contextual gap".into(),
            });
        }
        HsHKernEvidence::ZeroVerified { frame, evidence_ref } => {
            nonempty("hsh_kern.evidence_ref", evidence_ref)?;
            require_frame("hsh_kern.frame", &req.frame, frame)?;
            (0.0, format!("zero_verified:{evidence_ref}"))
        }
        HsHKernEvidence::KnownSumPx { frame, sum_px, evidence_ref } => {
            nonempty("hsh_kern.evidence_ref", evidence_ref)?;
            require_frame("hsh_kern.frame", &req.frame, frame)?;
            if !sum_px.is_finite() {
                return Err(SpaceError::UnverifiedHsHContext { reason: "HsH kern sum not finite".into() });
            }
            (*sum_px, format!("known_sum:{evidence_ref}"))
        }
    };

    // G(HsH).
    validate_tile("hsh_tile", hsh, &req.frame)?;
    if !shaping.covers_tile_sha256.iter().any(|h| h == &hsh.source_sha256) {
        return Err(SpaceError::UnverifiedHsHContext { reason: "capture shaping record does not cover the HsH tile".into() });
    }
    let hsh_runs = runs_expect(hsh, TRIPLET_HSH.matches('H').count())?;
    let hsh_gap_px = gaps(&hsh_runs)[0] as f64;
    let hsh_widths: Vec<i64> = hsh_runs.iter().map(|(a, b)| b - a + 1).collect();

    // rsb(H) + lsb(H).
    let mut hhh_gaps: Vec<i64> = Vec::new();
    let mut hhh_sha = String::new();
    let mut hhh_pix = String::new();
    let mut hhh_ident = String::new();
    let mut kern_px = 0.0_f64;
    let (sb_sum, hh_source) = match hh {
        HhSpacingEvidence::HhhTile { tile, kern } => {
            validate_tile("hhh_tile", tile, &req.frame)?;
            if !shaping.covers_tile_sha256.iter().any(|h| h == &tile.source_sha256) {
                return Err(SpaceError::UnverifiedHHSpacing {
                    reason: "capture shaping record does not cover the HHH tile".into(),
                });
            }
            let (k, src) = match kern {
                HhKernEvidence::Unverified => {
                    return Err(SpaceError::UnverifiedHHSpacing {
                        reason: "HHH tile without HH kern evidence; equal gaps do not show kern = 0".into(),
                    });
                }
                HhKernEvidence::ZeroVerified { frame, evidence_ref } => {
                    nonempty("hh_kern.evidence_ref", evidence_ref)?;
                    require_frame("hh_kern.frame", &req.frame, frame)?;
                    (0.0, format!("hhh_tile_kern_zero_verified:{evidence_ref}"))
                }
                HhKernEvidence::KnownPx { frame, kern_px, evidence_ref } => {
                    nonempty("hh_kern.evidence_ref", evidence_ref)?;
                    require_frame("hh_kern.frame", &req.frame, frame)?;
                    if !kern_px.is_finite() {
                        return Err(SpaceError::UnverifiedHHSpacing { reason: "HH kern not finite".into() });
                    }
                    (*kern_px, format!("hhh_tile_kern_known:{evidence_ref}"))
                }
            };
            let runs = runs_expect(tile, TRIPLET_HHH.len())?;
            hhh_gaps = gaps(&runs);
            let sum = (hhh_gaps[0] + hhh_gaps[1]) as f64;
            let mean_gap = sum / hhh_gaps.len() as f64;
            kern_px = k;
            hhh_sha = tile.source_sha256.clone();
            hhh_pix = sha256_hex(&tile.image.px);
            hhh_ident = tile.glyph_identity_ref.clone();
            // gap = rsb + lsb + k
            (finite("hhh mean gap minus kern", mean_gap - k)?, src)
        }
        HhSpacingEvidence::Explicit { frame, lsb_px, rsb_px, evidence_ref } => {
            nonempty("explicit_sidebearing.evidence_ref", evidence_ref)?;
            require_frame("explicit_sidebearing.frame", &req.frame, frame)?;
            check_sb(req.sidebearing_policy, "lsb", *lsb_px)?;
            check_sb(req.sidebearing_policy, "rsb", *rsb_px)?;
            (finite("explicit sidebearing sum", lsb_px + rsb_px)?, format!("explicit:{evidence_ref}"))
        }
    };
    if req.sidebearing_policy == SidebearingPolicy::RequireNonNegative && sb_sum < 0.0 {
        return Err(SpaceError::InvalidSidebearing { reason: "sidebearing sum negative under RequireNonNegative".into() });
    }

    // G = SB sum + advance + known HsH kern sum (letter-spacing verified 0).
    let space_px = finite("space advance px", hsh_gap_px - sb_sum - hsh_kern_sum)?;
    if space_px < 0.0 {
        return Err(SpaceError::NegativeSpace { gap_px: hsh_gap_px, sidebearing_sum_px: sb_sum });
    }
    let space_units = finite("space advance units", space_px * scale.units_per_px)?;

    let spread = if hhh_gaps.len() == TRIPLET_HHH.len() - 1 { (hhh_gaps[0] - hhh_gaps[1]).abs() } else { 0 };

    Ok(SpaceMeasurement {
        module: MODULE_ID,
        style_id: req.frame.style_id.clone(),
        frame_id: req.frame.frame_id.clone(),
        space_advance_px_slope: space_px,
        space_advance_units: space_units,
        hsh_gap_px,
        rsb_plus_lsb_px: sb_sum,
        hh_kern_px: kern_px,
        hsh_kern_sum_px: hsh_kern_sum,
        capture_shaping_ref: shaping.settings_ref.clone(),
        capture_letter_spacing_px: shaping.letter_spacing_px,
        capture_ligatures_disabled: shaping.ligatures_disabled,
        hhh_gaps_px: hhh_gaps,
        hhh_gap_spread_px: spread,
        units_per_px: scale.units_per_px,
        ink_threshold: INK_THRESHOLD,
        nominal_edge_bound_px: NOMINAL_EDGE_BOUND_PX,
        hsh_tile_sha256: hsh.source_sha256.clone(),
        hsh_pixels_sha256: sha256_hex(&hsh.image.px),
        hhh_tile_sha256: hhh_sha,
        hhh_pixels_sha256: hhh_pix,
        hsh_glyph_identity_ref: hsh.glyph_identity_ref.clone(),
        hhh_glyph_identity_ref: hhh_ident,
        hsh_cluster_widths_px: hsh_widths,
        hh_spacing_source: format!("{hh_source};hsh_kern:{hsh_kern_src}"),
        scale_ref: scale.evidence_ref.clone(),
        scale_status: match &scale.status {
            ScaleStatus::PinnedConsistent(proof) => format!("pinned_consistent:{}", proof.record_sha256()),
            ScaleStatus::Unverified => "unverified".to_string(),
        },
    })
}

/// Escape tab, newline, carriage return and backslash for a TSV cell.
pub fn tsv_escape(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => o.push_str("\\\\"),
            '\t' => o.push_str("\\t"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            _ => o.push(c),
        }
    }
    o
}

pub const LEDGER_HEADER: &str = "module\tstyle_id\tframe_id\thsh_tile_sha256\thsh_pixels_sha256\thsh_glyph_identity_ref\thhh_tile_sha256\thhh_pixels_sha256\thhh_glyph_identity_ref\thsh_gap_px\thhh_gaps_px\thhh_gap_spread_px\thh_kern_px\thsh_kern_sum_px\tcapture_shaping_ref\tcapture_letter_spacing_px\tcapture_ligatures_disabled\trsb_plus_lsb_px\tspace_advance_px_slope\tunits_per_px\tspace_advance_units\tink_threshold\tnominal_edge_bound_px_report_only\thh_spacing_source\tscale_ref\tscale_status\tunit";

impl SpaceMeasurement {
    /// One provenance ledger row; every free-text cell is escaped.
    pub fn ledger_row(&self) -> String {
        let gaps: Vec<String> = self.hhh_gaps_px.iter().map(|g| g.to_string()).collect();
        let cells: Vec<String> = vec![
            tsv_escape(self.module),
            tsv_escape(&self.style_id),
            tsv_escape(&self.frame_id),
            tsv_escape(&self.hsh_tile_sha256),
            tsv_escape(&self.hsh_pixels_sha256),
            tsv_escape(&self.hsh_glyph_identity_ref),
            tsv_escape(&self.hhh_tile_sha256),
            tsv_escape(&self.hhh_pixels_sha256),
            tsv_escape(&self.hhh_glyph_identity_ref),
            self.hsh_gap_px.to_string(),
            gaps.join(","),
            self.hhh_gap_spread_px.to_string(),
            self.hh_kern_px.to_string(),
            self.hsh_kern_sum_px.to_string(),
            tsv_escape(&self.capture_shaping_ref),
            self.capture_letter_spacing_px.to_string(),
            self.capture_ligatures_disabled.to_string(),
            self.rsb_plus_lsb_px.to_string(),
            self.space_advance_px_slope.to_string(),
            self.units_per_px.to_string(),
            self.space_advance_units.to_string(),
            self.ink_threshold.to_string(),
            self.nominal_edge_bound_px.to_string(),
            tsv_escape(&self.hh_spacing_source),
            tsv_escape(&self.scale_ref),
            tsv_escape(&self.scale_status),
            "px;units".to_string(),
        ];
        cells.join("\t")
    }
}

// Internal module keeps this refactor within the approved numeric-guard scope.
mod slope {
    use super::{
        CaptureShapingEvidence, MissingKind, ScaleEvidence, ScaleStatus, SourceFrame,
        SourceTile, SpaceError, border_background, finite, gaps, ink_column_runs_by,
        nonempty, require_frame, validate_frame, validate_tile, TRIPLET_HSH,
    };

    // ---------------------------------------------------------------------------
    // Slope route: H, n spaces, H for several n. space = d(ink gap)/d(n); H and its
    // sidebearings are in every tile and cancel, so no HHH tile is needed. Conditions
    // are records, not assumptions: letter-spacing 0, ligatures off, no kern on
    // H-space / space-space / space-H pairs (all verified), identical tile geometry,
    // distinct tiles per space count. The number is DESCRIPTIVE unless the caller
    // supplies a raster quantization bound with its derivation; then it is
    // ConsistentWithinBound only if every point lies on the fitted line within the
    // stated gap error. No threshold lives here.
    // ---------------------------------------------------------------------------

    pub const SLOPE_MODULE_ID: &str = "kni-space-slope/v1";

    /// Parameters of a straight line (slope, intercept); one residual needs one more point.
    const LINE_PARAMETERS: usize = 1 + 1;

    #[derive(Debug, Clone)]
    pub struct SlopeTile {
        /// Number of U+0020 in the submitted text between the two H, from the capture's
        /// own submission record (never parsed from a file name).
        pub spaces: usize,
        pub tile: SourceTile,
        /// Reference to that submission record for this tile.
        pub submitted_text_ref: String,
    }

    #[derive(Debug, Clone)]
    pub enum SlopeKernEvidence {
        /// kern(H,space), kern(space,space) and kern(space,H) are all zero (feature off or verified).
        ZeroVerifiedAllSpacePairs { frame: Option<SourceFrame>, evidence_ref: String },
        Unverified,
    }

    /// Ink definition of the source collection producer (kni_space_update.py /
    /// notdef_audit.column_profile): a pixel is ink when it differs from the tile's
    /// border-median background by MORE than `delta`; a column is inked when it holds at least one
    /// ink pixel; runs are maximal runs of inked columns. `delta` and its provenance come
    /// from the spec row, not from this file. Applies to the decoded gray plane (the old
    /// producer compared every channel; for black/white captures the two agree).
    #[derive(Debug, Clone)]
    pub struct InkModel {
        pub delta: u8,
        pub source_ref: String,
    }

    /// How the renderer turns an ideal straight edge into pixels. Only the model the
    /// chief named is supported: one binary sample per pixel, taken at the pixel center.
    #[derive(Debug, Clone, PartialEq)]
    pub enum EdgeSampling {
        BinaryPixelCenter,
    }

    /// Pinned renderer/capture contract. Every field is a reference to a record of the
    /// real capture (transform, device pixel ratio, antialias/filter, ink threshold,
    /// compression, clipping). The edge uncertainty is DERIVED from `sampling`; with no
    /// contract there is no bound and the result stays descriptive.
    #[derive(Debug, Clone)]
    pub struct RendererEdgeContract {
        pub sampling: EdgeSampling,
        pub capture_transform_ref: String,
        pub dpr_ref: String,
        /// Records that antialiasing/filtering is off (binary coverage), not assumed.
        pub filter_ref: String,
        pub threshold_ref: String,
        /// Records that the stored PNG is lossless.
        pub compression_ref: String,
        /// Records that no ink is clipped at the tile border.
        pub clipping_ref: String,
    }

    // Derivation, in half-pixel units so every number stays an exact integer.
    // One pixel pitch is two half-pixel units. A binary pixel-center sample places a
    // true straight edge inside a cell one pitch wide around the measured boundary, so
    // one edge is known to +- half a pitch. A gap is bounded by two edges, a cluster
    // width is bounded by two edges, and two cluster widths compared give four.
    const HALF_PX_PER_PX: i128 = 1 + 1;
    const EDGE_HALF_UNITS: i128 = HALF_PX_PER_PX / (1 + 1);
    const EDGES_PER_MEASURE: i128 = 1 + 1;
    /// f64 holds integers exactly up to 2^MANTISSA_DIGITS.
    const F64_EXACT_LIMIT: i128 = 1i128 << f64::MANTISSA_DIGITS;

    #[derive(Debug, Clone)]
    pub struct SpaceSlopeRequest {
        pub frame: SourceFrame,
        pub tiles: Vec<SlopeTile>,
        pub kern: Option<SlopeKernEvidence>,
        pub capture_shaping: Option<CaptureShapingEvidence>,
        pub scale: Option<ScaleEvidence>,
        pub edge_contract: Option<RendererEdgeContract>,
        pub ink: Option<InkModel>,
        /// Upper bound on slope tiles, from the manifest/spec limits. Checked before any allocation or loop over tiles.
        pub max_points: Option<usize>,
    }

    #[derive(Debug, Clone, PartialEq)]
    pub enum SlopeStatus {
        /// No renderer contract: slope and residuals are reported, nothing is decided.
        Descriptive { reason: String },
        /// A line exists whose gap at every n lies within the derived edge uncertainty of
        /// the measured gap, and the H cluster widths are consistent. The slope is an
        /// INTERVAL; `representative_px` is the midpoint of that interval (a selection
        /// rule, not a measurement).
        BoundedLineFeasible { slope_lo_px: f64, slope_hi_px: f64, representative_px: f64, derivation: String },
        /// No line fits every gap within the derived uncertainty. Says nothing beyond
        /// this model and these tiles.
        NoBoundedLine { reason: String },
        /// The feasible slope interval reaches zero or below while its top is positive: sign uncertain, reported as uncertain, never counted as positive.
        IntervalNotPositive { slope_lo_px: f64, slope_hi_px: f64 },
        /// The H cluster widths cannot all be one width within the derived uncertainty.
        GlyphWidthInconsistent { spread_px: f64, allowed_px: f64 },
    }

    #[derive(Debug, Clone, PartialEq)]
    pub struct SpaceSlopeMeasurement {
        pub module: &'static str,
        pub style_id: String,
        pub frame_id: String,
        pub spaces: Vec<usize>,
        pub tile_sha256: Vec<String>,
        pub gaps_px: Vec<i64>,
        pub increments_per_space_px: Vec<f64>,
        /// Ordinary least squares: DESCRIPTIVE only, separate from the bounded line.
        pub slope_px: f64,
        pub intercept_px: f64,
        pub residuals_px: Vec<f64>,
        pub max_abs_residual_px: f64,
        pub h_width_deviation_px: i64,
        pub units_per_px: f64,
        /// Descriptive: OLS slope in units. BoundedLineFeasible: representative in units.
        pub space_advance_units: f64,
        /// Units interval, present only for BoundedLineFeasible.
        pub advance_units_interval: Option<(f64, f64)>,
        pub scale_ref: String,
        pub status: SlopeStatus,
    }

    impl SpaceSlopeMeasurement {
        /// The only way to get a number the assembly may emit.
        pub fn exportable_advance_units(&self) -> Result<f64, SpaceError> {
            match &self.status {
                SlopeStatus::BoundedLineFeasible { .. } => Ok(self.space_advance_units),
                other => Err(SpaceError::SlopeNotExportable { reason: format!("{other:?}") }),
            }
        }

        /// Receipt text that must accompany any emitted slope value.
        pub fn uncertainty_line(&self) -> String {
            match (&self.status, self.advance_units_interval) {
                (SlopeStatus::BoundedLineFeasible { slope_lo_px, slope_hi_px, representative_px, derivation }, Some((lo, hi))) => format!(
                    "slope_interval_px\t{slope_lo_px}\t{slope_hi_px}\trepresentative_px\t{representative_px}\tunits_interval\t{lo}\t{hi}\tderivation\t{derivation}\t(interval, not an exact advance)"
                ),
                _ => "slope_interval\tnone".to_string(),
            }
        }
    }

    fn exact_i128(what: &str, v: i128) -> Result<i128, SpaceError> {
        if v.abs() <= F64_EXACT_LIMIT {
            Ok(v)
        } else {
            Err(SpaceError::NonFiniteResult { what: format!("{what} beyond exact f64 range") })
        }
    }

    fn ratio(what: &str, num: i128, den: i128) -> Result<f64, SpaceError> {
        exact_i128(what, num)?;
        exact_i128(what, den)?;
        if den == 0 {
            return Err(SpaceError::NonFiniteResult { what: what.to_string() });
        }
        finite(what, num as f64 / den as f64)
    }

    fn ck(what: &str, v: Option<i128>) -> Result<i128, SpaceError> {
        v.ok_or_else(|| SpaceError::ArithmeticOverflow { what: what.to_string() })
    }

    /// Sign combinations per constraint pair: lower or upper side for each of the two points.
    const SIDES_PER_POINT: u128 = 1 + 1;

    /// Work of the exact interval search for `n` points, in constraint evaluations:
    /// candidate (pair, side, side) lines times the points each is checked against.
    fn slope_work(n: u128) -> Option<u128> {
        let pairs = n.checked_mul(n.checked_sub(1)?)? / (1 + 1);
        pairs.checked_mul(SIDES_PER_POINT)?.checked_mul(SIDES_PER_POINT)?.checked_mul(n)
    }

    /// Exact feasible slope interval for lines a + s*n with |a + s*n_i - g_i| <= u for
    /// every point (integers, half-pixel units), every operation checked. Returns
    /// (lo, hi) as (num, den>0). Work is bounded by `budget` constraint evaluations,
    /// derived by the caller from max_points.
    fn feasible_slope_interval(pts: &[(i128, i128)], u: i128, budget: u128) -> Result<Option<((i128, i128), (i128, i128))>, SpaceError> {
        let n = u128::try_from(pts.len()).map_err(|_| SpaceError::ArithmeticOverflow { what: "point count".into() })?;
        let need = slope_work(n).ok_or_else(|| SpaceError::ArithmeticOverflow { what: "work estimate".into() })?;
        if need > budget {
            return Err(SpaceError::ResourceLimit { what: "slope interval work".into(), limit: budget, found: need });
        }
        let mut lo: Option<(i128, i128)> = None;
        let mut hi: Option<(i128, i128)> = None;
        let sides = [ck("side", u.checked_neg())?, u];
        for (i, &(ni, gi)) in pts.iter().enumerate() {
            for &(nj, gj) in pts.iter().skip(i + 1) {
                if ni == nj {
                    continue;
                }
                for si in sides {
                    for sj in sides {
                        let ci = ck("c_i", gi.checked_add(si))?;
                        let cj = ck("c_j", gj.checked_add(sj))?;
                        let mut num = ck("slope num", cj.checked_sub(ci))?;
                        let mut den = ck("slope den", nj.checked_sub(ni))?;
                        if den < 0 {
                            num = ck("slope num", num.checked_neg())?;
                            den = ck("slope den", den.checked_neg())?;
                        }
                        let a_num = ck("intercept", ci.checked_mul(den).and_then(|x| num.checked_mul(ni).and_then(|y| x.checked_sub(y))))?;
                        let mut ok = true;
                        for &(nk, gk) in pts {
                            let v = ck("constraint", num.checked_mul(nk).and_then(|x| a_num.checked_add(x)))?;
                            let lo_b = ck("bound", gk.checked_sub(u).and_then(|x| x.checked_mul(den)))?;
                            let hi_b = ck("bound", gk.checked_add(u).and_then(|x| x.checked_mul(den)))?;
                            if v < lo_b || v > hi_b {
                                ok = false;
                                break;
                            }
                        }
                        if !ok {
                            continue;
                        }
                        let less = |a: (i128, i128), b: (i128, i128)| -> Result<bool, SpaceError> {
                            Ok(ck("cmp", a.0.checked_mul(b.1))? < ck("cmp", b.0.checked_mul(a.1))?)
                        };
                        if match lo { None => true, Some(l) => less((num, den), l)? } {
                            lo = Some((num, den));
                        }
                        if match hi { None => true, Some(h) => less(h, (num, den))? } {
                            hi = Some((num, den));
                        }
                    }
                }
            }
        }
        Ok(lo.zip(hi))
    }

    pub fn measure_space_slope(req: &SpaceSlopeRequest) -> Result<SpaceSlopeMeasurement, SpaceError> {
        validate_frame("request.frame", &req.frame)?;
        let style = req.frame.style_id.clone();
        let missing = |m: MissingKind| SpaceError::MissingSpaceEvidence { style_id: style.clone(), missing: m };
        let scale = req.scale.as_ref().ok_or_else(|| missing(MissingKind::Scale))?;
        nonempty("scale.style_id", &scale.style_id)?;
        nonempty("scale.evidence_ref", &scale.evidence_ref)?;
        if scale.style_id != req.frame.style_id {
            return Err(SpaceError::ScaleStyleMismatch { expected: req.frame.style_id.clone(), found: scale.style_id.clone() });
        }
        if !matches!(scale.status, ScaleStatus::PinnedConsistent(_)) {
            return Err(SpaceError::ScaleNotPinnedConsistent { style_id: style.clone(), evidence_ref: scale.evidence_ref.clone() });
        }
        if !(scale.units_per_px.is_finite() && scale.units_per_px > 0.0) {
            return Err(SpaceError::InvalidScale { style_id: style.clone() });
        }
        let shaping = req.capture_shaping.as_ref().ok_or_else(|| missing(MissingKind::CaptureShaping))?;
        nonempty("capture_shaping.settings_ref", &shaping.settings_ref)?;
        require_frame("capture_shaping.frame", &req.frame, &shaping.frame)?;
        if !shaping.ligatures_disabled {
            return Err(SpaceError::UnverifiedHsHContext { reason: "ligatures not disabled in capture".into() });
        }
        if !shaping.letter_spacing_px.is_finite() || shaping.letter_spacing_px != 0.0 {
            return Err(SpaceError::UnverifiedHsHContext { reason: "capture letter-spacing is not zero or not recorded".into() });
        }
        match req.kern.as_ref().ok_or_else(|| missing(MissingKind::HsHKern))? {
            SlopeKernEvidence::ZeroVerifiedAllSpacePairs { frame, evidence_ref } => {
                nonempty("slope_kern.evidence_ref", evidence_ref)?;
                require_frame("slope_kern.frame", &req.frame, frame)?;
            }
            SlopeKernEvidence::Unverified => {
                return Err(SpaceError::UnverifiedHsHContext { reason: "kern around spaces not verified zero".into() });
            }
        }

        // Resource bound first: nothing below allocates or loops over tiles before this.
        let max_points = req.max_points.ok_or_else(|| missing(MissingKind::Limits))?;
        if req.tiles.len() > max_points {
            return Err(SpaceError::ResourceLimit { what: "slope tiles".into(), limit: max_points as u128, found: req.tiles.len() as u128 });
        }
        // Tiles: enough points, distinct counts, distinct bytes, same geometry, shaping coverage.
        let needed = LINE_PARAMETERS + 1;
        let mut tiles: Vec<&SlopeTile> = req.tiles.iter().collect();
        tiles.sort_by_key(|t| t.spaces);
        if tiles.len() < needed || tiles.iter().any(|t| t.spaces == 0) {
            return Err(SpaceError::TooFewSlopePoints { found: tiles.len(), needed });
        }
        for w in tiles.windows(LINE_PARAMETERS) {
            if w[0].spaces == w[1].spaces {
                return Err(SpaceError::DuplicateSpaceCount { spaces: w[0].spaces });
            }
        }
        for (i, a) in tiles.iter().enumerate() {
            validate_tile("slope_tile", &a.tile, &req.frame)?;
            nonempty("slope_tile.submitted_text_ref", &a.submitted_text_ref)?;
            if !shaping.covers_tile_sha256.iter().any(|h| h == &a.tile.source_sha256) {
                return Err(SpaceError::UnverifiedHsHContext { reason: "capture shaping record does not cover a slope tile".into() });
            }
            for b in tiles.iter().skip(i + 1) {
                if a.tile.source_sha256 == b.tile.source_sha256 {
                    return Err(SpaceError::AliasedSlopeTiles {
                        source_sha256: a.tile.source_sha256.clone(),
                        spaces_a: a.spaces,
                        spaces_b: b.spaces,
                    });
                }
            }
        }
        let ink = req.ink.as_ref().ok_or_else(|| missing(MissingKind::InkModel))?;
        nonempty("ink.source_ref", &ink.source_ref)?;
        let first = &tiles[0].tile.image;
        // Tile width follows the text length by construction; the frame (height) must not move.
        let wh = (first.width, first.height);
        for t in &tiles {
            let f = (t.tile.image.width, t.tile.image.height);
            if f.1 != wh.1 {
                return Err(SpaceError::SlopeGeometryDrift { source_sha256: t.tile.source_sha256.clone(), expected_wh: wh, found_wh: f });
            }
        }

        // Gap per tile (exactly two H clusters) and H width spread.
        let clusters = TRIPLET_HSH.matches('H').count();
        let mut gaps_px: Vec<i64> = Vec::new();
        let mut widths: Vec<i64> = Vec::new();
        for t in &tiles {
            let img = &t.tile.image;
            let bg = border_background(img, ink.delta, &t.tile.source_sha256)?;
            let runs = ink_column_runs_by(img, &|v| v.abs_diff(bg) > ink.delta);
            if runs.is_empty() {
                return Err(SpaceError::EmptyTile { source_sha256: t.tile.source_sha256.clone() });
            }
            if runs.len() != clusters {
                return Err(SpaceError::UnexpectedClusterCount { source_sha256: t.tile.source_sha256.clone(), expected: clusters, found: runs.len() });
            }
            gaps_px.push(gaps(&runs)[0]);
            widths.extend(runs.iter().map(|(a, b)| b - a + 1));
        }
        for t in tiles.windows(LINE_PARAMETERS) {
            if t[1].spaces <= t[0].spaces {
                return Err(SpaceError::SpacesNotStrictlyIncreasing { spaces_a: t[0].spaces, spaces_b: t[1].spaces });
            }
        }
        let wmax = widths.iter().copied().max().unwrap_or(0);
        let wmin = widths.iter().copied().min().unwrap_or(0);
        let h_width_deviation_px = wmax - wmin;

        // Exact integer bookkeeping first, bounded conversion after.
        let mut pts: Vec<(i128, i128)> = Vec::new();
        for (t, g) in tiles.iter().zip(&gaps_px) {
            let n = exact_i128("space count", i128::try_from(t.spaces).map_err(|_| SpaceError::NonFiniteResult { what: "space count".into() })?)?;
            pts.push((n, exact_i128("gap", ck("gap scale", HALF_PX_PER_PX.checked_mul(i128::from(*g)))?)?));
        }
        let cnt = i128::try_from(pts.len()).map_err(|_| SpaceError::ArithmeticOverflow { what: "point count".into() })?;
        let (mut sx, mut sy, mut sxx, mut sxy) = (0i128, 0i128, 0i128, 0i128);
        for p in &pts {
            sx = ck("sum n", sx.checked_add(p.0))?;
            sy = ck("sum gap", sy.checked_add(p.1))?;
            sxx = ck("sum n*n", p.0.checked_mul(p.0).and_then(|v| sxx.checked_add(v)))?;
            sxy = ck("sum n*gap", p.0.checked_mul(p.1).and_then(|v| sxy.checked_add(v)))?;
        }
        let den = ck("ols den", cnt.checked_mul(sxx).and_then(|a| sx.checked_mul(sx).and_then(|b| a.checked_sub(b))))?;
        let ols_num = ck("ols num", cnt.checked_mul(sxy).and_then(|a| sx.checked_mul(sy).and_then(|b| a.checked_sub(b))))?;
        // OLS slope in half-pixel units per space -> px.
        let slope_px = ratio("slope", ols_num, ck("ols den scale", den.checked_mul(HALF_PX_PER_PX))?)?;
        let n_f = ratio("count", cnt, 1)?;
        let sx_f = ratio("sum n", sx, 1)?;
        let sy_f = ratio("sum gap", sy, HALF_PX_PER_PX)?;
        let intercept_px = finite("intercept", (sy_f - slope_px * sx_f) / n_f)?;
        let mut residuals_px: Vec<f64> = Vec::new();
        for (t, g) in tiles.iter().zip(&gaps_px) {
            let x = ratio("space count", i128::try_from(t.spaces).map_err(|_| SpaceError::ArithmeticOverflow { what: "space count".into() })?, 1)?;
            residuals_px.push(finite("residual", *g as f64 - (intercept_px + slope_px * x))?);
        }
        let max_abs_residual_px = residuals_px.iter().fold(0.0f64, |m, r| m.max(r.abs()));
        let increments_per_space_px: Vec<f64> = tiles
            .windows(LINE_PARAMETERS)
            .zip(gaps_px.windows(LINE_PARAMETERS))
            .map(|(t, g)| finite("increment", (g[1] - g[0]) as f64 / (t[1].spaces - t[0].spaces) as f64))
            .collect::<Result<Vec<f64>, SpaceError>>()?;
        let mut space_advance_units = finite("space advance units", slope_px * scale.units_per_px)?;
        let mut advance_units_interval = None;

        let status = match &req.edge_contract {
            None => SlopeStatus::Descriptive { reason: "no pinned renderer edge contract; no uncertainty bound; linearity undecided".into() },
            Some(c) => {
                nonempty("edge_contract.capture_transform_ref", &c.capture_transform_ref)?;
                nonempty("edge_contract.dpr_ref", &c.dpr_ref)?;
                nonempty("edge_contract.filter_ref", &c.filter_ref)?;
                nonempty("edge_contract.threshold_ref", &c.threshold_ref)?;
                nonempty("edge_contract.compression_ref", &c.compression_ref)?;
                nonempty("edge_contract.clipping_ref", &c.clipping_ref)?;
                let EdgeSampling::BinaryPixelCenter = c.sampling;
                let u = EDGES_PER_MEASURE * EDGE_HALF_UNITS;
                let budget = slope_work(max_points as u128).ok_or_else(|| SpaceError::ArithmeticOverflow { what: "work budget".into() })?;
                // Cluster widths: every width W_j lies in [w_j - u, w_j + u]; one glyph means
                // the intervals must intersect, i.e. spread <= 2u (four edges).
                let allowed = EDGES_PER_MEASURE * u;
                let spread = HALF_PX_PER_PX * i128::from(h_width_deviation_px);
                if spread > allowed {
                    SlopeStatus::GlyphWidthInconsistent {
                        spread_px: ratio("width spread", spread, HALF_PX_PER_PX)?,
                        allowed_px: ratio("allowed width spread", allowed, HALF_PX_PER_PX)?,
                    }
                } else {
                    match feasible_slope_interval(&pts, u, budget)? {
                        None => SlopeStatus::NoBoundedLine {
                            reason: "no line keeps every gap within the derived edge uncertainty".into(),
                        },
                        Some(((nl, dl), (nh, dh))) => {
                            let lo = ratio("slope lo", nl, ck("slope lo den", dl.checked_mul(HALF_PX_PER_PX))?)?;
                            let hi = ratio("slope hi", nh, ck("slope hi den", dh.checked_mul(HALF_PX_PER_PX))?)?;
                            if hi <= 0.0 {
                                return Err(SpaceError::SlopeNotPositive { slope_px: hi });
                            } else if lo <= 0.0 {
                                SlopeStatus::IntervalNotPositive { slope_lo_px: lo, slope_hi_px: hi }
                            } else {
                                let rep = finite("representative", (lo + hi) / ratio("two", 1 + 1, 1)?)?;
                                space_advance_units = finite("representative units", rep * scale.units_per_px)?;
                                advance_units_interval = Some((
                                    finite("units lo", lo * scale.units_per_px)?,
                                    finite("units hi", hi * scale.units_per_px)?,
                                ));
                                SlopeStatus::BoundedLineFeasible {
                                    slope_lo_px: lo,
                                    slope_hi_px: hi,
                                    representative_px: rep,
                                    derivation: format!(
                                        "binary-pixel-center edge cell; transform {} dpr {} filter {} threshold {} compression {} clipping {}",
                                        c.capture_transform_ref, c.dpr_ref, c.filter_ref, c.threshold_ref, c.compression_ref, c.clipping_ref
                                    ),
                                }
                            }
                        }
                    }
                }
            }
        };
        if matches!(status, SlopeStatus::Descriptive { .. }) && slope_px <= 0.0 {
            return Err(SpaceError::SlopeNotPositive { slope_px });
        }
        Ok(SpaceSlopeMeasurement {
            module: SLOPE_MODULE_ID,
            style_id: req.frame.style_id.clone(),
            frame_id: req.frame.frame_id.clone(),
            spaces: tiles.iter().map(|t| t.spaces).collect(),
            tile_sha256: tiles.iter().map(|t| t.tile.source_sha256.clone()).collect(),
            gaps_px,
            increments_per_space_px,
            slope_px,
            intercept_px,
            residuals_px,
            max_abs_residual_px,
            h_width_deviation_px,
            units_per_px: scale.units_per_px,
            space_advance_units,
            advance_units_interval,
            scale_ref: scale.evidence_ref.clone(),
            status,
        })
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use crate::plane::GrayImage;
        use crate::space_measurement::ScaleConsistencyProof;

        fn frame() -> SourceFrame {
            SourceFrame { style_id: "unit-regular".into(), frame_id: "f1".into() }
        }

        fn tile(sha: &str, width: u32, h: u32, blocks: &[(u32, u32)]) -> SourceTile {
            let mut px = vec![255u8; (width * h) as usize];
            for &(s, w) in blocks {
                for y in 0..h {
                    for x in s..s + w {
                        px[(y * width + x) as usize] = 0;
                    }
                }
            }
            SourceTile {
                source_sha256: sha.to_string(),
                frame: Some(frame()),
                glyph_identity_ref: format!("manifest:{sha}"),
                image: GrayImage::new(width, h, px),
            }
        }

        fn scale() -> ScaleEvidence {
            ScaleEvidence { style_id: "unit-regular".into(), units_per_px: 2.0, evidence_ref: "scale-ref".into(), status: ScaleStatus::PinnedConsistent(ScaleConsistencyProof::check("r", "r", &frame(), &frame(), 2.0, 2.0, "t", &["t".to_string()]).unwrap()) }
        }

        fn shaping() -> CaptureShapingEvidence {
            CaptureShapingEvidence {
                frame: Some(frame()),
                settings_ref: "capture-settings-1".into(),
                ligatures_disabled: true,
                letter_spacing_px: 0.0,
                covers_tile_sha256: vec!["sha-hsh".into(), "sha-hhh".into()],
            }
        }

        // ---- slope route ----
        fn stile(sha: &str, spaces: usize, width: u32, gap: u32, w2: u32) -> SlopeTile {
            SlopeTile { spaces, tile: tile(sha, width, 8, &[(2, 10), (12 + gap, w2)]), submitted_text_ref: format!("ledger:{sha}") }
        }
        fn slope_shaping() -> CaptureShapingEvidence {
            CaptureShapingEvidence { covers_tile_sha256: vec!["s1".into(), "s2".into(), "s3".into()], ..shaping() }
        }
        fn slope_req(gaps: [u32; 3]) -> SpaceSlopeRequest {
            SpaceSlopeRequest {
                frame: frame(),
                tiles: vec![stile("s1", 1, 80, gaps[0], 10), stile("s2", 2, 80, gaps[1], 10), stile("s3", 3, 80, gaps[2], 10)],
                kern: Some(SlopeKernEvidence::ZeroVerifiedAllSpacePairs { frame: Some(frame()), evidence_ref: "kern-off".into() }),
                capture_shaping: Some(slope_shaping()),
                scale: Some(scale()),
                edge_contract: None,
                ink: Some(InkModel { delta: 8, source_ref: "test:kni_space_update INK_DELTA".into() }),
                max_points: Some(tile_limit_for_tests()),
            }
        }

        fn tile_limit_for_tests() -> usize {
            3 + 1
        }

        fn contract() -> RendererEdgeContract {
            RendererEdgeContract {
                sampling: EdgeSampling::BinaryPixelCenter,
                capture_transform_ref: "t".into(),
                dpr_ref: "d".into(),
                filter_ref: "f".into(),
                threshold_ref: "th".into(),
                compression_ref: "c".into(),
                clipping_ref: "cl".into(),
            }
        }

        #[test]
        fn slope_linear_is_descriptive_without_contract_and_not_exportable() {
            let m = measure_space_slope(&slope_req([12, 22, 32])).unwrap();
            assert_eq!(m.gaps_px, vec![12, 22, 32]);
            assert_eq!(m.slope_px, 10.0);
            assert_eq!(m.max_abs_residual_px, 0.0);
            assert!(matches!(m.status, SlopeStatus::Descriptive { .. }));
            assert!(m.advance_units_interval.is_none());
            assert!(matches!(m.exportable_advance_units(), Err(SpaceError::SlopeNotExportable { .. })));
        }

        #[test]
        fn slope_bounded_line_gives_interval_and_receipt() {
            let mut r = slope_req([12, 22, 32]);
            r.edge_contract = Some(contract());
            let m = measure_space_slope(&r).unwrap();
            // gap error +-1 px (two edges), so slope in [(32-1)-(12+1), ...]/2 = [9, 11]
            match &m.status {
                SlopeStatus::BoundedLineFeasible { slope_lo_px, slope_hi_px, representative_px, .. } => {
                    assert_eq!((*slope_lo_px, *slope_hi_px, *representative_px), (9.0, 11.0, 10.0));
                }
                o => panic!("{o:?}"),
            }
            assert_eq!(m.advance_units_interval, Some((18.0, 22.0)));
            assert_eq!(m.exportable_advance_units().unwrap(), 20.0);
            assert!(m.uncertainty_line().contains("interval, not an exact advance"));
        }

        #[test]
        fn real_marq_gaps_are_an_interval_not_an_exact_107() {
            let mut real = slope_req([12, 22, 32]);
            real.tiles = vec![stile("s1", 1, 700, 185, 10), stile("s2", 2, 700, 293, 10), stile("s3", 3, 700, 399, 10)];
            real.edge_contract = Some(contract());
            let m = measure_space_slope(&real).unwrap();
            assert_eq!(m.increments_per_space_px, vec![108.0, 106.0]);
            match &m.status {
                SlopeStatus::BoundedLineFeasible { slope_lo_px, slope_hi_px, .. } => {
                    assert!(*slope_lo_px < 107.0 && 107.0 < *slope_hi_px);
                    assert!(*slope_lo_px <= 106.0 + 1.0 && *slope_hi_px >= 108.0 - 1.0);
                }
                o => panic!("{o:?}"),
            }
            assert!(m.advance_units_interval.is_some());
        }

        #[test]
        fn slope_inconsistent_counts_have_no_bounded_line() {
            let mut r = slope_req([12, 22, 45]);
            r.edge_contract = Some(contract());
            let m = measure_space_slope(&r).unwrap();
            assert!(matches!(m.status, SlopeStatus::NoBoundedLine { .. }), "{:?}", m.status);
            assert!(m.exportable_advance_units().is_err());
            // OLS is still reported, separately, as descriptive
            assert!(m.max_abs_residual_px > 0.0);
        }

        #[test]
        fn slope_glyph_width_spread_uses_four_edges() {
            let mut r = slope_req([12, 22, 32]);
            r.edge_contract = Some(contract());
            r.tiles[2] = stile("s3", 3, 80, 32, 12); // spread 2 = four half-pixel edges: allowed
            assert!(matches!(measure_space_slope(&r).unwrap().status, SlopeStatus::BoundedLineFeasible { .. }));
            r.tiles[2] = stile("s3", 3, 80, 32, 13); // spread 3 > 2
            let m = measure_space_slope(&r).unwrap();
            assert!(matches!(m.status, SlopeStatus::GlyphWidthInconsistent { .. }), "{:?}", m.status);
            assert!(m.exportable_advance_units().is_err());
        }

        #[test]
        fn slope_contract_fields_are_required() {
            let mut r = slope_req([12, 22, 32]);
            let mut c = contract();
            c.filter_ref = String::new();
            r.edge_contract = Some(c);
            assert!(measure_space_slope(&r).is_err());
        }

        #[test]
        fn slope_interval_touching_zero_is_not_positive() {
            let mut r = slope_req([12, 13, 14]);
            r.edge_contract = Some(contract());
            let m = measure_space_slope(&r).unwrap();
            assert!(matches!(m.status, SlopeStatus::BoundedLineFeasible { .. } | SlopeStatus::IntervalNotPositive { .. }));
            // equal gaps: the feasible interval reaches zero or below, so no exportable bounded slope
            let mut r = slope_req([12, 12, 12]);
            r.edge_contract = Some(contract());
            let m = measure_space_slope(&r).unwrap();
            assert!(matches!(m.status, SlopeStatus::IntervalNotPositive { .. }), "{:?}", m.status);
            assert!(m.exportable_advance_units().is_err());
        }

        #[test]
        fn slope_counts_beyond_exact_f64_are_refused() {
            let mut r = slope_req([12, 22, 32]);
            r.tiles[2].spaces = usize::MAX;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::NonFiniteResult { .. })));
        }

        #[test]
        fn slope_ink_model_is_required_and_matches_old_producer_rule() {
            let mut r = slope_req([12, 22, 32]);
            r.ink = None;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::InkModel, .. })));
            // faint smear at or below delta from the background is not ink; above is
            let mut r = slope_req([12, 22, 32]);
            let w = r.tiles[0].tile.image.width as usize;
            let mid = w / (1 + 1);
            r.tiles[0].tile.image.px[mid] = 255 - 8;
            assert!(measure_space_slope(&r).is_ok());
            r.tiles[0].tile.image.px[mid] = 255 - 9;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::UnexpectedClusterCount { .. })));
        }

        #[test]
        fn slope_resource_limits_and_overflow_are_typed() {
            // more tiles than max_points: refused before any tile work
            let mut r = slope_req([12, 22, 32]);
            r.max_points = Some(2);
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::ResourceLimit { .. })));
            // limits missing
            let mut r = slope_req([12, 22, 32]);
            r.max_points = None;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::Limits, .. })));
            // work budget is derived from max_points: the same points under a smaller derived budget fail
            let pts = [(1i128, 24i128), (2, 44), (3, 64)];
            assert!(matches!(feasible_slope_interval(&pts, 2, 0), Err(SpaceError::ResourceLimit { .. })));
            assert!(feasible_slope_interval(&pts, 2, slope_work(3).unwrap()).unwrap().is_some());
            // overflow in the exact search is typed, not wrapped
            let big = [(0i128, i128::MAX / 2), (i128::MAX / 4, i128::MAX / 2)];
            assert!(matches!(feasible_slope_interval(&big, 2, slope_work(2).unwrap()), Err(SpaceError::ArithmeticOverflow { .. })));
        }

        #[test]
        fn slope_background_ambiguity_is_typed() {
            let mut r = slope_req([12, 22, 32]);
            r.tiles[0].tile.image.px[0] = 0; // dark top-left corner on a white border
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::BackgroundAmbiguous { .. })));
        }

        #[test]
        fn slope_refusals() {
            // aliased: two space counts, identical bytes (sha)
            let mut r = slope_req([12, 22, 32]);
            r.tiles[2] = stile("s2", 3, 80, 22, 10);
            r.capture_shaping = Some(slope_shaping());
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::AliasedSlopeTiles { .. })));
            // frame drift: different tile geometry
            let mut r = slope_req([12, 22, 32]);
            r.tiles[2].tile = tile("s3", 80, 9, &[(2, 10), (44, 10)]);
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::SlopeGeometryDrift { .. })));
            // tile frame differs from request
            let mut r = slope_req([12, 22, 32]);
            r.tiles[1].tile.frame = Some(SourceFrame { style_id: "unit-regular".into(), frame_id: "f2".into() });
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::FrameMismatch { .. })));
            // kern unknown
            let mut r = slope_req([12, 22, 32]);
            r.kern = Some(SlopeKernEvidence::Unverified);
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
            r.kern = None;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::HsHKern, .. })));
            // letter-spacing unknown/nonzero, ligatures on, shaping missing/not covering
            let mut r = slope_req([12, 22, 32]);
            r.capture_shaping = Some(CaptureShapingEvidence { letter_spacing_px: 1.0, ..slope_shaping() });
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
            r.capture_shaping = Some(CaptureShapingEvidence { letter_spacing_px: f64::NAN, ..slope_shaping() });
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
            r.capture_shaping = Some(CaptureShapingEvidence { ligatures_disabled: false, ..slope_shaping() });
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
            r.capture_shaping = Some(CaptureShapingEvidence { covers_tile_sha256: vec!["s1".into(), "s2".into()], ..slope_shaping() });
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
            r.capture_shaping = None;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::CaptureShaping, .. })));
            // too few points, duplicate count, zero spaces
            let mut r = slope_req([12, 22, 32]);
            r.tiles.truncate(2);
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::TooFewSlopePoints { .. })));
            let mut r = slope_req([12, 22, 32]);
            r.tiles[2].spaces = 2;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::DuplicateSpaceCount { .. })));
            let mut r = slope_req([12, 22, 32]);
            r.tiles[0].spaces = 0;
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::TooFewSlopePoints { .. })));
            // scale not pinned
            let mut r = slope_req([12, 22, 32]);
            r.scale = Some(ScaleEvidence { status: ScaleStatus::Unverified, ..scale() });
            assert!(matches!(measure_space_slope(&r), Err(SpaceError::ScaleNotPinnedConsistent { .. })));
            // decreasing gaps: negative slope refused, not clamped
            assert!(matches!(measure_space_slope(&slope_req([32, 22, 12])), Err(SpaceError::SlopeNotPositive { .. })));
            let mut dec = slope_req([20, 18, 16]);
            dec.edge_contract = Some(contract());
            assert!(matches!(measure_space_slope(&dec), Err(SpaceError::SlopeNotPositive { .. })));
            for g in [[20, 20, 21], [20, 19, 22]] {
                let mut r = slope_req(g);
                r.edge_contract = Some(contract());
                // not pre-rejected: the outcome is whatever the bounded interval says
                let m = measure_space_slope(&r).unwrap();
                assert!(matches!(m.status, SlopeStatus::BoundedLineFeasible { .. } | SlopeStatus::IntervalNotPositive { .. }), "{g:?}: {:?}", m.status);
            }
            // wrapped-looking (third gap no larger than the second): no hard pre-refusal; with a contract no bounded line exists
            let mut w = slope_req([12, 22, 22]);
            w.edge_contract = Some(contract());
            assert!(matches!(measure_space_slope(&w).unwrap().status, SlopeStatus::NoBoundedLine { .. }));
        }
        #[test]
        fn legacy_slope_api_remains_registered() {
            use crate::space_measurement as legacy;
            let measure: fn(&legacy::SpaceSlopeRequest) -> Result<legacy::SpaceSlopeMeasurement, legacy::SpaceError> = legacy::measure_space_slope;
            let result = measure(&slope_req([12, 22, 32])).unwrap();
            assert_eq!(result.module, legacy::SLOPE_MODULE_ID);
            let _: legacy::SlopeStatus = result.status;
        }
    }
}

// Preserve every public slope item at kni_metrics::space_measurement::*.
pub use self::slope::{
    EdgeSampling, InkModel, RendererEdgeContract, SLOPE_MODULE_ID, SlopeKernEvidence,
    SlopeStatus, SlopeTile, SpaceSlopeMeasurement, SpaceSlopeRequest, measure_space_slope,
};

// ---------------------------------------------------------------------------
// Unit tests. UNRUN: source-only, not compiled or executed. Expected values
// come from the layout arithmetic of synthetic tiles.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    fn frame() -> SourceFrame {
        SourceFrame { style_id: "unit-regular".into(), frame_id: "f1".into() }
    }

    fn tile(sha: &str, width: u32, h: u32, blocks: &[(u32, u32)]) -> SourceTile {
        let mut px = vec![255u8; (width * h) as usize];
        for &(s, w) in blocks {
            for y in 0..h {
                for x in s..s + w {
                    px[(y * width + x) as usize] = 0;
                }
            }
        }
        SourceTile {
            source_sha256: sha.to_string(),
            frame: Some(frame()),
            glyph_identity_ref: format!("manifest:{sha}"),
            image: GrayImage::new(width, h, px),
        }
    }

    fn scale() -> ScaleEvidence {
        ScaleEvidence { style_id: "unit-regular".into(), units_per_px: 2.0, evidence_ref: "scale-ref".into(), status: ScaleStatus::PinnedConsistent(ScaleConsistencyProof::check("r", "r", &frame(), &frame(), 2.0, 2.0, "t", &["t".to_string()]).unwrap()) }
    }

    fn zero_kern() -> HhKernEvidence {
        HhKernEvidence::ZeroVerified { frame: Some(frame()), evidence_ref: "kern-off".into() }
    }

    fn shaping() -> CaptureShapingEvidence {
        CaptureShapingEvidence {
            frame: Some(frame()),
            settings_ref: "capture-settings-1".into(),
            ligatures_disabled: true,
            letter_spacing_px: 0.0,
            covers_tile_sha256: vec!["sha-hsh".into(), "sha-hhh".into()],
        }
    }

    fn hsh_zero() -> HsHKernEvidence {
        HsHKernEvidence::ZeroVerified { frame: Some(frame()), evidence_ref: "hsh-kern-off".into() }
    }

    // H width 10. HHH gaps 4, 4. HsH gap 14 -> space 10 px (kern 0).
    fn request() -> SpaceRequest {
        SpaceRequest {
            frame: frame(),
            hsh_tile: Some(tile("sha-hsh", 40, 8, &[(2, 10), (26, 10)])),
            hh_spacing: Some(HhSpacingEvidence::HhhTile {
                tile: tile("sha-hhh", 50, 8, &[(2, 10), (16, 10), (30, 10)]),
                kern: zero_kern(),
            }),
            hsh_kern: Some(hsh_zero()),
            capture_shaping: Some(shaping()),
            scale: Some(scale()),
            sidebearing_policy: SidebearingPolicy::default(),
        }
    }

    #[test]
    fn hsh_kern_known_sum_subtracted_negative_allowed() {
        // G 14, SB 4, kern sum -2 -> space 14 - 4 + 2 = 12.
        let mut r = request();
        r.hsh_kern = Some(HsHKernEvidence::KnownSumPx { frame: Some(frame()), sum_px: -2.0, evidence_ref: "k".into() });
        assert_eq!(measure_space_advance(&r).unwrap().space_advance_px_slope, 12.0);
    }

    #[test]
    fn hsh_context_evidence_required() {
        let mut r = request();
        r.hsh_kern = Some(HsHKernEvidence::Unverified);
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
        let mut r = request();
        r.hsh_kern = None;
        assert!(matches!(
            measure_space_advance(&r),
            Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::HsHKern, .. })
        ));
        let mut r = request();
        r.capture_shaping = None;
        assert!(matches!(
            measure_space_advance(&r),
            Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::CaptureShaping, .. })
        ));
        let mut r = request();
        r.hsh_kern = Some(HsHKernEvidence::ZeroVerified { frame: None, evidence_ref: "x".into() });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::MissingFrameEvidence { .. })));
    }

    #[test]
    fn capture_shaping_conditions() {
        let mut r = request();
        r.capture_shaping.as_mut().unwrap().ligatures_disabled = false;
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
        let mut r = request();
        r.capture_shaping.as_mut().unwrap().letter_spacing_px = 0.5;
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
        let mut r = request();
        r.capture_shaping.as_mut().unwrap().covers_tile_sha256 = vec!["sha-hhh".into()];
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::UnverifiedHsHContext { .. })));
        let mut r = request();
        r.capture_shaping.as_mut().unwrap().covers_tile_sha256 = vec!["sha-hsh".into()];
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::UnverifiedHHSpacing { .. })));
        let mut r = request();
        r.capture_shaping.as_mut().unwrap().settings_ref = String::new();
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::EmptyField { .. })));
    }

    #[test]
    fn measures_with_zero_kern_evidence() {
        let m = measure_space_advance(&request()).unwrap();
        assert_eq!(m.hsh_gap_px, 14.0);
        assert_eq!(m.rsb_plus_lsb_px, 4.0);
        assert_eq!(m.space_advance_px_slope, 10.0);
        assert_eq!(m.space_advance_units, 20.0);
        assert_eq!(m.hhh_gaps_px, vec![4, 4]);
        assert_eq!(m.module, MODULE_ID);
    }

    #[test]
    fn known_kern_is_subtracted() {
        // gaps 4 = rsb+lsb+k with k = 1 -> sb sum 3 -> space 11.
        let mut r = request();
        if let Some(HhSpacingEvidence::HhhTile { kern, .. }) = r.hh_spacing.as_mut() {
            *kern = HhKernEvidence::KnownPx { frame: Some(frame()), kern_px: 1.0, evidence_ref: "k".into() };
        }
        let m = measure_space_advance(&r).unwrap();
        assert_eq!(m.rsb_plus_lsb_px, 3.0);
        assert_eq!(m.space_advance_px_slope, 11.0);
        assert_eq!(m.hh_kern_px, 1.0);
    }

    #[test]
    fn equal_gaps_without_kern_evidence_refused() {
        let mut r = request();
        if let Some(HhSpacingEvidence::HhhTile { kern, .. }) = r.hh_spacing.as_mut() {
            *kern = HhKernEvidence::Unverified;
        }
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::UnverifiedHHSpacing { .. })));
    }

    #[test]
    fn kern_evidence_needs_frame() {
        let mut r = request();
        if let Some(HhSpacingEvidence::HhhTile { kern, .. }) = r.hh_spacing.as_mut() {
            *kern = HhKernEvidence::ZeroVerified { frame: None, evidence_ref: "x".into() };
        }
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::MissingFrameEvidence { .. })));
    }

    #[test]
    fn explicit_sidebearings_bound_to_frame() {
        let mut r = request();
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: Some(frame()), lsb_px: 1.5, rsb_px: 2.5, evidence_ref: "ref".into(),
        });
        let m = measure_space_advance(&r).unwrap();
        assert_eq!(m.space_advance_px_slope, 10.0);
        assert_eq!(m.hhh_tile_sha256, "");
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: Some(SourceFrame { style_id: "other".into(), frame_id: "f1".into() }),
            lsb_px: 1.5, rsb_px: 2.5, evidence_ref: "ref".into(),
        });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::FrameMismatch { .. })));
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: None, lsb_px: 1.0, rsb_px: 1.0, evidence_ref: "ref".into(),
        });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::MissingFrameEvidence { .. })));
    }

    #[test]
    fn negative_sidebearing_policy_is_explicit() {
        let mut r = request();
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: Some(frame()), lsb_px: -1.0, rsb_px: 3.0, evidence_ref: "ref".into(),
        });
        // default allows: sum 2 -> space 12.
        assert_eq!(measure_space_advance(&r).unwrap().space_advance_px_slope, 12.0);
        r.sidebearing_policy = SidebearingPolicy::RequireNonNegative;
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::InvalidSidebearing { .. })));
    }

    #[test]
    fn non_finite_and_overflow_refused() {
        let mut r = request();
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: Some(frame()), lsb_px: f64::NAN, rsb_px: 1.0, evidence_ref: "r".into(),
        });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::InvalidSidebearing { .. })));
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: Some(frame()), lsb_px: f64::MAX, rsb_px: f64::MAX, evidence_ref: "r".into(),
        });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::NonFiniteResult { .. })));
        let mut r = request();
        r.scale = Some(ScaleEvidence { units_per_px: f64::MAX, ..scale() });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::NonFiniteResult { .. })));
    }

    #[test]
    fn scale_checks() {
        let mut r = request();
        r.scale = None;
        assert!(matches!(
            measure_space_advance(&r),
            Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::Scale, .. })
        ));
        r.scale = Some(ScaleEvidence { status: ScaleStatus::Unverified, ..scale() });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::ScaleNotPinnedConsistent { .. })));
        r.scale = Some(ScaleEvidence { style_id: "marq-alternate".into(), ..scale() });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::ScaleStyleMismatch { .. })));
        r.scale = Some(ScaleEvidence { evidence_ref: " ".into(), ..scale() });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::EmptyField { .. })));
        r.scale = Some(ScaleEvidence { units_per_px: 0.0, ..scale() });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::InvalidScale { .. })));
    }

    #[test]
    fn missing_tile_and_hh_spacing_typed() {
        let mut r = request();
        r.hsh_tile = None;
        assert!(matches!(
            measure_space_advance(&r),
            Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::HshTile, .. })
        ));
        let mut r = request();
        r.hh_spacing = None;
        assert!(matches!(
            measure_space_advance(&r),
            Err(SpaceError::MissingSpaceEvidence { missing: MissingKind::HhSpacing, .. })
        ));
    }

    #[test]
    fn tile_frame_and_identity_required() {
        let mut r = request();
        r.hsh_tile.as_mut().unwrap().frame = None;
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::MissingFrameEvidence { .. })));
        let mut r = request();
        r.hsh_tile.as_mut().unwrap().glyph_identity_ref = String::new();
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::EmptyField { .. })));
        let mut r = request();
        r.hsh_tile.as_mut().unwrap().source_sha256 = String::new();
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::EmptyField { .. })));
    }

    #[test]
    fn bad_image_dimensions_do_not_panic() {
        let mut r = request();
        let t = r.hsh_tile.as_mut().unwrap();
        t.image.px.truncate(5); // len disagrees with width*height
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::BadImage { .. })));
        let mut r = request();
        let t = r.hsh_tile.as_mut().unwrap();
        t.image.width = u32::MAX;
        t.image.height = u32::MAX;
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::BadImage { .. })));
    }

    #[test]
    fn cluster_count_and_empty_tile() {
        // Replacement tiles reuse "sha-hsh" so the shaping record covers them and
        // the cluster check (which runs after the coverage check) is reached.
        let mut r = request();
        r.hsh_tile = Some(tile("sha-hsh", 60, 8, &[(2, 10), (20, 10), (40, 10)]));
        assert!(matches!(
            measure_space_advance(&r),
            Err(SpaceError::UnexpectedClusterCount { expected: 2, found: 3, .. })
        ));
        r.hsh_tile = Some(tile("sha-hsh", 20, 4, &[]));
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::EmptyTile { .. })));
    }

    #[test]
    fn negative_space_reported_not_clamped() {
        let mut r = request();
        r.hh_spacing = Some(HhSpacingEvidence::Explicit {
            frame: Some(frame()), lsb_px: 10.0, rsb_px: 10.0, evidence_ref: "r".into(),
        });
        assert!(matches!(measure_space_advance(&r), Err(SpaceError::NegativeSpace { .. })));
    }

    #[test]
    fn outcome_has_no_fallback() {
        let mut r = request();
        r.scale = None;
        let o = SpaceOutcome::from_request(&r);
        assert!(o.emitted_advance_units().is_err());
        let o = SpaceOutcome::from_request(&request());
        assert_eq!(o.emitted_advance_units().unwrap(), 20.0);
    }

    #[test]
    fn ledger_row_escapes_and_matches_header() {
        let mut r = request();
        r.hsh_tile.as_mut().unwrap().glyph_identity_ref = "a\tb\nc".into();
        let m = measure_space_advance(&r).unwrap();
        let row = m.ledger_row();
        assert!(!row.contains('\n'));
        assert_eq!(row.split('\t').count(), LEDGER_HEADER.split('\t').count());
        assert!(row.contains("a\\tb\\nc"));
        assert_eq!(tsv_escape("x\\y"), "x\\\\y");
    }

    #[test]
    fn scale_proof_refuses_each_inconsistency() {
        let f = frame();
        let mut g = frame();
        g.frame_id = "other".into();
        let t = vec!["t".to_string()];
        assert!(ScaleConsistencyProof::check("a", "a", &f, &f, 2.0, 2.0, "t", &t).is_ok());
        assert!(matches!(ScaleConsistencyProof::check("a", "b", &f, &f, 2.0, 2.0, "t", &t), Err(ScaleProofError::ShaPinMismatch { .. })));
        assert!(matches!(ScaleConsistencyProof::check("a", "a", &g, &f, 2.0, 2.0, "t", &t), Err(ScaleProofError::FrameMismatch { .. })));
        assert!(matches!(ScaleConsistencyProof::check("a", "a", &f, &f, 2.0, 3.0, "t", &t), Err(ScaleProofError::UnitsMismatch { .. })));
        assert!(matches!(ScaleConsistencyProof::check("a", "a", &f, &f, 2.0, 2.0, "x", &t), Err(ScaleProofError::SourceNotLoadedTile)));
    }

}
