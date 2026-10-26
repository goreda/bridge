//! PN-3 speck KEEP+FLAG oracle: a positive-area sub-pixel ring is retained as
//! its own measured minimal contour (all-Line ring through its captured
//! points, scaled) and ledgered; the fitter is never consulted for it (no
//! fallback events); only a capture with no representation (zero-area 1/2
//! point traces) still counts in `dropped`.
use kni_core::capture::CapturedRing;
use kni_core::capture_fit::{fit_captured_with_typed_ledgers, reset_speck_areas, reset_speck_retained_hole, speck_areas_since, speck_retained_hole, speck_marker};
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{Point, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn ring(points: Vec<Point>) -> CapturedRing {
    CapturedRing { raw: points.clone(), points, corners: Vec::new(), hole: false }
}

const POLICY: FitPolicy = FitPolicy { squared_error: 0.25, max_refits: 8 };
const SCALE: f64 = 2.0;

#[test]
fn positive_area_speck_is_retained_as_minimal_contour() {
    // 0.4 x 0.4 px square: capture area 0.16 px^2 (< 0.5): a speck.
    let speck = ring(vec![p(10.0, 10.0), p(10.4, 10.0), p(10.4, 10.4), p(10.0, 10.4)]);
    // A normal ring well above the threshold (20 x 20 px square).
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    let marker = speck_marker();
    let (rings, _spans, _fb, dropped, fevents, _astubs, _declined) =
        fit_captured_with_typed_ledgers(&[speck, big], SCALE, &POLICY);
    assert_eq!(dropped, 0, "a positive-area speck is never dropped");
    let areas = speck_areas_since(marker);
    assert_eq!(areas.len(), 1, "one speck ledgered");
    assert!((areas[0] - 0.16).abs() < 1e-9, "ledgered area is the capture-space polygon area: {}", areas[0]);
    let speck_ring = rings.iter().find(|r| (r.start.x - 20.0).abs() < 1e-9 && (r.start.y - 20.0).abs() < 1e-9)
        .expect("the speck ring ships (start = first captured point, scaled)");
    assert!(speck_ring.spans.iter().all(|s| matches!(s, Span::Line { .. })), "minimal contour is Line spans only");
    assert_eq!(speck_ring.spans.len(), 4, "square speck: 4 closing Line spans");
    // The contour is the speck's OWN polygon (scaled) - closed back to start.
    let last_end = match speck_ring.spans.last() { Some(Span::Line { end }) => *end, other => panic!("{other:?}") };
    assert!((last_end.x - speck_ring.start.x).abs() < 1e-9 && (last_end.y - speck_ring.start.y).abs() < 1e-9, "ring closes to its start");
    assert!(fevents.is_empty(), "the speck path consults no fitter: no fallback events, got {}", fevents.len());
}

#[test]
fn grid_collapsed_speck_is_the_only_dropped_class() {
    // All points identical: positive-width trace collapsed to one capture
    // point; no representation exists at any grid. This is the only class
    // that still counts in `dropped`.
    let point = ring(vec![p(5.0, 5.0)]);
    let segment = ring(vec![p(5.0, 5.0), p(7.0, 5.0)]);
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    let marker = speck_marker();
    let (_rings, _spans, _fb, dropped, _fe, _a, _d) =
        fit_captured_with_typed_ledgers(&[point, segment, big], SCALE, &POLICY);
    assert_eq!(dropped, 2, "zero-area 1/2-point traces are truly unrepresentable");
    assert!(speck_areas_since(marker).is_empty(), "no speck ledgered for unrepresentable captures");
}

#[test]
fn speck_free_run_ledgers_nothing() {
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    let marker = speck_marker();
    let (_r, _s, _fb, dropped, _fe, _a, _d) = fit_captured_with_typed_ledgers(&[big], SCALE, &POLICY);
    assert_eq!(dropped, 0);
    assert!(speck_areas_since(marker).is_empty());
}

fn hole_ring(points: Vec<Point>) -> CapturedRing {
    CapturedRing { raw: points.clone(), points, corners: Vec::new(), hole: true }
}

fn emitted_area2(r: &kni_core::reference_slice::ReferenceRing) -> f64 {
    let mut pts = vec![r.start];
    for sp in &r.spans {
        if let Span::Line { end } = sp { pts.push(*end); }
    }
    kni_core::capture::ring_area2(&pts)
}

#[test]
fn hole_flagged_speck_ships_hole_wound_and_is_counted() {
    // A hole-flagged sub-pixel ring measured negative space: it ships as its
    // own minimal contour, hole-wound (negative signed area), and the hole
    // subset is counted in the typed speck_retained_hole row. Never dropped
    // for its class.
    let hole = hole_ring(vec![p(10.0, 10.0), p(10.4, 10.0), p(10.4, 10.4), p(10.0, 10.4)]);
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    reset_speck_retained_hole();
    let marker = speck_marker();
    let (rings, _spans, _fb, dropped, _fe, _a, _d) =
        fit_captured_with_typed_ledgers(&[hole, big], SCALE, &POLICY);
    assert_eq!(dropped, 0, "a hole-flagged speck is never dropped for its class");
    assert_eq!(speck_retained_hole(), 1, "typed retained-hole row counts it");
    let areas = speck_areas_since(marker);
    assert_eq!(areas.len(), 1, "the hole speck is ledgered like any retained speck");
    let speck_ring = rings.iter().find(|r| (r.start.x - 20.0).abs() < 1e-9 && (r.start.y - 20.0).abs() < 1e-9)
        .expect("the hole speck ships as its own measured contour");
    assert!(emitted_area2(speck_ring) < 0.0, "the hole speck ships hole-wound (negative signed area)");
    reset_speck_retained_hole();
}

#[test]
fn emitted_speck_is_exterior_wound_and_on_grid() {
    // Clockwise captured speck: the emitted contour is normalized to
    // exterior (positive signed area) winding, and every emitted point
    // sits on the integer emission lattice (rd rounding).
    let cw = ring(vec![p(10.0, 10.0), p(10.0, 10.4), p(10.4, 10.4), p(10.4, 10.0)]);
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    let (rings, _spans, _fb, dropped, _fe, _a, _d) =
        fit_captured_with_typed_ledgers(&[cw, big], SCALE, &POLICY);
    assert_eq!(dropped, 0);
    let speck_ring = rings.iter().find(|r| (r.start.x - 20.0).abs() < 1e-9 && (r.start.y - 20.0).abs() < 1e-9)
        .expect("the CW speck ships");
    assert!(emitted_area2(speck_ring) > 0.0, "emitted speck is exterior-wound");
    let mut pts = vec![speck_ring.start];
    for sp in &speck_ring.spans { if let Span::Line { end } = sp { pts.push(*end); } }
    assert!(pts.iter().all(|q| q.x.fract() == 0.0 && q.y.fract() == 0.0), "emitted speck points are on the integer lattice: {pts:?}");
}

#[test]
fn rounded_collinear_speck_is_grid_unrepresentable_and_dropped() {
    // A thin streak whose rounded points collapse onto one lattice line:
    // zero signed area at the grid, same unrepresentable class as the
    // single-point collapse. Capture polygon area stays positive pre-round.
    let streak = ring(vec![p(10.0, 10.10), p(10.4, 10.12), p(10.4, 10.20), p(10.0, 10.15)]);
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    let marker = speck_marker();
    let (_rings, _spans, _fb, dropped, _fe, _a, _d) =
        fit_captured_with_typed_ledgers(&[streak, big], SCALE, &POLICY);
    assert_eq!(dropped, 1, "post-round collinear collapse counts as dropped");
    assert!(speck_areas_since(marker).is_empty(), "no speck ledgered for a grid-unrepresentable capture");
}

#[test]
fn ccw_speck_keeps_exterior_winding_on_the_same_grid() {
    // Counter-clockwise (already exterior) captured speck: the emitted
    // contour stays exterior-wound and lands on the same lattice points as
    // the clockwise input case - winding normalization is invariant, not a
    // flip-everything rule.
    let ccw = ring(vec![p(10.0, 10.0), p(10.4, 10.0), p(10.4, 10.4), p(10.0, 10.4)]);
    let big = ring(vec![p(0.0, 0.0), p(20.0, 0.0), p(20.0, 20.0), p(0.0, 20.0)]);
    reset_speck_areas();
    let (rings, _spans, _fb, dropped, _fe, _a, _d) =
        fit_captured_with_typed_ledgers(&[ccw, big], SCALE, &POLICY);
    assert_eq!(dropped, 0);
    let speck_ring = rings.iter().find(|r| (r.start.x - 20.0).abs() < 1e-9 && (r.start.y - 20.0).abs() < 1e-9)
        .expect("the CCW speck ships");
    let a2 = emitted_area2(speck_ring);
    assert!(a2 > 0.0, "emitted speck keeps positive signed area, got {a2}");
    let mut pts = vec![speck_ring.start];
    for sp in &speck_ring.spans { if let Span::Line { end } = sp { pts.push(*end); } }
    assert!(pts.iter().all(|q| q.x.fract() == 0.0 && q.y.fract() == 0.0), "emitted speck points are on the integer lattice: {pts:?}");
}

#[test]
fn multiple_hole_specks_each_ship_hole_wound_and_count() {
    // Two hole-flagged sub-pixel rings plus one exterior speck: all three
    // ship; holes are negative-wound, the exterior positive-wound; the
    // retained-hole row counts exactly the holes.
    let h1 = hole_ring(vec![p(10.0, 10.0), p(10.4, 10.0), p(10.4, 10.4), p(10.0, 10.4)]);
    let h2 = hole_ring(vec![p(30.0, 30.0), p(30.3, 30.0), p(30.3, 30.3), p(30.0, 30.3)]);
    let ext = ring(vec![p(50.0, 50.0), p(50.4, 50.0), p(50.4, 50.4), p(50.0, 50.4)]);
    let big = ring(vec![p(0.0, 0.0), p(200.0, 0.0), p(200.0, 200.0), p(0.0, 200.0)]);
    reset_speck_areas();
    reset_speck_retained_hole();
    let marker = speck_marker();
    let (rings, _spans, _fb, dropped, _fe, _a, _d) =
        fit_captured_with_typed_ledgers(&[h1, h2, ext, big], SCALE, &POLICY);
    assert_eq!(dropped, 0, "no ring drops: holes and the exterior all ship");
    assert_eq!(speck_retained_hole(), 2, "typed retained-hole row counts exactly the holes");
    let areas = speck_areas_since(marker);
    assert_eq!(areas.len(), 3, "every retained speck is ledgered, holes included");
    let h1r = rings.iter().find(|r| (r.start.x - 20.0).abs() < 1e-9 && (r.start.y - 20.0).abs() < 1e-9).expect("h1 ships");
    let h2r = rings.iter().find(|r| (r.start.x - 60.0).abs() < 1e-9 && (r.start.y - 60.0).abs() < 1e-9).expect("h2 ships");
    let extr = rings.iter().find(|r| (r.start.x - 100.0).abs() < 1e-9 && (r.start.y - 100.0).abs() < 1e-9).expect("the exterior ships");
    assert!(emitted_area2(h1r) < 0.0 && emitted_area2(h2r) < 0.0, "holes ship negative-wound");
    assert!(emitted_area2(extr) > 0.0, "the exterior ships positive-wound");
    reset_speck_retained_hole();
}
