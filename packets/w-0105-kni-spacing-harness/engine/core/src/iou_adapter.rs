//! Binding between the evaluator/exporter side and `iou_report`. SOURCE ONLY (UNRUN).
//!
//! - Frame evidence comes from the SAME values the evaluator pins (`EvalConfig`) plus the
//!   capture origin; nothing is defaulted here.
//! - The outline to measure is the CFF bytes actually emitted, read back with `CffReader`
//!   against a caller-supplied sha256 (post-emit readback, `OutlineStage::OtfReadback`).
//! - Glyph -> gid mapping is the caller's (the exporter's `GlyphIdMap`); this module never guesses it.
use crate::cff_reader::CffReader;
use crate::economy_eval::EvalConfig;
use crate::iou_report::{FrameEvidence, IouError, IouJob, OutlineStage, ResourceLimits, SourceInput};
use crate::reference_slice::DrawnGlyph;

/// Evidence from explicit parts. `translation` is the font-unit shift between the capture frame
/// and the shipped outline (baseline shift, lsb translation); pass (0.0, 0.0) when none applies.
pub fn evidence_from_parts(scale_k: f64, origin: (f64, f64), translation: (f64, f64), ink_threshold: u8,
                           flatten_steps: usize, canvas: (usize, usize), limits: ResourceLimits) -> FrameEvidence {
    FrameEvidence {
        scale_k: Some(scale_k), origin: Some(origin), ink_threshold: Some(ink_threshold),
        flatten_steps: Some(flatten_steps), canvas: Some(canvas), translation: Some(translation), limits: Some(limits),
    }
}

/// Evidence taken from the evaluator's own config so both measure in one frame.
/// `origin` is `MeasuredContour::origin_x/origin_y` of the same tile.
pub fn evidence_from_eval(cfg: &EvalConfig, origin: (f64, f64), translation: (f64, f64), limits: ResourceLimits) -> FrameEvidence {
    evidence_from_parts(cfg.scale_k, origin, translation, cfg.threshold, cfg.flatten_steps, cfg.canvas, limits)
}

/// Read glyphs back out of emitted CFF/OTF bytes. `expected_font_sha256` must be the hash
/// recorded when the bytes were emitted (the reader refuses on mismatch). One `Err` per wanted
/// glyph when the font itself is refused; per-glyph read failures stay per glyph.
pub fn readback_outlines(font_bytes: &[u8], expected_font_sha256: &str, wanted: &[(String, u16)]) -> Vec<Result<DrawnGlyph, IouError>> {
    let reader = match CffReader::from_bytes(font_bytes, expected_font_sha256) {
        Ok(r) => r,
        Err(e) => {
            let detail = format!("font refused: {e:?}");
            return wanted.iter().map(|(id, _)| Err(IouError::OutlineReadback { glyph: id.clone(), detail: detail.clone() })).collect();
        }
    };
    wanted.iter().map(|(id, gid)| {
        reader.read_glyph(*gid)
            .map(|g| g.drawn(id.clone()))
            .map_err(|e| IouError::OutlineReadback { glyph: id.clone(), detail: format!("gid {gid}: {e:?}") })
    }).collect()
}

/// One job whose outline is the post-emit readback.
pub fn job_from_readback(style: &str, glyph_id: &str, source: SourceInput, outline: Result<DrawnGlyph, IouError>, evidence: FrameEvidence) -> IouJob {
    IouJob { style: style.to_string(), glyph_id: glyph_id.to_string(), source, outline, evidence, stage: OutlineStage::OtfReadback }
}
