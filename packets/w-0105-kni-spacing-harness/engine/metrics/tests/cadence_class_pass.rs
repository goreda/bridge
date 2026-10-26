//! tests/cadence_class_pass.rs
//! Lane B: cadence + optical area class pass (policy.cadence_class_pass).
//!
//! Properties under test (each is a property of the RETURNED solution):
//! 1. Pass OFF is the frozen behavior; pass ON with a uniform cadence that
//!    coincides with the anchor target derives NOTHING and every solution
//!    value is bit-identical (untouched pairs bit-identical BY CONSTRUCTION:
//!    derived == W_target stays on the frozen fallback).
//! 2. Pass ON with differentiated classes derives class-pair targets from
//!    the font's own measurements: the typed receipt lists exactly the
//!    retargeted class pairs; Straight|Straight (derived == anchor) is not
//!    among them and its pairs/ledger rows are bit-identical ON vs OFF;
//!    a Straight->Round pair is retargeted and tightens.
//! 3. A measured ctx class target always wins over the derivation.
//! 4. No interior stem intervals AND no non-flush class channel: the pass
//!    derives nothing, every value bit-identical.
//! 5. Determinism: same input, same bits.
//!
//! Fixture geometry is synthetic and declared per test; every expectation
//! derives from the fixture numbers, not from historical output.

use kni_metrics::cadence::measure_stem_intervals;
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    solve_spacing, FontContext, MeasuredPair, SpacingPolicy, SpacingSolution, UnobservedPolicy,
};

fn rows_uniform(n: usize, step: f64, weight: f64, ink: Vec<(f64, f64)>) -> Vec<ScanRow> {
    (0..n).map(|i| ScanRow {
        y: i as f64 * step,
        weight,
        ink: ink.iter().map(|&(left, right)| InkInterval { left, right }).collect(),
        span_lo: i as f64 * step - weight / 2.0,
        span_hi: i as f64 * step + weight / 2.0,
    }).collect()
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
        source_pin: "lane-b-test".into(),
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

/// Two-stem glyph ('n'/'h'/'m'/'u' family): flush straight sides, one
/// interior stem interval of `gap` per row.
fn two_stem(id: &str, stem: f64, gap: f64) -> OutlineProfile {
    profile(id, rows_uniform(10, 10.0, 10.0,
        vec![(0.0, stem), (stem + gap, 2.0 * stem + gap)]))
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
        let r = l + 2.0 * stem + counter; // mirrored: right wall recedes with c(i)
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

/// Single-stem solid bar (no interior white anywhere).
fn solid_bar(id: &str, stem: f64) -> OutlineProfile {
    profile(id, rows_uniform(10, 10.0, 10.0, vec![(0.0, stem)]))
}

fn policy(pass: bool) -> SpacingPolicy {
    SpacingPolicy { dcap: Some(50.0), cadence_class_pass: pass, ..Default::default() }
}

/// Value fingerprint: everything except the free-text receipt
/// (policy_derivation) and the receipt sets (unobserved_policy), which by
/// design record the pass when it is enabled. Debug formatting of f64 is
/// shortest-round-trip: equal strings imply identical bits (all NaNs here
/// are the f64::NAN constant, one bit pattern).
fn value_fingerprint(s: &SpacingSolution) -> String {
    let mut o = String::new();
    o.push_str(&format!("{:?}", (&s.baseline, &s.x_height, &s.cap_height, &s.glyphs)));
    o.push_str(&format!("{:?}", (&s.pairs, &s.space_status, &s.excluded_pairs)));
    o.push_str(&format!("{:?}", (s.complete, s.excluded_self_pairs, s.excluded_below_epsilon,
        s.excluded_unmeasurable, s.numeric_failed_pairs, s.geometric_hold_pairs,
        s.no_accepted_candidate_pairs)));
    o.push_str(&format!("{:?}", (&s.hold_reasons, &s.pair_ledger, &s.fallback_pairs)));
    o.push_str(&format!("{:?}", (s.fallback_natural_clear_pairs, s.fallback_verified_pairs,
        s.numeric_failed_nonfinite, s.numeric_failed_malformed,
        s.numeric_failed_natural_unverifiable, s.numeric_failed_natural_frame_conflict,
        s.accounting_residual, s.accounting_closed)));
    o
}

fn cadence_receipt(s: &SpacingSolution) -> Option<Vec<String>> {
    s.unobserved_policy.iter().find_map(|u| match u {
        UnobservedPolicy::ClassPairTargetCadenceDerived { class_pairs } => Some(class_pairs.clone()),
        _ => None,
    })
}

#[test]
fn uniform_cadence_coinciding_with_anchor_is_a_noop() {
    // All glyphs share one stem interval (46): the cadence unit, the
    // counter-channel anchor and every flush class contribution coincide,
    // so no class pair can be retargeted.
    let glyphs = vec![
        two_stem("n", 20.0, 46.0),
        two_stem("h", 20.0, 46.0),
        two_stem("m", 20.0, 46.0),
        two_stem("u", 20.0, 46.0),
    ];
    let m = measure_stem_intervals(&glyphs).unwrap().unwrap();
    assert_eq!(m.unit, 46.0);
    let off = solve_spacing(&glyphs, None, &policy(false)).unwrap();
    let on = solve_spacing(&glyphs, None, &policy(true)).unwrap();
    assert_eq!(cadence_receipt(&on), None, "nothing derived, nothing receipted");
    assert!(on.policy_derivation.contains("cadence class pass:"), "pass run is receipted");
    assert_eq!(value_fingerprint(&off), value_fingerprint(&on),
        "uniform cadence: every solution value bit-identical");
}

#[test]
fn differentiated_classes_derive_targets_and_adjust_only_targeted_pairs() {
    let glyphs = vec![
        two_stem("n", 20.0, 46.0),
        two_stem("h", 20.0, 46.0),
        round_bowl("o", 20.0, 60.0, 20.0, 20),
        round_bowl("e", 20.0, 60.0, 20.0, 20),
    ];
    // Cadence fixture math: 20 samples of 46 at weight 10 (total 200) vs
    // 40 bowl samples in [60,100] at weight 5 (total 200): the weighted
    // median lands exactly on the last 46.
    let m = measure_stem_intervals(&glyphs).unwrap().unwrap();
    assert_eq!(m.unit, 46.0);
    assert_eq!(m.samples, 60);
    assert_eq!(m.total_weight, 400.0);

    let off = solve_spacing(&glyphs, None, &policy(false)).unwrap();
    let on = solve_spacing(&glyphs, None, &policy(true)).unwrap();

    // Receipt: exactly the retargeted class pairs; Straight|Straight's
    // derived target equals the anchor (flush straight sides -> cadence
    // unit 46 == counter-channel anchor 46) so it is NOT retargeted.
    let receipt = cadence_receipt(&on).expect("pass derived class-pair targets");
    assert!(receipt.contains(&"Round->Round".to_string()), "receipt: {receipt:?}");
    assert!(receipt.contains(&"Straight->Round".to_string()), "receipt: {receipt:?}");
    assert!(receipt.contains(&"Round->Straight".to_string()), "receipt: {receipt:?}");
    assert!(!receipt.contains(&"Straight->Straight".to_string()), "receipt: {receipt:?}");
    assert!(cadence_receipt(&off).is_none());

    // Straight|Straight pairs and their ledger rows: bit-identical ON/OFF.
    let ss = |s: &SpacingSolution| -> String {
        let p: Vec<_> = s.pairs.iter()
            .filter(|p| ["n", "h"].contains(&p.left.as_str()) && ["n", "h"].contains(&p.right.as_str()))
            .collect();
        let l: Vec<_> = s.pair_ledger.iter()
            .filter(|r| ["n", "h"].contains(&r.left.as_str()) && ["n", "h"].contains(&r.right.as_str()))
            .collect();
        format!("{p:?}|{l:?}")
    };
    assert_eq!(ss(&off), ss(&on), "untouched class pairs bit-identical");

    // A Straight->Round pair is retargeted: emitted placement tightens.
    let find = |s: &SpacingSolution, l: &str, r: &str|
        s.pairs.iter().find(|p| p.left.as_str() == l && p.right.as_str() == r)
            .map(|p| (p.origin_distance, p.wall_gap));
    let on_no = find(&on, "n", "o").expect("n->o emitted with the pass on");
    match find(&off, "n", "o") {
        Some(off_no) => assert!(
            on_no.0 < off_no.0,
            "derived Straight->Round target is tighter: {} -> {}",
            off_no.0, on_no.0),
        None => {} // off run dropped it below the residual epsilon; on must still emit
    }

    // Glyph sidebearings are upstream of the class pass: never touched.
    assert_eq!(format!("{:?}", off.glyphs), format!("{:?}", on.glyphs));
}

#[test]
fn measured_class_target_always_wins() {
    let glyphs = vec![
        two_stem("n", 20.0, 46.0),
        two_stem("h", 20.0, 46.0),
        round_bowl("o", 20.0, 60.0, 20.0, 20),
        round_bowl("e", 20.0, 60.0, 20.0, 20),
    ];
    let ctx = FontContext {
        measured_pairs: vec![MeasuredPair { left: "n".into(), right: "h".into(), gap: 42.0 }],
        ..FontContext::default()
    };
    let off = solve_spacing(&glyphs, Some(&ctx), &policy(false)).unwrap();
    let on = solve_spacing(&glyphs, Some(&ctx), &policy(true)).unwrap();
    // Measured Straight|Straight target 42 wins; the derivation skips it.
    let receipt = cadence_receipt(&on).expect("other class pairs still derived");
    assert!(!receipt.contains(&"Straight->Straight".to_string()), "receipt: {receipt:?}");
    let ss = |s: &SpacingSolution| -> String {
        let p: Vec<_> = s.pairs.iter()
            .filter(|p| ["n", "h"].contains(&p.left.as_str()) && ["n", "h"].contains(&p.right.as_str()))
            .collect();
        let l: Vec<_> = s.pair_ledger.iter()
            .filter(|r| ["n", "h"].contains(&r.left.as_str()) && ["n", "h"].contains(&r.right.as_str()))
            .collect();
        format!("{p:?}|{l:?}")
    };
    assert_eq!(ss(&off), ss(&on), "measured class pair bit-identical with the pass on");
}

#[test]
fn no_cadence_and_all_flush_channels_derives_nothing() {
    // Single-stem bars: no interior stem interval, no counter, sides flush.
    let glyphs = vec![solid_bar("I", 20.0), solid_bar("l", 20.0), solid_bar("i", 20.0)];
    assert_eq!(measure_stem_intervals(&glyphs).unwrap(), None);
    let off = solve_spacing(&glyphs, None, &policy(false)).unwrap();
    let on = solve_spacing(&glyphs, None, &policy(true)).unwrap();
    assert_eq!(cadence_receipt(&on), None);
    assert_eq!(value_fingerprint(&off), value_fingerprint(&on),
        "nothing measurable: every solution value bit-identical");
}

#[test]
fn deterministic_repeat_with_pass_on() {
    let glyphs = vec![
        two_stem("n", 20.0, 46.0),
        two_stem("h", 20.0, 46.0),
        round_bowl("o", 20.0, 60.0, 20.0, 20),
        round_bowl("e", 20.0, 60.0, 20.0, 20),
    ];
    let a = solve_spacing(&glyphs, None, &policy(true)).unwrap();
    let b = solve_spacing(&glyphs, None, &policy(true)).unwrap();
    assert_eq!(format!("{a:?}"), format!("{b:?}"));
}

#[test]
fn pass_off_is_the_frozen_default() {
    // SpacingPolicy::default() must keep the pass off (frozen cascade).
    assert!(!SpacingPolicy::default().cadence_class_pass);
}
