//! Fixture e2e: manifest-declared auto_sb (median mode) vs the fixed baseline.
//!
//! The a2 unit tests cover population math and loaders; this test proves the
//! wiring end to end on the 2-glyph real fixture (kit-v415/notdef-v3):
//!   1. baseline run (no auto_sb keys) ships the engine-solved sidebearings;
//!   2. the same fixture with `auto_sb median` ships the pool global medians
//!      for every fitted glyph - an observable spacing-field change vs the
//!      baseline, not a no-op (this is the negative control: if the auto_sb
//!      wiring is disabled or half-applied, the shipped fields cannot carry
//!      the pool medians);
//!   3. the median run is deterministic across identical runs;
//!   4. the strict validation law holds: dangling auto_sb keys with the mode
//!      off, and median mode without its pool or tie_break, are all refused.
//!
//! Pool medians (20/15) are test input chosen to differ from the measured
//! fixture baseline (actual baseline run: t43 lsb -42.92554249799974
//! rsb -42.96014690179723, t44 lsb -0.18914473684210525 rsb
//! -8.75750339314195); no quality or whole-font claim is made from 2 glyphs.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

const POOL: &str = "left_class\tright_class\tlsb\trsb\nempty\tempty\t10.0\t5.0\nempty\tempty\t20.0\t15.0\nempty\tempty\t30.0\t25.0\n";
const WANT_LSB: &str = "20";
const WANT_RSB: &str = "15";

fn copy_tree(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap_or_else(|e| panic!("create {}: {e}", dst.display()));
    for entry in fs::read_dir(src).unwrap_or_else(|e| panic!("read {}: {e}", src.display())) {
        let entry = entry.unwrap();
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() { copy_tree(&from, &to); } else { fs::copy(&from, &to).unwrap_or_else(|e| panic!("copy {} -> {}: {e}", from.display(), to.display())); }
    }
}

fn unique_work_dir(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!("kni_autosb_e2e_{}_{}_{}", tag, std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)))
}

fn run_engine(bin: &Path, manifest: &Path, out_dir: &Path) -> Output {
    Command::new(bin)
        .arg(manifest).arg(out_dir)
        .arg("--style-id").arg("Marq-Regular")
        .arg("--allow-partial").arg("--fallback-export-warn")
        .arg("--jobs").arg("1")
        .output().unwrap_or_else(|e| panic!("spawn engine: {e}"))
}

fn must_ok(output: &Output, what: &str) {
    assert!(output.status.success(), "{what} failed\nstdout:\n{}\nstderr:\n{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
}

fn must_refused(output: &Output, what: &str) {
    assert!(!output.status.success(), "{what} must be refused, got success\nstdout:\n{}", String::from_utf8_lossy(&output.stdout));
}

fn spacing_rows(out: &Path) -> Vec<(String, String, String)> {
    let text = String::from_utf8(fs::read(out.join("spacing.tsv")).expect("spacing.tsv shipped")).unwrap();
    text.lines()
        .skip(1)
        .map(|l| {
            let c: Vec<&str> = l.split('\t').collect();
            (c[0].to_string(), c[1].to_string(), c[2].to_string())
        })
        .collect()
}

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run")
}

/// auto_sb off -> on: the shipped spacing fields visibly change from the
/// engine-solved fixed baseline to the pool global medians, deterministically.
#[test]
fn median_mode_replaces_fixed_baseline_sidebearings() {
    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));

    // 1. Fixed baseline: the fixture as shipped declares no auto_sb keys.
    let base = unique_work_dir("baseline");
    copy_tree(&fixture_dir(), &base);
    let manifest = fs::read_to_string(base.join("manifest.txt")).unwrap();
    assert!(!manifest.contains("auto_sb"), "fixture must start without auto_sb keys");
    must_ok(&run_engine(bin, &base.join("manifest.txt"), &base.join("out")), "baseline run");
    let baseline_rows = spacing_rows(&base.join("out"));
    assert!(baseline_rows.len() >= 2, "fixture ships both glyphs, got {}", baseline_rows.len());

    // 2. Median mode: same fixture plus the auto_sb manifest keys.
    let med = unique_work_dir("median");
    copy_tree(&fixture_dir(), &med);
    fs::write(med.join("pool.tsv"), POOL).unwrap();
    fs::write(med.join("manifest.txt"), format!("{manifest}auto_sb median\ntie_break A\nauto_sb_pool pool.tsv\n")).unwrap();
    must_ok(&run_engine(bin, &med.join("manifest.txt"), &med.join("out")), "auto_sb median run");
    let median_rows = spacing_rows(&med.join("out"));
    assert_eq!(median_rows.len(), baseline_rows.len(), "same glyph set ships under median mode");

    // 3. Observable change: every fitted glyph carries the pool global medians
    //    under median mode, and the shipped (lsb, rsb) pair differs from the
    //    fixed baseline for at least one glyph (grounded: pool input chosen
    //    after recording the actual baseline values).
    let mut changed = 0usize;
    for ((bg, blsb, brsb), (mg, mlsb, mrsb)) in baseline_rows.iter().zip(median_rows.iter()) {
        assert_eq!(bg, mg, "same glyph order");
        assert_eq!(mlsb, WANT_LSB, "{mg}: lsb must be the pool global median");
        assert_eq!(mrsb, WANT_RSB, "{mg}: rsb must be the pool global median");
        if blsb != mlsb || brsb != mrsb { changed += 1; }
    }
    assert!(changed >= 1, "auto_sb must visibly change shipped spacing vs the fixed baseline (baseline {baseline_rows:?})");

    // 4. Determinism: a second identical median run ships byte-identical spacing.tsv.
    let med2 = unique_work_dir("median2");
    copy_tree(&med, &med2);
    fs::remove_dir_all(med2.join("out")).ok();
    must_ok(&run_engine(bin, &med2.join("manifest.txt"), &med2.join("out")), "auto_sb median rerun");
    assert_eq!(
        fs::read(med2.join("out/spacing.tsv")).unwrap(),
        fs::read(med.join("out/spacing.tsv")).unwrap(),
        "auto_sb output must be deterministic across identical runs"
    );
}

/// Strict validation law, fail-closed at manifest time (no engine run cost):
/// dangling auto_sb keys with the mode off, and median mode missing its pool
/// or tie_break, are all refused.
#[test]
fn auto_sb_manifest_validation_is_strict() {
    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let manifest = fs::read_to_string(fixture_dir().join("manifest.txt")).unwrap();

    // Mode off + dangling pool key -> refused.
    let w = unique_work_dir("dangling");
    copy_tree(&fixture_dir(), &w);
    fs::write(w.join("pool.tsv"), POOL).unwrap();
    fs::write(w.join("manifest.txt"), format!("{manifest}auto_sb_pool pool.tsv\n")).unwrap();
    must_refused(&run_engine(bin, &w.join("manifest.txt"), &w.join("out")), "dangling auto_sb_pool with mode off");

    // Median mode without pool -> refused.
    let w = unique_work_dir("no-pool");
    copy_tree(&fixture_dir(), &w);
    fs::write(w.join("manifest.txt"), format!("{manifest}auto_sb median\ntie_break A\n")).unwrap();
    must_refused(&run_engine(bin, &w.join("manifest.txt"), &w.join("out")), "median mode without auto_sb_pool");

    // Median mode without tie_break -> refused.
    let w = unique_work_dir("no-tie");
    copy_tree(&fixture_dir(), &w);
    fs::write(w.join("pool.tsv"), POOL).unwrap();
    fs::write(w.join("manifest.txt"), format!("{manifest}auto_sb median\nauto_sb_pool pool.tsv\n")).unwrap();
    must_refused(&run_engine(bin, &w.join("manifest.txt"), &w.join("out")), "median mode without tie_break");
}
