//! Reproducer: ungated cubic_fit::fit_run emits pathological overshoot
//! controls on real captured contour data while satisfying its squared-error
//! bound at the samples.
//!
//! Data: arc extracted from the owner R scan (tests/fixtures/r_scan.png)
//! through capture::capture_png (ring 0, arc 1, scaled to 700 units cap
//! height, scale 700/405). Not invented: the exact samples below are the
//! probe output of the capture pipeline on that scan.
//!
//! Actual behavior (engine as landed): FitOutcome::Fitted with
//! max_squared_error = 0.403 (well under policy bound 1.0) but control point
//! c1.x = 100.5, about 50 units outside the arc sample bbox
//! x in [150.0, 383.4]. Assembled into a glyph, such spans inflate the font
//! bounding box roughly 3.9x and collapse raster IoU against the source scan
//! from ~0.98 to ~0.33.
//!
//! Desired behavior: fit_run (or its caller contract) rejects/clamps
//! solutions whose controls leave the sample bbox by more than a small
//! margin. capture_fit::plausible implements such a gate caller-side; this
//! test documents why the gate exists.

use kni_core::capture_fit::plausible;
use kni_core::cubic_fit::{adjacent_chord_tangents, fit_run, FitOutcome, FitPolicy};
use kni_core::reference_slice::Point;

#[test]
fn fit_run_emits_overshoot_controls_on_real_arc() {
    let samples: &[Point] = &[
        Point { x: 383.3903, y: 92.2851 },
        Point { x: 150.0182, y: 341.4266 },
        Point { x: 150.9631, y: 342.6550 },
        Point { x: 190.7565, y: 342.7242 },
        Point { x: 208.0580, y: 344.0464 },
    ];
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (lt, rt) = adjacent_chord_tangents(samples).expect("tangents");
    match fit_run(samples, lt, rt, &policy) {
        FitOutcome::Fitted { controls, max_squared_error, .. } => {
            assert!(max_squared_error <= 1.0, "error bound met at samples");
            assert!(
                !plausible(samples, &controls),
                "reproducer expects controls outside the plausible bound; \
                 if this fails the engine may have gained a clamp and this \
                 test should be re-characterized"
            );
        }
        other => panic!("expected Fitted, got {:?}", other),
    }
}
