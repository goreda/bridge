//! DEV CANDIDATE - AUTHOR DRAFT - NOT PRODUCTION.
//! Second round item 3: K2 store pin/SHA manifest key parse units
//! (missing, lone key, bad hex), black-box against the actual
//! kni-pipeline binary built from frozen b0b21e9 + gdb's K2 patches
//! (02-pck2-learned-priors b12a7770, 01-mainrs-learned-driver 1aac9bfc).
//!
//! New file only. Touches no production-writer file. Candidate only;
//! gdb's chief integrates.
//!
//! Wire under test (actual, from the applied patches):
//!   learned_store <repo-relative path> <sha256-hex>
//!   learned_gate_evidence <repo-relative path>
//!   Both absent = Cold (run unchanged); either alone = manifest error.

use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn bin() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_kni-pipeline"))
}

const PIN64: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

// Parse-valid base fixture: stage1_only (skips the run_mode-full population
// pin check), synthetic style with no declared-convention row, one glyph row
// whose tile does not exist, so a parse-ACCEPT run still refuses downstream
// at a deterministic, non-manifest stage.
fn base_manifest() -> String {
    let mut s = String::new();
    s.push_str("run_mode stage1_only\n");
    s.push_str("population_sha256 0000000000000000000000000000000000000000000000000000000000000000\n");
    s.push_str("family Devfixture\n");
    s.push_str("subfamily Unit\n");
    s.push_str("postscript_name Devfixture-Unit\n");
    s.push_str("vendor NONE\n");
    s.push_str("upm 1000\n");
    s.push_str("scale 1.0\n");
    s.push_str("rdp_epsilon 0.25\n");
    s.push_str("fit_tolerance_policy fixed\n");
    s.push_str("fit_squared_error 0.25\n");
    s.push_str("fit_max_refits 8\n");
    s.push_str("flatten_tolerance 0.5\n");
    s.push_str("max_pairs 1\n");
    s.push_str("glyph 0x0041 A tile-missing.png\n");
    s
}

struct Run {
    code: i32,
    stderr: String,
}

fn run_with(extra: &str) -> Run {
    let dir = std::env::temp_dir().join(format!(
        "k2dev-{}-{}", std::process::id(), unique()
    ));
    fs::create_dir_all(&dir).unwrap();
    let manifest = dir.join("fixture.manifest");
    fs::write(&manifest, format!("{}{}", base_manifest(), extra)).unwrap();
    let out = dir.join("out"); // must not exist: binary refuses overwrite
    let r = Command::new(bin())
        .arg(&manifest)
        .arg(&out)
        .arg("--style-id")
        .arg("Devfixture-Unit")
        .output()
        .unwrap();
    Run {
        code: r.status.code().unwrap_or(-1),
        stderr: String::from_utf8_lossy(&r.stderr).into_owned(),
    }
}

fn unique() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

fn assert_refused_with(r: &Run, want: &str) {
    assert_eq!(r.code, 1, "expected refusal exit 1, got {}: {}", r.code, r.stderr);
    assert!(
        r.stderr.contains(want),
        "stderr missing {:?}; got: {}",
        want, r.stderr
    );
}

// Control assertion for parse-ACCEPT cases: refusal comes from a later,
// non-learned stage; no learned-key manifest error may appear.
fn assert_parse_accepted(r: &Run) {
    assert_eq!(r.code, 1, "expected downstream refusal exit 1, got {}", r.code);
    // Pinned downstream marker for this fixture on frozen b0b21e9: the run
    // dies at scale wiring (capture_cohort undeclared), AFTER manifest parse.
    assert!(
        r.stderr.contains("scale wiring refused"),
        "expected downstream scale-wiring refusal; got: {}", r.stderr
    );
    assert!(!r.stderr.contains("usage:"), "unexpected usage refusal: {}", r.stderr);
    for bad in [
        "learned_store missing",
        "learned_store sha256",
        "learned_store extra",
        "duplicate learned_store",
        "requires learned_gate_evidence",
        "requires learned_store",
        "learned_gate_evidence missing",
    ] {
        assert!(!r.stderr.contains(bad), "unexpected learned-key error {:?}: {}", bad, r.stderr);
    }
}

// ---- Required class 1: missing ----

#[test]
fn missing_both_keys_parse_accepted_cold() {
    let r = run_with("");
    assert_parse_accepted(&r);
}

// ---- Required class 2: lone key ----

#[test]
fn lone_key_no_path_refused() {
    let r = run_with("learned_store\n");
    assert_refused_with(&r, "learned_store missing path");
}

#[test]
fn lone_key_path_no_pin_refused() {
    let r = run_with("learned_store store.knilearn\n");
    assert_refused_with(&r, "learned_store missing sha256");
}

#[test]
fn lone_evidence_key_no_path_refused() {
    let r = run_with("learned_gate_evidence\n");
    assert_refused_with(&r, "learned_gate_evidence missing path");
}

// ---- Required class 3: bad hex ----

#[test]
fn bad_hex_nonhex_refused() {
    let v = format!("{}g", "a".repeat(63));
    let r = run_with(&format!("learned_store store.knilearn {v}\n"));
    assert_refused_with(&r, "learned_store sha256 must be 64 lowercase hex");
}

#[test]
fn bad_hex_short_refused() {
    let v = "a".repeat(63);
    let r = run_with(&format!("learned_store store.knilearn {v}\n"));
    assert_refused_with(&r, "learned_store sha256 must be 64 lowercase hex");
}

#[test]
fn bad_hex_long_refused() {
    let v = "a".repeat(65);
    let r = run_with(&format!("learned_store store.knilearn {v}\n"));
    assert_refused_with(&r, "learned_store sha256 must be 64 lowercase hex");
}

#[test]
fn bad_hex_uppercase_refused() {
    let v = "A".repeat(64);
    let r = run_with(&format!("learned_store store.knilearn {v}\n"));
    assert_refused_with(&r, "learned_store sha256 must be 64 lowercase hex");
}

// ---- Structural classes around the pin key ----

#[test]
fn extra_field_refused() {
    let r = run_with(&format!("learned_store store.knilearn {PIN64} stray\n"));
    assert_refused_with(&r, "learned_store extra field");
}

#[test]
fn duplicate_store_key_refused() {
    let r = run_with(&format!(
        "learned_store a.knilearn {PIN64}\nlearned_store b.knilearn {PIN64}\n"
    ));
    assert_refused_with(&r, "duplicate learned_store");
}

#[test]
fn store_without_evidence_refused() {
    let r = run_with(&format!("learned_store store.knilearn {PIN64}\n"));
    assert_refused_with(&r, "learned_store requires learned_gate_evidence");
}

#[test]
fn evidence_without_store_refused() {
    let r = run_with("learned_gate_evidence evidence.tsv\n");
    assert_refused_with(&r, "learned_gate_evidence requires learned_store");
}

#[test]
fn valid_pair_parse_accepted() {
    let r = run_with(&format!(
        "learned_store store.knilearn {PIN64}\nlearned_gate_evidence evidence.tsv\n"
    ));
    assert_parse_accepted(&r);
}
