//! End-to-end checks for the opt-in merge-visibility observer output.
//!
//! The unit-level fold-order test lives beside the private stage-1 reducer in
//! `merge_observe_tests.rs`; this file covers the public run/env/file contract.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);
const OBSERVER_FILE: &str = "merge-visibility-mov1.jsonl";

fn unique_dir(label: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "kni_merge_visibility_{label}_{}_{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}

fn copy_tree(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap_or_else(|e| panic!("create {}: {e}", dst.display()));
    for entry in fs::read_dir(src).unwrap_or_else(|e| panic!("read {}: {e}", src.display())) {
        let entry = entry.unwrap();
        let source = entry.path();
        let target = dst.join(entry.file_name());
        if source.is_dir() {
            copy_tree(&source, &target);
        } else {
            fs::copy(&source, &target).unwrap_or_else(|e| {
                panic!("copy {} -> {}: {e}", source.display(), target.display())
            });
        }
    }
}

fn snapshot_tree(root: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    fn walk(root: &Path, here: &Path, out: &mut BTreeMap<PathBuf, Vec<u8>>) {
        for entry in fs::read_dir(here).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                walk(root, &path, out);
            } else {
                out.insert(
                    path.strip_prefix(root).unwrap().to_path_buf(),
                    fs::read(&path).unwrap(),
                );
            }
        }
    }
    let mut out = BTreeMap::new();
    walk(root, root, &mut out);
    out
}

/// Resource-aware gate (chief ruling 2026-10-23, W5 1-CPU finding): both tests
/// exercise the multi-job engine path with `--jobs 2`. On a host with < 2
/// available parallelism the engine correctly REFUSES `--jobs 2` (typed cap),
/// so the multi-job path cannot be exercised there. That is an environment
/// SKIP, never a pass and never a fail of engine behavior.
fn multi_job_available() -> bool {
    let n = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    if n < 2 {
        // Machine-readable, machine-distinct SKIP evidence (captured stdout/stderr
        // is invisible for passing tests): one marker file with the actual capacity
        // facts. Marker present + tests ok = SKIP recorded; marker absent + tests ok
        // = real multi-job PASS on this host.
        let host = std::env::var("HOSTNAME").unwrap_or_else(|_| "unknown-host".into());
        let marker = std::path::Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join(format!("merge_visibility_e2e.SKIPPED.{host}.txt"));
        let _ = fs::write(
            &marker,
            format!("SKIP merge_visibility_e2e: available_parallelism={n} (<2), host={host}, multi-job path NOT exercised\n"),
        );
        eprintln!("SKIP: merge_visibility_e2e requires >=2 available CPUs (available {n}); multi-job path not exercised; marker {}", marker.display());
        return false;
    }
    true
}

fn run_engine(out_dir: &Path, jobs: usize, observation: Option<&str>) -> Output {
    let engine = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let fixture =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let manifest = fixture.join("manifest.txt");
    let mut command = Command::new(engine);
    command
        .arg(&manifest)
        .arg(out_dir)
        .arg("--style-id")
        .arg("Marq-Regular")
        .arg("--jobs")
        .arg(jobs.to_string())
        .arg("--allow-partial")
        .arg("--fallback-export-warn");
    match observation {
        Some(value) => {
            command.env("KNI_MERGE_OBSERVE", value);
        }
        None => {
            command.env_remove("KNI_MERGE_OBSERVE");
        }
    }
    let output = command.output().expect("spawn KNI pipeline");
    assert!(
        output.status.success(),
        "engine run failed (jobs={jobs}, observe={observation:?})\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

fn clean_temp(path: &Path) {
    let _ = fs::remove_dir_all(path);
}

#[test]
fn disabled_observer_preserves_every_output_byte_and_creates_no_jsonl() {
    if !multi_job_available() {
        return;
    }
    let work = unique_dir("off");
    let out = work.join("out");
    let baseline = work.join("baseline");
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).unwrap();

    run_engine(&out, 2, None);
    assert!(
        !out.join(OBSERVER_FILE).exists(),
        "default-off mode must not create the visibility file"
    );
    copy_tree(&out, &baseline);

    clean_temp(&out);
    run_engine(&out, 2, Some("0"));
    assert!(
        !out.join(OBSERVER_FILE).exists(),
        "KNI_MERGE_OBSERVE=0 must not create the visibility file"
    );
    assert_eq!(
        snapshot_tree(&out),
        snapshot_tree(&baseline),
        "observer-disabled run must preserve the full output tree byte for byte"
    );
    clean_temp(&work);
}

#[test]
fn enabled_output_is_lf_jsonl_with_116_hex_fp58_values() {
    if !multi_job_available() {
        return;
    }
    let work = unique_dir("jsonl");
    let out = work.join("out");
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).unwrap();

    run_engine(&out, 2, Some("1"));
    let path = out.join(OBSERVER_FILE);
    let bytes = fs::read(&path)
        .unwrap_or_else(|e| panic!("enabled observer must write {}: {e}", path.display()));
    assert!(!bytes.is_empty(), "JSONL must contain records");
    assert!(bytes.ends_with(b"\n"), "JSONL must end with LF");
    assert!(
        !bytes.windows(2).any(|w| w == b"\r\n"),
        "JSONL uses LF, not CRLF"
    );

    let text = std::str::from_utf8(&bytes).expect("JSONL is UTF-8");
    let mut rows = 0usize;
    let mut fp58_values = 0usize;
    for (index, line) in text.split_terminator('\n').enumerate() {
        rows += 1;
        assert!(
            !line.contains('\n') && !line.contains('\r'),
            "line {} is one LF-terminated record",
            index + 1
        );
        assert!(
            line.starts_with('{') && line.ends_with('}'),
            "line {} is a JSON object",
            index + 1
        );
        let mut tail = line;
        while let Some(start) = tail.find("\"fp58\"") {
            let after_key = &tail[start + "\"fp58\"".len()..];
            let colon = after_key.find(':').expect("fp58 key has a value");
            let value = after_key[colon + 1..].trim_start();
            if let Some(rest) = value.strip_prefix("null") {
                tail = rest;
                continue;
            }
            let quoted = value
                .strip_prefix('"')
                .expect("non-null fp58 value is quoted hex");
            let end = quoted.find('"').expect("fp58 value is terminated");
            let hex = &quoted[..end];
            assert_eq!(hex.len(), 116, "fp58 is 58 bytes rendered as 116 hex chars");
            assert!(
                hex.bytes()
                    .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()),
                "fp58 is lowercase hex"
            );
            fp58_values += 1;
            tail = &quoted[end + 1..];
        }
    }
    assert!(rows > 0, "at least one JSONL record");
    assert!(fp58_values > 0, "at least one fp58 field is serialized");
    clean_temp(&work);
}
