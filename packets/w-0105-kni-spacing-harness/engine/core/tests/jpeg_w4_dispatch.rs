//! W4: non-subset JPEGs get typed refusals on both the SOF0 and SOF2 paths through
//! `decode_source`, and the pinned Paul 136-JPEG bundle (tests/fixtures/paul136, no env config)
//! passes the decoder. Corpus test is #[ignore]: run `cargo test --test jpeg_w4_dispatch -- --ignored --nocapture`.
use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::{decode_source, DispatchError};
use kni_core::jpeg_source::{JpegError, Limits};
use std::path::PathBuf;

fn jl() -> Limits { Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 28 } }
fn pl() -> DecodeLimits { DecodeLimits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 24 } }
fn fx(n: &str) -> Vec<u8> {
    std::fs::read(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/jpeg_progressive").join(n)).unwrap()
}
fn run(b: &[u8]) -> Result<(), JpegError> {
    match decode_source(b, &pl(), jl()) { Ok(_) => Ok(()), Err(DispatchError::Jpeg(e)) => Err(e), Err(e) => panic!("untyped: {e:?}") }
}
fn sof(b: &[u8]) -> usize {
    (2..b.len() - 1).find(|&i| b[i] == 0xFF && matches!(b[i + 1], 0xC0 | 0xC2)).unwrap()
}

/// Every mutation must differ from the control and the control must decode.
fn check_family(name: &str) {
    let ctl = fx(name);
    assert_eq!(run(&ctl), Ok(()), "{name} control");
    let p = sof(&ctl);
    let mut cases: Vec<(&str, Vec<u8>, JpegError)> = Vec::new();
    for (lbl, m) in [("sof3_lossless", 0xC3u8), ("sof1_extended", 0xC1), ("sof9_arith", 0xC9), ("sof10_arith_prog", 0xCA)] {
        let mut b = ctl.clone(); b[p + 1] = m; cases.push((lbl, b, JpegError::UnsupportedMode));
    }
    let mut b = ctl.clone(); b[p + 4] = 12; cases.push(("precision12", b, JpegError::UnsupportedPrecision));
    for (lbl, mutated, want) in cases {
        assert_ne!(mutated, ctl, "{name} {lbl} unchanged");
        assert_eq!(run(&mutated), Err(want), "{name} {lbl}");
    }
    // unsupported signature stays typed at dispatch level.
    assert!(matches!(decode_source(b"GIF89a", &pl(), jl()), Err(DispatchError::UnsupportedSignature)));
}
#[test] fn non_subset_typed_refusal_sof0() { check_family("gray_17x13.base.jpg"); check_family("ycbcr_420_35x27.base.jpg"); }
#[test] fn non_subset_typed_refusal_sof2() { check_family("gray_17x13.prog.jpg"); check_family("ycbcr_420_35x27.prog.jpg"); }

/// Rebuild the SOF segment with `nf` components. `valid_len` true: segment length matches nf
/// (structurally valid 4-component frame, e.g. CMYK/YCCK); false: only nf byte changed (length mismatch).
fn with_nf(ctl: &[u8], nf: u8, valid_len: bool) -> Vec<u8> {
    let p = sof(ctl);
    let old_len = u16::from_be_bytes([ctl[p + 2], ctl[p + 3]]) as usize;
    let mut b = ctl[..p + 2].to_vec();
    if valid_len {
        b.extend_from_slice(&((8 + 3 * nf as usize) as u16).to_be_bytes());
        b.extend_from_slice(&ctl[p + 4..p + 9]); // precision, height, width
        b.push(nf);
        for i in 0..nf { b.extend_from_slice(&[i + 1, 0x11, 0]); }
    } else {
        b.extend_from_slice(&ctl[p + 2..p + 2 + old_len]);
        b[p + 9] = nf;
    }
    b.extend_from_slice(&ctl[p + 2 + old_len..]);
    b
}
#[test] fn four_component_structurally_valid_is_unsupported_colour_both_paths() {
    // The decoder has no UnsupportedComponents variant: nf not in {1,3} is JpegError::UnsupportedColour.
    for name in ["gray_17x13.base.jpg", "gray_17x13.prog.jpg"] {
        let ctl = fx(name);
        let b = with_nf(&ctl, 4, true);
        assert_ne!(b, ctl);
        assert_eq!(run(&b), Err(JpegError::UnsupportedColour), "{name} valid nf=4");
    }
}
#[test] fn nf_byte_only_mutation_is_typed_both_paths() {
    // Length mismatch with nf=4: observed typed error, asserted exactly per path.
    for name in ["gray_17x13.base.jpg", "gray_17x13.prog.jpg"] {
        let ctl = fx(name);
        let b = with_nf(&ctl, 4, false);
        assert_ne!(b, ctl);
        let e = run(&b).expect_err("nf-only mutation accepted");
        assert_eq!(e, JpegError::UnsupportedColour, "{name}: got {e:?}");
    }
}

const BUNDLE: &str = "tests/fixtures/paul136";
/// sha256 of tests/fixtures/paul136/INDEX.sha256 (sorted "<sha256>  <name>" lines, 136 entries).
const INDEX_SHA256: &str = "23081b9f68567a264e4c5b7a3babf6721dbf304bd69842617523efd688f5a4fb";
/// Source tgz the bundle was unpacked from (flattened): KNI-PAUL-136-ORIGINAL-JPEG-0338-e18b159c.tgz
/// sha256 6b9517f6a5072c232f50a044e865a1221022754cdbbaa82020b6f7b913a924c1.
#[test] #[ignore = "run explicitly: cargo test --test jpeg_w4_dispatch -- --ignored --nocapture"]
fn paul_136_bundle_decodes() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(BUNDLE);
    let idx = std::fs::read(root.join("INDEX.sha256")).unwrap();
    assert_eq!(kni_core::reference_transfer::sha256_hex(&idx), INDEX_SHA256, "index pin");
    let idx = String::from_utf8(idx).unwrap();
    let entries: Vec<(&str, &str)> = idx.lines().map(|l| { let (h, n) = l.split_once("  ").unwrap(); (h, n) }).collect();
    assert_eq!(entries.len(), 136);
    let mut on_disk: Vec<String> = std::fs::read_dir(&root).unwrap().filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| n.ends_with(".jpg")).collect();
    on_disk.sort();
    let mut listed: Vec<String> = entries.iter().map(|e| e.1.to_string()).collect();
    listed.sort();
    assert_eq!(on_disk, listed, "file set differs from index");
    let (mut ok, mut prog, mut base, mut bad) = (0usize, 0usize, 0usize, Vec::new());
    for (h, n) in &entries {
        let b = std::fs::read(root.join(n)).unwrap();
        assert_eq!(kni_core::reference_transfer::sha256_hex(&b), *h, "{n} hash");
        if kni_core::jpeg_progressive::is_progressive(&b) { prog += 1 } else { base += 1 }
        match decode_source(&b, &pl(), jl()) {
            Ok(d) => {
                assert_eq!(d.gray.len(), d.width * d.height);
                assert_eq!(d.receipt.jpeg_identity.as_ref().unwrap().orig_sha256, *h, "{n} receipt hash");
                ok += 1
            }
            Err(e) => bad.push(format!("{n}: {e:?}")),
        }
    }
    eprintln!("paul bundle: files={} decoded={ok} progressive={prog} baseline={base} refused={}", entries.len(), bad.len());
    assert!(bad.is_empty(), "refused:\n{}", bad.join("\n"));
}
