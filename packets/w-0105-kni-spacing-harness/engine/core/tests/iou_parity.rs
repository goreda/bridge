//! Production parity for `iou_report` against the REAL `ProductionEvaluator`, on the emitted CFF
//! bytes read back with `CffReader`. Fixture root: KNI_G_FIXTURES when set, else
//! <crate>/tests/fixtures (fails loudly when missing, never skips) and the
//! `render_mask`/`source_mask` accessors from economy_eval.diff.
use kni_core::{
    capture::capture_png, capture_fit::fit_captured, cubic_fit::FitPolicy,
    economy_eval::{sha256_hex, EvalConfig, ProductionEvaluator},
    iou_adapter::*, iou_report::*, reference_slice::{DrawnGlyph, Point, ReferenceRing, Span},
    reference_transfer::canonical_bytes,
};

const K: f64 = 690.0 / 403.5087719298246;
const FX: [(&str, &str); 5] = [
    ("r_scan.png", "e820c617cd40ec517bb5e6e6daa01f948ae847de804474b3a78fc85071b3cbe0"),
    ("s_scan.png", "4d167e3b92af1fa27db5103bf87bd55048e926cd9f64406b769ac05be7b59add"),
    ("u_scan.png", "daf95988f8e779e0dfa361c86d798957f74a60b41c72d1191d27624282068fae"),
    ("dot_00b7.png", "33f0a1b27a357115174e881c168bc9df6989bf47e06aa627dfe894523349eae4"),
    ("quote_2018.png", "d7459752a33e6c80c95c31c06992b8e66908c233453c85e7e0c077878a0e3518"),
];
const CANVAS: (usize, usize) = (1485, 1050);
const STEPS: usize = 32;
const THR: u8 = 128;
const EPS: f64 = 0.5;

/// Explicit fixture root (no environment dependency): <crate>/tests/fixtures. A missing licensed
/// fixture is a typed test-setup blocker, never a silent pass or a skip.
const FIXTURE_ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
const REQUIRED_FIXTURES: [&str; 5] = ["00C9_scan.png", "dot_00b7.png", "quote_2018.png", "r_scan.png", "u_scan.png"];
fn dir() -> String {
    if let Ok(d) = std::env::var("KNI_G_FIXTURES") {
        if !d.is_empty() {
            assert!(std::path::Path::new(&d).is_dir(), "TEST-SETUP-BLOCKER: KNI_G_FIXTURES={d} is not a directory");
            return d;
        }
    }
    let missing: Vec<&str> = REQUIRED_FIXTURES.iter().copied().filter(|f| !std::path::Path::new(FIXTURE_ROOT).join(f).is_file()).collect();
    if !missing.is_empty() { panic!("TEST-SETUP-BLOCKER: fixture root {FIXTURE_ROOT} lacks {missing:?}"); }
    FIXTURE_ROOT.to_string()
}
fn cfg(sha: &str) -> EvalConfig {
    EvalConfig { frame_id: "CAP690-SCAN128-FITK-CFFINTEGER-RAWORIGIN".into(), scale_k: K, threshold: THR, canvas: CANVAS, capture_eps: EPS, flatten_steps: STEPS, expected_source_sha256: sha.into(), advance: 1000, render_limits: kni_core::economy_eval::RenderLimits { max_pixels: CANVAS.0 * CANVAS.1, max_flatten_steps: STEPS, max_edges: CANVAS.0 * CANVAS.1, max_working_bytes: 1 << 28 } }
}
fn limits() -> ResourceLimits {
    // resource guards for these fixtures, not quality thresholds
    ResourceLimits { max_pixels: (CANVAS.0 * CANVAS.1) as u64, max_flatten_steps: STEPS, max_edges: (CANVAS.0 * CANVAS.1) as u64, max_png_bytes: 1 << 24 , max_png_working_bytes: 1 << 26}
}
struct Fx { name: &'static str, png: Vec<u8>, cfg: EvalConfig, ev: ProductionEvaluator, origin: (f64, f64), g: DrawnGlyph }
fn load(i: usize) -> Fx {
    let png = std::fs::read(format!("{}/{}", dir(), FX[i].0)).unwrap();
    let c = cfg(FX[i].1);
    let ev = ProductionEvaluator::new(c.clone(), &png).unwrap();
    let mc = capture_png(&png, EPS).unwrap();
    let pol = FitPolicy { squared_error: 0.1, max_refits: 6 };
    let (rings, ..) = fit_captured(&mc.rings, K, &pol);
    Fx { name: FX[i].0, png, cfg: c, ev, origin: (mc.origin_x, mc.origin_y), g: DrawnGlyph { glyph_id: "g".into(), rings } }
}
fn same_rings(a: &DrawnGlyph, b: &DrawnGlyph) -> bool { canonical_bytes("g", &a.rings) == canonical_bytes("g", &b.rings) }
/// The evaluator's container path emits a bare CFF table (cff_one). CffReader reads sfnt, so wrap
/// that exact CFF in the minimal OTTO (CFF + cmap + head) the reader requires; the CFF bytes are untouched.
fn wrap_otto(cff: &[u8], upm: u16) -> Vec<u8> {
    let mut cmap = vec![0u8, 0, 0, 1, 0, 3, 0, 10, 0, 0, 0, 12];
    cmap.extend([0, 12, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 1]);
    cmap.extend(0x41u32.to_be_bytes()); cmap.extend(0x41u32.to_be_bytes()); cmap.extend(1u32.to_be_bytes());
    let mut head = vec![0u8; 54]; head[18..20].copy_from_slice(&upm.to_be_bytes());
    let tables: Vec<([u8; 4], Vec<u8>)> = vec![(*b"CFF ", cff.to_vec()), (*b"cmap", cmap), (*b"head", head)];
    let mut out = vec![0x4F, 0x54, 0x54, 0x4F, 0, 3, 0, 0, 0, 0, 0, 0];
    let mut off = 12 + 16 * tables.len();
    let mut body: Vec<u8> = Vec::new();
    for (tag, d) in &tables {
        out.extend(tag); out.extend([0u8; 4]); out.extend((off as u32).to_be_bytes()); out.extend((d.len() as u32).to_be_bytes());
        body.extend(d); off += d.len();
    }
    out.extend(body); out
}
/// Emit through the evaluator's real container path, read back glyph 1 ("glyph"; gid 0 is .notdef).
fn readback(f: &Fx, g: &DrawnGlyph) -> (Vec<u8>, DrawnGlyph) {
    let cff = f.ev.final_font_bytes(g).expect("emit");
    let bytes = wrap_otto(&cff, 1000);
    let sha = sha256_hex(&bytes);
    let rb = readback_outlines(&bytes, &sha, &[("g".to_string(), 1)]).remove(0).expect("readback");
    (bytes, rb)
}
fn tile(f: &Fx) -> SourceInput { SourceInput::Png(f.png.clone()) }
fn evidence(f: &Fx, tr: (f64, f64)) -> FrameEvidence { evidence_from_eval(&f.cfg, f.origin, tr, limits()) }

#[test]
fn readback_geometry_equals_emitted_geometry() {
    for i in 0..5 { let f = load(i); let (_, rb) = readback(&f, &f.g); assert!(same_rings(&rb, &f.g), "{}: CFF readback differs from drawn rings", f.name); }
}

#[test]
fn masks_are_bit_exact_against_production_evaluator() {
    for i in 0..5 {
        let f = load(i);
        let (_, rb) = readback(&f, &f.g);
        let frame = evidence(&f, (0.0, 0.0)).resolve().unwrap();
        let mine = coverage_mask(&frame, "g", &rb.rings).unwrap();
        let real = f.ev.render_mask(&f.g).expect("real mask");
        assert_eq!(mine.len(), real.len());
        assert!(mine == real, "{}: coverage mask differs from ProductionEvaluator::render_mask", f.name);
        let ink: Vec<bool> = png_gray(&f.png).iter().map(|v| *v < THR).collect();
        assert!(ink == f.ev.source_mask(), "{}: source ink mask differs", f.name);
    }
}
fn png_gray(png: &[u8]) -> Vec<u8> { kni_core::capture::decode_png_gray(png).unwrap().2 }

#[test]
fn iou_is_bit_identical_to_curve_point_and_stage_frame_pins_agree() {
    let mut jobs = Vec::new();
    let mut real = Vec::new();
    let mut origins = Vec::new();
    for i in 0..5 {
        let f = load(i);
        let cp = f.ev.curve_point(&f.g).expect("curve_point");
        real.push(cp.font_iou);
        origins.push(f.origin);
        // evaluator pin carries the frame values iou_report was given
        let pin = f.ev.node_count_parser_pin();
        assert!(pin.contains(&format!("K={:?}", K)) && pin.contains(&format!("thr={THR}")) && pin.contains(&format!("canvas={}x{}", CANVAS.0, CANVAS.1)));
        assert!(pin.contains(&format!("origin=({:?},{:?})", f.origin.0, f.origin.1)) && pin.contains(&format!("steps={STEPS}")));
        let (_, rb) = readback(&f, &f.g);
        jobs.push(job_from_readback("fx", &format!("g{i}"), tile(&f), Ok(DrawnGlyph { glyph_id: format!("g{i}"), rings: rb.rings }), evidence(&f, (0.0, 0.0))));
    }
    let out = run_jobs(&jobs, Some(2));
    let keys: Vec<(String, String)> = (0..5).map(|i| ("fx".to_string(), format!("g{i}"))).collect();
    let rep = build_report(&keys, out.rows, vec![], out.duplicates, Some(0.99)).expect("partition");
    for (i, r) in rep.rows().iter().enumerate() {
        let m = r.result().as_ref().expect("measured");
        assert_eq!(m.iou().to_bits(), real[i].to_bits(), "{}: iou differs from curve_point", FX[i].0);
        assert_eq!(r.stage(), OutlineStage::OtfReadback);
        let pin = r.frame_pin().unwrap();
        assert!(pin.contains(&format!("K={:?}|origin=({:?},{:?})|thr={THR}|steps={STEPS}|canvas={}x{}", K, origins[i].0, origins[i].1, CANVAS.0, CANVAS.1)));
        assert_eq!(r.tile_sha256().len(), 64);
        assert_eq!(r.outline_sha256().unwrap().len(), 64);
    }
    let rc = rep.to_receipt();
    assert!(rc.contains("iou stage otf-readback"));
    assert_eq!(rep.overall().measured, 5);
}

#[test]
fn translation_matches_a_shipped_shift_exactly() {
    // integer shift (as the exporter's baseline shift) applied before emit; the frame translation undoes it
    let f = load(0);
    let (dx, dy) = (5.0, -17.0);
    let mut sh = f.g.clone();
    for r in &mut sh.rings {
        r.start.x += dx; r.start.y += dy;
        for s in &mut r.spans { match s {
            Span::Line { end } => { end.x += dx; end.y += dy; }
            Span::Cubic { control_one, control_two, end } => { for p in [control_one, control_two, end] { p.x += dx; p.y += dy; } }
        } }
    }
    let (_, rb) = readback(&f, &sh);
    let base = f.ev.curve_point(&f.g).unwrap().font_iou;
    let ok = iou_glyph(&evidence(&f, (dx, dy)).resolve().unwrap(), &SourceTile::from_png("g", &f.png, &kni_core::capture::DecodeLimits { max_input_bytes: 1 << 24, max_pixels: (CANVAS.0*CANVAS.1) as usize, max_working_bytes: 1 << 26 }, kni_core::bounded_png_adapter::LimitsOrigin::Explicit("iou_parity test fixture".into())).unwrap().0, &DrawnGlyph { glyph_id: "g".into(), rings: rb.rings.clone() }).unwrap();
    assert_eq!(ok.iou().to_bits(), base.to_bits());
    let bad = iou_glyph(&evidence(&f, (0.0, 0.0)).resolve().unwrap(), &SourceTile::from_png("g", &f.png, &kni_core::capture::DecodeLimits { max_input_bytes: 1 << 24, max_pixels: (CANVAS.0*CANVAS.1) as usize, max_working_bytes: 1 << 26 }, kni_core::bounded_png_adapter::LimitsOrigin::Explicit("iou_parity test fixture".into())).unwrap().0, &DrawnGlyph { glyph_id: "g".into(), rings: rb.rings }).unwrap();
    assert!(bad.iou() < base);
}

#[test]
fn resource_gate_and_row_partition_on_real_fixtures() {
    let f = load(0);
    let (_, rb) = readback(&f, &f.g);
    let mut tiny = evidence(&f, (0.0, 0.0));
    tiny.limits = Some(ResourceLimits { max_pixels: 1000, max_flatten_steps: STEPS, max_edges: 10, max_png_bytes: 1 << 24 , max_png_working_bytes: 1 << 26});
    let jobs = vec![
        job_from_readback("fx", "ok", tile(&f), Ok(DrawnGlyph { glyph_id: "ok".into(), rings: rb.rings.clone() }), evidence(&f, (0.0, 0.0))),
        job_from_readback("fx", "capped", tile(&f), Ok(DrawnGlyph { glyph_id: "capped".into(), rings: rb.rings.clone() }), tiny),
        job_from_readback("fx", "unread", tile(&f), Err(IouError::OutlineReadback { glyph: "unread".into(), detail: "test".into() }), evidence(&f, (0.0, 0.0))),
    ];
    let out = run_jobs(&jobs, Some(1));
    assert!(matches!(out.rows[1].result(), Err(IouError::ResourceLimitExceeded { .. })));
    assert_eq!(out.rows[1].tile_sha256(), "UNHASHED");
    let ex = vec![Exclusion { style: "fx".into(), glyph_id: "blank".into(), reason: "no outline".into() }];
    let keys: Vec<(String, String)> = ["ok", "capped", "unread", "blank"].iter().map(|g| ("fx".to_string(), g.to_string())).collect();
    let rep = build_report(&keys, out.rows.clone(), ex.clone(), out.duplicates.clone(), None).unwrap();
    assert_eq!((rep.overall().total, rep.overall().measured, rep.overall().failed, rep.overall().excluded), (4, 1, 2, 1));
    // a lost glyph is an inventory violation, not a smaller report
    assert!(build_report(&keys, out.rows, vec![], out.duplicates, None).is_err());
}

#[test]
fn wrong_font_sha_is_a_readback_failure_not_a_measurement() {
    let f = load(0);
    let bytes = wrap_otto(&f.ev.final_font_bytes(&f.g).unwrap(), 1000);
    let r = readback_outlines(&bytes, &"0".repeat(64), &[("g".to_string(), 1)]);
    assert!(matches!(r[0], Err(IouError::OutlineReadback { .. })));
}

#[test]
fn collinear_integer_runs_measure_like_the_evaluators_canon_form() {
    // Diagonal edges split into exact collinear integer Line runs: the evaluator measures canon(ring);
    // iou_report must rasterize the same canonical form, so the masks stay bit-identical.
    let f = load(0);
    let p = |x: f64, y: f64| Point { x, y };
    let spans: Vec<Span> = [(200.0, 200.0), (300.0, 300.0), (700.0, 300.0), (500.0, 700.0), (300.0, 900.0), (100.0, 700.0), (100.0, 400.0), (100.0, 100.0)]
        .iter().map(|&(x, y)| Span::Line { end: p(x, y) }).collect();
    let g = DrawnGlyph { glyph_id: "g".into(), rings: vec![ReferenceRing { start: p(100.0, 100.0), spans }] };
    let frame = evidence(&f, (0.0, 0.0)).resolve().unwrap();
    let mine = coverage_mask(&frame, "g", &g.rings).unwrap();
    let real = f.ev.render_mask(&g).expect("real mask");
    assert!(mine == real, "mask differs from ProductionEvaluator::render_mask on collinear-run input");
    assert!(real.iter().any(|v| *v), "test outline rasterized to nothing");
}
