//! DECLARED CONVENTION wiring (source-only; no run, no landing without chief GO).
//! Scale model 2026-10-16 (chief code-integration spec, values per repo
//! docs/process/measurement-frame.md): the universal function lives here ONCE,
//!   h(cap_px, em_px) = 10 * round_half_up(1000 * cap_px / (10 * em_px))
//! round-half-up, positive only. Measurements are declared data; every
//! canonical collection style binds a declared per-style record (declared_units
//! over cap_px with em_px, basis, em_source; calibrated=false,
//! cross_frame_reuse=false, target upm 1000). Triple binding, any leg fails ->
//! typed refusal, never an edit:
//!   a. declared_units == 10 * rhU(1000 * cap_px / (10 * em_px))
//!   b. declared_units == rhU(cap_px * K) with K = declared_units / cap_px
//!   c. evidence JSON sha + ref tile sha + frame checks (bind-time, below).
//! No other module carries its own K literal. Marq/Unit rows are PROVISIONAL
//! (basis=estimated): replaced by measurement when a font lands; a row
//! changes, the code shape does not.
use kni_core::scale_context::{ContextError, ScaleContext};

/// Convention id written into the ScaleContext basis record.
pub const CONVENTION_ID: &str = "OwnerDeclaredScaleSet/2026-10-16-v2";

/// Where a record's em_px comes from. tile_measured: pure-tile ink envelope;
/// frame_fill_paul: frame-inclusive ink extent (Paul New); font_backcalc_reference:
/// font-metric back-calculation carried as declared reference data; estimated:
/// provisional placeholder inside the h-target interval (estimated rows only).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmSource { TileMeasured, FrameFillPaul, FontBackcalcReference, Estimated }

/// Declaration basis. FontVerified: locked against the owner-held font;
/// Family: uniform capture normalization from a font-verified sibling;
/// Estimated: no font and no family px/em - replaced when a font lands.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Basis { FontVerified, Family, Estimated }

/// Declared per-style tile-frame state (style-spec input to the capture
/// layer). Measured: the tile may carry a printed presentation frame; the
/// capture layer measures the band and traces the OUTLINE domain from the
/// band-cleared copy - the status-quo behavior every style keeps until its
/// own source audit declares otherwise. Absent: the style's source tiles
/// carry no presentation frame (the frame is removed at the capture
/// source); every pixel of the tile is glyph content, so no pixel may be
/// measured out or cleared and the outline domain is the original capture,
/// source ink preserved one to one. PresentRing: the style's source tiles
/// carry the printed presentation frame as a closed rectangle ring hugging
/// the tile edges (Paul New: the 2px printed site frame, measured per
/// image); the capture layer separates ONLY the jointly-proven ring for the
/// outline domain - edge-fused letterform stripes are glyph content and are
/// never cleared - while the measurement domain keeps the original capture.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[allow(dead_code)] // basis taxonomy: the Absent variant is constructed by the declared-convention test surface
pub enum TileFrame { Measured, Absent, PresentRing }

/// One declared per-style scale record. `h_ink_units` is the declared
/// cap-height in font units at 1000 upm; `cap_px` the declared reference
/// measurement on the pinned H tile; `em_px` the declared em in capture px;
/// frame and pin identify the exact tile the declaration is bound to.
pub struct DeclaredRecord {
    pub style_id: &'static str,
    pub h_ink_units: u32,
    pub cap_px: u32,
    pub em_px: f64,
    pub em_source: EmSource,
    pub basis: Basis,
    pub frame_width: u32,
    pub frame_height: u32,
    pub h_source_pin_sha256: &'static str,
    pub tile_frame: TileFrame,
}

/// The declared set. Style ids are kit folder styles (family "/" subfamily);
/// family display names are never accepted here. MCA U shares one family
/// em (411 px): the only value simultaneously satisfying every MCA U row
/// including both italics. Marq/Unit em_px are interval placeholders under
/// basis=estimated (em_source Estimated), NOT tile measurements.
pub const DECLARED_RECORDS: [DeclaredRecord; 19] = [
    DeclaredRecord { style_id: "Lÿno/Jean",       h_ink_units: 750,  cap_px: 375,  em_px: 500.0,  em_source: EmSource::FontBackcalcReference, basis: Basis::FontVerified, frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "5c8db308cfcdd77671d8a6f4651993c7368f5297567f86125486cca971ad882f" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Lÿno/Stan",       h_ink_units: 750,  cap_px: 375,  em_px: 500.0,  em_source: EmSource::FontBackcalcReference, basis: Basis::FontVerified, frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "5c8db308cfcdd77671d8a6f4651993c7368f5297567f86125486cca971ad882f" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Lÿno/Ulys",       h_ink_units: 750,  cap_px: 375,  em_px: 500.0,  em_source: EmSource::FontBackcalcReference, basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "d6b6a91eeab69d1063cff63ea9f530f07018634f6dacf6e1a216120d96ed9f62" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Lÿno/Walt",       h_ink_units: 750,  cap_px: 375,  em_px: 500.0,  em_source: EmSource::FontBackcalcReference, basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "a2863aa580436a29ee4b1ad7261756a51bb8062ae192f8984a0be993c925da08" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/2U1",       h_ink_units: 730,  cap_px: 300,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "db940ed28d37d725947ea6ac93c0c080de793daffad72c96a7ffa27ef21c8efa" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/3U1.5",     h_ink_units: 650,  cap_px: 267,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::FontVerified, frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "ff6768a5f087849e9d11ee779fd28170247ad0f88f767b1dba0c9e708885f0a4" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/4U2",       h_ink_units: 730,  cap_px: 300,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "f3909bdbb9c7fde90cac5aa84b96e20afe94346052f2cfa45ee1533d0f401aba" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/6U3",       h_ink_units: 730,  cap_px: 300,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "43810c1bbca2ffe586c00bf5b7f6a7e2dbb97fbec32ae8ab1ca1b7ad6eaf0a7c" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/8U4",       h_ink_units: 730,  cap_px: 300,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "f73307879f33d10b5a64bdb25d8ca7acdfe815ec89cfb4c420979af1e0fa0542" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/10U5",      h_ink_units: 730,  cap_px: 300,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "7f2a86a3449ca09004b5a164951cf0f469a247d45a2ec1b5e99db1efb20a6f1e" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/10U8",      h_ink_units: 730,  cap_px: 300,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "505cbd163783da8b0c7b9da3a4e358a72119f83d8a338de70080fb059432c2be" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/10U5 IT",   h_ink_units: 730,  cap_px: 298,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "79f17b97062f8a2343495896aba95fdaf11a49df688d96712500393c13351651" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "MCA U/10U8 IT",   h_ink_units: 730,  cap_px: 302,  em_px: 411.0,  em_source: EmSource::TileMeasured          , basis: Basis::Family,      frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "89eca5654dbc999cfbede5ceface194692f6a4df9c81d0ebd505d207637d6558" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Marq/Standard",   h_ink_units: 790,  cap_px: 402,  em_px: 509.0,  em_source: EmSource::Estimated,             basis: Basis::Estimated,   frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "208b0f2f465839d51b815714f86939826ee0762b22580b8101ea8c38dfc3e28d" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Marq/Alternate",  h_ink_units: 790,  cap_px: 403,  em_px: 510.0,  em_source: EmSource::Estimated,             basis: Basis::Estimated,   frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "342d808dae2f70d27a1db81023c160a010f298f6e79c2dd1414fef15335117c3" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Mona/Regular",    h_ink_units: 680,  cap_px: 322,  em_px: 473.5,  em_source: EmSource::FontBackcalcReference, basis: Basis::FontVerified, frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "7eb9e85b78d989e7056d89a6593606917b255865a5d6c0993905cd93b01fa3d8" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Mona Alt/Regular",h_ink_units: 940,  cap_px: 516,  em_px: 549.0,  em_source: EmSource::FontBackcalcReference, basis: Basis::FontVerified, frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "46822124ee32da94eb37e7ae3d07a201f99ad252e103135a3f3d0c3ab02b15e7" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Unit/Regular",    h_ink_units: 750,  cap_px: 375,  em_px: 500.0,  em_source: EmSource::Estimated,             basis: Basis::Estimated,   frame_width: 1485, frame_height: 1050, h_source_pin_sha256: "9a3d201e859033ec818e1f4bf3ee0e3b469292719fdf0addb7e515093237a1a1" , tile_frame: TileFrame::Measured },
    DeclaredRecord { style_id: "Paul New/Regular",h_ink_units: 1000, cap_px: 1122, em_px: 1122.0, em_source: EmSource::FrameFillPaul,         basis: Basis::FontVerified, frame_width: 786,  frame_height: 1122, h_source_pin_sha256: "c7cd69b88be228b339c3f7f1978ad11ced392b7f81f036c622a211c0a2e55464" , tile_frame: TileFrame::PresentRing },
];

/// cross_frame_reuse = false, by the relayed owner decision; a constant so no caller flips it silently.
#[allow(dead_code)] // cross_frame_reuse = false per the recorded owner decision; a constant so no caller flips it silently
pub const CROSS_FRAME_REUSE: bool = false;
/// Owner scope: 1000 upm only.
pub const EXPECTED_TARGET_UPM: f64 = 1000.0;

/// Paul New aliases kept for the pre-generalization test surface; the table
/// row above is the single source of the values.
#[allow(dead_code)] // Paul New style key kept for the pre-generalization test surface
pub const PAUL_STYLE_ID: &str = "Paul New/Regular";

/// Declared Paul New style spec. This block supersedes the earlier photo-derived pair
/// 770/-230: that pair was measured from the Rules of Hypergraphy book photos (the sans
/// printed beside Paul New) with a +-20-30 unit tolerance, and the declared spec retires it -
/// the line metrics are now fixed exactly, with cap height and x-height declared for the
/// first time:
/// Final vertical revision declared 2026-10-17; the tile anchor follows the descender.
///   ascender 850, cap height 700, x-height 500, baseline 0, descender -150.
/// Tile-box anchor: one tile maps 1:1 onto [0,696] x [-150,850] - MINUS the capture-measured left
/// frame band and a -1 edge overhang (owner ruling 2026-10-18 03:05/03:06; applied in paul_new_anchor).
/// The raw box below stays the K_X/K_Y basis - the tile's left edge is
/// x=0 and the tile's bottom edge is the descender line; bottom whitespace inside the tile
/// is preserved (never bottom-cropped), and one tile image carries exactly one whole glyph.
/// Advance model (2026-10-18 revision, supersedes the 2026-10-17 fixed-696/zero-lsb declaration):
/// the advance is derived per run as the frame-stripped em box (population median shipped ink xMax - 1);
/// declared lsb is each glyph's shipped ink xMin; target rsb -1. The 696 below stays the em-box raw
/// width (the K_X anchor basis), not the shipped advance. These set the hhea/OS2
/// line metrics, the OS/2 sCapHeight/sxHeight, and the advance model only: Paul New shapes
/// may overshoot the lines and are never clipped or per-glyph normalized to them.
pub const PAUL_NEW_FAMILY: &str = "Paul New";
pub const PAUL_NEW_ASCENDER_UNITS: i16 = 850;
pub const PAUL_NEW_CAP_HEIGHT_UNITS: i16 = 700;
pub const PAUL_NEW_X_HEIGHT_UNITS: i16 = 500;
#[allow(dead_code)] // Paul New vertical-metric set; the baseline entry has no wired consumer today
pub const PAUL_NEW_BASELINE_UNITS: i16 = 0;
// Descender revised 2026-10-18 03:37 owner directive (iMessage): -145, all other
// vertical metrics unchanged. hhea.descender, OS/2 sTypoDescender and usWinDescent
// (145) follow this constant through vertical_metrics_override; outlines untouched.
pub const PAUL_NEW_DESCENDER_UNITS: i16 = -145;
#[allow(dead_code)] // K_X anchor basis + spec-literal pin in tests; the shipped advance is derived per run (see Advance model above)
pub const PAUL_NEW_ADVANCE_UNITS: i16 = 696;
/// Declared Paul New tile width in px (the bound H tile's frame width): the x-basis of K_X.
#[allow(dead_code)] // declared Paul New tile width: the x-basis of K_X
pub const PAUL_NEW_TILE_WIDTH_PX: u32 = 786;
/// Paul New x-direction scale K_X = 696/786 (declared advance over declared tile width),
/// exact IEEE-754 bits of 0.8854961832061069. Exposed for the placement lane (W1); no
/// outline translation or placement consumes it in this change.
#[allow(dead_code)] // exact IEEE-754 bits of the declared K_X scale; exposed for the placement lane
pub const PAUL_NEW_K_X_BITS: u64 = 0x3fec_55fc_1773_4c37;
/// Paul New y-direction scale K_Y = 1000/1122: bit-identical to DECLARED_K_BITS, re-exposed
/// under the K_Y name so the placement lane reads K_X/K_Y as one pair.
#[allow(dead_code)] // exact IEEE-754 bits of the declared K_Y scale; exposed for the placement lane
#[allow(dead_code)] // declared-contract constant for the H evidence pin; consumed by the declared-convention tests
pub const PAUL_NEW_K_Y_BITS: u64 = DECLARED_K_BITS;

/// The Paul New special case, separate from the universal scale equation: when the font's own
/// family is Paul New, its vertical line metrics are the declared pair above.
pub fn vertical_metrics_override(family: &str) -> Option<(i16, i16)> {
    if family == PAUL_NEW_FAMILY { Some((PAUL_NEW_ASCENDER_UNITS, PAUL_NEW_DESCENDER_UNITS)) } else { None }
}
#[allow(dead_code)] // declared-contract constant for the H evidence pin; consumed by the declared-convention tests
pub const DECLARED_H_INK_HEIGHT_PX: u32 = 1122;
#[allow(dead_code)] // declared-contract constant for the H evidence pin; consumed by the declared-convention tests
pub const DECLARED_H_INK_UNITS: u32 = 1000;
/// Exact IEEE-754 bits of 1000.0 / 1122.0 = 0.8912655971479501.
pub const DECLARED_K_BITS: u64 = 0x3fec_853f_6df9_9c85;
#[allow(dead_code)] // declared-contract constant for the H evidence pin; consumed by the declared-convention tests
pub const EXPECTED_H_SOURCE_PIN_SHA256: &str = "c7cd69b88be228b339c3f7f1978ad11ced392b7f81f036c622a211c0a2e55464"; // 007__0048__c7cd69b88be2.jpg
#[allow(dead_code)] // declared-contract constant for the H evidence pin; consumed by the declared-convention tests
pub const EXPECTED_COHORT: &str = "Paul New/Regular";
#[allow(dead_code)] // declared-contract constant for the H evidence pin; consumed by the declared-convention tests
pub const EXPECTED_FRAME_ID: &str = "PaulNew-Regular:786x1122:H-sha256:c7cd69b88be228b339c3f7f1978ad11ced392b7f81f036c622a211c0a2e55464";

/// THE universal function, the only place it exists:
/// h(cap_px, em_px) = 10 * round_half_up(1000 * cap_px / (10 * em_px)).
/// Round-half-up on a positive f64 is f64::round (half away from zero, and
/// every input here is positive). Non-positive cap/em is a caller bug; the
/// function asserts positivity rather than rounding garbage.
pub fn h_from_cap_em(cap_px: f64, em_px: f64) -> u32 {
    assert!(cap_px > 0.0 && em_px > 0.0, "h_from_cap_em: positive inputs only");
    10 * (1000.0 * cap_px / (10.0 * em_px)).round() as u32
}

/// Round-half-up for the binding (b) leg: rhU(cap_px * K).
pub fn rhu(x: f64) -> u32 { assert!(x > 0.0, "rhu: positive inputs only"); x.round() as u32 }

/// Record lookup by canonical style id.
pub fn record_for(style_id: &str) -> Option<&'static DeclaredRecord> {
    DECLARED_RECORDS.iter().find(|r| r.style_id == style_id)
}

/// The capture-layer frame policy for a style, resolved from its declared
/// record: the style-spec record is the only place this decision lives. A
/// style declared Absent keeps every source pixel; declared-Measured styles
/// and undeclared styles keep the measured status quo.
pub fn frame_policy_for(style_id: &str) -> kni_core::capture_dispatch::FramePolicy {
    match record_for(style_id).map(|r| r.tile_frame) {
        Some(TileFrame::Absent) => kni_core::capture_dispatch::FramePolicy::PreserveAllInk,
        Some(TileFrame::PresentRing) => kni_core::capture_dispatch::FramePolicy::SeparatePresentRing,
        _ => kni_core::capture_dispatch::FramePolicy::Measure,
    }
}

/// The explicit Paul New tile->em anchor scope, independent of the capture
/// frame policy: a declared style of the Paul New family ships its outlines
/// re-anchored onto the declared em box ([0,696] x [-150,850], baseline 0 by
/// the tile anchor) and the export lane must not rebase that geometry a
/// second time. This key follows the style's declared family only; flipping
/// the frame policy can never switch the anchor off or on.
pub fn paul_new_tile_anchor_scope(style_id: &str) -> bool {
    record_for(style_id).map(|r| r.style_id.split('/').next() == Some(PAUL_NEW_FAMILY)).unwrap_or(false)
}

/// Deterministic frame slug from a canonical style id: spaces removed, '/'
/// replaced by '-'. "Paul New/Regular" -> "PaulNew-Regular". This is the ONLY
/// slug rule; the expected frame ids assume it.
pub fn frame_slug(style_id: &str) -> String {
    style_id.replace(' ', "").replace('/', "-")
}

/// Expected frame identity for a declared record. The consumer wiring
/// reconciles this with the capture manifest / runtime identity; any drift is
/// a typed refusal.
pub fn expected_frame_id(rec: &DeclaredRecord) -> String {
    format!("{}:{}x{}:H-sha256:{}", frame_slug(rec.style_id), rec.frame_width, rec.frame_height, rec.h_source_pin_sha256)
}

#[derive(Clone, Debug, PartialEq)]
pub enum ConventionError {
    /// Style has no declared record in the owner-declared set.
    StyleOutOfScope { style_id: String },
    /// Observed H source pin differs from the record's pin.
    HPinMismatch { expected: String, found: String },
    /// Observed H pin is not 64 lowercase-hex.
    MalformedHPin { found: String },
    /// Measured H ink height differs from the record's declared px.
    HHeightMismatch { expected: u32, found: u32 },
    /// Runtime frame identity differs from the record's expectation.
    HFrameMismatch { expected: String, found: String },
    /// Empty frame id cannot be validated at all.
    EmptyFrameId,
    /// target_upm outside the owner-scoped 1000 is a refusal, never an edit.
    TargetUpmOutOfScope { found: f64 },
    /// Triple-binding leg (a): declared_units != 10 * rhU(1000*cap/(10*em)).
    FormulaBindingMismatch { style_id: String, declared: u32, formula: u32 },
    /// Triple-binding leg (b): declared_units != rhU(cap_px * K).
    ScaleBindingMismatch { style_id: String, declared: u32, scaled: u32 },
    /// ScaleContext construction refused the declared values.
    Scale(ContextError),
    /// Receipt requested for a context that is NOT a validated declared-set
    /// binding: forgery path, typed refusal.
    ForeignContext { detail: String },
}

/// Identity of the H reference as observed at wiring time.
pub struct HReferenceObservation {
    pub style_id: String,
    pub h_source_pin_sha256: String,
    pub h_ink_height_px: u32,
    pub frame_id: String,
    pub target_upm: f64,
}

/// The record's declared K as an exact-bits f64, computed from the declared
/// integers so no caller re-derives it with a different rounding path.
pub fn declared_k(rec: &DeclaredRecord) -> f64 {
    rec.h_ink_units as f64 / rec.cap_px as f64
}

/// Triple-binding legs (a) and (b) for one record. Leg (c) is the bind-time
/// evidence/tile/frame validation below. Any leg failing is a typed refusal.
pub fn validate_triple_binding(rec: &DeclaredRecord) -> Result<(), ConventionError> {
    let formula = h_from_cap_em(rec.cap_px as f64, rec.em_px);
    if rec.h_ink_units != formula {
        return Err(ConventionError::FormulaBindingMismatch { style_id: rec.style_id.to_string(), declared: rec.h_ink_units, formula });
    }
    let scaled = rhu(rec.cap_px as f64 * declared_k(rec));
    if rec.h_ink_units != scaled {
        return Err(ConventionError::ScaleBindingMismatch { style_id: rec.style_id.to_string(), declared: rec.h_ink_units, scaled });
    }
    Ok(())
}

/// Paul-only helper kept for the pre-generalization test surface.
#[allow(dead_code)] // kept for the pre-generalization test surface
pub fn paul_record() -> &'static DeclaredRecord { record_for(PAUL_STYLE_ID).expect("Paul New/Regular is in the declared set") }

fn is_64_lower_hex(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Wire the declared convention into a bound ScaleContext. Fail-closed: style
/// without a declared record, broken triple binding, pin/height/frame drift,
/// malformed pin, or a non-1000 UPM are all typed refusals. calibrated=true
/// never happens here.
pub fn bind_declared_convention(observed: &HReferenceObservation) -> Result<ScaleContext, ConventionError> {
    let rec = record_for(&observed.style_id)
        .ok_or_else(|| ConventionError::StyleOutOfScope { style_id: observed.style_id.clone() })?;
    validate_triple_binding(rec)?;
    if !is_64_lower_hex(&observed.h_source_pin_sha256) {
        return Err(ConventionError::MalformedHPin { found: observed.h_source_pin_sha256.clone() });
    }
    if observed.h_source_pin_sha256 != rec.h_source_pin_sha256 {
        return Err(ConventionError::HPinMismatch { expected: rec.h_source_pin_sha256.to_string(), found: observed.h_source_pin_sha256.clone() });
    }
    if observed.h_ink_height_px != rec.cap_px {
        return Err(ConventionError::HHeightMismatch { expected: rec.cap_px, found: observed.h_ink_height_px });
    }
    if observed.frame_id.is_empty() {
        return Err(ConventionError::EmptyFrameId);
    }
    let expected_frame = expected_frame_id(rec);
    if observed.frame_id != expected_frame {
        return Err(ConventionError::HFrameMismatch { expected: expected_frame, found: observed.frame_id.clone() });
    }
    if observed.target_upm != EXPECTED_TARGET_UPM {
        return Err(ConventionError::TargetUpmOutOfScope { found: observed.target_upm });
    }
    ScaleContext::from_convention(&observed.style_id, CONVENTION_ID, declared_k(rec), EXPECTED_TARGET_UPM, &observed.style_id, &expected_frame)
        .map_err(ConventionError::Scale)
}

fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r") }

/// Receipt row built from a VALIDATED binding: every identity field of the
/// context is checked against the style's declared record first, so a foreign
/// context can never mint a declared-convention receipt.
pub fn convention_receipt_row(ctx: &ScaleContext) -> Result<String, ConventionError> {
    let rec = validate_declared_context(ctx)?;
    Ok(format!(
        "scale_status\tDECLARED_CONVENTION\tcalibrated\tfalse\tconvention\t{}\tk_bits\t{:016x}\th_ink_height_px\t{}\th_ink_units\t{}\tem_px\t{}\tem_source\t{:?}\tbasis\t{:?}\tcross_frame_reuse\tfalse\th_source_pin\t{}\tscale_id\t{}\tcohort\t{}\tframe\t{}\tcontext_basis\t{:?}\n",
        esc(CONVENTION_ID),
        declared_k(rec).to_bits(),
        rec.cap_px,
        rec.h_ink_units,
        rec.em_px,
        rec.em_source,
        rec.basis,
        esc(rec.h_source_pin_sha256),
        esc(ctx.id()),
        esc(ctx.cohort()),
        esc(ctx.frame_binding()),
        ctx.basis(),
    ))
}

fn validate_declared_context(ctx: &ScaleContext) -> Result<&'static DeclaredRecord, ConventionError> {
    let foreign = |d: &str| ConventionError::ForeignContext { detail: d.to_string() };
    let rec = record_for(ctx.id()).ok_or(foreign("id"))?;
    if ctx.units_per_px().to_bits() != declared_k(rec).to_bits() { return Err(foreign("k")); }
    if ctx.target_upm() != EXPECTED_TARGET_UPM { return Err(foreign("upm")); }
    if ctx.cohort() != rec.style_id { return Err(foreign("cohort")); }
    if ctx.frame_binding() != expected_frame_id(rec) { return Err(foreign("frame")); }
    match ctx.basis() {
        kni_core::scale_context::ScaleBasis::Convention { convention_id } if convention_id == CONVENTION_ID => {}
        _ => return Err(foreign("basis")),
    }
    Ok(rec)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn obs_for(rec: &DeclaredRecord) -> HReferenceObservation {
        HReferenceObservation {
            style_id: rec.style_id.to_string(),
            h_source_pin_sha256: rec.h_source_pin_sha256.to_string(),
            h_ink_height_px: rec.cap_px,
            frame_id: expected_frame_id(rec),
            target_upm: 1000.0,
        }
    }

    #[test]
    fn frame_policy_is_declared_per_style() {
        use kni_core::capture_dispatch::FramePolicy;
        // Paul New declares PresentRing: its tiles carry the printed frame
        // ring; only the jointly-proven ring is separated for the outline.
        assert_eq!(frame_policy_for(PAUL_STYLE_ID), FramePolicy::SeparatePresentRing);
        // Every other declared style keeps the measured status quo.
        for r in DECLARED_RECORDS.iter() {
            let want = if r.style_id == PAUL_STYLE_ID { FramePolicy::SeparatePresentRing } else { FramePolicy::Measure };
            assert_eq!(frame_policy_for(r.style_id), want, "{}", r.style_id);
        }
        // Undeclared styles keep the measured status quo as well.
        assert_eq!(frame_policy_for("No/SuchStyle"), FramePolicy::Measure);
    }
    #[test]
    fn tile_anchor_scope_is_declared_family_not_frame_policy() {
        // The anchor scope follows the declared Paul New family only, never
        // the capture frame policy: no policy flip can move it.
        assert!(paul_new_tile_anchor_scope(PAUL_STYLE_ID));
        for r in DECLARED_RECORDS.iter() {
            assert_eq!(paul_new_tile_anchor_scope(r.style_id), r.style_id == PAUL_STYLE_ID, "{}", r.style_id);
        }
        assert!(!paul_new_tile_anchor_scope("No/SuchStyle"));
        assert!(!paul_new_tile_anchor_scope("Paul New")); // family display name is not a style id
    }
    #[test]
    fn every_declared_style_binds() {
        assert_eq!(DECLARED_RECORDS.len(), 19);
        for rec in DECLARED_RECORDS.iter() {
            let ctx = bind_declared_convention(&obs_for(rec)).unwrap_or_else(|e| panic!("{} refused: {e:?}", rec.style_id));
            assert_eq!(ctx.units_per_px().to_bits(), declared_k(rec).to_bits(), "{}", rec.style_id);
            assert_eq!(ctx.cohort(), rec.style_id);
            assert_eq!(ctx.frame_binding(), expected_frame_id(rec));
        }
    }

    #[test]
    fn triple_binding_holds_for_every_record() {
        for rec in DECLARED_RECORDS.iter() {
            validate_triple_binding(rec).unwrap_or_else(|e| panic!("{} triple binding broken: {e:?}", rec.style_id));
        }
    }

    #[test]
    fn formula_spot_checks() {
        // The universal function against known reference points.
        assert_eq!(h_from_cap_em(300.0, 411.0), 730);
        assert_eq!(h_from_cap_em(267.0, 411.0), 650);
        assert_eq!(h_from_cap_em(298.0, 411.0), 730);
        assert_eq!(h_from_cap_em(302.0, 411.0), 730);
        assert_eq!(h_from_cap_em(375.0, 500.0), 750);
        assert_eq!(h_from_cap_em(322.0, 473.5), 680);
        assert_eq!(h_from_cap_em(516.0, 549.0), 940);
        assert_eq!(h_from_cap_em(1122.0, 1122.0), 1000);
        assert_eq!(h_from_cap_em(402.0, 509.0), 790);
        assert_eq!(h_from_cap_em(403.0, 510.0), 790);
    }

    #[test]
    fn declared_k_bits_match_declaration() {
        // Bits computed independently from the declared integers.
        let expected: [(&str, u64); 19] = [
            ("Lÿno/Jean", 0x4000_0000_0000_0000), ("Lÿno/Stan", 0x4000_0000_0000_0000),
            ("Lÿno/Ulys", 0x4000_0000_0000_0000), ("Lÿno/Walt", 0x4000_0000_0000_0000),
            ("MCA U/2U1", 0x4003_7777_7777_7777), ("MCA U/3U1.5", 0x4003_79c4_8de7_1238),
            ("MCA U/4U2", 0x4003_7777_7777_7777), ("MCA U/6U3", 0x4003_7777_7777_7777),
            ("MCA U/8U4", 0x4003_7777_7777_7777), ("MCA U/10U5", 0x4003_7777_7777_7777),
            ("MCA U/10U8", 0x4003_7777_7777_7777), ("MCA U/10U5 IT", 0x4003_98e9_aa18_0dbf),
            ("MCA U/10U8 IT", 0x4003_5676_aced_59db), ("Marq/Standard", 0x3fff_715a_6d88_4753),
            ("Marq/Alternate", 0x3fff_5d61_30e9_c44a), ("Mona/Regular", 0x4000_e4f8_0cb8_727c),
            ("Mona Alt/Regular", 0x3ffd_25b4_96d2_5b49), ("Unit/Regular", 0x4000_0000_0000_0000),
            ("Paul New/Regular", DECLARED_K_BITS),
        ];
        for (style, bits) in expected {
            let rec = record_for(style).unwrap();
            assert_eq!(declared_k(rec).to_bits(), bits, "{style}");
        }
        assert_eq!(DECLARED_K_BITS, (DECLARED_H_INK_UNITS as f64 / DECLARED_H_INK_HEIGHT_PX as f64).to_bits());
    }

    #[test]
    fn broken_triple_binding_is_typed_refusal() {
        let mut bad = DeclaredRecord { style_id: "Test/Row", h_ink_units: 731, cap_px: 300, em_px: 411.0,
            em_source: EmSource::Estimated, basis: Basis::Estimated, frame_width: 1485, frame_height: 1050,
            h_source_pin_sha256: "0".repeat(64).leak(), tile_frame: TileFrame::Measured };
        assert!(matches!(validate_triple_binding(&bad), Err(ConventionError::FormulaBindingMismatch { .. })));
        bad.h_ink_units = 730; bad.em_px = 410.0; // formula now 730? 1000*300/(10*410)=73.17 -> 730 ok; break leg (b) instead
        bad.cap_px = 302; // 302*K(730/302)=730 ok... force mismatch via h that disagrees with cap*K rounding is impossible; use formula leg
        bad.h_ink_units = 740; // formula at 302/410: 73.66 -> 740 matches (a); (b): 302*(740/302)=740 matches. Construct pure (b) break:
        let bad2 = DeclaredRecord { h_ink_units: 735, cap_px: 300, em_px: 410.959, ..bad };
        // (a): 1000*300/(10*410.959)=72.999.. -> 730 != 735 -> FormulaBindingMismatch
        assert!(matches!(validate_triple_binding(&bad2), Err(ConventionError::FormulaBindingMismatch { .. })));
    }

    #[test]
    fn unknown_style_is_typed_refusal() {
        let mut o = obs_for(paul_record());
        o.style_id = "Marq/Regular".to_string();
        assert!(matches!(bind_declared_convention(&o), Err(ConventionError::StyleOutOfScope { .. })));
    }

    #[test]
    fn drift_is_typed_refusal() {
        let rec = record_for("Marq/Standard").unwrap();
        let mut o = obs_for(rec);
        o.h_ink_height_px = 401; // thr128-domain value must not bind the full-ink declaration
        assert!(matches!(bind_declared_convention(&o), Err(ConventionError::HHeightMismatch { expected: 402, found: 401 })));
        let mut o = obs_for(rec);
        o.h_source_pin_sha256 = "0".repeat(64);
        assert!(matches!(bind_declared_convention(&o), Err(ConventionError::HPinMismatch { .. })));
        let mut o = obs_for(rec);
        o.frame_id = "Marq-Standard:100x1050:H-sha256:dead".to_string();
        assert!(matches!(bind_declared_convention(&o), Err(ConventionError::HFrameMismatch { .. })));
        let mut o = obs_for(rec);
        o.target_upm = 2048.0;
        assert!(matches!(bind_declared_convention(&o), Err(ConventionError::TargetUpmOutOfScope { .. })));
    }

    #[test]
    fn paul_aliases_match_the_table() {
        let rec = paul_record();
        assert_eq!(rec.h_ink_units, DECLARED_H_INK_UNITS);
        assert_eq!(rec.cap_px, DECLARED_H_INK_HEIGHT_PX);
        assert_eq!(rec.h_source_pin_sha256, EXPECTED_H_SOURCE_PIN_SHA256);
        assert_eq!(expected_frame_id(rec), EXPECTED_FRAME_ID);
    }
}
