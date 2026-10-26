//! Stem-pair containment-compensation invariants (function level).
//!
//! Design under test: the containment guard grows the advance of glyphs
//! whose bearings escape [0, advance] (left fix translates the ink right
//! by d = lsb_after - lsb_before, right fix widens the advance only). A
//! compensation pass then shifts every pair origin by d(left) - d(right),
//! restoring the pair frame gap to the solver wall gap. Pairs pushed below
//! zero origin form the negative-origin class (architect decision): never
//! clamped; measured tangent/clean pairs ship as legal GPOS negative
//! XAdvance values, real collisions ship cut at the tangent with a typed
//! `export_adjusted` row, and only unmeasurable or unverifiable cases hold
//! with the typed reason `containment_compensation_negative_origin`.
//!
//! The four invariants under test (suite runs downstream of the class
//! spacing policy stage; that policy is out of scope here):
//!   I1 held-ratio bound: held(compensated) <= held(noop) + negative-origin
//!      pairs, and containment-prefixed holds == negative-origin pairs.
//!      The noop baseline is the same applied population without the
//!      compensation call (compensation-off semantics).
//!   I2 violating glyphs sit at the font-derived floor; after the guard
//!      every inked glyph has lsb >= 0 and rsb >= 0; floor base sizes are
//!      reported and positive whenever an adjustment exists.
//!   I3 guard gap == solver wall gap: at compensated origins the frame gap
//!      (and the kern guard's measured gap) matches the pre-containment
//!      wall gap; non-typed overlap holds vanish.
//!   I4 untouched glyphs and pairs stay bit-identical, at the metric level
//!      and at the level of their kern ledger rows between the noop and
//!      compensated runs.
//!
//! Geometry is synthetic and exact; expectations are derived from the
//! constructed coordinates. Fractional fixtures use ulp-scaled tolerance;
//! integer fixtures are compared bitwise.

use crate::ink_containment::{self, Adjustment};
use kni_metrics::generated_outline_kern::{
    generate_residual_kern_jobs, measure_full_outline_gap, ExportGeometry, GeneratedKern,
    GeneratedKernPair, ProfileFrame,
};
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{GlyphSpacing, PairPosition, SpacingSolution, SpaceStatus};

const NEGATIVE_ORIGIN_HOLD: &str = "containment_compensation_negative_origin";

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
    PairPosition { left: left.into(), right: right.into(), origin_distance, wall_gap, optical_cost: 1.0, pair_target: None, compensated: false }
}

/// Reason type token: the note prefix before its first numeric parameter.
/// The known hold shapes are matched on their literal prefixes; anything
/// else compares as its full string.
fn reason_type(note: &str) -> &str {
    for prefix in [
        "containment_compensation_negative_origin",
        "collision at exact solver placement",
        "solver wall_gap",
        "no verified safe integer distance near",
    ] {
        if note.starts_with(prefix) {
            return prefix;
        }
    }
    note
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

/// ExportedB: the production frame; the guard measures with t = lsb - ink_xmin.
fn geo() -> ExportGeometry {
    ExportGeometry {
        profile_frame: ProfileFrame::ExportedB,
        upm: 1000,
        overlap_tolerance_units: 0.0,
        drop_zero_residual: false,
        row_align_tolerance_units: 1.0,
    }
}

/// Ink-to-ink wall gap of two stem profiles in the ExportedB frame.
fn wall_gap(l: &OutlineProfile, r: &OutlineProfile, lsb_l: f64, lsb_r: f64, origin: f64) -> f64 {
    measure_full_outline_gap(l, r, lsb_l - l.bounds[0], lsb_r - r.bounds[0], origin, 1.0)
        .expect("shared scan rows")
        .min_gap
}

fn metric_bits(g: &GlyphSpacing) -> (u64, u64, u64) {
    (g.lsb.to_bits(), g.rsb.to_bits(), g.advance.to_bits())
}

fn ready_row_bits(p: &GeneratedKernPair) -> (u64, i16, i32, Option<u64>, Option<u64>) {
    (
        p.residual_units.to_bits(),
        p.export_value,
        p.export_distance,
        p.measured_gap_at_origin.map(f64::to_bits),
        p.measured_gap_at_export.map(f64::to_bits),
    )
}

fn ready_by_pair(kern: &GeneratedKern) -> std::collections::BTreeMap<(String, String), GeneratedKernPair> {
    kern.ready.iter().map(|p| ((p.left.clone(), p.right.clone()), p.clone())).collect()
}

fn typed_hold_count(kern: &GeneratedKern) -> usize {
    kern.overlap_holds.iter().filter(|h| h.note.starts_with(NEGATIVE_ORIGIN_HOLD)).count()
}

/// I2: every violating glyph lands exactly on the font-derived floor, the
/// advance grows by the exact translation, no inked glyph keeps a negative
/// bearing, and the floor base sizes are reported and positive.
#[test]
fn invariant2_violating_glyphs_sit_at_the_floor() {
    let mut glyphs = vec![
        gs("H", 19.0, 19.0, 525.0),
        gs("N", 19.0, 19.0, 525.0),
        gs("M", 19.0, 19.0, 525.0),
        gs("I", -130.0, 19.0, 525.0),  // left escape
        gs("O", 19.0, -60.0, 548.0),   // right escape
        gs("Q", -5.0, -7.0, 400.0),    // both sides escape
    ];
    let profiles: Vec<OutlineProfile> = ["H", "N", "M", "I", "O", "Q"].map(stem).into();
    let out = ink_containment::apply(&mut glyphs, &profiles, &vec![pp("H", "N", 600.0, 0.0), pp("M", "I", 600.0, 0.0), pp("O", "Q", 400.0, 0.0)], &ink_containment::FloorEvidence { font_median_pair_target: None });

    assert_eq!(out.adjustments.len(), 3);
    assert!(out.floor_lsb_count > 0 && out.floor_rsb_count > 0, "floor base sizes reported and positive when adjustments exist");
    assert_eq!(out.floor_lsb_count, 4, "every inked glyph with lsb >= 0 feeds the lsb floor (H, N, M, O)");
    assert_eq!(out.floor_rsb_count, 4, "every inked glyph with rsb >= 0 feeds the rsb floor (H, N, M, I)");
    assert_eq!(out.floor_lsb, 19.0);
    assert_eq!(out.floor_rsb, 19.0);

    for a in &out.adjustments {
        if a.lsb_before < 0.0 {
            assert_eq!(a.lsb_after, out.floor_lsb, "{}: left violator sits at the lsb floor", a.glyph_id);
        } else {
            assert_eq!(a.lsb_after, a.lsb_before, "{}: non-violating lsb untouched", a.glyph_id);
        }
        if a.rsb_before < 0.0 {
            assert_eq!(a.rsb_after, out.floor_rsb, "{}: right violator sits at the rsb floor", a.glyph_id);
        } else {
            assert_eq!(a.rsb_after, a.rsb_before, "{}: non-violating rsb untouched", a.glyph_id);
        }
        let growth = (a.lsb_after - a.lsb_before).max(0.0) + (a.rsb_after - a.rsb_before).max(0.0);
        assert_eq!(a.advance_after, a.advance_before + growth, "{}: advance grows by the exact translation", a.glyph_id);
        assert!(a.advance_after > a.advance_before, "{}: corrections grow the advance only", a.glyph_id);
    }
    for g in &glyphs {
        assert!(g.lsb >= 0.0 && g.rsb >= 0.0, "{}: no inked glyph keeps a negative bearing", g.glyph_id);
    }

    let r = ink_containment::receipt(&out);
    assert!(r.starts_with("warning\tink_containment_adjusted\tcount\t3\t"), "typed summary row: {r:?}");
    assert!(
        r.contains(&format!("floor_lsb_n\t{}\tfloor_rsb_n\t{}\n", out.floor_lsb_count, out.floor_rsb_count)),
        "typed floor row with base sizes: {r:?}"
    );
    for a in &out.adjustments {
        assert!(r.contains(&format!("ink_containment\t{}\tlsb_before", a.glyph_id)), "per-glyph typed row for {}", a.glyph_id);
    }
}

/// I3 (frame identity): after apply + compensate, the pair frame gap
/// gap = origin_distance + lsb_R - (advance_L - rsb_L) equals the
/// pre-containment gap bitwise on integer fixtures and within ulp-scaled
/// tolerance on fractional fixtures.
#[test]
fn invariant3_frame_gap_restored_by_compensation() {
    let frame_gap = |origin: f64, l_adv: f64, r_rsb: f64, r_lsb: f64| origin + r_lsb - (l_adv - r_rsb);

    // Integer fixture: bitwise.
    let mut glyphs = vec![gs("H", 19.0, 19.0, 525.0), gs("M", 19.0, 19.0, 525.0), gs("I", -130.0, 19.0, 525.0)];
    let profiles: Vec<OutlineProfile> = ["H", "M", "I"].map(stem).into();
    let pre: std::collections::BTreeMap<(String, String), f64> = [
        (("I".to_string(), "H".to_string()), frame_gap(600.0, 525.0, 19.0, 19.0)),
        (("H".to_string(), "I".to_string()), frame_gap(700.0, 525.0, 19.0, -130.0)),
    ]
    .into_iter()
    .collect();
    let mut pairs = vec![pp("I", "H", 600.0, 0.0), pp("H", "I", 700.0, 0.0)];
    let containment = ink_containment::apply(&mut glyphs, &profiles, &[], &ink_containment::FloorEvidence { font_median_pair_target: None });
    let g: std::collections::BTreeMap<String, &GlyphSpacing> = glyphs.iter().map(|x| (x.glyph_id.clone(), x)).collect();
    let outcome = ink_containment::compensate_pair_origins(&mut pairs, &mut [], &containment.adjustments);
    assert_eq!(outcome.pairs_shifted, 2);
    assert!(outcome.negative_origin_pairs.is_empty());
    for p in &pairs {
        let (l, r) = (&g[&p.left], &g[&p.right]);
        let after = frame_gap(p.origin_distance, l.advance, r.rsb, r.lsb);
        let before = pre[&(p.left.clone(), p.right.clone())];
        assert_eq!(after.to_bits(), before.to_bits(), "{}->{}: frame gap restored bitwise", p.left, p.right);
    }

    // Fractional fixture: ulp-scaled tolerance.
    let adj = Adjustment {
        glyph_id: "I".into(),
        lsb_before: -0.1,
        lsb_after: 19.1,
        rsb_before: 19.05,
        rsb_after: 19.05,
        advance_before: 400.33,
        advance_after: 400.33 + (19.1 - (-0.1)),
    };
    let d = adj.lsb_after - adj.lsb_before;
    let before = frame_gap(500.17, 400.33, 19.05, 19.0);
    let mut fr_pairs = vec![pp("I", "H", 500.17, 0.0), pp("H", "I", 300.29, 0.0)];
    let fr_out = ink_containment::compensate_pair_origins(&mut fr_pairs, &mut [], &[adj]);
    assert_eq!(fr_out.pairs_shifted, 2);
    let after_left = frame_gap(fr_pairs[0].origin_distance, 400.33 + d, 19.05, 19.0);
    let before_right = frame_gap(300.29, 525.0, 19.05, -0.1);
    let after_right = frame_gap(fr_pairs[1].origin_distance, 525.0, 19.05, -0.1 + d);
    for (after, before, tag) in [(after_left, before, "I->H"), (after_right, before_right, "H->I")] {
        let tol = 4.0 * f64::EPSILON * before.abs().max(1.0);
        assert!((after - before).abs() <= tol, "{tag}: frame gap drift {} exceeds {tol:e}", (after - before).abs());
    }
}

/// I1 + I3 + I4 through the real kern guard: one synthetic population, one
/// noop run (containment applied, compensation off) and one compensated
/// run. Held ratio stays within noop + negative-origin pairs; every held
/// pair in the compensated run carries the typed reason; ready pairs
/// measure within the guard's own tolerance of the solver wall gap; pairs
/// and glyphs the guard never touched are bit-identical across both runs.
#[test]
fn invariants_1_3_4_noop_vs_compensated_run() {
    let profiles: Vec<OutlineProfile> = ["H", "N", "M", "I", "O"].map(stem).into();
    let base_glyphs = || {
        vec![
            gs("H", 19.0, 19.0, 525.0),
            gs("N", 19.0, 19.0, 525.0),
            gs("M", 19.0, 19.0, 525.0),
            gs("I", -130.0, 19.0, 525.0), // left escape, d = 149
            gs("O", 19.0, -60.0, 548.0),  // right escape, no ink translation
        ]
    };
    let (pi, ph, pn, po) = (&profiles[3], &profiles[0], &profiles[1], &profiles[4]);
    // Solver wall gaps measured on the pre-containment frames.
    let base_pairs = move || {
        vec![
            pp("I", "H", 600.0, wall_gap(pi, ph, -130.0, 19.0, 600.0)),
            pp("H", "I", 700.0, wall_gap(ph, pi, 19.0, -130.0, 700.0)),
            pp("N", "I", 100.0, wall_gap(pn, pi, 19.0, -130.0, 100.0)),
            pp("H", "N", 600.5, wall_gap(ph, pn, 19.0, 19.0, 600.5)),
            pp("N", "O", 650.0, wall_gap(pn, po, 19.0, 19.0, 650.0)),
            pp("O", "H", 655.0, wall_gap(po, ph, 19.0, 19.0, 655.0)),
        ]
    };
    let untouched_pair_keys: [(String, String); 3] = [
        ("H".to_string(), "N".to_string()),
        ("N".to_string(), "O".to_string()),
        ("O".to_string(), "H".to_string()),
    ];

    // Noop run: containment applied, compensation OFF.
    let mut noop_glyphs = base_glyphs();
    let noop_pairs = base_pairs();
    let _ = ink_containment::apply(&mut noop_glyphs, &profiles, &noop_pairs, &ink_containment::FloorEvidence { font_median_pair_target: None });
    let noop_kern = generate_residual_kern_jobs(&solution(noop_glyphs.clone(), noop_pairs.clone(), vec![]), &profiles, &geo(), 1);

    // Compensated run.
    let mut v3_glyphs = base_glyphs();
    let mut v3_pairs = base_pairs();
    let v3_containment = ink_containment::apply(&mut v3_glyphs, &profiles, &v3_pairs, &ink_containment::FloorEvidence { font_median_pair_target: None });
    let compensation = ink_containment::compensate_pair_origins(&mut v3_pairs, &mut [], &v3_containment.adjustments);
    let v3_kern = generate_residual_kern_jobs(&solution(v3_glyphs.clone(), v3_pairs.clone(), vec![]), &profiles, &geo(), 1);

    // Premise: the noop run surfaces guard-disagreement holds on the pairs
    // whose frames the containment translation shifted.
    assert_eq!(noop_kern.receipt.overlap_held, 3, "noop run: I->H, H->I and N->I disagree with the guard");
    assert_eq!(typed_hold_count(&noop_kern), 0);

    // Compensation flags: exactly the shifted pairs are flagged.
    for p in &v3_pairs {
        let shifted = ["I"].contains(&p.left.as_str()) || ["I"].contains(&p.right.as_str());
        assert_eq!(p.compensated, shifted, "{}->{}: compensated flag == actually shifted", p.left, p.right);
    }

    // I1.
    let n_neg = compensation.negative_origin_pairs.len();
    assert_eq!(n_neg, 1, "exactly N->I is pushed below zero origin");
    assert_eq!(compensation.negative_origin_pairs, vec![("N".to_string(), "I".to_string())]);
    assert!(
        v3_kern.receipt.overlap_held <= noop_kern.receipt.overlap_held + n_neg,
        "held(v3) {} exceeds held(noop) {} + {n_neg}",
        v3_kern.receipt.overlap_held, noop_kern.receipt.overlap_held
    );
    // Class rule: N->I no longer holds - it ships as a legal negative
    // XAdvance (measured tangent/clean at its compensated origin) or cut at
    // the tangent with a typed export_adjusted row on a real collision.
    assert_eq!(typed_hold_count(&v3_kern), 0, "no negative-origin pair holds under the class rule");
    assert_eq!(v3_kern.receipt.overlap_held, 0, "I3: no overlap holds survive compensation");
    let ni = v3_kern.ready.iter().chain(v3_kern.fallback_ready.iter())
        .find(|r| r.left == "N" && r.right == "I")
        .expect("N->I ships under the class rule");
    assert!(ni.export_value < 0, "N->I ships a negative XAdvance (legal GPOS): {}", ni.export_value);
    if ni.note.starts_with("export_adjusted: containment_compensation_negative_origin") {
        assert_eq!(v3_kern.receipt.export_adjusted, 1, "the tangent cut is counted");
        assert!(ni.measured_gap_at_export.expect("cut carries export gap evidence") >= 0.0,
            "the cut ships collision-free");
    } else {
        assert!(ni.note.is_empty(), "a legal shipment carries no note: {:?}", ni.note);
        let measured = ni.measured_gap_at_origin.expect("class pair carries origin gap evidence");
        let w = v3_pairs.iter().find(|p| p.left == "N" && p.right == "I").unwrap().wall_gap;
        let tol = 1024.0 * f64::EPSILON * (1.0 + w.abs() + measured.abs() + ni.residual_units.abs() + 600.0);
        assert!((measured - w).abs() <= tol, "N->I: guard gap {measured} vs wall_gap {w}");
    }

    // I3: ready pairs measure within the guard tolerance of the wall gap.
    let wg: std::collections::BTreeMap<(String, String), f64> =
        v3_pairs.iter().map(|p| ((p.left.clone(), p.right.clone()), p.wall_gap)).collect();
    for r in &v3_kern.ready {
        if r.note.starts_with("export_adjusted") {
            // Tangent cut: the shipped geometry is collision-free at the
            // adjusted distance; the pre-cut origin gap stays as evidence.
            let shipped = r.measured_gap_at_export.expect("adjusted pair carries export gap evidence");
            assert!(shipped >= 0.0, "{}->{}: cut ships at gap {shipped}", r.left, r.right);
            continue;
        }
        let w = wg[&(r.left.clone(), r.right.clone())];
        let measured = r.measured_gap_at_origin.expect("ready pair carries origin gap evidence");
        let tol = 1024.0 * f64::EPSILON * (1.0 + w.abs() + measured.abs() + r.residual_units.abs() + 600.0);
        assert!((measured - w).abs() <= tol, "{}->{}: guard gap {measured} vs wall_gap {w}", r.left, r.right);
    }

    // The class pair ships cut at the tangent, never kernless, never held:
    // origin -49 (100 - 149 after compensation), measured collision depth
    // 149 at the origin, cut at the integer tangent distance 100 with the
    // gap exactly 0 on the shipped geometry; the residual is written
    // through unclamped and the row carries the typed export_adjusted
    // ledger reason. (Values measured on this fixture.)
    let ni = v3_kern.ready.iter().find(|r| r.left == "N" && r.right == "I")
        .expect("N->I ships under the class rule");
    assert_eq!(ni.residual_units, 100.0 - 149.0 - 525.0, "negative origin written through, never clamped");
    assert_eq!(ni.export_distance, 100, "cut lands on the exact tangent distance");
    assert_eq!(ni.export_value, -425, "negative XAdvance of the cut: 100 - 525");
    assert_eq!(ni.measured_gap_at_origin, Some(-149.0), "pre-cut collision kept as evidence");
    assert_eq!(ni.measured_gap_at_export, Some(0.0), "shipped geometry is exactly tangent");
    assert!(!ni.ink_intersects);
    assert!(ni.left_frame.is_some() && ni.right_frame.is_some(), "an adjusted shipment binds its frames");
    assert!(
        ni.note.starts_with("export_adjusted: containment_compensation_negative_origin collision"),
        "typed ledger row: {:?}", ni.note
    );

    // I4: untouched glyphs bit-identical at the metric level.
    let before: std::collections::BTreeMap<String, (u64, u64, u64)> =
        base_glyphs().iter().map(|g| (g.glyph_id.clone(), metric_bits(g))).collect();
    for name in ["H", "N", "M"] {
        let g = v3_glyphs.iter().find(|g| g.glyph_id == name).unwrap();
        assert_eq!(&before[name], &metric_bits(g), "{name}: untouched glyph keeps bit-identical metrics");
    }
    // I4: untouched pairs keep bit-identical origins through compensation.
    let noop_origin: std::collections::BTreeMap<(String, String), u64> =
        noop_pairs.iter().map(|p| ((p.left.clone(), p.right.clone()), p.origin_distance.to_bits())).collect();
    for p in &v3_pairs {
        let key = (p.left.clone(), p.right.clone());
        if untouched_pair_keys.contains(&key) {
            assert_eq!(p.origin_distance.to_bits(), noop_origin[&key], "{}->{}: untouched pair origin bit-identical", p.left, p.right);
        }
    }
    // I4 at the kern-ledger level: untouched pairs' ready rows are
    // bit-identical between the noop and compensated runs.
    let noop_ready = ready_by_pair(&noop_kern);
    let v3_ready = ready_by_pair(&v3_kern);
    for key in &untouched_pair_keys {
        let (a, b) = (noop_ready.get(key), v3_ready.get(key));
        let (a, b) = (a.unwrap_or_else(|| panic!("{key:?} ready in noop run")), b.unwrap_or_else(|| panic!("{key:?} ready in compensated run")));
        assert_eq!(ready_row_bits(a), ready_row_bits(b), "{key:?}: kern row bit-identical across runs");
    }
}

/// The no-clamp contract at the compensation boundary, the fallback-pair
/// arm, and the typed receipt row.
#[test]
fn negative_origin_written_through_counted_never_clamped() {
    let adj = Adjustment {
        glyph_id: "I".into(),
        lsb_before: -130.0,
        lsb_after: 19.0,
        rsb_before: 19.0,
        rsb_after: 19.0,
        advance_before: 525.0,
        advance_after: 674.0,
    };
    let mut pairs = vec![pp("H", "I", 100.0, 0.0)];
    let mut fallback = vec![pp("I", "H", 600.0, 0.0)];
    let out = ink_containment::compensate_pair_origins(&mut pairs, &mut fallback, &[adj]);
    assert_eq!(pairs[0].origin_distance, 100.0 - 149.0, "negative value written through, no clamp");
    assert!(pairs[0].compensated && fallback[0].compensated, "shifted pairs are flagged");
    assert_eq!(out.negative_origin_pairs, vec![("H".to_string(), "I".to_string())]);
    assert_eq!(fallback[0].origin_distance, 600.0 + 149.0, "fallback pairs compensate too");
    assert_eq!(out.pairs_shifted, 2);
    assert_eq!(out.pairs_untouched, 0);
    assert_eq!(
        ink_containment::compensation_receipt(&out),
        "containment_compensation\tpairs_shifted\t2\tpairs_untouched\t0\tnegative_origin_pairs\t1\n",
        "typed receipt row"
    );
}

/// A right fix widens the advance but moves no ink: the glyph contributes
/// no delta and its pairs stay bit-identical.
#[test]
fn right_fix_only_glyph_contributes_no_delta() {
    let adj = Adjustment {
        glyph_id: "O".into(),
        lsb_before: 19.0,
        lsb_after: 19.0,
        rsb_before: -60.0,
        rsb_after: 19.0,
        advance_before: 548.0,
        advance_after: 627.0,
    };
    let mut pairs = vec![pp("H", "O", 600.5, 0.0), pp("O", "H", 601.5, 0.0)];
    let bits: Vec<u64> = pairs.iter().map(|p| p.origin_distance.to_bits()).collect();
    let out = ink_containment::compensate_pair_origins(&mut pairs, &mut [], &[adj]);
    assert_eq!(out.pairs_shifted, 0);
    assert_eq!(out.pairs_untouched, 2);
    for (p, b) in pairs.iter().zip(bits) {
        assert_eq!(p.origin_distance.to_bits(), b, "{}->{}: no arithmetic on untouched pairs", p.left, p.right);
        assert!(!p.compensated, "{}->{}: untouched pairs are never flagged", p.left, p.right);
    }
    assert!(out.negative_origin_pairs.is_empty(), "untouched pairs are never counted as negative-origin");
}

/// I1b reason whitelist: on pairs the delta map actually shifted, a hold
/// reason may keep its type, become the typed negative-origin hold, or
/// transition disagree -> collision (counted separately). On unshifted
/// pairs the hold status and reason are byte-identical between the noop
/// and compensated runs. Any other difference fails.
#[test]
fn invariant1b_reason_transitions_whitelist() {
    let profiles: Vec<OutlineProfile> = ["H", "N", "M", "I"].map(stem).into();
    let base_glyphs = || {
        vec![
            gs("H", 19.0, 19.0, 525.0),
            gs("N", 19.0, 19.0, 525.0),
            gs("M", 19.0, 19.0, 525.0),
            gs("I", -130.0, 19.0, 525.0),
        ]
    };
    let (pi, ph, pn, pm) = (&profiles[3], &profiles[0], &profiles[1], &profiles[2]);
    let base_pairs = move || {
        vec![
            pp("I", "H", 600.0, wall_gap(pi, ph, -130.0, 19.0, 600.0)), // shifted, disagree -> ready
            pp("H", "I", 700.0, wall_gap(ph, pi, 19.0, -130.0, 700.0)), // shifted, disagree -> ready
            pp("N", "I", 100.0, wall_gap(pn, pi, 19.0, -130.0, 100.0)), // shifted, -> typed hold
            pp("M", "I", 200.0, wall_gap(pm, pi, 19.0, -130.0, 200.0)), // shifted, disagree -> collision
            pp("N", "H", 90.0, wall_gap(pn, ph, 19.0, 19.0, 90.0)),     // unshifted genuine collision
            pp("H", "N", 600.5, wall_gap(ph, pn, 19.0, 19.0, 600.5)),   // unshifted clean
        ]
    };

    let mut noop_glyphs = base_glyphs();
    let noop_pairs = base_pairs();
    ink_containment::apply(&mut noop_glyphs, &profiles, &noop_pairs, &ink_containment::FloorEvidence { font_median_pair_target: None });
    let noop_kern = generate_residual_kern_jobs(&solution(noop_glyphs, noop_pairs, vec![]), &profiles, &geo(), 1);

    let mut v3_glyphs = base_glyphs();
    let mut v3_pairs = base_pairs();
    let containment = ink_containment::apply(&mut v3_glyphs, &profiles, &v3_pairs, &ink_containment::FloorEvidence { font_median_pair_target: None });
    let compensation = ink_containment::compensate_pair_origins(&mut v3_pairs, &mut [], &containment.adjustments);
    let shifted: std::collections::BTreeSet<(String, String)> = v3_pairs
        .iter()
        .filter(|p| p.compensated)
        .map(|p| (p.left.clone(), p.right.clone()))
        .collect();
    let v3_kern = generate_residual_kern_jobs(&solution(v3_glyphs, v3_pairs, vec![]), &profiles, &geo(), 1);

    let holds_of = |k: &GeneratedKern| -> std::collections::BTreeMap<(String, String), String> {
        k.overlap_holds.iter().map(|h| ((h.left.clone(), h.right.clone()), h.note.clone())).collect()
    };
    let noop_holds = holds_of(&noop_kern);
    let v3_holds = holds_of(&v3_kern);
    assert_eq!(noop_holds.len(), 5, "noop premise: I->H, H->I, N->I, M->I disagree with the guard; N->H collides");
    let all_keys: std::collections::BTreeSet<(String, String)> =
        noop_holds.keys().chain(v3_holds.keys()).cloned().collect();

    let mut transitions_disagree_to_collision = 0usize;
    let mut categorized = 0usize;
    for key in &all_keys {
        categorized += 1;
        let (n, v) = (noop_holds.get(key), v3_holds.get(key));
        if !shifted.contains(key) {
            assert_eq!(n, v, "{key:?}: unshifted pair keeps byte-identical hold status and reason");
            continue;
        }
        let Some(v_note) = v else { continue }; // shifted pair fixed to ready: the repair, allowed
        let v_type = reason_type(v_note);
        if v_type == "containment_compensation_negative_origin" {
            continue; // whitelist (b): anything -> typed negative-origin hold
        }
        if let Some(n_note) = n {
            if reason_type(n_note) == v_type {
                continue; // same reason type; embedded parameters may move with the origin
            }
            if reason_type(n_note) == "solver wall_gap"
                && n_note.contains("disagree beyond fp tolerance")
                && v_type == "collision at exact solver placement"
            {
                transitions_disagree_to_collision += 1; // whitelist (c)
                continue;
            }
        }
        panic!("{key:?}: reason transition {:?} -> {:?} outside the whitelist", n.map(|s| reason_type(s.as_str())), v_type);
    }
    assert_eq!(categorized, all_keys.len(), "every differing pair categorized");
    assert_eq!(transitions_disagree_to_collision, 1, "M->I: disagree in noop, collision at the compensated placement");
    assert_eq!(v3_holds.len(), 2, "transition collision + untouched collision (N->I ships under the class rule)");
    assert_eq!(compensation.negative_origin_pairs.len(), 1);

    // I1 bound on the same runs.
    assert!(v3_kern.receipt.overlap_held <= noop_kern.receipt.overlap_held + compensation.negative_origin_pairs.len());
}
