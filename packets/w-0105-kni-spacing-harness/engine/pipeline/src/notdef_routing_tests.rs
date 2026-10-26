//! Routing tests: manifest grammar, .notdef identity, and the two FINAL2 notdef routes.
//!
//! Pixel-evidence route: `capture_manifest` + `notdef evidence` rows ->
//! DetectionState::PixelEvidence. Repeated-form winning-group codepoints MAY
//! also appear as glyph rows: they ship as drawn glyphs with typed
//! placeholder_form flags (always-output ruling; blank-cell claims keep the
//! reject_placeholder_population typed gate). Blank advance is the font's
//! widest character advance; there is no space binding anywhere
//! (space_evidence_sha256 is a grammar refusal). The producer (notdef_producer,
//! claim-only) packages claims; bound_detector_validator::load decodes the whole
//! population once and verifies them (form hash, blank consistency, frequency,
//! unique winner, pixel_source == winning group).
//!
//! Proxy route (legacy-shape manifests only): `notdef_proxy <rule> <form-sha>
//! 0x<cp>` with rule in {legacy-largest-repeat-proxy, most-frequent-pixel-hash};
//! notdef_proxy::select decodes the glyph population and verifies the
//! most-frequent form claim. Proxy and evidence rows are mutually exclusive.
//!
//! These tests build the STAGED layout (post-stage_notdef.py) directly: the
//! stager is kit-side Python and is covered by its own scenario matrix; the
//! contract asserted here is the byte-exact staged shape the engine consumes.
//!
//! Verification limit: this module is API-matched against main.rs +
//! bound_detector_validator.rs + notdef_producer.rs by reading, but the full
//! crate (notdef_caller, space_evidence, space_spec, iou_population, kern
//! modules) is not part of this delivery, so it cannot be compiled here. It
//! must be run with `cargo test` after landing. Blank-cell assertions follow
//! the FINAL2 rule (no space binding anywhere); they require the matching
//! validator respin.
use super::*;

/// Minimal 8-bit grayscale PNG writer (stored deflate blocks) so tests can mint
/// tiles with controlled pixels: identical pixels with different bytes (the
/// byte-pin vs form-hash split) and arbitrary distinct forms.
fn crc32(bytes: &[u8]) -> u32 {
    let mut c: u32 = 0xFFFF_FFFF;
    for &b in bytes {
        c ^= b as u32;
        for _ in 0..8 { c = if c & 1 != 0 { (c >> 1) ^ 0xEDB8_8320 } else { c >> 1 }; }
    }
    !c
}
fn chunk(tag: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut out = (data.len() as u32).to_be_bytes().to_vec();
    out.extend_from_slice(tag);
    out.extend_from_slice(data);
    let mut crc_in = tag.to_vec(); crc_in.extend_from_slice(data);
    out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
    out
}
fn png_gray(width: u32, height: u32, gray: &[u8], tag: Option<&str>) -> Vec<u8> {
    assert_eq!(gray.len(), (width * height) as usize);
    let mut raw = Vec::new();
    for row in 0..height as usize {
        raw.push(0u8); // filter: none
        raw.extend_from_slice(&gray[row * width as usize..(row + 1) * width as usize]);
    }
    let mut z = vec![0x78u8, 0x01]; // zlib: deflate, 32K window, check
    let mut rest = raw.as_slice();
    loop {
        let n = rest.len().min(65535);
        let last = n == rest.len();
        z.push(if last { 1 } else { 0 });
        z.extend_from_slice(&(n as u16).to_le_bytes());
        z.extend_from_slice(&(!(n as u16)).to_le_bytes());
        z.extend_from_slice(&rest[..n]);
        rest = &rest[n..];
        if last { break; }
    }
    let mut a: u32 = 1; let mut b: u32 = 0; // adler32 of the raw scanlines
    for &x in &raw { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
    z.extend_from_slice(&((b << 16) | a).to_be_bytes());
    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    let mut ihdr = width.to_be_bytes().to_vec();
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.extend_from_slice(&[8, 0, 0, 0, 0]); // 8-bit grayscale
    png.extend_from_slice(&chunk(b"IHDR", &ihdr));
    if let Some(t) = tag {
        let mut tex = b"Comment".to_vec(); tex.push(0); tex.extend_from_slice(t.as_bytes());
        png.extend_from_slice(&chunk(b"tEXt", &tex));
    }
    png.extend_from_slice(&chunk(b"IDAT", &z));
    png.extend_from_slice(&chunk(b"IEND", &[]));
    png
}

const TEST_LIMITS: Limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };

/// Form identity exactly as the validator defines it.
fn form_sha(png: &[u8]) -> String {
    let d = kni_core::capture_dispatch::decode_source(png, &PNG_DECODE_LIMITS, TEST_LIMITS).unwrap();
    bound_detector_validator::pixel_form_sha256(d.width, d.height, &d.gray).unwrap()
}

fn test_dir(tag: &str) -> PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    let d = std::env::temp_dir().join(format!("kni-routing-{}-{}-{tag}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
    fs::create_dir_all(&d).unwrap();
    d
}

fn manifest_prefix() -> String {
    format!("run_mode full\nfamily Test\nsubfamily Regular\npostscript_name Test-Regular\nupm 1000\nscale 2\ncapture_frame f1\nfit_tolerance_policy fixed\npopulation_sha256 {}\n", "0".repeat(64))
}

fn rc_for(m: &Manifest, capture_dir: &Path) -> run_config::RunConfig {
    let ctx = kni_core::scale_context::ScaleContext::from_convention(
        "Test/Regular", "routing-test-v1", m.scale, f64::from(m.upm), "Test/Regular", "f1",
    ).unwrap();
    validated_run_config(m, ctx, capture_dir.to_path_buf(), capture_dir.join("out"), "s1").unwrap()
}

#[cfg(test)]
mod notdef_identity_tests {
    use super::*;
    fn manifest(row: &str) -> Manifest {
        parse_manifest(&format!("run_mode full\nfamily T\nsubfamily Regular\npostscript_name T-Regular\nscale 1\nfit_tolerance_policy fixed\npopulation_sha256 {}\n{row}", "0".repeat(64)), Path::new(".")).unwrap()
    }
    #[test]
    fn glyph_cp0_exact_run_validation_error() {
        assert!(validate_manifest_identities(&manifest("glyph 0 zero z.png\n")).unwrap_err() == "bad_notdef::ReservedCodepoint");
    }
    #[test]
    fn space_cp0_exact_run_validation_error() {
        assert!(validate_manifest_identities(&manifest("glyph 41 a a.png\nspace 0 250\n")).unwrap_err() == "bad_notdef::ReservedCodepoint");
    }
}

#[cfg(test)]
mod notdef_manifest_tests {
    use super::*;
    fn prefix() -> String {
        format!("run_mode full\nfamily T\nsubfamily Regular\npostscript_name T-Regular\nscale 1\nfit_tolerance_policy fixed\npopulation_sha256 {}\nglyph 41 a a.png\n", "0".repeat(64))
    }
    #[test]
    fn malformed_notdef_rows_have_exact_error_types() {
        for row in [
            "notdef\n",
            "notdef blank\n",
            "notdef repeated x.png 250 3\n",
            "notdef evidence x bad S C 1 F\n",
        ] {
            assert_eq!(
                parse_manifest(&(prefix() + row), Path::new(".")).unwrap_err(),
                "bad_notdef::Grammar",
                "{row}"
            );
        }
        let row = format!(
            "notdef evidence evidence.tsv {} S C 1 frame\n",
            "a".repeat(64)
        );
        assert_eq!(
            parse_manifest(&(prefix() + &row + &row), Path::new(".")).unwrap_err(),
            "bad_notdef::Duplicate"
        );
    }
}

#[cfg(test)]
mod notdef_scalar_route_tests {
    use super::*;
    #[test]
    fn space_nonscalar_exact_run_validation_error() {
        let body = format!("run_mode full\nfamily T\nsubfamily Regular\npostscript_name T-Regular\nscale 1\nfit_tolerance_policy fixed\npopulation_sha256 {}\nglyph 41 a a.png\nspace 110000 250\n", "0".repeat(64));
        let m = parse_manifest(&body, Path::new(".")).unwrap();
        assert!(validate_manifest_identities(&m).unwrap_err() == "bad_notdef::InvalidCodepoint");
    }
    #[test]
    fn glyph_nonscalar_run_helper_rejects_even_if_parser_is_bypassed() {
        let body = format!("run_mode full\nfamily T\nsubfamily Regular\npostscript_name T-Regular\nscale 1\nfit_tolerance_policy fixed\npopulation_sha256 {}\nglyph 41 a a.png\n", "0".repeat(64));
        let mut m = parse_manifest(&body, Path::new(".")).unwrap();
        m.glyphs[0].codepoint = Some(0xd800);
        assert!(validate_manifest_identities(&m).unwrap_err() == "bad_notdef::InvalidCodepoint");
    }
}


#[cfg(test)]
mod notdef_capture_row_tests {
    use super::*;
    fn prefix() -> String {
        format!("run_mode full\nfamily T\nsubfamily Regular\npostscript_name T-Regular\nscale 1\nfit_tolerance_policy fixed\npopulation_sha256 {}\nglyph 41 a a.png\n", "0".repeat(64))
    }
    #[test]
    fn capture_manifest_rows_have_exact_error_types() {
        for row in ["capture_manifest\n", "capture_manifest only-path\n", "capture_manifest p s extra\n"] {
            assert_eq!(parse_manifest(&(prefix() + row), Path::new(".")).unwrap_err(), "bad_notdef::Grammar", "{row}");
        }
        let row = format!("capture_manifest cap.tsv {}\n", "a".repeat(64));
        assert_eq!(parse_manifest(&(prefix() + &row + &row), Path::new(".")).unwrap_err(), "bad_notdef::Duplicate");
    }
    #[test]
    fn notdef_evidence_binding_accepts_the_staged_row_shape() {
        let row = format!(
            "capture_manifest notdef/capture-manifest.tsv {0}\nnotdef evidence notdef/evidence.tsv {1} Test/Regular {0} 2 f1\n",
            "a".repeat(64), "b".repeat(64)
        );
        let m = parse_manifest(&(prefix() + &row), Path::new(".")).unwrap();
        assert!(m.capture_manifest.is_some() && m.notdef.is_some());
    }
}

#[cfg(test)]
mod notdef_real_caller_tests {
    use super::*;
    use bound_detector_validator::{Action, DetectionState, PixelContext, PixelNotdefKind, PIXEL_INK_MODEL};

    const GRAY_A: [u8; 64] = [7u8; 64]; // inked 8x8 form A
    const GRAY_B: [u8; 64] = [9u8; 64]; // inked 8x8 form B (different pixels)
    const BLANK: [u8; 64] = [255u8; 64]; // all-255 blank form

    /// Staged run root: ordinary glyph 0x43 + winner tiles 0x41/0x42 under notdef/,
    /// capture manifest, and (optionally via producer) the v3 evidence record.
    struct Fx {
        dir: PathBuf,
        w65: Vec<u8>,
        w66: Vec<u8>,
        cap_text: String,
        cap_sha: String,
    }
    fn fx(w65: Vec<u8>, w66: Vec<u8>, ordinary: Vec<u8>) -> Fx {
        let dir = test_dir("pixel-evidence");
        fs::create_dir_all(dir.join("glyph")).unwrap();
        fs::create_dir_all(dir.join("notdef")).unwrap();
        fs::write(dir.join("glyph/t67.png"), &ordinary).unwrap();
        fs::write(dir.join("notdef/w65"), &w65).unwrap();
        fs::write(dir.join("notdef/w66"), &w66).unwrap();
        let cap_text = format!(
            "kni-capture-manifest\tv1\nstyle\tTest/Regular\nframe\tf1\ncohort\tTest/Regular\nsource\t0x43\tglyph/t67.png\t{}\nsource\t0x41\tnotdef/w65\t{}\nsource\t0x42\tnotdef/w66\t{}\n",
            sha256_hex(&ordinary), sha256_hex(&w65), sha256_hex(&w66)
        );
        let cap_sha = sha256_hex(cap_text.as_bytes());
        fs::write(dir.join("notdef/capture-manifest.tsv"), &cap_text).unwrap();
        Fx { dir, w65, w66, cap_text, cap_sha }
    }
    fn inked_fx() -> Fx {
        // Same pixels, different container bytes: byte pins differ, the form is one group.
        fx(png_gray(8, 8, &GRAY_A, None), png_gray(8, 8, &GRAY_A, Some("copy")), png_gray(8, 8, &GRAY_B, None))
    }
    fn context(f: &Fx) -> PixelContext {
        PixelContext {
            style: "Test/Regular".into(), frame: "f1".into(), units_per_px: 2.0,
            source_sha256: sha256_hex(&f.w65), ink_model: PIXEL_INK_MODEL.into(),
        }
    }
    fn tiles<'a>(f: &'a Fx, ordinary: &'a [u8], kind: PixelNotdefKind) -> Vec<notdef_producer::Tile<'a>> {
        vec![
            notdef_producer::Tile { cp: 0x43, path: "glyph/t67.png", bytes: ordinary, role: None },
            notdef_producer::Tile { cp: 0x41, path: "w65", bytes: &f.w65, role: Some(kind) },
            notdef_producer::Tile { cp: 0x42, path: "w66", bytes: &f.w66, role: Some(kind) },
        ]
    }
    fn produce_into(f: &Fx, kind: PixelNotdefKind, form_claim: &str) -> String {
        let ordinary = fs::read(f.dir.join("glyph/t67.png")).unwrap();
        let ts = tiles(f, &ordinary, kind);
        let ctx = context(f);
        let req = notdef_producer::Request {
            context: &ctx, cohort: "Test/Regular", request_source: "routing-test",
            capture_record: f.cap_text.as_bytes(), capture_sha256: &f.cap_sha,
            space_evidence_sha256: None, pixel_form_sha256: form_claim, tiles: &ts, limits: TEST_LIMITS,
        };
        let produced = notdef_producer::produce(&req).unwrap();
        fs::write(f.dir.join("notdef/evidence.tsv"), &produced.evidence).unwrap();
        produced.evidence_sha
    }
    fn resolve(f: &Fx, evidence_sha: &str, extra_glyph_rows: &str) -> Result<DetectionState, String> {
        let manifest = format!(
            "{}{}glyph 0x43 u43 glyph/t67.png\ncapture_manifest notdef/capture-manifest.tsv {}\nnotdef evidence notdef/evidence.tsv {} Test/Regular {} 2 f1\n",
            manifest_prefix(), extra_glyph_rows, f.cap_sha, evidence_sha, f.cap_sha
        );
        let m = parse_manifest(&manifest, &f.dir).unwrap();
        let rc = rc_for(&m, &f.dir);
        resolve_notdef(&m, &rc, TEST_LIMITS)
    }

    #[test]
    fn pixel_evidence_route_end_to_end_repeated_form() {
        let f = inked_fx();
        let form = form_sha(&f.w65);
        assert_eq!(form, form_sha(&f.w66), "same pixels, different bytes: one form group");
        assert_ne!(sha256_hex(&f.w65), sha256_hex(&f.w66), "byte pins differ");
        let ev_sha = produce_into(&f, PixelNotdefKind::RepeatedForm, &form);
        let state = resolve(&f, &ev_sha, "").unwrap();
        let (kind, sources, claimed, ev) = match &state {
            DetectionState::PixelEvidence { kind, sources, pixel_form_sha256, evidence_sha256, .. } =>
                (kind, sources, pixel_form_sha256, evidence_sha256),
            other => panic!("expected PixelEvidence, got {other:?}"),
        };
        assert_eq!(*kind, PixelNotdefKind::RepeatedForm);
        assert_eq!(sources, &vec![0x41, 0x42], "winner group, sorted");
        assert_eq!(claimed, &form, "claimed form verified against decoded pixels");
        assert_eq!(ev, &ev_sha);
        // The placeholder gate passes: winner codepoints are not glyph rows.
        let m = parse_manifest(&format!("{}glyph 0x43 u43 glyph/t67.png\n", manifest_prefix()), &f.dir).unwrap();
        assert_eq!(reject_placeholder_population(&m.glyphs, sources), Ok(()));
        assert!(matches!(state.action(false, 1000.0), Ok(Action::PixelEvidence { .. })));
    }

    #[test]
    fn winner_codepoint_as_glyph_row_is_skipped_with_typed_row_and_no_cmap() {
        // A repeated-form winner codepoint present as a glyph row is the
        // designer\'s .notdef form: typed skip, not exported to cmap, run not refused.
        let f = inked_fx();
        let form = form_sha(&f.w65);
        let ev_sha = produce_into(&f, PixelNotdefKind::RepeatedForm, &form);
        let state = resolve(&f, &ev_sha, "glyph 0x41 u41 glyph/t67.png\n").unwrap();
        let (sources, claimed) = match &state {
            DetectionState::PixelEvidence { sources, pixel_form_sha256, .. } => (sources.clone(), pixel_form_sha256.clone()),
            other => panic!("expected PixelEvidence, got {other:?}"),
        };
        let m = parse_manifest(
            &format!("{}glyph 0x43 u43 glyph/t67.png\nglyph 0x41 u41 glyph/t67.png\n", manifest_prefix()), &f.dir,
        ).unwrap();
        let (flags, skipped) = placeholder_claim_skip_lines(&m.glyphs, &sources, &claimed);
        assert!(flags.contains("placeholder_skip\tu41\tcp\t0x41\tkind\trepeated-form"));
        assert!(flags.contains("decision_basis\tbound-notdef-evidence\n"));
        assert!(!flags.contains("placeholder_skip\tu43\t"));
        assert_eq!(skipped, vec![0x41u32], "bound cp leaves the ordinary glyph population; u43 stays");
    }

    #[test]
    fn tied_top_frequency_is_ambiguous() {
        // Two forms, each on two codepoints: no unique winner.
        let a1 = png_gray(8, 8, &GRAY_A, None);
        let a2 = png_gray(8, 8, &GRAY_A, Some("a2"));
        let dir = test_dir("tie");
        fs::create_dir_all(dir.join("glyph")).unwrap();
        fs::create_dir_all(dir.join("notdef")).unwrap();
        let ordinary = png_gray(8, 8, &GRAY_B, None);
        fs::write(dir.join("glyph/t67.png"), &ordinary).unwrap();
        // Two distinct forms, each on exactly two codepoints: the top frequency ties.
        let c1 = png_gray(8, 8, &[3u8; 64], None);
        let c2 = png_gray(8, 8, &[3u8; 64], Some("c2"));
        for (n, b) in [("w41", &a1), ("w42", &a2), ("w44", &c1), ("w45", &c2)] {
            fs::write(dir.join(format!("notdef/{n}")), b).unwrap();
        }
        let cap = format!(
            "kni-capture-manifest\tv1\nstyle\tTest/Regular\nframe\tf1\ncohort\tTest/Regular\nsource\t0x43\tglyph/t67.png\t{}\nsource\t0x41\tnotdef/w41\t{}\nsource\t0x42\tnotdef/w42\t{}\nsource\t0x44\tnotdef/w44\t{}\nsource\t0x45\tnotdef/w45\t{}\n",
            sha256_hex(&ordinary), sha256_hex(&a1), sha256_hex(&a2), sha256_hex(&c1), sha256_hex(&c2)
        );
        let cap_sha = sha256_hex(cap.as_bytes());
        fs::write(dir.join("notdef/capture-manifest.tsv"), &cap).unwrap();
        let form = form_sha(&a1);
        let ctx = PixelContext { style: "Test/Regular".into(), frame: "f1".into(), units_per_px: 2.0, source_sha256: sha256_hex(&a1), ink_model: PIXEL_INK_MODEL.into() };
        let ts = [
            notdef_producer::Tile { cp: 0x43, path: "glyph/t67.png", bytes: &ordinary, role: None },
            notdef_producer::Tile { cp: 0x41, path: "w41", bytes: &a1, role: Some(PixelNotdefKind::RepeatedForm) },
            notdef_producer::Tile { cp: 0x42, path: "w42", bytes: &a2, role: Some(PixelNotdefKind::RepeatedForm) },
            notdef_producer::Tile { cp: 0x44, path: "w44", bytes: &c1, role: None },
            notdef_producer::Tile { cp: 0x45, path: "w45", bytes: &c2, role: None },
        ];
        let req = notdef_producer::Request {
            context: &ctx, cohort: "Test/Regular", request_source: "routing-test",
            capture_record: cap.as_bytes(), capture_sha256: &cap_sha,
            space_evidence_sha256: None, pixel_form_sha256: &form, tiles: &ts, limits: TEST_LIMITS,
        };
        let produced = notdef_producer::produce(&req).unwrap();
        fs::write(dir.join("notdef/evidence.tsv"), &produced.evidence).unwrap();
        let manifest = format!(
            "{}glyph 0x43 u43 glyph/t67.png\ncapture_manifest notdef/capture-manifest.tsv {}\nnotdef evidence notdef/evidence.tsv {} Test/Regular {} 2 f1\n",
            manifest_prefix(), cap_sha, produced.evidence_sha, cap_sha
        );
        let m = parse_manifest(&manifest, &dir).unwrap();
        let rc = rc_for(&m, &dir);
        assert!(resolve_notdef(&m, &rc, TEST_LIMITS).unwrap_err() == "bad_notdef::AmbiguousPixelCandidate");
    }

    #[test]
    fn singleton_group_is_missing_pixel_evidence() {
        // Hand-written: the producer refuses a single claim (MissingPixelEvidence), so this
        // record bypasses it to prove the validator holds the same line on the engine side.
        let f = inked_fx();
        let form = form_sha(&f.w65);
        let evidence = format!(
            "kni-pixel-notdef-evidence\tv3\nkind\trepeated-form\nstyle\tTest/Regular\nframe\tf1\nscale\t2\nink_model\t{}\ncapture_sha256\t{}\npixel_form_sha256\t{}\nselected\tw65\t{}\npixel_source\t0x41\trepeated-form\tw65\t{}\n",
            PIXEL_INK_MODEL, f.cap_sha, form, sha256_hex(&f.w65), sha256_hex(&f.w65)
        );
        fs::write(f.dir.join("notdef/evidence.tsv"), &evidence).unwrap();
        assert!(resolve(&f, &sha256_hex(evidence.as_bytes()), "").unwrap_err() == "bad_notdef::MissingPixelEvidence");
    }

    #[test]
    fn wrong_form_claim_is_ambiguous_pixel_candidate() {
        let f = inked_fx();
        let ev_sha = produce_into(&f, PixelNotdefKind::RepeatedForm, &"0".repeat(64));
        assert!(resolve(&f, &ev_sha, "").unwrap_err() == "bad_notdef::AmbiguousPixelCandidate");
    }

    #[test]
    fn blank_cell_route_carries_no_space_binding() {
        let f = fx(png_gray(8, 8, &BLANK, None), png_gray(8, 8, &BLANK, Some("copy")), png_gray(8, 8, &GRAY_B, None));
        let form = form_sha(&f.w65);
        let ev_sha = produce_into(&f, PixelNotdefKind::BlankCell, &form);
        let state = resolve(&f, &ev_sha, "").unwrap();
        match &state {
            DetectionState::PixelEvidence { kind, sources, .. } => {
                assert_eq!(*kind, PixelNotdefKind::BlankCell);
                assert_eq!(sources, &vec![0x41, 0x42]);
            }
            other => panic!("expected PixelEvidence, got {other:?}"),
        }
    }

    #[test]
    fn blank_form_claimed_as_repeated_is_ambiguous() {
        let f = fx(png_gray(8, 8, &BLANK, None), png_gray(8, 8, &BLANK, Some("copy")), png_gray(8, 8, &GRAY_B, None));
        let form = form_sha(&f.w65);
        let ev_sha = produce_into(&f, PixelNotdefKind::RepeatedForm, &form);
        assert!(resolve(&f, &ev_sha, "").unwrap_err() == "bad_notdef::AmbiguousPixelCandidate");
    }

    #[test]
    fn inked_form_claimed_as_blank_is_ambiguous() {
        let f = inked_fx();
        let form = form_sha(&f.w65);
        let ev_sha = produce_into(&f, PixelNotdefKind::BlankCell, &form);
        assert!(resolve(&f, &ev_sha, "").unwrap_err() == "bad_notdef::AmbiguousPixelCandidate");
    }

    #[test]
    fn space_evidence_row_is_a_grammar_refusal() {
        // Blank advance is the font's widest character advance; no space binding exists.
        let f = inked_fx();
        let form = form_sha(&f.w65);
        let evidence = format!(
            "kni-pixel-notdef-evidence\tv3\nkind\trepeated-form\nstyle\tTest/Regular\nframe\tf1\nscale\t2\nink_model\t{}\ncapture_sha256\t{}\npixel_form_sha256\t{}\nspace_evidence_sha256\t{}\nselected\tw65\t{}\npixel_source\t0x41\trepeated-form\tw65\t{}\npixel_source\t0x42\trepeated-form\tw66\t{}\n",
            PIXEL_INK_MODEL, f.cap_sha, form, "e".repeat(64), sha256_hex(&f.w65), sha256_hex(&f.w65), sha256_hex(&f.w66)
        );
        fs::write(f.dir.join("notdef/evidence.tsv"), &evidence).unwrap();
        assert!(resolve(&f, &sha256_hex(evidence.as_bytes()), "").unwrap_err() == "bad_notdef::Grammar");
    }

    #[test]
    fn v2_record_is_a_grammar_refusal() {
        let f = inked_fx();
        let evidence = format!(
            "kni-notdef-evidence\tv2\nstyle\tTest/Regular\nframe\tf1\nscale\t2\ncapture\t{}\nselected\tw65\t{}\n",
            f.cap_sha, sha256_hex(&f.w65)
        );
        fs::write(f.dir.join("notdef/evidence.tsv"), &evidence).unwrap();
        assert!(resolve(&f, &sha256_hex(evidence.as_bytes()), "").unwrap_err() == "bad_notdef::Grammar");
    }

    #[test]
    fn producer_holds_the_claim_lines() {
        let f = inked_fx();
        let form = form_sha(&f.w65);
        let ordinary = fs::read(f.dir.join("glyph/t67.png")).unwrap();
        // A single claimed form is not a candidate.
        let ts = [notdef_producer::Tile { cp: 0x41, path: "w65", bytes: &f.w65, role: Some(PixelNotdefKind::RepeatedForm) }];
        let ctx = context(&f);
        let req = notdef_producer::Request {
            context: &ctx, cohort: "Test/Regular", request_source: "routing-test",
            capture_record: f.cap_text.as_bytes(), capture_sha256: &f.cap_sha,
            space_evidence_sha256: None, pixel_form_sha256: &form, tiles: &ts, limits: TEST_LIMITS,
        };
        assert!(matches!(notdef_producer::produce(&req), Err(notdef_producer::ProducerError::MissingPixelEvidence)));
        // Mixed roles in one group.
        let ts = [
            notdef_producer::Tile { cp: 0x41, path: "w65", bytes: &f.w65, role: Some(PixelNotdefKind::RepeatedForm) },
            notdef_producer::Tile { cp: 0x42, path: "w66", bytes: &f.w66, role: Some(PixelNotdefKind::BlankCell) },
        ];
        let req = notdef_producer::Request { tiles: &ts, ..req };
        assert!(matches!(notdef_producer::produce(&req), Err(notdef_producer::ProducerError::AmbiguousPixelCandidate)));
        // The selected byte pin must resolve to a claimed tile.
        let ts = tiles(&f, &ordinary, PixelNotdefKind::RepeatedForm);
        let bad_ctx = PixelContext { source_sha256: "9".repeat(64), ..context(&f) };
        let req = notdef_producer::Request { context: &bad_ctx, tiles: &ts, ..req };
        assert!(matches!(notdef_producer::produce(&req), Err(notdef_producer::ProducerError::Invalid(bound_detector_validator::BadNotdef::ShaMismatch))));
        // Capture record must match its pin.
        let zeros = "0".repeat(64);
        let req = notdef_producer::Request { capture_sha256: &zeros, ..req };
        assert!(matches!(notdef_producer::produce(&req), Err(notdef_producer::ProducerError::Invalid(bound_detector_validator::BadNotdef::ShaMismatch))));
        // The form claim must be 64 lowercase hex; it is never computed here.
        // Clean request: pixel_form_sha256 is the ONLY broken field (check order is
        // capture-sha before form-grammar, so a dirty capture pin would mask this case).
        let ctx = context(&f);
        let clean = notdef_producer::Request {
            context: &ctx, cohort: "Test/Regular", request_source: "routing-test",
            capture_record: f.cap_text.as_bytes(), capture_sha256: &f.cap_sha,
            space_evidence_sha256: None, pixel_form_sha256: "XYZ", tiles: &ts, limits: TEST_LIMITS,
        };
        assert!(matches!(notdef_producer::produce(&clean), Err(notdef_producer::ProducerError::Invalid(bound_detector_validator::BadNotdef::Grammar))));
    }
}
pub(crate) mod notdef_readback_tests {
    use kni_core::generated_native::prepare_generated;
    use kni_core::native_font::{encode_with_layout, NativeFontInput};
    use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
    use kni_core::sfnt_metadata::{
        HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata,
    };

    fn table<'a>(bytes: &'a [u8], tag: &[u8; 4]) -> &'a [u8] {
        let count = u16::from_be_bytes(bytes[4..6].try_into().unwrap()) as usize;
        for i in 0..count {
            let r = 12 + i * 16;
            if &bytes[r..r + 4] == tag {
                let off = u32::from_be_bytes(bytes[r + 8..r + 12].try_into().unwrap()) as usize;
                let len = u32::from_be_bytes(bytes[r + 12..r + 16].try_into().unwrap()) as usize;
                return &bytes[off..off + len];
            }
        }
        panic!("missing table")
    }
    fn pt(x: f64, y: f64) -> Point {
        Point { x, y }
    }
    pub(crate) fn quad(x0: f64, x1: f64, h: f64) -> ReferenceRing {
        ReferenceRing {
            start: pt(x0, 0.0),
            spans: vec![
                Span::Line { end: pt(x1, 0.0) },
                Span::Line { end: pt(x1, h) },
                Span::Line { end: pt(x0, h) },
                Span::Line { end: pt(x0, 0.0) },
            ],
        }
    }
    pub(crate) fn meta() -> NativeFontInput {
        NativeFontInput {
            postscript_name: "T-Regular".into(),
            glyphs: vec![],
            left_side_bearings: vec![],
            mapping: vec![],
            head: HeadMetadata {
                revision: 0x10000,
                flags: 0,
                units_per_em: 1000,
                created: 0,
                modified: 0,
                bounds: [0, -12, 800, 740],
                mac_style: 0,
                lowest_ppem: 1,
            },
            hhea: HheaMetadata {
                ascender: 0,
                descender: 0,
                line_gap: 0,
                advance_max: 0,
                min_lsb: 0,
                min_rsb: 0,
                max_extent: 0,
                caret_rise: 1,
                caret_run: 0,
                caret_offset: 0,
                metric_count: 0,
            },
            post: PostMetadata {
                italic_angle_fixed: 0,
                underline_position: -100,
                underline_thickness: 50,
                fixed_pitch: 0,
                memory: [0; 4],
            },
            os2: Os2Metadata {
                average_width: 500,
                weight: 400,
                width: 5,
                embedding: 0,
                subscript: [650, 600, 0, 75],
                superscript: [650, 600, 0, 350],
                strikeout: [50, 300],
                family_class: 0,
                panose: [0; 10],
                unicode_ranges: [0; 4],
                vendor: *b"TEST",
                selection: 64,
                first_char: 0,
                last_char: 0,
                typo: [0; 3],
                win_ascent: 0,
                win_descent: 0,
                version: 0,
                cap_height: 0,
                x_height: 0,
            },
            names: (1..=6)
                .map(|id| NameRecord {
                    language: 0x409,
                    name_id: id,
                    value: if id == 6 {
                        "T-Regular".into()
                    } else {
                        format!("Test{id}")
                    },
                })
                .collect(),
        }
    }

    /// Unit-only CFF readback: gid 0 geometry written by assembly reads back
    /// with the same ring count, gid order is stable, and .notdef never sits
    /// in the cmap. Runs entirely in-process (no pipeline execution).
    #[test]
    fn notdef_gid0_geometry_round_trips_through_cff() {
        let glyphs = vec![
            DrawnGlyph {
                glyph_id: ".notdef".into(),
                rings: vec![quad(50.0, 150.0, 100.0)],
            },
            DrawnGlyph {
                glyph_id: "a".into(),
                rings: vec![quad(100.0, 400.0, 200.0)],
            },
        ];
        let mut f = meta();
        f.postscript_name = "T-Regular".into();

        let metrics = vec![
            (".notdef".to_string(), 0.0, 0.0, 250.0),
            ("a".to_string(), 100.0, 100.0, 600.0),
        ];
        let prepared = prepare_generated(&glyphs, &[(0x61, 1)], &metrics, &f).unwrap();

        let bytes = encode_with_layout(&prepared, None).unwrap();
        let sha = kni_core::cff_reader::sha256_hex(&bytes);
        let font = kni_core::cff_reader::CffReader::from_bytes(&bytes, &sha).unwrap();
        assert_eq!(font.glyph_count(), 2);
        let g0 = font.read_glyph(0).expect("gid 0 readable");
        assert_eq!(g0.rings.len(), 1, "gid0 ring count round-trips");
        // prepare_generated translates xmin=50 to explicit lsb=0.
        assert_eq!(g0.rings[0].start, pt(0.0, 0.0));
        let ends: Vec<Point> = g0.rings[0]
            .spans
            .iter()
            .map(|s| match s {
                Span::Line { end } => *end,
                _ => panic!("expected line"),
            })
            .collect();
        assert_eq!(
            ends,
            vec![
                pt(100.0, 0.0),
                pt(100.0, 100.0),
                pt(0.0, 100.0),
                pt(0.0, 0.0)
            ]
        );
        assert_eq!(&table(&bytes, b"hmtx")[..4], &[0, 250, 0, 0]);
        let art_bytes = bytes.clone();
        assert_eq!(
            font.glyph_for_codepoint(0x61),
            Some(1),
            "gid stability: first mapped glyph stays gid 1"
        );
        assert!(
            !font.codepoints().iter().any(|(_, gid)| *gid == 0),
            ".notdef never in cmap"
        );
        // empty gid0 variant: blank-state .notdef ships zero rings
        let glyphs_blank = vec![
            DrawnGlyph {
                glyph_id: ".notdef".into(),
                rings: vec![],
            },
            DrawnGlyph {
                glyph_id: "a".into(),
                rings: vec![quad(100.0, 400.0, 200.0)],
            },
        ];
        let prepared = prepare_generated(&glyphs_blank, &[(0x61, 1)], &metrics, &f).unwrap();

        let bytes = encode_with_layout(&prepared, None).unwrap();
        let sha = kni_core::cff_reader::sha256_hex(&bytes);
        let font = kni_core::cff_reader::CffReader::from_bytes(&bytes, &sha).unwrap();
        assert_eq!(
            font.read_glyph(0).expect("gid 0 readable").rings.len(),
            0,
            "blank .notdef ships zero rings"
        );
        assert_ne!(bytes, art_bytes);
        assert_eq!(&table(&bytes, b"hmtx")[..4], &[0, 250, 0, 0]);
        assert_eq!(bytes, encode_with_layout(&prepared, None).unwrap());
        assert!(!font.codepoints().iter().any(|(_, gid)| *gid == 0));
    }
}

#[cfg(test)]
mod candidate_proxy_manifest_tests {
    use super::*;
    use bound_detector_validator::{Action, DetectionState};

    const GRAY_A: [u8; 64] = [7u8; 64];
    const GRAY_B: [u8; 64] = [9u8; 64];

    /// Glyph-population fixture: three real PNG tiles as glyph rows.
    fn proxy_dir(tag: &str, third: Option<&[u8; 64]>) -> (PathBuf, Vec<u8>, Vec<u8>) {
        let dir = test_dir(tag);
        let a = png_gray(8, 8, &GRAY_A, None);
        let b = png_gray(8, 8, &GRAY_A, Some("copy"));
        fs::write(dir.join("a.png"), &a).unwrap();
        fs::write(dir.join("b.png"), &b).unwrap();
        if let Some(g) = third { fs::write(dir.join("c.png"), png_gray(8, 8, g, None)).unwrap(); }
        (dir, a, b)
    }
    fn proxy_resolve(dir: &Path, rows: &str) -> Result<DetectionState, String> {
        let m = parse_manifest(&format!("{}{}", manifest_prefix(), rows), dir).unwrap();
        let rc = rc_for(&m, dir);
        resolve_notdef(&m, &rc, TEST_LIMITS)
    }
    fn rows(pin: &str, cp: &str, rule: &str) -> String {
        format!("glyph 0x41 u41 a.png\nglyph 0x42 u42 b.png\nglyph 0x43 u43 c.png\nnotdef_proxy {rule} {pin} {cp}\n")
    }

    #[test]
    fn proxy_route_selects_the_repeated_group() {
        let (dir, a, _) = proxy_dir("proxy-happy", Some(&GRAY_B));
        let pin = form_sha(&a);
        for rule in ["legacy-largest-repeat-proxy", "most-frequent-pixel-hash"] {
            let state = proxy_resolve(&dir, &rows(&pin, "0x41", rule)).unwrap();
            match &state {
                DetectionState::CandidateProxy { candidate_cps, selected_source_sha, selected_cp, .. } => {
                    assert_eq!(candidate_cps, &vec![0x41, 0x42]);
                    assert_eq!(selected_source_sha, &pin);
                    assert_eq!(*selected_cp, 0x41);
                }
                other => panic!("expected CandidateProxy, got {other:?}"),
            }
            assert!(matches!(state.action(false, 1000.0), Ok(Action::CandidateProxy)), "{rule}");
        }
    }

    #[test]
    fn proxy_form_pin_mismatch_is_typed() {
        let (dir, _, _) = proxy_dir("proxy-pin", Some(&GRAY_B));
        assert!(proxy_resolve(&dir, &rows(&"0".repeat(64), "0x41", "most-frequent-pixel-hash")).unwrap_err() == "bad_notdef::CandidateProxyShaMismatch");
    }

    #[test]
    fn proxy_reference_cp_outside_the_group_is_typed() {
        let (dir, a, _) = proxy_dir("proxy-cp", Some(&GRAY_B));
        let pin = form_sha(&a);
        assert!(proxy_resolve(&dir, &rows(&pin, "0x43", "most-frequent-pixel-hash")).unwrap_err() == "bad_notdef::CandidateProxySelectionMismatch");
    }

    #[test]
    fn proxy_without_repetition_is_missing_evidence() {
        // Three distinct forms: a count=1 form is an ordinary glyph, never a candidate.
        let dir = test_dir("proxy-single");
        for (n, g) in [("a.png", [7u8; 64]), ("b.png", [9u8; 64]), ("c.png", [11u8; 64])] {
            fs::write(dir.join(n), png_gray(8, 8, &g, None)).unwrap();
        }
        let pin = form_sha(&fs::read(dir.join("a.png")).unwrap());
        assert!(proxy_resolve(&dir, &rows(&pin, "0x41", "most-frequent-pixel-hash")).unwrap_err() == "bad_notdef::MissingPixelEvidence");
    }

    #[test]
    fn proxy_tied_top_frequency_is_ambiguous() {
        let dir = test_dir("proxy-tie");
        fs::write(dir.join("a.png"), png_gray(8, 8, &GRAY_A, None)).unwrap();
        fs::write(dir.join("b.png"), png_gray(8, 8, &GRAY_A, Some("copy"))).unwrap();
        fs::write(dir.join("c.png"), png_gray(8, 8, &GRAY_B, None)).unwrap();
        fs::write(dir.join("d.png"), png_gray(8, 8, &GRAY_B, Some("copy"))).unwrap();
        let pin = form_sha(&fs::read(dir.join("a.png")).unwrap());
        let rows = format!(
            "glyph 0x41 u41 a.png\nglyph 0x42 u42 b.png\nglyph 0x43 u43 c.png\nglyph 0x44 u44 d.png\nnotdef_proxy most-frequent-pixel-hash {pin} 0x41\n"
        );
        assert!(proxy_resolve(&dir, &rows).unwrap_err() == "bad_notdef::AmbiguousPixelCandidate");
    }

    #[test]
    fn proxy_and_evidence_rows_are_mutually_exclusive() {
        let (dir, a, _) = proxy_dir("proxy-excl", Some(&GRAY_B));
        let pin = form_sha(&a);
        let ev = format!("notdef evidence notdef/evidence.tsv {} Test/Regular {} 2 f1\n", "b".repeat(64), "a".repeat(64));
        assert!(proxy_resolve(&dir, &(rows(&pin, "0x41", "most-frequent-pixel-hash") + &ev)).unwrap_err() == "bad_notdef::ContextMismatch");
        let cap = format!("capture_manifest notdef/capture-manifest.tsv {}\n", "a".repeat(64));
        assert!(proxy_resolve(&dir, &(rows(&pin, "0x41", "most-frequent-pixel-hash") + &cap)).unwrap_err() == "bad_notdef::ContextMismatch");
    }

    #[test]
    fn proxy_row_grammar_is_exact() {
        let (dir, a, _) = proxy_dir("proxy-grammar", Some(&GRAY_B));
        let pin = form_sha(&a);
        let glyphs = "glyph 0x41 u41 a.png\nglyph 0x42 u42 b.png\nglyph 0x43 u43 c.png\n".to_string();
        for bad in [
            format!("notdef_proxy guessed {pin} 0x41\n"),          // unknown rule token
            format!("notdef_proxy most-frequent-pixel-hash {} 0x41\n", "AB".repeat(32)), // non-lowercase-hex pin
            format!("notdef_proxy most-frequent-pixel-hash {pin} 0x41 extra\n"),          // trailing field
            "notdef_proxy most-frequent-pixel-hash 0x41\n".to_string(),                   // missing pin
        ] {
            assert_eq!(
                parse_manifest(&(manifest_prefix() + &glyphs + &bad), &dir).unwrap_err(),
                "bad_notdef::Grammar",
                "{bad:?}"
            );
        }
        let dup = format!("notdef_proxy most-frequent-pixel-hash {pin} 0x41\nnotdef_proxy legacy-largest-repeat-proxy {pin} 0x41\n");
        assert_eq!(
            parse_manifest(&(manifest_prefix() + &glyphs + &dup), &dir).unwrap_err(),
            "bad_notdef::Duplicate"
        );
    }

    #[test]
    fn proxy_cp0_is_a_typed_refusal() {
        let (dir, a, _) = proxy_dir("proxy-cp0", Some(&GRAY_B));
        let pin = form_sha(&a);
        assert!(proxy_resolve(&dir, &rows(&pin, "0x0", "most-frequent-pixel-hash")).unwrap_err() == "bad_notdef::ReservedCodepoint");
    }

    #[test]
    fn proxy_missing_tile_is_typed_io() {
        let dir = test_dir("proxy-io");
        fs::write(dir.join("a.png"), png_gray(8, 8, &GRAY_A, None)).unwrap();
        let pin = form_sha(&fs::read(dir.join("a.png")).unwrap());
        let rows = format!("glyph 0x41 u41 a.png\nglyph 0x42 u42 absent.png\nnotdef_proxy most-frequent-pixel-hash {pin} 0x41\n");
        assert!(proxy_resolve(&dir, &rows).unwrap_err() == "bad_notdef::Io");
    }
}

#[cfg(test)]
mod ignored_evidence_tests {
    use super::*;
    use bound_detector_validator::{DetectionState, PixelNotdefKind};

    #[test]
    fn ignorable_codes_are_exactly_the_four_evidence_failures() {
        for (e, c) in [("bad_notdef::ShaMismatch", "ShaMismatch"), ("bad_notdef::ContextMismatch", "ContextMismatch"),
                       ("bad_notdef::Grammar", "Grammar"), ("bad_notdef::Duplicate", "Duplicate")] {
            assert_eq!(ignorable_notdef_evidence_code(e), Some(c));
        }
        for e in ["bad_notdef::Io", "bad_notdef::ResourceLimit", "bad_notdef::MissingPixelEvidence", "bad_notdef::AmbiguousPixelCandidate"] {
            assert_eq!(ignorable_notdef_evidence_code(e), None);
        }
    }

    #[test]
    fn broken_evidence_is_ignored_and_font_gets_empty_notdef_with_max_advance() {
        let dir = test_dir("ignored-evidence");
        fs::write(dir.join("a.png"), png_gray(8, 8, &[7u8; 64], None)).unwrap();
        // Evidence bound to another style: a ContextMismatch under the bound-detector validator.
        let rows = format!("glyph 0x41 u41 a.png\nnotdef evidence notdef/evidence.tsv {} Other/Style {} 2 f1\ncapture_manifest notdef/capture-manifest.tsv {}\n",
            "b".repeat(64), "a".repeat(64), "a".repeat(64));
        let m = parse_manifest(&format!("{}{}", manifest_prefix(), rows), &dir).unwrap();
        let rc = rc_for(&m, &dir);
        assert!(resolve_notdef(&m, &rc, TEST_LIMITS).is_err());
        let (state, code) = resolve_notdef_or_ignore(&m, &rc, TEST_LIMITS).unwrap();
        assert_eq!(code, Some("ContextMismatch"));
        assert!(matches!(&state, DetectionState::PixelEvidence { kind: PixelNotdefKind::BlankCell, sources, .. } if sources.is_empty()));
        assert!(matches!(state.action(false, 1000.0), Ok(bound_detector_validator::Action::PixelEvidence { .. })));
        let metrics = [kni_metrics::self_anchored_spacing::GlyphSpacing { glyph_id: "A".into(), lsb: 0.0, rsb: 0.0, advance: 410.0 }];
        let mut receipt = String::new();
        let (g, l, r, a) = assemble_pixel_notdef(&state, &[], &[], &metrics, &std::collections::HashMap::new(), None, None,
            &space_evidence::SpaceGate::NotRequested, &mut receipt).unwrap();
        assert!(g.rings.is_empty());
        assert_eq!((l, r, a), (0.0, 0.0, 410.0));
        assert!(receipt.contains("kind\tblank-cell"));
    }

    #[test]
    fn non_evidence_errors_still_fail() {
        let dir = test_dir("ignored-evidence-io");
        fs::write(dir.join("a.png"), png_gray(8, 8, &[7u8; 64], None)).unwrap();
        let rows = "glyph 0x41 u41 a.png\n";
        let m = parse_manifest(&format!("{}{}", manifest_prefix(), rows), &dir).unwrap();
        let rc = rc_for(&m, &dir);
        let (state, code) = resolve_notdef_or_ignore(&m, &rc, TEST_LIMITS).unwrap();
        assert_eq!(code, None);
        assert!(matches!(state, DetectionState::MissingPixelEvidence));
    }
}

#[test]
fn partial_degrade_blank_notdef_advances_declared_em_not_zero() {
    // W6 finding: the partial-degrade blank .notdef previously shipped a
    // fabricated 0.0 advance, collapsing gid0 and shadowing the
    // max-glyph-advance assembly branch. The advance is the caller-declared
    // em (manifest upm), the same fallback the empty-population arm uses.
    for state in [
        bound_detector_validator::DetectionState::MissingPixelEvidence,
        bound_detector_validator::DetectionState::MissingEvidence,
        bound_detector_validator::DetectionState::Ambiguous,
    ] {
        match state.action(true, 1000.0) {
            Ok(bound_detector_validator::Action::Empty { advance, partial_reason }) => {
                assert_eq!(advance, 1000.0);
                assert!(partial_reason.is_some());
            }
            other => panic!("expected Empty, got {other:?}"),
        }
        // Non-degrade mode still refuses, never emits an advance.
        assert!(state.action(false, 1000.0).is_err());
    }
}
