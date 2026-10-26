//! Stem-pair containment-compensation invariants at the kern-guard level.
//!
//! Design under test: the post-solve containment guard translates ink for
//! glyphs whose bearings escape [0, advance]; a compensation pass then
//! shifts each pair origin by d(left) - d(right) so the pair frame gap
//! equals the solver wall gap again. Pairs the compensation pushes below
//! zero origin form the negative-origin class (architect decision): a
//! negative origin is a legal GPOS negative XAdvance, never clamped, and
//! the class is decided on the measured geometry at that origin:
//! tangent/clean pairs ship ready; a real collision ships cut at the
//! tangent (gap = 0 on the integer grid) with a typed `export_adjusted`
//! ledger row; only unmeasurable or unverifiable cases hold with the typed
//! reason `containment_compensation_negative_origin` and ship kernless.
//!
//! This file pins the kern-side half of the four invariants:
//!   held-ratio bound: held(v3) <= held(noop) + negative_origin_pairs;
//!   class rule: clean and tangent negative origins ship as legal negative
//!       XAdvance values; collisions ship cut at the tangent, ledgered;
//!   guard agreement: at the compensated origin the measured gap equals
//!       the solver wall gap within the guard's own tolerance;
//!   untouched pairs: positive-origin outcomes are exact and unaffected by
//!       the presence of class pairs in the same run.
//!
//! The hold reason is matched as a literal so this suite compiles against
//! the pre-compensation tree and fails there on behaviour, not on a
//! missing symbol. Geometry is synthetic and exact; expectations are
//! derived from the constructed coordinates.

use kni_metrics::generated_outline_kern::{
    generate_residual_kern_jobs, measure_full_outline_gap, ExportGeometry, ProfileFrame,
};
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{GlyphSpacing, PairPosition, SpacingSolution, SpaceStatus};

/// Typed hold reason for a negative post-compensation origin (registry
/// literal; mirrored here so the suite compiles before the change lands).
const NEGATIVE_ORIGIN_HOLD: &str = "containment_compensation_negative_origin";

/// Single-stem profile: one ink interval [0, 100] on two stacked unit rows
/// (a lone exact row has zero height and yields no wall segments).
fn stem(id: &str) -> OutlineProfile {
    let row = |y: f64| ScanRow {
        y,
        weight: 1.0,
        ink: vec![InkInterval { left: 0.0, right: 100.0 }],
        span_lo: y - 0.5,
        span_hi: y + 0.5,
    };
    OutlineProfile {
        glyph_id: id.to_string(),
        source_pin: format!("pin-{id}"),
        upm: 1000,
        origin: [0.0, 0.0],
        rows: vec![row(0.0), row(1.0)],
        bounds: [0.0, 0.0, 100.0, 2.0],
        ink_area: 200.0,
        counter_area: 0.0,
        open_left: 0.0,
        open_right: 0.0,
        profile_method: "synthetic-test".to_string(),
        row_step: 1.0,
        flatten_tolerance: 0.0,
    }
}

fn gs(id: &str, lsb: f64, rsb: f64, advance: f64) -> GlyphSpacing {
    GlyphSpacing { glyph_id: id.into(), lsb, rsb, advance }
}

fn pp(left: &str, right: &str, origin_distance: f64, wall_gap: f64) -> PairPosition {
    PairPosition { left: left.into(), right: right.into(), origin_distance, wall_gap, optical_cost: 1.0, compensated: false, pair_target: None }
}

/// A pair in its post-compensation state (the compensation pass shifted its
/// origin and flagged it).
fn ppc(left: &str, right: &str, origin_distance: f64, wall_gap: f64) -> PairPosition {
    PairPosition { compensated: true, ..pp(left, right, origin_distance, wall_gap) }
}

fn solution(glyphs: Vec<GlyphSpacing>, pairs: Vec<PairPosition>, fallback_pairs: Vec<PairPosition>) -> SpacingSolution {
    SpacingSolution {
        glyphs,
        pairs,
        space_status: SpaceStatus::Absent,
        excluded_pairs: Vec::new(),
        complete: true,
        excluded_self_pairs: 0,
        excluded_below_epsilon: 0,
        excluded_unmeasurable: 0,
        numeric_failed_pairs: 0,
        geometric_hold_pairs: 0,
        no_accepted_candidate_pairs: 0,
        hold_reasons: Vec::new(),
        policy_derivation: "test".to_string(),
        unobserved_policy: Vec::new(),
        font_median_pair_target: None,
        anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run(),
        contrast_floor_adjustments: Vec::new(),
        contrast_floor_failures: Vec::new(),
        x_height: 0.0,
        x_height_source: kni_metrics::self_anchored_spacing::XHeightSource::Ctx,
        cap_height: 0.0,
        baseline: 0.0,
        pair_ledger: Vec::new(),
        fallback_pairs,
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

/// RawGenerated frame: the guard measures untranslated (t = 0), so the
/// honest wall gap of two [0, 100] stems at origin o is o - 100.
fn geo() -> ExportGeometry {
    ExportGeometry {
        profile_frame: ProfileFrame::RawGenerated,
        upm: 1000,
        overlap_tolerance_units: 0.0,
        drop_zero_residual: false,
        row_align_tolerance_units: 1.0,
    }
}

/// Measured wall gap of two raw stems at `origin` (translations zero).
fn stem_gap(a: &OutlineProfile, b: &OutlineProfile, origin: f64) -> f64 {
    measure_full_outline_gap(a, b, 0.0, 0.0, origin, 1.0)
        .expect("shared scan rows")
        .min_gap
}

fn typed_hold_count(kern: &kni_metrics::generated_outline_kern::GeneratedKern) -> usize {
    kern.overlap_holds.iter().filter(|h| h.note.starts_with(NEGATIVE_ORIGIN_HOLD)).count()
}

/// Negative-origin class, collision arm: a compensated pair that truly
/// collides at its negative origin ships cut at the tangent (gap = 0 on
/// the integer grid), counted as export_adjusted with a typed ledger row -
/// never clamped, never dropped, never held. Both the solver-pair path and
/// the fallback-pair path take it.
#[test]
fn negative_origin_collision_is_cut_at_tangent_and_ledgered() {
    let (pa, pb) = (stem("A"), stem("B"));
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("B", 0.0, 0.0, 600.0)];

    for (pairs, fallback, is_fb, tag) in [
        (vec![ppc("A", "B", -1.0, stem_gap(&pa, &pb, -1.0))], vec![], false, "solver pair"),
        (vec![], vec![ppc("A", "B", -2.5, stem_gap(&pa, &pb, -2.5))], true, "fallback pair"),
    ] {
        let origin = pairs.first().or_else(|| fallback.first()).unwrap().origin_distance;
        let kern = generate_residual_kern_jobs(&solution(glyphs.clone(), pairs, fallback), &[pa.clone(), pb.clone()], &geo(), 1);
        assert_eq!(kern.receipt.overlap_held, 0, "{tag}: a repairable collision is never held");
        assert_eq!(kern.receipt.export_adjusted, 1, "{tag}: exactly one typed adjustment");
        let rows = if is_fb { &kern.fallback_ready } else { &kern.ready };
        assert_eq!(rows.len(), 1, "{tag}: the pair ships");
        let r = &rows[0];
        // Two [0, 100] stems: gap at origin o is o - 100, so the exact
        // tangent distance is origin + (100 - origin) = 100 for any origin
        // below zero; the integer grid ships 100 with gap exactly 0.
        assert_eq!(r.export_distance, 100, "{tag}: cut lands on the exact tangent distance");
        assert_eq!(r.export_value, -500, "{tag}: negative XAdvance of the tangent cut");
        assert_eq!(r.residual_units, origin - 600.0, "{tag}: residual written through, never clamped");
        assert_eq!(r.measured_gap_at_origin, Some(origin - 100.0), "{tag}: pre-cut collision kept as evidence");
        assert_eq!(r.measured_gap_at_export, Some(0.0), "{tag}: shipped geometry is exactly tangent");
        assert!(!r.ink_intersects, "{tag}: shipped geometry does not intersect");
        assert!(r.left_frame.is_some() && r.right_frame.is_some(), "{tag}: an adjusted shipment binds its frames");
        assert!(
            r.note.starts_with("export_adjusted: containment_compensation_negative_origin collision"),
            "{tag}: typed ledger row, got {:?}",
            r.note
        );
    }
}

/// Negative-origin class, legal arm: a compensated pair measured tangent or
/// clean at its negative origin ships as a legal GPOS negative XAdvance at
/// its own placement - no adjustment, no hold, no wall-gap second-guessing.
#[test]
fn negative_origin_tangent_or_clean_ships_as_legal_negative_xadvance() {
    let pa = stem("A");
    // Right ink offset by 150: the pair gap at origin o is o + 50, so
    // o = -50 is exact contact (tangent) and o = -25 is clean (gap 25).
    let poff = {
        let mut p = stem("F");
        p.glyph_id = "F".to_string();
        p.source_pin = "pin-F".to_string();
        for row in &mut p.rows {
            for iv in &mut row.ink {
                iv.left += 150.0;
                iv.right += 150.0;
            }
        }
        p.bounds = [150.0, 0.0, 250.0, 2.0];
        p
    };
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("F", 0.0, 0.0, 600.0)];

    for (origin, want_value, want_distance, want_gap, tag) in [
        (-50.0_f64, -650_i16, -50_i32, 0.0_f64, "tangent"),
        (-25.0_f64, -625_i16, -25_i32, 25.0_f64, "clean"),
    ] {
        let wall = measure_full_outline_gap(&pa, &poff, 0.0, 0.0, origin, 1.0)
            .expect("shared scan rows")
            .min_gap;
        assert_eq!(wall, want_gap, "{tag}: fixture gap premise");
        let kern = generate_residual_kern_jobs(
            &solution(glyphs.clone(), vec![ppc("A", "F", origin, wall)], vec![]),
            &[pa.clone(), poff.clone()],
            &geo(),
            1,
        );
        assert_eq!(kern.receipt.overlap_held, 0, "{tag}: a legal negative origin never holds");
        assert_eq!(kern.receipt.ready, 1, "{tag}: a legal negative origin ships");
        assert_eq!(kern.receipt.export_adjusted, 0, "{tag}: a legal placement needs no adjustment");
        let r = &kern.ready[0];
        assert_eq!((r.export_value, r.export_distance), (want_value, want_distance), "{tag}: negative XAdvance written through");
        assert_eq!(r.measured_gap_at_export, Some(want_gap), "{tag}: shipped gap is the measured gap");
        assert!(r.note.is_empty(), "{tag}: a legal shipment carries no adjustment note: {:?}", r.note);
    }
}

/// Negative-origin class, rounding-repair arm: the tangent/clean verdict is
/// taken at the exact origin; when the integer-rounded export distance
/// collides, the existing safe-integer guard repairs it and the row is
/// ledgered with the same typed export_adjusted reason as the generic path.
#[test]
fn negative_origin_legal_arm_keeps_the_rounding_guard() {
    let pa = stem("A");
    // Right ink offset by 149.6: gap at origin o is o + 49.6. At o = -49.51
    // the exact placement is clean (gap 0.09) but the rounded distance -50
    // collides (gap -0.41); the safe integer is -49 (gap 0.59).
    let poff = {
        let mut p = stem("F");
        p.glyph_id = "F".to_string();
        p.source_pin = "pin-F".to_string();
        for row in &mut p.rows {
            for iv in &mut row.ink {
                iv.left += 149.6;
                iv.right += 149.6;
            }
        }
        p.bounds = [149.6, 0.0, 249.6, 2.0];
        p
    };
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("F", 0.0, 0.0, 600.0)];
    let origin = -49.51_f64;
    let wall = measure_full_outline_gap(&pa, &poff, 0.0, 0.0, origin, 1.0)
        .expect("shared scan rows")
        .min_gap;
    assert!(wall > 0.0 && wall < 0.5, "fixture premise: clean but fragile placement, gap {wall}");
    let kern = generate_residual_kern_jobs(
        &solution(glyphs, vec![ppc("A", "F", origin, wall)], vec![]),
        &[pa, poff],
        &geo(),
        1,
    );
    assert_eq!(kern.receipt.overlap_held, 0, "a rounding collision is repaired, never held");
    assert_eq!(kern.receipt.ready, 1);
    assert_eq!(kern.receipt.export_adjusted, 1, "the repair is counted");
    let r = &kern.ready[0];
    assert_eq!(r.export_distance, -49, "safe integer above the colliding rounded distance");
    assert!(r.measured_gap_at_export.unwrap() > 0.0, "shipped gap positive: {:?}", r.measured_gap_at_export);
    assert!(!r.ink_intersects);
    assert!(r.note.starts_with("export_adjusted: rounded distance -50 collided"), "guard note: {:?}", r.note);
}

/// Negative-origin class, residual hold: without measurable geometry the
/// class cannot be decided, so the pair keeps the typed
/// `containment_compensation_negative_origin` hold and ships kernless -
/// never clamped, never guessed.
#[test]
fn negative_origin_without_geometry_keeps_the_typed_hold() {
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("B", 0.0, 0.0, 600.0)];
    let mut p = pp("A", "B", -1.0, 0.0);
    p.compensated = true;
    let kern = generate_residual_kern_jobs(&solution(glyphs, vec![p], vec![]), &[], &geo(), 1);
    assert_eq!(kern.receipt.ready, 0);
    assert_eq!(kern.receipt.overlap_held, 1);
    let h = &kern.overlap_holds[0];
    assert!(h.note.starts_with(NEGATIVE_ORIGIN_HOLD), "typed reason kept: {:?}", h.note);
    assert_eq!(h.export_value, 0, "held pair ships kernless");
    assert!(h.left_frame.is_none() && h.right_frame.is_none(), "frames stay unbound on a hold");
}

/// Held-ratio bound: with the compensation active, the held share never
/// exceeds the noop (uncompensated) share plus the negative-origin share.
/// Under the class rule the negative-origin pairs do not hold at all: a
/// colliding one ships cut at the tangent with a typed export_adjusted
/// row, so held(v3) equals held(noop) here and the bound holds with slack.
/// Genuine overlaps keep their own untyped hold reason in both runs.
#[test]
fn held_ratio_bound_and_typed_hold_count() {
    let (pa, pb) = (stem("A"), stem("B"));
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("B", 0.0, 0.0, 600.0)];

    // Clean pairs (ready in every run), one genuine collision (untyped hold
    // in every run), and three pairs the compensation scenario pushes below
    // zero (cut-at-tangent shipments in the compensated run, clean in the
    // noop run).
    let clean_origins = [650.0, 660.0, 670.0, 680.0, 690.0];
    let negative_origins = [-1.0, -2.5, -0.25];
    let noop_origins = [650.5, 660.5, 670.5]; // pre-compensation placement of the same pairs

    let build = |neg: &[f64]| -> Vec<PairPosition> {
        let mut v: Vec<PairPosition> = clean_origins
            .iter()
            .map(|&o| pp("A", "B", o, stem_gap(&pa, &pb, o)))
            .collect();
        v.push(pp("A", "B", 90.0, stem_gap(&pa, &pb, 90.0))); // genuine overlap
        v.extend(neg.iter().map(|&o| if o < 0.0 { ppc("A", "B", o, stem_gap(&pa, &pb, o)) } else { pp("A", "B", o, stem_gap(&pa, &pb, o)) }));
        v
    };

    let noop = generate_residual_kern_jobs(&solution(glyphs.clone(), build(&noop_origins), vec![]), &[pa.clone(), pb.clone()], &geo(), 1);
    let v3 = generate_residual_kern_jobs(&solution(glyphs, build(&negative_origins), vec![]), &[pa.clone(), pb.clone()], &geo(), 1);

    let total = noop.receipt.ready + noop.receipt.fallback_ready + noop.receipt.overlap_held + noop.receipt.rejected + noop.receipt.dropped_zero;
    assert_eq!(total, 9, "fixture covers every pair exactly once");
    assert_eq!(noop.receipt.overlap_held, 1, "noop run holds only the genuine collision");
    assert_eq!(typed_hold_count(&noop), 0, "noop run has no negative-origin pairs");

    let n_neg = negative_origins.len();
    assert!(
        v3.receipt.overlap_held <= noop.receipt.overlap_held + n_neg,
        "held(v3) {} exceeds held(noop) {} + negative_origin_pairs {n_neg}",
        v3.receipt.overlap_held, noop.receipt.overlap_held
    );
    assert_eq!(typed_hold_count(&v3), 0, "no negative-origin pair holds under the class rule");
    assert_eq!(v3.receipt.overlap_held, 1, "only the genuine collision holds");
    assert_eq!(v3.receipt.export_adjusted, n_neg, "every colliding negative origin ships cut at the tangent");
    assert_eq!(
        v3.receipt.ready,
        clean_origins.len() + n_neg,
        "clean pairs and tangent cuts ship ready"
    );
    let cuts: Vec<_> = v3.ready.iter().filter(|r| r.note.starts_with("export_adjusted: containment_compensation_negative_origin")).collect();
    assert_eq!(cuts.len(), n_neg, "every cut carries the typed ledger row");
    for r in cuts {
        assert_eq!(r.export_distance, 100, "tangent distance for two [0, 100] stems");
        assert_eq!(r.export_value, -500, "negative XAdvance of the cut");
        assert_eq!(r.measured_gap_at_export, Some(0.0), "shipped geometry is exactly tangent");
    }
}

/// Guard agreement after a containment translation: glyph I's ink moved
/// right by 149 (lsb -130 -> 19, advance 525 -> 674, rsb preserved). At the
/// compensated origin the measured gap equals the solver wall gap and the
/// pair ships ready; at the uncompensated origin the guard disagrees and
/// holds. Translations here are ExportedB (t = lsb - ink_xmin).
#[test]
fn guard_gap_matches_wall_gap_at_compensated_origin() {
    let (pi, ph) = (stem("I"), stem("H"));
    let geo = ExportGeometry {
        profile_frame: ProfileFrame::ExportedB,
        upm: 1000,
        overlap_tolerance_units: 0.0,
        drop_zero_residual: false,
        row_align_tolerance_units: 1.0,
    };
    // Pre-fix frames: t_I = -130, t_H = 19; solver placement 600.
    let t_i_pre = -130.0;
    let t_h = 19.0;
    let wall_gap = measure_full_outline_gap(&pi, &ph, t_i_pre, t_h, 600.0, 1.0)
        .expect("shared rows")
        .min_gap;
    let d_i = 149.0_f64; // lsb_after - lsb_before = 19 - (-130)
    let compensated = 600.0 + d_i;

    let glyphs_post = vec![gs("I", 19.0, 19.0, 674.0), gs("H", 19.0, 19.0, 525.0)];

    let ok = generate_residual_kern_jobs(
        &solution(glyphs_post.clone(), vec![ppc("I", "H", compensated, wall_gap)], vec![]),
        &[pi.clone(), ph.clone()],
        &geo,
        1,
    );
    assert_eq!(ok.receipt.overlap_held, 0, "compensated origin must not be held");
    assert_eq!(ok.receipt.ready, 1);
    let r = &ok.ready[0];
    let tol = 1024.0 * f64::EPSILON * (1.0 + wall_gap.abs() + wall_gap.abs() + compensated.abs());
    assert!(
        (r.measured_gap_at_origin.unwrap() - wall_gap).abs() <= tol,
        "guard gap {} vs solver wall_gap {wall_gap}",
        r.measured_gap_at_origin.unwrap()
    );

    let bad = generate_residual_kern_jobs(
        &solution(glyphs_post, vec![pp("I", "H", 600.0, wall_gap)], vec![]),
        &[pi, ph],
        &geo,
        1,
    );
    assert_eq!(bad.receipt.ready, 0, "uncompensated origin must not ship");
    assert_eq!(bad.receipt.overlap_held, 1);
    assert!(bad.overlap_holds[0].note.contains("disagree"), "note: {}", bad.overlap_holds[0].note);
    assert!(
        !bad.overlap_holds[0].note.starts_with(NEGATIVE_ORIGIN_HOLD),
        "a guard disagreement is not a negative-origin hold"
    );
}

/// Untouched pairs are unaffected by class pairs in the same run: clean
/// positive-origin pairs ship with their exact export values and measured
/// gaps whether or not a negative-origin class pair is present.
#[test]
fn shipped_negative_origin_pair_does_not_touch_ready_rows() {
    let (pa, pb) = (stem("A"), stem("B"));
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("B", 0.0, 0.0, 600.0)];
    let clean = vec![
        pp("A", "B", 650.0, stem_gap(&pa, &pb, 650.0)),
        pp("A", "B", 660.0, stem_gap(&pa, &pb, 660.0)),
    ];

    let alone = generate_residual_kern_jobs(&solution(glyphs.clone(), clean.clone(), vec![]), &[pa.clone(), pb.clone()], &geo(), 1);
    let mut with_class = clean;
    with_class.push(ppc("A", "B", -1.0, stem_gap(&pa, &pb, -1.0)));
    let mixed = generate_residual_kern_jobs(&solution(glyphs, with_class, vec![]), &[pa.clone(), pb.clone()], &geo(), 1);

    assert_eq!(alone.receipt.ready, 2);
    assert_eq!(mixed.receipt.ready, 3, "the two clean pairs plus the tangent cut");
    for (a, b) in alone.ready.iter().zip(mixed.ready.iter()) {
        assert_eq!(a.residual_units.to_bits(), b.residual_units.to_bits());
        assert_eq!(a.export_value, b.export_value);
        assert_eq!(a.export_distance, b.export_distance);
        assert_eq!(a.measured_gap_at_origin.map(f64::to_bits), b.measured_gap_at_origin.map(f64::to_bits));
        assert_eq!(a.measured_gap_at_export.map(f64::to_bits), b.measured_gap_at_export.map(f64::to_bits));
    }
    assert_eq!((50, 650), (mixed.ready[0].export_value, mixed.ready[0].export_distance));
    assert_eq!((60, 660), (mixed.ready[1].export_value, mixed.ready[1].export_distance));
    let cut = &mixed.ready[2];
    assert_eq!((cut.export_value, cut.export_distance), (-500, 100), "class pair ships the tangent cut");
    assert!(cut.note.starts_with("export_adjusted: containment_compensation_negative_origin"));
}

/// A negative origin on a pair the compensation never touched is NOT
/// attributed to containment: no typed reason, no kernless binding — the
/// pair follows the normal geometry path (here: a genuine collision hold
/// with full frame binding).
#[test]
fn untouched_negative_origin_keeps_the_geometry_path() {
    let (pa, pb) = (stem("A"), stem("B"));
    let glyphs = vec![gs("A", 0.0, 0.0, 600.0), gs("B", 0.0, 0.0, 600.0)];
    let sol = solution(glyphs, vec![pp("A", "B", -1.0, stem_gap(&pa, &pb, -1.0))], vec![]);
    let kern = generate_residual_kern_jobs(&sol, &[pa.clone(), pb.clone()], &geo(), 1);
    assert_eq!(kern.receipt.overlap_held, 1);
    let h = &kern.overlap_holds[0];
    assert!(
        !h.note.starts_with(NEGATIVE_ORIGIN_HOLD),
        "an untouched pair never carries the containment reason: {:?}",
        h.note
    );
    assert!(h.note.starts_with("collision at exact solver placement"), "geometry verdict kept: {:?}", h.note);
    assert!(h.left_frame.is_some() && h.right_frame.is_some(), "geometry holds bind their frames");
    assert!(h.measured_gap_at_origin.is_some(), "geometry holds keep their gap evidence");
}
