//! VALIDATOR-A (independent) — K1 pair-visual real-value trace, end-to-end.
//!
//! Separate test file; production main.rs is NOT modified by this test.
//! Traces REAL measured values from the K1 pair reader
//! (pair_visual_wiring::read_kerning_folder -> kni_metrics::pair_visual_read)
//! downstream to the run artifacts (pair_visual_report.tsv, .pin.tsv, stdout
//! receipt pin) through the actual kni-pipeline binary and its --pair-visual
//! adapter call in main.rs.
//!
//! The fixture image is generated independently of the patch authors
//! (validator-side, fixed geometry): 140x100 white RGBA, two black bars
//! x in [10,50) and [70,110), y in [20,80). Expected measurement, derived
//! by hand from metrics/src/pair_visual_read.rs semantics:
//!   min_gap_px = 20, mean_gap_px = 20, shared_rows = 60,
//!   gap_band = [50, 70), threshold = 0 (pure two-level image).
//! If the adapter call (pair_visual_pre_stage in main.rs run()) is removed,
//! the report files never appear and THIS TEST FAILS (negative proof below,
//! run in the adapter-removed tree).

use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

/// The validator-generated fixture PNG (140x100 RGBA, bars [10,50) / [70,110) x [20,80)).
/// sha256 = 557e30019365c94dbd18c9dcfcc21d54c0b555b684b5c30c97106aca8abeb6fc
const PAIR_AV_PNG_B64: &str = "iVBORw0KGgoAAAANSUhEUgAAAIwAAABkCAYAAABU19jRAAABD0lEQVR42u3SgQkAMAgDwey/tJ1BsFToPTiA4VJSo5hAwAgYASNgBIwEjIARMAJGwAgYCRgBI2AEjIARMBIwegYmyeobH+azf4EBBhhggAEGGGCAAQYYYPwLDDDAAAMMMMAAAwwwwAADDDDAAAMMMMAAAwwwBgQGGGCAAQYYYIABBhhggDGgf4EBBhhggAEGGGCAAQYYYPwLDDDAAAMMMMAAA4wBgQEGGGCAAQYYYIABBhhgDAgMMMAAAwwwwAADDDDAAAOMf4EBBhhggAEGGGCAAQYYYPwLDDDAAAMMMMAAA4wBgQEGGGCA2QxGAkbACBgBI2AEjASMgBEwAkbACBgJGAEjYASMgBEwEjC60gFekubwSLO7QAAAAABJRU5ErkJggg==";
const PAIR_AV_SHA256: &str = "557e30019365c94dbd18c9dcfcc21d54c0b555b684b5c30c97106aca8abeb6fc";

fn b64decode(s: &str) -> Vec<u8> {
    fn val(c: u8) -> u8 {
        match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => panic!("bad b64"),
        }
    }
    let bytes: Vec<u8> = s.bytes().filter(|&c| c != b'=').collect();
    let mut out = Vec::with_capacity(bytes.len() * 3 / 4);
    for q in bytes.chunks(4) {
        let n = q.len();
        let v: u32 = q.iter().enumerate().map(|(i, &c)| (val(c) as u32) << (18 - 6 * i)).sum();
        out.push((v >> 16) as u8);
        if n > 2 { out.push((v >> 8) as u8); }
        if n > 3 { out.push(v as u8); }
    }
    out
}

fn copy_tree(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap();
    for e in fs::read_dir(src).unwrap() {
        let e = e.unwrap();
        let to = dst.join(e.file_name());
        if e.file_type().unwrap().is_dir() {
            fs::create_dir_all(&to).unwrap();
            copy_tree(&e.path(), &to);
        } else {
            fs::copy(e.path(), &to).unwrap();
        }
    }
}

#[test]
fn k1_pair_visual_values_flow_downstream() {
    let png = b64decode(PAIR_AV_PNG_B64);
    let actual_sha = kni_core::cff_reader::sha256_hex(&png);
    assert_eq!(actual_sha, PAIR_AV_SHA256, "embedded fixture bytes drifted");

    let n = NEXT.fetch_add(1, Ordering::SeqCst);
    let work = std::env::temp_dir().join(format!("kni-k1-trace-{}-{}", std::process::id(), n));
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    copy_tree(&fixture, &work);

    // Real kerning folder, sha-pinned name per kerning_pairs grammar.
    let kdir = work.join("kerning");
    fs::create_dir_all(&kdir).unwrap();
    let member = format!("00001__0041_0056__{}.png", &actual_sha[..12]);
    fs::write(kdir.join(&member), &png).unwrap();

    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let out = work.join("out");
    let output = Command::new(bin)
        .arg(work.join("manifest.txt"))
        .arg(&out)
        .arg("--style-id").arg("Marq-Regular")
        .arg("--allow-partial")
        .arg("--fallback-export-warn")
        .arg("--pair-visual").arg(&kdir)
        .output()
        .expect("run engine");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    assert!(output.status.success(), "engine refused: {}", String::from_utf8_lossy(&output.stderr));

    // DOWNSTREAM ARTIFACT 1: the measured row in the report, with the exact
    // values predicted from the fixture geometry (not the patch's own numbers).
    let report_path = out.join("pair_visual_report.tsv");
    let tsv = fs::read_to_string(&report_path)
        .expect("pair_visual_report.tsv missing - the --pair-visual stage did not run (adapter call absent?)");
    assert!(tsv.starts_with("left\tright\tmin_gap_px\tmean_gap_px\tshared_rows\tgap_band_start\tgap_band_end\tthreshold\tgap_fu\tsource_sha256\tstatus\treason\timage_path\n"), "bad header:\n{tsv}");
    let row = format!("A\tV\t20.000\t20.000\t60\t50\t70\t0\t\t{}\tmeasured\t", actual_sha);
    assert!(tsv.contains(&row), "predicted measured row absent.\nwant: {row}\ngot:\n{tsv}");

    // DOWNSTREAM ARTIFACT 2: the pin sidecar binds the report bytes + counts.
    let pin_path = out.join("pair_visual_report.pin.tsv");
    let pin = fs::read_to_string(&pin_path).expect("pair_visual_report.pin.tsv missing");
    let report_sha = kni_core::cff_reader::sha256_hex(tsv.as_bytes());
    assert!(pin.contains(&format!("report_sha256\t{report_sha}")), "pin lacks report sha:\n{pin}");
    assert!(pin.contains("pair_visual_scope\treport_only\tspacing_use\tnone"), "pin lacks scope:\n{pin}");
    assert!(pin.contains("measured\t1\tfailed\t0\tunavailable\t0"), "pin counts wrong:\n{pin}");

    // DOWNSTREAM ARTIFACT 3: the pin reaches the run's stdout receipt tail.
    assert!(stdout.contains("pair_visual_report\tmeasured\t1"), "stdout receipt lacks pin lines:\n{stdout}");

    // The normal run still shipped its font (pre-stage did not break the run).
    assert!(out.join("font-Marq-Regular.otf").is_file(), "no OTF shipped");

    let _ = fs::remove_dir_all(&work);
}

// B-port S1a: declared same-source evidence is report-only, even when labels
// resolve to both glyphs in the actual solve population.
#[test]
fn s1a_same_source_is_report_only_with_byte_identical_spacing_and_font() {
    let n = NEXT.fetch_add(1, Ordering::SeqCst);
    let work = std::env::temp_dir().join(format!("kni-k12-parity-{}-{}", std::process::id(), n));
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    copy_tree(&fixture, &work);
    let kdir = work.join("kerning");
    fs::create_dir_all(&kdir).unwrap();
    let png = b64decode(PAIR_AV_PNG_B64);
    let sha = kni_core::cff_reader::sha256_hex(&png);
    fs::write(kdir.join(format!("00001__0043_0044__{}.png", &sha[..12])), png).unwrap();
    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let run = |tag: &str, pair: bool| {
        let out = work.join(tag);
        let mut cmd = Command::new(bin);
        cmd.arg(work.join("manifest.txt")).arg(&out).args(["--style-id", "Marq-Regular", "--jobs", "1", "--allow-partial", "--fallback-export-warn"]);
        if pair { cmd.arg("--pair-visual").arg(&kdir); }
        let output = cmd.output().unwrap();
        assert!(output.status.success(), "{}: {}", tag, String::from_utf8_lossy(&output.stderr));
        out
    };
    let cold = run("cold", false);
    let report = run("report", true);
    let manifest = work.join("manifest.txt");
    let mut text = fs::read_to_string(&manifest).unwrap();
    text.push_str("\npair_visual_same_source\n");
    fs::write(&manifest, &text).unwrap();
    let declared = run("declared", true);
    let receipt = fs::read_to_string(declared.join("receipt-Marq-Regular.txt")).unwrap();
    assert!(receipt.contains("pair_visual_targets\tmapped_pairs\t1"), "{}", receipt);
    assert!(receipt.contains("pair_visual_targets\tconsumption\treport_only\tspacing_use\tnone"));
    assert!(receipt.contains("pair_visual_scope\treport_only\tspacing_use\tnone"));
    for file in ["font-Marq-Regular.otf", "spacing.tsv", "spacing-pair-ledger.tsv", "kern-ledger.tsv", "kern-diagnostic.tsv", "mapping.tsv", "profile-metadata.tsv"] {
        assert_eq!(fs::read(cold.join(file)).unwrap(), fs::read(report.join(file)).unwrap(), "report-only changed {file}");
        assert_eq!(fs::read(cold.join(file)).unwrap(), fs::read(declared.join(file)).unwrap(), "same-source changed {file}");
    }
    // Same-source declaration without a pinned report refuses, not guessed evidence.
    let missing = Command::new(bin).arg(&manifest).arg(work.join("missing-pin")).args(["--style-id", "Marq-Regular", "--jobs", "1", "--allow-partial", "--fallback-export-warn"]).output().unwrap();
    assert!(!missing.status.success());
    assert!(String::from_utf8_lossy(&missing.stderr).contains("K1 pin is unreadable"));
    assert!(!work.join("missing-pin/font-Marq-Regular.otf").exists());
    let _ = fs::remove_dir_all(&work);
}
