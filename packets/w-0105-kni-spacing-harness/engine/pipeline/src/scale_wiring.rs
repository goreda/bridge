//! Source-only runtime scale adapter. No normalization or scale interpolation.
use kni_core::capture_dispatch::{decode_source, DispatchError};
use kni_core::capture::DecodeLimits;
use kni_core::jpeg_source::JpegError;
use crate::run_config::RunConfig;
use kni_core::cff_reader::sha256_hex;
use kni_core::jpeg_source::Limits;
use kni_core::scale_context::{ContextError, ScaleBasis, ScaleContext};
use crate::declared_convention::{
    bind_declared_convention, convention_receipt_row, record_for, ConventionError, HReferenceObservation,
    CONVENTION_ID,
};

/// The single config default multiplier for every style OUTSIDE the
/// declared set (OwnerDeclaredScaleSet/2026-10-16-v2); declared-set styles
/// never take it (owner-declared; exact f64 literal, no re-derivation path).
pub const CONFIG_K: f64 = RunConfig::default_units_per_px();
/// Convention id written into the ScaleContext basis record for the config path.
pub const CONFIG_CONVENTION_ID: &str = "ConfigDefaultScaleK/v1";

#[derive(Clone, Debug, PartialEq)]
pub enum WiringError {
    /// A required field (style id, cohort, frame binding) was empty.
    EmptyField { field: &'static str },
    /// target_upm not finite or not > 0.
    BadTargetUpm { found: f64 },
    /// Canonical Paul New style selected without an H observation: the
    /// declared convention can never bind from the config default.
    MissingHObservation { style_id: String },
    /// Declared-convention refusal (pin/height/frame/style/upm/foreign ctx).
    Convention(ConventionError),
    /// ScaleContext construction refused the config-convention values.
    Scale(ContextError),
    /// H source bytes failed signature dispatch / decode.
    Decode { reason: String },
    /// Receipt requested for a context whose basis is neither the declared
    /// Paul New convention nor the config default convention.
    ForeignBasis { detail: String },
    /// Integration-point guard: a manifest per-glyph scale override reached
    /// the wired path. One style = one immutable K; overrides are refused.
    PerGlyphScaleOverride { glyph: String },
    OuterConflict { field: &'static str, expected: String, found: String },
    ManifestScaleMismatch { expected_bits: u64, found_bits: u64 },
    MissingHRow,
    DuplicateHRow,
    ReadH { reason: String },
    HSourceChanged { expected: String, found: String },
    UnsupportedMode,
}

/// Only this module can mint a receipt-capable binding. A raw ScaleContext is
/// not evidence that the runtime guard accepted it.
#[derive(Debug)]
pub struct BoundRunScale { ctx: ScaleContext }
impl BoundRunScale {
    pub fn context(&self) -> &ScaleContext { &self.ctx }
    pub fn into_context(self) -> ScaleContext { self.ctx }
}
impl std::ops::Deref for BoundRunScale {
    type Target = ScaleContext;
    fn deref(&self) -> &ScaleContext { &self.ctx }
}

pub fn reject_glyph_override(glyph: &str, scale: Option<f64>) -> Result<(), WiringError> {
    if scale.is_some() { return Err(WiringError::PerGlyphScaleOverride { glyph: glyph.into() }); }
    Ok(())
}
pub fn check_manifest_scale(scale: f64, ctx: &ScaleContext) -> Result<(), WiringError> {
    if scale.to_bits() != ctx.units_per_px().to_bits() {
        return Err(WiringError::ManifestScaleMismatch { expected_bits: ctx.units_per_px().to_bits(), found_bits: scale.to_bits() });
    }
    Ok(())
}

/// Canonical style id from manifest family/subfamily ("Paul New" + "Regular"
/// -> "Paul New/Regular"). Empty parts are a typed refusal.
pub fn style_id_of(family: &str, subfamily: &str) -> Result<String, WiringError> {
    if family.is_empty() { return Err(WiringError::EmptyField { field: "family" }); }
    if subfamily.is_empty() { return Err(WiringError::EmptyField { field: "subfamily" }); }
    Ok(format!("{family}/{subfamily}"))
}

/// Deterministic frame slug from a canonical style id: spaces removed, '/'
/// replaced by '-'. "Paul New/Regular" -> "PaulNew-Regular". This is the ONLY
/// slug rule; the expected frame id in declared_convention assumes it.
pub fn frame_slug(style_id: &str) -> String {
    crate::declared_convention::frame_slug(style_id)
}

/// Inked-row span of a decoded gray raster at the full-ink level (any pixel
/// darker than paper white, gray < 255). The declared per-style reference
/// heights are full-ink pixel-scan measurements: identical to the thr128 rule
/// on hard-edged tiles, and the only rule consistent across the whole
/// declared set (soft-edged Marq/Standard H: 402 full-ink vs 401 thr128; the
/// declaration binds 402). Returns (first_row, last_row, height). No
/// normalize, no clamp: the caller compares against declared expectations
/// and refuses on mismatch.
pub fn measure_ink_rows(gray: &[u8], width: usize, height: usize) -> Option<(u32, u32, u32)> {
    if gray.len() != width.saturating_mul(height) || width == 0 || height == 0 { return None; }
    let mut first: Option<u32> = None;
    let mut last: u32 = 0;
    for y in 0..height {
        let row = &gray[y * width..(y + 1) * width];
        if row.iter().any(|&g| g < 255) {
            if first.is_none() { first = Some(y as u32); }
            last = y as u32;
        }
    }
    first.map(|f| (f, last, last - f + 1))
}

/// Build the runtime H reference observation from the ACTUAL H source bytes
/// selected by the capture manifest's H row (codepoint 0x48). Pin = real
/// SHA-256 of the file bytes; dimensions = decoded raster dimensions; ink
/// height = measured inked-row span; frame id = constructed from slug + real
/// dimensions + real pin. Nothing is trusted from a hardcoded frame string;
/// bind_declared_convention refuses any drift from the pinned expectation.
pub fn observe_h_reference(
    style_id: &str,
    h_bytes: &[u8],
    png_limits: &DecodeLimits,
    jpeg_limits: Limits,
    target_upm: f64,
) -> Result<HReferenceObservation, WiringError> {
    let pin = sha256_hex(h_bytes);
    let decoded = decode_source(h_bytes, png_limits, jpeg_limits)
        .map_err(|e| match e {
            DispatchError::Jpeg(JpegError::UnsupportedMode) => WiringError::UnsupportedMode,
            other => WiringError::Decode { reason: format!("{other:?}") },
        })?;
    let (_first, _last, ink_height) = measure_ink_rows(&decoded.gray, decoded.width, decoded.height)
        .ok_or_else(|| WiringError::Decode { reason: "H source has no inked row at iso 0.5".to_string() })?;
    Ok(HReferenceObservation {
        style_id: style_id.to_string(),
        h_source_pin_sha256: pin.clone(),
        h_ink_height_px: ink_height,
        frame_id: format!("{}:{}x{}:H-sha256:{}", frame_slug(style_id), decoded.width, decoded.height, pin),
        target_upm,
    })
}

/// Bind the ONE immutable ScaleContext for a style/run. Every style in the
/// declared set (OwnerDeclaredScaleSet/2026-10-16-v2, 19 records) goes only
/// through the declared convention (H observation REQUIRED; the config
/// default can never mint a declared-set binding). Every style outside the
/// declared set binds the config default K = 2.4377 as a config convention
/// (calibrated never set).
/// No interpolation, no per-glyph override, same K for glyph/mark/space/
/// notdef/class.
pub fn bind_run_scale(
    style_id: &str,
    h_observation: Option<&HReferenceObservation>,
    cohort: &str,
    frame_binding: &str,
    target_upm: f64,
) -> Result<BoundRunScale, WiringError> {
    if style_id.is_empty() { return Err(WiringError::EmptyField { field: "style_id" }); }
    if !target_upm.is_finite() || target_upm <= 0.0 { return Err(WiringError::BadTargetUpm { found: target_upm }); }
    if cohort.is_empty() { return Err(WiringError::EmptyField { field: "cohort" }); }
    if frame_binding.is_empty() { return Err(WiringError::EmptyField { field: "frame_binding" }); }
    if cohort != style_id {
        return Err(WiringError::OuterConflict { field: "cohort", expected: style_id.into(), found: cohort.into() });
    }
    if let Some(obs) = h_observation {
        for (field, expected, found) in [("style_id", obs.style_id.as_str(), style_id), ("frame_binding", obs.frame_id.as_str(), frame_binding)] {
            if expected != found { return Err(WiringError::OuterConflict { field, expected: expected.into(), found: found.into() }); }
        }
        if target_upm.to_bits() != obs.target_upm.to_bits() {
            return Err(WiringError::OuterConflict { field: "target_upm", expected: obs.target_upm.to_string(), found: target_upm.to_string() });
        }
    }
    let ctx = if record_for(style_id).is_some() {
        let obs = h_observation.ok_or_else(|| WiringError::MissingHObservation { style_id: style_id.to_string() })?;
        bind_declared_convention(obs).map_err(WiringError::Convention)?
    } else {
        ScaleContext::from_convention(style_id, CONFIG_CONVENTION_ID, RunConfig::default_units_per_px(), target_upm, cohort, frame_binding)
            .map_err(WiringError::Scale)?
    };
    Ok(BoundRunScale { ctx })
}

fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r") }

/// Receipt row for a wired context. Declared-set contexts delegate to the
/// declared module's validated receipt; config contexts report
/// CONFIG_CONVENTION with calibrated=false. Any other basis is a typed refusal.
pub fn wiring_receipt_row(bound: &BoundRunScale) -> Result<String, WiringError> {
    let ctx = bound.context();
    match ctx.basis() {
        ScaleBasis::Convention { convention_id } if convention_id == CONVENTION_ID => {
            convention_receipt_row(ctx).map_err(WiringError::Convention)
        }
        ScaleBasis::Convention { convention_id } if convention_id == CONFIG_CONVENTION_ID => {
            if record_for(ctx.id()).is_some() || ctx.units_per_px().to_bits() != RunConfig::default_units_per_px().to_bits() || ctx.cohort() != ctx.id() {
                return Err(WiringError::ForeignBasis { detail: "config K/style/cohort conflict".into() });
            }
            let expected = ScaleContext::from_convention(ctx.id(), CONFIG_CONVENTION_ID, RunConfig::default_units_per_px(), ctx.target_upm(), ctx.id(), ctx.frame_binding()).map_err(WiringError::Scale)?;
            if ctx.binding_record() != expected.binding_record() { return Err(WiringError::ForeignBasis { detail: "config identity conflict".into() }); }
            Ok(format!(
            "scale_status\tCONFIG_CONVENTION\tcalibrated\tfalse\tconvention\t{}\tk_bits\t{:016x}\tscale_id\t{}\tcohort\t{}\tframe\t{}\n",
            esc(CONFIG_CONVENTION_ID),
            CONFIG_K.to_bits(),
            esc(ctx.id()),
            esc(ctx.cohort()),
            esc(ctx.frame_binding()),
        ))
        },
        other => Err(WiringError::ForeignBasis { detail: format!("{other:?}") }),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::declared_convention::{DECLARED_H_INK_HEIGHT_PX, DECLARED_K_BITS, EXPECTED_FRAME_ID, EXPECTED_H_SOURCE_PIN_SHA256, EXPECTED_TARGET_UPM};

    const TEST_PNG_LIMITS: DecodeLimits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    const TEST_LIMITS: Limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };

    // ---- minimal PNG encoder (test-only): grayscale 8-bit, filter 0, stored deflate ----
    fn crc32(data: &[u8]) -> u32 {
        let mut c: u32 = 0xffff_ffff;
        for &b in data {
            c ^= b as u32;
            for _ in 0..8 { c = if c & 1 == 1 { (c >> 1) ^ 0xedb8_8320 } else { c >> 1 }; }
        }
        !c
    }
    fn adler32(data: &[u8]) -> u32 {
        let (mut a, mut b) = (1u32, 0u32);
        for &x in data { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
        (b << 16) | a
    }
    fn chunk(typ: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(&(body.len() as u32).to_be_bytes());
        v.extend_from_slice(typ);
        v.extend_from_slice(body);
        let mut c = typ.to_vec();
        c.extend_from_slice(body);
        v.extend_from_slice(&crc32(&c).to_be_bytes());
        v
    }
    /// width x height grayscale PNG; inked rows [ink_first, ink_last] have a
    /// black column at x=0, everything else white.
    pub(crate) fn test_png(width: usize, height: usize, ink_first: usize, ink_last: usize) -> Vec<u8> {
        let mut raw = Vec::with_capacity(height * (width + 1));
        for y in 0..height {
            raw.push(0u8); // filter none
            for x in 0..width {
                raw.push(if x == 0 && y >= ink_first && y <= ink_last { 0 } else { 255 });
            }
        }
        let mut def = Vec::new();
        let mut off = 0;
        while off < raw.len() {
            let n = (raw.len() - off).min(65535);
            let fin = if off + n == raw.len() { 1u8 } else { 0u8 };
            def.push(fin);
            def.extend_from_slice(&(n as u16).to_le_bytes());
            def.extend_from_slice(&(!(n as u16)).to_le_bytes());
            def.extend_from_slice(&raw[off..off + n]);
            off += n;
        }
        let mut z = vec![0x78u8, 0x01];
        z.extend_from_slice(&def);
        z.extend_from_slice(&adler32(&raw).to_be_bytes());
        let mut ihdr = Vec::new();
        ihdr.extend_from_slice(&(width as u32).to_be_bytes());
        ihdr.extend_from_slice(&(height as u32).to_be_bytes());
        ihdr.extend_from_slice(&[8, 0, 0, 0, 0]); // 8-bit grayscale, no interlace
        let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
        png.extend_from_slice(&chunk(b"IHDR", &ihdr));
        png.extend_from_slice(&chunk(b"IDAT", &z));
        png.extend_from_slice(&chunk(b"IEND", &[]));
        png
    }

    fn paul_obs(pin: &str, height: u32, frame: &str) -> HReferenceObservation {
        HReferenceObservation {
            style_id: "Paul New/Regular".to_string(),
            h_source_pin_sha256: pin.to_string(),
            h_ink_height_px: height,
            frame_id: frame.to_string(),
            target_upm: EXPECTED_TARGET_UPM,
        }
    }

    #[test]
    fn config_binds_default_k_for_other_styles() {
        let ctx = bind_run_scale("Marq/Regular", None, "Marq/Regular", "marq-frame", 1000.0).unwrap();
        assert_eq!(ctx.units_per_px().to_bits(), CONFIG_K.to_bits());
        assert_eq!(ctx.units_per_px(), 2.4377);
        match ctx.basis() {
            ScaleBasis::Convention { convention_id } => assert_eq!(convention_id, CONFIG_CONVENTION_ID),
            other => panic!("expected config convention basis, got {other:?}"),
        }
    }

    #[test]
    fn parity_default_k_matches_manifest_literal() {
        // Default parity: the manifest "scale" key's current literal and the
        // wired config default are the same f64 bits, so the wired path
        // reproduces today's default behaviour for styles outside the
        // declared set.
        assert_eq!(CONFIG_K.to_bits(), "2.4377".parse::<f64>().unwrap().to_bits());
    }

    #[test]
    fn config_receipt_is_config_convention_never_calibrated() {
        let ctx = bind_run_scale("Marq/Regular", None, "Marq/Regular", "marq-frame", 1000.0).unwrap();
        let row = wiring_receipt_row(&ctx).unwrap();
        assert!(row.contains("scale_status\tCONFIG_CONVENTION\t"));
        assert!(row.contains("calibrated\tfalse\t"));
        assert!(row.contains(&format!("k_bits\t{:016x}", CONFIG_K.to_bits())));
    }

    #[test]
    fn paul_requires_h_observation() {
        let e = bind_run_scale("Paul New/Regular", None, "Paul New/Regular", EXPECTED_FRAME_ID, 1000.0).unwrap_err();
        assert_eq!(e, WiringError::MissingHObservation { style_id: "Paul New/Regular".to_string() });
    }

    #[test]
    fn paul_binds_declared_k_bits() {
        let obs = paul_obs(EXPECTED_H_SOURCE_PIN_SHA256, DECLARED_H_INK_HEIGHT_PX, EXPECTED_FRAME_ID);
        let ctx = bind_run_scale("Paul New/Regular", Some(&obs), "Paul New/Regular", EXPECTED_FRAME_ID, 1000.0).unwrap();
        assert_eq!(ctx.units_per_px().to_bits(), DECLARED_K_BITS);
        let row = wiring_receipt_row(&ctx).unwrap();
        assert!(row.contains("scale_status\tDECLARED_CONVENTION\t"));
        assert!(row.contains("calibrated\tfalse\t"));
    }

    #[test]
    fn pin_mismatch_is_typed_refusal() {
        let obs = paul_obs(&"0".repeat(64), DECLARED_H_INK_HEIGHT_PX, EXPECTED_FRAME_ID);
        match bind_run_scale("Paul New/Regular", Some(&obs), "Paul New/Regular", &obs.frame_id, 1000.0) {
            Err(WiringError::Convention(ConventionError::HPinMismatch { .. })) => {}
            other => panic!("expected HPinMismatch, got {other:?}"),
        }
    }

    #[test]
    fn ink_height_mismatch_is_typed_refusal_no_clamp() {
        let obs = paul_obs(EXPECTED_H_SOURCE_PIN_SHA256, 1000, EXPECTED_FRAME_ID);
        match bind_run_scale("Paul New/Regular", Some(&obs), "Paul New/Regular", &obs.frame_id, 1000.0) {
            Err(WiringError::Convention(ConventionError::HHeightMismatch { expected: 1122, found: 1000 })) => {}
            other => panic!("expected HHeightMismatch, got {other:?}"),
        }
    }

    #[test]
    fn frame_mismatch_is_typed_refusal() {
        let obs = paul_obs(EXPECTED_H_SOURCE_PIN_SHA256, DECLARED_H_INK_HEIGHT_PX, "PaulNew-Regular:100x1122:H-sha256:c7cd");
        match bind_run_scale("Paul New/Regular", Some(&obs), "Paul New/Regular", &obs.frame_id, 1000.0) {
            Err(WiringError::Convention(ConventionError::HFrameMismatch { .. })) => {}
            other => panic!("expected HFrameMismatch, got {other:?}"),
        }
    }

    #[test]
    fn observe_builds_frame_identity_from_real_capture() {
        let png = test_png(786, 1122, 0, 1121);
        let obs = observe_h_reference("Paul New/Regular", &png, &TEST_PNG_LIMITS, TEST_LIMITS, EXPECTED_TARGET_UPM).unwrap();
        assert_eq!(obs.h_source_pin_sha256, sha256_hex(&png));
        assert_eq!(obs.h_ink_height_px, 1122);
        assert_eq!(obs.frame_id, format!("PaulNew-Regular:786x1122:H-sha256:{}", sha256_hex(&png)));
    }

    #[test]
    fn observe_short_ink_measures_not_clamps() {
        let png = test_png(786, 1122, 61, 1060); // 1000 inked rows
        let obs = observe_h_reference("Paul New/Regular", &png, &TEST_PNG_LIMITS, TEST_LIMITS, EXPECTED_TARGET_UPM).unwrap();
        assert_eq!(obs.h_ink_height_px, 1000);
        // ...and the declared wrapper refuses the drift (typed Convention
        // error; this synthetic capture is not the pinned H, so the pin check
        // fires first). The pure height-refusal path is covered by
        // ink_height_mismatch_is_typed_refusal_no_clamp.
        match bind_run_scale("Paul New/Regular", Some(&obs), "Paul New/Regular", &obs.frame_id, 1000.0) {
            Err(WiringError::Convention(_)) => {}
            other => panic!("expected typed Convention refusal, got {other:?}"),
        }
    }

    #[test]
    fn observe_undecodable_bytes_refused() {
        match observe_h_reference("Paul New/Regular", b"not an image", &TEST_PNG_LIMITS, TEST_LIMITS, 1000.0) {
            Err(WiringError::Decode { .. }) => {}
            Ok(_) => panic!("expected Decode refusal, got Ok"),
            Err(other) => panic!("expected Decode refusal, got {other:?}"),
        }
    }

    #[test]
    fn empty_fields_and_bad_upm_refused() {
        assert!(matches!(bind_run_scale("", None, "c", "f", 1000.0), Err(WiringError::EmptyField { field: "style_id" })));
        assert!(matches!(bind_run_scale("X/Y", None, "c", "f", 0.0), Err(WiringError::BadTargetUpm { .. })));
        assert!(matches!(bind_run_scale("X/Y", None, "", "f", 1000.0), Err(WiringError::EmptyField { field: "cohort" })));
        assert!(matches!(bind_run_scale("X/Y", None, "c", "", 1000.0), Err(WiringError::EmptyField { field: "frame_binding" })));
        assert!(matches!(style_id_of("", "Regular"), Err(WiringError::EmptyField { field: "family" })));
        assert!(matches!(style_id_of("Paul New", ""), Err(WiringError::EmptyField { field: "subfamily" })));
    }

    #[test]
    fn foreign_basis_receipt_refused() {
        let foreign = ScaleContext::from_convention("X/Y", "SomeOtherConvention/v9", 1.0, 1000.0, "c", "f").unwrap();
        assert!(matches!(wiring_receipt_row(&BoundRunScale { ctx: foreign }), Err(WiringError::ForeignBasis { .. })));
    }

    #[test]
    fn per_glyph_override_variant_is_typed() {
        // Integration-point guard: constructing the refusal is explicit and
        // carries the glyph name; the wired path never applies an override.
        let e = WiringError::PerGlyphScaleOverride { glyph: "A".to_string() };
        assert!(format!("{e:?}").contains("A"));
    }

    #[test]
    fn slug_rule_is_the_only_rule() {
        assert_eq!(frame_slug("Paul New/Regular"), "PaulNew-Regular");
        assert_eq!(style_id_of("Paul New", "Regular").unwrap(), "Paul New/Regular");
    }
    #[test]
    fn paul_outer_upm_cohort_and_frame_are_conflicts() {
        let obs = paul_obs(EXPECTED_H_SOURCE_PIN_SHA256, DECLARED_H_INK_HEIGHT_PX, EXPECTED_FRAME_ID);
        for (cohort, frame, upm, field) in [
            ("Paul New/Regular", EXPECTED_FRAME_ID, 2048.0, "target_upm"),
            ("foreign", EXPECTED_FRAME_ID, 1000.0, "cohort"),
            ("Paul New/Regular", "foreign", 1000.0, "frame_binding"),
        ] {
            assert!(matches!(bind_run_scale("Paul New/Regular", Some(&obs), cohort, frame, upm), Err(WiringError::OuterConflict { field: f, .. }) if f == field));
        }
    }

    #[test]
    fn forged_config_k_and_paul_identity_cannot_mint_receipts() {
        for (style, k, cohort) in [("Marq/Regular", 9.0, "Marq/Regular"), ("Paul New/Regular", CONFIG_K, "Paul New/Regular"), ("Marq/Regular", CONFIG_K, "other")] {
            // White-box adversarial construction. Production cannot construct BoundRunScale.
            let ctx = ScaleContext::from_convention(style, CONFIG_CONVENTION_ID, k, 1000.0, cohort, "frame").unwrap();
            assert!(matches!(wiring_receipt_row(&BoundRunScale { ctx }), Err(WiringError::ForeignBasis { .. })));
        }
    }

    #[test]
    fn manifest_bits_mismatch_is_typed_and_default_is_shared() {
        let b = bind_run_scale("Marq/Regular", None, "Marq/Regular", "frame", 1000.0).unwrap();
        assert_eq!(CONFIG_K.to_bits(), RunConfig::default_units_per_px().to_bits());
        assert!(check_manifest_scale(2.4377, b.context()).is_ok());
        assert!(matches!(check_manifest_scale(f64::from_bits(CONFIG_K.to_bits() + 1), b.context()), Err(WiringError::ManifestScaleMismatch { .. })));
        for v in [Some(CONFIG_K), Some(9.0), Some(f64::NAN)] {
            assert!(matches!(reject_glyph_override("H", v), Err(WiringError::PerGlyphScaleOverride { .. })));
        }
    }

    #[test]
    fn observe_threads_explicit_png_limits_to_v3_bounded_decoder() {
        let png = test_png(2, 2, 0, 1);
        let tight = DecodeLimits { max_pixels: 1, ..TEST_PNG_LIMITS };
        assert!(matches!(observe_h_reference("X/Y", &png, &tight, TEST_LIMITS, 1000.0), Err(WiringError::Decode { .. })));
        assert!(observe_h_reference("X/Y", &png, &TEST_PNG_LIMITS, TEST_LIMITS, 1000.0).is_ok());
        let tight = DecodeLimits { max_input_bytes: png.len() - 1, ..TEST_PNG_LIMITS };
        assert!(matches!(observe_h_reference("X/Y", &png, &tight, TEST_LIMITS, 1000.0), Err(WiringError::Decode { .. })));
    }

    #[test]
    fn progressive_sof2_supported_subset_decodes_and_unsupported_typed_refusals() {
        // Declared subset (kni.jpeg-progressive.v1-q14): SOF2 Huffman 8-bit, complete scan
        // script. A real progressive fixture in the declared subset proceeds through the
        // same wiring path; there is no silent fallback decode.
        let prog = include_bytes!("../../core/tests/fixtures/jpeg_progressive/gray_grad_40x40.prog.jpg") as &[u8];
        let obs = observe_h_reference("Paul New/Regular", prog, &TEST_PNG_LIMITS, TEST_LIMITS, 1000.0)
            .expect("declared-subset progressive SOF2 fixture must proceed");
        assert!(obs.h_ink_height_px > 0);
        // 12-bit precision: the real fixture with its SOF2 precision byte flipped to 12 ->
        // typed UnsupportedPrecision at the decoder; typed refusal through the wiring path.
        let mut p12 = prog.to_vec();
        let sof = p12.windows(2).position(|w| w == [0xff, 0xc2]).expect("fixture has SOF2");
        assert_eq!(p12[sof + 4], 8, "fixture precision is 8-bit");
        p12[sof + 4] = 12;
        assert_eq!(kni_core::jpeg_progressive::decode(&p12, TEST_LIMITS).err(),
            Some(kni_core::jpeg_source::JpegError::UnsupportedPrecision));
        assert!(matches!(observe_h_reference("Paul New/Regular", &p12, &TEST_PNG_LIMITS, TEST_LIMITS, 1000.0), Err(WiringError::Decode { .. })));
        // Incomplete scan script (last scan dropped, EOI appended): typed UnsupportedScan,
        // never a partial decode at lower quality.
        let sos = prog.windows(2).rposition(|w| w == [0xff, 0xda]).expect("fixture has SOS");
        let mut cut = prog[..sos].to_vec();
        cut.extend_from_slice(&[0xff, 0xd9]);
        assert_eq!(kni_core::jpeg_progressive::decode(&cut, TEST_LIMITS).err(),
            Some(kni_core::jpeg_source::JpegError::UnsupportedScan));
        assert!(observe_h_reference("Paul New/Regular", &cut, &TEST_PNG_LIMITS, TEST_LIMITS, 1000.0).is_err());
    }

}
