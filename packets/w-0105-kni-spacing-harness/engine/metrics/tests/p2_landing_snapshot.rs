//! P2 run3 landing data snapshot (legacy witness).
//!
//! Data class: the fixture is a SOURCE-GATE-BYPASSED PROBE diagnostic
//! ledger, unvalidated diagnostic output, preserved verbatim as the
//! landing data snapshot of the run3 kern diagnostic.
//!
//! These tests are a witness over that frozen snapshot. They are NOT a
//! quality gate: they call no production code and prove nothing about
//! repaired behavior. Their only job is to make any drift of the snapshot
//! a deliberate, reviewable diff.
//!
//! Post-repair direction (tracked separately): once the solver collision
//! constraint and the export guard are unified on the same geometry, the
//! new solver and guard must produce a gap that agrees with the measured
//! gap on the same geometry. The mismatch row recorded here is then
//! expected to change and updating this snapshot becomes a reviewed diff.
//! The Eacute/u hold recorded below is observed diagnostic state, not an
//! invariant target.

use std::path::PathBuf;

/// Fixture byte identity: sha256 of the preserved diagnostic ledger.
const FIXTURE_SHA256: &str =
    "786e50ebb7e692514a4b71d6a4549494b0976b98facd63c866e666ebf2f2a942";

/// Exact fixture header: all 21 field names, in order.
const HEADER: &str = "bucket\tleft\tright\tresidual\texport_value\texport_distance\tsolver_wall_gap\tgap_at_origin\tgap_at_export\twmean_origin\twmean_export\tink_intersects\tleft_lsb\tleft_ink_xmin\tleft_advance\tleft_x_translation\tright_lsb\tright_ink_xmin\tright_advance\tright_x_translation\tnote";

struct Row {
    bucket: String,
    left: String,
    right: String,
    residual: f64,
    export_distance: f64,
    solver_wall_gap: String,
    gap_at_origin: String,
    ink_intersects: bool,
    left_advance: f64,
    note: String,
}

impl Row {
    /// Post-kern ledger margin: signed slack of the rounded export distance
    /// over the exact left advance plus residual.
    fn margin(&self) -> f64 {
        self.export_distance - (self.left_advance + self.residual)
    }
}

/// Minimal SHA-256 (FIPS 180-4) so the fixture identity check runs without
/// dependencies. Gated against the published empty and "abc" vectors in
/// `run3_snapshot_fixture_integrity` before any fixture bytes are trusted.
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for block in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, c) in block.chunks_exact(4).enumerate() {
            w[i] = u32::from_be_bytes([c[0], c[1], c[2], c[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) =
            (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
    let mut out = String::with_capacity(64);
    for word in h {
        out.push_str(&format!("{word:08x}"));
    }
    out
}

fn fixture_bytes() -> Vec<u8> {
    std::fs::read(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests")
            .join("fixtures")
            .join("p2-hold-diagnostic.tsv"),
    )
    .expect("p2 landing snapshot fixture must be readable")
}

fn load_rows(text: &str) -> Vec<Row> {
    let mut lines = text.lines();
    let header = lines.next().expect("fixture must have a header row");
    assert_eq!(
        header, HEADER,
        "fixture header drifted: expected the exact 21-field ledger header"
    );
    lines
        .map(|line| {
            let c: Vec<&str> = line.split('\t').collect();
            assert_eq!(c.len(), 21, "fixture row must have 21 columns: {line}");
            Row {
                bucket: c[0].to_string(),
                left: c[1].to_string(),
                right: c[2].to_string(),
                residual: c[3].parse().expect("residual must parse as f64"),
                export_distance: c[5].parse().expect("export_distance must parse as f64"),
                solver_wall_gap: c[6].to_string(),
                gap_at_origin: c[7].to_string(),
                ink_intersects: c[11].parse().expect("ink_intersects must parse as bool"),
                left_advance: c[14].parse().expect("left_advance must parse as f64"),
                note: c[20].to_string(),
            }
        })
        .collect()
}

#[test]
fn run3_snapshot_fixture_integrity() {
    // Gate the in-file hash on the published FIPS vectors first.
    assert_eq!(
        sha256_hex(b""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    assert_eq!(
        sha256_hex(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    let bytes = fixture_bytes();
    assert_eq!(
        sha256_hex(&bytes),
        FIXTURE_SHA256,
        "landing snapshot bytes drifted"
    );
}

#[test]
fn run3_snapshot_distribution_witness() {
    let bytes = fixture_bytes();
    let text = String::from_utf8(bytes).expect("fixture must be UTF-8");
    let rows = load_rows(&text);
    let ready = rows.iter().filter(|r| r.bucket == "ready").count();
    let holds: Vec<&Row> = rows.iter().filter(|r| r.bucket == "overlap_hold").collect();
    assert_eq!(rows.len(), 30, "snapshot row count drifted");
    assert_eq!(ready, 12, "snapshot ready count drifted");
    assert_eq!(holds.len(), 18, "snapshot overlap_hold count drifted");

    let intersects: Vec<&&Row> = holds.iter().filter(|r| r.ink_intersects).collect();
    assert_eq!(
        intersects.len(),
        17,
        "snapshot intersect-hold count drifted (non-intersect holds: {:?})",
        holds
            .iter()
            .filter(|r| !r.ink_intersects)
            .map(|r| format!("{}/{}", r.left, r.right))
            .collect::<Vec<_>>()
    );

    // Observed state: every intersect-hold shows a negative post-kern
    // ledger margin (rounded export distance lands left of advance +
    // residual). Evidence of leftward double-rounding displacement, not
    // proof that exact-origin geometry was intersection-free.
    let mut margins: Vec<f64> = intersects.iter().map(|r| r.margin()).collect();
    margins.sort_by(f64::total_cmp);
    assert!(
        margins.iter().all(|m| *m < 0.0),
        "snapshot intersect-hold margins must be negative; observed min {:?} max {:?}",
        margins.first(),
        margins.last()
    );
}

#[test]
fn run3_snapshot_eacute_u_mismatch_witness() {
    let bytes = fixture_bytes();
    let text = String::from_utf8(bytes).expect("fixture must be UTF-8");
    let rows = load_rows(&text);
    let matches: Vec<&Row> = rows
        .iter()
        .filter(|r| r.left == "Eacute" && r.right == "u")
        .collect();
    assert_eq!(matches.len(), 1, "exactly one Eacute/u snapshot row");
    let row = matches[0];

    // Legacy witness of the unrepaired diagnostic state: solver wall gap 0
    // versus measured exact-origin gap 4.999999999999943, recorded as a
    // solver/measured disagreement hold. This is the observed snapshot
    // state only; after solver/guard unification the same geometry must
    // agree and this row is expected to change. Exact evidence strings are
    // pinned, not re-derived.
    assert_eq!(row.bucket, "overlap_hold", "snapshot state drifted");
    assert_eq!(row.solver_wall_gap, "0");
    assert_eq!(row.gap_at_origin, "Some(4.999999999999943)");
    assert!(!row.ink_intersects);
    assert!(
        row.note.contains("disagree"),
        "snapshot row note drifted, got: {}",
        row.note
    );
    assert!(
        row.margin() > 0.0,
        "snapshot Eacute/u margin drifted (observed {})",
        row.margin()
    );
}
