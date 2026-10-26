//! Stage-4 exact measurement authority: the SAME pair, placement and solver wall_gap measured on the sampled profile rows (stage 3) and on
//! the exact slab rows (stage 4). A spike narrower in y than the scan row pitch sits between two sampled rows: the sampled guard ships the
//! pair, the exact guard holds it. With `exact = None` the path is the sampled one, unchanged. Fixture geometry is synthetic.
use kni_metrics::exact_rows::ExactSlabs;
use kni_metrics::generated_outline_kern::{generate_residual_kern_jobs, generate_residual_kern_jobs_exact, ExactMap, ExportGeometry, ProfileFrame};
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, OutlineProfile, ScanPolicy, MERGE_GUARD_UNITS};
use kni_metrics::self_anchored_spacing::{GlyphSpacing, PairPosition, SpaceStatus, SpacingSolution};

fn gs(id: &str, lsb: f64, rsb: f64, advance: f64) -> GlyphSpacing {
    GlyphSpacing { glyph_id: id.into(), lsb, rsb, advance }
}
fn pp(left: &str, right: &str, origin_distance: f64, wall_gap: f64) -> PairPosition {
    PairPosition { left: left.into(), right: right.into(), origin_distance, wall_gap, optical_cost: 1.0, compensated: false, pair_target: None }
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


fn geo() -> ExportGeometry {
    ExportGeometry { profile_frame: ProfileFrame::RawGenerated, upm: 1000, overlap_tolerance_units: 0.0, drop_zero_residual: false, row_align_tolerance_units: 1.0 }
}
fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
    vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
}
fn prof(id: &str, rings: &[Vec<[f64; 2]>]) -> OutlineProfile {
    profile_outline(
        &OutlineInput { glyph_id: id.into(), source_pin: "t".into(), upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0, rings: rings.to_vec() },
        ScanPolicy { row_step: 10.0, max_rows: 100000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) },
    )
    .unwrap()
}

/// left block [0,20] x [0,40]; right = bar [40,60] with a hairline spike (y 11.5..13.5, between sampled midpoints 5 and 15) reaching x=15.
fn fixture() -> (Vec<[f64; 2]>, Vec<Vec<[f64; 2]>>, Vec<Vec<[f64; 2]>>) {
    let block = rect(0.0, 0.0, 20.0, 40.0);
    let bar = vec![[40.0, 0.0], [60.0, 0.0], [60.0, 40.0], [40.0, 40.0], [40.0, 13.5], [15.0, 12.5], [40.0, 11.5]];
    (block.clone(), vec![block], vec![bar])
}

fn run(exact: bool, origin: f64) -> kni_metrics::generated_outline_kern::GeneratedKern {
    let (_, l, r) = fixture();
    let (pl, pr) = (prof("L", &l), prof("R", &r));
    let sampled_gap = 20.0 + 0.0; // sampled rows see block [0,20] vs bar [40,60] at origin 0: gap 20
    let _ = sampled_gap;
    let sol = solution(vec![gs("L", 0.0, 0.0, 60.0), gs("R", 0.0, 0.0, 60.0)], vec![pp("L", "R", origin, origin + 40.0 - 20.0)], vec![]);
    if exact {
        let mut m: ExactMap = Default::default();
        m.insert("L".into(), ExactSlabs::from_rings(&l).unwrap());
        m.insert("R".into(), ExactSlabs::from_rings(&r).unwrap());
        generate_residual_kern_jobs_exact(&sol, &[pl, pr], Some(&m), &geo(), 1)
    } else {
        generate_residual_kern_jobs(&sol, &[pl, pr], &geo(), 1)
    }
}

#[test]
fn sampled_stage_ships_the_spike_pair_and_the_exact_stage_holds_it() {
    // origin 0: spike tip at x=15 lies inside the block (ink to 20): a real overlap of 5; the sampled wall_gap is 20 (bar face 40 vs block face 20)
    let s = run(false, 0.0);
    assert_eq!(s.receipt.ready + s.receipt.fallback_ready, 1, "sampled rows miss the spike: {:?}", s.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    // am. 47: the exact stage no longer holds this pair; the exact origin collision is repaired by the existing lattice walk and the
    // shipped integer is verified exact-clear (gap >= 0, no hit). It is a typed lattice-resolved shipment, not an unverified one.
    let e = run(true, 0.0);
    assert_eq!(e.receipt.overlap_held, 0, "{:?}", e.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(e.lattice_resolved.len(), 1);
    let l = &e.lattice_resolved[0];
    assert!(l.gap_at_origin < 0.0 && l.gap_at_shipped >= 0.0 && l.d_shipped as f64 > l.solver_origin && !l.below_epsilon);
    let p = e.ready.iter().chain(e.fallback_ready.iter()).chain(e.dropped_zero.iter()).next().expect("shipped");
    assert!(!p.ink_intersects && p.measured_gap_at_export.unwrap() >= 0.0 && p.note.contains("EXACT_ORIGIN_COLLISION_RESOLVED_ON_LATTICE"), "{}", p.note);
}

#[test]
fn with_no_spike_the_exact_and_sampled_stages_agree_exactly() {
    let block = vec![rect(0.0, 0.0, 20.0, 40.0)];
    let bar = vec![rect(40.0, 0.0, 60.0, 40.0)];
    let sol = solution(vec![gs("L", 0.0, 0.0, 60.0), gs("R", 0.0, 0.0, 60.0)], vec![pp("L", "R", 0.0, 20.0)], vec![]);
    let (pl, pr) = (prof("L", &block), prof("R", &bar));
    let mut m: ExactMap = Default::default();
    m.insert("L".into(), ExactSlabs::from_rings(&block).unwrap());
    m.insert("R".into(), ExactSlabs::from_rings(&bar).unwrap());
    let a = generate_residual_kern_jobs(&sol, &[pl.clone(), pr.clone()], &geo(), 1);
    let b = generate_residual_kern_jobs_exact(&sol, &[pl, pr], Some(&m), &geo(), 1);
    let key = |k: &kni_metrics::generated_outline_kern::GeneratedKern| k.ready.iter().map(|p| (p.export_value, p.export_distance, p.measured_gap_at_origin.map(f64::to_bits), p.measured_gap_at_export.map(f64::to_bits))).collect::<Vec<_>>();
    assert_eq!(key(&a), key(&b));
    assert_eq!(a.receipt.ready, 1);
}

#[test]
fn a_pair_whose_glyph_has_no_exact_geometry_is_refused_not_measured_on_the_sampled_model() {
    let (_, l, r) = fixture();
    let (pl, pr) = (prof("L", &l), prof("R", &r));
    let sol = solution(vec![gs("L", 0.0, 0.0, 60.0), gs("R", 0.0, 0.0, 60.0)], vec![pp("L", "R", 0.0, 20.0)], vec![]);
    let mut m: ExactMap = Default::default();
    m.insert("L".into(), ExactSlabs::from_rings(&l).unwrap());
    let k = generate_residual_kern_jobs_exact(&sol, &[pl, pr], Some(&m), &geo(), 1);
    assert_eq!(k.receipt.rejected, 1);
    assert!(k.rejected[0].note.contains("exact ring geometry unavailable"), "{}", k.rejected[0].note);
}

/// Scissor at kern level: A = [0,10], B runs [20,30] -> [-30,-20] inside one vertex slab. Sampled rows (10 unit pitch, midpoints 5) and
/// vertex-limit rows see B ahead of A (or wholly behind); only the crossing cuts expose the pass-through. The pair must hold, never ship.
#[test]
fn scissor_pair_is_held_by_the_exact_stage() {
    let a = vec![rect(0.0, 0.0, 10.0, 10.0)];
    let b = vec![vec![[20.0, 0.0], [30.0, 0.0], [-20.0, 10.0], [-30.0, 10.0]]];
    let sol = solution(vec![gs("A", 0.0, 0.0, 40.0), gs("B", 0.0, 0.0, 40.0)], vec![pp("A", "B", 0.0, 10.0)], vec![]);
    let (pa, pb) = (prof("A", &a), prof("B", &b));
    let mut m: ExactMap = Default::default();
    m.insert("A".into(), ExactSlabs::from_rings(&a).unwrap());
    m.insert("B".into(), ExactSlabs::from_rings(&b).unwrap());
    let k = generate_residual_kern_jobs_exact(&sol, &[pa, pb], Some(&m), &geo(), 1);
    // am. 47: never ready by assumption; ships only when the existing walk reaches an integer that re-measures exact-clear.
    assert_eq!(k.receipt.overlap_held + k.receipt.rejected, 0, "{:?}", k.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(k.lattice_resolved.len(), 1);
    let l = &k.lattice_resolved[0];
    assert!(l.gap_at_origin < 0.0 && l.gap_at_shipped >= 0.0, "pass-through at origin, exact-clear at the shipped integer");
    let p = k.ready.iter().chain(k.fallback_ready.iter()).chain(k.dropped_zero.iter()).next().expect("shipped");
    assert!(!p.ink_intersects && p.measured_gap_at_export.unwrap() >= 0.0);
}
