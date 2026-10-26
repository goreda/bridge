//! r282: per-span fallback provenance rows bind to the finalized typed ledger.
//! Fixture: real Marq/Standard collection tile marq_invertedq_00bf.png, the
//! same input lineage_none_rule pins at SU=6. Every provenance row must pair
//! 1:1 with a finalized fallback event (same arc/s/e, same typed reason from
//! the producer branch) and carry measured px geometry from the producer
//! arc's own samples: chord never exceeds arc length, and no value is
//! invented (None stays None).

use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::capture_source;
use kni_core::capture_fit::{fit_captured_with_span_provenance, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::jpeg_source::Limits;

const MARQ_SCALE: f64 = 1.9651741293532339;

#[test]
fn provenance_rows_bind_one_to_one_with_finalized_events() {
    let png = include_bytes!("fixtures/marq_invertedq_00bf.png");
    let png_limits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let src = capture_source(png, 0.25, &png_limits, jpeg_limits).expect("capture");
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let (_r, _n, _fb, _d, fevents, _astubs, dec, fprov) =
        fit_captured_with_span_provenance(&src.contour.rings, MARQ_SCALE, &policy);
    assert!(!fevents.is_empty(), "fixture must produce fallback events");
    assert_eq!(fprov.len(), fevents.len(), "one provenance row per finalized event");
    let su = fevents.iter().filter(|e| e.reason == FallbackReason::SplitUnresolved).count();
    assert_eq!(su, 4, "fixture pin: 4 SplitUnresolved events (lineage_none_rule; r297-REV guard resolved the 3 band windows)");
    let max_ring = fevents.iter().map(|e| e.arc).max().unwrap_or(0);
    for (e, p) in fevents.iter().zip(fprov.iter()) {
        assert_eq!(p.reason, e.reason, "typed reason comes from the producer branch");
        // r288: the stop rides verbatim from the fallback event; the decline
        // class joins by construction (SU spans) or stays absent.
        assert_eq!(p.stop, e.stop, "provenance stop is the event's producer stop, verbatim");
        match e.reason {
            FallbackReason::SplitUnresolved => {
                let dc = p.decline.expect("SU span joins its sibling declined-ambiguity receipt");
                assert!(dec.iter().any(|d| (d.arc, d.s, d.e) == (e.arc, e.s, e.e) && d.class == dc),
                    "joined decline class exists in the finalized declined ledger");
            }
            _ => {
                assert!(p.decline.is_none(), "non-SU event classes carry no decline class");
                assert!(p.stop.is_none(), "non-SU event classes have no producer stop");
            }
        }
        assert!(p.ring < 1024, "ring index is a real ring ordinal, got {}", p.ring);
        assert!(p.ring <= max_ring + 1024, "ring index sane");
        if e.reason == FallbackReason::AreaCollapseRestored {
            // ring-level event: no arc fragment; perimeter is the measured arc length
            assert_eq!(p.arc, usize::MAX);
            assert!(p.chord_px.is_none() && p.max_dev_px.is_none());
            assert!(p.arc_len_px.unwrap_or(0.0) > 0.0, "restored ring perimeter measured");
            continue;
        }
        assert_eq!((p.arc, p.s, p.e), (e.arc, e.s, e.e), "span identity binds to the event");
        assert_ne!(p.arc, usize::MAX, "arc-level events keep their arc index");
        let chord = p.chord_px.expect("chord measured");
        let arc_len = p.arc_len_px.expect("arc length measured");
        let max_dev = p.max_dev_px.expect("max deviation measured");
        assert!(chord >= 0.0 && arc_len >= 0.0 && max_dev >= 0.0);
        assert!(chord <= arc_len + 1e-9, "chord cannot exceed arc length: {chord} vs {arc_len}");
        assert!(arc_len > 0.0, "a multi-sample fragment has positive length");
    }
    // Producer reasons stay typed across the ledger; no row is reason-less.
    assert!(fprov.iter().all(|p| matches!(p.reason,
        FallbackReason::SplitUnresolved | FallbackReason::DepthLimit |
        FallbackReason::DegenerateTangents | FallbackReason::SubGridSpan |
        FallbackReason::AreaCollapseRestored)));
}
