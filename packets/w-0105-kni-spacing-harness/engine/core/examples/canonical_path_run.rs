//! Canonical-path run harness (W2-3 / next-version work list item 4,
//! CANON-FIX-1 reconcile wiring).
//!
//! Runs the canonical chain capture_png -> fit_captured -> export-boundary
//! rounding reconcile -> integer charstring at fit scale K=1 and, for
//! measured comparison, the raw chain (no reconcile) at the manifest's
//! production scale K, exactly as W2-3 measured it
//! (docs/process/measurement-frame.md records the production path as
//! capture, fit_captured(rings, K), integer charstring in font units). The
//! reconcile stage is the landed kni_core::rounding_reconcile code: every
//! coordinate is quantized to the integer export grid (round half away from
//! zero, EXPORT_RESOLUTION, the same per-scalar rounding production applies
//! in prepare_generated_with_placement), then the W2-2 constant-cubic
//! cleanup runs with one typed ledger row per drop/hold. The W2-3 finding
//! was that the canonical chain alone cannot reach an integer charstring on
//! glyphs production ships (charstring_refused:UnrepresentableCoordinate);
//! the reconcile stage is the production mechanism that closes exactly that
//! gap, so the canonical arm wires it and re-measures. The production arm
//! is left byte-for-byte as W2-3 ran it (raw chain, its two typed refusals
//! documented in measurements.run2-7422a4ac.tsv). Per-glyph reconcile
//! outcomes are typed note tokens: reconcile_quantized:moved=N:max_delta=D:
//! non_finite=N, constant_cubic_dropped:ring=R:span=S,
//! constant_cubic_held:ring=R:span=S:why=W. Nothing drops silently.
//! Everything else in the two arms comes from the manifest; nothing in the
//! existing production paths is modified.
//!
//! Per glyph and arm it measures: segment counts (line/cubic) of the decoded
//! integer charstring outline, fit error against the capture's raw rings
//! (symmetric mean squared distance and max deviation, in px), scan-domain
//! IoU at the declared threshold (ProductionEvaluator rasterizer), and the
//! charstring bytes. The per-glyph byte diff compares the two arms'
//! charstrings; whole-font CFF bytes per arm are emitted for the font-level
//! byte diff. Every glyph failure is a typed row; nothing drops silently.
//!
//! Usage:
//!   canonical_path_run MANIFEST TILEDIR OUT_DIR THRESHOLD FLATTEN_STEPS \
//!       FLATTEN_TOL_PX MAX_WORKING_BYTES
//!
//! All parameters are explicit operational inputs; the harness declares no
//! numeric constants of its own. TILEDIR substitutes the @TILEDIR@ token in
//! manifest glyph paths (pass any existing directory when unused).
//! Frame pins follow the format pinned in economy_eval::ProductionEvaluator.

use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::cff_container::{charstring, cff_one, CffGlyph};
use kni_core::cff_reader::sha256_hex;
use kni_core::cubic_fit::FitPolicy;
use kni_core::curve_stress::flatten_ring;
use kni_core::economy_eval::{EvalConfig, ProductionEvaluator, RenderLimits};
use kni_core::glyph_segments::segment_metrics;
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing};

#[derive(Clone)]
struct GlyphRow { cp: String, name: String, path: String }

struct ManifestCfg {
    scale: f64, eps: f64, se: f64, refits: usize, upm: u16,
    ps_name: String, population: String, glyphs: Vec<GlyphRow>,
    ignored_keys: Vec<String>,
}

fn parse_manifest(text: &str, tiledir: &str, manifest_dir: &std::path::Path) -> Result<ManifestCfg, String> {
    let (mut scale, mut eps, mut se, mut refits, mut upm, mut ps, mut pop) = (None, None, None, None, None, None, String::new());
    let mut glyphs = Vec::new();
    let mut ignored = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        let p: Vec<&str> = line.split_whitespace().collect();
        match p[0] {
            "scale" => scale = Some(p[1].parse::<f64>().map_err(|_| "bad scale")?),
            "rdp_epsilon" => eps = Some(p[1].parse::<f64>().map_err(|_| "bad rdp_epsilon")?),
            "fit_squared_error" => se = Some(p[1].parse::<f64>().map_err(|_| "bad fit_squared_error")?),
            "fit_max_refits" => refits = Some(p[1].parse::<usize>().map_err(|_| "bad fit_max_refits")?),
            "upm" => upm = Some(p[1].parse::<u16>().map_err(|_| "bad upm")?),
            "postscript_name" => ps = Some(p[1].to_string()),
            "population_sha256" => pop = p[1].to_string(),
            "glyph" => {
                if p.len() < 4 { return Err(format!("bad glyph row: {line}")); }
                let raw = p[3];
                let resolved = if let Some(rest) = raw.strip_prefix("@TILEDIR@/") {
                    format!("{tiledir}/{rest}")
                } else if std::path::Path::new(raw).is_absolute() {
                    raw.to_string()
                } else {
                    manifest_dir.join(raw).to_string_lossy().into_owned()
                };
                glyphs.push(GlyphRow { cp: p[1].to_string(), name: p[2].to_string(), path: resolved });
            }
            other => ignored.push(other.to_string()),
        }
    }
    Ok(ManifestCfg {
        scale: scale.ok_or("manifest: missing scale")?,
        eps: eps.ok_or("manifest: missing rdp_epsilon")?,
        se: se.ok_or("manifest: missing fit_squared_error")?,
        refits: refits.ok_or("manifest: missing fit_max_refits")?,
        upm: upm.ok_or("manifest: missing upm")?,
        ps_name: ps.ok_or("manifest: missing postscript_name")?,
        population: pop, glyphs, ignored_keys: ignored,
    })
}

/// Point-to-polyline distance (closed polyline), same estimator family as
/// economy_eval::dist_to_poly (point-to-segment minimum over edges).
fn dist_to_poly(p: Point, poly: &[Point]) -> f64 {
    let n = poly.len();
    if n == 0 { return f64::INFINITY; }
    (0..n).map(|i| {
        let a = poly[i]; let b = poly[(i + 1) % n];
        let dx = b.x - a.x; let dy = b.y - a.y;
        let l2 = dx * dx + dy * dy;
        let t = if l2 == 0.0 { 0.0 } else { (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0) };
        let (cx, cy) = (a.x + t * dx, a.y + t * dy);
        ((p.x - cx).powi(2) + (p.y - cy).powi(2)).sqrt()
    }).fold(f64::INFINITY, f64::min)
}

/// Fit error of one emitted glyph against the capture's raw rings, in px.
/// Mirrors the economy_eval RegionAssessment quantities: symmetric mean
/// squared distance (both directions, averaged) and maximum deviation.
/// Rings align by index: fit_captured preserves capture order (subsequence
/// with drops). A count mismatch is reported as None (typed at the caller),
/// never silently re-aligned.
fn fit_error_px(raw: &[Vec<Point>], rings: &[ReferenceRing], k: f64, flatten_tol_px: f64) -> Option<(f64, f64)> {
    if raw.len() != rings.len() { return None; }
    let tol_font = flatten_tol_px * k;
    let mut sfe_sum = 0.0f64; let mut maxdev = 0.0f64;
    for (r, ring) in raw.iter().zip(rings.iter()) {
        if r.is_empty() { return None; }
        let poly: Vec<Point> = flatten_ring(ring, tol_font).iter().map(|p| Point { x: p.x / k, y: p.y / k }).collect();
        if poly.is_empty() { return None; }
        let d1: Vec<f64> = r.iter().map(|p| dist_to_poly(*p, &poly)).collect();
        let d2: Vec<f64> = poly.iter().map(|p| dist_to_poly(*p, r)).collect();
        let mean2 = |d: &[f64]| d.iter().map(|x| x * x).sum::<f64>() / d.len() as f64;
        let sfe = (mean2(&d1) + mean2(&d2)) / 2.0;
        let md = d1.iter().chain(d2.iter()).cloned().fold(0.0, f64::max);
        if !(sfe.is_finite() && md.is_finite()) { return None; }
        sfe_sum += sfe; if md > maxdev { maxdev = md; }
    }
    Some((sfe_sum / rings.len().max(1) as f64, maxdev))
}

struct ArmOut {
    rings: Vec<ReferenceRing>, fallback: bool, dropped: usize,
    cs: Vec<u8>, container_accepted: bool,
    line: usize, cubic: usize, sfe: Option<f64>, maxdev: Option<f64>, iou: Option<f64>,
    notes: Vec<String>,
}

fn run_arm(
    label: &str, mc: &kni_core::capture::MeasuredContour, png: &[u8], png_sha: &str,
    k: f64, policy: &FitPolicy, capture_eps: f64, upm: u16, glyph_name: &str,
    threshold: u8, flatten_steps: usize, flatten_tol_px: f64, max_working_bytes: usize,
    reconcile: bool,
) -> ArmOut {
    let mut notes = Vec::new();
    let (rings, spans, fallback, dropped) = fit_captured(&mc.rings, k, policy);
    // CANON-FIX-1: when this arm reconciles, run the landed export-boundary
    // rounding reconcile between fit and the integer container: quantize to
    // the export grid, then the W2-2 constant-cubic cleanup. Measurements
    // below (segments, fit error, IoU, charstring) describe the reconciled
    // outline, i.e. what this arm would actually ship; every effect is a
    // typed note token. The charstring gate still refuses non-finite or
    // out-of-range coordinates as typed rows; reconcile never hides them.
    let mut rings = rings;
    if reconcile {
        let mut drawn = DrawnGlyph { glyph_id: glyph_name.to_string(), rings };
        let q = kni_core::rounding_reconcile::quantize_outline(&mut drawn);
        notes.push(format!(
            "reconcile_quantized:moved={}:max_delta={:.6}:non_finite={}",
            q.moved, q.max_abs_delta, q.non_finite
        ));
        let mut cffs = vec![CffGlyph { name: glyph_name.to_string(), advance: upm, outline: drawn }];
        let cc = kni_core::rounding_reconcile::drop_constant_cubics(&mut cffs);
        for d in &cc.dropped {
            notes.push(format!("constant_cubic_dropped:ring={}:span={}", d.ring_index, d.span_index));
        }
        for h in &cc.held {
            notes.push(format!("constant_cubic_held:ring={}:span={}:why={:?}", h.ring_index, h.span_index, h.why));
        }
        rings = cffs.into_iter().next().map(|g| g.outline.rings).unwrap_or_default();
    }
    let glyph = DrawnGlyph { glyph_id: glyph_name.to_string(), rings: rings.clone() };
    let cff_glyph = CffGlyph { name: glyph_name.to_string(), advance: upm, outline: glyph.clone() };
    // The integer container accepts exact-integer coordinates only (its
    // delta encoding is then faithful by construction), so container
    // acceptance IS the integer-charstring gate: accepted glyphs measure
    // exactly what the charstring encodes. A refusal is a typed finding
    // (the canonical chain emitted a non-integer or out-of-range
    // coordinate), never a silent skip.
    let (cs, container_accepted) = match charstring(&cff_glyph) {
        Ok(b) => (b, true),
        Err(e) => { notes.push(format!("charstring_refused:{e:?}")); (Vec::new(), false) }
    };
    let measured = rings.clone();
    let m = segment_metrics(&measured);
    let raw: Vec<Vec<Point>> = mc.rings.iter().map(|r| r.raw.clone()).collect();
    let (sfe, maxdev) = match fit_error_px(&raw, &measured, k, flatten_tol_px) {
        Some((s, d)) => (Some(s), Some(d)),
        None => { notes.push("fit_error_unassessable:ring_alignment".into()); (None, None) }
    };
    let (w, h) = (mc.width, mc.height);
    let cfg = EvalConfig {
        frame_id: format!("CAP-{}-SCAN{}-FITK-CFFINTEGER-RAWORIGIN", label, threshold),
        scale_k: k, threshold, canvas: (w, h), capture_eps, flatten_steps,
        expected_source_sha256: png_sha.to_string(), advance: upm,
        render_limits: RenderLimits { max_pixels: w * h, max_flatten_steps: flatten_steps, max_edges: w * h, max_working_bytes },
    };
    let iou = match ProductionEvaluator::new(cfg, png) {
        Ok(ev) => {
            let cover = ev.render_mask(&DrawnGlyph { glyph_id: glyph_name.to_string(), rings: measured.clone() }).ok();
            match cover {
                Some(cover) => {
                    let src = ev.source_mask();
                    let (mut inter, mut uni) = (0u64, 0u64);
                    for (i, &c) in cover.iter().enumerate() {
                        let s = src[i];
                        if c && s { inter += 1; }
                        if c || s { uni += 1; }
                    }
                    if uni == 0 { notes.push("iou_unassessable:empty_union".into()); None } else { Some(inter as f64 / uni as f64) }
                }
                None => { notes.push("iou_unassessable:render_refused".into()); None }
            }
        }
        Err(e) => { notes.push(format!("evaluator_refused:{e}")); None }
    };
    let _ = spans;
    ArmOut { rings, fallback, dropped, cs, container_accepted, line: m.line, cubic: m.cubic, sfe, maxdev, iou, notes }
}

fn byte_diff(a: &[u8], b: &[u8]) -> (bool, usize, Option<usize>, usize) {
    let n = a.len().min(b.len());
    let mut first = None; let mut count = a.len().abs_diff(b.len());
    for i in 0..n {
        if a[i] != b[i] {
            if first.is_none() { first = Some(i); }
            count += 1;
        }
    }
    (a == b, a.len() + b.len(), first, count)
}

fn main() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 8 {
        return Err("usage: canonical_path_run MANIFEST TILEDIR OUT_DIR THRESHOLD FLATTEN_STEPS FLATTEN_TOL_PX MAX_WORKING_BYTES".into());
    }
    let manifest_path = std::path::PathBuf::from(&a[1]);
    let tiledir = &a[2];
    let out_dir = std::path::PathBuf::from(&a[3]);
    let threshold: u8 = a[4].parse().map_err(|_| "invalid threshold")?;
    let flatten_steps: usize = a[5].parse().map_err(|_| "invalid flatten steps")?;
    let flatten_tol_px: f64 = a[6].parse().map_err(|_| "invalid flatten tol")?;
    let max_working_bytes: usize = a[7].parse().map_err(|_| "invalid working bytes")?;
    if !flatten_tol_px.is_finite() || flatten_tol_px <= 0.0 { return Err("invalid flatten tol".into()); }
    let text = std::fs::read_to_string(&manifest_path).map_err(|e| format!("manifest read: {e}"))?;
    let manifest_dir = manifest_path.parent().ok_or("manifest dir")?.to_path_buf();
    let cfg = parse_manifest(&text, tiledir, &manifest_dir)?;
    if !(cfg.scale.is_finite() && cfg.scale > 0.0) { return Err("invalid manifest scale".into()); }
    let policy = FitPolicy { squared_error: cfg.se, max_refits: cfg.refits };
    std::fs::create_dir_all(&out_dir).map_err(|e| format!("out dir: {e}"))?;

    let mut tsv = String::from("glyph\tcodepoint\tarm\tK\trings_in\trings_out\tdropped\tfallback\tsegments_line\tsegments_cubic\tsegments_total\tfit_error_sfe_px2\tfit_error_maxdev_px\tiou_scan_domain\tcharstring_len\tcharstring_sha256\tcharstring_eq_other_arm\tbyte_diff_first_offset\tbyte_diff_count\tcontainer_accepted\tnotes\n");
    let mut ledger = String::new();
    ledger.push_str(&format!("manifest_population_sha256\t{}\n", cfg.population));
    for k in &cfg.ignored_keys { ledger.push_str(&format!("manifest_ignored_key\t{k}\n")); }

    let mut font_glyphs_k1: Vec<CffGlyph> = Vec::new();
    let mut font_glyphs_prod: Vec<CffGlyph> = Vec::new();
    let mut rows = 0usize;

    for g in &cfg.glyphs {
        let png = match std::fs::read(&g.path) {
            Ok(b) => b,
            Err(e) => {
                tsv.push_str(&format!("{}\t{}\tBOTH\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\tread_error:{e}\n", g.name, g.cp));
                continue;
            }
        };
        let png_sha = sha256_hex(&png);
        let mc = match capture_png(&png, cfg.eps) {
            Ok(m) => m,
            Err(e) => {
                tsv.push_str(&format!("{}\t{}\tBOTH\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\tcapture_refused:{e}\n", g.name, g.cp));
                continue;
            }
        };
        let rings_in = mc.rings.len();
        let k1 = run_arm("K1", &mc, &png, &png_sha, 1.0, &policy, cfg.eps, cfg.upm, &g.name, threshold, flatten_steps, flatten_tol_px, max_working_bytes, true);
        let prod = run_arm("PROD", &mc, &png, &png_sha, cfg.scale, &policy, cfg.eps, cfg.upm, &g.name, threshold, flatten_steps, flatten_tol_px, max_working_bytes, false);
        let (eq, _tot, first, ndiff) = byte_diff(&k1.cs, &prod.cs);
        let diff_assessable = k1.container_accepted && prod.container_accepted;
        for (label, k, arm) in [("canonical_k1", 1.0f64, &k1), ("production", cfg.scale, &prod)] {
            tsv.push_str(&format!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                g.name, g.cp, label, k, rings_in, arm.rings.len(), arm.dropped, arm.fallback,
                arm.line, arm.cubic, arm.line + arm.cubic,
                arm.sfe.map(|v| format!("{v:.6}")).unwrap_or("n/a".into()),
                arm.maxdev.map(|v| format!("{v:.6}")).unwrap_or("n/a".into()),
                arm.iou.map(|v| format!("{v:.6}")).unwrap_or("n/a".into()),
                arm.cs.len(), sha256_hex(&arm.cs),
                if diff_assessable { eq.to_string() } else { "n/a".into() },
                if diff_assessable { first.map(|v| v.to_string()).unwrap_or("none".into()) } else { "n/a".into() },
                if diff_assessable { ndiff.to_string() } else { "n/a".into() },
                arm.container_accepted,
                if arm.notes.is_empty() { "-".into() } else { arm.notes.join("|") },
            ));
            rows += 1;
        }
        if k1.container_accepted {
            font_glyphs_k1.push(CffGlyph { name: g.name.clone(), advance: cfg.upm, outline: DrawnGlyph { glyph_id: g.name.clone(), rings: k1.rings.clone() } });
        } else {
            ledger.push_str(&format!("font_excluded_glyph\tcanonical_k1\t{}\tcontainer_refused\n", g.name));
        }
        if prod.container_accepted {
            font_glyphs_prod.push(CffGlyph { name: g.name.clone(), advance: cfg.upm, outline: DrawnGlyph { glyph_id: g.name.clone(), rings: prod.rings.clone() } });
        } else {
            ledger.push_str(&format!("font_excluded_glyph\tproduction\t{}\tcontainer_refused\n", g.name));
        }
    }

    // Whole-font CFF bytes per arm (notdef at GID0, manifest order after).
    let notdef = CffGlyph { name: ".notdef".into(), advance: cfg.upm, outline: DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] } };
    let mut font_rows = String::new();
    for (label, glyphs, file) in [("canonical_k1", &font_glyphs_k1, "canonical-k1.otf"), ("production", &font_glyphs_prod, "production.otf")] {
        let mut all = vec![notdef.clone()];
        all.extend(glyphs.iter().cloned());
        match cff_one(&cfg.ps_name, &all) {
            Ok(bytes) => {
                std::fs::write(out_dir.join(file), &bytes).map_err(|e| format!("font write: {e}"))?;
                font_rows.push_str(&format!("font\t{}\t{}\t{}\t{}\tglyphs={}\n", label, file, bytes.len(), sha256_hex(&bytes), glyphs.len() + 1));
            }
            Err(e) => font_rows.push_str(&format!("font\t{}\t{}\trefused\t{:?}\n", label, file, e)),
        }
    }

    std::fs::write(out_dir.join("measurements.tsv"), &tsv).map_err(|e| format!("tsv write: {e}"))?;
    std::fs::write(out_dir.join("ledger.tsv"), &ledger).map_err(|e| format!("ledger write: {e}"))?;
    std::fs::write(out_dir.join("fonts.tsv"), &font_rows).map_err(|e| format!("fonts write: {e}"))?;
    println!("rows={rows} glyphs={}", cfg.glyphs.len());
    println!("{font_rows}");
    Ok(())
}
