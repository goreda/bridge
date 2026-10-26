//! Vector-path measurement tests: exact-geometry fidelity, exact extrema,
//! path labels. The reference R fixtures are a learning case for structure;
//! no test here compares any glyph to a node count taken from R.

use kni_master::fixture::parse;
use kni_master::model::{MasterGlyph, Op, StrokeContour};
use kni_master::validate::Params;
use kni_master::vector::{
    analyse, analyse_with, exact_extrema, rasterised_cross_check, vector_fidelity, Axis, MasterFill, PathLabel, Verdict,
};

fn poly(name: &str, pts: &[(f64, f64)]) -> StrokeContour {
    let mut ops = vec![Op::Move(pts[0])];
    for p in &pts[1..] {
        ops.push(Op::Line(*p));
    }
    ops.push(Op::Close);
    StrokeContour { stroke: name.into(), ops }
}

fn glyph(contours: Vec<StrokeContour>) -> MasterGlyph {
    MasterGlyph { name: "t".into(), advance: 500.0, upm: 1000.0, contours }
}

fn rect(x0: f64) -> MasterGlyph {
    glyph(vec![poly("r", &[(x0, 0.0), (x0 + 10.0, 0.0), (x0 + 10.0, 20.0), (x0, 20.0)])])
}

fn params() -> Params {
    Params::from_rounding(0.5)
}

fn l_master() -> MasterGlyph {
    glyph(vec![
        poly("stem", &[(0.0, 0.0), (100.0, 0.0), (100.0, 600.0), (0.0, 600.0)]),
        poly("foot", &[(50.0, 0.0), (350.0, 0.0), (350.0, 100.0), (50.0, 100.0)]),
    ])
}

fn l_export() -> MasterGlyph {
    glyph(vec![poly(
        "outline",
        &[(0.0, 0.0), (350.0, 0.0), (350.0, 100.0), (100.0, 100.0), (100.0, 600.0), (0.0, 600.0)],
    )])
}

#[test]
fn shifted_rectangles_have_exact_area_and_hausdorff() {
    let f = vector_fidelity(&rect(0.0), &rect(3.0), params(), MasterFill::UnionOfStrokes).unwrap();
    assert!((f.symdiff_area - 120.0).abs() < 1e-9, "{f:?}");
    assert!((f.source_area - 200.0).abs() < 1e-9);
    assert!((f.symdiff_fraction - 0.6).abs() < 1e-9);
    assert!((f.hausdorff - 3.0).abs() < 1e-9, "{f:?}");
    assert_eq!(f.label, PathLabel::Vector);
}

#[test]
fn edge_crossings_are_integrated_exactly() {
    // square 10x10 against a diamond of half-diagonal 8 centred on it:
    // intersection 92, so symmetric difference (100-92)+(128-92) = 44.
    let sq = glyph(vec![poly("s", &[(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)])]);
    let dia = glyph(vec![poly("d", &[(5.0, -3.0), (13.0, 5.0), (5.0, 13.0), (-3.0, 5.0)])]);
    let f = vector_fidelity(&sq, &dia, params(), MasterFill::UnionOfStrokes).unwrap();
    assert!((f.symdiff_area - 44.0).abs() < 1e-9, "{f:?}");
    assert!((f.source_area - 128.0).abs() < 1e-9);
}

#[test]
fn overlapping_strokes_match_the_merged_outline() {
    let f = vector_fidelity(&l_master(), &l_export(), params(), MasterFill::UnionOfStrokes).unwrap();
    assert!(f.symdiff_area < 1e-9, "{f:?}");
    assert!(f.hausdorff <= f.distance_floor, "{f:?}");
}

#[test]
fn moved_stroke_leaves_the_floors_and_grows_with_the_move() {
    let shifted = |dy: f64| {
        let mut g = l_master();
        for o in &mut g.contours[1].ops {
            if let Op::Line(p) | Op::Move(p) = o {
                p.1 += dy;
            }
        }
        g
    };
    let a = vector_fidelity(&shifted(12.0), &l_export(), params(), MasterFill::UnionOfStrokes).unwrap();
    let b = vector_fidelity(&shifted(24.0), &l_export(), params(), MasterFill::UnionOfStrokes).unwrap();
    assert!(a.symdiff_area > a.area_floor, "{a:?}");
    assert!(a.hausdorff > a.distance_floor, "{a:?}");
    assert!(b.symdiff_area > a.symdiff_area && b.hausdorff > a.hausdorff, "{a:?} {b:?}");
}

#[test]
fn a_master_that_copies_its_source_is_unchanged() {
    let source = parse(include_str!("fixtures/reference_r_export.glyph")).unwrap();
    let pitch = Params::derive(&parse(include_str!("fixtures/reference_r.glyph")).unwrap()).unwrap();
    let r = analyse_with(&source, &source, pitch, MasterFill::Merged).unwrap();
    assert_eq!(r.verdict, Verdict::Unchanged, "{:?}", r.fidelity);
    assert!(r.fidelity.symdiff_area < 1e-9);
    assert!(r.fidelity.hausdorff < 1e-9);
}

#[test]
fn fewer_nodes_at_equal_distance_is_improved() {
    // a source with a collinear midpoint node; the master drops it
    let source = glyph(vec![poly("s", &[(0.0, 0.0), (5.0, 0.0), (10.0, 0.0), (10.0, 20.0), (0.0, 20.0)])]);
    let master = rect(0.0);
    let r = analyse_with(&master, &source, params(), MasterFill::UnionOfStrokes).unwrap();
    assert_eq!(r.verdict, Verdict::Improved, "{:?}", r.fidelity);
    assert!(r.nodes_master < r.nodes_source);
}

#[test]
fn more_nodes_or_moved_geometry_is_differs_not_an_error() {
    let r = analyse_with(&l_master(), &l_export(), params(), MasterFill::UnionOfStrokes).unwrap();
    assert_eq!(r.verdict, Verdict::Differs, "same geometry but more nodes");
    let r = analyse_with(&rect(0.0), &rect(3.0), params(), MasterFill::UnionOfStrokes).unwrap();
    assert_eq!(r.verdict, Verdict::Differs);
}

fn arc(split: bool) -> MasterGlyph {
    let ops = if split {
        vec![
            Op::Move((0.0, 0.0)),
            Op::Curve((0.0, 5.0), (2.5, 7.5), (5.0, 7.5)),
            Op::Curve((7.5, 7.5), (10.0, 5.0), (10.0, 0.0)),
            Op::Close,
        ]
    } else {
        vec![Op::Move((0.0, 0.0)), Op::Curve((0.0, 10.0), (10.0, 10.0), (10.0, 0.0)), Op::Close]
    };
    glyph(vec![StrokeContour { stroke: "arc".into(), ops }])
}

#[test]
fn extremum_without_node_is_found_exactly_and_covered_after_a_split() {
    let r = exact_extrema(&arc(false), params());
    assert_eq!(r.curve_segments, 1);
    assert_eq!(r.missing.len(), 1, "{r:?}");
    let m = &r.missing[0];
    assert_eq!(m.axis, Axis::Y);
    assert!((m.t - 0.5).abs() < 1e-12 && (m.point.0 - 5.0).abs() < 1e-9 && (m.point.1 - 7.5).abs() < 1e-9, "{m:?}");
    let s = exact_extrema(&arc(true), params());
    assert!(s.missing.is_empty(), "{s:?}");
}

#[test]
fn extrema_check_reads_geometry_not_labels() {
    // the same arc as one stroke named anything: result depends on points only
    let mut g = arc(false);
    g.contours[0].stroke = "extremum-covered".into();
    assert_eq!(exact_extrema(&g, params()).missing.len(), 1);
}

#[test]
fn every_row_carries_the_path_label_and_the_raster_check_is_labelled_separately() {
    let r = analyse_with(&rect(0.0), &rect(3.0), params(), MasterFill::UnionOfStrokes).unwrap();
    let rows = r.rows();
    assert!(!rows.is_empty());
    assert!(rows.iter().all(|s| s.starts_with("vector\t")), "{rows:?}");
    let (label, _gate) = rasterised_cross_check(&l_master(), &l_export()).unwrap();
    assert_eq!(label, PathLabel::VectorRasterised);
    assert_ne!(label.as_str(), PathLabel::Vector.as_str());
}

#[test]
fn learning_case_reports_counts_without_gating_on_them() {
    let master = parse(include_str!("fixtures/reference_r.glyph")).unwrap();
    let source = parse(include_str!("fixtures/reference_r_export.glyph")).unwrap();
    let r = analyse(&master, &source, MasterFill::UnionOfStrokes).expect("reference pair measures");
    assert_eq!(r.label, PathLabel::Vector);
    // counts are reported, never compared with a constant
    assert!(r.rows().iter().any(|s| s.contains("\tnodes\tmaster\t")));
    assert!(r.rows().iter().any(|s| s.contains("\tnodes\tsource\t")));
}
