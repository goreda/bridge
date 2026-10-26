//! Post-A2 pair frame (S3). A2 AUTO-SB rewrites glyph lsb/rsb/advance after stage 3 but the solved pairs keep their pre-A2
//! origin_distance/wall_gap; stage 4 then compares a post-A2 measurement with a pre-A2 wall_gap. `rebase_pairs_to_glyphs` re-runs
//! the SAME pair cascade on the post-A2 metrics. Fixture geometry is synthetic and every expectation derives from it.
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    diagnose_unmeasurable_pairs, rebase_pairs_to_glyphs, solve_colliding_self_pairs, solve_spacing, SpacingPolicy, SpacingSolution,
};

fn rows_uniform(n: usize, step: f64, weight: f64, ink: Vec<(f64, f64)>) -> Vec<ScanRow> {
    (0..n).map(|i| ScanRow {
        y: i as f64 * step,
        weight,
        ink: ink.iter().map(|&(left, right)| InkInterval { left, right }).collect(),
        span_lo: i as f64 * step - weight / 2.0,
        span_hi: i as f64 * step + weight / 2.0,
    }).collect()
}

fn profile(id: &str, rows: Vec<ScanRow>) -> OutlineProfile {
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

use kni_metrics::generated_outline_kern::{generate_residual_kern_jobs, ExportGeometry, ProfileFrame};

fn two_stem(id: &str, stem: f64, gap: f64) -> OutlineProfile {
    profile(id, rows_uniform(10, 10.0, 10.0, vec![(0.0, stem), (stem + gap, 2.0 * stem + gap)]))
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
    profile(id, rows)
}

fn bar(id: &str, w: f64) -> OutlineProfile { profile(id, rows_uniform(10, 10.0, 10.0, vec![(0.0, w)])) }

fn population() -> Vec<OutlineProfile> {
    vec![two_stem("n", 20.0, 46.0), two_stem("h", 20.0, 46.0), bar("l", 20.0), bar("i", 24.0), round_bowl("o", 20.0, 30.0, 20.0, 20), round_bowl("c", 20.0, 30.0, 20.0, 20)]
}
fn policy() -> SpacingPolicy { SpacingPolicy { dcap: Some(50.0), ..Default::default() } }
fn geo() -> ExportGeometry {
    ExportGeometry { profile_frame: ProfileFrame::ExportedB, upm: 1000, overlap_tolerance_units: 0.0, drop_zero_residual: false, row_align_tolerance_units: 10.0 }
}
/// A2-shaped rewrite: every glyph gets the same classless bearings; advance moves by the bearing deltas (as a2_apply_targets does).
fn a2_shift(s: &SpacingSolution) -> Vec<kni_metrics::self_anchored_spacing::GlyphSpacing> {
    s.glyphs.iter().map(|g| { let mut n = g.clone(); n.lsb = 31.25; n.rsb = 29.0; n.advance = g.advance + (31.25 - g.lsb) + (29.0 - g.rsb); n }).collect()
}

#[test]
fn rebase_on_unchanged_glyphs_reproduces_the_stage3_pairs_bit_for_bit() {
    let profs = population();
    let sol = solve_spacing(&profs, None, &policy()).unwrap();
    assert!(!sol.pairs.is_empty());
    let rb = rebase_pairs_to_glyphs(&profs, None, &policy(), 1, &sol.glyphs).unwrap();
    assert_eq!(format!("{:?}", rb.pairs), format!("{:?}", sol.pairs), "same cascade, same inputs: identical pairs");
    assert_eq!(format!("{:?}", rb.fallback_pairs), format!("{:?}", sol.fallback_pairs));
}

#[test]
fn stale_pre_a2_pairs_disagree_after_a2_and_the_rebased_pairs_do_not() {
    let profs = population();
    let mut sol = solve_spacing(&profs, None, &policy()).unwrap();
    let shifted = a2_shift(&sol);
    sol.glyphs = shifted.clone();
    // stale: post-A2 glyphs with pre-A2 pairs (the defect)
    let stale = generate_residual_kern_jobs(&sol, &profs, &geo(), 1);
    let stale_disagree = stale.overlap_holds.iter().filter(|h| h.note.contains("disagree") || h.note.contains("collision at exact solver placement")).count();
    eprintln!("PAIRS {} stale ready {} held {} notes {:?}", sol.pairs.len(), stale.receipt.ready, stale.receipt.overlap_held, stale.rejected.iter().map(|h| h.note.clone()).collect::<Vec<_>>());
    assert!(stale_disagree > 0, "the stale frame must produce frame-mix holds ({} ready, {} held)", stale.receipt.ready, stale.receipt.overlap_held);
    // rebased: pairs measured against the post-A2 bearings
    let rb = rebase_pairs_to_glyphs(&profs, None, &policy(), 1, &shifted).unwrap();
    assert!(rb.accounting_closed);
    sol.pairs = rb.pairs; sol.fallback_pairs = rb.fallback_pairs;
    let fresh = generate_residual_kern_jobs(&sol, &profs, &geo(), 1);
    eprintln!("REBASED ready {} held {} fallback {} notes {:?}", fresh.receipt.ready, fresh.receipt.overlap_held, fresh.receipt.fallback_ready, fresh.overlap_holds.iter().map(|h| h.note.clone()).collect::<Vec<_>>());
    assert!(fresh.receipt.ready > 0, "rebased pairs reach ready");
    let bad = fresh.overlap_holds.iter().filter(|h| h.note.contains("disagree")).count();
    assert_eq!(bad, 0, "no wall_gap-vs-measured disagreement once the pair frame is post-A2: {:?}", fresh.overlap_holds.iter().map(|h| &h.note).collect::<Vec<_>>());
    // the gate itself is unchanged: every pair job is still accounted for exactly once
    let r = &fresh.receipt;
    assert_eq!(r.ready + r.fallback_ready + r.rejected + r.overlap_held + r.dropped_zero, sol.pairs.len() + sol.fallback_pairs.len());
    assert!(r.overlap_held < stale.receipt.overlap_held, "rebase reduces frame-mix holds ({} vs {})", r.overlap_held, stale.receipt.overlap_held);
}

#[test]
fn rebase_with_a_missing_glyph_is_a_typed_refusal_not_a_default() {
    let profs = population();
    let sol = solve_spacing(&profs, None, &policy()).unwrap();
    let mut g = sol.glyphs.clone(); g.retain(|x| x.glyph_id != "n");
    assert!(rebase_pairs_to_glyphs(&profs, None, &policy(), 1, &g).is_err());
}

#[test]
fn only_colliding_self_pairs_get_a_kern_row_and_the_stage4_gate_clears_them() {
    let profs = population();
    let mut sol = solve_spacing(&profs, None, &policy()).unwrap();
    // stage-3 bearings: no self pair collides, so nothing is added
    let none = solve_colliding_self_pairs(&profs, None, &policy(), 1, &sol.glyphs).unwrap();
    assert!(none.solved.is_empty() && none.unresolved.is_empty() && none.colliding == 0, "non-colliding self pairs are untouched: {none:?}");
    // 'i' (ink 24 wide) gets overhanging bearings (T-like): two copies overlap by 20 (less than the 24 ink width)
    let mut g = sol.glyphs.clone();
    for x in g.iter_mut() { if x.glyph_id == "i" { x.advance += (-10.0 - x.lsb) + (-10.0 - x.rsb); x.lsb = -10.0; x.rsb = -10.0; } }
    let rep = solve_colliding_self_pairs(&profs, None, &policy(), 1, &g).unwrap();
    assert_eq!((rep.colliding, rep.solved.len(), rep.unresolved.len()), (1, 1, 0), "accounting closes: {rep:?}");
    let sp = rep.solved;
    assert_eq!(sp.len(), 1, "exactly the colliding self pair: {sp:?}");
    assert_eq!((sp[0].left.as_str(), sp[0].right.as_str()), ("i", "i"));
    assert!(sp[0].wall_gap >= 0.0, "solved placement clears the collision: wall_gap {}", sp[0].wall_gap);
    // stage 4 measures it through the unchanged gate: the self pair is ready, with a positive (spreading) kern value
    sol.glyphs = g; sol.pairs.extend(sp);
    let k = generate_residual_kern_jobs(&sol, &profs, &geo(), 1);
    let row = k.ready.iter().find(|r| r.left == "i" && r.right == "i").expect("self pair ships through the gate");
    assert!(row.export_value > 0, "residual spreads the colliding copies: {row:?}");
}

#[test]
fn unmeasurable_diag_lists_exactly_the_gate_failures_with_their_numbers() {
    // 'p' sits at y 300..400 while every other glyph is at y 0..100: disjoint vertical extents, zero shared rows.
    let mut profs = population();
    let mut hi = profile("p", rows_uniform(10, 10.0, 10.0, vec![(0.0, 20.0)]));
    for r in hi.rows.iter_mut() { r.y += 300.0; r.span_lo += 300.0; r.span_hi += 300.0; }
    hi.bounds[1] += 300.0; hi.bounds[3] += 300.0;
    profs.push(hi);
    let sol = solve_spacing(&profs, None, &policy()).unwrap();
    let d = diagnose_unmeasurable_pairs(&profs, None, &policy()).unwrap();
    assert_eq!(d.len(), sol.excluded_unmeasurable, "diag count equals the ledger count: {d:?}");
    assert!(d.iter().all(|x| x.reason == "SHARED_ROWS_BELOW_MIN" && x.shared_rows < x.min_required));
    assert!(d.iter().all(|x| x.left == "p" || x.right == "p"), "only the vertically disjoint glyph is unmeasurable");
}

#[test]
fn deep_overlap_self_pair_is_reported_unresolved_with_a_typed_reason_not_dropped() {
    let profs = population();
    let sol = solve_spacing(&profs, None, &policy()).unwrap();
    // overlap 60 > the 24 ink width: the facing-cell model has no cell, so the cascade cannot solve it
    let mut g = sol.glyphs.clone();
    for x in g.iter_mut() { if x.glyph_id == "i" { x.advance += (-30.0 - x.lsb) + (-30.0 - x.rsb); x.lsb = -30.0; x.rsb = -30.0; } }
    let rep = solve_colliding_self_pairs(&profs, None, &policy(), 1, &g).unwrap();
    assert_eq!(rep.colliding, rep.solved.len() + rep.unresolved.len(), "accounting closes: {rep:?}");
    assert_eq!(rep.colliding, 1, "{rep:?}");
    assert!(rep.solved.is_empty());
    assert_eq!(rep.unresolved[0].0, "i");
    assert!(rep.unresolved[0].1.starts_with("GATE_UNMEASURABLE_SHARED_ROWS_0_BELOW_"), "{:?}", rep.unresolved);
}
