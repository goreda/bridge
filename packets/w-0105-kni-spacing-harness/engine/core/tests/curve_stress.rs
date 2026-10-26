//! curve_stress gate: unit contracts for the measurement functions and the
//! committed node-economy baseline corpus over the engine's own capture
//! fixtures.
//!
//! Baseline regeneration (bless): run
//!   KNI_CURVE_STRESS_BLESS=1 cargo test -p kni-core --test curve_stress
//! which rewrites core/tests/fixtures/curve_stress/baseline-v1.tsv and the
//! proof PNGs next to it. Without the env var the test is a read-only gate:
//! the regenerated corpus must equal the committed file byte for byte.
//!
//! Gate-fixture config (documented in the module docs):
//!   scale: tile-height-1000 (derived: the full tile height maps to 1000
//!     units, mirroring UPM 1000; the fixtures' declared style scale is not
//!     part of the engine tree);
//!   rdp_eps_px: 0.5 (CONVENTION: one half-pixel iso band - capture traces
//!     the 0.5 ink-strength iso contour, so 0.5 px is the contour's own
//!     localization band);
//!   fit_squared_error: (scale/2)^2 (the run_config DerivedSourceQuantization
//!     value);
//!   max_refits: derive_max_refits (one refit consumes one split sample).

use kni_core::capture;
use kni_core::curve_stress::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};
use std::path::PathBuf;

const GATE_FIXTURES: [&str; 6] = [
    "00C9_scan", "dot_00b7", "quote_2018", "r_scan", "s_scan", "u_scan",
];
const GATE_STYLE: &str = "core-fixtures";
const GATE_RDP_EPS_PX: f64 = 0.5;
const BLESS_ENV: &str = "KNI_CURVE_STRESS_BLESS";

fn gate_config() -> GlyphRunConfig {
    GlyphRunConfig {
        scale: ScaleSpec::TileHeight1000,
        rdp_eps_px: GATE_RDP_EPS_PX,
        fit_se: FitSeSpec::DerivedSourceQuantization,
        max_refits: RefitSpec::Derived,
    }
}

fn p(x: f64, y: f64) -> Point { Point { x, y } }

fn line(end: Point) -> Span { Span::Line { end } }
fn cubic(c1: Point, c2: Point, end: Point) -> Span {
    Span::Cubic { control_one: c1, control_two: c2, end }
}

/// Quarter-circle cubic, traversed clockwise (decreasing angle) from a0 to
/// a0-90deg, radius r around center c. Handle length kappa*r with the exact
/// circular-arc kappa = 4/3*tan(pi/8).
fn quarter_arc(c: Point, r: f64, a0_deg: f64) -> (Point, Span) {
    let k = 4.0 / 3.0 * (std::f64::consts::PI / 8.0).tan() * r;
    let a0 = a0_deg.to_radians();
    let a1 = (a0_deg - 90.0).to_radians();
    let p0 = p(c.x + r * a0.cos(), c.y + r * a0.sin());
    let p3 = p(c.x + r * a1.cos(), c.y + r * a1.sin());
    // Velocity direction under decreasing angle: (sin a, -cos a).
    let d0 = p(a0.sin(), -a0.cos());
    let d1 = p(a1.sin(), -a1.cos());
    let p1 = p(p0.x + k * d0.x, p0.y + k * d0.y);
    let p2 = p(p3.x - k * d1.x, p3.y - k * d1.y);
    (p0, cubic(p1, p2, p3))
}

fn ring(start: Point, spans: Vec<Span>) -> ReferenceRing {
    ReferenceRing { start, spans }
}

#[test]
fn rectangle_has_four_corners_no_breaks() {
    let r = ring(p(0.0, 0.0), vec![
        line(p(200.0, 0.0)), line(p(200.0, 100.0)), line(p(0.0, 100.0)), line(p(0.0, 0.0)),
    ]);
    let g = analyze_rings(&[r]).unwrap();
    assert_eq!(g.nodes, 4);
    assert_eq!(g.lines, 4);
    assert_eq!(g.cubics, 0);
    assert_eq!(g.corners, 4);
    assert_eq!(g.curvature_breaks, 0);
    assert_eq!(g.unavailable_joints, 0);
    assert!(g.deviation.is_none());
}

#[test]
fn exact_circle_is_smooth_everywhere() {
    // Four quarter arcs of equal radius and equal orientation: curvature is
    // constant, so every joint is smooth and any reported break is a defect.
    let c = p(0.0, 0.0);
    let (s0, a0) = quarter_arc(c, 100.0, 180.0);
    let (_, a1) = quarter_arc(c, 100.0, 90.0);
    let (_, a2) = quarter_arc(c, 100.0, 0.0);
    let (_, a3) = quarter_arc(c, 100.0, -90.0);
    let g = analyze_rings(&[ring(s0, vec![a0, a1, a2, a3])]).unwrap();
    assert_eq!(g.nodes, 4);
    assert_eq!(g.cubics, 4);
    assert_eq!(g.corners, 0);
    assert_eq!(g.curvature_breaks, 0);
    assert_eq!(g.unavailable_joints, 0);
}

#[test]
fn radius_jump_at_smooth_joint_is_one_curvature_break() {
    // Two tangent-continuous quarter arcs, r=100 into r=50 (same turn
    // direction): the joint is G1 but not G2 - exactly one curvature break,
    // analytically. The closing line contributes two corners.
    let (s0, a0) = quarter_arc(p(0.0, 0.0), 100.0, 180.0); // (-100,0) -> (0,100)
    let (_, a1) = quarter_arc(p(0.0, 50.0), 50.0, 90.0); // (0,100) -> (50,50)
    let close = line(s0);
    let g = analyze_rings(&[ring(s0, vec![a0, a1, close])]).unwrap();
    assert_eq!(g.curvature_breaks, 1, "joints: {:?}", g.joints.iter().map(|j| (j.node, j.kind)).collect::<Vec<_>>());
    assert_eq!(g.corners, 2);
    let brk = g.joints.iter().find(|j| j.kind == JointKind::CurvatureBreak).unwrap();
    assert_eq!(brk.node, 0);
    assert!(brk.severity > brk.floor);
    // Sanity band vs the analytic circle value |1/100 - 1/50| * min chord:
    // the kappa cubic only approximates a circle, so its endpoint curvature
    // deviates from 1/r by a small arc-approximation error. The 5% band is a
    // test oracle for that approximation, not an engine quality threshold.
    let chord = (50.0f64.powi(2) + 50.0f64.powi(2)).sqrt();
    let expected = 0.01 * chord;
    assert!((brk.severity - expected).abs() < 0.05 * expected, "severity {} expected ~{}", brk.severity, expected);
}

#[test]
fn line_into_tangent_aligned_arc_is_a_break_not_a_corner() {
    // Line along (1,0) into a tangent-aligned r=50 arc: no corner, one break.
    let s0 = p(0.0, 0.0);
    let (_, arc) = quarter_arc(p(100.0, -50.0), 50.0, 90.0); // (100,0) -> (150,-50)
    let g = analyze_rings(&[ring(s0, vec![
        line(p(100.0, 0.0)), arc, line(p(0.0, -50.0)), line(s0),
    ])]).unwrap();
    assert_eq!(g.curvature_breaks, 1, "joints: {:?}", g.joints.iter().map(|j| (j.node, j.kind)).collect::<Vec<_>>());
    assert_eq!(g.corners, 3);
}

#[test]
fn nonzero_winding_distinguishes_ring_direction() {
    // Two nested squares. Nonzero winding: same direction fills the inner
    // square (winding 2), opposite direction leaves the counter open. The
    // even-odd rule would leave it open in both cases, which is exactly the
    // renderer bug this gate exists to catch.
    let outer_ccw: Vec<(f64, f64)> = vec![(2.0, 2.0), (18.0, 2.0), (18.0, 18.0), (2.0, 18.0)];
    let inner_ccw: Vec<(f64, f64)> = vec![(6.0, 6.0), (14.0, 6.0), (14.0, 14.0), (6.0, 14.0)];
    let inner_cw: Vec<(f64, f64)> = inner_ccw.iter().rev().cloned().collect();
    let center = |img: &[u8], w: usize, h: usize| img[(h - 1 - 10) * w + 10];
    let w = 20;
    let h = 20;
    let filled = rasterize_nonzero(w, h, &[outer_ccw.clone(), inner_ccw]);
    assert_eq!(center(&filled, w, h), 0, "same-direction nested rings: nonzero winding fills");
    let holed = rasterize_nonzero(w, h, &[outer_ccw, inner_cw]);
    assert_eq!(center(&holed, w, h), 255, "opposite-direction nested rings: counter stays open");
}

#[test]
fn deviation_is_symmetric_and_exact_on_parallel_segments() {
    let fitted = vec![vec![p(0.0, 0.0), p(10.0, 0.0)]];
    let source = vec![vec![p(0.0, 3.0), p(10.0, 3.0)]];
    let d = symmetric_deviation(&fitted, &source).unwrap();
    assert_eq!(d.max, 3.0);
    assert_eq!(d.mean, 3.0);
    assert_eq!(d.samples, 4);
    let identical = symmetric_deviation(&fitted, &fitted).unwrap();
    assert_eq!(identical.max, 0.0);
}

#[test]
fn png_encoder_roundtrips_through_the_production_decoder() {
    // Deterministic pattern with runs and noise, exercising both the
    // distance-1 match path and literal emission.
    let w = 37;
    let h = 23;
    let mut img = vec![0u8; w * h];
    for y in 0..h {
        for x in 0..w {
            img[y * w + x] = if (x * 31 + y * 17) % 5 == 0 { 0 } else { 255 };
        }
    }
    let png = encode_png_gray(w, h, &img).unwrap();
    let (dw, dh, decoded) = capture::decode_png_gray(&png).unwrap();
    assert_eq!((dw, dh), (w, h));
    assert_eq!(decoded, img);
}

fn fixture_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

#[test]
fn baseline_corpus_matches_committed() {
    let cfg = gate_config();
    let note = config_note(&cfg);
    let regen = "KNI_CURVE_STRESS_BLESS=1 cargo test -p kni-core --test curve_stress";
    let mut rows = Vec::new();
    let mut proofs: Vec<(String, Vec<u8>, Vec<u8>)> = Vec::new();
    for glyph in GATE_FIXTURES {
        let path = fixture_dir().join(format!("{glyph}.png"));
        let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
        let run = run_glyph(GATE_STYLE, glyph, &bytes, &cfg)
            .unwrap_or_else(|e| panic!("{glyph}: {e}"));
        proofs.push((glyph.to_string(), run.fit_png, run.overlay_png));
        rows.push(run.row);
    }
    let doc = corpus_document(GATE_STYLE, &note, regen, &rows).unwrap();
    let out_dir = fixture_dir().join("curve_stress");
    let baseline_path = out_dir.join("baseline-v1.tsv");
    if std::env::var(BLESS_ENV).is_ok() {
        std::fs::create_dir_all(&out_dir).unwrap();
        std::fs::write(&baseline_path, &doc).unwrap();
        for (glyph, fit_png, ovl_png) in &proofs {
            std::fs::write(out_dir.join(format!("{glyph}.fit.png")), fit_png).unwrap();
            std::fs::write(out_dir.join(format!("{glyph}.ovl.png")), ovl_png).unwrap();
        }
        eprintln!("curve_stress: baseline blessed at {}", baseline_path.display());
        return;
    }
    let committed = std::fs::read_to_string(&baseline_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e} - bless the baseline first ({regen})", baseline_path.display()));
    if committed != doc {
        let old: Vec<&str> = committed.lines().collect();
        let new: Vec<&str> = doc.lines().collect();
        for i in 0..old.len().max(new.len()) {
            let a = old.get(i).copied().unwrap_or("<missing>");
            let b = new.get(i).copied().unwrap_or("<missing>");
            if a != b {
                panic!("curve_stress baseline drift at line {}:\ncommitted: {a}\nregenerated: {b}\nregenerate with: {regen}", i + 1);
            }
        }
        panic!("curve_stress baseline length drift; regenerate with: {regen}");
    }
}

// ---------- SVG outline import + explicit emission grid ----------

fn svg_ring_counts(rings: &[kni_core::reference_slice::ReferenceRing]) -> (usize, usize) {
    let cubics = rings.iter().flat_map(|r| r.spans.iter())
        .filter(|s| matches!(s, Span::Cubic { .. })).count();
    let lines = rings.iter().flat_map(|r| r.spans.iter())
        .filter(|s| matches!(s, Span::Line { .. })).count();
    (cubics, lines)
}

#[test]
fn svg_parse_potrace_style_relative_cubics() {
    // potrace: integer path data under translate+scale, relative c/l, z.
    let xml = r##"<svg width="100pt" height="100pt" viewBox="0 0 100 100">
<g transform="translate(0,1000) scale(0.1,-0.1)" fill="#000000">
<path d="M100 100 c10 0 20 10 20 20 c0 10 -10 20 -20 20 l-30 0 z"/>
</g></svg>"##;
    let svg = parse_svg_outline(xml).expect("parse");
    assert_eq!(svg.dark_paths, 1);
    assert_eq!(svg.white_paths_skipped, 0);
    assert_eq!(svg.half_coord, 0.5); // integer data
    assert_eq!(svg.rings.len(), 1);
    let (c, l) = svg_ring_counts(&svg.rings);
    assert_eq!((c, l), (2, 2)); // two cubics, explicit l + implicit z line
    let stress = analyze_rings_with_grid(&svg.rings, svg.half_coord).expect("analyze");
    assert_eq!(stress.nodes, 4);
    // transform composed as translate*scale (scale applied to points first)
    let p = affine_apply(&svg.group_transform, Point { x: 100.0, y: 100.0 });
    assert!((p.x - 10.0).abs() < 1e-9 && (p.y - 990.0).abs() < 1e-9);
}

#[test]
fn svg_parse_skips_white_and_reads_decimals() {
    // autotrace style: white background path + dark path with decimals.
    let xml = r##"<svg width="1485" height="1050">
<path style="fill:#ffffff; stroke:none;" d="M0 0L0 1050L1485 1050L1485 0L0 0z"/>
<path style="fill:#000000; stroke:none;" d="M633 409C638.643 403.18 642.99 396.412 651 393.549L690 426L633 409z"/>
</svg>"##;
    let svg = parse_svg_outline(xml).expect("parse");
    assert_eq!(svg.dark_paths, 1);
    assert_eq!(svg.white_paths_skipped, 1);
    assert_eq!(svg.half_coord, 0.0005); // 3 decimals
    let (c, l) = svg_ring_counts(&svg.rings);
    assert_eq!((c, l), (1, 2));
}

#[test]
fn svg_parse_rejects_unsupported_commands() {
    let err = parse_svg_outline(r##"<svg><path fill="#000" d="M0 0 Q1 1 2 2 z"/></svg>"##).err().expect("unsupported command must fail");
    assert!(err.contains('Q'), "error names the command: {err}");
}

#[test]
fn svg_explicit_grid_matches_default_on_integer_data() {
    // A rectangle: analyze_rings (integer font-unit grid) equals the
    // explicit 0.5 grid, and corners are detected at the square's nodes.
    let rings = parse_path_data("M0 0 L10 0 L10 10 L0 10 z").expect("path");
    let a = analyze_rings(&rings).expect("default grid");
    let b = analyze_rings_with_grid(&rings, 0.5).expect("explicit grid");
    assert_eq!(a.corners, 4);
    assert_eq!(a.corners, b.corners);
    assert_eq!(a.curvature_breaks, b.curvature_breaks);
    // A collinear middle node is smooth on both grids
    let rings2 = parse_path_data("M0 0 L5 0 L10 0 L10 10 L0 10 z").expect("path2");
    let c = analyze_rings_with_grid(&rings2, 0.5).expect("analyze2");
    assert_eq!(c.corners, 4);
    assert_eq!(c.joints.iter().filter(|j| j.kind == JointKind::Smooth).count(), 1);
}

#[test]
fn svg_transform_parse_and_white_forms() {
    let m = parse_transform("translate(0.000000,1050.000000) scale(0.100000,-0.100000)").expect("transform");
    let p = affine_apply(&m, Point { x: 6484.0, y: 6809.0 });
    assert!((p.x - 648.4).abs() < 1e-9 && (p.y - 369.1).abs() < 1e-9);
    assert!(parse_transform("rotate(30)").is_err());
    assert!(is_white_fill("#FFFFFF"));
    assert!(is_white_fill(" #fff "));
    assert!(!is_white_fill("#1F1F1F"));
}
