//! Paul New declared tile-frame state PresentRing (style-spec): the pinned
//! production tiles carry the printed 2px presentation frame as a closed
//! rectangle ring hugging the tile edges. FramePolicy::SeparatePresentRing
//! separates ONLY the jointly-proven ring for the OUTLINE domain (one
//! contiguous end-to-end ink line per edge, the SAME measured thickness on
//! all four edges, corners closed by construction); edge-fused letterform
//! stripes are glyph content and are never cleared. The measurement domain
//! keeps the original capture, byte for byte; a tile without the full
//! closed ring is a no-op.
//!
//! Regression for the edge-fused stripe swallow (percent / perthousand /
//! quoteleft class) of the per-edge band growth (f2f6fea8): on the pinned
//! percent tile the old rule measured (top,bottom,left,right)=(2,2,2,58)
//! and deleted a real stripe (8 source rings -> 6). The joint ring rule
//! measures (2,2,2,2) on the same bytes and loses none (8 -> 7: the frame
//! ring only). 92ee4a24's PreserveAllInk bypass kept the stripes but also
//! kept the frame; both defects are pinned below.
use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::{capture_source, capture_source_with_policy, decode_source, FramePolicy};
use kni_core::jpeg_source::Limits;
use std::path::PathBuf;

fn jl() -> Limits { Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 28 } }
fn pl() -> DecodeLimits { DecodeLimits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 24 } }
fn tile(n: &str) -> Vec<u8> { std::fs::read(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/paul136").join(n)).unwrap() }
const RDP: f64 = 0.75;

/// The defect class named in the brief: tile, codepoint, source rings under
/// PreserveAllInk (glyph rings + the printed frame ring), shipped rings
/// under SeparatePresentRing (the frame ring gone, every stripe kept).
const CASES: [(&str, usize, usize); 4] = [
    ("083__0025__00ecaf81c98d.jpg", 8, 7), // percent: 7 stripes + frame -> 7 stripes
    ("123__2030__b7101429b917.jpg", 8, 7), // perthousand: 7 stripes + frame -> 7 stripes
    ("092__2018__19c8ddc6a768.jpg", 2, 1), // quoteleft: stripe + frame -> stripe
    ("093__2019__2115d64e0b8c.jpg", 2, 1), // quoteright: stripe + frame -> stripe
];

#[test]
fn separate_present_ring_removes_only_the_proven_frame_ring() {
    for (name, want_before, want_after) in CASES {
        let bytes = tile(name);
        let decoded = decode_source(&bytes, &pl(), jl()).unwrap();
        let src = capture_source_with_policy(&bytes, RDP, &pl(), jl(), FramePolicy::SeparatePresentRing).unwrap();
        // The jointly-proven band is the measured 2px ring on every edge -
        // never the 58px per-edge over-reach that swallowed a stripe.
        let (band, cells) = src.receipt.frame_band_measured;
        assert_eq!(band, (2, 2, 2, 2), "{name}: band must be the proven frame ring");
        assert!(cells > 0, "{name}: the frame ring holds ink");
        // The measurement domain is the original capture, byte-identical.
        assert_eq!(src.gray, decoded.gray, "{name}: measurement gray altered");
        // The outline domain lost exactly the frame ring.
        let outline = src.outline_contour.as_ref().expect("{name}: outline domain exists");
        assert_eq!(src.contour.rings.len(), want_before, "{name}: source ring count");
        assert_eq!(outline.rings.len(), want_after, "{name}: shipped ring count");
        // Pixel certificate, zero removed letterform ink: the cleared copy
        // differs from the source ONLY inside the proven band, every changed
        // cell is ink -> white, and their count is exactly the band's ink.
        let og = src.outline_gray.as_ref().unwrap();
        let (w, h) = (decoded.width, decoded.height);
        let (bt, bb, bl, br) = band;
        let mut diffs = 0usize;
        for y in 0..h {
            for x in 0..w {
                let i = y * w + x;
                if og[i] != decoded.gray[i] {
                    let in_band = y < bt || y >= h - bb || x < bl || x >= w - br;
                    assert!(in_band, "{name}: pixel ({x},{y}) outside the proven band was cleared");
                    assert!(decoded.gray[i] < 128 && og[i] == 255, "{name}: only band ink may be cleared to white");
                    diffs += 1;
                }
            }
        }
        assert_eq!(diffs, cells, "{name}: cleared cells must be exactly the proven band ink");
    }
}

/// The per-edge over-reach that motivated PresentRing is RETIRED (S10,
/// 2026-10-23): Measure clearing is gated by the same closed-ring proof, so
/// on the pinned percent tile it now clears exactly the proven ring and
/// keeps the edge-fused stripe - identical outline behavior to
/// SeparatePresentRing on framed tiles, while edge-flush letterform crops
/// with no ring (the Mercator H class) keep every pixel. The per-edge
/// measurement survives only as receipt evidence, never as a clearing rule.
#[test]
fn measure_policy_clears_only_the_proven_ring() {
    let bytes = tile("083__0025__00ecaf81c98d.jpg");
    let src = capture_source(&bytes, RDP, &pl(), jl()).unwrap();
    assert_eq!(src.receipt.frame_band_measured.0, (2, 2, 2, 2), "Measure clears only the proven ring");
    assert_eq!(src.receipt.frame_band_evidence, kni_core::capture_dispatch::FrameBandEvidence::RingProofCleared);
    assert_eq!(src.outline_contour.as_ref().unwrap().rings.len(), 7, "Measure outline keeps every stripe");
}

/// PreserveAllInk (the 92ee4a24 bypass) is the other pinned defect: stripes
/// survive but the printed frame is traced like glyph ink. Kept as the
/// regression contract for truly frame-free declared styles only.
#[test]
fn preserve_all_ink_keeps_stripes_and_the_frame() {
    let bytes = tile("083__0025__00ecaf81c98d.jpg");
    let kept = capture_source_with_policy(&bytes, RDP, &pl(), jl(), FramePolicy::PreserveAllInk).unwrap();
    assert_eq!(kept.receipt.frame_band_measured, ((0, 0, 0, 0), 0));
    assert_eq!(kept.contour.rings.len(), 8, "Preserve keeps all 7 stripes plus the frame ring");
}

/// Full pinned bundle: SeparatePresentRing clears ONLY proven frame-ring ink
/// on every tile - per tile the pixel certificate above must hold and the
/// ring loss must be exactly the frame ring count. Heavy (decodes + traces
/// the whole corpus); run explicitly:
/// cargo test --test paul_new_ink_preservation -- --ignored --nocapture
#[test]
#[ignore]
fn separate_present_ring_sweeps_the_whole_pinned_bundle() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/paul136");
    let mut names: Vec<_> = std::fs::read_dir(&dir).unwrap().filter_map(|e| {
        let n = e.unwrap().file_name().into_string().unwrap();
        if n.ends_with(".jpg") { Some(n) } else { None }
    }).collect();
    names.sort();
    assert_eq!(names.len(), 136, "pinned bundle size");
    let mut total_cleared = 0usize;
    for n in names {
        let bytes = tile(&n);
        let decoded = decode_source(&bytes, &pl(), jl()).unwrap();
        let src = capture_source_with_policy(&bytes, RDP, &pl(), jl(), FramePolicy::SeparatePresentRing).unwrap();
        assert_eq!(src.gray, decoded.gray, "{n}: measurement gray altered");
        let (band, cells) = src.receipt.frame_band_measured;
        let (w, h) = (decoded.width, decoded.height);
        let (bt, bb, bl, br) = band;
        if cells == 0 {
            assert!(src.outline_contour.is_none() && src.outline_gray.is_none(), "{n}: no ring proven, no clearing");
            continue;
        }
        let og = src.outline_gray.as_ref().unwrap();
        let mut diffs = 0usize;
        for y in 0..h {
            for x in 0..w {
                let i = y * w + x;
                if og[i] != decoded.gray[i] {
                    let in_band = y < bt || y >= h - bb || x < bl || x >= w - br;
                    assert!(in_band, "{n}: pixel ({x},{y}) outside the proven band was cleared");
                    assert!(decoded.gray[i] < 128 && og[i] == 255, "{n}: only band ink may be cleared");
                    diffs += 1;
                }
            }
        }
        assert_eq!(diffs, cells, "{n}: cleared cells must be exactly the proven band ink");
        // Ring counts are not a purity measure: where a letterform was fused
        // with the frame ring the tracer had them as one ring, so clearing
        // the frame can SPLIT it into more rings. The pixel certificate
        // above is the ink-preservation guarantee. The pinned production
        // tiles (numeric seq) all carry the same 2px closed ring; specimen
        // sheets (__sample__) are not part of the shipped collection.
        if !n.contains("__sample__") {
            assert_eq!(band, (2, 2, 2, 2), "{n}: production tiles carry the 2px frame ring");
        }
        total_cleared += cells;
    }
    assert!(total_cleared > 0, "the bundle carries the printed frame");
}
