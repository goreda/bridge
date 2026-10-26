//! r109: typed `x_height_source` on SpacingSolution - the three metrics-side
//! producer paths. Fixture shape mirrors tests/space_status_dar.rs (wired
//! measured sidebearings/pairs so the anchor cascade resolves); expectations
//! are derived from the constructed geometry, no recorded constants.
//!   (1) ctx.x_height = Some -> XHeightSource::Ctx, value passes through.
//!   (2) no ctx value + lowercase tops present -> XHeightSource::LcTopMedian,
//!       value = median of (y_max - baseline) over flat-top lowercase glyphs.
//!   (3) no ctx value + NO lowercase tops -> XHeightSource::AllGlyphProxy,
//!       value = median over ALL inked glyphs, and
//!       UnobservedPolicy::XHeightAllGlyphProxy is recorded.
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    solve_spacing, FontContext, MeasuredPair, MeasuredSidebearing, SpacingPolicy,
    UnobservedPolicy, XHeightSource,
};

const EPS: f64 = 1e-9;

fn profile(id: &str, rows: usize) -> OutlineProfile {
    let ink = [(0.0, 10.0), (30.0, 40.0)];
    let mk = |y: f64| ScanRow { y, weight: 1.0, span_lo: y, span_hi: y + 1.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect() };
    OutlineProfile {
        glyph_id: id.to_string(), source_pin: format!("pin-{id}"), upm: 1000,
        origin: [0.0, 0.0], rows: (0..rows).map(|i| mk(i as f64)).collect(),
        bounds: [0.0, 0.0, 40.0, rows as f64],
        ink_area: rows as f64 * 20.0,
        counter_area: 0.0, open_left: 0.0, open_right: 0.0,
        profile_method: "x-height-source-test".into(),
        row_step: 1.0, flatten_tolerance: 0.0,
    }
}

/// Wired anchor context (dar-fixture shape): measured sidebearings/pairs so
/// the solve resolves; x_height presence is the test variable. codepoints map
/// the glyph ids to real letters so case resolution is exercised.
fn ctx(l: &str, r: &str, lc: bool, x_height: Option<f64>) -> FontContext {
    let (lcp, rcp) = if lc { (0x61, 0x62) } else { (0x41, 0x42) };
    FontContext {
        x_height, cap_height: None, baseline: None,
        measured_sidebearings: vec![
            MeasuredSidebearing { glyph_id: l.into(), lsb: 12.0, rsb: 13.0 },
            MeasuredSidebearing { glyph_id: r.into(), lsb: 12.0, rsb: 13.0 }],
        measured_pairs: vec![
            MeasuredPair { left: l.into(), right: r.into(), gap: 20.0 },
            MeasuredPair { left: r.into(), right: l.into(), gap: 20.0 }],
        measured_space_advance: None,
        glyph_codepoints: vec![(l.into(), lcp), (r.into(), rcp)],
    }
}

#[test]
fn ctx_value_carries_ctx_source() {
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    let (a, b) = (profile("A", 4), profile("B", 4));
    let sol = solve_spacing(&[a, b], Some(&ctx("A", "B", false, Some(450.0))), &policy)
        .expect("solve with ctx x_height");
    assert_eq!(sol.x_height_source, XHeightSource::Ctx);
    assert_eq!(sol.x_height_source.token(), "ctx");
    assert!((sol.x_height - 450.0).abs() < EPS, "ctx x_height must pass through, got {}", sol.x_height);
}

#[test]
fn lowercase_top_median_carries_lc_top_source() {
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    // lowercase a (4 rows) + b (6 rows): lc tops over baseline 0 = [4.0, 6.0] -> median 5.0
    let (a, b) = (profile("a", 4), profile("b", 6));
    let sol = solve_spacing(&[a, b], Some(&ctx("a", "b", true, None)), &policy)
        .expect("solve with lowercase tops");
    assert_eq!(sol.x_height_source, XHeightSource::LcTopMedian);
    assert_eq!(sol.x_height_source.token(), "lc_top_median");
    assert!((sol.x_height - 5.0).abs() < EPS, "lc-top median must be 5.0, got {}", sol.x_height);
    assert!(!sol.unobserved_policy.iter().any(|u| matches!(u, UnobservedPolicy::XHeightAllGlyphProxy)),
        "lc-top path must NOT record the all-glyph proxy convention");
}

#[test]
fn no_lowercase_tops_carries_all_glyph_proxy_source() {
    let policy = SpacingPolicy { dcap: Some(50.0), ..Default::default() };
    // uppercase only: no lowercase tops -> all-glyph proxy over [4.0, 6.0] -> median 5.0
    let (a, b) = (profile("A", 4), profile("B", 6));
    let sol = solve_spacing(&[a, b], Some(&ctx("A", "B", false, None)), &policy)
        .expect("solve without lowercase tops");
    assert_eq!(sol.x_height_source, XHeightSource::AllGlyphProxy);
    assert_eq!(sol.x_height_source.token(), "all_glyph_proxy");
    assert!((sol.x_height - 5.0).abs() < EPS, "all-glyph median must be 5.0, got {}", sol.x_height);
    assert!(sol.unobserved_policy.iter().any(|u| matches!(u, UnobservedPolicy::XHeightAllGlyphProxy)),
        "all-glyph proxy path must record the typed convention");
}
