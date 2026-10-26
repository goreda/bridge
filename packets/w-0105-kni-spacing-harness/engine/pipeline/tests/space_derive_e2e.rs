//! End-to-end fixture for the always-output space derivation.
//!
//! Fixture: tests/fixtures/kit-v415/notdef-v3/run, a complete two-glyph
//! full-mode population (C and D: no n, no lowercase) with NO space row and
//! NO space-measurement evidence. With the manifest key
//! `derive_space_from_letter_advances` the run must ship an OTF whose cmap
//! maps U+0020, and the receipt must name the derivation basis
//! (all_glyph_median here) instead of running partial or refusing.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

fn unique_work_dir(tag: &str) -> PathBuf {
    let n = NEXT.fetch_add(1, Ordering::SeqCst);
    let dir = std::env::temp_dir().join(format!("kni-space-derive-e2e-{}-{}", std::process::id(), n));
    fs::create_dir_all(&dir).unwrap();
    let _ = tag;
    dir
}

fn copy_tree(src: &Path, dst: &Path) {
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
fn derive_space_key_ships_space_glyph_and_names_basis() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let work = unique_work_dir("derive");
    copy_tree(&fixture, &work);
    let mut manifest = fs::read_to_string(work.join("manifest.txt")).unwrap();
    assert!(!manifest.contains("space "), "fixture must start without a space row");
    manifest.push_str("derive_space_from_letter_advances\n");
    fs::write(work.join("manifest.txt"), manifest).unwrap();

    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let out = work.join("out");
    // The fixture's notdef evidence is intentionally unresolved (same as the
    // stage1 replay e2e), so the run goes through the engine's partial mode for
    // the .notdef side only; the space side must NOT be partial.
    let output = Command::new(bin)
        .arg(&work.join("manifest.txt"))
        .arg(&out)
        .arg("--style-id")
        .arg("Marq-Regular")
        .arg("--allow-partial")
        .arg("--fallback-export-warn")
        .output()
        .expect("run engine");
    assert!(output.status.success(), "engine refused: {}", String::from_utf8_lossy(&output.stderr));

    // The OTF ships and its cmap maps U+0020.
    assert!(out.join("font-Marq-Regular.otf").is_file(), "no OTF shipped");
    let mapping = fs::read_to_string(out.join("mapping.tsv")).unwrap();
    assert!(mapping.lines().any(|l| l.starts_with("0x20\t")), "cmap has no U+0020 row:\n{mapping}");

    // Receipt: derived source with the all-glyph-median basis (C and D only),
    // the typed space_derived warning row, and never a partial marker.
    let receipt = fs::read_to_string(out.join("receipt-Marq-Regular.txt")).unwrap();
    let asm = receipt.lines().find(|l| l.starts_with("assembly_space_glyph")).expect("no assembly_space_glyph row");
    assert!(asm.contains("true"), "space glyph not assembled: {asm}");
    assert!(asm.contains("source\tderived:all_glyph_median"), "unexpected source: {asm}");
    let warn = receipt.lines().find(|l| l.starts_with("warning\tspace_derived\t")).expect("no space_derived warning row");
    assert!(warn.contains("basis\tall_glyph_median"), "unexpected basis: {warn}");
    let value: f64 = warn.rsplit("\tvalue\t").next().unwrap().parse().expect("value must be a number");
    assert!(value > 0.0, "derived advance must be positive: {warn}");
    assert!(!receipt.contains("reason\tspace_missing_evidence"), "derived space must never mark the run space-partial:\n{receipt}");

    let _ = fs::remove_dir_all(&work);
}

#[test]
fn without_derive_key_old_behavior_is_intact() {
    // Same fixture without the key: the old space path stands - no space glyph is
    // assembled (assembly_space_glyph false) and nothing is derived.
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let work = unique_work_dir("nokey");
    copy_tree(&fixture, &work);
    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let out = work.join("out");
    let output = Command::new(bin)
        .arg(&work.join("manifest.txt"))
        .arg(&out)
        .arg("--style-id")
        .arg("Marq-Regular")
        .arg("--allow-partial")
        .arg("--fallback-export-warn")
        .output()
        .expect("run engine");
    assert!(output.status.success(), "engine refused: {}", String::from_utf8_lossy(&output.stderr));
    let receipt = fs::read_to_string(out.join("receipt-Marq-Regular.txt")).unwrap();
    let asm = receipt.lines().find(|l| l.starts_with("assembly_space_glyph")).expect("no assembly_space_glyph row");
    assert!(asm.contains("false"), "old path assembles no space glyph: {asm}");
    assert!(!receipt.contains("space_derived"), "no derivation without the key:\n{receipt}");
    let mapping = fs::read_to_string(out.join("mapping.tsv")).unwrap();
    assert!(!mapping.lines().any(|l| l.starts_with("0x20\t")), "old path maps no U+0020:\n{mapping}");
    let _ = fs::remove_dir_all(&work);
}
