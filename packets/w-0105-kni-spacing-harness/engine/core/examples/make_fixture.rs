//! LOCAL TEST SCAFFOLD (not for delivery): builds a fixture OTF with known
//! outlines so ocr_render can be verified against analytic ink areas.
//! .notdef empty; A=U+0041 rect x100..600 y0..700 (area 350000 u^2);
//! O=U+004F outer circle c(325,350) r275 with counter r125 (area pi*60000);
//! space=U+0020 empty. Writes fixture.otf to the path in argv[1].
use kni_core::cff_container::CffGlyph;
use kni_core::ink_bounds::{integer_outward_bounds, union_bounds};
use kni_core::native_font::{encode, NativeFontInput};
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn g(name: &str, advance: u16, rings: Vec<ReferenceRing>) -> CffGlyph {
    CffGlyph { name: name.into(), advance, outline: DrawnGlyph { glyph_id: name.into(), rings } }
}
fn rect_a() -> ReferenceRing {
    ReferenceRing { start: p(100.0, 0.0), spans: vec![
        Span::Line { end: p(600.0, 0.0) }, Span::Line { end: p(600.0, 700.0) },
        Span::Line { end: p(100.0, 700.0) }, Span::Line { end: p(100.0, 0.0) }] }
}
fn circle4(cx: f64, cy: f64, r: f64, cw: bool) -> ReferenceRing {
    let k = (0.5522847498307936 * r).round();
    let (e, n, w, s) = (p(cx + r, cy), p(cx, cy + r), p(cx - r, cy), p(cx, cy - r));
    let spans = if !cw { vec![
        Span::Cubic { control_one: p(cx + r, cy + k), control_two: p(cx + k, cy + r), end: n },
        Span::Cubic { control_one: p(cx - k, cy + r), control_two: p(cx - r, cy + k), end: w },
        Span::Cubic { control_one: p(cx - r, cy - k), control_two: p(cx - k, cy - r), end: s },
        Span::Cubic { control_one: p(cx + k, cy - r), control_two: p(cx + r, cy - k), end: e },
    ] } else { vec![
        Span::Cubic { control_one: p(cx + r, cy - k), control_two: p(cx + k, cy - r), end: s },
        Span::Cubic { control_one: p(cx - k, cy - r), control_two: p(cx - r, cy - k), end: w },
        Span::Cubic { control_one: p(cx - r, cy + k), control_two: p(cx - k, cy + r), end: n },
        Span::Cubic { control_one: p(cx + k, cy + r), control_two: p(cx + r, cy + k), end: e },
    ] };
    ReferenceRing { start: e, spans }
}

fn main() -> Result<(), String> {
    let out = std::env::args().nth(1).ok_or("usage: make_fixture OUT.otf")?;
    let glyphs = vec![
        g(".notdef", 500, vec![]),
        g("A", 700, vec![rect_a()]),
        g("O", 650, vec![circle4(325.0, 350.0, 275.0, false), circle4(325.0, 350.0, 125.0, true)]),
        g("space", 250, vec![]),
    ];
    let mut bounds = None;
    for gl in &glyphs { bounds = union_bounds(bounds, integer_outward_bounds(&gl.outline).map_err(|e| format!("{e:?}"))?); }
    let bounds = bounds.unwrap_or([0; 4]);
    let input = NativeFontInput {
        postscript_name: "KNIOcrFixture-Regular".into(),
        left_side_bearings: vec![0, 100, 50, 0],
        mapping: vec![(0x41, 1), (0x4F, 2), (0x20, 3)],
        head: HeadMetadata { revision: 0x00010000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds, mac_style: 0, lowest_ppem: 8 },
        hhea: HheaMetadata { ascender: 800, descender: -200, line_gap: 0, advance_max: 700, min_lsb: 50, min_rsb: 50, max_extent: 600, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 4 },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
        os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [0; 4], superscript: [0; 4], strikeout: [0; 2], family_class: 0, panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"KNIF", selection: 0, first_char: 0x20, last_char: 0x4F, typo: [800, -200, 0], win_ascent: 800, win_descent: 200, version: 4, cap_height: 700, x_height: 500 },
        names: vec![
            NameRecord { language: 0x409, name_id: 1, value: "KNI OCR Fixture".into() },
            NameRecord { language: 0x409, name_id: 2, value: "Regular".into() },
            NameRecord { language: 0x409, name_id: 3, value: "KNIOcrFixture-Regular;test".into() },
            NameRecord { language: 0x409, name_id: 4, value: "KNI OCR Fixture Regular".into() },
            NameRecord { language: 0x409, name_id: 5, value: "Version 1.0".into() },
            NameRecord { language: 0x409, name_id: 6, value: "KNIOcrFixture-Regular".into() },
        ],
        glyphs,
    };
    let bytes = encode(&input).map_err(|e| format!("encode: {e:?}"))?;
    std::fs::write(&out, &bytes).map_err(|e| format!("write: {e}"))?;
    println!("wrote {out} ({} bytes), bounds {bounds:?}", bytes.len());
    Ok(())
}
