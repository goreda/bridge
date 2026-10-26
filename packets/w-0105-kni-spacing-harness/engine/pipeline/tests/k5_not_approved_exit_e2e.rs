//! r4 gate test built from the v3 sweep helpers. DEV candidate (never compiled by its author). SEARCH harness, not a gate: finds a synthetic population whose
//! spacing-pair-ledger.tsv has at least one UNRESOLVED reason (no_feasible, no_accepted_candidate, not_converged,
//! nonfinite_failure, natural_unverifiable, natural_frame_conflict), so the failed-path assertions of
//! k5_main_wire_e2e.rs stop being vacuous. Run once, send the printed SWEEP lines back, then the winning variant is frozen
//! into a normal test. Reuses the in-tree fixture and the PNG writer pattern of tests/stage1_replay_e2e.rs.
//! Run: cargo test -p kni-pipeline --test k5_unresolved_sweep -- --ignored --nocapture
//! Every variant prints one line: SWEEP <name> exit=<code> ledger_rows=<n> reasons=<code:count,...> or the first stderr line.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data { crc ^= b as u32; for _ in 0..8 { crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 }; } }
    !crc
}
fn png_chunk(out: &mut Vec<u8>, kind: &[u8; 4], body: &[u8]) {
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    let mut t = kind.to_vec(); t.extend_from_slice(body);
    out.extend_from_slice(&t); out.extend_from_slice(&crc32(&t).to_be_bytes());
}
fn gray_png(w: usize, h: usize, px: &[u8]) -> Vec<u8> {
    let mut raw = Vec::new();
    for row in px.chunks(w) { raw.push(0); raw.extend_from_slice(row); }
    let mut z = vec![0x78, 0x01];
    let blocks: Vec<&[u8]> = raw.chunks(65535).collect();
    for (i, b) in blocks.iter().enumerate() {
        z.push(if i + 1 == blocks.len() { 1 } else { 0 });
        z.extend_from_slice(&(b.len() as u16).to_le_bytes());
        z.extend_from_slice(&(!(b.len() as u16)).to_le_bytes());
        z.extend_from_slice(b);
    }
    let (mut a, mut b) = (1u32, 0u32);
    for &x in &raw { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
    z.extend_from_slice(&((b << 16) | a).to_be_bytes());
    let mut out = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&(w as u32).to_be_bytes()); ihdr.extend_from_slice(&(h as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
    png_chunk(&mut out, b"IHDR", &ihdr); png_chunk(&mut out, b"IDAT", &z); png_chunk(&mut out, b"IEND", &[]);
    out
}
/// 120x120 white tile with the union of black rectangles (x0, x1, y0, y1), all inclusive.
fn tile(rects: &[(usize, usize, usize, usize)]) -> Vec<u8> {
    let (w, h) = (120usize, 120usize);
    let mut px = vec![255u8; w * h];
    for &(x0, x1, y0, y1) in rects { for y in y0..=y1 { for x in x0..=x1 { px[y * w + x] = 0; } } }
    gray_png(w, h, &px)
}
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h: [u32; 8] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let mut m = data.to_vec();
    m.push(0x80);
    while m.len() % 64 != 56 { m.push(0); }
    m.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in m.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([chunk[4*i], chunk[4*i+1], chunk[4*i+2], chunk[4*i+3]]); }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let mj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(mj);
            v[7] = v[6]; v[6] = v[5]; v[5] = v[4]; v[4] = v[3].wrapping_add(t1);
            v[3] = v[2]; v[2] = v[1]; v[1] = v[0]; v[0] = t1.wrapping_add(t2);
        }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}
struct Lcg(u64);
impl Lcg { fn next(&mut self, lo: usize, hi: usize) -> usize { self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407); lo + ((self.0 >> 33) as usize) % (hi - lo + 1) } }

fn copy_tree(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap();
    for e in fs::read_dir(src).unwrap() {
        let e = e.unwrap(); let to = dst.join(e.file_name());
        if e.path().is_dir() { copy_tree(&e.path(), &to); } else { fs::copy(e.path(), &to).unwrap(); }
    }
}



type Shape = Vec<(usize, usize, usize, usize)>;
fn seeded_shapes(seed: u64) -> Vec<Shape> {
    let mut r = Lcg(seed);
    (0..8).map(|_| {
        let x0 = r.next(2, 70); let x1 = (x0 + r.next(2, 45)).min(117);
        let y0 = r.next(2, 60); let y1 = (y0 + r.next(4, 55)).min(117);
        let mut s = vec![(x0, x1, y0, y1)];
        if r.next(0, 1) == 1 { let a0 = r.next(2, 90); s.push((a0, (a0 + r.next(2, 25)).min(117), r.next(2, 100), r.next(60, 117))); }
        s
    }).collect()
}
const UNRESOLVED: [&str; 7] = [
    "no_feasible", "no_accepted_candidate", "not_converged",
    "nonfinite_failure", "natural_unverifiable", "natural_frame_conflict", "excluded_unmeasurable",
];

/// Seeds 1..4 at default resolution gave excluded_unmeasurable rows 4/6/4/18 on Team 8's v3 run (a measured fact about
/// that run, same engine bytes). The assertions below are non-vacuous only if the ledger really has such a row, and the
/// test checks that first, so it cannot pass vacuously: it fails loudly if the shapes stop producing unmeasurable pairs.
/// r5: asserts the chief decision (no release OTF when unresolved rows exist); today's engine publishes the OTF as normal, so the OTF assertion is RED BY DESIGN and names the engine gap.
/// Needs the patched adapter (patch 04 or its Team 9 successor) built in; on the baseline it fails at export-gate-pairs.tsv.
#[test]
fn not_approved_row_means_exit_3_and_reports_exist() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    for seed in 1..=4u64 {
        let mut shapes = seeded_shapes(seed);
        // Needle pair (policy-update fix): tier-2b natural-clear closes the old
        // seed-only unmeasurable population, so this pair is engineered to stay
        // unresolved - y-extents overlap by only 2 rows (58,59), far below the
        // shared-row evidence floor, so the pair must remain excluded_unmeasurable
        // and the test cannot go vacuous. If a future policy closes even this,
        // the loud vacuousness panic below fires again by design.
        shapes.push(vec![(10, 60, 20, 59)]);
        shapes.push(vec![(10, 60, 58, 100)]);
        let work: PathBuf = std::env::temp_dir().join(format!("kni-k5-unmeas-{}-{}", std::process::id(), seed));
        let _ = fs::remove_dir_all(&work);
        copy_tree(&fixture, &work);
        let mut manifest = String::new();
        for line in fs::read_to_string(work.join("manifest.txt")).unwrap().lines() {
            if line.starts_with("glyph ") || line.starts_with("population_sha256") || line.starts_with("pair_min_shared_rows") { continue; }
            manifest.push_str(line); manifest.push('\n');
        }
        let mut rows: Vec<String> = Vec::new();
        for (i, shape) in shapes.iter().enumerate() {
            let c = 0x43u32 + i as u32;
            fs::write(work.join(format!("glyph/t{:x}.png", c)), tile(shape)).unwrap();
            manifest.push_str(&format!("glyph 0x{:X} t{:x} glyph/t{:x}.png\n", c, c, c));
            rows.push(format!("{:x}:t{:x}\n", c, c));
        }
        // Force the unmeasurable lane: no pair can show a million shared scan
        // rows, so above-epsilon pairs must surface as excluded_unmeasurable -
        // the unresolved-row population this test exists to check the gate on.
        manifest.push_str("pair_min_shared_rows 1000000\n");
        rows.sort();
        manifest.push_str(&format!("population_sha256 {}\n", sha256_hex(rows.concat().as_bytes())));
        fs::write(work.join("manifest.txt"), manifest).unwrap();
        let out = work.join("out");
        let o = Command::new(Path::new(env!("CARGO_BIN_EXE_kni-pipeline")))
            .arg(work.join("manifest.txt")).arg(&out).arg("--style-id").arg("Marq-Regular")
            .arg("--allow-partial").arg("--fallback-export-warn").output().expect("spawn");
        // r5 (chief decision 16:06:35, peer-reported): unresolved rows mean NO release OTF. Exit status is not constrained here
        // (a refusal is allowed), but the reports below must exist: a refusal before any ledger would leave nothing to check.
        let exit_note = format!("exit={:?} stderr_tail={}", o.status.code(), String::from_utf8_lossy(&o.stderr).lines().last().unwrap_or(""));

        let ledger = fs::read_to_string(out.join("spacing-pair-ledger.tsv")).unwrap();
        let unresolved: Vec<String> = ledger.lines().skip(1).filter_map(|l| {
            let c: Vec<&str> = l.split('\t').collect();
            if c.len() >= 4 && UNRESOLVED.contains(&c[3]) { Some(format!("{}|{}|{}\t{}", c[0], c[1], c[2], c[3])) } else { None }
        }).collect();
        assert!(!unresolved.is_empty(), "seed {seed}: ledger has no unresolved row, so this test would be vacuous (shapes no longer give unmeasurable pairs)");

        let gate = fs::read_to_string(out.join("export-gate-pairs.tsv")).expect("export-gate-pairs.tsv missing: adapter not wired");
        for u in &unresolved {
            let (pair, reason) = u.split_once('\t').unwrap();
            let want = format!("{}\tfailed\t{}", pair.trim(), reason);
            // Duplicate names collapse in the gate (first wins), so a duplicate may appear as duplicate_pair_name: accept either form.
            assert!(gate.lines().any(|l| l == want) || gate.lines().any(|l| l.starts_with(pair.trim()) && l.contains("duplicate_pair_name")),
                "seed {seed}: unresolved pair not reported failed: {want}");
        }
        let receipt = fs::read_to_string(out.join("receipt-Marq-Regular.txt")).unwrap_or_else(|_| panic!("seed {seed}: receipt missing ({exit_note})"));
        // No approved/release OTF. Carrier (chief decision relayed 16:10:26, peer-reported): exactly one receipt row
        // export_gate<TAB>diagnostic<TAB>not_approved<TAB>reason<TAB><code>, code non-empty. No file name or path encoding.
        let otfs: Vec<String> = fs::read_dir(&out).unwrap().filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().to_string()).filter(|n| n.ends_with(".otf")).collect();
        let diag_rows: Vec<Vec<&str>> = receipt.lines().map(|l| l.split('\t').collect::<Vec<&str>>())
            .filter(|f| f.len() == 5 && f[0] == "export_gate" && f[1] == "diagnostic" && f[2] == "not_approved" && f[3] == "reason" && !f[4].is_empty())
            .collect();
        if !otfs.is_empty() {
            assert_eq!(o.status.code(), Some(3), "seed {seed}: not_approved row + .otf must exit 3 ({exit_note})");
            assert!(String::from_utf8_lossy(&o.stderr).contains("not_approved"), "seed {seed}: stderr must name not_approved");
            assert!(diag_rows.len() == 1,
                "ENGINE GAP (red by design): seed {seed}: {otfs:?} exist although {} unresolved pair(s) exist, and the receipt has {} export_gate diagnostic not_approved reason rows (need exactly 1)",
                unresolved.len(), diag_rows.len());
        }
        let row = receipt.lines().find(|l| l.starts_with("export_gate_pairs\tsubmitted\t")).expect("no export_gate_pairs receipt row");
        assert!(row.contains("complete\tfalse"), "seed {seed}: gate must be incomplete with unresolved pairs: {row}");
        assert!(receipt.contains("partial_output\ttrue\treason\texport_gate_pairs_failed"), "seed {seed}: partial marker missing");
    }
}
