//! Stage ablation for the four-way race (chief review, item 5): measures
//! scan-domain IoU at every observable stage of the KNI chain on the same
//! population, plus the potrace mask, so the IoU gap is attributed to a
//! stage instead of asserted. Stages: capture (raw contour polylines),
//! fit (fit_captured at production K, float - exactly what the canonical
//! harness's production arm measures), round (export-grid quantize +
//! constant-cubic cleanup), shipped (integer charstrings decoded from the
//! shipped CFF read back through cff_reader). The pre-node/post-node split
//! inside fit_captured is not a public boundary; every public stage is
//! covered. Consecutive-stage mask XOR counts localize the loss.
//!
//! Usage: stage_ablation MANIFEST TILEDIR WRAPPED_OTF POTRACE_SVGDIR \
//!     THRESHOLD FLATTEN_STEPS OUT_TSV
use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::cff_container::CffGlyph;
use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_core::cubic_fit::FitPolicy;
use kni_core::economy_eval::{EvalConfig, ProductionEvaluator, RenderLimits};
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

// Shares the manifest/SVG parser with the race harness so both measure with
// the same code; only the parser entry points are used here.
#[allow(dead_code)]
#[path = "race_external.rs"]
mod race;

/// Render + compare. Any refusal - including a cover/source mask length
/// mismatch - is a typed error, so a mismatched row can never enter the
/// paired universe: callers map the error to NaN and the all_finite gate
/// excludes it.
fn iou_of(ev: &ProductionEvaluator, rings: &[ReferenceRing]) -> Result<(f64, Vec<bool>), String> {
    let cover = ev.render_mask(&DrawnGlyph { glyph_id: "g".into(), rings: rings.to_vec() }).map_err(|e| format!("render_refused:{e:?}"))?;
    let src = ev.source_mask();
    if cover.len() != src.len() { return Err(format!("mask_len:cover:{}:src:{}", cover.len(), src.len())); }
    let (mut inter, mut uni) = (0u64, 0u64);
    for (i, &c) in cover.iter().enumerate() {
        let s = src[i];
        if c && s { inter += 1; }
        if c || s { uni += 1; }
    }
    if uni == 0 { Err("empty_union".into()) } else { Ok((inter as f64 / uni as f64, cover)) }
}

fn main() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 8 {
        return Err("usage: stage_ablation MANIFEST TILEDIR WRAPPED_OTF POTRACE_SVGDIR THRESHOLD FLATTEN_STEPS OUT_TSV".into());
    }
    let manifest_path = std::path::PathBuf::from(&a[1]);
    let tiledir = &a[2];
    let otf_path = &a[3];
    let potrace_dir = &a[4];
    let threshold: u8 = a[5].parse().map_err(|_| "bad threshold")?;
    let flatten_steps: usize = a[6].parse().map_err(|_| "bad flatten")?;
    let out_path = &a[7];
    let text = String::from_utf8(race::read_capped(&a[1], race::MAX_MANIFEST_BYTES, "manifest")?).map_err(|_| "manifest: not utf8".to_string())?;
    let _ = &manifest_path;
    let mc_cfg = race::parse_manifest(&text, tiledir)?;
    let bytes = race::read_capped(otf_path, race::MAX_OTF_BYTES, "otf")?;
    let sha = sha256_hex(&bytes);
    let font = CffReader::from_bytes(&bytes, &sha).map_err(|e| format!("otf parse: {e:?}"))?;
    let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };

    let mut tsv = String::from("glyph\tiou_capture\tiou_fit\tiou_fit_economy\tiou_round\tiou_shipped\tiou_potrace\txor_capture_fit\txor_fit_round\txor_round_shipped\txor_shipped_potrace\tnodes_fit\tnodes_fit_economy\tnodes_shipped\tnotes\n");
    let (mut sum_c, mut sum_f, mut sum_fe, mut sum_r, mut sum_s, mut sum_p) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    let mut n_ok = 0usize;
    for g in &mc_cfg.glyphs {
        let mut notes: Vec<String> = Vec::new();
        let png = match race::read_capped(&g.path, race::MAX_TILE_BYTES, "tile") { Ok(b) => b, Err(e) => { tsv.push_str(&format!("{}\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\ttile_read_error:{e},NOT_REACHED:stage_nan\n", g.name)); continue; } };
        let png_sha = sha256_hex(&png);
        if let Err(e) = race::verify_tile_pin(&g.path, &png_sha) { tsv.push_str(&format!("{}\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t{e},NOT_REACHED:stage_nan\n", g.name)); continue; }
        let mc = match capture_png(&png, mc_cfg.eps) { Ok(m) => m, Err(e) => { tsv.push_str(&format!("{}\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\tcapture_refused:{e}\n", g.name)); continue; } };
        let (w, h) = (mc.width, mc.height);
        let mk_ev = |k: f64| ProductionEvaluator::new(EvalConfig {
            frame_id: format!("ABL-SCAN{threshold}"), scale_k: k, threshold, canvas: (w, h),
            capture_eps: mc_cfg.eps, flatten_steps, expected_source_sha256: png_sha.clone(),
            advance: mc_cfg.upm,
            render_limits: RenderLimits { max_pixels: w * h, max_flatten_steps: flatten_steps, max_edges: 16 * w * h, max_working_bytes: 268435456 },
        }, &png);
        let ev1 = mk_ev(1.0)?; // capture-stage rings are in px
        let evk = mk_ev(mc_cfg.scale)?; // later stages in font units at production K
        // stage 1: capture raw polylines
        // capture ring points are already in the evaluator's frame: y-up px,
        // bbox-relative (capture.rs "font coords: y up (flip), keep raw pixel
        // scale"); the evaluator adds the capture origin itself at k=1.
        let cap_rings: Vec<ReferenceRing> = mc.rings.iter().map(|r| {
            let conv = |p: Point| p;
            let pts = if r.raw.len() >= 3 { &r.raw } else { &r.points };
            let mut spans = Vec::new();
            for i in 1..pts.len() { spans.push(Span::Line { end: conv(pts[i]) }); }
            ReferenceRing { start: conv(pts[0]), spans }
        }).collect();
        let (iou_c, mask_c) = match iou_of(&ev1, &cap_rings) { Ok(x) => x, Err(e) => { notes.push(format!("capture_iou:{e}")); (f64::NAN, Vec::new()) } };
        // stage 2: fit (float, production K) - the canonical production arm
        let (fit_rings, _, _, _) = fit_captured(&mc.rings, mc_cfg.scale, &policy);
        let (iou_f, mask_f) = match iou_of(&evk, &fit_rings) { Ok(x) => x, Err(e) => { notes.push(format!("fit_iou:{e}")); (f64::NAN, Vec::new()) } };
        // stage 2b: fit with economy enabled (same fit_captured_economy_candidate
        // path, enable_economy=true) - measures economy's contribution directly,
        // since production fit_captured wires enable_economy=false (capture_fit.rs).
        let (eco_rings, _, _, _, _decisions) = kni_core::capture_fit::fit_captured_with_economy(&mc.rings, mc_cfg.scale, &policy);
        let nodes_fe: usize = eco_rings.iter().map(|r| r.spans.len()).sum();
        let (iou_fe, _mask_fe) = match iou_of(&evk, &eco_rings) { Ok(x) => x, Err(e) => { notes.push(format!("fit_economy_iou:{e}")); (f64::NAN, Vec::new()) } };
        // stage 3: round (quantize + constant-cubic cleanup)
        let mut drawn = DrawnGlyph { glyph_id: g.name.clone(), rings: fit_rings.clone() };
        let q = kni_core::rounding_reconcile::quantize_outline(&mut drawn);
        let mut cffs = vec![CffGlyph { name: g.name.clone(), advance: mc_cfg.upm, outline: drawn }];
        let _cc = kni_core::rounding_reconcile::drop_constant_cubics(&mut cffs);
        let round_rings = cffs.into_iter().next().map(|g2| g2.outline.rings).unwrap_or_default();
        if q.non_finite > 0 { notes.push(format!("non_finite:{}", q.non_finite)); }
        let (iou_r, mask_r) = match iou_of(&evk, &round_rings) { Ok(x) => x, Err(e) => { notes.push(format!("round_iou:{e}")); (f64::NAN, Vec::new()) } };
        // stage 4: shipped readback
        let cp = u32::from_str_radix(g.cp.trim_start_matches("0x"), 16).map_err(|_| "bad cp")?;
        let (iou_s, mask_s, nodes_s) = match font.read_codepoint(cp) {
            Ok(Some(rg)) => {
                let rings = rg.drawn(g.name.clone()).rings;
                let nodes: usize = rings.iter().map(|r| r.spans.len()).sum();
                match iou_of(&evk, &rings) { Ok((v, m)) => (v, m, nodes), Err(e) => { notes.push(format!("shipped_iou:{e}")); (f64::NAN, Vec::new(), nodes) } }
            }
            Ok(None) => { notes.push("not_shipped:container_refusal".into()); (f64::NAN, Vec::new(), 0) }
            Err(e) => { notes.push(format!("readback_refused:{e:?}")); (f64::NAN, Vec::new(), 0) }
        };
        // potrace mask
        let (iou_p, mask_p) = match race::read_capped(&format!("{potrace_dir}/{}.svg", g.name), race::MAX_SVG_BYTES, "svg").and_then(|b| String::from_utf8(b).map_err(|_| "svg: not utf8".to_string())) {
            Ok(svg) => match race::parse_svg(&svg, "potrace", (w, h)) {
                Ok(parsed) => {
                    let rings: Vec<ReferenceRing> = parsed.into_iter().map(|(start, spans, _)| {
                        let conv = |p: Point| Point { x: p.x - mc.origin_x, y: -p.y - mc.origin_y };
                        ReferenceRing { start: conv(start), spans: spans.iter().map(|s| match s {
                            Span::Line { end } => Span::Line { end: conv(*end) },
                            Span::Cubic { control_one, control_two, end } => Span::Cubic { control_one: conv(*control_one), control_two: conv(*control_two), end: conv(*end) },
                        }).collect() }
                    }).collect();
                    match iou_of(&ev1, &rings) { Ok(x) => x, Err(e) => { notes.push(format!("potrace_iou:{e}")); (f64::NAN, Vec::new()) } }
                }
                Err(e) => { notes.push(format!("potrace_parse:{e}")); (f64::NAN, Vec::new()) }
            },
            Err(e) => { notes.push(format!("potrace_svg:{e}")); (f64::NAN, Vec::new()) }
        };
        let xor = |a: &[bool], b: &[bool]| -> String {
            if a.is_empty() || b.is_empty() { return "-".into(); }
            if a.len() != b.len() { return format!("NOT_REACHED:mask_len:{}:{}", a.len(), b.len()); }
            a.iter().zip(b.iter()).filter(|(x, y)| x != y).count().to_string()
        };
        let nodes_f: usize = fit_rings.iter().map(|r| r.spans.len()).sum();
        // Exact paired universe: a glyph enters every summary only when ALL
        // stages produced a finite IoU on the same canvas; anything else is
        // a typed NOT_REACHED row and is excluded from every mean.
        let all_finite = [iou_c, iou_f, iou_fe, iou_r, iou_s, iou_p].iter().all(|v| v.is_finite());
        let note = if notes.is_empty() { "-".into() } else { notes.join(",") };
        let note = if all_finite { note } else if note == "-" { "NOT_REACHED:stage_nan".into() } else { format!("{note},NOT_REACHED:stage_nan") };
        let f6 = |v: f64| if v.is_finite() { format!("{v:.6}") } else { "-".into() };
        tsv.push_str(&format!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
            g.name, f6(iou_c), f6(iou_f), f6(iou_fe), f6(iou_r), f6(iou_s), f6(iou_p),
            xor(&mask_c, &mask_f), xor(&mask_f, &mask_r), xor(&mask_r, &mask_s), xor(&mask_s, &mask_p),
            nodes_f, nodes_fe, nodes_s, note
        ));
        if all_finite {
            sum_c += iou_c; sum_f += iou_f; sum_fe += iou_fe; sum_r += iou_r; sum_s += iou_s; sum_p += iou_p;
            n_ok += 1;
        }
    }
    if n_ok == 0 { return Err("no glyph reached all stages".into()); }
    println!("n={} capture={:.6} fit={:.6} fit_economy={:.6} round={:.6} shipped={:.6} potrace={:.6}",
        n_ok, sum_c / n_ok as f64, sum_f / n_ok as f64, sum_fe / n_ok as f64, sum_r / n_ok as f64, sum_s / n_ok as f64, sum_p / n_ok as f64);
    std::fs::write(out_path, tsv).map_err(|e| format!("write: {e}"))?;
    Ok(())
}
