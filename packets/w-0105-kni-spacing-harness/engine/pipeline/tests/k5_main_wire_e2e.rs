//! DEV candidate r4 (seven unresolved codes; r1 had six and ran 1 passed, vacuous on the failed path, on Team 8's run). Full-main end-to-end check for the K5 bind
//! (patch 55876535, k5_main_adapter wired into main.rs). It runs the real kni-pipeline binary on the in-tree
//! two-glyph fixture, then recomputes the expected export-gate-pairs.tsv INDEPENDENTLY from the run's own
//! spacing-pair-ledger.tsv and compares. It must FAIL on the frozen baseline (no export-gate-pairs.tsv is written there),
//! so a pass is evidence of the new wire, never of the baseline.
//! Scope: default mode (never refuses). Strict mode is covered by the adapter unit tests in the patch.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

/// Same list as k5_main_adapter::UNRESOLVED_CODES, repeated on purpose: the test must not import the code under test.
/// r4: seven codes. excluded_unmeasurable is a typed UNRESOLVED code by the chief decision (16:01 relay): a pair with it makes the gate incomplete.
const UNRESOLVED: [&str; 7] = [
    "no_feasible", "no_accepted_candidate", "not_converged",
    "nonfinite_failure", "natural_unverifiable", "natural_frame_conflict", "excluded_unmeasurable",
];

fn unique_work_dir() -> PathBuf {
    let n = NEXT.fetch_add(1, Ordering::SeqCst);
    let dir = std::env::temp_dir().join(format!("kni-k5-main-wire-{}-{}", std::process::id(), n));
    fs::create_dir_all(&dir).unwrap();
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

fn clean(s: &str) -> String { s.replace('\t', " ").replace('\n', " ").replace('\r', " ") }

#[test]
fn main_writes_export_gate_pairs_consistent_with_its_own_ledger() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let work = unique_work_dir();
    copy_tree(&fixture, &work);
    let out = work.join("out");
    let output = Command::new(Path::new(env!("CARGO_BIN_EXE_kni-pipeline")))
        .arg(work.join("manifest.txt")).arg(&out)
        .arg("--style-id").arg("Marq-Regular")
        .arg("--allow-partial").arg("--fallback-export-warn")
        .output().expect("run engine");
    assert!(output.status.success(), "engine refused (default mode must never refuse on K5): {}", String::from_utf8_lossy(&output.stderr));

    // The font is still published: K5 default mode never decides publication.
    assert!(out.join("font-Marq-Regular.otf").is_file(), "no OTF shipped");

    // 1. The new report exists (absent on baseline: this is the line that fails there).
    let gate = fs::read_to_string(out.join("export-gate-pairs.tsv")).expect("export-gate-pairs.tsv missing: K5 bind not wired");
    assert_eq!(gate.lines().next(), Some("pair\tstatus\treason"), "unexpected header");

    // 2. Recompute expectations from the ledger main itself wrote.
    let ledger = fs::read_to_string(out.join("spacing-pair-ledger.tsv")).unwrap();
    let mut n_rows = 0usize;
    let mut want_failed: Vec<(String, String)> = Vec::new();
    let mut want_solved: Vec<String> = Vec::new();
    for line in ledger.lines().skip(1) {
        let c: Vec<&str> = line.split('\t').collect();
        assert!(c.len() >= 4, "short ledger row: {line}");
        n_rows += 1;
        let pair = clean(format!("{}|{}|{}", c[0], c[1], c[2]).trim());
        if UNRESOLVED.contains(&c[3]) { want_failed.push((pair, c[3].to_string())); } else { want_solved.push(pair); }
    }
    let got_solved: Vec<String> = gate.lines().skip(1).filter(|l| l.contains("\tsolved\t")).map(|l| l.split('\t').next().unwrap().to_string()).collect();
    let got_failed: Vec<(String, String)> = gate.lines().skip(1).filter(|l| l.contains("\tfailed\t") && !l.starts_with("(counter-only)"))
        .map(|l| { let c: Vec<&str> = l.split('\t').collect(); (c[0].to_string(), c[2].to_string()) }).collect();
    // Duplicate names collapse in the gate (first wins), so compare as sets and bound the counts.
    for p in &got_solved { assert!(want_solved.contains(p), "solved row not in ledger: {p}"); }
    for f in &got_failed { assert!(want_failed.iter().any(|w| w.0 == f.0), "failed row not in ledger: {f:?}"); }
    assert!(got_solved.len() + got_failed.len() <= n_rows, "gate reports more pairs than the ledger has");

    // 3. Receipt row agrees with the report.
    let receipt = fs::read_to_string(out.join("receipt-Marq-Regular.txt")).unwrap();
    let row = receipt.lines().find(|l| l.starts_with("export_gate_pairs\tsubmitted\t")).expect("no export_gate_pairs receipt row");
    assert!(row.contains("report\texport-gate-pairs.tsv"), "row does not name its report: {row}");
    assert!(row.contains(&format!("submitted\t{}\t", n_rows)), "submitted != ledger rows ({n_rows}): {row}");
    let failed_n = got_failed.len();
    assert!(row.contains(&format!("failed\t{}\t", failed_n)), "failed count mismatch ({failed_n}): {row}");

    // 4. Partial marker iff something failed (counter-only numeric failures also count and are named in the report).
    let counter_only = gate.lines().any(|l| l.starts_with("(counter-only)"));
    let has_marker = receipt.contains("partial_output\ttrue\treason\texport_gate_pairs_failed");
    assert_eq!(has_marker, failed_n > 0 || counter_only, "partial marker disagrees with the report");
}
