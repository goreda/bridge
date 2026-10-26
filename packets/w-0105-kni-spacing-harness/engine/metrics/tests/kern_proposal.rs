//! Kern proposal table: wraps the generator, adds no predictor.

use kni_metrics::gen;
use kni_metrics::kern_proposal::*;

fn load_inputs() -> gen::GenerationInputs {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
    let rd = |n: &str| std::fs::read_to_string(format!("{dir}/{n}")).unwrap();
    let (glyphs, knowledge) = gen::parse_classes(&rd("classes.tsv")).unwrap();
    gen::GenerationInputs {
        glyphs,
        knowledge,
        targets: gen::parse_targets(&rd("targets.tsv")).unwrap(),
        walls: gen::parse_walls(&rd("walls.tsv")).unwrap(),
        existing: gen::existing_from_pairs(gen::parse_pairs(&rd("existing.tsv")).unwrap()).unwrap(),
        restore: gen::parse_pairs(&rd("restore.tsv")).unwrap(),
    }
}

#[test]
fn output_is_deterministic_and_independent_of_glyph_order() {
    let inp = load_inputs();
    let a = build_proposal(&inp, None).unwrap();
    let b = build_proposal(&inp, None).unwrap();
    assert_eq!(a.tsv(), b.tsv());
    assert_eq!(a.tsv_sha256(), b.tsv_sha256());
    let mut rev = inp.clone();
    rev.glyphs.reverse();
    assert_eq!(build_proposal(&rev, None).unwrap().tsv(), a.tsv());
}

#[test]
fn proposed_rows_equal_the_generator_output() {
    let inp = load_inputs();
    let p = build_proposal(&inp, None).unwrap();
    let generated = gen::generate(&inp).unwrap();
    let mut from_rows: Vec<(String, String, i32)> = p
        .rows
        .iter()
        .filter(|r| r.status == Status::Proposed)
        .map(|r| (r.left.clone(), r.right.clone(), r.value.unwrap()))
        .collect();
    let mut from_gen: Vec<(String, String, i32)> =
        generated.iter().map(|g| (g.left.clone(), g.right.clone(), g.kern)).collect();
    from_rows.sort();
    from_gen.sort();
    assert_eq!(from_rows, from_gen, "the table must not change a generated value");
    // The additive guarantee holds for the proposed rows.
    let pairs: Vec<gen::GeneratedPair> = generated;
    gen::build_additive_set(&inp, &pairs).expect("additive check");
}

#[test]
fn rows_are_sorted_unique_and_never_cover_existing_pairs() {
    let inp = load_inputs();
    let p = build_proposal(&inp, None).unwrap();
    let keys: Vec<(&str, &str)> = p.rows.iter().map(|r| (r.left.as_str(), r.right.as_str())).collect();
    let mut sorted = keys.clone();
    sorted.sort();
    sorted.dedup();
    assert_eq!(keys, sorted);
    for r in &p.rows {
        assert!(!inp.existing.contains_key(&(r.left.clone(), r.right.clone())));
    }
}

#[test]
fn status_fields_are_consistent_and_unavailable_never_has_a_value() {
    let inp = load_inputs();
    let p = build_proposal(&inp, None).unwrap();
    let pol = gen::derive_policy(&inp).unwrap();
    for r in &p.rows {
        match r.status {
            Status::Proposed => {
                assert!(r.value.is_some() && r.reason.is_none());
                if r.source != Some(Source::Restore) {
                    let v = r.value.unwrap();
                    assert!((pol.clamp_lo..=pol.clamp_hi).contains(&v));
                    assert!(v.unsigned_abs() >= pol.noise_floor as u32);
                }
            }
            Status::Unavailable => assert!(r.value.is_none() && r.reason.is_some()),
        }
        if r.reason == Some(Reason::BelowNoise) {
            assert!(r.raw_value.is_some());
        }
        assert_ne!(r.reason, Some(Reason::NotConverged));
    }
}

#[test]
fn explicit_zero_is_protected_and_counted() {
    let mut inp = load_inputs();
    let p0 = build_proposal(&inp, None).unwrap();
    let first = p0.rows.iter().find(|r| r.source != Some(Source::Restore) && r.status == Status::Proposed).unwrap();
    let key = (first.left.clone(), first.right.clone());
    inp.existing.insert(key.clone(), 0);
    let p = build_proposal(&inp, None).unwrap();
    assert!(!p.rows.iter().any(|r| (r.left.clone(), r.right.clone()) == key));
    assert!(p.protected_zero >= 1);
    assert_eq!(p.protected_existing, inp.existing.len());
}

#[test]
fn tsv_has_a_fixed_header_and_twelve_columns() {
    let inp = load_inputs();
    let t = build_proposal(&inp, None).unwrap().tsv();
    let mut lines = t.lines();
    assert_eq!(lines.next().unwrap(), TSV_HEADER);
    assert_eq!(lines.next().unwrap(), TSV_COLUMNS);
    assert!(t.ends_with('\n'));
    let mut data = 0;
    for l in t.lines().filter(|l| !l.starts_with('#')) {
        assert_eq!(l.split('\t').count(), 12, "{l}");
        data += 1;
    }
    assert!(data > 0);
    assert!(t.contains("\n#inputs_sha256\t"));
}

#[test]
fn input_errors_are_the_typed_errors_of_the_generator() {
    let mut inp = load_inputs();
    inp.existing.clear();
    assert!(build_proposal(&inp, None).is_err());
    let mut inp = load_inputs();
    inp.targets.global_mingap = f64::NAN;
    assert!(matches!(build_proposal(&inp, None).unwrap_err(), gen::GenError::NonFinite(_)));
}

#[test]
fn inputs_digest_changes_with_the_inputs() {
    let inp = load_inputs();
    let a = build_proposal(&inp, None).unwrap().inputs_sha256;
    let mut other = load_inputs();
    other.targets.global_mingap += 1.0;
    assert_ne!(a, build_proposal(&other, None).unwrap().inputs_sha256);
}
