use kni_core::corner_wiring::{wire_drawing, wire_ring, SeamAction, SeamKind};
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }

/// Two-cubic ring whose joint seam has a small tangent break (sub-floor at
/// chord length 4: floor = 2*atan(0.5/4) ~ 14.25 deg) and whose closure seam
/// is also sub-floor.
fn soft_ring() -> ReferenceRing {
    ReferenceRing {
        start: p(0., 0.),
        spans: vec![
            Span::Cubic { control_one: p(1., 0.), control_two: p(3., 0.), end: p(4., 0.05) },
            Span::Cubic { control_one: p(5., 0.05), control_two: p(7., 0.), end: p(8., 0.) },
        ],
    }
}

#[test]
fn sub_floor_seam_is_smoothed_to_g1() {
    let mut ring = soft_ring();
    let reps = wire_ring(&mut ring);
    assert_eq!(reps.len(), 2); // joint seam + closure seam
    // seam 0: tangent_out = unit(end - c2) = unit((1, 0.05)) ~ +2.9 deg,
    // tangent_in = unit(c1 - start) = unit((1, 0)) = 0 deg -> delta ~ 2.9
    // deg < floor ~ 14.25 deg
    let s0 = &reps[0];
    assert_eq!(s0.kind, SeamKind::CubicCubic);
    assert!(s0.delta_deg < s0.floor_deg, "delta {} floor {}", s0.delta_deg, s0.floor_deg);
    assert_eq!(s0.action, SeamAction::Smoothed);
    // after wiring the inner handles sit on the mean tangent: exact G1.
    if let (Span::Cubic { control_two, end, .. }, Span::Cubic { control_one, .. }) = (&ring.spans[0], &ring.spans[1]) {
        let t_out = (end.x - control_two.x, end.y - control_two.y);
        let t_in = (control_one.x - end.x, control_one.y - end.y);
        let cross = t_out.0 * t_in.1 - t_out.1 * t_in.0;
        assert!(cross.abs() < 1e-9, "cross {cross}");
    } else { panic!("spans changed type"); }
}

#[test]
fn super_floor_seam_keeps_its_corner_untouched() {
    let mut ring = soft_ring();
    if let Span::Cubic { control_two, .. } = &mut ring.spans[0] { *control_two = p(3., -1.5); }
    let before = format!("{ring:?}");
    let reps = wire_ring(&mut ring);
    let s0 = &reps[0];
    // tangent_out ~ atan2(1.55, 1) ~ 57 deg vs tangent_in 0 deg >> floor ~ 14.25
    assert!(s0.delta_deg > s0.floor_deg);
    assert_eq!(s0.action, SeamAction::Corner);
    assert_eq!(before, format!("{ring:?}"), "corner seam geometry must be untouched");
}

#[test]
fn handle_rotation_beyond_half_resolution_is_guard_rejected() {
    let mut ring = soft_ring();
    // long inner handle: same small delta, rotation moves the control ~1 unit
    if let Span::Cubic { control_two, .. } = &mut ring.spans[0] { *control_two = p(-16., -0.95); }
    let before = format!("{ring:?}");
    let reps = wire_ring(&mut ring);
    let s0 = &reps[0];
    assert!(s0.delta_deg < s0.floor_deg);
    assert_eq!(s0.action, SeamAction::GuardRejected);
    assert_eq!(before, format!("{ring:?}"), "rejected seam must keep original handles");
}

#[test]
fn line_line_seam_below_floor_is_abstained() {
    let mut ring = ReferenceRing {
        start: p(0., 0.),
        spans: vec![
            Span::Line { end: p(4., 0.05) },
            Span::Line { end: p(8., 0.) },
        ],
    };
    let reps = wire_ring(&mut ring);
    let s0 = &reps[0];
    assert_eq!(s0.kind, SeamKind::LineLine);
    assert!(s0.delta_deg < s0.floor_deg);
    assert_eq!(s0.action, SeamAction::Abstained);
}

#[test]
fn line_line_seam_above_floor_is_a_corner() {
    let mut ring = ReferenceRing {
        start: p(0., 0.),
        spans: vec![
            Span::Line { end: p(4., 4.) },
            Span::Line { end: p(8., 0.) },
        ],
    };
    let reps = wire_ring(&mut ring);
    assert_eq!(reps[0].action, SeamAction::Corner);
    assert!(reps[0].delta_deg > 80.0, "delta {}", reps[0].delta_deg);
}

#[test]
fn totals_and_tsv_shape() {
    let mut rings = vec![soft_ring()];
    let (reps, totals) = wire_drawing(&mut rings);
    assert_eq!(reps.len(), 2);
    assert_eq!(totals.seams, 2);
    assert_eq!(totals.smoothed + totals.corners + totals.abstained + totals.guard_rejected, totals.seams);
    let row = kni_core::corner_wiring::seam_report_tsv("g", &reps[0]);
    assert_eq!(row.trim_end().split('\t').count(), 9);
}
