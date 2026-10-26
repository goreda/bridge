//! outline_spacing determinism gate: profiling the same input twice in one
//! process must produce bit-identical floats (to_bits). Regression cover
//! for the comps HashMap -> BTreeMap fix: HashMap iteration order is
//! randomized per instance, and the component-area f64 accumulation order
//! then leaked into counter_area/open_left/open_right at ULP scale
//! (measured 2 ULP drift on counter_area over in-process repetitions of a
//! 24-counter synthetic, kni-src babc1bee).

use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};

fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
    vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
}
fn rect_rev(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
    vec![[x0, y0], [x0, y1], [x1, y1], [x1, y0]]
}

/// Mirrored-C aperture on the global left edge, a solid frame with 24 true
/// holes (opposite winding: 24 enclosed white components), and a C aperture
/// on the global right edge. Varied, non-round dimensions so the component
/// areas share no exact binary representation and summation order is
/// visible in the ULPs.
fn probe_input() -> OutlineInput {
    let mut rings = Vec::new();
    rings.push(vec![
        [100.0, 0.0], [0.0, 0.0], [0.0, 40.0], [55.0, 40.0], [55.0, 160.0], [0.0, 160.0], [0.0, 200.0], [100.0, 200.0],
    ]);
    rings.push(rect(150.0, 0.0, 650.0, 300.0));
    for i in 0..24 {
        let x = 170.0 + (i % 8) as f64 * 57.0;
        let y = 20.0 + (i / 8) as f64 * 90.0;
        let w = 13.0 + (i as f64) * 0.7 + (i % 3) as f64 * 0.13;
        let h = 17.0 + (i as f64) * 1.1 + (i % 5) as f64 * 0.07;
        rings.push(rect_rev(x, y, x + w, y + h));
    }
    rings.push(vec![
        [700.0, 0.0], [800.0, 0.0], [800.0, 40.0], [745.0, 40.0], [745.0, 160.0], [800.0, 160.0], [800.0, 200.0], [700.0, 200.0],
    ]);
    OutlineInput {
        glyph_id: "determinism-gate".into(),
        source_pin: "gate".into(),
        upm: 1000,
        origin: [0.0, 0.0],
        flatten_tolerance: 0.0,
        rings,
    }
}

#[test]
fn profile_is_bit_deterministic_across_repeated_runs() {
    let input = probe_input();
    let policy = ScanPolicy { row_step: 3.7, max_rows: 4096, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
    let reference = profile_outline(&input, policy).expect("reference profile");
    for run in 1..16 {
        let p = profile_outline(&input, policy).expect("repeat profile");
        assert_eq!(p.ink_area.to_bits(), reference.ink_area.to_bits(), "ink_area drifted at run {run}");
        assert_eq!(p.counter_area.to_bits(), reference.counter_area.to_bits(), "counter_area drifted at run {run}");
        assert_eq!(p.open_left.to_bits(), reference.open_left.to_bits(), "open_left drifted at run {run}");
        assert_eq!(p.open_right.to_bits(), reference.open_right.to_bits(), "open_right drifted at run {run}");
        assert_eq!(p.bounds.map(f64::to_bits), reference.bounds.map(f64::to_bits), "bounds drifted at run {run}");
        assert_eq!(p.rows.len(), reference.rows.len(), "row count drifted at run {run}");
        for (a, b) in p.rows.iter().zip(reference.rows.iter()) {
            assert_eq!(a.y.to_bits(), b.y.to_bits());
            assert_eq!(a.weight.to_bits(), b.weight.to_bits());
            assert_eq!(a.span_lo.to_bits(), b.span_lo.to_bits());
            assert_eq!(a.span_hi.to_bits(), b.span_hi.to_bits());
            assert_eq!(a.ink, b.ink);
        }
    }
    // Sanity that the probe exercises every accumulation class: enclosed
    // counters, left and right apertures all present.
    assert!(reference.counter_area > 0.0, "probe must produce enclosed white");
    assert!(reference.open_left > 0.0, "probe must produce left aperture");
    assert!(reference.open_right > 0.0, "probe must produce right aperture");
}
