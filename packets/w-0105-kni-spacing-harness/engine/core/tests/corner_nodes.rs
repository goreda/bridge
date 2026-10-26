//! corner_nodes coverage: the C3 explicit corner-node representation.
//! Synthetic rings pin the semantics (split, collapse, verify); the 5 pinned
//! real-scan fixtures prove byte-identity of the representation on fitted
//! production output. No env var, no skipping.
use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::corner_nodes::*;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

fn pt(x: f64, y: f64) -> Point { Point { x, y } }
fn line(end: Point) -> Span { Span::Line { end } }
fn cubic(c1: Point, c2: Point, end: Point) -> Span { Span::Cubic { control_one: c1, control_two: c2, end } }
fn ring(start: Point, spans: Vec<Span>) -> ReferenceRing { ReferenceRing { start, spans } }
fn glyph(rings: Vec<ReferenceRing>) -> DrawnGlyph { DrawnGlyph { glyph_id: "g".into(), rings } }
/// ReferenceRing/Span carry no PartialEq; compare the full debug rendering
/// (the repo's `same()` precedent in economy_eval tests).
fn same_ring(a: &ReferenceRing, b: &ReferenceRing) -> bool { format!("{:?}", a) == format!("{:?}", b) }

/// 100x100 square, four 90-degree line-into-line corners.
fn square() -> ReferenceRing {
    ring(pt(0., 0.), vec![line(pt(100., 0.)), line(pt(100., 100.)), line(pt(0., 100.)), line(pt(0., 0.))])
}

/// Two-cubic closed ring, G1-smooth at both joints (shared end/start tangent).
fn smooth_ring() -> ReferenceRing {
    ring(pt(0., 0.), vec![
        cubic(pt(0., -50.), pt(100., -50.), pt(100., 0.)),
        cubic(pt(100., 50.), pt(0., 50.), pt(0., 0.)),
    ])
}

#[test]
fn square_corners_split_into_explicit_pairs_and_collapse_back() {
    let r = square();
    let joints = observe_joints(&r, 1.0);
    assert_eq!(joints.len(), 4);
    assert!(joints.iter().all(|j| j.class == JointClass::Corner));
    assert!(joints.iter().all(|j| (j.turn_deg - 90.0).abs() < 1e-9));
    // Floor is derived from leg and grid: 2 * atan(1/100) in degrees.
    assert!(joints.iter().all(|j| (j.floor_deg - 2.0 * (1.0f64 / 100.0).atan().to_degrees()).abs() < 1e-9));
    let x = split_ring(&r, 1.0).unwrap();
    assert_eq!(x.nodes.len(), 8); // 4 corners, each split into exit+entry
    assert_eq!(x.connectors.iter().filter(|c| matches!(c, Connector::CornerLink(_))).count(), 4);
    assert!(verify_explicit_ring(&x, 1.0).is_empty());
    let back = collapse_ring(&x).unwrap();
    assert!(same_ring(&r, &back));
    let g = glyph(vec![r]);
    let xg = split_glyph(&g, 1.0).unwrap();
    let s = glyph_stats(&g, &xg, 1.0);
    assert_eq!(s, CornerSplitStats { rings: 1, nodes_before: 4, nodes_after: 8, corner_pairs: 4, hidden_breaks_before: 4, residual_breaks_after: 0, zero_tangents: 0 });
    assert!(same_ring(&g.rings[0], &collapse_glyph(&xg).unwrap().rings[0]));
}

#[test]
fn smooth_ring_keeps_single_nodes() {
    let r = smooth_ring();
    let joints = observe_joints(&r, 1.0);
    assert!(joints.iter().all(|j| j.class == JointClass::Smooth));
    assert!(joints.iter().all(|j| j.turn_deg == 0.0));
    let x = split_ring(&r, 1.0).unwrap();
    assert_eq!(x.nodes.len(), 2);
    assert!(x.connectors.iter().all(|c| matches!(c, Connector::Geometry(_))));
    assert!(verify_explicit_ring(&x, 1.0).is_empty());
    assert!(same_ring(&r, &collapse_ring(&x).unwrap()));
}

#[test]
fn only_real_corners_split_in_a_mixed_ring() {
    // B: G1-smooth cubic-into-cubic joint; C and A: 45-degree cubic/line corners.
    let r = ring(pt(0., 0.), vec![
        cubic(pt(0., -50.), pt(100., -50.), pt(100., 0.)),
        cubic(pt(100., 50.), pt(100., 100.), pt(50., 100.)),
        line(pt(0., 0.)),
    ]);
    let joints = observe_joints(&r, 1.0);
    assert_eq!(joints[0].class, JointClass::Corner); // A: line into cubic
    assert_eq!(joints[1].class, JointClass::Smooth); // B: shared tangent (0,50)
    assert_eq!(joints[2].class, JointClass::Corner); // C: cubic into line
    let x = split_ring(&r, 1.0).unwrap();
    assert_eq!(x.nodes.len(), 5);
    let s = glyph_stats(&glyph(vec![r.clone()]), &split_glyph(&glyph(vec![r.clone()]), 1.0).unwrap(), 1.0);
    assert_eq!((s.hidden_breaks_before, s.corner_pairs, s.nodes_before, s.nodes_after, s.residual_breaks_after), (2, 2, 3, 5, 0));
    assert!(same_ring(&r, &collapse_ring(&x).unwrap()));
}

#[test]
fn collapse_rejects_a_diverged_corner_link() {
    let mut x = split_ring(&square(), 1.0).unwrap();
    // Move the entry node of the first corner pair off the exit node.
    x.nodes[1].x += 1.0;
    // Connector ends still agree with the moved node, so the first failure
    // is the diverged link itself; rebuild connector ends to isolate it.
    if let Connector::Geometry(Span::Line { end }) = &mut x.connectors[1] { end.x += 1.0; }
    assert_eq!(collapse_ring(&x).unwrap_err(), CornerSplitError::DivergedCornerLink { node_index: 0 });
}

#[test]
fn verify_flags_breaks_hidden_on_ordinary_joints() {
    // Hand-built explicit ring: the square's corners were never split, so
    // every joint is an undeclared break - the exact C3 defect, now visible.
    let r = square();
    let nodes = vec![pt(0., 0.), pt(100., 0.), pt(100., 100.), pt(0., 100.)];
    let connectors = r.spans.iter().map(|s| Connector::Geometry(s.clone())).collect();
    let x = CornerExplicitRing { nodes, connectors };
    let issues = verify_explicit_ring(&x, 1.0);
    assert_eq!(issues.len(), 4);
    assert!(issues.iter().all(|i| matches!(i, ExplicitIssue::UndeclaredBreak { turn_deg, .. } if (*turn_deg - 90.0).abs() < 1e-9)));
}

#[test]
fn degenerate_tangents_fall_back_then_report_zero_tangent() {
    // control_two == end: the end tangent falls back to control_one.
    let r = ring(pt(0., 0.), vec![
        cubic(pt(0., -50.), pt(100., 0.), pt(100., 0.)),
        cubic(pt(100., 50.), pt(0., 50.), pt(0., 0.)),
    ]);
    let joints = observe_joints(&r, 1.0);
    assert!(joints.iter().all(|j| j.class != JointClass::ZeroTangent));
    // Fully degenerate span (every point equal): zero tangent is reported,
    // never silently classified smooth or corner.
    let d = ring(pt(7., 7.), vec![cubic(pt(7., 7.), pt(7., 7.), pt(7., 7.)), line(pt(7., 7.))]);
    let joints = observe_joints(&d, 1.0);
    assert!(joints.iter().all(|j| j.class == JointClass::ZeroTangent));
    let s = glyph_stats(&glyph(vec![d.clone()]), &split_glyph(&glyph(vec![d]), 1.0).unwrap(), 1.0);
    assert_eq!(s.zero_tangents, 2);
    assert_eq!(s.corner_pairs, 0);
}

#[test]
fn open_contour_is_a_typed_error_not_a_silent_closure() {
    let r = ring(pt(0., 0.), vec![line(pt(100., 0.)), line(pt(100., 100.))]);
    assert_eq!(split_ring(&r, 1.0).unwrap_err(), CornerSplitError::OpenContour);
}

#[test]
fn empty_ring_passes_through_unchanged() {
    // The space/.notdef contract: an intentionally empty ring stays empty.
    let r = ring(pt(0., 0.), vec![]);
    let x = split_ring(&r, 1.0).unwrap();
    assert!(x.nodes.is_empty() && x.connectors.is_empty());
    assert!(verify_explicit_ring(&x, 1.0).is_empty());
    let back = collapse_ring(&x).unwrap();
    assert!(back.spans.is_empty());
}

const K: f64 = 690.0 / 403.5087719298246;
const FX: [(&str, &str); 5] = [
    ("r_scan.png", "e820c617cd40ec517bb5e6e6daa01f948ae847de804474b3a78fc85071b3cbe0"),
    ("s_scan.png", "4d167e3b92af1fa27db5103bf87bd55048e926cd9f64406b769ac05be7b59add"),
    ("u_scan.png", "daf95988f8e779e0dfa361c86d798957f74a60b41c72d1191d27624282068fae"),
    ("dot_00b7.png", "33f0a1b27a357115174e881c168bc9df6989bf47e06aa627dfe894523349eae4"),
    ("quote_2018.png", "d7459752a33e6c80c95c31c06992b8e66908c233453c85e7e0c077878a0e3518"),
];

#[test]
fn fitted_real_scans_split_and_collapse_byte_identical() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
    let pol = FitPolicy { squared_error: 0.1, max_refits: 6 };
    let mut rows = Vec::new();
    for (name, _) in FX {
        let png = std::fs::read(format!("{}/{}", dir, name)).unwrap();
        let mc = capture_png(&png, 0.5).unwrap();
        let (rings, ..) = fit_captured(&mc.rings, K, &pol);
        let g = glyph(rings);
        let xg = split_glyph(&g, 1.0).unwrap();
        // Byte-identity of the representation on production-fitted output.
        let back = collapse_glyph(&xg).unwrap();
        assert_eq!(back.rings.len(), g.rings.len());
        for (a, b) in g.rings.iter().zip(back.rings.iter()) {
            assert!(same_ring(a, b), "{}: collapse changed the ring", name);
        }
        let s = glyph_stats(&g, &xg, 1.0);
        // No break may stay hidden after the split.
        assert_eq!(s.residual_breaks_after, 0, "{}: undeclared break survived the split", name);
        assert_eq!(s.nodes_after, s.nodes_before + s.corner_pairs, "{}: node accounting", name);
        assert_eq!(s.hidden_breaks_before, s.corner_pairs, "{}: every hidden break became an explicit pair", name);
        rows.push((name.to_string(), s));
    }
    println!("{}", render_report(&rows));
}
