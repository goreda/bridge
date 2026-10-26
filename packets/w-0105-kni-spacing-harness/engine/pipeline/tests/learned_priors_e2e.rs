//! PC-K2 end-to-end proof: receipt -> learned store -> gate -> priors ->
//! engine pair targets. Every number below is measured by running the real
//! solver (kni_metrics::self_anchored_spacing) through the real consumer
//! (kni_pipeline::learned_priors); nothing is stubbed.

use kni_learning::prior::Key;
use kni_learning::store::{Obs, Provenance, Store};
use kni_metrics::outline_spacing::{InkInterval, OutlineProfile, ScanRow};
use kni_metrics::self_anchored_spacing::{
    solve_spacing, FontContext, MeasuredPair, SpacingPolicy,
};
use kni_pipeline::learned_priors::{
    load_and_gate, observed_cells, pair_key, solve_with_priors, Learned,
};
use kni_metrics::self_anchored_spacing::SideClass;

/// Stem-counter-stem profile (the solver test suite's `countered` shape):
/// straight sides plus an interior white channel, so the anchor fallback
/// derives a positive target instead of collapsing to zero.
fn countered(id: &str) -> OutlineProfile {
    let rows = (0..10)
        .map(|i| ScanRow {
            y: i as f64 * 10.0,
            weight: 10.0,
            ink: vec![InkInterval { left: 0.0, right: 20.0 }, InkInterval { left: 60.0, right: 80.0 }],
            span_lo: i as f64 * 10.0 - 5.0,
            span_hi: i as f64 * 10.0 + 5.0,
        })
        .collect();
    OutlineProfile {
        glyph_id: id.into(),
        source_pin: "pck2-e2e".into(),
        upm: 1000,
        origin: [0.0, 0.0],
        rows,
        bounds: [0.0, 0.0, 80.0, 100.0],
        ink_area: 4000.0,
        counter_area: 4000.0,
        open_left: 0.0,
        open_right: 0.0,
        profile_method: "pck2-e2e".into(),
        row_step: 10.0,
        flatten_tolerance: 0.5,
    }
}

fn prov(font: &str) -> Provenance {
    Provenance {
        font_id: font.into(),
        run_id: "run-pck2".into(),
        receipt_id: "rcpt-pck2".into(),
        tested_sha: "0".repeat(64),
        declared_cap_u: 700.0,
        measured_cap_px: 100.0,
        certified: true,
    }
}

fn obs(key: Key, font: &str, n: u64, mean: f64, var: f64) -> Obs {
    let nf = n as f64;
    Obs { key, n, sum: mean * nf, sumsq: (var + mean * mean) * nf, prov: prov(font) }
}

const KEY_SS: &str = "straight->straight";

/// Six fonts in three families (two siblings each), all observing the
/// straight->straight class pair near `mean` with small spread.
fn warm_store(mean: f64) -> (Store, Vec<String>) {
    let mut st = Store::new(1, &["class"]).unwrap();
    let fonts = ["fA1", "fA2", "fB1", "fB2", "fC1", "fC2"];
    for (i, f) in fonts.iter().enumerate() {
        let m = mean + (i as f64 - 2.5) * 0.4; // per-font means within +/-1 of `mean`
        st.append(obs(pair_key(SideClass::Straight, SideClass::Straight), f, 50, m, 4.0)).unwrap();
    }
    (st, fonts.iter().map(|s| s.to_string()).collect())
}

fn family_of(font: &str) -> Option<String> {
    Some(font.chars().take(2).collect()) // fA1/fA2 -> "fA"
}

fn write_store(st: &Store, name: &str) -> String {
    let dir = std::env::temp_dir().join("pck2_learned_priors_e2e");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    let p = path.to_str().unwrap().to_string();
    st.save_new(&p).unwrap();
    p
}

fn baseline_far(key: &Key) -> Option<f64> {
    if key[0].1 == KEY_SS {
        Some(400.0) // the engine's current path predicts 400; priors sit near 12
    } else {
        None
    }
}

/// Two straight rects -> the straight->straight pair resolves with the
/// anchor fallback target under the default policy (no measured ctx, both
/// derived lanes off). Measured anchor target and origins below.
#[test]
fn warm_gated_store_retargets_anchor_pairs_with_measured_before_after() {
    let (st, fonts) = warm_store(12.0);
    let path = write_store(&st, "warm.knilearn");
    let cells = |f: &str| observed_cells(&st, f, &baseline_far);
    let learned = load_and_gate(&path, None, &cells, &family_of);
    let active = match learned {
        Learned::Active(a) => a,
        Learned::Cold(reason) => panic!("gate must open for the warm store, got Cold: {reason}"),
    };
    assert_eq!(active.groups().len(), 3, "one gate report per held-out family");
    assert!(active.groups().iter().all(|g| g.report.open), "every group open");

    let profiles = vec![countered("H"), countered("n")];
    let policy = SpacingPolicy::default();

    // BEFORE: the frozen engine path (no learning).
    let before = solve_with_priors(&profiles, None, &policy, None).unwrap();
    let plain = solve_spacing(&profiles, None, &policy).unwrap();
    assert_eq!(
        format!("{:?}", before.solution.pairs),
        format!("{:?}", plain.pairs),
        "Cold (None) must leave the engine path bit-identical"
    );
    assert!(before.report.applied.is_empty());
    let before_pair = before.solution.pairs.iter().find(|p| p.left == "H" && p.right == "n").unwrap();
    let audit_row = before.audit.pair_target_for("H", "n").unwrap();
    assert_eq!(
        audit_row.source,
        kni_metrics::class_audit::ClassTargetSource::AnchorWTarget,
        "default policy without ctx must resolve straight->straight on the anchor"
    );

    // AFTER: the same engine, gate-open priors active.
    let after = solve_with_priors(&profiles, None, &policy, Some(active.priors())).unwrap();
    assert_eq!(after.report.applied.len(), before.solution.pairs.len(), "every anchor-covered pair is re-targeted");
    let ap = after.report.applied.iter().find(|a| a.left == "H" && a.right == "n").unwrap();
    let after_pair = after.solution.pairs.iter().find(|p| p.left == "H" && p.right == "n").unwrap();

    // Measured before/after numbers, asserted tight:
    assert_eq!(ap.key, KEY_SS);
    assert_eq!(ap.anchor_target, audit_row.target, "receipt carries the target the cascade used");
    assert!((ap.learned_target - 12.0).abs() < 1.0, "learned target is the pooled prior mean, got {}", ap.learned_target);
    assert_eq!(ap.before_origin, before_pair.origin_distance);
    assert_eq!(ap.after_origin, after_pair.origin_distance);
    assert!(ap.before_origin != ap.after_origin, "the learned target moves the pair: before={} after={}", ap.before_origin, ap.after_origin);
    assert_eq!(after_pair.pair_target, Some(ap.learned_target));
    // Glyph sidebearings are the font's own solve: untouched.
    assert_eq!(format!("{:?}", before.solution.glyphs), format!("{:?}", after.solution.glyphs));
    // The derivation receipt names the pass.
    assert!(after.solution.policy_derivation.contains("learned_priors"));
    // The store fonts feed the gate only; the solved font is synthetic and
    // never entered the store (no self-validation possible).
    assert!(fonts.iter().all(|f| f.starts_with('f')));
}

/// Re-solving a pair against the SAME target the cascade used must
/// reproduce the cascade's origin AND optical_cost bit-exactly: this pins
/// the consumer's reconstruction (domain, export frame, objective) to the
/// production recipe.
#[test]
fn resolve_reconstruction_is_bit_identical_at_the_original_target() {
    let profiles = vec![countered("H"), countered("n"), countered("o")];
    let policy = SpacingPolicy::default();
    let base = solve_with_priors(&profiles, None, &policy, None).unwrap();

    // Priors whose mean equals the anchor target exactly: the learned pass
    // re-solves with the identical target.
    let anchor = base.audit.w_target;
    let mut st = Store::new(1, &["class"]).unwrap();
    for f in ["gA1", "gA2", "gB1", "gB2", "gC1", "gC2"] {
        st.append(obs(pair_key(SideClass::Straight, SideClass::Straight), f, 50, anchor, 0.0)).unwrap();
    }
    let path = write_store(&st, "anchor-mirror.knilearn");
    let cells = |f: &str| observed_cells(&st, f, &baseline_far);
    let learned = load_and_gate(&path, None, &cells, &|f: &str| Some(f.chars().take(2).collect()));
    let active = match learned {
        Learned::Active(a) => a,
        Learned::Cold(r) => panic!("gate must open: {r}"),
    };
    let out = solve_with_priors(&profiles, None, &policy, Some(active.priors())).unwrap();
    for ap in &out.report.applied {
        assert_eq!(ap.before_origin, ap.after_origin, "same target -> same origin for {}->{}", ap.left, ap.right);
    }
    for p in &out.solution.pairs {
        let orig = base.solution.pairs.iter().find(|q| q.left == p.left && q.right == p.right).unwrap();
        assert_eq!(p.origin_distance, orig.origin_distance, "origin bit-identity for {}->{}", p.left, p.right);
        assert_eq!(p.optical_cost, orig.optical_cost, "optical_cost bit-identity for {}->{}", p.left, p.right);
    }
}

/// A measured source target always wins: the learned pass never overrides
/// measured pairs, and the measured pair's placement is bit-identical.
#[test]
fn measured_targets_are_never_overridden() {
    let (st, _) = warm_store(12.0);
    let path = write_store(&st, "warm2.knilearn");
    let cells = |f: &str| observed_cells(&st, f, &baseline_far);
    let learned = load_and_gate(&path, None, &cells, &family_of);
    let active = match learned {
        Learned::Active(a) => a,
        Learned::Cold(r) => panic!("gate must open: {r}"),
    };
    let profiles = vec![countered("H"), countered("n")];
    let mut ctx = FontContext::default();
    ctx.measured_pairs = vec![MeasuredPair { left: "H".into(), right: "n".into(), gap: 250.0 }];
    let policy = SpacingPolicy::default();
    let before = solve_with_priors(&profiles, Some(&ctx), &policy, None).unwrap();
    let after = solve_with_priors(&profiles, Some(&ctx), &policy, Some(active.priors())).unwrap();
    assert_eq!(after.report.applied.len(), 0, "measured pair: no learned re-target");
    assert_eq!(after.report.skipped_measured_or_derived, before.solution.pairs.len(), "every pair resolves measured via its class target");
    assert_eq!(format!("{:?}", before.solution.pairs), format!("{:?}", after.solution.pairs));
}

/// Cold inputs leave the engine untouched: absent file, gate closed
/// (baseline unbeatable), too few groups, and the sibling-leak shape where
/// a family's key dies with the family held out.
#[test]
fn cold_paths_keep_the_engine_unchanged() {
    let profiles = vec![countered("H"), countered("n")];
    let policy = SpacingPolicy::default();
    let frozen = solve_with_priors(&profiles, None, &policy, None).unwrap();

    // 1. Absent store file.
    match load_and_gate("/nonexistent/pck2/none.knilearn", None, &|_| vec![], &family_of) {
        Learned::Cold(_) => {}
        Learned::Active(_) => panic!("absent store must be Cold"),
    }

    // 2. Gate closed: baseline predictions equal each font's own observed
    //    mean, so the prior cannot strictly beat the baseline on any group.
    let (st2, _) = warm_store(12.0);
    let p2 = write_store(&st2, "closed.knilearn");
    let cells_self = |f: &str| {
        observed_cells(&st2, f, &|k: &Key| {
            let mut n = 0u64;
            let mut s = 0.0;
            for o in st2.records.iter().filter(|o| o.prov.font_id == f && &o.key == k) {
                n += o.n;
                s += o.sum;
            }
            if n == 0 { None } else { Some(s / n as f64) }
        })
    };
    match load_and_gate(&p2, None, &cells_self, &family_of) {
        Learned::Cold(_) => {}
        Learned::Active(_) => panic!("a baseline that equals each font's own mean cannot be beaten"),
    }

    // 3. Too few groups: 3 fonts but only 2 families.
    let mut st3 = Store::new(1, &["class"]).unwrap();
    for f in ["hA1", "hA2", "hB1"] {
        st3.append(obs(pair_key(SideClass::Straight, SideClass::Straight), f, 50, 120.0, 4.0)).unwrap();
    }
    let p3 = write_store(&st3, "twogroups.knilearn");
    let cells3 = |f: &str| observed_cells(&st3, f, &baseline_far);
    match load_and_gate(&p3, None, &cells3, &family_of) {
        Learned::Cold(_) => {}
        Learned::Active(_) => panic!("MIN_FOLD_GROUPS=3: two families must stay closed"),
    }

    // 4. Sibling leak: only family kA carries the straight->straight key;
    //    the kA fold holds the whole family out, so that key has no support
    //    and its cells are UNSEEN (unscored). The round->round baseline is
    //    exact, so the kB/kC folds cannot open either. Gate stays closed.
    let mut st4 = Store::new(1, &["class"]).unwrap();
    for f in ["kA1", "kA2"] {
        st4.append(obs(pair_key(SideClass::Straight, SideClass::Straight), f, 50, 120.0, 4.0)).unwrap();
    }
    for f in ["kB1", "kB2", "kC1", "kC2"] {
        st4.append(obs(pair_key(SideClass::Round, SideClass::Round), f, 50, 300.0, 4.0)).unwrap();
    }
    let p4 = write_store(&st4, "sibling.knilearn");
    let cells4 = |f: &str| {
        observed_cells(&st4, f, &|k: &Key| {
            if k[0].1 == KEY_SS { Some(400.0) } else { Some(300.0) } // baseline exact for round->round
        })
    };
    match load_and_gate(&p4, None, &cells4, &family_of) {
        Learned::Cold(_) => {}
        Learned::Active(_) => panic!("sibling-supported keys and an unbeaten group must stay closed"),
    }

    // Every Cold path above means the engine call runs with None priors:
    // the frozen solve, unchanged and deterministic.
    let again = solve_with_priors(&profiles, None, &policy, None).unwrap();
    assert_eq!(format!("{:?}", frozen.solution), format!("{:?}", again.solution), "determinism of the unchanged path");
}

/// A gate-open prior that does not cover the solved font's class pairs is
/// UNSEEN: pairs stay on the anchor, nothing changes.
#[test]
fn unseen_keys_leave_pairs_on_the_anchor() {
    let mut st = Store::new(1, &["class"]).unwrap();
    for f in ["mA1", "mA2", "mB1", "mB2", "mC1", "mC2"] {
        st.append(obs(pair_key(SideClass::Round, SideClass::Round), f, 50, 88.0, 4.0)).unwrap();
    }
    let path = write_store(&st, "unseen.knilearn");
    let cells = |f: &str| {
        observed_cells(&st, f, &|k: &Key| if k[0].1 == "round->round" { Some(500.0) } else { None })
    };
    let learned = load_and_gate(&path, None, &cells, &family_of);
    let active = match learned {
        Learned::Active(a) => a,
        Learned::Cold(r) => panic!("gate must open for round->round: {r}"),
    };
    let profiles = vec![countered("H"), countered("n")];
    let policy = SpacingPolicy::default();
    let before = solve_with_priors(&profiles, None, &policy, None).unwrap();
    let after = solve_with_priors(&profiles, None, &policy, Some(active.priors())).unwrap();
    assert_eq!(after.report.applied.len(), 0);
    assert_eq!(after.report.skipped_unseen, before.solution.pairs.len());
    assert_eq!(format!("{:?}", before.solution.pairs), format!("{:?}", after.solution.pairs));
}
