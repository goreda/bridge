use kni_core::regress_class::*;

#[test]
fn synthetic_sign_counts_and_unmatched() {
    let cohort = "glyph\tcodepoint\tshape_class\told_iou\tstatus\nA\tU+0041\tS\t0.9\tregressed\nB\tU+0042\tS\t0.9\tregressed\nC\tU+0043\tG\t0.9\tregressed\n";
    let meas = "glyph\tcodepoint\tarm\tiou_scan_domain\nA\t0x0041\tx\t0.8\nA\t0x0041\ty\t0.95\nB\t0x0042\tx\t0.92\nB\t0x0042\ty\t0.91\n";
    let r = report(&parse_cohort(cohort).unwrap(), &parse_measurements(meas).unwrap(), "x", "y");
    let s = &r.classes[&("regressed".to_string(), "S".to_string())];
    assert_eq!((s.n, s.arm_a_below_old, s.arm_b_below_old, s.arm_a_below_arm_b), (2, 1, 0, 1));
    assert_eq!(r.unmatched, vec!["C".to_string()]);
}

#[test]
fn missing_column_is_typed_error() {
    assert!(parse_cohort("glyph\tcodepoint\n").is_err());
    assert!(parse_measurements("glyph\tcodepoint\n").is_err());
}

/// Canonical run (CANON-FIX-1 measurements-after.tsv) against the W2-8 cohort.
/// Pinned raw counts measured on HEAD 38f506e3.
#[test]
fn canonical_run_cohort_counts() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let cohort = std::fs::read_to_string(root.join("tests/fixtures/regress-class/cohort-w2-8.tsv")).unwrap();
    let meas = std::fs::read_to_string(root.join("../docs/engine/execution/20261018-canon-fix-1/measurements-after.tsv")).unwrap();
    let r = report(&parse_cohort(&cohort).unwrap(), &parse_measurements(&meas).unwrap(), "canonical_k1", "production");
    assert!(r.unmatched.is_empty());
    let reg: Vec<&ClassRow> = r.classes.iter().filter(|(k, _)| k.0 == "regressed").map(|(_, v)| v).collect();
    assert_eq!(reg.iter().map(|v| v.n).sum::<usize>(), 34);
    assert_eq!(reg.iter().map(|v| v.arm_a_below_old).sum::<usize>(), 9);
    assert_eq!(reg.iter().map(|v| v.arm_b_below_old).sum::<usize>(), 2);
    assert_eq!(reg.iter().map(|v| v.arm_a_below_arm_b).sum::<usize>(), 32);
}
