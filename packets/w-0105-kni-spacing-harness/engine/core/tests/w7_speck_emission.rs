//! W7 speck emission contract (fixture ownership: engine-side).
//! Fixture: real Marq/Standard tile marq_g_0067.png - it carries a large
//! speck population: positive-area sub-gate rings (area < 0.5 px^2, the PN-3
//! KEEP+FLAG class, shipped hole-flag-wound as their own minimal contour)
//! plus hairline slivers above the gate (area 0.5056 px^2, span 0.62x1.62 px).
//! Both classes are sub-pixel specks that must reach the OTF.
//!
//! R1: every emitted speck coordinate equals the main emit path's rounding
//!     output (integer half-away + integer lsb shift), not merely integral.
//! R2 (chief ruling W7-R2 (a), 2026-10-17): the emitted speck winding must
//!     equal capture's depth-parity hole classification propagated through
//!     fit+export (hole=true -> CW/negative, hole=false -> CCW/positive);
//!     the engine's winding semantics are unchanged. On this fixture every
//!     surviving speck is depth-odd (hole=true, 211/211; marq_invertedq_00bf
//!     105/105), so the asserted sign is negative here - a fixture property,
//!     not a bug; the landed sub_pixel_speck_retained_hole receipt row is the
//!     run-level evidence. Non-hole exterior speck coverage is a separate
//!     fixture-synthesis task (post-kit).
//! R4: e2e - the speck survives tile -> capture -> fit -> prepare_generated
//!     -> native_font::encode -> OTF -> Type2 charstring decode: contour
//!     present, grid-aligned, winding/hole correct.
//! R5: the landed append-only speck ledger (capture_fit speck areas +
//!     speck_retained_hole, surfaced as sub_pixel_speck_retained /
//!     sub_pixel_speck_retained_hole receipt rows) pinned on this fixture.

use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::capture_source;
use kni_core::capture_fit::fit_captured;
use kni_core::cff_container::CffGlyph;
use kni_core::cubic_fit::FitPolicy;
use kni_core::generated_native::prepare_generated;
use kni_core::jpeg_source::Limits;
use kni_core::native_font::{self, NativeFontInput};
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, PostMetadata, Os2Metadata, NameRecord};
use kni_core::reference_slice::{DrawnGlyph, Point, Span};

const MARQ_SCALE: f64 = 1.9651741293532339;

fn ring_points(r: &kni_core::reference_slice::ReferenceRing) -> Vec<Point> {
    // flattened control-polygon points (on-curve only: start + span ends)
    let mut v = vec![r.start];
    for s in &r.spans {
        match s { Span::Line { end } => v.push(*end), Span::Cubic { end, .. } => v.push(*end) }
    }
    v
}

fn signed_area2(pts: &[Point]) -> f64 {
    let mut a = 0.0;
    for i in 0..pts.len() {
        let p = pts[i]; let q = pts[(i + 1) % pts.len()];
        a += p.x * q.y - q.x * p.y;
    }
    a
}

fn capture_area2(pts: &[Point]) -> f64 { signed_area2(pts).abs() }

struct SpeckCase { _fitted_index: usize, _capture_area_px2: f64 }

struct FixtureFit {
    glyph: DrawnGlyph,
    specks: Vec<SpeckCase>,
    src: kni_core::capture_dispatch::CapturedSource,
    /// kept capture-ring indices (non-degenerate), in fitted-ring order.
    kept: Vec<usize>,
}
/// Emitted-side speck test: a ring whose emitted control polygon is tiny.
/// (Ring ORDER is not stable across processes - HashMap-seeded fit internals -
/// so the emitted speck set is selected by geometry, never by index.)
fn is_emitted_speck(r: &kni_core::reference_slice::ReferenceRing) -> bool {
    let pts = ring_points(r);
    let a = signed_area2(&pts).abs();
    a > 0.0 && a < 100.0
}

fn fit_g() -> FixtureFit {
    let png = include_bytes!("fixtures/marq_g_0067.png");
    let png_limits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let src = capture_source(png, 0.25, &png_limits, jpeg_limits).expect("capture");
    // v3 KEEP+FLAG: the gate classifies, it does not drop; a capture ring
    // ships iff it has a grid representation. Dropped classes: zero-area
    // 1/2-point traces (normal path, no fit) and post-round grid-collapsed
    // specks. Map fitted rings back to capture rings by simulating the same
    // scan: representable = not in either dropped class.
    let scale = MARQ_SCALE;
    let representable = |r: &kni_core::capture::CapturedRing| -> bool {
        let area = kni_core::capture::ring_area2(&r.points).abs();
        if area > 0.0 && kni_core::capture::is_degenerate_ring(&r.points) {
            // speck path: post-round single-point / zero-area collapse drops
            let pts: Vec<Point> = r.points.iter()
                .map(|p| Point { x: (p.x * scale).round(), y: (p.y * scale).round() }).collect();
            let start = pts[0];
            if pts.iter().all(|p| *p == start) { return false; }
            if kni_core::capture::ring_area2(&pts) == 0.0 { return false; }
            return true;
        }
        if area == 0.0 {
            // zero-area trace: 1/2-point traces have no representation;
            // a collinear streak with >=3 distinct points goes to the guard
            let mut u = r.points.clone();
            u.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap().then(a.y.partial_cmp(&b.y).unwrap()));
            u.dedup();
            return u.len() >= 3;
        }
        true
    };
    let kept: Vec<usize> = src.contour.rings.iter().enumerate()
        .filter(|(_, r)| representable(r))
        .map(|(i, _)| i).collect();
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let (fitted, _n, _fb, dropped) = fit_captured(&src.contour.rings, MARQ_SCALE, &policy);
    assert_eq!(fitted.len(), kept.len(),
        "one fitted ring per representable capture ring (dropped={dropped})");
    let mut specks = Vec::new();
    for (fi, &ci) in kept.iter().enumerate() {
        let a = capture_area2(&src.contour.rings[ci].points) / 2.0;
        let pts = &src.contour.rings[ci].points;
        let (mut x0, mut y0, mut x1, mut y1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for p in pts { x0 = x0.min(p.x); y0 = y0.min(p.y); x1 = x1.max(p.x); y1 = y1.max(p.y); }
        let subpx = (x1 - x0) < 1.0 || (y1 - y0) < 1.0;
        if subpx && a > 0.0 && a < 4.0 { specks.push(SpeckCase { _fitted_index: fi, _capture_area_px2: a }); }
    }
    FixtureFit { glyph: DrawnGlyph { glyph_id: "g".into(), rings: fitted }, specks, src, kept }
}

fn meta() -> NativeFontInput {
    NativeFontInput { postscript_name: "W7Speck-Regular".into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
        head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 1 },
        hhea: HheaMetadata { ascender: 800, descender: -200, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
        os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
            panose: [0; 10], unicode_ranges: [1, 0, 0, 0], vendor: *b"W7FX", selection: 64, first_char: 32, last_char: 111, typo: [800, -200, 0], win_ascent: 800, win_descent: 200, version: 0, cap_height: 0, x_height: 0 },
        names: [(1, "W7Speck"), (2, "Regular"), (3, "W7Speck:1"), (4, "W7Speck Regular"), (5, "Version 1.0"), (6, "W7Speck-Regular")].iter()
            .map(|(id, t)| NameRecord { language: 0x409, name_id: *id, value: t.to_string() }).collect() }
}

// Minimal Type2 charstring walker for the byte shapes charstring() emits:
// numbers (28 int16 / 29 int32 / 32..246 / 247..254), ops 21 rmoveto,
// 5 rlineto, 8 rrcurveto, 14 endchar.
fn decode_charstring(b: &[u8]) -> Vec<Vec<Point>> {
    let mut i = 0usize; let mut stack: Vec<f64> = Vec::new(); let mut rings: Vec<Vec<Point>> = Vec::new();
    let mut cur = Point { x: 0.0, y: 0.0 }; let mut ring: Vec<Point> = Vec::new(); let mut first = true;
    while i < b.len() {
        let op = b[i]; i += 1;
        match op {
            28 => { stack.push(i16::from_be_bytes([b[i], b[i + 1]]) as f64); i += 2; }
            29 => { stack.push(i32::from_be_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]) as f64); i += 4; }
            32..=246 => stack.push(op as f64 - 139.0),
            247..=250 => { stack.push((op as f64 - 247.0) * 256.0 + b[i] as f64 + 108.0); i += 1; }
            251..=254 => { stack.push(-(op as f64 - 251.0) * 256.0 - b[i] as f64 - 108.0); i += 1; }
            21 => { let (dx, dy) = (stack[stack.len() - 2], stack[stack.len() - 1]); stack.clear();
                    cur = Point { x: cur.x + dx, y: cur.y + dy };
                    if !first { rings.push(std::mem::take(&mut ring)); }
                    first = false; ring.push(cur); }
            5 => { let (dx, dy) = (stack[stack.len() - 2], stack[stack.len() - 1]); stack.clear();
                   cur = Point { x: cur.x + dx, y: cur.y + dy }; ring.push(cur); }
            8 => { let n = stack.len();
                   for k in (0..n).step_by(2) { cur = Point { x: cur.x + stack[k], y: cur.y + stack[k + 1] }; }
                   stack.clear(); ring.push(cur); }
            14 => { rings.push(std::mem::take(&mut ring)); break; }
            other => panic!("unexpected Type2 op {other}"),
        }
    }
    rings
}

fn exported_glyphs() -> (Vec<CffGlyph>, FixtureFit) {
    let fx = fit_g();
    assert!(!fx.specks.is_empty(), "fixture tile must carry surviving specks (selection loop: marq_g_0067)");
    let notdef = DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] };
    let glyphs = vec![notdef, fx.glyph.clone()];
    let metrics: Vec<(String, f64, f64, f64)> = vec![
        (".notdef".into(), 0.0, 0.0, 500.0),
        ("g".into(), 20.0, 20.0, 600.0)];
    let mapping = vec![(0x67u32, 1u16)];
    let prepared = prepare_generated(&glyphs, &mapping, &metrics, &meta()).expect("prepare_generated");
    (vec![prepared.glyphs[0].clone(), prepared.glyphs[1].clone()], fx)
}

#[test]
fn r4_speck_survives_to_otf_grid_aligned_exterior() {
    let (prepared, fx) = exported_glyphs();
    let fitted = &fx.glyph;
    let prepared_full = prepare_generated(&[DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, fitted.clone()],
        &vec![(0x67u32, 1u16)],
        &vec![(".notdef".to_string(), 0.0, 0.0, 500.0), ("g".to_string(), 20.0, 20.0, 600.0)],
        &meta()).expect("prepare_generated(full)");
    let otf = native_font::encode(&prepared_full).expect("encode");
    assert!(otf.len() > 100, "OTF bytes produced");
    let eg = &prepared[1].outline; // glyph g
    let fe = &fitted.rings;
    let specks = &fx.specks;
    // emitted ring count equals fitted ring count (no silent speck drop)
    assert_eq!(eg.rings.len(), fe.len(), "speck contour must survive to the OTF-bound outline");
    // dominant exterior ring winding (largest |area|)
    let mut main = 0usize; let mut best = 0.0f64;
    for (i, r) in eg.rings.iter().enumerate() {
        let a = signed_area2(&ring_points(r)).abs();
        if a > best { best = a; main = i; }
    }
    let exterior_sign = signed_area2(&ring_points(&eg.rings[main])).signum();
    assert_eq!(exterior_sign, 1.0, "dominant exterior ring is CCW (capture depth-parity, y-up)");
    let emitted_specks: Vec<usize> = eg.rings.iter().enumerate()
        .filter(|(_, r)| is_emitted_speck(r)).map(|(i, _)| i).collect();
    assert!(!emitted_specks.is_empty(), "speck contours must survive to the OTF-bound outline");
    eprintln!("capture-side surviving specks: {} emitted-side tiny rings: {}", specks.len(), emitted_specks.len());
    // R1 + R2 in one pass: match each emitted speck back to its fitted ring
    // by the main-path rounding identity (R1: exactly one candidate), then
    // read the capture hole flag through the kept-index chain and require the
    // emitted winding to equal it (R2 ruling (a): hole=true -> negative).
    let mut expected_sign: std::collections::HashMap<usize, f64> = std::collections::HashMap::new();
    for &si in &emitted_specks {
        let r = &eg.rings[si];
        assert!(!r.spans.is_empty(), "speck {si}: contour present");
        for p in ring_points(r).iter() {
            assert_eq!(p.x.fract(), 0.0, "grid-aligned x");
            assert_eq!(p.y.fract(), 0.0, "grid-aligned y");
        }
        // R1: at least one fitted ring must reproduce the emitted integers
        // under the main-path rounding (the MARQ dash-sliver class carries
        // same-shape repeats, so uniqueness is NOT required; every candidate
        // shares the shape, hence the rounding output and the hole class).
        let cand: Vec<usize> = fe.iter().enumerate().filter(|(_, fr)| {
            let shift_x = r.start.x - fr.start.x.round();
            ring_points(r).iter().zip(ring_points(fr).iter()).all(|(p, q)|
                p.x == (q.x + shift_x).round() && p.y == q.y.round())
        }).map(|(i, _)| i).collect();
        assert!(!cand.is_empty(), "speck {si}: a fitted ring matches the main-path rounding output");
        let holes: std::collections::BTreeSet<bool> =
            cand.iter().map(|&ci| fx.src.contour.rings[fx.kept[ci]].hole).collect();
        assert_eq!(holes.len(), 1, "speck {si}: same-shape candidates share one hole class");
        let hole = holes.into_iter().next().unwrap();
        let expect = if hole { -1.0 } else { 1.0 };
        expected_sign.insert(si, expect);
        assert_eq!(signed_area2(&ring_points(r)).signum(), expect,
                   "speck {si}: emitted winding == capture hole flag (hole={hole})");
    }
    // OTF-level: decode the g charstring from the encoded font bytes.
    let text = String::from_utf8_lossy(&otf);
    let _ = text; // directory walk below uses raw bytes
    let rings = decode_from_otf(&otf, 1);
    assert_eq!(rings.len(), eg.rings.len(), "charstring contour count survives the OTF round trip");
    let otf_specks: Vec<usize> = rings.iter().enumerate()
        .filter(|(_, rr)| { let a = signed_area2(rr).abs(); a > 0.0 && a < 100.0 })
        .map(|(i, _)| i).collect();
    assert_eq!(otf_specks.len(), emitted_specks.len(), "speck contours survive the OTF byte round trip");
    for &si in &otf_specks {
        let rr = &rings[si];
        assert!(rr.len() >= 2, "speck {si}: decoded contour present in OTF charstring");
        for p in rr { assert_eq!(p.x.fract(), 0.0); assert_eq!(p.y.fract(), 0.0); }
        let expect = expected_sign[&si];
        assert_eq!(signed_area2(rr).signum(), expect, "speck {si}: OTF winding == capture hole flag");
    }
}

fn decode_from_otf(otf: &[u8], glyph_index: usize) -> Vec<Vec<Point>> {
    // locate the CharStrings INDEX inside the CFF table: walk the sfnt directory.
    let u16at = |o: usize| u16::from_be_bytes([otf[o], otf[o + 1]]) as usize;
    let u32at = |o: usize| u32::from_be_bytes([otf[o], otf[o + 1], otf[o + 2], otf[o + 3]]) as usize;
    let num_tables = u16at(4);
    let mut cff = None;
    for t in 0..num_tables {
        let o = 12 + 16 * t;
        if &otf[o..o + 4] == b"CFF " { cff = Some((u32at(o + 8), u32at(o + 12))); }
    }
    let (cff_off, _cff_len) = cff.expect("CFF table");
    // CFF: header, Name INDEX, Top DICT INDEX, String INDEX, GlobalSubr INDEX, then
    // charset/Encoding/CharStrings per Top DICT. This fixture's writer emits a fixed
    // layout; walk INDEXes generically and take CharStrings offset from the top dict.
    let rd_index = |mut o: usize| -> (Vec<(usize, usize)>, usize) {
        let count = u16at(o); o += 2;
        if count == 0 { return (vec![], o); }
        let offsize = otf[o] as usize; o += 1;
        let mut offs = Vec::with_capacity(count + 1);
        for _ in 0..=count {
            let mut v = 0usize;
            for _ in 0..offsize { v = v * 256 + otf[o] as usize; o += 1; }
            offs.push(v);
        }
        let data = o;
        let spans = (0..count).map(|i| (data + offs[i] - 1, data + offs[i + 1] - 1)).collect();
        (spans, data + offs[count] - 1)
    };
    let mut o = cff_off + otf[cff_off + 2] as usize; // header size byte
    let (_names, no) = rd_index(o); o = no;
    let (topdicts, _) = rd_index(o);
    // find CharStrings offset (op 17) in the top dict
    let (tds, tde) = topdicts[0];
    let mut cs_off = None;
    let mut i = tds;
    while i < tde {
        let b = otf[i]; i += 1;
        match b {
            28 => i += 2,
            29 => { let _v = i32::from_be_bytes([otf[i], otf[i+1], otf[i+2], otf[i+3]]); i += 4; }
            32..=246 => {}
            247..=254 => i += 1,
            17 => { // CharStrings op: value is last number on stack; re-scan for it
                    let _ = &mut cs_off; }
            _ => {}
        }
        if b == 17 { // operand is the number just before op; re-read backwards is fragile:
            // instead: scan forward collecting operand values
            let mut val = None; let mut j = tds;
            while j < tde {
                let c = otf[j]; j += 1;
                match c {
                    28 => { val = Some(i16::from_be_bytes([otf[j], otf[j + 1]]) as i32 as usize); j += 2; }
                    29 => { val = Some(i32::from_be_bytes([otf[j], otf[j+1], otf[j+2], otf[j+3]]) as usize); j += 4; }
                    32..=246 => val = Some(c as usize - 139),
                    247..=250 => { val = Some((c as usize - 247) * 256 + otf[j] as usize + 108); j += 1; }
                    251..=254 => { val = Some((c as usize - 251) * 256 + otf[j] as usize + 108); j += 1; }
                    17 => { cs_off = val; break; }
                    _ => {}
                }
            }
            break;
        }
    }
    let cs_off = cff_off + cs_off.expect("CharStrings offset");
    let (strings, _end) = rd_index(cs_off);
    let (s, e) = strings[glyph_index];
    decode_charstring(&otf[s..e])
}

#[test]
fn r1_r2_speck_emit_matches_main_rounding_and_capture_winding() {
    // Covered inside the e2e above; kept as a named surface so the contract
    // failure message names the rule.
    r4_speck_survives_to_otf_grid_aligned_exterior();
}

/// R5: the landed v3 speck ledger (capture_fit::speck_areas_since +
/// speck_retained_hole, surfaced as the sub_pixel_speck_retained /
/// sub_pixel_speck_retained_hole receipt rows) pinned on the fixture tile.
/// Pins measured on base 7d09dd9 (speck v3 + fill-lane) at the Marq run
/// capture (eps 0.25, iso 0.5).
#[test]
fn r5_speck_ledger_pinned_on_fixture() {
    let png = include_bytes!("fixtures/marq_g_0067.png");
    let png_limits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let src = capture_source(png, 0.25, &png_limits, jpeg_limits).expect("capture");
    kni_core::capture_fit::reset_speck_areas();
    kni_core::capture_fit::reset_speck_retained_hole();
    kni_core::capture_fit::reset_speck_dropped_collapse();
    let marker = kni_core::capture_fit::speck_marker();
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let (_f, _n, _fb, dropped) = fit_captured(&src.contour.rings, MARQ_SCALE, &policy);
    let areas = kni_core::capture_fit::speck_areas_since(marker);
    assert_eq!(areas.len(), 194, "KEEP+FLAG retained specks (capture-space area ledger)");
    // Chief ruling: retained_hole counts RETAINED hole specks only (the
    // counter increments after the grid-collapse checks), so it equals the
    // areas ledger length on this all-hole fixture; the 42 collapsed specks
    // are the typed dropped class (reason post_round_collapse). Classified
    // total 236 = 194 retained + 42 dropped.
    assert_eq!(kni_core::capture_fit::speck_retained_hole(), 194,
        "hole-flagged retained specks (sub_pixel_speck_retained_hole)");
    assert_eq!(kni_core::capture_fit::speck_dropped_collapse(), 42,
        "post-round grid-collapsed specks (sub_pixel_speck_dropped, reason post_round_collapse)");
    assert_eq!(dropped, 117, "zero-area traces (75) + post-round grid-collapsed specks (42)");
}
