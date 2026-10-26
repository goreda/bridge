//! Synthetic tests for the vector-path rows A1, A2 and A3.

use kni_master::fixture;
use kni_master::model::MasterGlyph;
use kni_master::validate::Params;
use kni_master::vector::PathLabel;
use kni_master::vector_rows::*;

fn g(body: &str) -> MasterGlyph {
    fixture::parse(&format!("glyph t 500 1000\nstroke s\n{body}\n")).unwrap()
}

const RECT: &str = "M 0 0\nL 100 0\nL 100 700\nL 0 700\nZ";
const CIRCLE: &str = "M 0 50\nC 0 78 22 100 50 100\nC 78 100 100 78 100 50\nC 100 22 78 0 50 0\nC 22 0 0 22 0 50\nZ";

fn gp(limit: Option<f64>) -> GuideParams {
    GuideParams {
        link: 5.0,
        min_edges: 1,
        declared_spread_limit: limit.map(|v| Declared { value: v, derivation: "test value".into() }),
    }
}

#[test]
fn a1_copy_has_zero_offsets_and_unevaluated_abstain_without_a_declared_limit() {
    let src = g(RECT);
    let p = Params::derive(&src).unwrap();
    let r = guide_fidelity(&src, &src, p, &gp(None));
    assert_eq!(r.label, PathLabel::Vector);
    assert_eq!(r.classes.len(), 2);
    for k in &r.classes {
        assert_eq!(k.status, ClassStatus::NotEvaluated);
        assert_eq!(k.nodes, 2);
        assert_eq!(k.median_offset, Some(0.0));
        assert_eq!(k.max_abs_offset, Some(0.0));
    }
    assert!(r.rows().iter().all(|row| row.starts_with("vector\tA1\t")));
    assert!(r.rows()[0].contains("declared, not measured: unavailable"));
}

#[test]
fn a1_signed_offset_and_declared_limit() {
    let src = g(RECT);
    let master = g("M 0 0\nL 100 0\nL 100 701\nL 0 701\nZ");
    let p = Params::from_rounding(2.0);
    let r = guide_fidelity(&master, &src, p, &gp(Some(1.0)));
    let top = r.classes.iter().find(|k| k.value == 700.0).unwrap();
    assert_eq!(top.status, ClassStatus::Active);
    assert_eq!(top.median_offset, Some(1.0));
    let bottom = r.classes.iter().find(|k| k.value == 0.0).unwrap();
    assert_eq!(bottom.median_offset, Some(0.0));
    assert_eq!(r.unassigned_nodes, 0);
}

#[test]
fn a1_node_outside_the_class_window_is_unassigned_not_snapped() {
    let src = g(RECT);
    let master = g("M 0 0\nL 100 0\nL 100 710\nL 0 710\nZ");
    let r = guide_fidelity(&master, &src, Params::from_rounding(2.0), &gp(Some(1.0)));
    assert_eq!(r.unassigned_nodes, 2);
    let top = r.classes.iter().find(|k| k.value == 700.0).unwrap();
    assert_eq!(top.nodes, 0);
    assert_eq!(top.median_offset, None);
}

#[test]
fn a1_wide_class_spread_makes_nodes_abstain() {
    // Two flat tops 4 units apart form one class with a measured spread above the declared limit.
    let two = "M 0 0\nL 100 0\nL 100 700\nL 0 700\nZ\nstroke t\nM 200 0\nL 300 0\nL 300 704\nL 200 704\nZ";
    let src = g(two);
    let r = guide_fidelity(&src, &src, Params::from_rounding(2.0), &gp(Some(1.0)));
    let top = r.classes.iter().find(|k| k.value > 100.0).unwrap();
    assert!(top.measured_spread > 1.0);
    assert_eq!(top.status, ClassStatus::Abstained);
    assert_eq!(top.abstained_nodes, top.nodes);
    assert_eq!(top.median_offset, None);
}

#[test]
fn a1_no_flat_edges_is_na_not_zero() {
    let src = g(CIRCLE);
    let r = guide_fidelity(&src, &src, Params::derive(&src).unwrap(), &gp(None));
    assert!(r.classes.is_empty());
    assert_eq!(r.rows(), vec!["vector\tA1\tn/a (no flat edges in the source)".to_string()]);
}

#[test]
fn a2_identical_smooth_nodes_are_within() {
    let src = g(CIRCLE);
    let r = join_angle(&src, &src, A2Params { smooth_class_tol_deg: 5.0 });
    assert_eq!(r.verdict, JoinVerdict::Within);
    assert_eq!(r.master.unwrap().nodes, 4);
    assert!(r.rows()[0].starts_with("vector\tA2\t"));
}

#[test]
fn a2_a_bent_handle_exceeds_the_source_noise() {
    let src = g(CIRCLE);
    let master = g("M 0 50\nC 0 78 22 100 50 100\nC 78 100 100 78 100 50\nC 101 22 78 0 50 0\nC 22 0 0 22 0 50\nZ");
    let r = join_angle(&master, &src, A2Params { smooth_class_tol_deg: 5.0 });
    assert_eq!(r.verdict, JoinVerdict::Exceeds);
    let m = r.master.unwrap();
    assert!((m.max - (1.0f64 / 28.0).atan().to_degrees()).abs() < 1e-9);
}

#[test]
fn a2_source_without_smooth_nodes_is_na() {
    let src = g(RECT);
    let master = g(CIRCLE);
    let r = join_angle(&master, &src, A2Params { smooth_class_tol_deg: 5.0 });
    assert_eq!(r.verdict, JoinVerdict::NotAvailable("source has no smooth curve nodes"));
    assert!(r.rows()[0].contains("n/a (source has no smooth curve nodes)"));
}

#[test]
fn a3_identity_mapping_and_refusal_for_a_different_master() {
    let src = g(CIRCLE);
    let p = Params::derive(&src).unwrap();
    let r = curvature_variation(&src, Some(&src), p).unwrap();
    assert_eq!(r.mapping, Mapping::Identity);
    assert_eq!(r.added_extrema, AddedExtrema::IdentityTrivial);
    assert!(r.rows_text().last().unwrap().contains("n/a (identity mapping, trivially 0)"));
    assert_eq!(r.rows.len(), 4);
    for row in &r.rows {
        let v = row.values.unwrap();
        assert_eq!(v.sign_changes, 0);
        assert!(v.max_dk_ds >= 0.0 && v.rms_dk_ds >= 0.0 && v.rms_dk_ds <= v.max_dk_ds + 1e-12);
    }
    let other = g("M 0 50\nC 0 78 22 100 50 100\nC 78 100 100 78 100 50\nC 100 22 78 0 50 0\nC 22 0 0 23 0 50\nZ");
    assert_eq!(curvature_variation(&other, Some(&src), p).unwrap_err(), A3Error::MappingUndefined);
}

#[test]
fn a3_master_alone_has_no_added_extrema_value() {
    let m = g(CIRCLE);
    let r = curvature_variation(&m, None, Params::derive(&m).unwrap()).unwrap();
    assert_eq!(r.mapping, Mapping::MasterOnly);
    assert_eq!(r.added_extrema, AddedExtrema::NoSourceMapping);
    assert!(r.rows_text().last().unwrap().contains("n/a (no source mapping)"));
}

#[test]
fn a3_s_curve_changes_sign_once_and_a_straight_cubic_has_zero_curvature() {
    let s = g("M 0 0\nC 0 100 100 -100 100 0\nZ");
    let r = curvature_variation(&s, None, Params::derive(&s).unwrap()).unwrap();
    assert_eq!(r.rows[0].values.unwrap().sign_changes, 1);
    let line = g("M 0 0\nC 30 0 60 0 100 0\nL 100 50\nZ");
    let r = curvature_variation(&line, None, Params::derive(&line).unwrap()).unwrap();
    let v = r.rows[0].values.unwrap();
    assert_eq!((v.sign_changes, v.max_dk_ds), (0, 0.0));
}

#[test]
fn a3_zero_tangent_is_na() {
    let c = g("M 0 0\nC 0 0 50 50 100 0\nZ");
    let r = curvature_variation(&c, None, Params::derive(&c).unwrap()).unwrap();
    assert!(r.rows[0].values.is_none());
    assert!(r.rows_text()[0].contains("n/a (zero tangent)"));
}
