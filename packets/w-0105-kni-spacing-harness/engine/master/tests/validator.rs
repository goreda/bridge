//! Validator tests (rules R1-R7). Negative cases are built from the reference
//! fixture by one targeted edit each; no test asserts a node count as a norm.

use kni_master::fixture::parse;
use kni_master::model::{MasterGlyph, Op, StrokeContour};
use kni_master::raster::polygons;
use kni_master::validate::{silhouette_gate, validate as validate_res, Params, Report, Role, ValidateError};

fn validate(g: &MasterGlyph) -> Report {
    validate_res(g).expect("pitch")
}

fn reference() -> MasterGlyph {
    parse(include_str!("fixtures/reference_r.glyph")).expect("fixture parses")
}

fn stroke<'a>(g: &'a mut MasterGlyph, n: &str) -> &'a mut StrokeContour {
    g.contours.iter_mut().find(|c| c.stroke == n).unwrap()
}

#[test]
fn reference_fixture_passes_r1_to_r6() {
    let r = validate(&reference());
    assert!(r.ok(), "violations: {:#?}", r.violations);
}

#[test]
fn every_node_has_a_role_and_hidden_nodes_are_wraps() {
    let g = reference();
    let r = validate(&g);
    let nodes: usize = g.contours.iter().map(|c| c.nodes().len()).sum();
    assert_eq!(r.roles.len(), nodes, "every node classified (a node without a role is a violation)");
    assert!(r.roles.iter().any(|x| x.2 == Role::Wrap));
    assert!(r.roles.iter().any(|x| x.2 == Role::Extremum));
}

#[test]
fn params_come_from_the_glyph() {
    let r = validate(&reference());
    assert_eq!(r.params.grid, 0.5, "integer drawing => half-unit rounding error");
    let mut g = reference();
    for c in &mut g.contours {
        for o in &mut c.ops {
            *o = match o.clone() {
                Op::Move(p) => Op::Move((p.0 / 2.0, p.1 / 2.0)),
                Op::Line(p) => Op::Line((p.0 / 2.0, p.1 / 2.0)),
                Op::Curve(a, b, p) => Op::Curve((a.0 / 2.0, a.1 / 2.0), (b.0 / 2.0, b.1 / 2.0), (p.0 / 2.0, p.1 / 2.0)),
                Op::Close => Op::Close,
            };
        }
    }
    let r2 = validate(&g);
    assert!(r2.ok(), "a half-scale drawing validates on its own tolerances: {:#?}", r2.violations);
}

#[test]
fn r1_duplicate_stroke_name_and_duplicate_outline() {
    let mut g = reference();
    let dup = g.contours[2].clone();
    g.contours.push(dup);
    let r = validate(&g);
    assert!(!r.rule_ok("R1"));
}

#[test]
fn r1_open_contour() {
    let mut g = reference();
    stroke(&mut g, "leg").ops.pop();
    assert!(!validate(&g).rule_ok("R1"));
}

#[test]
fn r2_counter_as_separate_contour() {
    let mut g = reference();
    // an opposite-winding ring strictly inside the stem
    let l = |x: f64, y: f64| Op::Line((x, y));
    g.contours.push(StrokeContour {
        stroke: "counter".into(),
        ops: vec![Op::Move((80.0, 300.0)), l(80.0, 400.0), l(100.0, 400.0), l(100.0, 300.0), Op::Close],
    });
    let r = validate(&g);
    assert!(!r.rule_ok("R2"), "{:#?}", r.violations);
}

#[test]
fn r3_collinear_midpoint() {
    let mut g = reference();
    stroke(&mut g, "stem").ops.insert(1, Op::Line((125.0, 400.0)));
    assert!(!validate(&g).rule_ok("R3"));
}

#[test]
fn r3_duplicate_node() {
    let mut g = reference();
    stroke(&mut g, "stem").ops.insert(2, Op::Line((125.0, 690.0)));
    assert!(!validate(&g).rule_ok("R3"));
}

#[test]
fn r4_curve_on_a_straight_stroke() {
    let mut g = reference();
    let leg = stroke(&mut g, "leg");
    // replace the leg's first line by a curve whose handles lie on the chord
    leg.ops[1] = Op::Curve((115.0, 255.0), (115.0, 305.0), (115.0, 281.0));
    let r = validate(&g);
    assert!(!r.rule_ok("R4"), "{:#?}", r.violations);
}

#[test]
fn r5_corner_implied_by_handle_collision() {
    let mut g = reference();
    // collapse a curve's out-handle onto its end node at a real corner
    let bowl = stroke(&mut g, "bowl");
    if let Op::Curve(_, c2, p) = &mut bowl.ops[4] {
        *c2 = *p; // zero-length handle at the (310,690) CL joint: curve into a line
    }
    let r = validate(&g);
    assert!(r.violations.iter().any(|v| v.rule == "R5" || v.rule == "R3"), "{:#?}", r.violations);
}

#[test]
fn r6_hidden_non_corner_node() {
    let mut g = reference();
    // a hidden curve node strictly inside the stem
    let leg = stroke(&mut g, "leg");
    // a hidden node that touches a curve inside the stem overlap
    leg.ops[2] = Op::Curve((112.0, 270.0), (100.0, 250.0), (90.0, 240.0));
    let r = validate(&g);
    assert!(!r.rule_ok("R6"), "{:#?}", r.violations);
}

#[test]
fn r6_hidden_curve() {
    let mut g = reference();
    g.contours.push(StrokeContour {
        stroke: "blob".into(),
        ops: vec![
            Op::Move((90.0, 300.0)),
            Op::Curve((95.0, 305.0), (95.0, 310.0), (90.0, 315.0)),
            Op::Curve((85.0, 310.0), (85.0, 305.0), (90.0, 300.0)),
            Op::Close,
        ],
    });
    assert!(!validate(&g).rule_ok("R6"));
}

// ---- R7 -------------------------------------------------------------------

/// Expected outline = hand-merged union of two overlapping rectangles.
#[test]
fn r7_overlap_master_matches_merged_export() {
    let l = |x: f64, y: f64| Op::Line((x, y));
    let rect = |n: &str, x0: f64, y0: f64, x1: f64, y1: f64| StrokeContour {
        stroke: n.into(),
        ops: vec![Op::Move((x0, y0)), l(x1, y0), l(x1, y1), l(x0, y1), Op::Close],
    };
    let g = MasterGlyph {
        name: "L".into(),
        advance: 400.0,
        upm: 1000.0,
        contours: vec![rect("stem", 0.0, 0.0, 100.0, 600.0), rect("foot", 50.0, 0.0, 350.0, 100.0)],
    };
    let merged = vec![vec![(0.0, 0.0), (350.0, 0.0), (350.0, 100.0), (100.0, 100.0), (100.0, 600.0), (0.0, 600.0)]];
    let gate = silhouette_gate(&g, &merged).unwrap();
    assert!(gate.pass, "{gate:?}");
    assert_eq!(gate.miss_px + gate.excess_px, 0);

    // shift the foot 12 units: the gate must fail
    let mut bad = g.clone();
    for o in &mut bad.contours[1].ops {
        if let Op::Line(p) | Op::Move(p) = o {
            p.1 += 12.0;
        }
    }
    let gate = silhouette_gate(&bad, &merged).unwrap();
    assert!(!gate.pass, "{gate:?}");
    let _ = polygons(&g);
}

#[test]
fn r7_noise_floor_is_measured_not_fixed() {
    let l = |x: f64, y: f64| Op::Line((x, y));
    let g = MasterGlyph {
        name: "tri".into(),
        advance: 300.0,
        upm: 1000.0,
        contours: vec![StrokeContour { stroke: "a".into(), ops: vec![Op::Move((0.0, 0.0)), l(200.0, 0.0), l(100.0, 173.0), Op::Close] }],
    };
    let merged = polygons(&g);
    let gate = silhouette_gate(&g, &merged).unwrap();
    assert!(gate.noise_iou < 1.0 && gate.noise_iou > 0.8, "diagonal edges give a nonzero measured noise: {}", gate.noise_iou);
    assert!(gate.pass);
}

/// R7 on the reference R: master (3 strokes) vs the 21-node export
/// outline (2 contours), same unit frame, no frame mapping needed.
#[test]
fn r7_reference_master_vs_export() {
    use kni_master::raster::polygons;
    let master = reference();
    let export = parse(include_str!("fixtures/reference_r_export.glyph")).unwrap();
    let exp_polys = polygons(&export);
    let gate = silhouette_gate(&master, &exp_polys).unwrap();
    eprintln!("R7 reference: {gate:?}");
    assert!(gate.pass, "{gate:?}");
}

#[test]
fn pitch_is_derived_or_reported_missing() {
    // arbitrary float coordinates: no pitch, an error instead of a silent floor
    let mut g = reference();
    if let Op::Move(p) = &mut g.contours[0].ops[0] {
        *p = (258.0 + 0.0123456, 338.0);
    }
    assert_eq!(validate_res(&g).err(), Some(ValidateError::NoPitch));
    // the caller supplies the rounding error and validation proceeds
    let r = kni_master::validate::validate_with(&g, Params::from_rounding(0.05));
    assert!(r.params.margin == 0.1);
}

#[test]
fn margin_is_one_drawing_step() {
    let r = validate(&reference());
    assert_eq!(r.params.margin, 2.0 * r.params.grid);
    assert_eq!(r.params.margin, 1.0, "integer drawing: one unit, as before");
}

#[test]
fn pixel_budget_is_an_error_not_an_allocation() {
    let g = reference();
    let huge = vec![vec![(0.0, 0.0), (1.0e7, 0.0), (1.0e7, 1.0e7)]];
    let e = silhouette_gate(&g, &huge).err();
    assert!(matches!(e, Some(ValidateError::PixelBudget { .. })), "{e:?}");
}

/// MANDATORY: the gate stays discriminating at the looser noise floor. A
/// 12-unit misplacement fails; the measured floor on the reference is
/// recorded by r7_reference_master_vs_export (stderr).
#[test]
fn r7_twelve_unit_misplacement_still_fails() {
    r7_overlap_master_matches_merged_export();
}
