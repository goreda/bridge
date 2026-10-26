//! Scan evidence production must enter the current bound .notdef chain.
use std::{fs, path::{Path, PathBuf}, process::Command};
use std::sync::atomic::{AtomicUsize, Ordering};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn tree(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap();
    for e in fs::read_dir(src).unwrap() {
        let e = e.unwrap(); let to = dst.join(e.file_name());
        if e.file_type().unwrap().is_dir() { tree(&e.path(), &to); }
        else { fs::copy(e.path(), to).unwrap(); }
    }
}
fn fixture() -> PathBuf {
    let work = std::env::temp_dir().join(format!("k3-route-e2e-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
    let fix = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3");
    tree(&fix.join("run"), &work);
    fs::create_dir_all(work.join("notdef")).unwrap();
    for n in ["capture-manifest.tsv", "evidence.tsv", "w41.png", "w42.png"] {
        fs::copy(fix.join("staged-expected").join(n), work.join("notdef").join(n)).unwrap();
    }
    fs::copy(fix.join("staged-expected/manifest.txt"), work.join("manifest.txt")).unwrap();
    work
}
fn engine(work: &Path, tag: &str) -> String {
    let output = Command::new(env!("CARGO_BIN_EXE_kni-pipeline"))
        .arg(work.join("manifest.txt")).arg(work.join(tag))
        .args(["--style-id", "Marq-Regular", "--allow-partial", "--fallback-export-warn"])
        .output().unwrap();
    assert!(output.status.success(), "engine: {}", String::from_utf8_lossy(&output.stderr));
    fs::read_to_string(work.join(tag).join("receipt-Marq-Regular.txt")).unwrap()
}
#[test]
fn scan_confirmed_repeated_form_matches_declared_evidence_outputs() {
    let work = fixture();
    let manifest = fs::read_to_string(work.join("manifest.txt")).unwrap();
    let declared = engine(&work, "declared");
    assert!(!declared.contains("evidence_route\tconfirmed"));
    let scan = manifest.lines().filter(|l| !l.starts_with("notdef evidence ")).collect::<Vec<_>>().join("\n") + "\n";
    fs::write(work.join("manifest.txt"), scan).unwrap();
    let scanned = engine(&work, "scan");
    assert!(scanned.contains("k3_notdef_scan\tevidence_route\tconfirmed\tkind\trepeated-form"), "{scanned}");
    assert!(scanned.contains("sources\t0x41,0x42"), "{scanned}");
    for name in ["font-Marq-Regular.otf", "mapping.tsv", "spacing.tsv", "kern-ledger.tsv"] {
        assert_eq!(fs::read(work.join("declared").join(name)).unwrap(), fs::read(work.join("scan").join(name)).unwrap(), "{name}");
    }
    let mapping = fs::read_to_string(work.join("scan/mapping.tsv")).unwrap();
    assert!(!mapping.lines().any(|l| l.starts_with("0x41\t") || l.starts_with("0x42\t")), "{mapping}");
    assert!(!fs::read_dir(&work).unwrap().any(|e| e.unwrap().file_name().to_string_lossy().starts_with(".k3-scan-evidence-")));
    fs::remove_dir_all(work).unwrap();
}
#[test]
fn rejected_declared_evidence_does_not_trigger_scan_confirmation() {
    let work = fixture();
    let p = work.join("notdef/evidence.tsv");
    let mut evidence = fs::read(p.clone()).unwrap(); evidence.extend_from_slice(b"tamper"); fs::write(p, evidence).unwrap();
    let receipt = engine(&work, "rejected");
    assert!(receipt.contains("notdef_evidence_ignored\tShaMismatch"), "{receipt}");
    assert!(!receipt.contains("evidence_route\tconfirmed"), "{receipt}");
    fs::remove_dir_all(work).unwrap();
}
