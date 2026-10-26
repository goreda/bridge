//! Master `.glyphs` companion builder (kit integration): structural geometry
//! from the manifest-pinned master source; font info, vertical metrics,
//! widths and unicodes from the prepared font being shipped. The master
//! source IS the structural drawing (one contour per stroke, free overlaps);
//! final OTF readback must exactly match those structural rings. Every
//! fact comes from the prepared font or the pinned source, and a mismatch
//! between them is a typed error, never a silent pick.

use kni_core::native_font::NativeFontInput;
use kni_core::reference_slice::{DrawnGlyph, Span};
use kni_master::fixture;
use kni_master::glyphs as gw;
use kni_master::model::{MasterGlyph, Op};
use std::collections::BTreeMap;

/// Receipt-safe form of an arbitrary source string: backslash-escaped
/// (\\, \t, \n, \r, \u00XX for other controls). A raw nameID 5 whose
/// qualifier the version grammar legitimately allows (e.g. tabs/newlines)
/// can never inject receipt columns or rows.
pub fn receipt_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// One decompose-route row: the glyph re-emitted from its shipped outline,
/// the part classes decompose produced, and the measured silhouette
/// reconstruction IoU (slice A's contract; exact ring parity is impossible
/// for boolean-merged or refit outlines by construction).
/// Fields are read by the lib target's report consumers (emission
/// examples); the bin target compiles this module but never reads them.
#[allow(dead_code)]
#[derive(Debug)]
pub struct DecomposeRow {
    pub glyph: String,
    pub parts: String,
    pub iou: f64,
}

#[derive(Debug)]
pub struct ParityReport {
    pub compared: usize,
    pub skipped_empty: usize,
    /// Names of the skipped blank glyphs (space): typed, never anonymous
    /// (chief 20:15: name the uncompared glyph as a typed receipt row).
    pub skipped_empty_names: Vec<String>,
    /// Glyphs whose owner-master strokes failed exact ring parity and were
    /// re-emitted from the shipped outline via slice A's decompose route:
    /// source-derived structural parts, named, with reconstruction IoU.
    pub decomposed: Vec<DecomposeRow>,
    /// Every glyph whose exact ring parity failed, with detail. In Refuse
    /// mode the first entry aborts the build; in Report mode the document
    /// is still emitted and this list carries every mismatch.
    pub mismatches: Vec<String>,
    /// Raw source nameID 5 and its normalized pair, receipted for durable
    /// preservation (the .glyphs schema stores only the pair).
    pub version_raw: String,
    pub version: (u32, u32),
}

// Conservative exact identity contract: each structural stroke must be one
// final closed ring, in the same traversal and starting position. Explicit
// and implicit final straight closure are equivalent. Ring order may vary.
// No raster tolerances, point snapping, boolean assumptions, or cubic
// flattening. Boolean-reconciled outlines are refused without source lineage.
type Edge = (u8, [f64; 8]);
fn ring_edges(g: &DrawnGlyph) -> Result<Vec<Vec<Edge>>, String> {
    let mut rings = Vec::new();
    for ring in &g.rings {
        let mut cur = ring.start;
        let mut edges = Vec::new();
        for span in &ring.spans {
            let (kind, c1, c2, end) = match span {
                Span::Line { end } => (0, cur, *end, *end),
                Span::Cubic { control_one, control_two, end } => (1, *control_one, *control_two, *end),
            };
            let v = [cur.x, cur.y, c1.x, c1.y, c2.x, c2.y, end.x, end.y];
            if !v.iter().all(|v| v.is_finite()) { return Err("non-finite final outline".into()); }
            edges.push((kind, v));
            cur = end;
        }
        if cur != ring.start {
            let end = ring.start;
            edges.push((0, [cur.x, cur.y, cur.x, cur.y, end.x, end.y, end.x, end.y]));
        }
        if !edges.is_empty() { rings.push(edges); }
    }
    Ok(rings)
}
pub(crate) fn structural_outline(g: &MasterGlyph) -> Result<DrawnGlyph, String> {
    use kni_core::reference_slice::{Point, ReferenceRing};
    let p = |p: (f64, f64)| Point { x: p.0, y: p.1 };
    let mut rings = Vec::new();
    for c in &g.contours {
        let start = match c.ops.first() { Some(Op::Move(v)) => p(*v), _ => return Err("stroke must start with Move".into()) };
        if !matches!(c.ops.last(), Some(Op::Close)) { return Err("stroke must end with Close".into()); }
        let mut spans = Vec::new();
        for op in &c.ops[1..c.ops.len()-1] {
            spans.push(match op {
                Op::Line(v) => Span::Line { end: p(*v) },
                Op::Curve(a,b,v) => Span::Cubic { control_one: p(*a), control_two: p(*b), end: p(*v) },
                _ => return Err("stroke has interior Move or Close".into()),
            });
        }
        if spans.is_empty() { return Err("empty stroke".into()); }
        rings.push(ReferenceRing { start, spans });
    }
    Ok(DrawnGlyph { glyph_id: g.name.clone(), rings })
}
/// Slice A integrated route: decompose the SHIPPED final outline into
/// structural parts (source-derived, provenance-carrying). Returns the part
/// contours for re-emission plus the receipt row. The shipped outline is the
/// source of truth; the owner-master strokes it replaces were measured
/// non-identical to it by the exact-ring check above.
fn decompose_fallback(shipped: &DrawnGlyph, name: &str, upm: f64) -> Result<(Vec<kni_master::model::StrokeContour>, DecomposeRow), String> {
    use kni_master::decompose::{check_structure, decompose};
    use kni_master::model::MasterGlyph;
    let mut contours = Vec::new();
    for (i, ring) in shipped.rings.iter().enumerate() {
        contours.push(ring_to_stroke_contour(ring, &format!("contour-{}", i + 1)));
    }
    let flat = MasterGlyph { name: name.to_string(), advance: 0.0, upm, contours };
    let d = decompose(&flat).map_err(|e| format!("{e:?}"))?;
    check_structure(&d).map_err(|e| format!("structure: {e}"))?;
    // Reconstruction IoU, same method as slice A's own test: rasterize the
    // source rings and the part rings under a nonzero fill, paired IoU.
    let src_polys: Vec<Vec<(f64, f64)>> = flat.contours.iter().map(kni_master::check::stroke_polygon).collect();
    let part_polys: Vec<Vec<(f64, f64)>> = d.glyph.contours.iter().map(kni_master::check::stroke_polygon).collect();
    let b = kni_master::raster::bounds_of(&[&src_polys, &part_polys], 2.0);
    let span = (b.2 - b.0).max(b.3 - b.1);
    let px = span / 640.0;
    let (_, _, m_src) = kni_master::raster::rasterize(&src_polys, true, b, px, (0.5, 0.5));
    let (_, _, m_part) = kni_master::raster::rasterize(&part_polys, true, b, px, (0.5, 0.5));
    let iou = kni_master::raster::paired_iou(&m_part, &m_src).0;
    let mut classes: Vec<&str> = d.parts.iter().map(|p| p.class.as_str()).collect();
    classes.sort_unstable();
    Ok((d.glyph.contours, DecomposeRow { glyph: name.to_string(), parts: classes.join("+"), iou }))
}

fn parity_glyph(master: &MasterGlyph, shipped: &DrawnGlyph) -> Result<bool, String> {
    let a = ring_edges(&structural_outline(master)?)?;
    let mut b = ring_edges(shipped)?;
    let empty = a.is_empty() && b.is_empty();
    for ring in &a {
        let index = b.iter().position(|r| r == ring).ok_or_else(|| format!("parity refused: exact structural ring absent from final outline of {:?}; boolean reconciliation needs verified lineage", master.name))?;
        b.remove(index);
    }
    if !b.is_empty() { return Err(format!("parity refused: extra final rings in {:?}", master.name)); }
    Ok(empty)
}

fn name_value(font: &NativeFontInput, id: u16) -> Option<String> {
    // Prefer the en-US Windows record; otherwise any record with the id.
    let mut any: Option<&str> = None;
    for r in &font.names {
        if r.name_id == id && !r.value.is_empty() {
            if r.language == 0x409 {
                return Some(r.value.clone());
            }
            any.get_or_insert(&r.value);
        }
    }
    any.map(str::to_string)
}

/// Build the .glyphs document for the font being shipped. `master_text` is
/// the pinned multi-glyph structural source (fixture format: glyph/stroke/
/// M/L/C/Z blocks, file order is glyph order there, but the shipped order
/// comes from the font).
pub fn build(
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
    master_text: &str,
    deltas: Option<(&[i64], &[i64])>,
    kerning: &[kni_master::glyphs_file::KerningPair],
) -> Result<(String, ParityReport), String> {
    let masters = fixture::parse_many(master_text)?;
    build_from(prepared, mapping, &masters.iter().collect::<Vec<_>>(), deltas, kerning)
}

/// Owner-emission path: exact parity measured and recorded for every glyph,
/// but a mismatch does not block the deliverable; the mismatch ledger is
/// part of the result. Publication through the pipeline uses `build` /
/// `build_from`, which refuse.
/// Report-mode API used by the lib target and the emission examples; the
/// pipeline bin compiles this module but only calls `build`.
#[allow(dead_code)]
/// Self-derived structural masters (owner order 2026-10-18 19:42,
/// integrated engine feature): no external structural source - the master
/// contours ARE the final font's own readback rings, exact by construction.
/// The receipt labels the mode self-derived (never an independent-source
/// claim). Shared by the emit hook (main.rs) and the validation test.
/// THE pinned ReferenceRing -> StrokeContour conversion (SliceA amendment 1,
/// chief accepted): every lane that turns final rings into master contours goes
/// through this one fn - the self-derived emission lane and the decompose lane.
pub fn ring_to_stroke_contour(
    ring: &kni_core::reference_slice::ReferenceRing,
    stroke: &str,
) -> kni_master::model::StrokeContour {
    use kni_core::reference_slice::Span;
    use kni_master::model::Op;
    let mut ops = Vec::with_capacity(ring.spans.len() + 2);
    ops.push(Op::Move((ring.start.x, ring.start.y)));
    for span in &ring.spans {
        match span {
            Span::Line { end } => ops.push(Op::Line((end.x, end.y))),
            Span::Cubic { control_one, control_two, end } => {
                ops.push(Op::Curve((control_one.x, control_one.y), (control_two.x, control_two.y), (end.x, end.y)))
            }
        }
    }
    ops.push(Op::Close);
    kni_master::model::StrokeContour { stroke: stroke.to_string(), ops }
}

pub fn self_derived_masters(prepared: &kni_core::native_font::NativeFontInput) -> Vec<kni_master::model::MasterGlyph> {
    let upm = f64::from(prepared.head.units_per_em);
    let mut masters = Vec::with_capacity(prepared.glyphs.len());
    for g in &prepared.glyphs {
        let mut contours = Vec::with_capacity(g.outline.rings.len());
        for (i, ring) in g.outline.rings.iter().enumerate() {
            contours.push(ring_to_stroke_contour(ring, &format!("contour-{}", i + 1)));
        }
        masters.push(kni_master::model::MasterGlyph { name: g.name.clone(), advance: f64::from(g.advance), upm, contours });
    }
    masters
}

pub fn build_from_report(
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
    masters: &[&kni_master::model::MasterGlyph],
    no_export: &std::collections::BTreeSet<String>,
    kerning: &[kni_master::glyphs_file::KerningPair],
) -> Result<(String, ParityReport), String> {
    build_impl(prepared, mapping, masters, None, true, no_export, kerning, false)
}

/// Same as `build`, from already-parsed structural masters (e.g. the owner
/// .glyphs masters via the owner_master converter). `deltas` is the optional
/// post-pass (translations, advance_deltas) pair, one entry per glyph id.
pub fn build_from(
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
    masters: &[&kni_master::model::MasterGlyph],
    deltas: Option<(&[i64], &[i64])>,
    kerning: &[kni_master::glyphs_file::KerningPair],
) -> Result<(String, ParityReport), String> {
    build_impl(prepared, mapping, masters, deltas, false, &std::collections::BTreeSet::new(), kerning, false)
}

/// Finalize one glyph with precisely the report builder's historical fallback.
/// Checkpoint callers cache this result, not the initial decomposition alone.
pub(crate) fn finalize_one(master: &MasterGlyph, shipped: &DrawnGlyph, upm: f64) -> (MasterGlyph,String) {
    let mut out=master.clone();
    let mut rows=String::new();
    if let Err(e)=parity_glyph(master,shipped) {
        match decompose_fallback(shipped,&master.name,upm) {
            Ok((contours,row)) => { out.contours=contours; rows=format!("master_glyphs_finalized\t{}\tparts\t{}\tiou\t{}\n",row.glyph,row.parts,row.iou); }
            Err(reason) => rows=format!("master_glyphs_finalized_residual\t{}\t{}; {}\n",master.name,e,reason),
        }
    }
    (out,rows)
}

/// Only validated finalized checkpoints enter this crate-private assembly path.
/// Metadata, names, sorting, widths and all global document gates are unchanged.
pub(crate) fn build_from_finalized_report(prepared:&NativeFontInput,mapping:&[(u32,u16)],masters:&[&MasterGlyph],kerning:&[kni_master::glyphs_file::KerningPair])->Result<(String,ParityReport),String>{
    build_impl(prepared,mapping,masters,None,true,&std::collections::BTreeSet::new(),kerning,true)
}

fn build_impl(
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
    masters: &[&kni_master::model::MasterGlyph],
    deltas: Option<(&[i64], &[i64])>,
    report_only: bool,
    no_export: &std::collections::BTreeSet<String>,
    kerning: &[kni_master::glyphs_file::KerningPair],
    finalized: bool,
) -> Result<(String, ParityReport), String> {
    if let Some((t, a)) = deltas {
        if t.len() != prepared.glyphs.len() || a.len() != prepared.glyphs.len() {
            return Err("post-pass delta glyph count mismatch".into());
        }
    }
    let mut by_name: BTreeMap<&str, &kni_master::model::MasterGlyph> = BTreeMap::new();
    for m in masters {
        if by_name.insert(m.name.as_str(), m).is_some() {
            return Err(format!("master source: duplicate glyph {:?}", m.name));
        }
    }
    let upm = u32::from(prepared.head.units_per_em);
    // Glyph set must be exactly the shipped glyph set, in shipped order;
    // advances and upm must agree (same drawing), otherwise typed error.
    // Report-mode may carry extra no-export glyphs beyond the shipped run
    // (owner ruling: carry all, export = 0); the strict path stays exact.
    if masters.len() != prepared.glyphs.len() && !(report_only && masters.len() > prepared.glyphs.len() && masters.len() - prepared.glyphs.len() == no_export.len()) {
        return Err(format!(
            "master source glyph count {} != shipped glyph count {}",
            masters.len(),
            prepared.glyphs.len()
        ));
    }
    let mut unicodes: BTreeMap<u16, Vec<u32>> = BTreeMap::new();
    for (cp, gid) in mapping {
        unicodes.entry(*gid).or_default().push(*cp);
    }
    for cps in unicodes.values_mut() {
        cps.sort_unstable();
    }
    let version = name_value(prepared, 5).ok_or("font has no version string (name id 5)")?;
    let mut glyphs: Vec<(kni_master::model::MasterGlyph, Vec<u32>, bool)> = Vec::with_capacity(masters.len());
    for (gid, g) in prepared.glyphs.iter().enumerate() {
        let m = by_name
            .get(g.name.as_str())
            .ok_or_else(|| format!("master source: shipped glyph {:?} has no structural drawing", g.name))?;
        if m.upm != f64::from(prepared.head.units_per_em) {
            return Err(format!("master source glyph {:?}: upm {} != font upm {}", g.name, m.upm, prepared.head.units_per_em));
        }
        // Post-pass deltas (same certificate the post-metrics ledger uses):
        // the master source is pre-pass, so its advance plus the pass delta
        // must equal the FINAL shipped advance, and its strokes are compared
        // after the pass translation.
        let dadv = deltas.map(|(_, a)| a[gid]).unwrap_or(0);
        let expected = g.advance as i64 - dadv;
        if m.advance.fract() != 0.0 || m.advance < 0.0 || m.advance != expected as f64 {
            return Err(format!(
                "master source glyph {:?}: advance {} != shipped advance {} (post-pass delta {dadv})",
                g.name, m.advance, g.advance
            ));
        }
        let dx = deltas.map(|(t, _)| t[gid]).unwrap_or(0) as f64;
        let mut emitted = (*m).clone();
        emitted.advance = f64::from(g.advance);
        for contour in &mut emitted.contours {
            for op in &mut contour.ops {
                match op {
                    Op::Move(p) | Op::Line(p) => p.0 += dx,
                    Op::Curve(a,b,p) => { a.0 += dx; b.0 += dx; p.0 += dx; },
                    Op::Close => {},
                }
            }
        }
        let cps = unicodes.get(&(gid as u16)).cloned().unwrap_or_default();
        let export = !no_export.contains(&emitted.name);
        glyphs.push((emitted, cps, export));
    }
    // Carried glyphs with no shipped counterpart (owner ruling: carry all,
    // `export = 0`, named in findings). They sit beyond the shipped gid run
    // and skip parity (no final outline exists to compare against).
    for m in masters.iter().skip(prepared.glyphs.len()) {
        if !no_export.contains(&m.name) {
            return Err(format!("carried glyph {:?} beyond the shipped run is not declared no-export", m.name));
        }
        glyphs.push(((**m).clone(), Vec::new(), false));
    }
    let mut report = ParityReport { compared: 0, skipped_empty: 0, skipped_empty_names: Vec::new(), decomposed: Vec::new(), mismatches: Vec::new(), version_raw: version.clone(), version: (0, 0) };
    let n_shipped = prepared.glyphs.len();
    let mut replacements: Vec<(usize, Vec<kni_master::model::StrokeContour>, DecomposeRow)> = Vec::new();
    for (i, ((emitted, ..), g)) in glyphs.iter().zip(&prepared.glyphs).enumerate() {
        if finalized { continue; }
        match parity_glyph(emitted, &g.outline) {
            Ok(true) => {
                report.skipped_empty += 1;
                report.skipped_empty_names.push(emitted.name.clone());
            }
            Ok(false) => report.compared += 1,
            Err(e) => {
                if !report_only { return Err(e); }
                match decompose_fallback(&g.outline, &emitted.name, f64::from(prepared.head.units_per_em)) {
                    Ok((contours, row)) => replacements.push((i, contours, row)),
                    Err(reason) => report.mismatches.push(format!("{e}; decompose route failed: {reason}")),
                }
            }
        }
    }
    let _ = n_shipped;
    for (i, contours, row) in replacements {
        glyphs[i].0.contours = contours;
        report.decomposed.push(row);
    }
    // Glyphs-friendly deterministic order (owner acceptance 2026-10-18):
    // grouped by official GlyphData category/script/subcategory so the Font
    // View shows one contiguous run per group; .notdef first. The glyph
    // multiset is unchanged - names, unicodes, geometry, widths all travel
    // with their glyph; only positions change.
    let glyphs = kni_master::glyphdata::ordered(glyphs, |(g, ..)| g.name.as_str());
    let family = name_value(prepared, 1).ok_or("font has no family name (name id 1)")?;
    let style = name_value(prepared, 2).ok_or("font has no style name (name id 2)")?;
    // ONE shared parser (slice B item 15, kni_master::version); C's local
    // parser is retired. Numeric equality only; raw nameID 5 retained below.
    let (version_major, version_minor) = kni_master::version::parse_version(&version)
        .ok_or_else(|| format!("version {version:?}: rejected by the shared version grammar"))?;
    report.version = (version_major, version_minor);
    if prepared.os2.version < 2 && prepared.glyphs.iter().any(|g| !g.outline.rings.is_empty()) {
        return Err(format!("OS/2 version {} < 2: no source cap height / x-height to derive from", prepared.os2.version));
    }
    let mut properties = Vec::new();
    for (id, key) in [(0u16, "copyright"), (8, "manufacturer"), (9, "designer"), (11, "manufacturerURL"), (12, "designerURL"), (13, "license"), (14, "licenseURL")] {
        if let Some(v) = name_value(prepared, id) {
            properties.push(gw::InfoProperty { key: key.to_string(), value: v });
        }
    }
    // Absence is logged by the caller's receipt; nothing is invented here.
    let vendor: String = prepared
        .os2
        .vendor
        .iter()
        .map(|b| *b as char)
        .collect::<String>()
        .trim()
        .to_string();
    if !vendor.is_empty() && vendor.bytes().all(|b| b.is_ascii_graphic()) {
        properties.push(gw::InfoProperty { key: "vendorID".into(), value: vendor });
    }
    let os2 = &prepared.os2;
    let font = gw::MasterFont {
        info: gw::FontInfo {
            version_raw: version,
            family_name: family,
            style_name: style,
            version_major,
            version_minor,
            units_per_em: upm,
            properties,
            instance: {
                if !(1..=1000).contains(&os2.weight) || !(1..=9).contains(&os2.width) {
                    return Err(format!("OS/2 class out of range: weight {} width {}", os2.weight, os2.width));
                }
                gw::InstanceInfo {
                    weight_class: os2.weight,
                    width_class: os2.width,
                    bold: os2.selection & 32 != 0,
                    italic: os2.selection & 1 != 0,
                }
            },
        },
        metrics: gw::VerticalMetrics {
            ascender: f64::from(os2.typo[0]),
            cap_height: f64::from(os2.cap_height),
            x_height: f64::from(os2.x_height),
            descender: f64::from(os2.typo[1]), // OS/2 sTypoDescender; typo[2] is sTypoLineGap
        },
        glyphs,
        kerning: kerning.to_vec(),
    };
    let doc = gw::write_glyphs(&font)?;
    Ok((doc, report))
}

/// Gate the freshly written document against its sources (chief 2026-10-18
/// 20:16 order, zero tolerance): the doc kerningLTR/m01 pair set equals the
/// final-GPOS effective pairs it was built from; every m01 layer width equals
/// the final hmtx advance; the m01 metricValues equal the OS/2-derived five
/// (ascender, cap height, x-height, baseline=0, descender). Any mismatch
/// refuses publish with the failures named. Returns the receipt rows.
pub fn gate_written_doc(
    doc: &str,
    prepared: &NativeFontInput,
    kerning: &[kni_master::glyphs_file::KerningPair],
) -> Result<String, String> {
    let root = kni_master::glyphsfile::parse(doc.as_bytes()).map_err(|e| format!("master gate: written doc fails strict parse (refuse publish): {e}"))?;
    let info = kni_master::glyphsfile::font_info(&root).map_err(|e| format!("master gate: written doc facts unreadable (refuse publish): {e}"))?;
    // Kerning gate: pair set equality, zero tolerance.
    let mut expected: Vec<(String, String, f64)> = kerning.iter().map(|k| (k.left.clone(), k.right.clone(), k.value)).collect();
    expected.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    let mut got: Vec<(String, String, f64)> = Vec::new();
    for home in &info.kern_homes {
        if home.table == "kerningLTR" && home.master.as_deref() == Some(kni_master::glyphs::MASTER_ID) {
            got.extend(home.pairs.iter().cloned());
        }
    }
    got.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    if got != expected {
        let missing: Vec<_> = expected.iter().filter(|p| !got.contains(p)).take(10).collect();
        let extra: Vec<_> = got.iter().filter(|p| !expected.contains(p)).take(10).collect();
        return Err(format!(
            "master gate kerning mismatch (refuse publish): doc {} pairs vs source {} pairs; missing from doc {missing:?}; extra in doc {extra:?}",
            got.len(), expected.len()
        ));
    }
    // Width gate: each exporting glyph's m01 layer width == final hmtx advance.
    let mut compared = 0usize;
    let mut bad: Vec<String> = Vec::new();
    for g in &prepared.glyphs {
        let rec = info.widths.iter().find(|w| w.glyph == g.name && w.master.as_deref() == Some(kni_master::glyphs::MASTER_ID));
        let Some(rec) = rec else { bad.push(format!("{}: no m01 layer", g.name)); continue; };
        let Some(w) = rec.width else { bad.push(format!("{}: m01 layer has no width", g.name)); continue; };
        if w != f64::from(g.advance) { bad.push(format!("{}: doc width {} != hmtx {}", g.name, w, g.advance)); continue; }
        compared += 1;
    }
    if !bad.is_empty() {
        return Err(format!("master gate width mismatch (refuse publish), {} glyph(s): {}", bad.len(), bad.join("; ")));
    }
    // Metrics gate: m01 metricValues positional against the doc's own registry.
    let want: [(String, f64); 5] = [
        ("ascender".into(), f64::from(prepared.os2.typo[0])),
        ("cap height".into(), f64::from(prepared.os2.cap_height)),
        ("x-height".into(), f64::from(prepared.os2.x_height)),
        ("baseline".into(), 0.0),
        ("descender".into(), f64::from(prepared.os2.typo[1])),
    ];
    let m01 = info.masters.iter().find(|m| m.id.as_deref() == Some(kni_master::glyphs::MASTER_ID))
        .ok_or("master gate: written doc has no m01 master (refuse publish)")?;
    if !m01.has_metric_values {
        return Err("master gate: m01 master has no metricValues (refuse publish)".into());
    }
    for (kind, value) in &want {
        let slot = m01.metric_values.iter().find(|(t, _, _)| t.as_deref() == Some(kind.as_str()));
        match slot {
            Some((_, Some(pos), _)) if pos == value => {}
            other => return Err(format!("master gate metric mismatch (refuse publish): {kind} want {value} got {other:?}")),
        }
    }
    Ok(format!(
        "master_glyphs_gate	kerning	pairs	{}	status	match
master_glyphs_gate	widths	compared	{}	status	match
master_glyphs_gate	metrics	master	m01	values	5	status	match
",
        expected.len(), compared
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_core::native_font::NativeFontInput;
    use kni_core::reference_slice::DrawnGlyph;
    use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata};

    fn font() -> (NativeFontInput, Vec<(u32, u16)>) {
        // Outlines match the MASTER structural strokes exactly - the shipped
        // geometry the parity gate verifies against.
        let mut glyphs = vec![
            kni_core::cff_container::CffGlyph { name: ".notdef".into(), advance: 500, outline: DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] } },
            kni_core::cff_container::CffGlyph { name: "h".into(), advance: 620, outline: DrawnGlyph { glyph_id: "h".into(), rings: vec![] } },
            kni_core::cff_container::CffGlyph { name: "dotlessi".into(), advance: 260, outline: DrawnGlyph { glyph_id: "dotlessi".into(), rings: vec![] } },
        ];
        outline_rect(&mut glyphs[0], 50.0, 0.0, 450.0, 700.0);
        outline_rect(&mut glyphs[1], 60.0, 0.0, 140.0, 700.0);
        outline_rect(&mut glyphs[2], 90.0, 0.0, 170.0, 500.0);
        let names = |id: u16, v: &str| NameRecord { language: 0x409, name_id: id, value: v.to_string() };
        let f = NativeFontInput {
            postscript_name: "Marq-Alternate".into(),
            left_side_bearings: vec![0, 0, 0],
            glyphs,
            mapping: vec![(0x68, 1)],
            head: HeadMetadata { revision: 0, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 8 },
            hhea: HheaMetadata { ascender: 800, descender: -200, line_gap: 0, advance_max: 620, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 3 },
            post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
            os2: Os2Metadata {
                average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [0; 4], superscript: [0; 4], strikeout: [0; 2],
                family_class: 0, panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"KNI\0", selection: 0, first_char: 0x68, last_char: 0x68,
                typo: [770, -145, 0], win_ascent: 800, win_descent: 200, version: 4, cap_height: 700, x_height: 500,
            },
            names: vec![
                names(1, "Marq"), names(2, "Alternate"), names(3, "u"), names(4, "Marq Alternate"),
                names(5, "Version 1.050"), names(6, "Marq-Alternate"), names(9, "Karl Nawrot"),
            ],
        };
        (f, vec![(0x68, 1)])
    }

    const MASTER: &str = "glyph .notdef 500 1000\nstroke box\nM 50 0\nL 50 700\nL 450 700\nL 450 0\nZ\nglyph h 620 1000\nstroke stem\nM 60 0\nL 60 700\nL 140 700\nL 140 0\nZ\nglyph dotlessi 260 1000\nstroke stem\nM 90 0\nL 90 500\nL 170 500\nL 170 0\nZ\n";

    #[test]
    fn builds_doc_from_font_facts_and_structural_source() {
        let (f, mapping) = font();
        let (doc, _) = build(&f, &mapping, MASTER, None, &[]).unwrap();
        assert!(doc.contains("familyName = \"Marq\";"), "{doc}");
        assert!(doc.contains("name = \"Alternate\";"), "{doc}");
        assert!(doc.contains("pos = 770;"), "{doc}");
        assert!(doc.contains("pos = -145;"), "{doc}");
        assert!(doc.contains("unicode = 104;"), "{doc}");
        assert!(doc.contains("width = 620;"), "{doc}");
        assert!(doc.contains("key = \"designer\";"), "{doc}");
        assert!(doc.contains("versionMajor = 1;\nversionMinor = 50;"), "{doc}");
        // shipped order, not source order: .notdef first
        let n = doc.find("glyphname = \".notdef\";").unwrap();
        let h = doc.find("glyphname = \"h\";").unwrap();
        assert!(n < h, "{doc}");
    }

    #[test]
    fn mismatches_are_typed_errors() {
        let (f, mapping) = font();
        let bad_adv = MASTER.replace("glyph h 620", "glyph h 621");
        assert!(build(&f, &mapping, &bad_adv, None, &[]).unwrap_err().contains("advance"));
        let bad_upm = MASTER.replace("glyph h 620 1000", "glyph h 620 999");
        assert!(build(&f, &mapping, &bad_upm, None, &[]).unwrap_err().contains("upm"));
        let missing = MASTER.replace("glyph dotlessi", "glyph xdotlessi");
        assert!(build(&f, &mapping, &missing, None, &[]).unwrap_err().contains("no structural drawing"));
        let dup = format!("{MASTER}{MASTER}");
        assert!(build(&f, &mapping, &dup, None, &[]).unwrap_err().contains("duplicate"));
        let mut f2 = font().0;
        f2.names.retain(|r| r.name_id != 5);
        assert!(build(&f2, &mapping, MASTER, None, &[]).unwrap_err().contains("version"));
    }
fn outline_rect(g: &mut kni_core::cff_container::CffGlyph, x0: f64, y0: f64, x1: f64, y1: f64) {
        use kni_core::reference_slice::{Point, ReferenceRing, Span};
        let p = |x: f64, y: f64| Point { x, y };
        g.outline.rings = vec![ReferenceRing {
            start: p(x0, y0),
            spans: vec![Span::Line { end: p(x0, y1) }, Span::Line { end: p(x1, y1) }, Span::Line { end: p(x1, y0) }, Span::Line { end: p(x0, y0) }],
        }];
    }

    #[test]
    fn parity_refuses_geometry_that_is_not_the_shipped_drawing() {
        let (mut f, mapping) = font();
        // shipped .notdef matches the master's 50..450 x 0..700 box
        outline_rect(&mut f.glyphs[0], 50.0, 0.0, 450.0, 700.0);
        // shipped h matches the master stem box
        outline_rect(&mut f.glyphs[1], 60.0, 0.0, 140.0, 700.0);
        outline_rect(&mut f.glyphs[2], 90.0, 0.0, 170.0, 500.0);
        let (_, report) = build(&f, &mapping, MASTER, None, &[]).unwrap();
        assert_eq!(report.compared, 3, "{report:?}");

        // same name/count/upm/advance but DIFFERENT geometry: refused
        outline_rect(&mut f.glyphs[1], 200.0, 100.0, 280.0, 600.0);
        let e = build(&f, &mapping, MASTER, None, &[]).unwrap_err();
        assert!(e.contains("parity refused"), "{e}");
        assert!(e.contains("\"h\""), "{e}");
    }
    #[test]
    fn parity_applies_certified_deltas_to_the_emitted_master() {
        let (mut f, mapping) = font();
        for glyph in &mut f.glyphs {
            glyph.advance += 12;
            for ring in &mut glyph.outline.rings {
                ring.start.x += 7.0;
                for span in &mut ring.spans {
                    match span {
                        Span::Line { end } => end.x += 7.0,
                        Span::Cubic { control_one, control_two, end } => {
                            control_one.x += 7.0; control_two.x += 7.0; end.x += 7.0;
                        }
                    }
                }
            }
        }
        let translations = vec![7i64; 3];
        let advance_deltas = vec![12i64; 3];
        let (doc, report) = build(&f, &mapping, MASTER, Some((&translations, &advance_deltas)), &[]).unwrap();
        assert_eq!(report.compared, 3);
        assert!(doc.contains("(67,0,l)"), "translated master coordinate absent");
        assert!(doc.contains("width = 632;"), "final advance absent");
        assert!(build(&f, &mapping, MASTER, None, &[]).is_err());
    }

    #[test]
    fn parity_rejects_small_differences_and_wrong_cubic_controls() {
        let m = fixture::parse("glyph arbitrary 500 1000\nstroke stroke\nM 0 0\nC 10 20 30 40 50 60\nL 0 60\nZ\n").unwrap();
        let mut shipped = structural_outline(&m).unwrap();
        assert!(!parity_glyph(&m, &shipped).unwrap());
        if let Span::Cubic { control_one, .. } = &mut shipped.rings[0].spans[0] {
            control_one.x += 0.00001;
        }
        assert!(parity_glyph(&m, &shipped).is_err());
        let tiny = fixture::parse("glyph arbitrary 500 1000\nstroke stroke\nM 0 0\nL 1 0\nL 1 1\nZ\n").unwrap();
        let blank = DrawnGlyph { glyph_id: "arbitrary".into(), rings: vec![] };
        assert!(parity_glyph(&tiny, &blank).is_err());
    }

    #[test]
    fn metrics_come_from_offset_true_os2_fields() {
        let (f, mapping) = font();
        let os2_bytes = kni_core::sfnt_metadata::os2(&f.os2).unwrap();
        assert_eq!(i16::from_be_bytes([os2_bytes[68], os2_bytes[69]]), 770, "sTypoAscender at 68");
        assert_eq!(i16::from_be_bytes([os2_bytes[70], os2_bytes[71]]), -145, "sTypoDescender at 70");
        assert_eq!(i16::from_be_bytes([os2_bytes[72], os2_bytes[73]]), 0, "sTypoLineGap at 72");
        let (doc, _) = build(&f, &mapping, MASTER, None, &[]).unwrap();
        assert!(doc.contains("pos = -145;"), "{doc}");
        assert!(!doc.contains("pos = 0;\n},\n{ pos = -145"), "linegap must not be descender: {doc}");
    }

    #[test]
    fn receipt_raw_version_cannot_inject_columns_or_rows() {
        let raw = "1.050\tbuild\n7\r\\";
        let (mut f, _) = font();
        f.names.iter_mut().find(|r| r.name_id == 5).unwrap().value = raw.to_string();
        let escaped = receipt_escape(raw);
        assert!(!escaped.contains('\t') && !escaped.contains('\n') && !escaped.contains('\r'));
        assert_eq!(escaped.matches("\\t").count(), 1, "{escaped}");
        assert_eq!(escaped.matches("\\n").count(), 1, "{escaped}");
        assert!(escaped.ends_with("\\\\"), "{escaped}");
        // the grammar accepts this qualifier and the escaped value is what a
        // receipt may carry
        let (_, report) = build(&f, &font().1, MASTER, None, &[]).unwrap();
        assert_eq!(report.version_raw, raw);
        assert_eq!(report.version, (1, 50));
        let row = format!("master_glyphs_version\traw\t{}", receipt_escape(&report.version_raw));
        assert_eq!(row.lines().count(), 1, "{row:?}");
        assert_eq!(row.split('\t').count(), 3, "{row:?}");
    }

}


#[cfg(test)]
mod self_derived_validation_tests {
    /// Emission proof on a real shipped OTF (env-gated):
    /// KNI_SELF_DERIVE_FIXTURE_OTF=<path> - builds the self-derived masters
    /// from the shipped font's own readback rings, runs the doc build, and
    /// reports parity + doc size. Skipped silently when unset.
    #[test]
    #[ignore]
    fn self_derived_doc_from_shipped_otf() {
        let Ok(path) = std::env::var("KNI_SELF_DERIVE_FIXTURE_OTF") else { return; };
        let bytes = std::fs::read(path).unwrap();
        let (mut font, mapping) = crate::otf_facts::read_otf(&bytes).unwrap();
        for (i, g) in font.glyphs.iter_mut().enumerate() {
            g.name = if i == 0 { ".notdef".into() } else { format!("g{i:04}") };
        }
        let masters = crate::master_glyphs::self_derived_masters(&font);
        let ordered: Vec<_> = masters.iter().collect();
        let (doc, report) = crate::master_glyphs::build_from_report(&font, &mapping, &ordered, &std::collections::BTreeSet::new(), &[]).unwrap();
        eprintln!("self_derived\tmasters\t{}\tcompared\t{}\tdecomposed\t{}\tmismatches\t{}\tdoc_bytes\t{}",
            masters.len(), report.compared, report.decomposed.len(), report.mismatches.len(), doc.len());
        assert_eq!(report.mismatches.len(), 0, "self-derived parity must be exact: {:?}", &report.mismatches[..report.mismatches.len().min(3)]);
    }
}
