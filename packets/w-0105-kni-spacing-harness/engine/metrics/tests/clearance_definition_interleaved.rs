//! Documents, with a minimal fixture, how the solver's facing-cell clearance and the kern guard's pair clearance treat an ink piece of
//! the RIGHT glyph that lies wholly behind every LEFT ink piece in a row (interleaved shapes: a stroke tucked into an aperture).
//! Neither is a row-extent gap (rightmost-left-ink to leftmost-right-ink); a row-extent reading is negative here although no ink overlaps.

use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::signed_clearance::{clearance_cells_constant_rows, evidence_at, pair_clearance};

fn prof(id: &str, ink: Vec<(f64, f64)>) -> OutlineProfile {
    let rows: Vec<ScanRow> = (0..5).map(|i| ScanRow { y: i as f64 * 10.0, weight: 10.0,
        ink: ink.iter().map(|&(l, r)| InkInterval { left: l, right: r }).collect(), span_lo: i as f64 * 10.0 - 5.0, span_hi: i as f64 * 10.0 + 5.0 }).collect();
    let x0 = ink.iter().map(|i| i.0).fold(f64::INFINITY, f64::min);
    let x1 = ink.iter().map(|i| i.1).fold(f64::NEG_INFINITY, f64::max);
    OutlineProfile { glyph_id: id.into(), source_pin: "t".into(), upm: 1000, origin: [0.0, 0.0], rows, bounds: [x0, 0.0, x1, 40.0],
        ink_area: 1.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0, profile_method: "t".into(), row_step: 10.0, flatten_tolerance: 0.5 }
}

#[test]
fn piece_wholly_behind_the_left_ink_is_skipped_by_the_solver_cells_but_negative_in_the_guard_clearance() {
    // left ink [0,20]; right ink pieces [-10,-5] (wholly behind the left ink) and [30,50] (ahead, gap 10)
    let l = prof("L", vec![(0.0, 20.0)]);
    let r = prof("R", vec![(-10.0, -5.0), (30.0, 50.0)]);
    let rows = kni_metrics::outline_spacing::align_pair_rows(&l, &r);
    let cells = clearance_cells_constant_rows(&rows, 0.0);
    assert!(!cells.is_empty() && cells.iter().all(|c| c.1 == 10.0), "solver cells: the behind piece has no wall behind it, gap is the facing 10: {cells:?}");
    let g = pair_clearance(&l, &r, 0.0, 0.0, 0.0).unwrap();
    assert_eq!(g.min_gap, -30.0, "guard clearance: the wholly-reversed piece reports rl - max_right = -10 - 20");
    let e = evidence_at(&l, &r, 0.0, 0.0, 0.0).unwrap();
    assert!(!e.interval_hit, "no ink interval overlaps");
    // a row-extent reading (leftmost right ink minus rightmost left ink) is also -30 here, with no ink overlap: it is not the clearance
    assert_eq!(-10.0 - 20.0, -30.0);
}
