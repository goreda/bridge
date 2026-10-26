//! Compatibility checker tests. Negative cases are one targeted edit each on
//! the reference fixture; positive cases are structure-preserving scales.

use kni_master::compat::check_set;
use kni_master::fixture::parse;
use kni_master::model::{MasterGlyph, Op};

fn reference() -> MasterGlyph {
    parse(include_str!("fixtures/reference_r.glyph")).expect("fixture parses")
}

/// Scale x by 2 (integer grid kept): same structure, different geometry.
fn widened(g: &MasterGlyph) -> MasterGlyph {
    let mut o = g.clone();
    o.advance *= 2.0;
    for c in &mut o.contours {
        for op in &mut c.ops {
            *op = match *op {
                Op::Move(p) => Op::Move((p.0 * 2.0, p.1)),
                Op::Line(p) => Op::Line((p.0 * 2.0, p.1)),
                Op::Curve(a, b, p) => Op::Curve((a.0 * 2.0, a.1), (b.0 * 2.0, b.1), (p.0 * 2.0, p.1)),
                Op::Close => Op::Close,
            };
        }
    }
    o
}

#[test]
fn identical_and_widened_masters_are_compatible() {
    let r = reference();
    let rep = check_set(&[r.clone(), r.clone()]);
    assert!(rep.rule_ok("C1") && rep.rule_ok("C3") && rep.rule_ok("C4") && rep.rule_ok("C5") && rep.rule_ok("C6") && rep.rule_ok("C7"), "{:#?}", rep.issues);
    let rep = check_set(&[r.clone(), widened(&r)]);
    for rule in ["C1", "C2", "C3", "C4", "C5", "C6"] {
        assert!(rep.rule_ok(rule), "{} {:#?}", rule, rep.issues);
    }
    assert_eq!(rep.validated.len(), 2);
}

#[test]
fn single_and_empty_sets_only_validate() {
    assert!(check_set(&[]).ok());
    assert_eq!(check_set(&[reference()]).validated.len(), 1);
}

#[test]
fn dropped_contour_is_c3() {
    let r = reference();
    let mut m = r.clone();
    m.contours.pop();
    assert!(!check_set(&[r, m]).rule_ok("C3"));
}

#[test]
fn swapped_stroke_order_is_c4() {
    let r = reference();
    let mut m = r.clone();
    m.contours.swap(0, 1);
    assert!(!check_set(&[r, m]).rule_ok("C4"));
}

#[test]
fn line_turned_curve_is_c5() {
    let r = reference();
    let mut m = r.clone();
    'o: for c in &mut m.contours {
        for i in 1..c.ops.len() {
            if let Op::Line(p) = c.ops[i].clone() {
                let q = match c.ops[i - 1] { Op::Move(a) | Op::Line(a) => a, Op::Curve(_, _, a) => a, Op::Close => continue };
                c.ops[i] = Op::Curve(q, p, p);
                break 'o;
            }
        }
    }
    assert!(!check_set(&[r, m]).rule_ok("C5"));
}

#[test]
fn reversed_contour_is_c6() {
    let r = reference();
    let mut m = r.clone();
    // Mirror y within the glyph: flips winding of every contour.
    for c in &mut m.contours {
        for op in &mut c.ops {
            *op = match *op {
                Op::Move(p) => Op::Move((p.0, -p.1)),
                Op::Line(p) => Op::Line((p.0, -p.1)),
                Op::Curve(a, b, p) => Op::Curve((a.0, -a.1), (b.0, -b.1), (p.0, -p.1)),
                Op::Close => Op::Close,
            };
        }
    }
    assert!(!check_set(&[r, m]).rule_ok("C6"));
}

#[test]
fn upm_and_name_mismatch() {
    let r = reference();
    let mut m = r.clone();
    m.upm += 1.0;
    m.name.push('x');
    let rep = check_set(&[r, m]);
    assert!(!rep.rule_ok("C1") && !rep.rule_ok("C2"));
}
