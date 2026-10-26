//! tests/pair_target_fill.rs
//! Production solve fills PairPosition.pair_target (the pair's own J target)
//! and SpacingSolution.font_median_pair_target from font-derived values.
//! Expectations derive from the fixture numbers declared per test.

use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    font_median_pair_target, solve_spacing, FontContext, MeasuredPair, SpacingPolicy,
};

fn two_stem(id: &str, stem: f64, gap: f64) -> OutlineProfile {
    let ink = vec![(0.0, stem), (stem + gap, 2.0 * stem + gap)];
    let rows: Vec<ScanRow> = (0..10).map(|i| ScanRow {
        y: i as f64 * 10.0,
        weight: 10.0,
        ink: ink.iter().map(|&(left, right)| InkInterval { left, right }).collect(),
        span_lo: i as f64 * 10.0 - 5.0,
        span_hi: i as f64 * 10.0 + 5.0,
    }).collect();
    OutlineProfile {
        glyph_id: id.into(),
        source_pin: "pair-target-fill".into(),
        upm: 1000,
        origin: [0.0, 0.0],
        bounds: [0.0, 0.0, 2.0 * stem + gap, 90.0],
        rows,
        ink_area: 0.0,
        counter_area: 0.0,
        open_left: 0.0,
        open_right: 0.0,
        profile_method: "test-fixture".into(),
        row_step: 10.0,
        flatten_tolerance: 0.5,
    }
}

/// Round bowl: both side walls recede smoothly at top/bottom
/// (c(i) = amp*(1-cos(pi*(i-mid)/mid)) over `n` rows), one interior
/// counter per row. With amp=20, n=20, stem=20: per-row wall delta
/// <= 6.61 <= s/2 = 10 (Round class), wall range 40 > s/2 (not Straight),
/// max jump <= s (not Arm), direction changes (not Diagonal).
fn round_bowl(id: &str, stem: f64, counter: f64, amp: f64, n: usize) -> OutlineProfile {
    let step = 5.0;
    let mid = (n - 1) as f64 / 2.0;
    let c = |i: usize| amp * (1.0 - (std::f64::consts::PI * (i as f64 - mid) / mid).cos());
    let rows = (0..n).map(|i| {
        let l = c(i);
        let r = l + 2.0 * stem + counter;
        ScanRow {
            y: i as f64 * step,
            weight: step,
            ink: vec![
                InkInterval { left: l, right: l + stem },
                InkInterval { left: l + stem + counter, right: r },
            ],
            span_lo: i as f64 * step - step / 2.0,
            span_hi: i as f64 * step + step / 2.0,
        }
    }).collect();
    profile(id, rows)
}

fn glyphs() -> Vec<OutlineProfile> {
    vec![two_stem("n", 20.0, 46.0), two_stem("h", 20.0, 46.0),
         round_bowl("o", 20.0, 60.0, 20.0, 20), round_bowl("e", 20.0, 60.0, 20.0, 20)]
}

fn policy() -> SpacingPolicy {
    SpacingPolicy { dcap: Some(50.0), ..Default::default() }
}

#[test]
fn measured_class_target_is_carried_per_pair_and_median() {
    // Measured Straight|Straight gap 42 (< dcap 50). Other class pairs fall
    // back to the anchor / class targets of this same solve; every solved
    // pair carries a usable target, straight|straight pairs carry 42.
    let target = 42.0f64;
    let ctx = FontContext {
        measured_pairs: vec![MeasuredPair { left: "n".into(), right: "h".into(), gap: target }],
        ..FontContext::default()
    };
    let s = solve_spacing(&glyphs(), Some(&ctx), &policy()).unwrap();
    assert!(!s.pairs.is_empty(), "fixture must yield solved pairs");
    for p in &s.pairs {
        let t = p.pair_target.expect("filled");
        assert!(t.is_finite() && t >= 0.0);
        if p.left.as_str() < "o" && p.right.as_str() < "o" { assert_eq!(t, target); }
    }
    assert_eq!(s.font_median_pair_target, font_median_pair_target(&s.pairs));
    assert!(s.font_median_pair_target.is_some());
}

#[test]
fn geometry_only_target_is_font_derived_and_filled() {
    let s = solve_spacing(&glyphs(), None, &policy()).unwrap();
    assert!(!s.pairs.is_empty(), "fixture must yield solved pairs");
    for p in &s.pairs {
        let t = p.pair_target.expect("filled");
        assert!(t.is_finite() && t >= 0.0);
    }
    let m = s.font_median_pair_target.expect("median filled");
    let (lo, hi) = s.pairs.iter().filter_map(|p| p.pair_target)
        .fold((f64::INFINITY, f64::NEG_INFINITY), |(l, h), t| (l.min(t), h.max(t)));
    assert!(lo <= m && m <= hi);
    assert_eq!(Some(m), font_median_pair_target(&s.pairs));
}

#[test]
fn deterministic() {
    let a = solve_spacing(&glyphs(), None, &policy()).unwrap();
    let b = solve_spacing(&glyphs(), None, &policy()).unwrap();
    assert_eq!(format!("{:?}", a.pairs), format!("{:?}", b.pairs));
    assert_eq!(a.font_median_pair_target.map(f64::to_bits), b.font_median_pair_target.map(f64::to_bits));
}

fn profile(id: &str, rows: Vec<ScanRow>) -> OutlineProfile {
    let (mut x0, mut y0) = (f64::INFINITY, f64::INFINITY);
    let (mut x1, mut y1) = (f64::NEG_INFINITY, f64::NEG_INFINITY);
    for r in &rows {
        y0 = y0.min(r.y); y1 = y1.max(r.y);
        for iv in &r.ink { x0 = x0.min(iv.left); x1 = x1.max(iv.right); }
    }
    OutlineProfile {
        glyph_id: id.into(),
        source_pin: "pair-target-fill".into(),
        upm: 1000,
        origin: [0.0, 0.0],
        rows,
        bounds: [x0, y0, x1, y1],
        ink_area: 0.0,
        counter_area: 0.0,
        open_left: 0.0,
        open_right: 0.0,
        profile_method: "test-fixture".into(),
        row_step: 10.0,
        flatten_tolerance: 0.5,
    }
}
