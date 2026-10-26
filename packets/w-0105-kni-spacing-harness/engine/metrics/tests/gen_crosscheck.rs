//! Integration checks for the additive generation apply phase: determinism,
//! typed refusals, protected explicit zeros and cold-start equivalence.
use kni_metrics::gen;
use kni_metrics::learn::ExistingPair;

fn load_inputs() -> gen::GenerationInputs {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
    let classes = std::fs::read_to_string(format!("{dir}/classes.tsv")).unwrap();
    let targets = std::fs::read_to_string(format!("{dir}/targets.tsv")).unwrap();
    let walls = std::fs::read_to_string(format!("{dir}/walls.tsv")).unwrap();
    let existing = std::fs::read_to_string(format!("{dir}/existing.tsv")).unwrap();
    let restore = std::fs::read_to_string(format!("{dir}/restore.tsv")).unwrap();
    let (glyphs, knowledge) = gen::parse_classes(&classes).unwrap();
    gen::GenerationInputs {
        glyphs,
        knowledge,
        targets: gen::parse_targets(&targets).unwrap(),
        walls: gen::parse_walls(&walls).unwrap(),
        existing: gen::existing_from_pairs(gen::parse_pairs(&existing).unwrap()).unwrap(),
        restore: gen::parse_pairs(&restore).unwrap(),
    }
}

// No fixed-count expected-output fixture is used: the pair count is an output.
#[test]
fn output_is_deterministic_and_has_no_count_target() {
    let inp = load_inputs();
    let a = gen::generate(&inp).unwrap();
    let b = gen::generate(&inp).unwrap();
    assert_eq!(a, b, "two runs on equal inputs must be identical");
}

#[test]
fn empty_existing_is_a_typed_refusal() {
    let mut inp = load_inputs();
    inp.existing.clear();
    assert_eq!(gen::generate(&inp).unwrap_err(), gen::GenError::NoExistingKern);
}

#[test]
fn policy_range_contains_zero_and_report_counts() {
    let inp = load_inputs();
    let (out, pol, rep) = gen::generate_with_policy(&inp, None).unwrap();
    assert!(pol.clamp_lo <= 0 && 0 <= pol.clamp_hi);
    assert!(pol.noise_floor >= 1 && pol.min_cell_support >= 2);
    assert_eq!(rep.written, out.len());
    assert_eq!(rep.rejected_sign_flip, 0);
    assert!(!pol.derivation.is_empty());
}

#[test]
fn additive_guarantee_holds_over_full_existing() {
    let inp = load_inputs();
    let out = gen::generate(&inp).unwrap();
    let set = gen::build_additive_set(&inp, &out).expect("additive verification failed");
    assert_eq!(set.generated_count(), out.len());
}

#[test]
fn rounding_is_ties_to_even() {
    // Cell medians can land on .5 exactly; ties go to the even integer.
    assert_eq!(14.5f64.round_ties_even() as i32, 14);
    assert_eq!((-22.5f64).round_ties_even() as i32, -22);
    assert_eq!(13.5f64.round_ties_even() as i32, 14);
}

#[test]
fn restore_pairs_lead_and_existing_never_regenerated() {
    let inp = load_inputs();
    let out = gen::generate(&inp).unwrap();
    assert!(out.len() >= inp.restore.len());
    for (got, want) in out.iter().zip(inp.restore.iter()) {
        assert_eq!(got.tier, "T0");
        assert_eq!((&got.left, &got.right, got.kern), (&want.left, &want.right, want.kern));
    }
    for p in &out {
        assert!(!inp.existing.contains_key(&(p.left.clone(), p.right.clone())));
    }
    // every generated pair carries a sane value
    let pol = gen::derive_policy(&inp).unwrap();
    for p in &out {
        assert!(p.kern.abs() >= pol.noise_floor || p.tier == "T0");
        assert!((pol.clamp_lo..=pol.clamp_hi).contains(&p.kern) || p.tier == "T0");
        assert!(p.tier == "T0" || p.tier.starts_with("G-"));
    }
    let _ = ExistingPair { left: String::new(), right: String::new(), kern: 0 };
}

fn first_generated_pair(inp: &gen::GenerationInputs) -> (String, String) {
    let out = gen::generate(inp).unwrap();
    let p = out.iter().find(|p| p.tier != "T0").expect("a generated pair");
    (p.left.clone(), p.right.clone())
}

#[test]
fn glyph_order_does_not_change_output() {
    let inp = load_inputs();
    let want = gen::generate(&inp).unwrap();
    let mut rev = inp.clone();
    rev.glyphs.reverse();
    assert_eq!(gen::generate(&rev).unwrap(), want);
}

#[test]
fn duplicate_glyph_is_a_typed_error() {
    let mut inp = load_inputs();
    let g = inp.glyphs[0].clone();
    inp.glyphs.push(g.clone());
    assert_eq!(gen::generate(&inp).unwrap_err(), gen::GenError::DuplicateGlyph(g));
}

#[test]
fn duplicate_existing_and_restore_pairs_are_typed_errors() {
    let pair = |k| ExistingPair { left: "a".into(), right: "b".into(), kern: k };
    assert_eq!(
        gen::existing_from_pairs(vec![pair(3), pair(4)]).unwrap_err(),
        gen::GenError::DuplicateExistingPair { left: "a".into(), right: "b".into() }
    );
    let mut inp = load_inputs();
    let (l, r) = first_generated_pair(&inp);
    inp.restore = vec![
        ExistingPair { left: l.clone(), right: r.clone(), kern: 7 },
        ExistingPair { left: l.clone(), right: r.clone(), kern: 7 },
    ];
    assert_eq!(
        gen::generate(&inp).unwrap_err(),
        gen::GenError::DuplicateRestorePair { left: l, right: r }
    );
}

#[test]
fn restore_existing_conflict_is_a_typed_error() {
    let mut inp = load_inputs();
    let mut keys: Vec<_> = inp.existing.keys().cloned().collect();
    keys.sort();
    let (l, r) = keys[0].clone();
    inp.restore = vec![ExistingPair { left: l.clone(), right: r.clone(), kern: 5 }];
    assert_eq!(
        gen::generate(&inp).unwrap_err(),
        gen::GenError::RestoreExistingConflict { left: l, right: r }
    );
}

#[test]
fn non_finite_numbers_are_typed_errors() {
    let mut inp = load_inputs();
    inp.targets.global_mingap = f64::NAN;
    assert!(matches!(gen::generate(&inp).unwrap_err(), gen::GenError::NonFinite(_)));
    let mut inp = load_inputs();
    let name = inp.walls.keys().min().cloned().unwrap();
    inp.walls.get_mut(&name).unwrap().advance = f64::INFINITY;
    assert!(matches!(gen::generate(&inp).unwrap_err(), gen::GenError::NonFinite(_)));
    let mut inp = load_inputs();
    for v in inp.targets.cell_median.values_mut() {
        *v = f64::NAN;
    }
    assert!(matches!(gen::derive_policy(&inp).unwrap_err(), gen::GenError::NonFinite(_)));
}

#[test]
fn saturated_values_are_typed_errors() {
    let mut inp = load_inputs();
    inp.existing.insert(("zz_new_l".into(), "zz_new_r".into()), i32::MIN);
    assert!(matches!(gen::generate(&inp).unwrap_err(), gen::GenError::Saturated(_)));
    let mut inp = load_inputs();
    let (l, r) = first_generated_pair(&inp);
    inp.restore = vec![ExistingPair { left: l, right: r, kern: i32::MAX }];
    assert!(matches!(gen::generate(&inp).unwrap_err(), gen::GenError::Saturated(_)));
    // A target whose rounded value leaves the i32 range is refused, not clamped by `as`.
    let mut inp = load_inputs();
    inp.targets.global_mingap = -1.0e12;
    inp.targets.stratum_mingap.values_mut().for_each(|v| *v = -1.0e12);
    inp.targets.cell_median.clear();
    // The geometric gate would (correctly) close a stratum whose solve is this far
    // off; the representability check itself is exercised on the ungated policy.
    let (l, r) = first_generated_pair(&load_inputs());
    assert!(matches!(
        gen::predict_checked(&inp, &l, &r, None, &gen::KernPolicy::permissive()),
        Err(gen::GenError::Saturated(_))
    ));
}

#[test]
fn explicit_source_zero_is_protected_and_left_out_of_statistics() {
    let mut inp = load_inputs();
    let before = gen::derive_policy(&inp).unwrap();
    let (l, r) = first_generated_pair(&inp);
    inp.existing.insert((l.clone(), r.clone()), 0);
    let (out, after, rep) = gen::generate_with_policy(&inp, None).unwrap();
    assert!(!out.iter().any(|p| p.left == l && p.right == r), "an explicit zero is never regenerated");
    assert!(rep.protected_zero >= 1);
    assert_eq!(
        (before.noise_floor, before.clamp_lo, before.clamp_hi, before.min_cell_support),
        (after.noise_floor, after.clamp_lo, after.clamp_hi, after.min_cell_support),
        "zeros are excluded from the statistics"
    );
    let set = gen::build_additive_set(&inp, &out).expect("additive guarantee with a zero anchor");
    assert_eq!(set.generated_count(), out.len());
}

// Cold-start equivalence: with no usable store the engine takes the current path.
// Every store failure mode must reproduce the fixture byte for byte (against the no-store run).
mod cold_start {
    use super::*;
    use kni_learning::{Loaded, Priors, Store};

    fn render(out: &[gen::GeneratedPair]) -> String {
        out.iter().map(|g| format!("{}\t{}\t{}\t{}\n", g.left, g.right, g.kern, g.tier)).collect()
    }

    fn priors_from(path: &str, pin: Option<&str>) -> Option<Priors> {
        match Store::load(path, pin) {
            Loaded::Warm(s) => Some(Priors::from_store(&s)).filter(|p| !p.is_empty()),
            Loaded::Cold(_) => None,
        }
    }

    #[test]
    fn missing_empty_corrupt_and_pin_mismatch_match_fixture() {
        let inp = load_inputs();
        let want = render(&gen::generate(&inp).unwrap());
        let dir = std::env::temp_dir();
        let t = |n: &str| format!("{}/kni-cold-{}-{n}", dir.display(), std::process::id());
        let (missing, empty, header, corrupt, pinned) = (t("m"), t("e"), t("h"), t("c"), t("p"));
        std::fs::write(&empty, "").unwrap();
        std::fs::write(&header, "KNI-LEARN\tschema=1\tfields=right_class\n").unwrap();
        std::fs::write(&corrupt, "garbage\x00").unwrap();
        // A valid, populated store whose pin does not match: warm with the right pin,
        // cold with a wrong one, so the mismatch is the only cause of the cold start.
        let mut st = Store::new(1, &["right_class"]).unwrap();
        for f in ["a", "b"] {
            st.append(kni_learning::Obs {
                key: vec![("right_class".into(), "1".into())], n: 2, sum: 2.0, sumsq: 2.0,
                prov: kni_learning::Provenance { font_id: f.into(), run_id: "r".into(), receipt_id: "x".into(), tested_sha: "s".into(), declared_cap_u: 1.0, measured_cap_px: 1.0, certified: true },
            }).unwrap();
        }
        st.save_new(&pinned).unwrap();
        let (good_pin, _) = st.pin();
        assert!(matches!(Store::load(&pinned, Some(&good_pin)), Loaded::Warm(_)));
        for (p, pin) in [(&missing, None), (&empty, None), (&header, None), (&corrupt, None), (&pinned, Some("00"))] {
            let pri = priors_from(p, pin);
            assert!(pri.is_none(), "{p} should be cold");
            assert_eq!(render(&gen::generate_with(&inp, pri.as_ref()).unwrap()), want, "{p}");
        }
        for p in [&empty, &header, &corrupt, &pinned] {
            let _ = std::fs::remove_file(p);
        }
    }
}
