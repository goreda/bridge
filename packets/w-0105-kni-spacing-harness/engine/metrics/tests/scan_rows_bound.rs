//! Shape-profile check of the manifest generator's scan_max_rows bound against
//! the real profile_outline (anchored grid, grid_anchor_y = Some(0.0)).
use kni_metrics::outline_spacing::*;

fn bound(h: f64, step: f64) -> usize { (h / step).ceil() as usize + 1 } // == spacing_manifest_gen.scan_rows_upper_bound

fn prof(miny: f64, h: f64, step: f64, max_rows: usize) -> Result<OutlineProfile, ProfileError> {
    let r = vec![[0.0, miny], [30.0, miny], [30.0, miny + h], [0.0, miny + h]];
    let input = OutlineInput { glyph_id: "g".into(), source_pin: "t".into(), upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0, rings: vec![r] };
    profile_outline(&input, ScanPolicy { row_step: step, max_rows, merge_guard: 1.0, grid_anchor_y: Some(0.0) })
}

#[test]
fn bound_accepts_every_boundary_phase() {
    let step = 10.0;
    for &h in &[1.0, 9.9, 10.0, 10.1, 99.5, 100.0, 105.0] {
        for k in 0..400 {
            let miny = k as f64 * 0.37 - 20.0;
            assert!(prof(miny, h, step, bound(h, step)).is_ok(), "h={h} miny={miny}");
        }
    }
}
#[test]
fn old_bound_ceil_h_over_step_is_refused_for_some_phase() {
    let (step, h) = (10.0_f64, 10.1_f64);
    let old = (h / step).ceil() as usize;
    assert!((0..400).any(|k| prof(k as f64 * 0.37 - 20.0, h, step, old).is_err()), "old bound never refused: not a counterexample");
}
