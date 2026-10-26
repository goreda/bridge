//! PN-3 architect rule (a): an in-bound ambiguous-lineage Line whose
//! fragment carries a REAL measurement (>=3 samples, chord deviation <= the
//! dense bound) is accepted event-free; the typed DeclinedAmbiguity receipt
//! is retained in full. A two-sample fragment (no interior measurement)
//! keeps its SplitUnresolved event.

use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::capture_source;
use kni_core::capture_fit::{fit_captured_with_typed_ledgers, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::jpeg_source::Limits;

fn fit_tile(png: &[u8]) -> (usize, usize, Vec<(usize, usize)>) {
    let png_limits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let src = capture_source(png, 0.25, &png_limits, jpeg_limits).expect("capture");
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let scale = 2.4377; // kit PNG-scan route scale (style-scales.tsv family)
    let (_r, _n, _fb, _d, fevents, _astubs, declined) =
        fit_captured_with_typed_ledgers(&src.contour.rings, scale, &policy);
    let fragments: Vec<(usize, usize)> = fevents
        .iter()
        .filter(|e| e.reason == FallbackReason::SplitUnresolved)
        .map(|e| (e.s, e.e))
        .collect();
    (fevents.len(), declined.len(), fragments)
}

#[test]
fn s_scan_resolves_event_free_with_receipts_retained() {
    let png = include_bytes!("fixtures/s_scan.png");
    let (events, declined, _fragments) = fit_tile(png);
    assert_eq!(events, 0, "s scan: all bottom-out fragments are in-bound measured lines");
    assert!(declined > 0, "typed DeclinedAmbiguity receipts are retained: {declined}");
}

#[test]
fn quote_keeps_event_on_two_sample_fragment() {
    let png = include_bytes!("fixtures/quote_2018.png");
    let (events, declined, fragments) = fit_tile(png);
    assert_eq!(events, 1, "quote: one fragment remains, got {events}");
    // The surviving event is the measured two-sample fragment (s7..e8): no
    // interior point, so no real deviation measurement - event retained.
    assert!(fragments.iter().all(|&(s, e)| e - s + 1 < 3), "surviving events must be sub-3-sample fragments: {fragments:?}");
    assert!(declined > 0, "typed receipts retained: {declined}");
}
