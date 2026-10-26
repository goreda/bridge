//! P0 circle-pass regression tests (architect position 2026-10-11):
//! phantom circles on rectilinear bar rings (a rectangle's 4 corners are
//! concyclic, so vertex-only Kasa residual is ~0 by construction), the
//! small-ring corner blindness that let them through, and the derived
//! acceptance/abstention thresholds.

use kni_core::capture::corners;
use kni_core::capture_fit::fit_ring;
use kni_core::cubic_fit::FitPolicy;
use kni_core::form::recognize_circle_ring;
use kni_core::reference_slice::{Point, Span};

fn pt(x: f64, y: f64) -> Point {
    Point { x, y }
}

/// Closed CCW (y-up) polygon on a circle.
fn circle_pts(cx: f64, cy: f64, r: f64, n: usize) -> Vec<Point> {
    (0..n)
        .map(|i| {
            let a = i as f64 / n as f64 * std::f64::consts::TAU;
            pt(cx + r * a.cos(), cy + r * a.sin())
        })
        .collect()
}

/// RDP-like rectangle ring: 4 true corners + near-corner duplicates,
/// the shape real bar captures take after simplification.
fn bar_ring(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<Point> {
    vec![
        pt(x0 + 1.0, y0 + 2.0),
        pt(x0 + 1.0, y1),
        pt(x1, y1),
        pt(x1 - 1.0, y1 - 2.0),
        pt(x1 - 1.0, y0),
        pt(x0, y0),
    ]
}

#[test]
fn small_rectangle_ring_reports_four_corners() {
    let ring = bar_ring(0.0, 0.0, 100.0, 14.0);
    let cs = corners(&ring);
    assert_eq!(cs.len(), 4, "6-point rectangle ring must report 4 corners, got {:?}", cs);
}

#[test]
fn small_rectangle_ring_fits_without_circle_or_fallback() {
    let ring = bar_ring(0.0, 0.0, 100.0, 14.0);
    let cs = corners(&ring);
    assert_eq!(cs.len(), 4, "4 corners");
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (fitted, nspans, fb) = fit_ring(ring, cs, &policy);
    assert!(!fb, "clean rectangle must not fall back");
    // Ruling target is 4 LINE spans (corner-to-corner). Today's fit emits
    // cubics for 3-point arcs (near-duplicate points left between corners),
    // so 4-LINE lands with P1 line-first fitting; the binding regressions
    // here are: no phantom circle, no fallback, exact closure.
    assert!(nspans >= 4, "at least one span per corner arc, got {}", nspans);
    let cubic_runs = fitted
        .spans
        .iter()
        .filter(|s| matches!(s, Span::Cubic { .. }))
        .count();
    assert!(cubic_runs != 4 || fitted.spans.len() != 4, "must not be a 4-cubic circle pattern");
    let last_end = match fitted.spans.last().unwrap() {
        Span::Line { end } => *end,
        Span::Cubic { end, .. } => *end,
    };
    assert_eq!(last_end, fitted.start, "ring must close exactly");
}

#[test]
fn bar_ring_is_not_a_circle() {
    // Actual C-card bar ring (gi=2 ring1), capture px scaled by 0.8945.
    let s = 0.8945;
    let ring: Vec<Point> = [
        (167.0, 2.0), (168.0, 56.0), (558.0, 56.0), (559.0, 56.0),
        (559.0, 2.0), (558.0, 0.0), (168.0, 0.0),
    ]
    .iter()
    .map(|&(x, y)| pt(x * s, y * s))
    .collect();
    assert!(
        recognize_circle_ring(&ring, &[], false, 1.0 * s, 0.5 * s).is_none(),
        "a rectangle's concyclic corners must not pass as a circle"
    );
}

#[test]
fn true_circle_is_accepted() {
    // r=125 font units, dense perimeter, eps=0.5: derived coverage limit
    // 1.5*2*sqrt(2*0.5/125) = 15.4 deg; dense 64-pt ring gap ~5.6 deg.
    let ring = circle_pts(400.0, 400.0, 125.0, 64);
    let out = recognize_circle_ring(&ring, &[], false, 1.0, 0.5);
    assert!(out.is_some(), "true r=125 circle must be accepted");
    let ring = out.unwrap();
    assert_eq!(ring.spans.len(), 4, "circle emits 4 kappa cubics");
    for s in &ring.spans {
        assert!(matches!(s, Span::Cubic { .. }));
    }
}

#[test]
fn octagon_is_not_a_circle() {
    // sagitta r*(1-cos(pi/8)) = 9.5 at r=125 >> T_circle=1.0: dense edge
    // midpoints fail the radial residual.
    let ring = circle_pts(400.0, 400.0, 125.0, 8);
    assert!(recognize_circle_ring(&ring, &[], false, 1.0, 0.5).is_none());
}

#[test]
fn ellipse_is_not_a_circle() {
    // aspect 1.1: bbox w/h vs 2r mismatch exceeds T_circle.
    let ring: Vec<Point> = (0..64)
        .map(|i| {
            let a = i as f64 / 64.0 * std::f64::consts::TAU;
            pt(400.0 + 125.0 * a.cos(), 400.0 + 137.5 * a.sin())
        })
        .collect();
    assert!(recognize_circle_ring(&ring, &[], false, 1.0, 0.5).is_none());
}

#[test]
fn small_circle_abstains_to_cubic_fit() {
    // r=10, eps=0.5: coverage limit = 1.5*2*sqrt(2*0.5/10) = 54 deg > 45 deg
    // -> evidence insufficient, must abstain (fall through to cubic fit).
    let ring = circle_pts(400.0, 400.0, 10.0, 64);
    assert!(recognize_circle_ring(&ring, &[], false, 1.0, 0.5).is_none());
}

#[test]
fn declared_corners_still_skip() {
    let ring = circle_pts(400.0, 400.0, 125.0, 64);
    assert!(recognize_circle_ring(&ring, &[3], false, 1.0, 0.5).is_none());
}

#[test]
fn near_duplicate_pair_does_not_mask_or_fake_a_corner() {
    use kni_core::capture::dedup_ring;
    // A near-duplicate pair (0.3 < rdp eps 0.5) before the real corner:
    // unfiltered, the k=1 direct turn reads the dup pair as a sharp corner.
    let ring = vec![
        pt(0.0, 0.0), pt(50.0, 0.0), pt(50.0, 0.3), pt(100.0, 0.0), pt(100.0, 50.0), pt(0.0, 50.0),
    ];
    let dd = dedup_ring(&ring, 0.5);
    assert_eq!(dd.len(), 5, "near-duplicate dropped, got {:?}", dd.len());
    let cs = corners(&dd);
    assert_eq!(cs.len(), 4, "rectangle's 4 corners, got {:?}", cs);
    assert!(!cs.contains(&1), "the collinear midpoint (50,0) is not a corner: {:?}", cs);
}

/// Sample an emitted span set, return the max distance of any sampled point
/// from the straight chord start->end for the spans covering [0,100] on y=0.
fn max_excursion_on_chord(ring: &kni_core::reference_slice::ReferenceRing) -> f64 {
    let mut cur = ring.start;
    let mut worst = 0.0f64;
    for s in &ring.spans {
        match s {
            Span::Line { end } => {
                cur = *end;
            }
            Span::Cubic { control_one, control_two, end } => {
                for k in 1..=64 {
                    let t = k as f64 / 64.0;
                    let mt = 1.0 - t;
                    let x = mt * mt * mt * cur.x
                        + 3.0 * mt * mt * t * control_one.x
                        + 3.0 * mt * t * t * control_two.x
                        + t * t * t * end.x;
                    let y = mt * mt * mt * cur.y
                        + 3.0 * mt * mt * t * control_one.y
                        + 3.0 * mt * t * t * control_two.y
                        + t * t * t * end.y;
                    if (0.0..=100.0).contains(&x) {
                        worst = worst.max(y.abs());
                    }
                }
                cur = *end;
            }
        }
    }
    worst
}

#[test]
fn three_collinear_points_no_above_bound_excursion() {
    // Pentagon = rectangle with a collinear midpoint on the bottom edge;
    // the bottom corner arc holds exactly 3 collinear points. The dense gate
    // must keep the emitted curve on the chord (no tail-bulge-class bowing).
    let ring = vec![pt(0.0, 0.0), pt(50.0, 0.0), pt(100.0, 0.0), pt(100.0, 50.0), pt(0.0, 50.0)];
    let cs = corners(&ring);
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (fitted, _, fb) = fit_ring(ring, cs, &policy);
    assert!(!fb);
    let db = 0.5 + 2.0 * policy.squared_error.sqrt(); // dense_bound at scale 1
    let exc = max_excursion_on_chord(&fitted);
    assert!(exc <= db, "excursion {} exceeds dense bound {}", exc, db);
}

#[test]
fn three_point_spike_rejects_cubic_and_splits_to_lines() {
    // Same ring but the bottom edge midpoint spiked 25 units out with NO
    // declared corner there: the dense gate must refuse the bulging cubic;
    // the argmax split then divides at the spike -> two straight spans.
    let ring = vec![pt(0.0, 0.0), pt(50.0, 25.0), pt(100.0, 0.0), pt(100.0, 50.0), pt(0.0, 50.0)];
    let cs = vec![0, 2, 3, 4];
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (fitted, _, fb) = fit_ring(ring, cs, &policy);
    assert!(!fb);
    // find the spans covering the spike region: between (0,0) and (100,0)
    // there must be a Line through the spike point, not a bulging cubic.
    let mut cur = fitted.start;
    let mut saw_spike_line = false;
    for s in &fitted.spans {
        if let Span::Line { end } = s {
            if ((cur.x - 50.0).abs() < 1.0 && (cur.y - 25.0).abs() < 1.0)
                || ((end.x - 50.0).abs() < 1.0 && (end.y - 25.0).abs() < 1.0)
            {
                saw_spike_line = true;
            }
        }
        cur = match s {
            Span::Line { end } => *end,
            Span::Cubic { end, .. } => *end,
        };
    }
    assert!(saw_spike_line, "spike must be served by LINE spans after gate rejection");
}

#[test]
fn corner_vertex_dropped_but_turn_preserved_within_eps() {
    use kni_core::capture::dedup_ring;
    // Near-duplicates on BOTH sides of the corner vertex (100,0.2): the
    // vertex itself may be dropped (incoming neighbor kept); the corner's
    // TURN must survive at a kept point within rdp eps of the true corner.
    let ring = vec![
        pt(0.0, 0.0), pt(99.8, 0.0), pt(100.0, 0.2), pt(100.2, 50.0), pt(0.0, 50.0),
    ];
    let dd = dedup_ring(&ring, 0.5);
    let cs = corners(&dd);
    assert_eq!(cs.len(), 4, "quadrilateral corners, got {:?}", cs);
    let near_corner = cs.iter().any(|&i| {
        (dd[i].x - 100.0).hypot(dd[i].y - 0.2) <= 0.5
    });
    assert!(near_corner, "a corner survives within rdp eps of (100,0.2): {:?}", cs.iter().map(|&i| (dd[i].x, dd[i].y)).collect::<Vec<_>>());
}
