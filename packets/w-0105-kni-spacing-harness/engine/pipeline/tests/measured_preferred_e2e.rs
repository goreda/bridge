//! R1 end-to-end on the bounded kit-v415 notdef-v3 fixture (C and D glyph scans).
//! Key absent: no os2_x_height_measured row and the OTF is the same as before the key existed.
//! `os2_x_height_write measured_preferred` + a declared M3 set: this fixture's glyphs have round
//! bottoms, so M1/M3 stay UNRESOLVED; the run must say so honestly and keep the current solver
//! sxHeight (same OTF bytes as the run without the key). The RESOLVED real-source path needs a
//! scan with flat-bottom/flat-top glyphs and is NOT covered here.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

fn copy_tree(src: &Path, dst: &Path) {
    for e in fs::read_dir(src).unwrap() {
        let e = e.unwrap();
        let to = dst.join(e.file_name());
        if e.file_type().unwrap().is_dir() { fs::create_dir_all(&to).unwrap(); copy_tree(&e.path(), &to); } else { fs::copy(e.path(), &to).unwrap(); }
    }
}

const M3: &str = "m3_lower_set 0x43 0x44\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 1\nm3_tol_flat 2\nm3_min_gap 5\n";

fn run(extra: &str) -> (PathBuf, String, Vec<u8>) {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let work = std::env::temp_dir().join(format!("kni-mp-e2e-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
    fs::create_dir_all(&work).unwrap();
    copy_tree(&fixture, &work);
    let mut m = fs::read_to_string(work.join("manifest.txt")).unwrap();
    m.push_str(extra);
    fs::write(work.join("manifest.txt"), m).unwrap();
    let out = work.join("out");
    let o = Command::new(Path::new(env!("CARGO_BIN_EXE_kni-pipeline"))).arg(work.join("manifest.txt")).arg(&out)
        .args(["--style-id", "Marq-Regular", "--allow-partial", "--fallback-export-warn"]).output().expect("run engine");
    assert!(o.status.success(), "engine refused: {}", String::from_utf8_lossy(&o.stderr));
    let receipt = fs::read_to_string(out.join("receipt-Marq-Regular.txt")).unwrap();
    let otf = fs::read(out.join("font-Marq-Regular.otf")).unwrap();
    (work, receipt, otf)
}

fn os2_x_height(otf: &[u8]) -> i16 {
    let n = u16::from_be_bytes([otf[4], otf[5]]) as usize;
    for i in 0..n {
        let r = 12 + 16 * i;
        if &otf[r..r + 4] == b"OS/2" {
            let off = u32::from_be_bytes([otf[r + 8], otf[r + 9], otf[r + 10], otf[r + 11]]) as usize;
            return i16::from_be_bytes([otf[off + 86], otf[off + 87]]);
        }
    }
    panic!("no OS/2 table");
}

#[test]
fn key_absent_has_no_measured_row_and_measured_preferred_falls_back_honestly() {
    let (w0, r0, otf0) = run("");
    let (w1, r1, otf1) = run(&format!("{M3}os2_x_height_write measured_preferred\n"));
    assert!(!r0.contains("os2_x_height_measured"), "key absent must not add the row");
    assert!(r1.lines().any(|l| l == "os2_x_height_measured\tnot_measured\treason\tM3_UNRESOLVED_OR_NOT_DECLARED\tfallback\tsolver_current"), "{r1}");
    assert!(r1.contains("m3_result\tUNRESOLVED"), "fixture M3 must stay unresolved");
    // R3: the run_config token carries the full declared M3 input set (bit-pattern f64s),
    // so run_config_sha256 binds exactly what measured_preferred would consume.
    let expected_token = "measured_preferred;m3[lower=43,44;excl=6F;cap=-;gap=4024000000000000;min_cs=1;tol=4000000000000000;min_gap=4014000000000000]";
    assert!(r1.contains(&format!("run_config\tos2_x_height_write\t{expected_token}\tPOLICY")), "declared key + full declared M3 inputs are receipted in run_config: {r1}");
    assert_eq!(os2_x_height(&otf0), os2_x_height(&otf1), "fallback keeps the solver sxHeight");
    assert_eq!(os2_x_height(&otf0), 635);
    let _ = fs::remove_dir_all(w0); let _ = fs::remove_dir_all(w1);
}
