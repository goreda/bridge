//! Slice 5: stage-3 below-epsilon drops whose NATURAL placement collides exactly become stage-4 eligible (additive); the rest keep the
//! epsilon drop, typed and without a row. Fixture geometry is synthetic; every expectation derives from it.
use std::collections::BTreeSet;
use kni_metrics::outline_spacing::{InkInterval, ScanRow};
use kni_metrics::self_anchored_spacing::{solve_below_epsilon_candidates, solve_spacing, SpacingPolicy, PairLedgerReason};
use kni_metrics::exact_rows::ExactSlabs;
use kni_metrics::generated_outline_kern::{generate_residual_kern_jobs_below_eps, generate_residual_kern_jobs_exact, BELOW_EPSILON_RESIDUAL_COLLIDING, ExactMap, ExportGeometry, ProfileFrame};
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


fn world() -> (Vec<OutlineProfile>, ExactMap) {
    let r = vec![rect(0.0, 0.0, 20.0, 40.0)];
    let mut m: ExactMap = Default::default();
    let mut ps = Vec::new();
    for id in ["A", "B", "C", "D"] {
        ps.push(prof(id, &r));
        m.insert(id.into(), ExactSlabs::from_rings(&r).unwrap());
    }
    (ps, m)
}
/// Left glyphs differ only in advance: A=15 (natural placement of B overlaps A by 5), C=50 (gap 30), D=20 (exact contact, gap 0).
fn sol3() -> SpacingSolution {
    solution(
        vec![gs("A", 0.0, 0.0, 15.0), gs("B", 0.0, 0.0, 20.0), gs("C", 0.0, 0.0, 50.0), gs("D", 0.0, 0.0, 20.0)],
        vec![pp("A", "B", 15.2, 0.0), pp("C", "B", 50.2, 30.0), pp("D", "B", 20.2, 0.0)],
        vec![],
    )
}
fn keys() -> BTreeSet<(String, String)> {
    [("A", "B"), ("C", "B"), ("D", "B")].iter().map(|(l, r)| (l.to_string(), r.to_string())).collect()
}

#[test]
fn below_epsilon_candidates_keep_the_drop_unless_the_natural_placement_collides_exactly() {
    let (ps, m) = world();
    let (k, be) = generate_residual_kern_jobs_below_eps(&sol3(), &ps, Some(&m), &keys(), &geo(), 1);
    assert_eq!(be.candidates, 3);
    let dropped: Vec<(&str, &str, f64)> = be.dropped_no_exact_collision.iter().map(|(l, r, g)| (l.as_str(), r.as_str(), *g)).collect();
    assert_eq!(dropped, vec![("C", "B", 30.0), ("D", "B", 0.0)], "clear (gap 30) and exact contact (gap 0 is not a collision) keep the epsilon drop");
    // am. 47: the colliding candidate walks the existing lattice from d0 = max(15, ceil(15.2)) = 16 to the first exact-clear integer 20
    assert_eq!(k.receipt.ready + k.receipt.fallback_ready, 1);
    assert!(k.overlap_holds.is_empty(), "{:?}", k.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(be.resolved_on_lattice.len(), 1);
    let c = &be.resolved_on_lattice[0];
    assert_eq!((c.left.as_str(), c.right.as_str(), c.d0, c.d_shipped, c.walk_steps), ("A", "B", 16, 20, 4));
    assert!(c.below_epsilon && c.gap_at_origin < 0.0 && c.gap_at_shipped == 0.0 && c.contact_class() == "TOUCH_GAP_0");
    assert!(be.partition_closed() && be.held == 0);
}

#[test]
fn an_empty_candidate_set_is_the_unchanged_stage_four_bit_for_bit() {
    let (ps, m) = world();
    let (a, be) = generate_residual_kern_jobs_below_eps(&sol3(), &ps, Some(&m), &BTreeSet::new(), &geo(), 1);
    let b = generate_residual_kern_jobs_exact(&sol3(), &ps, Some(&m), &geo(), 1);
    assert_eq!(format!("{a:?}"), format!("{b:?}"));
    assert!(be.dropped_no_exact_collision.is_empty() && be.candidates == 0);
    // untouched paths: the two non-colliding pairs ship exactly as before when they are not candidates
    assert_eq!(a.receipt.ready, 3, "C->B, D->B and (am. 47) the lattice-resolved A->B ship when they are ordinary pairs");
    assert_eq!(a.lattice_resolved.len(), 1);
    assert!(!a.lattice_resolved[0].below_epsilon && a.lattice_resolved[0].d_shipped == 20);
    // ... and a candidate set that names only the colliding pair leaves the other two byte-identical
    let only_a: BTreeSet<(String, String)> = [("A".to_string(), "B".to_string())].into_iter().collect();
    let (c, _) = generate_residual_kern_jobs_below_eps(&sol3(), &ps, Some(&m), &only_a, &geo(), 1);
    let untouched = |g: &kni_metrics::generated_outline_kern::GeneratedKern| format!("{:?}", g.ready.iter().filter(|e| e.left != "A").collect::<Vec<_>>());
    assert_eq!(untouched(&c), untouched(&a));
}

// ---- solver side (profile-row fixtures from the post-A2 rebase tests) ----
fn rows_uniform(n: usize, step: f64, weight: f64, ink: Vec<(f64, f64)>) -> Vec<ScanRow> {
    (0..n).map(|i| ScanRow {
        y: i as f64 * step,
        weight,
        ink: ink.iter().map(|&(left, right)| InkInterval { left, right }).collect(),
        span_lo: i as f64 * step - weight / 2.0,
        span_hi: i as f64 * step + weight / 2.0,
    }).collect()
}

fn profile2(id: &str, rows: Vec<ScanRow>) -> OutlineProfile {
    let (mut x0, mut y0) = (f64::INFINITY, f64::INFINITY);
    let (mut x1, mut y1) = (f64::NEG_INFINITY, f64::NEG_INFINITY);
    for r in &rows {
        y0 = y0.min(r.y); y1 = y1.max(r.y);
        for iv in &r.ink { x0 = x0.min(iv.left); x1 = x1.max(iv.right); }
    }
    let ink_area: f64 = rows.iter().map(|r| r.weight * r.ink.iter().map(|i| i.right - i.left).sum::<f64>()).sum();
    OutlineProfile {
        glyph_id: id.into(),
        source_pin: "lane-b-test".into(),
        upm: 1000,
        origin: [0.0, 0.0],
        rows,
        bounds: [x0, y0, x1, y1],
        ink_area,
        counter_area: 0.0,
        open_left: 0.0,
        open_right: 0.0,
        profile_method: "test-fixture".into(),
        row_step: 10.0,
        flatten_tolerance: 0.5,
    }
}

fn two_stem(id: &str, stem: f64, gap: f64) -> OutlineProfile {
    profile2(id, rows_uniform(10, 10.0, 10.0, vec![(0.0, stem), (stem + gap, 2.0 * stem + gap)]))
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
    profile2(id, rows)
}

fn bar(id: &str, w: f64) -> OutlineProfile { profile2(id, rows_uniform(10, 10.0, 10.0, vec![(0.0, w)])) }

fn population() -> Vec<OutlineProfile> {
    vec![two_stem("n", 20.0, 46.0), two_stem("h", 20.0, 46.0), bar("l", 20.0), bar("i", 24.0), round_bowl("o", 20.0, 30.0, 20.0, 20), round_bowl("c", 20.0, 30.0, 20.0, 20)]
}
fn policy() -> SpacingPolicy { SpacingPolicy { dcap: Some(50.0), ..Default::default() } }
/// A2-shaped rewrite: every glyph gets the same classless bearings; advance moves by the bearing deltas (as a2_apply_targets does).

#[test]
fn candidate_run_returns_exactly_the_stage3_below_epsilon_directions_and_changes_nothing_else() {
    let profs = population();
    let sol = solve_spacing(&profs, None, &policy()).unwrap();
    let cands = solve_below_epsilon_candidates(&profs, None, &policy(), 1, &sol.glyphs).unwrap();
    let ledger: BTreeSet<(String, String)> = sol.pair_ledger.iter()
        .filter(|r| r.reason == PairLedgerReason::ExcludedBelowEpsilon).map(|r| (r.left.clone(), r.right.clone())).collect();
    let got: BTreeSet<(String, String)> = cands.iter().map(|p| (p.left.clone(), p.right.clone())).collect();
    eprintln!("BELOW-EPS ledger {} candidates {}", ledger.len(), cands.len());
    assert_eq!(got, ledger, "same cascade, same bearings: the candidates are the stage-3 epsilon drops");
    assert_eq!(cands.len(), sol.excluded_below_epsilon);
    assert!(cands.iter().all(|p| p.left != p.right && p.origin_distance.is_finite()));
    let sol2 = solve_spacing(&profs, None, &policy()).unwrap();
    assert_eq!(format!("{:?}", sol.pairs), format!("{:?}", sol2.pairs), "stage-3 output is not touched by the candidate run");
}

#[test]
fn colliding_self_pair_below_epsilon_is_typed_and_reaches_stage4_not_a_cascade_hold() {
    use kni_metrics::self_anchored_spacing::solve_colliding_self_pairs;
    let profs = population();
    // same population and overhanging 'i' as the self-pair test; a wide epsilon makes the solved residual (about 46) a stage-3 noise drop
    let wide = SpacingPolicy { dcap: Some(50.0), sample_resolution: 400.0, ..Default::default() };
    let sol = solve_spacing(&profs, None, &policy()).unwrap();
    let mut g = sol.glyphs.clone();
    for x in g.iter_mut() { if x.glyph_id == "i" { x.advance += (-10.0 - x.lsb) + (-10.0 - x.rsb); x.lsb = -10.0; x.rsb = -10.0; } }
    let normal = solve_colliding_self_pairs(&profs, None, &policy(), 1, &g).unwrap();
    assert_eq!((normal.colliding, normal.solved.len(), normal.below_epsilon.len(), normal.unresolved.len()), (1, 1, 0, 0));
    let rep = solve_colliding_self_pairs(&profs, None, &wide, 1, &g).unwrap();
    assert_eq!((rep.colliding, rep.solved.len(), rep.below_epsilon.len(), rep.unresolved.len()), (1, 0, 1, 0),
        "typed BELOW_EPSILON_RESIDUAL, not CASCADE_HOLD_OR_NO_ACCEPTED_CANDIDATE: {rep:?}");
    assert_eq!((rep.below_epsilon[0].left.as_str(), rep.below_epsilon[0].right.as_str()), ("i", "i"));
    // stage 4: the pair is a candidate; its natural placement collides exactly (two 24-wide copies overlapping by 20), so it is eligible
    // and, never ready by assumption, ends as a typed hold or a gate-cleared row, accounted exactly once.
    let mut s2 = sol.clone();
    s2.glyphs = g;
    let key = (rep.below_epsilon[0].left.clone(), rep.below_epsilon[0].right.clone());
    s2.pairs.extend(rep.below_epsilon);
    let set: BTreeSet<(String, String)> = [key].into_iter().collect();
    let (k, be) = kni_metrics::generated_outline_kern::generate_residual_kern_jobs_below_eps(&s2, &profs, None, &set, &geo(), 1);
    assert_eq!(be.candidates, 1);
    assert!(be.dropped_no_exact_collision.is_empty(), "natural placement collides: eligible, not dropped");
    let tagged = k.ready.iter().chain(k.overlap_holds.iter()).filter(|r| r.note.contains(BELOW_EPSILON_RESIDUAL_COLLIDING)).count();
    assert_eq!(tagged, 1, "{:?}", k.ready.iter().chain(k.overlap_holds.iter()).map(|r| (&r.left, &r.right, &r.note)).collect::<Vec<_>>());
}

// ---- Am. 47 unified walk: below-epsilon candidates resolve via the existing lattice walk (existing predicate, no new constant) ----

/// E: advance 19.6 (natural placement of B overlaps E by 0.4, sub-unit); lattice start d0 = max(round(19.6), ceil(19.6 - 0)) = 20 = exact contact.
/// F: advance 15 (overlap 5 -> d0 = 16 still collides by 4). G: advance 25 (clear, gap 5).
fn sol4b() -> SpacingSolution {
    solution(
        vec![gs("E", 0.0, 0.0, 19.6), gs("F", 0.0, 0.0, 15.0), gs("B", 0.0, 0.0, 20.0)],
        vec![pp("E", "B", 19.6, 0.0), pp("F", "B", 15.0, 0.0)],
        vec![],
    )
}
fn world4b() -> (Vec<OutlineProfile>, ExactMap) {
    let r = vec![rect(0.0, 0.0, 20.0, 40.0)];
    let mut m: ExactMap = Default::default();
    let mut ps = Vec::new();
    for id in ["E", "F", "B"] {
        ps.push(prof(id, &r));
        m.insert(id.into(), ExactSlabs::from_rings(&r).unwrap());
    }
    (ps, m)
}
fn cand(pairs: &[(&str, &str)]) -> BTreeSet<(String, String)> {
    pairs.iter().map(|(l, r)| (l.to_string(), r.to_string())).collect()
}

#[test]
fn candidates_walk_the_existing_lattice_typed_and_counted_once() {
    let (ps, m) = world4b();
    let (k, be) = generate_residual_kern_jobs_below_eps(&sol4b(), &ps, Some(&m), &cand(&[("E", "B"), ("F", "B")]), &geo(), 1);
    assert!(k.overlap_holds.is_empty(), "{:?}", k.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    assert_eq!(be.resolved_on_lattice.len(), 2);
    let e = be.resolved_on_lattice.iter().find(|c| c.left == "E").unwrap();
    assert_eq!((e.d0, e.d_shipped, e.walk_steps, e.export_value), (20, 20, 0, 0), "step 0 included: d0 itself is exact-clear");
    assert_eq!(e.solver_origin, 19.6);
    assert!((e.shift - 0.4).abs() < 1e-12 && e.depth_at_origin > 0.39 && e.depth_at_origin < 0.41);
    assert!(e.gap_at_origin < 0.0 && e.gap_at_d0 == 0.0 && e.gap_at_shipped == 0.0 && e.below_epsilon);
    assert_eq!(e.contact_class(), "TOUCH_GAP_0", "gap 0 is TOUCH: neither clean nor a collision");
    assert_eq!(e.target_met(), e.pair_target.map(|t| e.gap_at_shipped >= t));
    let f = be.resolved_on_lattice.iter().find(|c| c.left == "F").unwrap();
    assert_eq!((f.d0, f.d_shipped, f.walk_steps, f.export_value), (15, 20, 5, 5));
    assert_eq!(be.ready + be.fallback_ready + be.held + be.rejected + be.dropped_zero, 0, "K is counted only in K");
    assert_eq!(be.candidates, 2);
    assert!(be.partition_closed());
    for en in k.ready.iter().chain(k.fallback_ready.iter()).chain(k.dropped_zero.iter()) {
        assert!(en.note.contains("BELOW_EPSILON_RESIDUAL_RESOLVED_ON_LATTICE"), "{}", en.note);
        assert!(!en.ink_intersects && en.measured_gap_at_export.unwrap() >= 0.0, "every shipped integer is exact-clear");
    }
}

#[test]
fn ordinary_pairs_use_the_same_walk_with_ordinary_provenance_and_the_same_shipped_integers() {
    let (ps, m) = world4b();
    let (k, be) = generate_residual_kern_jobs_below_eps(&sol4b(), &ps, Some(&m), &BTreeSet::new(), &geo(), 1);
    assert!(be.resolved_on_lattice.is_empty() && be.partition_closed() && be.candidates == 0);
    assert!(k.overlap_holds.is_empty());
    assert_eq!(k.lattice_resolved.len(), 2);
    for l in &k.lattice_resolved { assert!(!l.below_epsilon && l.gap_at_shipped >= 0.0); }
    let (kc, _) = generate_residual_kern_jobs_below_eps(&sol4b(), &ps, Some(&m), &cand(&[("E", "B"), ("F", "B")]), &geo(), 1);
    let ship = |g: &kni_metrics::generated_outline_kern::GeneratedKern| g.lattice_resolved.iter().map(|l| (l.left.clone(), l.d_shipped, l.export_value)).collect::<Vec<_>>();
    assert_eq!(ship(&k), ship(&kc), "one rule: provenance changes the tag, never the placement");
    for en in &k.ready { assert!(en.note.contains("EXACT_ORIGIN_COLLISION_RESOLVED_ON_LATTICE"), "{}", en.note); }
}

#[test]
fn a_pair_whose_walk_cannot_ship_a_verified_integer_is_never_lattice_resolved() {
    // advance so negative that the shipped export_value leaves i16: no verified shipment, so no lattice-resolved class
    let (mut ps, mut m) = world4b();
    let r = vec![rect(0.0, 0.0, 20.0, 40.0)];
    m.insert("Z".into(), ExactSlabs::from_rings(&r).unwrap());
    ps.push(prof("Z", &r));
    let sol = solution(vec![gs("Z", 0.0, 0.0, -32760.0), gs("B", 0.0, 0.0, 20.0)], vec![pp("Z", "B", 15.0, 0.0)], vec![]);
    let (k, _) = generate_residual_kern_jobs_below_eps(&sol, &ps, Some(&m), &BTreeSet::new(), &geo(), 1);
    assert!(k.lattice_resolved.is_empty());
    assert_eq!(k.receipt.ready + k.receipt.fallback_ready + k.receipt.dropped_zero, 0);
}

#[test]
fn empty_candidate_set_partition_is_trivially_closed_and_empty() {
    let (ps, m) = world4b();
    let (_k, be) = generate_residual_kern_jobs_below_eps(&sol4b(), &ps, Some(&m), &BTreeSet::new(), &geo(), 1);
    assert!(be.candidates == 0 && be.resolved_on_lattice.is_empty() && be.partition_closed());
}
