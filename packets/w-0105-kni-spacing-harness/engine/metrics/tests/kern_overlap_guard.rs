//! K3 overlap-guard regression tests for the P2 root-cause classes
//! (2026-10-15 owner order): solver/measurement disagreement holds
//! (Eacute->u class: solver wall_gap 0 vs measured 5) and
//! reversed-order ink at a shared segment (the silent-skip hole: right
//! interval left of every left wall used to contribute NO gap, letting
//! min_gap stay +INF and the pair ship Ready unmeasured).
//! Geometry is synthetic and exact; expectations are derived from the
//! constructed coordinates, no recorded constants.

use kni_metrics::generated_outline_kern::{
    generate_residual_kern, measure_full_outline_gap, ExportGeometry, ProfileFrame,
};
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{GlyphSpacing, PairPosition, SpacingSolution};

fn profile(id: &str, rows: &[(f64, f64, Vec<(f64, f64)>)], bounds: [f64; 4]) -> OutlineProfile {
    let mut area = 0.0;
    let rs: Vec<ScanRow> = rows
        .iter()
        .map(|(y, w, ink)| {
            let iv: Vec<InkInterval> = ink
                .iter()
                .map(|(l, r)| InkInterval { left: *l, right: *r })
                .collect();
            for i in &iv {
                area += w * (i.right - i.left);
            }
            ScanRow { y: *y, weight: *w, ink: iv, span_lo: *y - *w * 0.5, span_hi: *y + *w * 0.5 }
        })
        .collect();
    // The signed_clearance primitive works on piecewise-linear wall segments,
    // which need a vertical span: a single exact row has zero height and
    // yields no segments. Expand a lone row into two stacked identical rows;
    // ink is identical, so every measured value is unchanged.
    let rs = if rs.len() == 1 {
        let mut up = rs[0].clone();
        up.y += rs[0].weight;
        vec![rs[0].clone(), up]
    } else {
        rs
    };
    OutlineProfile {
        glyph_id: id.to_string(),
        source_pin: format!("pin-{id}"),
        upm: 1000,
        origin: [0.0, 0.0],
        rows: rs,
        bounds,
        ink_area: area,
        counter_area: 0.0,
        open_left: 0.0,
        open_right: 0.0,
        profile_method: "synthetic-test".to_string(),
        row_step: 1.0,
        flatten_tolerance: 0.0,
    }
}

fn solution(l: &str, r: &str, origin_distance: f64, wall_gap: f64) -> SpacingSolution {
    SpacingSolution {
        glyphs: vec![
            GlyphSpacing { glyph_id: l.to_string(), lsb: 0.0, rsb: 0.0, advance: 100.0 },
            GlyphSpacing { glyph_id: r.to_string(), lsb: 0.0, rsb: 0.0, advance: 100.0 },
        ],
        font_median_pair_target: None,
        pairs: vec![PairPosition {
            left: l.to_string(),
            right: r.to_string(),
            origin_distance,
            wall_gap,
            optical_cost: 0.0,
            pair_target: None,
            compensated: false,
        }],
        space_status: kni_metrics::self_anchored_spacing::SpaceStatus::Absent,
        excluded_pairs: Vec::new(),
        complete: true,
        excluded_self_pairs: 0,
        excluded_below_epsilon: 0,
        excluded_unmeasurable: 0,
        numeric_failed_pairs: 0, geometric_hold_pairs: 0, no_accepted_candidate_pairs: 0, hold_reasons: Vec::new(),
        policy_derivation: "test".to_string(),
        unobserved_policy: Vec::new(),
        anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run(),
        contrast_floor_adjustments: Vec::new(),
        contrast_floor_failures: Vec::new(),
        x_height: 0.0,
        x_height_source: kni_metrics::self_anchored_spacing::XHeightSource::Ctx,
        cap_height: 0.0,
        baseline: 0.0,
        pair_ledger: Vec::new(),
        fallback_pairs: Vec::new(),
        fallback_natural_clear_pairs: 0,
        fallback_verified_pairs: 0,
        numeric_failed_nonfinite: 0,
        numeric_failed_malformed: 0,
        numeric_failed_natural_unverifiable: 0,
        numeric_failed_natural_frame_conflict: 0,
        accounting_residual: 0,
        accounting_closed: true,
    }
}

fn geo() -> ExportGeometry {
    ExportGeometry {
        profile_frame: ProfileFrame::RawGenerated,
        upm: 1000,
        overlap_tolerance_units: 0.5,
        drop_zero_residual: false,
        row_align_tolerance_units: 1.0,
    }
}

/// Reversed-order segment: right glyph's ink ([10,30] after placement) sits
/// left of EVERY left wall (left ink [50,100]). No true intersection, but
/// the truthful gap is negative: 10 - 100 = -90.
#[test]
fn reversed_order_segment_measures_negative_gap() {
    let left = profile("L", &[(0.0, 1.0, vec![(50.0, 100.0)])], [50.0, 0.0, 100.0, 1.0]);
    let right = profile("R", &[(0.0, 1.0, vec![(0.0, 20.0)])], [0.0, 0.0, 20.0, 1.0]);
    let m = measure_full_outline_gap(&left, &right, 0.0, 0.0, 10.0, 1.0)
        .expect("shared rows exist");
    assert!(!m.intersects, "no true interval intersection here");
    assert!((m.min_gap - -90.0).abs() < 1e-9, "min_gap {}", m.min_gap);
}

/// The same reversed-order pair must be OverlapHold, never Ready (the old
/// code skipped the interval and could report +INF as the measured gap).
#[test]
fn reversed_order_pair_is_held_not_ready() {
    let left = profile("L", &[(0.0, 1.0, vec![(50.0, 100.0)])], [50.0, 0.0, 100.0, 1.0]);
    let right = profile("R", &[(0.0, 1.0, vec![(0.0, 20.0)])], [0.0, 0.0, 20.0, 1.0]);
    let sol = solution("L", "R", 10.0, -90.0);
    let out = generate_residual_kern(&sol, &[left, right], &geo());
    assert_eq!(out.ready.len(), 0, "reversed pair must not ship ready");
    assert_eq!(out.overlap_holds.len(), 1);
    assert!(out.overlap_holds[0].measured_gap_at_origin.unwrap() < 0.0);
}

/// Eacute->u P2 class: solver wall_gap 0 but full-outline measurement at
/// the exact origin distance is +5 - the guard must hold, not guess.
#[test]
fn solver_measurement_disagreement_is_held() {
    let e = profile("Eacute", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let u = profile("u", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let sol = solution("Eacute", "u", 105.0, 0.0);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.ready.len(), 0);
    assert_eq!(out.overlap_holds.len(), 1);
    let h = &out.overlap_holds[0];
    assert!((h.measured_gap_at_origin.unwrap() - 5.0).abs() < 1e-9);
    assert!(h.note.contains("disagree"), "note: {}", h.note);
}

/// Clean control: solver and measurement agree, no overlap at export.
#[test]
fn agreeing_pair_ships_ready() {
    let e = profile("Eacute", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let u = profile("u", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let sol = solution("Eacute", "u", 105.0, 5.0);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.overlap_holds.len(), 0);
    assert_eq!(out.ready.len(), 1);
    assert_eq!(out.ready[0].export_value, 5);
}

/// True ink intersection at the shipped distance stays an OverlapHold.
#[test]
fn true_intersection_at_export_is_held() {
    let e = profile("Eacute", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let u = profile("u", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    // origin 90: inks overlap by 10 already; solver agrees (wall_gap -10).
    let sol = solution("Eacute", "u", 90.0, -10.0);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.ready.len(), 0);
    assert_eq!(out.overlap_holds.len(), 1);
    assert!(out.overlap_holds[0].ink_intersects);
}

// ---------------------------------------------------------------------------
// K3 integer-safe placement + exact origin diagnostic (chief 2026-10-15)
// ---------------------------------------------------------------------------

use kni_metrics::signed_clearance;

/// Eacute/u fixture: Eacute carries a stem band and a high accent band; u
/// carries two stems at x-height. Rows are exact unit rows.
pub fn eacute_u_fixture() -> (OutlineProfile, OutlineProfile) {
    let e = profile(
        "Eacute",
        &[
            (0.0, 1.0, vec![(0.0, 100.0)]),
            (1.0, 1.0, vec![(0.0, 100.0)]),
            (800.0, 1.0, vec![(40.0, 70.0)]), // accent
        ],
        [0.0, 0.0, 100.0, 801.0],
    );
    let u = profile(
        "u",
        &[
            (0.0, 1.0, vec![(0.0, 20.0), (80.0, 100.0)]),
            (1.0, 1.0, vec![(0.0, 20.0), (80.0, 100.0)]),
        ],
        [0.0, 0.0, 100.0, 2.0],
    );
    (e, u)
}

/// Integer-safe placement: left ink sticks 0.1 past its advance
/// (ink [0,100.1], advance 100), exact origin 100.4 leaves a clean 0.3 gap,
/// but the rounded distance 100 penetrates by 0.1. The guard must ship the
/// deterministic nearest collision-free integer: 101 (export_value 1).
#[test]
fn integer_safe_placement_adjusts_rounded_distance() {
    let l = profile("L", &[(0.0, 1.0, vec![(0.0, 100.1)])], [0.0, 0.0, 100.1, 1.0]);
    let r = profile("R", &[(0.0, 1.0, vec![(0.0, 10.0)])], [0.0, 0.0, 10.0, 1.0]);
    let sol = solution("L", "R", 100.4, 0.3);
    let out = generate_residual_kern(&sol, &[l, r], &geo());
    assert_eq!(out.overlap_holds.len(), 0, "holds: {:?}", out.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(out.ready.len(), 1);
    let row = &out.ready[0];
    assert_eq!(row.export_distance, 101);
    assert_eq!(row.export_value, 1);
    // Adjustment is observable without a receipt field: the shipped integer
    // distance moved one lattice step up from the rounded exact placement.
    assert_eq!(row.export_distance, 100 + 1);
    // Shipped distance verified collision-free by the shared primitive.
    let ev = signed_clearance::evidence_at(
        &profile("L", &[(0.0, 1.0, vec![(0.0, 100.1)])], [0.0, 0.0, 100.1, 1.0]),
        &profile("R", &[(0.0, 1.0, vec![(0.0, 10.0)])], [0.0, 0.0, 10.0, 1.0]),
        0.0, 0.0, row.export_distance as f64).unwrap();
    assert!(!ev.collides());
    assert!((ev.clearance.min_gap - 0.9).abs() < 1e-9);
}

/// Exact origin collision: the exact placement already penetrates
/// (origin 99.9 vs ink right edge 100.1), so integer-safe placement is not
/// applicable and the hold carries the exact-origin diagnostic.
#[test]
fn exact_origin_collision_is_held_with_diagnostic() {
    let l = profile("L", &[(0.0, 1.0, vec![(0.0, 100.1)])], [0.0, 0.0, 100.1, 1.0]);
    let r = profile("R", &[(0.0, 1.0, vec![(0.0, 10.0)])], [0.0, 0.0, 10.0, 1.0]);
    let sol = solution("L", "R", 99.9, -0.2);
    let out = generate_residual_kern(&sol, &[l, r], &geo());
    assert_eq!(out.ready.len(), 0);
    assert_eq!(out.overlap_holds.len(), 1);
    let h = &out.overlap_holds[0];
    assert!(h.note.contains("origin"), "note: {}", h.note);
    // Exact-origin diagnostic re-verified through the shared primitive:
    // the exact placement penetrates by 0.2.
    let l2 = profile("L", &[(0.0, 1.0, vec![(0.0, 100.1)])], [0.0, 0.0, 100.1, 1.0]);
    let r2 = profile("R", &[(0.0, 1.0, vec![(0.0, 10.0)])], [0.0, 0.0, 10.0, 1.0]);
    let ev0 = signed_clearance::evidence_at(&l2, &r2, 0.0, 0.0, 99.9).unwrap();
    assert!(ev0.collides());
    assert!((ev0.clearance.penetration_depth - 0.2).abs() < 1e-9);
}

/// Eacute/u fixture pair through the guard: solver wall_gap 0 vs measured 5
/// stays a disagreement hold (the P2 Eacute->u class), with the diagnostic.
#[test]
fn eacute_u_fixture_disagreement_hold() {
    let (e, u) = eacute_u_fixture();
    let sol = solution("Eacute", "u", 105.0, 0.0);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.ready.len(), 0);
    assert_eq!(out.overlap_holds.len(), 1);
    let h = &out.overlap_holds[0];
    assert!((h.measured_gap_at_origin.unwrap() - 5.0).abs() < 1e-9);
    assert!(h.note.contains("disagree"));
    let (e2, u2) = eacute_u_fixture();
    let ev0 = signed_clearance::evidence_at(&e2, &u2, 0.0, 0.0, 105.0).unwrap();
    assert!(!ev0.interval_hit);
}

/// K3 integer verification consumer test: every Ready row the guard emits
/// must verify collision-free at its shipped integer distance through the
/// shared primitive, and every adjusted row must carry the adjustment note.
#[test]
fn consumer_verifies_all_ready_rows_integer_safe() {
    let (e, u) = eacute_u_fixture();
    let l = profile("L", &[(0.0, 1.0, vec![(0.0, 100.1)])], [0.0, 0.0, 100.1, 1.0]);
    let r = profile("R", &[(0.0, 1.0, vec![(0.0, 10.0)])], [0.0, 0.0, 10.0, 1.0]);
    let mut sol = solution("Eacute", "u", 105.0, 5.0);
    sol.pairs.push(PairPosition { left: "L".into(), right: "R".into(),
        origin_distance: 100.4, wall_gap: 0.3, optical_cost: 0.0, pair_target: None, compensated: false });
    sol.glyphs.push(GlyphSpacing { glyph_id: "L".into(), lsb: 0.0, rsb: 0.0, advance: 100.0 });
    sol.glyphs.push(GlyphSpacing { glyph_id: "R".into(), lsb: 0.0, rsb: 0.0, advance: 100.0 });
    let profs = [e, u, l, r];
    let by_id = |id: &str| profs.iter().find(|p| p.glyph_id == id).unwrap();
    let out = generate_residual_kern(&sol, &profs, &geo());
    assert_eq!(out.ready.len(), 2, "holds: {:?}", out.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    for row in &out.ready {
        let ev = signed_clearance::evidence_at(
            by_id(&row.left), by_id(&row.right), 0.0, 0.0, row.export_distance as f64)
            .expect("coverage");
        assert!(!ev.collides(), "ready row {}->{} collides at {}", row.left, row.right, row.export_distance);
        assert_eq!(row.export_distance as i64,
            row.export_value as i64 + 100, "export_distance = round(advance) + export_value");
    }
    // Adjusted rows are derived, not field-read: shipped distance above the
    // rounded exact placement means integer-safe placement moved the pair.
    let adjusted: Vec<_> = out.ready.iter()
        .filter(|r| (r.export_distance as f64) > 100.0 + (r.residual_units).round())
        .collect();
    assert_eq!(adjusted.len(), 1);
}

// ---------------------------------------------------------------------------
// Origin-arm contact rule (chief 2026-10-17): depth-0 contact at the exact
// solver placement is NOT a collision; real penetration IS. Post-solve frame
// repairs (containment compensation) shift the re-measured placement by ulps;
// a sub-agree_tol penetration is frame noise, never a hold.
// ---------------------------------------------------------------------------

/// Exact contact (min_gap 0, depth 0): the pair ships, no hold.
#[test]
fn exact_contact_at_origin_is_not_a_collision() {
    let e = profile("Eacute", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let u = profile("u", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let sol = solution("Eacute", "u", 100.0, 0.0);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.overlap_holds.len(), 0, "holds: {:?}", out.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(out.ready.len(), 1, "contact pair must ship ready");
    assert_eq!(out.ready[0].export_value, 0);
    assert_eq!(out.ready[0].measured_gap_at_origin.unwrap(), 0.0);
}

/// A few-ulps penetration at the origin - the shape a post-solve frame
/// repair (containment compensation) leaves on a legally placed contact
/// pair - is frame noise indistinguishable from contact: the pair ships.
/// The shift is derived from the pair's own magnitude (ulps of 100), never
/// a fixed epsilon; the solver's wall_gap reads the same shift.
#[test]
fn ulp_scale_origin_penetration_from_frame_shift_is_not_held() {
    let e = profile("Eacute", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let u = profile("u", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let shift = 8.0 * f64::EPSILON * 100.0;
    let sol = solution("Eacute", "u", 100.0 - shift, -shift);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.overlap_holds.len(), 0, "holds: {:?}", out.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(out.ready.len(), 1, "frame-noise contact pair must ship ready");
    assert_eq!(out.ready[0].export_value, 0);
    assert!(out.ready[0].measured_gap_at_origin.unwrap() < 0.0, "the sub-tolerance penetration is still reported, not hidden");
}

/// Real penetration at the exact solver placement stays an OverlapHold:
/// origin 90 on touching 100-wide inks overlaps by 10 units, far beyond
/// any frame noise.
#[test]
fn real_penetration_at_origin_is_held() {
    let e = profile("Eacute", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let u = profile("u", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let sol = solution("Eacute", "u", 90.0, -10.0);
    let out = generate_residual_kern(&sol, &[e, u], &geo());
    assert_eq!(out.ready.len(), 0);
    assert_eq!(out.overlap_holds.len(), 1);
    assert!(out.overlap_holds[0].note.contains("collision at exact solver placement"), "note: {}", out.overlap_holds[0].note);
}

/// interval_overlap_depth: exact contact measures exactly 0.0.
#[test]
fn interval_overlap_depth_is_zero_at_exact_contact() {
    let e = profile("L", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let r = profile("R", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let d = signed_clearance::interval_overlap_depth(&e, &r, 0.0, 0.0, 100.0);
    assert_eq!(d, 0.0, "touching endpoints contribute no depth");
    assert!(!signed_clearance::interval_collision(&e, &r, 0.0, 0.0, 100.0));
}

/// interval_overlap_depth: a 2.5-unit penetration measures 2.5.
#[test]
fn interval_overlap_depth_measures_real_penetration() {
    let e = profile("L", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let r = profile("R", &[(0.0, 1.0, vec![(0.0, 100.0)])], [0.0, 0.0, 100.0, 1.0]);
    let d = signed_clearance::interval_overlap_depth(&e, &r, 0.0, 0.0, 97.5);
    assert_eq!(d, 2.5, "depth {}", d);
    assert!(signed_clearance::interval_collision(&e, &r, 0.0, 0.0, 97.5));
}
