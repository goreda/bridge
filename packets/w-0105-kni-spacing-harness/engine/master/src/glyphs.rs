//! Source-derived kit facts adapter to the shared glyphs_file serializer.
//! No independent file syntax, parser, or geometry conversion lives here.
//! The generator omits appVersion rather than claiming an application build;
//! schema-required-key exception and real Glyphs acceptance remain separate.

use crate::model::MasterGlyph;

/// Vertical metrics for the single master, in the fixed top-level order
/// ascender, cap height, x-height, baseline, descender. Baseline is the
/// coordinate-system origin by definition (pos 0) and is not stored here.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VerticalMetrics {
    pub ascender: f64,
    pub cap_height: f64,
    pub x_height: f64,
    pub descender: f64,
}

/// One source-derived font-info property (Glyphs `properties` entry).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InfoProperty {
    pub key: String,
    pub value: String,
}

/// Single-instance facts from the source font (OS/2 classes, style bits).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InstanceInfo {
    pub weight_class: u16,
    pub width_class: u16,
    pub bold: bool,
    pub italic: bool,
}

/// Source-derived font facts. `version_*` comes from the font's own version
/// string (see `parse_version`); it is never a hardcoded default.
#[derive(Debug, Clone, PartialEq)]
pub struct FontInfo {
    /// Raw source nameID 5 string, retained beside the normalized pair.
    pub version_raw: String,
    pub family_name: String,
    pub style_name: String,
    pub version_major: u32,
    pub version_minor: u32,
    pub units_per_em: u32,
    /// Source-derived only; empty when the source declares nothing.
    pub properties: Vec<InfoProperty>,
    pub instance: InstanceInfo,
}

/// The complete single-master document: info + metrics + structural glyphs.
/// Glyph order is the font's glyph order; unicodes are empty for unmapped
/// glyphs (.notdef, ligature-only glyphs).
#[derive(Debug, Clone)]
pub struct MasterFont {
    pub info: FontInfo,
    pub metrics: VerticalMetrics,
    /// (glyph, cmap code points, export): export=false writes `export = 0`
    /// for carried glyphs with no shipped counterpart (owner ruling).
    /// Effective LTR kerning pairs from the source font's final GPOS
    /// (expanded, unconditional xAdvance adjustments only); written under
    /// kerningLTR for the single master m01.
    pub glyphs: Vec<(MasterGlyph, Vec<u32>, bool)>,
    pub kerning: Vec<crate::glyphs_file::KerningPair>,
}

/// Fixed top-level metrics order (task-pinned 2026-10-18):
/// ascender, cap height, x-height, baseline, descender.
pub const METRICS_ORDER: [&str; 5] = ["ascender", "cap height", "x-height", "baseline", "descender"];

/// Generated single-master id (explicit local convention; this writer emits
/// exactly one master and cannot preserve arbitrary multi-master source ids).
pub const MASTER_ID: &str = "m01";

/// Canonical generator version policy (single parser for B/C/D):
/// Adapt source-derived kit facts to the ONE shared B/C serializer.
pub fn write_glyphs(font: &MasterFont) -> Result<String, String> {
    use crate::glyphs_file::*;
    let metrics = [font.metrics.ascender, font.metrics.cap_height, font.metrics.x_height, 0.0, font.metrics.descender];
    let inst = &font.info.instance;
    let mut properties: Vec<GlyphsProperty> = font.info.properties.iter().map(|p| GlyphsProperty { key: p.key.clone(), value: p.value.clone() }).collect();
    properties.sort_by(|a,b| a.key.cmp(&b.key));
    write(&GlyphsFont {
        family_name: font.info.family_name.clone(),
        upm: font.info.units_per_em,
        version: (font.info.version_major, font.info.version_minor),
        app_version: None,
        axes: vec![],
        metric_types: METRICS_ORDER.iter().map(|s| s.to_string()).collect(),
        masters: vec![GlyphsMaster { id: MASTER_ID.into(), name: font.info.style_name.clone(), axes_values: vec![], metrics: metrics.iter().map(|v| MetricValue { pos: *v, over: None }).collect() }],
        glyphs: font.glyphs.iter().map(|(g, u, x)| GlyphsGlyph { name: g.name.clone(), unicode: u.clone(), layers: vec![GlyphsLayer::from_master_glyph(MASTER_ID, g)], export: *x }).collect(),
        kerning: GlyphsKerning { ltr: font.kerning.clone(), rtl: Vec::new(), vertical: Vec::new() },
        instances: vec![GlyphsInstance { name: font.info.style_name.clone(), axes_values: vec![], exports: true, weight_class: Some(inst.weight_class), width_class: Some(inst.width_class), is_bold: inst.bold.then_some(true), is_italic: inst.italic.then_some(true) }],
        properties,
    }).map_err(|e| e.to_string())
}
