//! End-to-end regression for the stage-1 cache replay path.
//!
//! Protocol: one engine binary runs the same fixture twice. The first run
//! fits stage 1 live and writes its own stage-1 cache. The second run reuses
//! that cache (manifest + one `stage1_cache` line), so the cache executable
//! pin matches by construction. The replay run must reproduce the live run's
//! outputs byte for byte: the shipped font and the kern/spacing ledgers all
//! derive from the stage-1 shipped geometry, so any geometry the replay drops
//! or swaps (for example a missing shipped write-back, or measurement
//! geometry leaking into the shipped channel) shows up here as a byte
//! difference.
//!
//! Fixture: tests/fixtures/kit-v415/notdef-v3/run, a complete two-glyph
//! full-mode population that already ships in this repository. A second case
//! generates a two-tile population in which one tile carries a sub-pixel
//! speck, so the speck evidence path goes through the cache as well.
//!
//! The run receipt is compared line by line too. Only lines that label
//! themselves live-only are masked, plus a short fixed list of rows that
//! describe the invocation itself (see `INVOCATION_ROWS`).

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

/// Outputs the replay must reproduce byte for byte. The font file name
/// derives from the `--style-id Marq-Regular` invocation below.
const ARTIFACTS: [&str; 7] = [
    "font-Marq-Regular.otf",
    "kern-ledger.tsv",
    "kern-diagnostic.tsv",
    "spacing-pair-ledger.tsv",
    "spacing.tsv",
    "mapping.tsv",
    "profile-metadata.tsv",
];

/// Label a receipt line carries when it describes the live stage-1 pass only.
const LIVE_ONLY_LABEL: &str = "(live stage1 pass only)";

/// Rows that describe the invocation, not the run result: the replay manifest
/// has one more line (the cache reference), so its pin differs by construction
/// and the replay run reports the cache it reused.
const INVOCATION_ROWS: [&str; 2] = ["manifest_pin\t", "stage1_cache\t"];

/// Field whose value hashes the run configuration, which includes the manifest.
const CONFIG_HASH_FIELD: &str = "run_config_sha256\t";

fn receipt_name() -> &'static str {
    "receipt-Marq-Regular.txt"
}

/// Receipt lines with the explicitly masked content removed.
fn comparable_receipt(text: &str) -> Vec<String> {
    text.lines()
        .filter(|l| !l.contains(LIVE_ONLY_LABEL))
        .filter(|l| !INVOCATION_ROWS.iter().any(|p| l.starts_with(p)))
        .map(|l| match l.find(CONFIG_HASH_FIELD) {
            Some(i) => l[..i + CONFIG_HASH_FIELD.len()].to_string(),
            None => l.to_string(),
        })
        .collect()
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

fn png_chunk(out: &mut Vec<u8>, kind: &[u8; 4], body: &[u8]) {
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    let mut tagged = kind.to_vec();
    tagged.extend_from_slice(body);
    out.extend_from_slice(&tagged);
    out.extend_from_slice(&crc32(&tagged).to_be_bytes());
}

/// Minimal 8-bit grayscale PNG with stored (uncompressed) deflate blocks.
fn gray_png(width: usize, height: usize, pixels: &[u8]) -> Vec<u8> {
    assert_eq!(pixels.len(), width * height);
    let mut raw = Vec::with_capacity((width + 1) * height);
    for row in pixels.chunks(width) {
        raw.push(0);
        raw.extend_from_slice(row);
    }
    let mut z = vec![0x78, 0x01];
    let blocks: Vec<&[u8]> = raw.chunks(65535).collect();
    for (i, b) in blocks.iter().enumerate() {
        z.push(if i + 1 == blocks.len() { 1 } else { 0 });
        z.extend_from_slice(&(b.len() as u16).to_le_bytes());
        z.extend_from_slice(&(!(b.len() as u16)).to_le_bytes());
        z.extend_from_slice(b);
    }
    let (mut a, mut b) = (1u32, 0u32);
    for &x in &raw {
        a = (a + x as u32) % 65521;
        b = (b + a) % 65521;
    }
    z.extend_from_slice(&((b << 16) | a).to_be_bytes());
    let mut out = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&(width as u32).to_be_bytes());
    ihdr.extend_from_slice(&(height as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
    png_chunk(&mut out, b"IHDR", &ihdr);
    png_chunk(&mut out, b"IDAT", &z);
    png_chunk(&mut out, b"IEND", &[]);
    out
}

/// White 120x120 tile with a filled black rectangle. When `speck` is set, one
/// isolated mid-dark pixel far from the rectangle adds a sub-pixel ring.
fn tile(speck: bool) -> Vec<u8> {
    let (w, h) = (120usize, 120usize);
    let mut px = vec![255u8; w * h];
    for y in 30..=90 {
        for x in 40..=70 {
            px[y * w + x] = 0;
        }
    }
    if speck {
        px[20 * w + 100] = 60;
    }
    gray_png(w, h, &px)
}

fn copy_tree(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap_or_else(|e| panic!("create {}: {e}", dst.display()));
    for entry in fs::read_dir(src).unwrap_or_else(|e| panic!("read {}: {e}", src.display())) {
        let entry = entry.unwrap();
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() {
            copy_tree(&from, &to);
        } else {
            fs::copy(&from, &to).unwrap_or_else(|e| panic!("copy {} -> {}: {e}", from.display(), to.display()));
        }
    }
}

fn run_engine(bin: &Path, manifest: &Path, out_dir: &Path) {
    let output = Command::new(bin)
        .arg(manifest)
        .arg(out_dir)
        .arg("--style-id")
        .arg("Marq-Regular")
        // The fixture's notdef evidence is intentionally unresolved; these two
        // explicit export intents keep that path shippable without changing
        // geometry, kern, or spacing emission.
        .arg("--allow-partial")
        .arg("--fallback-export-warn")
        .output()
        .unwrap_or_else(|e| panic!("spawn engine: {e}"));
    assert!(
        output.status.success(),
        "engine run failed for manifest {}\nstdout:\n{}\nstderr:\n{}",
        manifest.display(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn artifact(dir: &Path, name: &str) -> Vec<u8> {
    fs::read(dir.join(name)).unwrap_or_else(|e| panic!("read {} from {}: {e}", name, dir.display()))
}

fn unique_work_dir(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "kni_stage1_replay_e2e_{}_{}_{}",
        tag,
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}

/// Runs live, then replay from the live cache. Returns (live dir, replay dir).
/// The replay writes to the same output path the live run used (the live
/// outputs are moved aside first), so output paths in the receipt match.
fn live_then_replay(work: &Path) -> (PathBuf, PathBuf) {
    let bin = Path::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    let out = work.join("out");
    let live_out = work.join("out-live");

    run_engine(bin, &work.join("manifest.txt"), &out);
    let cache = work.join("stage1-cache-live.txt");
    fs::copy(out.join("stage1-cache.txt"), &cache).expect("live run must write stage1-cache.txt");
    fs::rename(&out, &live_out).expect("move live outputs aside");

    let mut replay_manifest = fs::read_to_string(work.join("manifest.txt")).expect("read live manifest");
    replay_manifest.push_str("stage1_cache stage1-cache-live.txt\n");
    let replay_manifest_path = work.join("manifest-replay.txt");
    fs::write(&replay_manifest_path, replay_manifest).expect("write replay manifest");
    run_engine(bin, &replay_manifest_path, &out);
    (live_out, out)
}

fn assert_replay_matches(live: &Path, replay: &Path) {
    for name in ARTIFACTS {
        assert_eq!(
            artifact(replay, name),
            artifact(live, name),
            "replay output {name} must be byte-identical to the live run"
        );
    }
    let live_receipt = String::from_utf8(artifact(live, receipt_name())).expect("receipt is utf-8");
    let replay_receipt = String::from_utf8(artifact(replay, receipt_name())).expect("receipt is utf-8");
    let (l, r) = (comparable_receipt(&live_receipt), comparable_receipt(&replay_receipt));
    let mut diffs = Vec::new();
    for i in 0..l.len().max(r.len()) {
        let (a, b) = (l.get(i), r.get(i));
        if a != b {
            diffs.push(format!("line {i}\n  live:   {}\n  replay: {}", a.map_or("<none>", |s| s.as_str()), b.map_or("<none>", |s| s.as_str())));
        }
    }
    assert!(diffs.is_empty(), "receipt differs between live and replay outside the masked lines:\n{}", diffs.join("\n"));
}

fn receipt_row(dir: &Path, prefix: &str) -> String {
    let text = String::from_utf8(artifact(dir, receipt_name())).expect("receipt is utf-8");
    text.lines().find(|l| l.starts_with(prefix)).unwrap_or_else(|| panic!("receipt has no {prefix} row")).to_string()
}

#[test]
fn stage1_cache_replay_reproduces_live_run_byte_for_byte() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let work = unique_work_dir("fixture");
    copy_tree(&fixture, &work);
    let (live, replay) = live_then_replay(&work);
    assert_replay_matches(&live, &replay);
    let _ = fs::remove_dir_all(&work);
}

#[test]
fn stage1_cache_replay_with_speck_reproduces_live_run() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let work = unique_work_dir("speck");
    copy_tree(&fixture, &work);
    // Replace both tiles; the first one carries the speck.
    fs::write(work.join("glyph/t43.png"), tile(true)).unwrap();
    fs::write(work.join("glyph/t44.png"), tile(false)).unwrap();
    let (live, replay) = live_then_replay(&work);

    // Guard the case itself: the live run must have retained a speck.
    let live_row = receipt_row(&live, "sub_pixel_speck_retained\t");
    assert!(
        live_row.starts_with("sub_pixel_speck_retained\tcount\t1\t"),
        "fixture must produce exactly one speck on the live run: {live_row}"
    );
    // The speck row is labeled live-only and so masked below, but the replay
    // restores it from the cache; a changed count would be a dropped speck.
    let replay_row = receipt_row(&replay, "sub_pixel_speck_retained\t");
    assert_eq!(replay_row, live_row, "replay must report the same retained specks");

    assert_replay_matches(&live, &replay);
    let _ = fs::remove_dir_all(&work);
}
