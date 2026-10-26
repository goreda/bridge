//! Regression tests for the vector path (master-mode regression item):
//! determinism, typed refusals, row format, label discipline. No node count
//! from any glyph is used as a norm.

use kni_master::fixture::parse;
use kni_master::model::{MasterGlyph, Op, StrokeContour};
use kni_master::validate::{Params, ValidateError};
use kni_master::vector::{analyse, analyse_with, MasterFill, PathLabel, VectorError};

fn rect(x0: f64, w: f64) -> MasterGlyph {
    let l = |x: f64, y: f64| Op::Line((x, y));
    MasterGlyph {
        name: "t".into(),
        advance: 500.0,
        upm: 1000.0,
        contours: vec![StrokeContour {
            stroke: "r".into(),
            ops: vec![Op::Move((x0, 0.0)), l(x0 + w, 0.0), l(x0 + w, 20.0), l(x0, 20.0), Op::Close],
        }],
    }
}

#[test]
fn the_report_is_deterministic() {
    let m = parse(include_str!("fixtures/reference_r.glyph")).unwrap();
    let s = parse(include_str!("fixtures/reference_r_export.glyph")).unwrap();
    let a = analyse(&m, &s, MasterFill::UnionOfStrokes).unwrap().rows();
    let b = analyse(&m, &s, MasterFill::UnionOfStrokes).unwrap().rows();
    assert_eq!(a, b);
}

#[test]
fn row_format_is_label_row_quantity_value_unit() {
    let r = analyse_with(&rect(0.0, 10.0), &rect(3.0, 10.0), Params::from_rounding(0.5), MasterFill::UnionOfStrokes).unwrap();
    for row in r.rows() {
        let f: Vec<&str> = row.split('\t').collect();
        assert_eq!(f.len(), 5, "{row}");
        assert_eq!(f[0], PathLabel::Vector.as_str());
        assert!(!f[3].is_empty());
    }
}

#[test]
fn a_drawing_with_no_pitch_is_refused_not_guessed() {
    let mut g = rect(0.0, 10.0);
    if let Op::Move(p) = &mut g.contours[0].ops[0] {
        *p = (0.0123456, 0.0);
    }
    let e = analyse(&g, &rect(0.0, 10.0), MasterFill::UnionOfStrokes).err();
    assert_eq!(e, Some(VectorError::Pitch(ValidateError::NoPitch)));
}

#[test]
fn an_empty_outline_is_a_typed_error() {
    let empty = MasterGlyph { name: "e".into(), advance: 0.0, upm: 1000.0, contours: vec![] };
    let e = analyse_with(&empty, &rect(0.0, 10.0), Params::from_rounding(0.5), MasterFill::UnionOfStrokes).err();
    assert_eq!(e, Some(VectorError::EmptyOutline));
}

#[test]
fn an_oversized_outline_hits_the_edge_budget_not_memory() {
    // a many-sided polygon beyond the resource limit
    let n = kni_master::vector::MAX_EDGES + 8;
    let mut ops = vec![Op::Move((0.0, 0.0))];
    for i in 1..n {
        let a = i as f64 / n as f64 * std::f64::consts::TAU;
        ops.push(Op::Line((100.0 * a.cos(), 100.0 * a.sin())));
    }
    ops.push(Op::Close);
    let big = MasterGlyph {
        name: "big".into(),
        advance: 0.0,
        upm: 1000.0,
        contours: vec![StrokeContour { stroke: "p".into(), ops }],
    };
    let e = analyse_with(&big, &rect(0.0, 10.0), Params::from_rounding(0.5), MasterFill::UnionOfStrokes).err();
    assert!(matches!(e, Some(VectorError::EdgeBudget { .. })), "{e:?}");
}

#[test]
fn a_copy_of_the_source_never_depends_on_the_source_glyph() {
    // any outline copied as master reports geometry equal to itself
    for w in [7.0, 130.0, 411.0] {
        let g = rect(0.0, w);
        let r = analyse_with(&g, &g, Params::from_rounding(0.5), MasterFill::Merged).unwrap();
        assert!(r.fidelity.symdiff_area < 1e-9 && r.fidelity.hausdorff < 1e-9, "{:?}", r.fidelity);
    }
}
