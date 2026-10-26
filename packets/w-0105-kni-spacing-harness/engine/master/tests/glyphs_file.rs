//! Serializer tests for the `.glyphs` parts master.
//!
//! Two layers of checking, per the acceptance rule that an own-parser
//! round-trip alone hid the legacy-scalar format mismatch:
//!
//! 1. Schema-shape assertions on the emitted text: `.formatVersion = 3`,
//!    top-level ordered `metrics` registry, per-master `metricValues`,
//!    master `name`, `unitsPerEm`, `versionMajor`/`versionMinor`, and the
//!    absence of the legacy scalar master fields (`ascender = 850` style),
//!    which Glyphs 3/4 ignores.
//! 2. Exact write/read parity on the reread twin: glyph order, contour
//!    (part) order, node coordinates and types, widths, cmap, metrics,
//!    masters, axes, instances, properties.
//!
//! Third-party validation (glyphsLib load/save) is run outside cargo; see
//! the slice report.

use kni_master::fixture;
use kni_master::glyphs_file::{
    self, ComponentAlignment, GlyphsAxis, GlyphsComponent, GlyphsFont, GlyphsGlyph, GlyphsInstance,
    GlyphsKerning, GlyphsLayer, GlyphsMaster, GlyphsProperty, GlyphsShape, KerningPair, MetricValue,
    WriteError,
};
use kni_master::model::{MasterGlyph, StrokeContour};

fn metric_types() -> Vec<String> {
    vec!["ascender".into(), "cap height".into(), "x-height".into(), "baseline".into(), "descender".into()]
}

fn master(id: &str, name: &str) -> GlyphsMaster {
    GlyphsMaster {
        id: id.into(),
        name: name.into(),
        axes_values: vec![100.0, 100.0],
        metrics: vec![
            MetricValue { pos: 850.0, over: None },
            MetricValue { pos: 700.0, over: Some(10.0) },
            MetricValue { pos: 500.0, over: Some(10.0) },
            MetricValue { pos: 0.0, over: None },
            MetricValue { pos: -145.0, over: Some(-15.0) },
        ],
    }
}

fn axes() -> Vec<GlyphsAxis> {
    vec![
        GlyphsAxis { name: "Weight".into(), tag: "wght".into() },
        GlyphsAxis { name: "Width".into(), tag: "wdth".into() },
    ]
}

fn font_with(glyphs: Vec<(MasterGlyph, Vec<u32>)>) -> GlyphsFont {
    GlyphsFont {
        family_name: "Serializer Test".into(),
        upm: 1000,
        version: (1, 2),
        app_version: None,
        axes: axes(),
        metric_types: metric_types(),
        masters: vec![master("m01", "Regular")],
        glyphs: glyphs
            .into_iter()
            .map(|(g, unicode)| GlyphsGlyph {
                name: g.name.clone(),
                unicode,
                layers: vec![GlyphsLayer::from_master_glyph("m01", &g)],
                export: true,
            })
            .collect(),
        instances: vec![],
        kerning: glyphs_file::GlyphsKerning::default(),
        properties: vec![],
    }
}

fn reference_r() -> MasterGlyph {
    fixture::parse(include_str!("fixtures/reference_r.glyph")).expect("reference R fixture")
}

fn rect(stroke: &str, x0: f64, y0: f64, x1: f64, y1: f64) -> MasterGlyph {
    use kni_master::model::Op;
    MasterGlyph {
        name: stroke.into(),
        advance: 600.0,
        upm: 1000.0,
        contours: vec![StrokeContour {
            stroke: stroke.into(),
            ops: vec![
                Op::Move((x0, y0)),
                Op::Line((x1, y0)),
                Op::Line((x1, y1)),
                Op::Line((x0, y1)),
                Op::Close,
            ],
        }],
    }
}

#[test]
fn reference_r_parts_roundtrip_exact() {
    let font = font_with(vec![(reference_r(), vec![0x52])]);
    let text = glyphs_file::write(&font).expect("write");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    let layer = &back.glyphs[0].layers[0];
    assert_eq!(layer.shapes.len(), 3, "one shape per part, unmerged");
    let names: Vec<&str> = layer
        .shapes
        .iter()
        .map(|s| match s {
            GlyphsShape::Path(c) => c.stroke.as_str(),
            GlyphsShape::Component(_) => panic!("unexpected component"),
        })
        .collect();
    assert_eq!(names, ["bowl", "leg", "stem"], "part order and names preserved");
}

#[test]
fn schema_shape_carries_metrics_and_master_name() {
    let font = font_with(vec![(reference_r(), vec![0x52])]);
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains(".formatVersion = 3;"), "format header");
    assert!(text.contains("unitsPerEm = 1000;"), "upm");
    assert!(text.contains("versionMajor = 1;"), "version from input");
    assert!(text.contains("versionMinor = 2;"), "version from input");
    assert!(text.contains("name = \"Regular\";"), "master name present");
    // Legacy scalar master fields are Glyphs 2; Glyphs 3/4 ignores them.
    assert!(!text.contains("capHeight"), "no legacy capHeight scalar");
    assert!(!text.contains("xHeight"), "no legacy xHeight scalar");
    assert!(!text.contains("\nascender = "), "no legacy ascender scalar");
    assert!(!text.contains("\ndescender = "), "no legacy descender scalar");
    // Ordered metrics registry, chief's order.
    let order = ["type = \"ascender\";", "type = \"cap height\";", "type = \"x-height\";", "type = \"baseline\";", "type = \"descender\";"];
    let mut at = 0;
    for key in order {
        let i = text[at..].find(key).unwrap_or_else(|| panic!("registry entry {key} missing"));
        at += i + key.len();
    }
    // metricValues in registry order: 850, 700, 500, 0, -145.
    let mv = text.find("metricValues = (").expect("metricValues present");
    let mv_end = text[mv..].find(");\n").map(|e| mv + e).expect("metricValues end");
    let block = &text[mv..mv_end];
    for pos in ["pos = 850;", "pos = 700;", "pos = 500;", "pos = 0;", "pos = -145;"] {
        assert!(block.contains(pos), "metric value {pos} missing");
    }
    // Overshoots only where measured: the registry has 5 entries, 3 overs.
    assert_eq!(block.matches("over = ").count(), 3, "no blind overshoot zeros");
    assert!(text.contains("width = 436;"), "layer width from advance");
    assert!(text.contains("unicode = 82;"), "cmap as decimal code point");
}

#[test]
fn multi_master_layers_and_metrics_link() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    let mut bold = master("m02", "Bold");
    bold.metrics[0].pos = 900.0;
    font.masters.push(bold);
    let r = reference_r();
    font.glyphs[0].layers.push(GlyphsLayer::from_master_glyph("m02", &r));
    let text = glyphs_file::write(&font).expect("write");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    assert_eq!(back.glyphs[0].layers.len(), 2);
    assert_eq!(back.glyphs[0].layers[1].master_id, "m02");
    assert_eq!(back.masters[1].metrics[0].pos, 900.0);
}

#[test]
fn cmap_forms_roundtrip() {
    let font = font_with(vec![
        (rect(".notdef", 0.0, 0.0, 500.0, 700.0), vec![]),
        (rect("A", 0.0, 0.0, 500.0, 700.0), vec![0x41]),
        (rect("fi", 0.0, 0.0, 500.0, 700.0), vec![0xFB01]),
        (rect("double", 0.0, 0.0, 500.0, 700.0), vec![0xC0, 0x1F600]),
    ]);
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains("unicode = 65;"), "single code point as decimal");
    assert!(text.contains("unicode = (192,128512);"), "multiple code points as decimal array");
    assert!(text.contains("unicode = 64257;"), "above-FFFF-safe decimal");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    assert!(back.glyphs[0].unicode.is_empty(), ".notdef stays unencoded");
}

#[test]
fn fractional_and_negative_coordinates_roundtrip_exactly() {
    use kni_master::model::Op;
    let mut g = rect("frac", 0.0, 0.0, 500.0, 700.0);
    g.contours = vec![StrokeContour {
        stroke: "s".into(),
        ops: vec![
            Op::Move((61.5, -0.125)),
            Op::Curve((100.25, 200.75), (300.125, 400.5), (377.25, 471.0)),
            Op::Line((-12.5, 0.0)),
            Op::Close,
        ],
    }];
    let font = font_with(vec![(g, vec![])]);
    let text = glyphs_file::write(&font).expect("write");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    let ops_of = |l: &GlyphsLayer| match &l.shapes[0] {
        GlyphsShape::Path(c) => c.ops.clone(),
        GlyphsShape::Component(_) => panic!("unexpected component"),
    };
    assert_eq!(ops_of(&font.glyphs[0].layers[0]), ops_of(&back.glyphs[0].layers[0]));
}

#[test]
fn write_is_deterministic_and_idempotent() {
    let font = font_with(vec![(reference_r(), vec![0x52])]);
    let a = glyphs_file::write(&font).expect("write a");
    let b = glyphs_file::write(&font).expect("write b");
    assert_eq!(a, b, "deterministic");
    let back = glyphs_file::read(&a).expect("read");
    let c = glyphs_file::write(&back).expect("rewrite");
    assert_eq!(a, c, "write-read-write is the identical text");
}

#[test]
fn instances_and_properties_roundtrip() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    font.instances = vec![
        GlyphsInstance {
            name: "Regular".into(),
            axes_values: vec![100.0, 100.0],
            exports: true,
            weight_class: Some(400),
            width_class: Some(5),
            is_bold: Some(false),
            is_italic: Some(false),
        },
        GlyphsInstance {
            name: "Draft".into(),
            axes_values: vec![150.0, 100.0],
            exports: false,
            weight_class: None,
            width_class: None,
            is_bold: None,
            is_italic: None,
        },
    ];
    font.properties = vec![
        GlyphsProperty { key: "designers".into(), value: "Source Designer".into() },
        GlyphsProperty { key: "copyrights".into(), value: "From source only".into() },
    ];
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains("exports = 0;"), "non-exporting instance marked");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    assert_eq!(back.instances[1].exports, false);
}

#[test]
fn typed_errors_not_silent_files() {
    use kni_master::model::Op;
    // Open contour.
    let mut g = rect("open", 0.0, 0.0, 1.0, 1.0);
    g.contours[0].ops.pop();
    let err = glyphs_file::write(&font_with(vec![(g, vec![])])).unwrap_err();
    assert!(matches!(err, WriteError::OpenContour { .. }));
    // Missing master name.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 1.0, 1.0), vec![])]);
    font.masters[0].name.clear();
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyMasterName);
    // Metric count mismatch with the registry.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 1.0, 1.0), vec![])]);
    font.masters[0].metrics.pop();
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::MetricCountMismatch { .. }));
    // Move not first.
    let mut g = rect("bad", 0.0, 0.0, 1.0, 1.0);
    g.contours = vec![StrokeContour { stroke: "s".into(), ops: vec![Op::Line((0.0, 0.0)), Op::Close] }];
    assert!(matches!(glyphs_file::write(&font_with(vec![(g, vec![])])).unwrap_err(), WriteError::MoveNotFirst { .. }));
}

#[test]
fn reader_rejects_outside_subset_with_typed_errors() {
    // Quadratic nodes are outside the emitted subset.
    let text = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    let q = text.replacen("(300,338,o),", "(300,338,q),", 1);
    assert!(matches!(glyphs_file::read(&q), Err(glyphs_file::ParseError::Unsupported(_))));
    // Format 2 files are a different node layout.
    let v2 = text.replacen(".formatVersion = 3;", ".formatVersion = 2;", 1);
    assert!(matches!(glyphs_file::read(&v2), Err(glyphs_file::ParseError::Unsupported(_))));
    // Components are outside the master-parts subset.
    let comp = text.replacen("closed = 1;\nnodes = (\n(258,338,l)", "ref = stem;\nclosed = 1;\nnodes = (\n(258,338,l)", 1);
    assert!(matches!(glyphs_file::read(&comp), Err(glyphs_file::ParseError::Unsupported(_))));
}

#[test]
fn legacy_paths_key_and_comments_read() {
    // Glyphs writes `shapes`; older files and the previous writer use
    // `paths`. Both parse; comments and extra keys are tolerated.
    let text = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    let legacy = text.replacen("shapes = (", "paths = (", 1);
    let commented = format!("// header comment\n{}", legacy.replace("glyphs = (", "glyphs = ( /* mid */"));
    let back = glyphs_file::read(&commented).expect("read legacy");
    assert_eq!(back.glyphs[0].layers[0].shapes.len(), 3);
}

#[test]
fn glyph_order_is_caller_data_and_preserved() {
    // The serializer never reorders, groups or deduplicates: the producer
    // owns source-backed ordering. Names need no category to round-trip.
    let font = font_with(vec![
        (rect("percent", 0.0, 0.0, 1.0, 1.0), vec![0x25]),
        (rect("A", 0.0, 0.0, 1.0, 1.0), vec![0x41]),
        (rect("one", 0.0, 0.0, 1.0, 1.0), vec![0x31]),
        (rect("A.alt", 0.0, 0.0, 1.0, 1.0), vec![]),
    ]);
    let back = glyphs_file::read(&glyphs_file::write(&font).expect("write")).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    let names: Vec<&str> = back.glyphs.iter().map(|g| g.name.as_str()).collect();
    assert_eq!(names, ["percent", "A", "one", "A.alt"], "caller order preserved verbatim");
}

// -------------------------------------------------------------------------
// negatives: strict write validation and strict read
// -------------------------------------------------------------------------

use kni_master::glyphs_file::ParseError;
use kni_master::model::Op;

fn contour_with(ops: Vec<Op>) -> MasterGlyph {
    MasterGlyph { name: "g".into(), advance: 600.0, upm: 1000.0, contours: vec![StrokeContour { stroke: "s".into(), ops }] }
}

#[test]
fn mid_stream_close_and_degenerate_contours_rejected() {
    // Move,Line,Close,Line,Close would silently merge two subpaths.
    let g = contour_with(vec![
        Op::Move((0.0, 0.0)), Op::Line((10.0, 0.0)), Op::Close,
        Op::Line((20.0, 0.0)), Op::Close,
    ]);
    let err = glyphs_file::write(&font_with(vec![(g, vec![])])).unwrap_err();
    assert!(matches!(err, WriteError::CloseNotFinal { .. } | WriteError::TooFewSegments { .. }));
    // Two on-curve nodes: degenerate, area-less.
    let g = contour_with(vec![Op::Move((0.0, 0.0)), Op::Line((10.0, 0.0)), Op::Close]);
    assert!(matches!(
        glyphs_file::write(&font_with(vec![(g, vec![])])).unwrap_err(),
        WriteError::TooFewSegments { .. }
    ));
    // A final-Close contour with a mid Close and enough nodes still fails.
    let g = contour_with(vec![
        Op::Move((0.0, 0.0)), Op::Line((10.0, 0.0)), Op::Line((10.0, 10.0)), Op::Close,
        Op::Line((20.0, 0.0)), Op::Close,
    ]);
    assert!(matches!(
        glyphs_file::write(&font_with(vec![(g, vec![])])).unwrap_err(),
        WriteError::CloseNotFinal { .. }
    ));
}

#[test]
fn non_finite_values_rejected_at_write() {
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.glyphs[0].layers[0].advance = f64::NAN;
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::NonFiniteAdvance { .. }));
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.masters[0].axes_values[0] = f64::INFINITY;
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::NonFiniteAxisValue { .. }));
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.instances.push(GlyphsInstance { name: "I".into(), axes_values: vec![f64::NAN, 100.0], exports: true, weight_class: None, width_class: None, is_bold: None, is_italic: None });
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::NonFiniteAxisValue { .. }));
}

#[test]
fn cmap_validation_at_write() {
    // Same code point on two glyphs.
    let font = font_with(vec![
        (rect("A", 0.0, 0.0, 10.0, 10.0), vec![0x41]),
        (rect("A2", 0.0, 0.0, 10.0, 10.0), vec![0x41]),
    ]);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::CodepointConflict { value: 0x41, .. }));
    // Duplicate inside one glyph.
    let font = font_with(vec![(rect("A", 0.0, 0.0, 10.0, 10.0), vec![0x41, 0x41])]);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::DuplicateCodepoint { .. }));
    // Surrogate and out-of-range.
    let font = font_with(vec![(rect("s", 0.0, 0.0, 10.0, 10.0), vec![0xD800])]);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::InvalidCodepoint { .. }));
    let font = font_with(vec![(rect("s", 0.0, 0.0, 10.0, 10.0), vec![0x110000])]);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::InvalidCodepoint { .. }));
}

#[test]
fn structure_validation_at_write() {
    // Missing layer for a master.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.masters.push(master("m02", "Bold"));
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::MissingMasterLayer { .. }));
    // Duplicate layer for a master.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    let dup = font.glyphs[0].layers[0].clone();
    font.glyphs[0].layers.push(dup);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::DuplicateLayerForMaster { .. }));
    // Empty ids / family / axes.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.family_name.clear();
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyFamilyName);
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.masters[0].id.clear();
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyMasterId);
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.axes[0].tag.clear();
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyAxisTag);
    // UPM range.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.upm = 0;
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::UpmOutOfRange { .. }));
    // Instance axes count.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.instances.push(GlyphsInstance { name: "I".into(), axes_values: vec![100.0], exports: true, weight_class: None, width_class: None, is_bold: None, is_italic: None });
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::InstanceAxesCountMismatch { .. }));
    // Mixed-geometry upm via from_master_glyph.
    let mut g = rect("a", 0.0, 0.0, 10.0, 10.0);
    g.upm = 2048.0;
    let font = font_with(vec![(g, vec![])]);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::UpmMismatch { .. }));
}

#[test]
fn comment_prefix_names_are_quoted_and_roundtrip() {
    // `//` or `/*` leading a bare atom would lex as a comment on reread.
    let font = font_with(vec![
        (rect("//foo", 0.0, 0.0, 10.0, 10.0), vec![]),
        (rect("/*bar*/", 0.0, 0.0, 10.0, 10.0), vec![]),
    ]);
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains("glyphname = \"//foo\";"), "comment-prefix name quoted");
    assert!(text.contains("glyphname = \"/*bar*/\";"), "comment-prefix name quoted");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
}

#[test]
fn reader_rejects_sloppy_plist() {
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    // Duplicate key.
    let dup = good.replacen("glyphname = \"R\";", "glyphname = R;\nglyphname = R;", 1);
    assert!(matches!(glyphs_file::read(&dup), Err(ParseError::Structure(_))));
    // Missing comma in an array.
    let mc = good.replacen("(258,338,l),", "(258,338,l) (300,338,o) /*dup*/", 1).replacen("(300,338,o),\n(340,367,o),", "(340,367,o),", 1);
    assert!(glyphs_file::read(&mc).is_err(), "missing comma must fail");
    // Doubled comma.
    let dc = good.replacen("(258,338,l),", "(258,338,l),,", 1);
    assert!(glyphs_file::read(&dc).is_err(), "doubled comma must fail");
    // Non-finite literal in a numeric field.
    let nan = good.replacen("width = 436;", "width = nan;", 1);
    assert!(glyphs_file::read(&nan).is_err(), "nan width must fail");
}

#[test]
fn reader_refuses_unknown_or_geometry_keys() {
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    // Anchors on a layer.
    let a = good.replacen("width = 436;", "anchors = ();\nwidth = 436;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))));
    // Shape attributes.
    let a = good.replacen("closed = 1;", "attr = {};\nclosed = 1;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))));
    // Kerning at root.
    let a = good.replacen("unitsPerEm = 1000;", "kerning = {};\nunitsPerEm = 1000;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "v2 bare kerning key stays refused");
    // Stems registry at root.
    let a = good.replacen("unitsPerEm = 1000;", "stems = ();\nunitsPerEm = 1000;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))));
    // shapes and paths both present.
    let a = good.replacen("shapes = (", "paths = ();\nshapes = (", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))));
}

#[test]
fn reader_strict_nodes_and_closed() {
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    // Smooth suffix is now carried (sidecar); junk suffixes stay refused.
    let a = good.replacen("(258,338,l),", "(258,338,ls),", 1);
    let f = glyphs_file::read(&a).expect("smooth suffix carried");
    assert!(f.glyphs[0].layers[0].smooth[0][0], "ls marks the first node smooth");
    // Junk suffix must not match by first letter.
    let a = good.replacen("(258,338,l),", "(258,338,linejunk),", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))));
    // Node attributes (4th tuple item).
    let a = good.replacen("(258,338,l),", "(258,338,l,{}),", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))));
    // closed is schema-required; absence is reported, not defaulted.
    let a = good.replacen("closed = 1;\n", "", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::MissingField("closed"))));
    // The schema enum is exactly 0 or 1; any other number is rejected,
    // not coerced by "nonzero means true".
    for bad in ["2", "0.5", "-1"] {
        let a = good.replacen("closed = 1;", &format!("closed = {bad};"), 1);
        assert!(
            matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))),
            "closed = {bad} must fail"
        );
    }
    // Documented external default that IS supported: absent over means 0.
    let a = good.replacen("over = 10;\n", "", 1);
    let f = glyphs_file::read(&a).expect("absent over reads as default");
    assert_eq!(f.masters[0].metrics[1].over, None);
}

#[test]
fn strokenames_mismatch_and_localized_properties_are_loud() {
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    // userData list desynchronized from the path count.
    let a = good.replacen("\"bowl\",\n\"leg\",\n\"stem\"", "\"bowl\",\n\"leg\"", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))));
    // Localized property values: preservation not established, refused.
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    font.properties = vec![GlyphsProperty { key: "designers".into(), value: "X".into() }];
    let text = glyphs_file::write(&font).expect("write");
    let loc = text.replacen("value = \"X\";", "values = ({language = dflt;\nvalue = \"X\";});", 1);
    assert!(matches!(glyphs_file::read(&loc), Err(ParseError::Unsupported(_))));
}

// -------------------------------------------------------------------------
// negatives: lossy-allowlist removals, malformed metadata, numeric names
// -------------------------------------------------------------------------

#[test]
fn semantic_fields_are_refused_not_dropped() {
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    // Root level: each of these is schema-defined but outside the subset,
    // and dropping it would change the built font.
    for (key, val) in [
        ("classes", "()"), ("features", "()"), ("featurePrefixes", "()"),
        ("customParameters", "()"), ("settings", "{}"), ("userData", "{}"),
    ] {
        let a = good.replacen("unitsPerEm = 1000;", &format!("{key} = {val};\nunitsPerEm = 1000;"), 1);
        assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "root {key} must be refused");
    }
    // Glyph level: export flags, classifications, metric/kern bindings.
    for key in ["category", "script", "subCategory", "case", "direction",
                "metricLeft", "metricRight", "metricWidth", "metricVertWidth",
                "kernLeft", "kernRight", "kernTop", "kernBottom", "production", "userData",
                "sortName", "sortNameKeep", "group", "groupIdx"] {
        let a = good.replacen("glyphname = \"R\";", &format!("{key} = 1;\nglyphname = R;"), 1);
        assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "glyph {key} must be refused");
    }
    // Instance and axis level.
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    font.instances.push(GlyphsInstance { name: "Bold".into(), axes_values: vec![700.0, 100.0], exports: true, weight_class: None, width_class: None, is_bold: None, is_italic: None });
    let with_inst = glyphs_file::write(&font).expect("write");
    for key in ["userData", "active", "customParameters", "instanceInterpolations"] {
        let a = with_inst.replacen("name = \"Bold\";", &format!("{key} = 1;\nname = Bold;"), 1);
        assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "instance {key} must be refused");
    }
    let a = good.replacen("name = \"Weight\";", "userData = {};\nname = Weight;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "axis userData must be refused");
    // Instance exports outside the schema enum [0,1].
    let a = with_inst.replacen("name = \"Bold\";", "exports = 2;\nname = Bold;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "exports = 2 must fail");
}

#[test]
fn malformed_userdata_is_a_typed_error() {
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    // userData present but not a dict.
    let block = "userData = {\n\"KNI.strokeNames\" = (\n\"bowl\",\n\"leg\",\n\"stem\"\n);\n};";
    let a = good.replacen(block, "userData = 5;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "non-dict userData must fail");
    // strokeNames not an array.
    let a = good.replace("\"KNI.strokeNames\" = (\n\"bowl\",\n\"leg\",\n\"stem\"\n);", "\"KNI.strokeNames\" = 5;");
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "non-array strokeNames must fail");
    // strokeNames with a non-string entry.
    let a = good.replace("\"bowl\",\n\"leg\",\n\"stem\"", "\"bowl\",\n5,\n\"stem\"");
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "mixed strokeNames must fail");
    // Unknown userData key alongside the known one.
    let a = good.replacen("\"KNI.strokeNames\" = (", "other = 1;\n\"KNI.strokeNames\" = (", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "unknown userData key must be refused");
}

#[test]
fn property_requires_a_value() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    font.properties = vec![GlyphsProperty { key: "designers".into(), value: "X".into() }];
    let text = glyphs_file::write(&font).expect("write");
    let a = text.replacen("value = \"X\";\n", "", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::MissingField("value"))), "key without value must fail");
    // Localized values refused (reachable specific check).
    let a = text.replacen("value = \"X\";", "values = ({language = dflt;\nvalue = \"X\";});", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))));
}

#[test]
fn numeric_looking_strings_are_quoted_and_roundtrip() {
    // The lexer tokenizes f64-parseable words as numbers, so these names
    // written bare would reread as Num, not as strings.
    let font = font_with(vec![
        (rect("+1", 0.0, 0.0, 10.0, 10.0), vec![]),
        (rect(".5", 0.0, 0.0, 10.0, 10.0), vec![]),
        (rect("1e3", 0.0, 0.0, 10.0, 10.0), vec![]),
        (rect("nan", 0.0, 0.0, 10.0, 10.0), vec![]),
        (rect("inf", 0.0, 0.0, 10.0, 10.0), vec![]),
    ]);
    let text = glyphs_file::write(&font).expect("write");
    for n in ["\"+1\"", "\".5\"", "\"1e3\"", "\"nan\"", "\"inf\""] {
        assert!(text.contains(&format!("glyphname = {n};")), "{n} must be quoted");
    }
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
}

#[test]
fn empty_required_semantics_rejected_at_write() {
    // No masters at all (schema: fontMaster minItems 1); a glyph with no
    // layers would otherwise slip through.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.masters.clear();
    font.glyphs[0].layers.clear();
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::NoMasters);
    // Empty instance name.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.instances.push(GlyphsInstance { name: "".into(), axes_values: vec![100.0, 100.0], exports: true, weight_class: None, width_class: None, is_bold: None, is_italic: None });
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyInstanceName);
    // Empty property key.
    let mut font = font_with(vec![(rect("a", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.properties = vec![GlyphsProperty { key: "".into(), value: "X".into() }];
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyPropertyKey);
}

#[test]
fn absent_metricvalue_pos_reads_as_schema_default() {
    // Schema $defs/metricStore documents default 0 for pos (and over).
    let good = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    let a = good.replacen("pos = 850;\n", "", 1);
    let f = glyphs_file::read(&a).expect("absent pos reads as schema default 0");
    assert_eq!(f.masters[0].metrics[0].pos, 0.0);
}

// -------------------------------------------------------------------------
// instance OS/2 optional fields (schema $defs/instance)
// -------------------------------------------------------------------------

#[test]
fn instance_optional_fields_write_read_parity() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    font.instances = vec![GlyphsInstance {
        name: "Bold Italic".into(),
        axes_values: vec![700.0, 100.0],
        exports: true,
        weight_class: Some(700),
        width_class: Some(7),
        is_bold: Some(true),
        is_italic: Some(true),
    }];
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains("weightClass = 700;"));
    assert!(text.contains("widthClass = 7;"));
    assert!(text.contains("isBold = 1;"));
    assert!(text.contains("isItalic = 1;"));
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    // None omits the key (schema defaults 400 / 5 / 0 / 0).
    font.instances[0].weight_class = None;
    font.instances[0].width_class = None;
    font.instances[0].is_bold = None;
    font.instances[0].is_italic = None;
    let text = glyphs_file::write(&font).expect("write");
    for k in ["weightClass", "widthClass", "isBold", "isItalic"] {
        assert!(!text.contains(k), "{k} must be omitted when None");
    }
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
}

#[test]
fn instance_optional_fields_range_and_enum_checked() {
    let base = |w: Option<u16>, wc: Option<u16>| {
        let mut font = font_with(vec![(reference_r(), vec![0x52])]);
        font.instances = vec![GlyphsInstance {
            name: "X".into(),
            axes_values: vec![100.0, 100.0],
            exports: true,
            weight_class: w,
            width_class: wc,
            is_bold: None,
            is_italic: None,
        }];
        font
    };
    // Write side: schema ranges weightClass 1..=1000, widthClass 1..=9.
    assert!(matches!(
        glyphs_file::write(&base(Some(0), None)).unwrap_err(),
        WriteError::InstanceWeightClassOutOfRange { .. }
    ));
    assert!(matches!(
        glyphs_file::write(&base(Some(1001), None)).unwrap_err(),
        WriteError::InstanceWeightClassOutOfRange { .. }
    ));
    assert!(matches!(
        glyphs_file::write(&base(None, Some(0))).unwrap_err(),
        WriteError::InstanceWidthClassOutOfRange { .. }
    ));
    assert!(matches!(
        glyphs_file::write(&base(None, Some(10))).unwrap_err(),
        WriteError::InstanceWidthClassOutOfRange { .. }
    ));
    // Read side: out-of-range values and non-enum bools are typed errors.
    let good = glyphs_file::write(&base(Some(700), Some(5))).expect("write");
    let a = good.replacen("weightClass = 700;", "weightClass = 1200;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))));
    let a = good.replacen("widthClass = 5;", "widthClass = 42;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))));
    let a = good.replacen("widthClass = 5;", "isBold = 2;\nwidthClass = 5;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))));
}

// -------------------------------------------------------------------------
// glyph export flag (schema enum [0,1], default 1)
// -------------------------------------------------------------------------

#[test]
fn glyph_export_flag_write_read_parity() {
    let mut font = font_with(vec![(reference_r(), vec![0x52]), (rect("carry", 0.0, 0.0, 10.0, 10.0), vec![])]);
    font.glyphs[1].export = false;
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains("export = 0;"), "non-exporting glyph emits export = 0");
    assert_eq!(text.matches("export").count(), 1, "exporting glyphs omit the key (schema default 1)");
    let back = glyphs_file::read(&text).expect("read");
    assert!(back.glyphs[0].export);
    assert!(!back.glyphs[1].export);
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    // export = 1 reads as true; outside the enum is a typed error.
    let a = text.replacen("export = 0;", "export = 1;", 1);
    let f = glyphs_file::read(&a).expect("export = 1 reads as true");
    assert!(f.glyphs[1].export);
    for bad in ["2", "0.5", "-1"] {
        let a = text.replacen("export = 0;", &format!("export = {bad};"), 1);
        assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "export = {bad} must fail");
    }
}

// -------------------------------------------------------------------------
// P3 structure (chief ruling 19:48): single glyphs array, per-style font
// info, metrics in doc, no repeated sections.
// -------------------------------------------------------------------------

#[test]
fn p3_single_sections_and_per_style_masters() {
    // Two styles as two masters of one document.
    let mut font = font_with(vec![(reference_r(), vec![0x52]), (rect("h", 0.0, 0.0, 500.0, 700.0), vec![0x68])]);
    font.masters.push(master("m02", "Extradraw"));
    for g in &mut font.glyphs {
        let contours: Vec<StrokeContour> = g.layers[0]
            .shapes
            .iter()
            .filter_map(|s| match s {
                GlyphsShape::Path(c) => Some(c.clone()),
                GlyphsShape::Component(_) => None,
            })
            .collect();
        let mg = MasterGlyph { name: g.name.clone(), advance: 600.0, upm: 1000.0, contours };
        g.layers.push(GlyphsLayer::from_master_glyph("m02", &mg));
    }
    let text = glyphs_file::write(&font).expect("write");
    // Every top-level section exactly once (no repeated sections).
    for key in [".formatVersion", "familyName", "fontMaster", "glyphs", "metrics", "unitsPerEm", "versionMajor", "versionMinor", "axes"] {
        assert_eq!(text.matches(&format!("\n{key} = ")).count(), 1, "section {key} must appear exactly once");
    }
    // Single glyphs array: one entry per input glyph, both master layers each.
    assert_eq!(text.matches("glyphname = ").count(), 2, "single glyphs array, one entry per glyph");
    assert_eq!(text.matches("layerId = \"m01\";").count(), 2);
    assert_eq!(text.matches("layerId = \"m02\";").count(), 2);
    // Per-style master info: names and ids both present.
    assert!(text.contains("name = \"Regular\";") && text.contains("name = \"Extradraw\";"));
    // Metrics in doc: registry + per-master metricValues, one registry only.
    assert_eq!(text.matches("metricValues = ").count(), 2, "one metricValues per master");
    // Round-trip parity.
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
}

// -------------------------------------------------------------------------
// kerning (pairs only) + smooth node sidecar
// -------------------------------------------------------------------------

fn kerned_font() -> GlyphsFont {
    let mut font = font_with(vec![(reference_r(), vec![0x52]), (rect("h", 0.0, 0.0, 500.0, 700.0), vec![0x68])]);
    font.kerning = GlyphsKerning {
        ltr: vec![
            KerningPair { master_id: "m01".into(), left: "R".into(), right: "h".into(), value: -80.0 },
            KerningPair { master_id: "m01".into(), left: "R".into(), right: "R".into(), value: -25.5 },
            KerningPair { master_id: "m01".into(), left: "h".into(), right: "R".into(), value: 12.0 },
        ],
        rtl: vec![],
        vertical: vec![KerningPair { master_id: "m01".into(), left: "R".into(), right: "h".into(), value: 40.0 }],
    };
    font
}

#[test]
fn kerning_pairs_write_read_parity() {
    let font = kerned_font();
    let text = glyphs_file::write(&font).expect("write");
    // Schema keys and nesting; pairs only, names quoted, integral values integral.
    assert!(text.contains("kerningLTR = {"), "schema key kerningLTR");
    assert!(text.contains("kerningVertical = {"), "schema key kerningVertical");
    assert!(!text.contains("kerningRTL"), "empty direction omitted");
    assert!(text.contains("\"R\" = {\n\"h\" = -80;\n\"R\" = -25.5;\n};"), "nested master/left/right, first-seen order, integer value");
    assert!(text.contains("\"R\" = -25.5;"), "non-integral value keeps its decimal");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    // Order preserved: R first, then h, as supplied.
    assert_eq!(back.kerning.ltr[0].left, "R");
    assert_eq!(back.kerning.ltr[2].left, "h");
}

#[test]
fn kerning_typed_negatives() {
    // Non-finite value.
    let mut font = kerned_font();
    font.kerning.ltr[0].value = f64::NAN;
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::NonFiniteKerning { .. }));
    // Empty name.
    let mut font = kerned_font();
    font.kerning.ltr[0].left.clear();
    assert_eq!(glyphs_file::write(&font).unwrap_err(), WriteError::EmptyKerningName);
    // Duplicate triple in one direction.
    let mut font = kerned_font();
    let dup = font.kerning.ltr[0].clone();
    font.kerning.ltr.push(dup);
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::DuplicateKerningPair { .. }));
    // Dangling master id.
    let mut font = kerned_font();
    font.kerning.ltr[0].master_id = "m99".into();
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::UnknownMasterId(_)));
    // Read side: value not a number, levels not dicts.
    let good = glyphs_file::write(&kerned_font()).expect("write");
    let a = good.replacen("\"h\" = -80;", "\"h\" = nan;", 1);
    assert!(glyphs_file::read(&a).is_err(), "non-finite read fails");
    let a = good.replacen("\"R\" = {\n\"h\" = -80;\n\"R\" = -25.5;\n};", "\"R\" = 5;", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "non-dict level fails");
    // Same left name twice under one master in the FILE: the parser's
    // duplicate-key rejection fires (dict keys are unique per dict), so a
    // file can never express a duplicate triple.
    let a = good.replacen("\"h\" = {\n\"R\" = 12;\n};", "\"h\" = {\n\"R\" = 12;\n};\n\"R\" = {\n\"h\" = 1;\n};", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Structure(_))), "file-level duplicate key caught: {:?}", glyphs_file::read(&a).err());
}

#[test]
fn smooth_sidecar_write_read_parity_and_negatives() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    // Tuple counts for the reference R contours: bowl 25 (1 M + 6*3 C + 6 L),
    // leg 5, stem 6.
    let n0 = 25;
    // Bowl on-curve tuple indexes: 0(M), 3,4,7,10,11,12,13,16,19,22,23,24;
    // flag the even ones (off-curve tuples 1,2,5,6,... stay corner).
    font.glyphs[0].layers[0].smooth = vec![
        [0usize, 4, 10, 12, 16, 22, 24].into_iter().fold(vec![false; n0], |mut v, j| { v[j] = true; v }),
        vec![false, false, false, false, false],
        vec![true, false, false, false, false, false],
    ];
    let text = glyphs_file::write(&font).expect("write");
    assert!(text.contains("(258,338,ls)"), "smooth line node carries s suffix");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    // Empty sidecar == all corner: a fresh font has none and emits no s suffixes.
    let plain = glyphs_file::write(&font_with(vec![(reference_r(), vec![0x52])])).expect("write");
    assert!(!plain.contains(",ls)") && !plain.contains(",cs)"));
    // Sidecar length mismatch.
    font.glyphs[0].layers[0].smooth = vec![vec![true]];
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::SmoothSidecarMismatch { .. }));
    // Off-curve flagged: contour 0 node 1 is an off-curve (300,338,o).
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    let mut v = vec![false; n0];
    v[1] = true; // tuple 1 in the bowl is the first off-curve node
    font.glyphs[0].layers[0].smooth = vec![v, vec![false; 5], vec![false; 6]];
    assert!(matches!(glyphs_file::write(&font).unwrap_err(), WriteError::SmoothSidecarMismatch { .. }));
    // Read side: smooth off-curve suffix refused.
    let a = plain.replacen("(300,338,o),", "(300,338,os),", 1);
    assert!(matches!(glyphs_file::read(&a), Err(ParseError::Unsupported(_))), "os refused");
}

fn composite_component(glyph: &str) -> GlyphsComponent {
    GlyphsComponent {
        glyph: glyph.into(),
        pos: (0.0, 0.0),
        scale: (1.0, 1.0),
        angle: 0.0,
        alignment: ComponentAlignment::Default,
        anchor: None,
    }
}

fn rect_path() -> StrokeContour {
    match GlyphsLayer::from_master_glyph("m01", &rect("leg", 0.0, 0.0, 100.0, 700.0)).shapes.into_iter().next().unwrap() {
        GlyphsShape::Path(c) => c,
        GlyphsShape::Component(_) => unreachable!(),
    }
}

#[test]
fn component_write_read_parity_z_order_and_default_omission() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    let full = GlyphsComponent {
        glyph: "R".into(),
        pos: (10.0, 20.0),
        scale: (0.5, 1.5),
        angle: 15.0,
        alignment: ComponentAlignment::Horizontal,
        anchor: Some("top".into()),
    };
    let bare = composite_component("R");
    font.glyphs.push(GlyphsGlyph {
        name: "R.alt".into(),
        unicode: vec![],
        layers: vec![GlyphsLayer {
            master_id: "m01".into(),
            advance: 600.0,
            shapes: vec![
                GlyphsShape::Component(full.clone()),
                GlyphsShape::Path(rect_path()),
                GlyphsShape::Component(bare.clone()),
            ],
            source_upm: None,
            smooth: vec![],
        }],
        export: true,
    });
    let text = glyphs_file::write(&font).expect("write");
    // The full component carries every non-default key.
    assert!(
        text.contains("ref = \"R\";\npos = (10,20);\nscale = (0.5,1.5);\nangle = 15;\nalignment = 3;\nanchor = \"top\";"),
        "full component emission:\n{text}"
    );
    // The all-default component emits ref only.
    assert!(text.contains("{\nref = \"R\";\n}"), "default keys omitted:\n{text}");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
    // z-order preserved: component, path, component.
    let shapes = &back.glyphs[1].layers[0].shapes;
    assert!(matches!(&shapes[0], GlyphsShape::Component(c) if *c == full));
    assert!(matches!(&shapes[1], GlyphsShape::Path(_)));
    assert!(matches!(&shapes[2], GlyphsShape::Component(c) if *c == bare));
}

#[test]
fn component_typed_negatives_and_read_refusals() {
    let mk = |cp: GlyphsComponent| {
        let mut font = font_with(vec![(reference_r(), vec![0x52])]);
        font.glyphs.push(GlyphsGlyph {
            name: "R.alt".into(),
            unicode: vec![],
            layers: vec![GlyphsLayer {
                master_id: "m01".into(),
                advance: 600.0,
                shapes: vec![GlyphsShape::Component(cp)],
                source_upm: None,
                smooth: vec![],
            }],
            export: true,
        });
        font
    };
    assert!(matches!(glyphs_file::write(&mk(composite_component(""))), Err(WriteError::EmptyComponentRef { .. })));
    assert!(matches!(glyphs_file::write(&mk(composite_component("nope"))), Err(WriteError::UnknownComponentRef { .. })));
    let mut c = composite_component("R");
    c.pos = (f64::NAN, 0.0);
    assert!(matches!(glyphs_file::write(&mk(c)), Err(WriteError::NonFiniteComponentTransform { .. })));
    let mut c = composite_component("R");
    c.anchor = Some(String::new());
    assert!(matches!(glyphs_file::write(&mk(c)), Err(WriteError::EmptyComponentAnchor { .. })));

    // Read-side: component keys outside the subset are a typed refusal.
    let good = glyphs_file::write(&mk(composite_component("R"))).expect("write");
    for key in [
        "masterId = \"m01\";",
        "locked = 1;",
        "orientation = 0;",
        "keepWeight = 0;",
        "piece = {};",
        "attr = {};",
        "userData = {};",
    ] {
        let bad = good.replacen("ref = \"R\";", &format!("ref = \"R\";\n{key}"), 1);
        assert!(matches!(glyphs_file::read(&bad), Err(ParseError::Unsupported(_))), "{key} refused: {:?}", glyphs_file::read(&bad).err());
    }
    // Malformed transform, alignment outside the enum, empty anchor, empty ref.
    let bad = good.replacen("ref = \"R\";", "ref = \"R\";\npos = (1,2,3);", 1);
    assert!(matches!(glyphs_file::read(&bad), Err(ParseError::Structure(_))));
    let bad = good.replacen("ref = \"R\";", "ref = \"R\";\nalignment = 2;", 1);
    assert!(matches!(glyphs_file::read(&bad), Err(ParseError::Structure(_))));
    let bad = good.replacen("ref = \"R\";", "ref = \"R\";\nanchor = \"\";", 1);
    assert!(matches!(glyphs_file::read(&bad), Err(ParseError::Structure(_))));
    let bad = good.replacen("ref = \"R\";", "ref = \"\";", 1);
    assert!(matches!(glyphs_file::read(&bad), Err(ParseError::Structure(_))));
}

#[test]
fn smooth_sidecar_indexes_path_shapes_only_with_components() {
    let mut font = font_with(vec![(reference_r(), vec![0x52])]);
    font.glyphs.push(GlyphsGlyph {
        name: "R.alt".into(),
        unicode: vec![],
        layers: vec![GlyphsLayer {
            master_id: "m01".into(),
            advance: 600.0,
            // One component, then one path: the sidecar counts paths only.
            shapes: vec![GlyphsShape::Component(composite_component("R")), GlyphsShape::Path(rect_path())],
            source_upm: None,
            smooth: vec![vec![true, false, false, true]],
        }],
        export: true,
    });
    let text = glyphs_file::write(&font).expect("write");
    assert_eq!(text.matches(",ls)").count(), 2, "two smooth line nodes emitted:\n{text}");
    let back = glyphs_file::read(&text).expect("read");
    assert_eq!(glyphs_file::parity_errors(&font, &back), Vec::<String>::new());
}

#[test]
fn close_ring_regression_open_ring_is_refused_not_accepted() {
    // P6 (chief ruling 19:48): ring closure is fail-closed on both sides
    // of the harness. SliceC tidy will manipulate nodes; these guard the
    // contract it must preserve - an open ring is a typed refusal, never
    // silently closed, defaulted, or dropped.
    let text = glyphs_file::write(&font_with(vec![(rect("ring", 0.0, 0.0, 1.0, 1.0), vec![])])).expect("write");

    // Reader: closed = 0 is a typed refusal, not a default-to-closed.
    let open = text.replacen("closed = 1;", "closed = 0;", 1);
    match glyphs_file::read(&open) {
        Err(glyphs_file::ParseError::Unsupported(m)) => assert!(m.contains("open path"), "{m}"),
        other => panic!("expected open-path refusal, got {other:?}"),
    }

    // Reader: closed outside the schema enum [0,1] is a structure violation.
    let bad = text.replacen("closed = 1;", "closed = 2;", 1);
    match glyphs_file::read(&bad) {
        Err(glyphs_file::ParseError::Structure(m)) => assert!(m.contains("closed must be 0 or 1"), "{m}"),
        other => panic!("expected enum refusal, got {other:?}"),
    }

    // Writer: a contour whose ops do not close is refused.
    let mut g = rect("open", 0.0, 0.0, 1.0, 1.0);
    g.contours[0].ops.pop();
    assert!(matches!(
        glyphs_file::write(&font_with(vec![(g, vec![])])),
        Err(WriteError::OpenContour { .. })
    ));
}

#[test]
fn serializer_determinism_is_the_tidy_idempotence_anchor() {
    // P6 (chief ruling 19:48): the tidy-idempotence test (tidy . tidy ==
    // tidy) plugs in here when SliceC's tidy lands at the B4 merge - it is
    // NOT_RUN until then, the function is not in this tree. The harness
    // anchor available now: emission is deterministic, so any future tidy
    // stage has a stable fixed point to converge to.
    let font = font_with(vec![(rect("idem", 0.0, 0.0, 1.0, 1.0), vec![])]);
    let a = glyphs_file::write(&font).expect("write a");
    let b = glyphs_file::write(&glyphs_file::read(&a).expect("read")).expect("write b");
    assert_eq!(a, b, "write-read-write must be byte-identical");
}
