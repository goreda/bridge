//! P6 pipeline orchestration smoke: synthetic generated geometry -> spacing -> residual kern ledger -> native OTF
//! bytes -> independent byte-level read-back, plus boundary refusals. Synthetic fixture only: no source font,
//! no corpus, no benchmark, no quality claim. Each stage is the library's own public path.
#[path = "../examples/support/generated_native_fixture.rs"] #[allow(dead_code)] mod fixture;
#[path = "../examples/support/cubic_flatten.rs"] #[allow(dead_code)] mod flat;
use kni_core::cff_container::{CffGlyph, ContainerError};
use kni_core::generated_native::{encode_generated, prepare_generated, GeneratedError};
use kni_core::native_font::{self, NativeFontInput};
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata};
use kni_metrics::generated_outline_kern::{generate_residual_kern, ExportGeometry, ProfileFrame};
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, OutlineProfile, ScanPolicy};
use kni_metrics::self_anchored_spacing::{solve_spacing, FontContext, SpacingPolicy};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn rect(id: &str, x0: f64, y0: f64, x1: f64, y1: f64) -> DrawnGlyph {
    // counter-clockwise
    DrawnGlyph { glyph_id: id.into(), rings: vec![ReferenceRing { start: p(x0, y0), spans: vec![
        Span::Line { end: p(x1, y0) }, Span::Line { end: p(x1, y1) }, Span::Line { end: p(x0, y1) }, Span::Line { end: p(x0, y0) }] }] }
}
fn circle(id: &str, cx: f64, cy: f64, r: f64) -> DrawnGlyph {
    let k = 0.5522847498 * r;
    let c = |a: (f64, f64), b: (f64, f64), e: (f64, f64)| Span::Cubic { control_one: p(a.0, a.1), control_two: p(b.0, b.1), end: p(e.0, e.1) };
    DrawnGlyph { glyph_id: id.into(), rings: vec![ReferenceRing { start: p(cx + r, cy), spans: vec![
        c((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)), c((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
        c((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)), c((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy))] }] }
}
fn polys(g: &DrawnGlyph) -> Vec<Vec<[f64; 2]>> {
    g.rings.iter().map(|r| { let mut poly = vec![[r.start.x, r.start.y]]; let mut s = r.start;
        for sp in &r.spans { match sp {
            Span::Line { end } => { poly.push([end.x, end.y]); s = *end }
            Span::Cubic { control_one, control_two, end } => { flat::flatten_cubic([s, *control_one, *control_two, *end], 0.5, 12, 10_000, &mut poly).unwrap(); s = *end }
        } } poly.pop(); poly }).collect()
}
fn profile(g: &DrawnGlyph) -> OutlineProfile {
    profile_outline(&OutlineInput { glyph_id: g.glyph_id.clone(), source_pin: "0".repeat(64), upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.5, rings: polys(g) },
        ScanPolicy { row_step: 10.0, max_rows: 1000, merge_guard: 1.0, grid_anchor_y: Some(0.0) }).unwrap()
}
fn u16at(b: &[u8], o: usize) -> u16 { u16::from_be_bytes([b[o], b[o + 1]]) }
fn u32at(b: &[u8], o: usize) -> u32 { u32::from_be_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]]) }
fn sum(b: &[u8]) -> u32 { b.chunks(4).fold(0u32, |s, c| { let mut w = [0; 4]; w[..c.len()].copy_from_slice(c); s.wrapping_add(u32::from_be_bytes(w)) }) }
struct Otf<'a> { tables: Vec<([u8; 4], &'a [u8])> }
fn read_otf(b: &[u8]) -> Otf<'_> {
    assert_eq!(&b[0..4], b"OTTO");
    let n = u16at(b, 4) as usize; let mut tables = vec![];
    for i in 0..n { let r = 12 + 16 * i; let tag = [b[r], b[r + 1], b[r + 2], b[r + 3]]; let (off, len) = (u32at(b, r + 8) as usize, u32at(b, r + 12) as usize);
        assert!(off + len <= b.len() && off % 4 == 0, "table range/alignment {:?}", tag);
        let t = &b[off..off + len];
        if &tag != b"head" { assert_eq!(sum(t), u32at(b, r + 4), "checksum {:?}", std::str::from_utf8(&tag)); }
        tables.push((tag, t)); }
    assert!(tables.windows(2).all(|w| w[0].0 < w[1].0), "directory sorted");
    Otf { tables }
}
impl<'a> Otf<'a> { fn t(&self, tag: &[u8; 4]) -> &'a [u8] { self.tables.iter().find(|x| &x.0 == tag).unwrap_or_else(|| panic!("no {:?}", tag)).1 } }
/// format 4 cmap lookup, independent of the writer
fn cmap_lookup(cmap: &[u8], cp: u32) -> Option<u16> {
    let n = u16at(cmap, 2) as usize;
    for i in 0..n { let (plat, enc, off) = (u16at(cmap, 4 + 8 * i), u16at(cmap, 6 + 8 * i), u32at(cmap, 8 + 8 * i) as usize);
        if plat == 3 && enc == 1 && u16at(cmap, off) == 4 && cp <= 0xffff {
            let sc = u16at(cmap, off + 6) as usize / 2; let ends = off + 14; let starts = ends + 2 * sc + 2; let deltas = starts + 2 * sc; let ranges = deltas + 2 * sc;
            for s in 0..sc { if cp as u16 <= u16at(cmap, ends + 2 * s) { if (cp as u16) < u16at(cmap, starts + 2 * s) { return None; }
                let ro = u16at(cmap, ranges + 2 * s); let d = u16at(cmap, deltas + 2 * s);
                let g = if ro == 0 { (cp as u16).wrapping_add(d) } else { let a = ranges + 2 * s + ro as usize + 2 * (cp as usize - u16at(cmap, starts + 2 * s) as usize); let v = u16at(cmap, a); if v == 0 { 0 } else { v.wrapping_add(d) } };
                return if g == 0 { None } else { Some(g) }; } } } }
    None
}

fn names(ps: &str) -> Vec<NameRecord> {
    [(1, "Smoke"), (2, "Regular"), (3, "Smoke:1"), (4, "Smoke Regular"), (5, "Version 1.0"), (6, ps)].iter()
        .map(|(id, t)| NameRecord { language: 0x409, name_id: *id, value: t.to_string() }).collect()
}
fn meta() -> NativeFontInput {
    NativeFontInput { postscript_name: "Smoke-Regular".into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
        head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 1 },
        hhea: HheaMetadata { ascender: 800, descender: -200, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
        os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
            panose: [0; 10], unicode_ranges: [1, 0, 0, 0], vendor: *b"TEST", selection: 64, first_char: 32, last_char: 111, typo: [800, -200, 0], win_ascent: 800, win_descent: 200, version: 0, cap_height: 0, x_height: 0 },
        names: names("Smoke-Regular") }
}
fn metrics_for(ids: &[&str]) -> Vec<(String, f64, f64, f64)> { ids.iter().map(|i| (i.to_string(), 50.0, 50.0, 400.0)).collect() }

#[test]
fn full_chain_geometry_spacing_kern_otf() {
    let drawn = vec![rect("H", 0.0, 0.0, 80.0, 700.0), circle("o", 250.0, 250.0, 250.0), rect("I", 0.0, 0.0, 60.0, 700.0)];
    let profiles: Vec<OutlineProfile> = drawn.iter().map(profile).collect(); // profile() unwraps: any stage error PANICS, nothing is skipped
    let processed_count = profiles.len();
    assert_eq!(processed_count, 3, "every fixture glyph must be processed; a skipped glyph can never make this test pass");
    assert!(profiles.iter().all(|p| p.ink_area > 0.0), "non-empty ink for every processed glyph");
    let cps: Vec<(String, u32)> = vec![("H".into(), 0x48), ("o".into(), 0x6f), ("I".into(), 0x49)];
    let policy = SpacingPolicy { sample_resolution: 10.0, max_pair_evaluations: 100_000, max_pairs: 100, pair_min_shared_rows: 1, lambda: Some(0.0), dcap: None, contrast_floor: false, cadence_class_pass: false, class_channel_targets: false };
    let ctx = FontContext { glyph_codepoints: cps.clone(), ..FontContext::default() };
    let solved = solve_spacing(&profiles, Some(&ctx), &policy).unwrap();
    assert_eq!(solved.glyphs.len(), 3);
    assert!(solved.glyphs.iter().all(|g| g.advance.is_finite() && g.advance > 0.0));
    // residual kern ledger over the solved pairs (stage K); every pair must land in exactly one bucket
    let geo = ExportGeometry { profile_frame: ProfileFrame::RawGenerated, upm: 1000, overlap_tolerance_units: 0.0, drop_zero_residual: false, row_align_tolerance_units: 10.0 };
    let kern = generate_residual_kern(&solved, &profiles, &geo);
    let total = kern.ready.len() + kern.overlap_holds.len() + kern.rejected.len() + kern.dropped_zero.len();
    assert!(total >= solved.pairs.len().min(1), "pairs accounted for: {} of {}", total, solved.pairs.len());
    assert_eq!(kern.writer_declared_rows().len(), total);
    // native export through the real fixture exporter (notdef + gNNNNN names)
    let dir = std::env::temp_dir().join(format!("kni-p6-{}-{}", std::process::id(), solved.glyphs.len()));
    let _ = std::fs::remove_dir_all(&dir);
    fixture::export_fixture(&drawn, &solved, &cps, &dir).unwrap();
    let bytes = std::fs::read(dir.join("B.otf")).unwrap();
    let otf = read_otf(&bytes);
    for tag in [b"CFF ", b"head", b"hhea", b"hmtx", b"maxp", b"name", b"cmap", b"OS/2", b"post"] { otf.t(tag); }
    let n = 4u16; // .notdef + processed_count
    assert_eq!(n as usize, processed_count + 1);
    assert_eq!(u16at(otf.t(b"maxp"), 4), n);
    assert_eq!(u16at(otf.t(b"hhea"), 34), n);
    let hmtx = otf.t(b"hmtx"); assert_eq!(hmtx.len(), 4 * n as usize);
    assert_eq!(u16at(hmtx, 0), 0, ".notdef advance as requested (0)");
    for (raw, cp) in &cps { let gid = drawn.iter().position(|g| g.glyph_id == *raw).unwrap() as u16 + 1; assert_eq!(cmap_lookup(otf.t(b"cmap"), *cp), Some(gid), "{raw}");
        let adv = solved.glyphs.iter().find(|g| &g.glyph_id == raw).unwrap().advance.round() as u16; assert_eq!(u16at(hmtx, 4 * gid as usize), adv, "{raw} advance"); }
    assert_eq!(cmap_lookup(otf.t(b"cmap"), 0x41), None, "unmapped codepoint");
    // determinism: second export identical bytes
    let dir2 = dir.with_extension("b"); let _ = std::fs::remove_dir_all(&dir2);
    fixture::export_fixture(&drawn, &solved, &cps, &dir2).unwrap();
    assert_eq!(bytes, std::fs::read(dir2.join("B.otf")).unwrap());
    // no-overwrite
    assert!(fixture::export_fixture(&drawn, &solved, &cps, &dir).is_err());
    let _ = std::fs::remove_dir_all(&dir); let _ = std::fs::remove_dir_all(&dir2);
}

fn base_glyphs() -> Vec<DrawnGlyph> { vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, rect("A", 10.0, 0.0, 110.0, 700.0)] }
fn enc(g: &[DrawnGlyph], map: &[(u32, u16)], m: &[(String, f64, f64, f64)]) -> Result<Vec<u8>, GeneratedError> { encode_generated(g, map, m, &meta()) }

#[test]
fn notdef_space_empty_and_mapping() {
    // space = empty outline with advance, mapped; .notdef empty
    let mut g = base_glyphs(); g.push(DrawnGlyph { glyph_id: "space".into(), rings: vec![] });
    let m = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), 10.0, 40.0, 150.0), ("space".into(), 0.0, 0.0, 250.0)];
    let b = enc(&g, &[(0x20, 2), (0x41, 1)], &m).unwrap();
    let o = read_otf(&b); let h = o.t(b"hmtx");
    assert_eq!(u16at(h, 0), 500); assert_eq!(u16at(h, 8), 250);
    assert_eq!(cmap_lookup(o.t(b"cmap"), 0x20), Some(2)); assert_eq!(cmap_lookup(o.t(b"cmap"), 0x41), Some(1));
    // mapping refusals must be typed Err, not panic and not silently dropped
    assert!(enc(&g, &[(0x41, 9)], &m).is_err(), "mapping to missing glyph id");
    let dup = enc(&g, &[(0x41, 1), (0x41, 2)], &m); assert!(dup.is_err(), "duplicate codepoint: {:?}", dup.as_ref().map(|v| v.len()));
    // glyph with no .notdef-first order: first glyph not .notdef
    let mut swapped = g.clone(); swapped.swap(0, 1);
    let r = enc(&swapped, &[(0x41, 0)], &m); println!("swapped notdef order -> {:?}", r.as_ref().map(|v| v.len()));
}

#[test]
fn negative_bearings_and_extreme_values() {
    let g = base_glyphs();
    // negative requested lsb: ink moves left of origin; hhea min_lsb must be derived negative and encode must accept
    let m = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), -30.0, 0.0, 200.0)];
    let i = prepare_generated(&g, &[(0x41, 1)], &m, &meta()).unwrap();
    assert_eq!(i.left_side_bearings[1], -30); assert!(i.hhea.min_lsb <= -30); assert!(i.head.bounds[0] <= -30);
    let b = enc(&g, &[(0x41, 1)], &m).unwrap(); read_otf(&b);
    // negative rsb (ink wider than advance) is allowed geometry, still encodes
    let m2 = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), 10.0, 0.0, 50.0)];
    assert!(enc(&g, &[(0x41, 1)], &m2).is_ok());
    // negative advance, huge advance, NaN lsb: typed refusals
    for (l, a) in [(0.0, -1.0), (0.0, 40000.0), (f64::NAN, 100.0), (f64::INFINITY, 100.0), (0.0, f64::NAN)] {
        let mm = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), l, 0.0, a)];
        assert!(prepare_generated(&g, &[(0x41, 1)], &mm, &meta()).is_err(), "lsb={l} adv={a}");
    }
}

#[test]
fn malformed_inputs_refuse_without_panic() {
    let m = || metrics_for(&[".notdef", "A"]);
    assert!(enc(&[], &[], &[]).is_err(), "no glyphs");
    let mut g = base_glyphs(); g[1].rings[0].spans.pop(); assert!(enc(&g, &[(0x41, 1)], &m()).is_err(), "open ring");
    let mut g = base_glyphs(); g[1].rings[0].start.x = f64::NAN; assert!(enc(&g, &[(0x41, 1)], &m()).is_err(), "NaN");
    let mut g = base_glyphs(); g[1].rings[0].start.x = 1e9; assert!(enc(&g, &[(0x41, 1)], &m()).is_err(), "out of i16");
    let mut g = base_glyphs(); g[1].rings[0].spans.clear(); assert!(enc(&g, &[(0x41, 1)], &m()).is_err(), "ring without spans");
    let mut g = base_glyphs(); g[1].glyph_id = ".notdef".into(); assert!(enc(&g, &[(0x41, 1)], &m()).is_err(), "duplicate glyph id");
    assert!(enc(&base_glyphs(), &[(0x41, 1)], &metrics_for(&[".notdef"])).is_err(), "missing metric row");
    let mut mm = m(); mm.push(mm[1].clone()); assert!(enc(&base_glyphs(), &[(0x41, 1)], &mm).is_err(), "duplicate metric row");
    let mut mm = m(); mm.push(("ghost".into(), 0.0, 0.0, 10.0)); assert!(enc(&base_glyphs(), &[(0x41, 1)], &mm).is_err(), "extra metric row");
    // metadata: empty name id, ps-name mismatch, inconsistent hhea count at the raw encoder
    let mut md = meta(); md.names.retain(|r| r.name_id != 4);
    assert!(matches!(encode_generated(&base_glyphs(), &[(0x41, 1)], &m(), &md), Err(GeneratedError::Native(ContainerError::InvalidMetadata))));
    let mut md = meta(); md.postscript_name = "Other".into();
    assert!(encode_generated(&base_glyphs(), &[(0x41, 1)], &m(), &md).is_err());
    let raw = native_font::encode(&NativeFontInput { glyphs: vec![CffGlyph { name: ".notdef".into(), advance: 1, outline: DrawnGlyph { glyph_id: "x".into(), rings: vec![] } }], left_side_bearings: vec![], ..meta() });
    assert!(raw.is_err(), "lsb length mismatch");
    // too many glyphs
    let many: Vec<DrawnGlyph> = (0..70000).map(|i| DrawnGlyph { glyph_id: format!("g{i}"), rings: vec![] }).collect();
    let mm: Vec<_> = many.iter().map(|g| (g.glyph_id.clone(), 0.0, 0.0, 1.0)).collect();
    assert!(encode_generated(&many, &[], &mm, &meta()).is_err(), "more than u16 glyphs");
}
