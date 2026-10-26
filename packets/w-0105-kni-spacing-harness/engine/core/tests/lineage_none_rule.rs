//! PN-3 architect-approved lineage-None extension of rule (a): an in-bound
//! Line bottom-out WITHOUT lineage evidence is measured the same way as an
//! ambiguous-lineage one - the fragment's own sample count decides whether a
//! real measurement exists. >=3 samples within the dense bound: accepted
//! event-free with a typed DeclinedAmbiguity receipt (class NoLineage; this
//! branch wrote no receipt before the extension). Two samples: the event
//! stays (no interior measurement, honesty policy unchanged).
//!
//! Fixtures: real Marq/Standard collection tiles (glyph slots 00032 and
//! 00352). Measured receipts on base b4b4ec67 at
//! DIAG_SCALE = 1.9651741293532339 (style-scales.tsv), eps/se 0.25:
//! - marq_g_0067.png: pre-extension SplitUnresolved=1, the single SU event
//!   being the lineage-None in-bound n=3 fragment (arc 54, stub_dev
//!   0.665 fu, db 1.483 fu). The tile also carries 412
//!   AreaCollapseRestored events from the base's zero-area emission guard
//!   (MARQ dash sliver class) - an orthogonal mechanism this extension
//!   does not touch, so SU-class events are pinned, not the total.
//! - marq_invertedq_00bf.png: pre-extension SU=7 = 3 over-bound band lines
//!   + 1 lineage-None in-bound n=20 fragment (arc 12 s19-e38, stub_dev
//!   0.619 fu) + 3 two-sample fragments. Post-extension: SU=6 (3 band +
//!   3 two-sample), plus 187 orthogonal AreaCollapseRestored events.
//!   r297-REV guard (unresolved band windows skip the line-first accept):
//!   measured - arc10 s3e6 fits event- and receipt-free; the arc3 band
//!   region resolves with one two-sample bottom-out (arc3 s9e10, stop
//!   BudgetExhausted). SU=4 (3 two-sample + that bottom-out); NoLineage
//!   receipts 5 (arc12 n=20 + arc1 s4e7 + 3 two-sample).

use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::capture_source;
use kni_core::capture_fit::{fit_captured_with_typed_ledgers, DeclinedClass, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::jpeg_source::Limits;

const MARQ_SCALE: f64 = 1.9651741293532339;

fn fit_tile(png: &[u8]) -> (Vec<FallbackReason>, Vec<(DeclinedClass, usize, usize)>) {
    let png_limits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let src = capture_source(png, 0.25, &png_limits, jpeg_limits).expect("capture");
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let (_r, _n, _fb, _d, fevents, _astubs, declined) =
        fit_captured_with_typed_ledgers(&src.contour.rings, MARQ_SCALE, &policy);
    (
        fevents.iter().map(|e| e.reason).collect(),
        declined.iter().map(|d| (d.class, d.s, d.e)).collect(),
    )
}

fn split_unresolved(reasons: &[FallbackReason]) -> usize {
    reasons.iter().filter(|r| **r == FallbackReason::SplitUnresolved).count()
}

#[test]
fn g_lineage_none_inbound_fragment_resolves_event_free() {
    let png = include_bytes!("fixtures/marq_g_0067.png");
    let (reasons, declined) = fit_tile(png);
    let su = split_unresolved(&reasons);
    assert_eq!(su, 0, "g: the lineage-None in-bound n=3 fragment is accepted event-free, got SU={su}");
    let nl = declined.iter().filter(|d| d.0 == DeclinedClass::NoLineage).count();
    assert!(nl >= 1, "typed NoLineage receipt retained: {nl}");
}

#[test]
fn inverted_question_keeps_band_and_two_sample_events() {
    let png = include_bytes!("fixtures/marq_invertedq_00bf.png");
    let (reasons, declined) = fit_tile(png);
    let su = split_unresolved(&reasons);
    assert_eq!(su, 4, "inverted-question: 3 two-sample + 1 bottom-out (arc3 s9e10) SU events remain after the r297-REV guard, got SU={su}");
    let nl = declined.iter().filter(|d| d.0 == DeclinedClass::NoLineage).count();
    assert_eq!(nl, 5, "1 measured (n=20) + arc1 s4e7 + 3 two-sample NoLineage receipts, got {nl}");
    // The dropped event was the n=20 fragment: every surviving lineage-None
    // receipt's span is either measured (>=3 samples, receipt-only) or the
    // two-sample event carriers; no n>=3 lineage-None fragment may remain
    // eventful - the SU count above pins exactly that.
}
