//! PN-3 regression: the Paul New photo tiles (JPEG, 786x1122) degrade
//! intended-curved regions to per-point Line fallback spans (measured:
//! exactly 2501 SplitUnresolved ledger events across the 132-tile cohort,
//! v11.2 warn tag). The fallback rescue (damped Newton refit + corner
//! resplit + chord-line terminal accept, all under the caller's dense
//! bound) resolves them. These tests pin the rescue on the cohort's worst
//! measured tiles and assert the ledger contract end-to-end.

use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::capture_source;
use kni_core::capture_fit::{fit_captured_with_typed_ledgers, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::jpeg_source::Limits;
use kni_core::reference_slice::Span;

const SCALE: f64 = 1000.0 / 1122.0; // declared convention: 786x1122 frame, K=1000/1122

fn check_tile(path: &str) {
    let bytes = std::fs::read(path).expect("tile readable");
    let png_limits = DecodeLimits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 24 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let src = capture_source(&bytes, 0.25, &png_limits, jpeg_limits).expect("capture");
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    for (domain, contour) in [("meas", &src.contour)].into_iter().chain(src.outline_contour.as_ref().map(|o| ("outline", o))) {
        let (rings, _n, _fb, _dropped, fevents, _astubs, _declined) =
            fit_captured_with_typed_ledgers(&contour.rings, SCALE, &policy);
        let unresolved = fevents.iter().filter(|e| e.reason != FallbackReason::SubGridSpan).count();
        assert_eq!(unresolved, 0, "{domain}: typed fallback ledger must be empty after the rescue, got {fevents:?}");
        // Rings still close exactly (rescue never breaks ring topology).
        for r in &rings {
            let last = match r.spans.last().unwrap() { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
            assert_eq!(last, r.start, "{domain}: ring must close exactly");
        }
    }
}

#[test]
fn period_tile_resolves_zero_fallback_events() {
    // The cohort's worst measured tile (123 meas / 139 outline events
    // pre-rescue): two-step spread corners + noisy short arcs.
    check_tile("tests/fixtures/paul136/026__002E__18c180f00dd5.jpg");
}

#[test]
fn d_tile_resolves_zero_fallback_events() {
    // Second-worst tile pre-rescue (8 meas / 13 outline events): long
    // near-straight hooks that failed plausibility within the dense bound.
    check_tile("tests/fixtures/paul136/030__0064__a472eb6cef30.jpg");
}
