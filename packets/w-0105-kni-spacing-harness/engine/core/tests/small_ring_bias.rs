//! Regression: small closed rings (dots, quotes) must not bulge outward of the captured ink.
//! With a dense-gate bound of two fit-tolerance units the fitted cubics of the kit middle dot and
//! left single quote carried ~0.5 px mean outward offset; the fitted area must stay close to the
//! captured polygon area (old bound: +1.2% and +2.2%; now +0.1% and -0.6%).

use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured_with_fallback_events;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{Point, Span};

fn cubic_pt(p0: Point, c1: Point, c2: Point, p3: Point, t: f64) -> Point {
    let v = 1.0 - t;
    Point {
        x: v * v * v * p0.x + 3.0 * v * v * t * c1.x + 3.0 * v * t * t * c2.x + t * t * t * p3.x,
        y: v * v * v * p0.y + 3.0 * v * v * t * c1.y + 3.0 * v * t * t * c2.y + t * t * t * p3.y,
    }
}

fn area(poly: &[Point]) -> f64 {
    let mut a = 0.0;
    for i in 0..poly.len() {
        let (u, v) = (poly[i], poly[(i + 1) % poly.len()]);
        a += u.x * v.y - v.x * u.y;
    }
    a / 2.0
}

// PN-3 fallback rescue: the damped-Newton rescue + corner resplit resolve
// the historical SplitUnresolved events on both fixtures at this policy, so
// both ledger counts pin to 0 (was: dot 3, quote 2). The area-fidelity
// contract below is unchanged and still asserted.
fn check(png: &[u8], expect_events: usize) {
    let mc = capture_png(png, 0.5).expect("capture");
    let scale = 1.0;
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (rings, _n, status, _d, fevents) = fit_captured_with_fallback_events(&mc.rings, scale, &policy);
    // Capture status derives from the finalized typed fallback ledger
    // (has_unresolved == !events.is_empty()). This asserts the status/ledger
    // contract, NOT a fit-quality claim.
    assert_eq!(status, !fevents.is_empty(), "status must derive from the finalized typed fallback ledger");
    assert_eq!(fevents.len(), expect_events, "typed fallback ledger count changed");
    assert!(
        fevents.iter().all(|e| matches!(e.reason, kni_core::capture_fit::FallbackReason::SplitUnresolved)),
        "unexpected fallback reason (expect SplitUnresolved only)"
    );
    let mut fit_area = 0.0;
    for r in &rings {
        let mut poly = vec![r.start];
        let mut cur = r.start;
        for sp in &r.spans {
            match sp {
                Span::Line { end } => { poly.push(*end); cur = *end; }
                Span::Cubic { control_one, control_two, end } => {
                    for i in 1..=16 { poly.push(cubic_pt(cur, *control_one, *control_two, *end, i as f64 / 16.0)); }
                    cur = *end;
                }
            }
        }
        fit_area += area(&poly).abs() * if r.start.x.is_nan() { 0.0 } else { 1.0 };
    }
    let mut src_area = 0.0;
    for r in &mc.rings { src_area += area(&r.points).abs(); }
    let rel = (fit_area - src_area) / src_area;
    assert!(rel < 0.01, "fitted ink area exceeds captured area by {:.1}%", rel * 100.0);
}

#[test]
fn middle_dot_does_not_bulge() { check(include_bytes!("fixtures/dot_00b7.png"), 0); }

#[test]
fn single_quote_does_not_bulge() { check(include_bytes!("fixtures/quote_2018.png"), 0); }
