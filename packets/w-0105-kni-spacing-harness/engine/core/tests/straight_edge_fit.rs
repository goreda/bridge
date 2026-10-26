//! Regression: straight edges of a rasterised glyph must not be emitted as bowed cubics.
//! The fixture is the kit 'U' (straight diagonal serifs). Before the straight-over-curve
//! pass, serif edges whose raw boundary points lie on a line were emitted as cubics with
//! handles several units off the chord (measured on kit U: 0.9377 -> 0.9765 with the pass).

use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured_with_fallback_events;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::Span;

#[test]
fn straight_serif_edges_are_not_bowed() {
    let png = include_bytes!("fixtures/u_scan.png");
    let mc = capture_png(png, 0.5).expect("capture");
    let scale = 1000.0 / 1050.0; // adaptive scale of the kit battery (1000 / source image height)
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (rings, _n, status, _d, fevents) = fit_captured_with_fallback_events(&mc.rings, scale, &policy);
    // Capture status derives from the finalized typed fallback ledger
    // (has_unresolved == !events.is_empty()). This asserts the status/ledger
    // contract, NOT a fit-quality claim.
    assert_eq!(status, !fevents.is_empty(), "status must derive from the finalized typed fallback ledger");
    // PN-3 fallback rescue + architect rule (a) (in-bound ambiguous-lineage
    // Lines with a real measurement accepted event-free, typed receipts
    // retained): 7 -> 0.
    assert_eq!(fevents.len(), 0, "typed fallback ledger count changed");
    assert!(
        fevents.iter().all(|e| matches!(e.reason, kni_core::capture_fit::FallbackReason::SplitUnresolved)),
        "unexpected fallback reason (expect SplitUnresolved only)"
    );
    for r in &rings {
        let mut cur = r.start;
        for sp in &r.spans {
            match sp {
                Span::Line { end } => cur = *end,
                Span::Cubic { control_one, control_two, end } => {
                    let (dx, dy) = (end.x - cur.x, end.y - cur.y);
                    let l = dx.hypot(dy);
                    if l > 60.0 {
                        let sag = |c: &kni_core::reference_slice::Point| (dx * (c.y - cur.y) - dy * (c.x - cur.x)).abs() / l;
                        let sag_ratio = sag(control_one).max(sag(control_two)) / l;
                        // a long span whose handles hug the chord (< 2% of length) is a straight
                        // edge and must be a Line, not a cubic
                        assert!(sag_ratio > 0.02, "long near-straight cubic: len {:.1} sag ratio {:.4}", l, sag_ratio);
                    }
                    cur = *end;
                }
            }
        }
    }
}
