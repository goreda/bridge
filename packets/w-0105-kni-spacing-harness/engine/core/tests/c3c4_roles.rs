//! Unit tests for c3c4_roles. All fixtures are SYNTHETIC FIXTURES.
use kni_core::c3c4_roles::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn line(e: Point) -> Span { Span::Line { end: e } }
fn cubic(c1: Point, c2: Point, e: Point) -> Span { Span::Cubic { control_one: c1, control_two: c2, end: e } }
fn ring(start: Point, spans: Vec<Span>) -> ReferenceRing { ReferenceRing { start, spans } }

#[test]
fn noise_declared_when_no_axis_aligned_lines() {
    // synthetic fixture: one diagonal-only ring
    let r = ring(p(0.0, 0.0), vec![line(p(10.0, 10.0)), line(p(0.0, 0.0))]);
    let n = measure_noise(&[r]);
    assert_eq!(n.origin, NoiseOrigin::Declared);
    assert_eq!(n.sigma, 0.0);
    assert!(n.effective_sigma() > 0.0); // quantisation floor still applies
}

#[test]
fn noise_measured_rms_over_sqrt2() {
    // synthetic fixture: two near-horizontal lines with perpendicular mismatch +2 and -2
    let r = ring(p(0.0, 0.0), vec![
        line(p(100.0, 2.0)),    // near-horizontal, dy = +2
        line(p(0.0, 0.0)),      // near-horizontal backwards, dy = -2
    ]);
    let n = measure_noise(&[r]);
    assert_eq!(n.origin, NoiseOrigin::Measured);
    let expect = (((2.0f64 * 2.0 + 2.0 * 2.0) / 2.0) / 2.0).sqrt();
    assert!((n.sigma - expect).abs() < 1e-12);
    assert!(n.derivation.contains("measured") || n.derivation.contains("RMS"));
}

#[test]
fn c3_axis_aligned_and_deviant_and_abstain() {
    // synthetic fixture: horizontal line, 45-degree line, zero-length cubic handle
    let r = ring(p(0.0, 0.0), vec![
        line(p(100.0, 0.0)),                                  // deviation 0 -> aligned
        line(p(200.0, 100.0)),                                // 45 degrees, deviation pi/4 -> deviant
        cubic(p(200.0, 100.0), p(150.0, 100.0), p(0.0, 0.0)), // out-handle zero -> abstain
    ]);
    let n = measure_noise(&[r.clone()]);
    let rep = c3_measure(&[r], &n, InputPath::Vector);
    assert_eq!(rep.path, "vector");
    assert_eq!(rep.elements.len(), 4); // 2 line dirs + 2 cubic handles
    assert_eq!(rep.elements[0].class, AxisClass::Aligned);
    assert!((rep.elements[0].deviation_rad.unwrap() - 0.0).abs() < 1e-15);
    assert_eq!(rep.elements[1].class, AxisClass::Deviant);
    assert!((rep.elements[1].deviation_rad.unwrap() - std::f64::consts::FRAC_PI_4).abs() < 1e-12);
    assert!(matches!(rep.elements[2].class, AxisClass::Abstain(_)));
    assert_eq!(rep.aligned + rep.deviant + rep.abstain, rep.elements.len());
    assert!(rep.conventions.iter().any(|c| c.contains("CONVENTION")));
    assert_eq!(rep.noise.origin, n.origin);
}

#[test]
fn c4_smooth_corner_abstain() {
    // synthetic fixture: straight-through join (0 rad), 90-degree join, zero tangent join
    let r = ring(p(0.0, 0.0), vec![
        line(p(100.0, 0.0)),   // node 1: in (100,0)->... out ...
        line(p(200.0, 0.0)),   // join at node 1: straight -> smooth
        line(p(200.0, 100.0)), // join at node 2: 90 deg -> corner
        cubic(p(200.0, 100.0), p(200.0, 100.0), p(0.0, 0.0)), // zero in/out handles
    ]);
    let n = measure_noise(&[r.clone()]);
    let rep = c4_measure(&[r], &n, InputPath::Image);
    assert_eq!(rep.path, "image");
    assert_eq!(rep.nodes.len(), 4);
    assert_eq!(rep.nodes[1].class, JoinClass::Smooth);
    assert!((rep.nodes[1].join_rad.unwrap() - 0.0).abs() < 1e-15);
    assert_eq!(rep.nodes[2].class, JoinClass::Corner);
    assert!((rep.nodes[2].join_rad.unwrap() - std::f64::consts::FRAC_PI_2).abs() < 1e-12);
    assert!(matches!(rep.nodes[3].class, JoinClass::Abstain(_)));
    assert_eq!(rep.smooth + rep.corner + rep.abstain, rep.nodes.len());
}

#[test]
fn c4_wraps_on_closed_ring() {
    // synthetic fixture: triangle, every corner 60 or 120 degrees -> all corner at any noise floor
    let r = ring(p(0.0, 0.0), vec![line(p(100.0, 0.0)), line(p(50.0, 86.60254037844386)), line(p(0.0, 0.0))]);
    let n = NoiseRecord { sigma: 0.0, origin: NoiseOrigin::Declared, derivation: "test declared".into() };
    let rep = c4_measure(&[r], &n, InputPath::Vector);
    assert_eq!(rep.nodes.len(), 3);
    assert!(rep.nodes.iter().all(|x| x.class == JoinClass::Corner));
}

#[test]
fn reports_carry_noise_record_and_convention_label() {
    let r = ring(p(0.0, 0.0), vec![line(p(10.0, 0.0)), line(p(0.0, 0.0))]);
    let n = measure_noise(&[r.clone()]);
    let c3 = c3_measure(&[r.clone()], &n, InputPath::Vector);
    let c4 = c4_measure(&[r], &n, InputPath::Vector);
    assert_eq!(c3.noise.origin, n.origin);
    assert_eq!(c4.noise.origin, n.origin);
    assert!(!c3.conventions.is_empty() && !c4.conventions.is_empty());
}
