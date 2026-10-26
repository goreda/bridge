//! curve_stress_race: four-engine R/g joint-quality race. Applies the
//! curve_stress joint analysis to KNI (production capture+fit on the
//! selection tiles) and to the potrace/autotrace/vtracer tracer SVGs
//! (W6 tracer-svgs.zip). Per engine/font/glyph row: node economy, G1
//! tangent breaks (corners), G2 curvature breaks with severity mean/max,
//! per-node rates. Tracer floors derive from each file's own decimal
//! emission step (analyze_rings_with_grid); KNI's floor is the integer
//! font-unit grid. KNI runs use the production manifest fit parameters and
//! the style's declared em (parsed from pipeline's declared_convention.rs,
//! never copied by hand).
//!
//! Usage: curve_stress_race --selection <selection.tsv> --tiles-root <dir>
//!   --svgs-root <dir> --declared <declared_convention.rs> --out <dir>

use kni_core::curve_stress::*;
use kni_core::reference_slice::{Point, Span};
use std::path::{Path, PathBuf};

struct Entry { font: String, style: String, glyph: String, tile_file: String }

fn slug(font: &str, style: &str) -> String {
    format!("{font}/{style}").replace(' ', "").replace('/', "-")
}

fn parse_declared_scales(path: &Path) -> Vec<(String, f64)> {
    let text = std::fs::read_to_string(path).expect("read declared_convention.rs");
    let mut out = Vec::new();
    for line in text.lines() {
        if !line.contains("DeclaredRecord {") { continue; }
        let sid = line.split("style_id: \"").nth(1).and_then(|r| r.split('"').next());
        let em = line.split("em_px: ").nth(1)
            .and_then(|r| r.split([',', ' ']).next())
            .and_then(|v| v.trim_end_matches(".0").parse::<f64>().ok().or_else(|| format!("{v}").parse().ok()));
        if let (Some(sid), Some(em)) = (sid, em) {
            out.push((sid.to_string(), 1000.0 / em));
        }
    }
    out
}

struct Row {
    engine: String, font: String, glyph: String,
    nodes: usize, cubics: usize, lines: usize, rings: usize,
    g1: usize, g2: usize, unavail: usize,
    sev_sum: f64, sev_max: f64, half_coord: f64, white_skipped: usize,
}

fn row_from_stress(engine: &str, font: &str, glyph: &str, s: &GlyphStress, half: f64, white: usize) -> Row {
    let sev_sum: f64 = s.joints.iter().filter(|j| j.kind == JointKind::CurvatureBreak).map(|j| j.severity).sum();
    Row {
        engine: engine.into(), font: font.into(), glyph: glyph.into(),
        nodes: s.nodes, cubics: s.cubics, lines: s.lines, rings: s.rings,
        g1: s.corners, g2: s.curvature_breaks, unavail: s.unavailable_joints,
        sev_sum, sev_max: s.max_break_severity, half_coord: half, white_skipped: white,
    }
}

/// SVG-space rings to a tile-canvas overlay: user units -> pixels via the
/// viewBox (or 1:1 when absent), then y-down -> canvas y-up.
fn svg_overlay(svg: &SvgOutline, tile_w: usize, tile_h: usize, tile_gray: &[u8]) -> Result<Vec<u8>, String> {
    let (sx, sy, ox, oy) = match svg.view_box {
        Some(vb) => (tile_w as f64 / vb[2], tile_h as f64 / vb[3], vb[0], vb[1]),
        None => (1.0, 1.0, 0.0, 0.0),
    };
    let to_canvas = |p: Point| -> (f64, f64) {
        let u = affine_apply(&svg.group_transform, p);
        ((u.x - ox) * sx, (tile_h as f64 - 1.0) - (u.y - oy) * sy)
    };
    let tol_user = 0.5 / sx.max(1e-9); // half output pixel in user units
    let mut overlay: Vec<u8> = tile_gray.iter()
        .map(|&v| (OVERLAY_DIM_BASE + (v as u16) / 2) as u8).collect();
    for ring in &svg.rings {
        let flat: Vec<(f64, f64)> = flatten_ring(ring, tol_user).iter().map(|&p| to_canvas(p)).collect();
        draw_polyline(&mut overlay, tile_w, tile_h, &flat, true, OVERLAY_OUTLINE);
        let mut prev = to_canvas(ring.start);
        draw_marker(&mut overlay, tile_w, tile_h, prev, 2, OVERLAY_OUTLINE);
        for s in &ring.spans {
            match s {
                Span::Line { end } => {
                    let e = to_canvas(*end);
                    draw_marker(&mut overlay, tile_w, tile_h, e, 2, OVERLAY_OUTLINE);
                    prev = e;
                }
                Span::Cubic { control_one, control_two, end } => {
                    let c1 = to_canvas(*control_one);
                    let c2 = to_canvas(*control_two);
                    let e = to_canvas(*end);
                    draw_polyline(&mut overlay, tile_w, tile_h, &[prev, c1], false, OVERLAY_HANDLE);
                    draw_polyline(&mut overlay, tile_w, tile_h, &[e, c2], false, OVERLAY_HANDLE);
                    draw_marker(&mut overlay, tile_w, tile_h, c1, 1, OVERLAY_HANDLE);
                    draw_marker(&mut overlay, tile_w, tile_h, c2, 1, OVERLAY_HANDLE);
                    draw_marker(&mut overlay, tile_w, tile_h, e, 2, OVERLAY_OUTLINE);
                    prev = e;
                }
            }
        }
    }
    Ok(overlay)
}

fn run_one_entry(
    e: &Entry, scales: &[(String, f64)], tiles_root: &Path, svgs_root: &Path,
    out: &Path, cfg: &GlyphRunConfig,
) -> Vec<Row> {
    let mut rows = Vec::new();
    let style_id = format!("{}/{}", e.font, e.style);
    let sl = slug(&e.font, &e.style);
    let tile = tiles_root.join(&e.font).join(&e.style).join("glyph").join(&e.tile_file);
    let bytes = std::fs::read(&tile).unwrap_or_else(|_| panic!("read {}", tile.display()));
    // KNI: production capture+fit at the declared style scale.
    let scale = scales.iter().find(|(s, _)| s == &style_id)
        .unwrap_or_else(|| panic!("no declared record for {style_id}")).1;
    let run = run_glyph(&style_id, &format!("{sl}-{}", e.glyph), &bytes,
        &GlyphRunConfig { scale: ScaleSpec::UnitsPerPx(scale), ..*cfg }).expect("kni run_glyph");
    rows.push(row_from_stress("kni", &style_id, &e.glyph, &run.row.metrics, 0.5, 0));
    std::fs::write(out.join("ovl").join(format!("kni_{sl}-{}.ovl.png", e.glyph)), &run.overlay_png).unwrap();
    eprintln!("kni {style_id} {} done", e.glyph);
    // Tracers: joint analysis of the emitted SVG geometry.
    // Tiles may be PNG or JPEG (Paul New): go through the dispatch decode.
    let src = kni_core::capture_dispatch::capture_source(&bytes, 0.25, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS)
        .expect("decode tile");
    let (tw, th, tgray) = (src.contour.width, src.contour.height, src.gray);
    for engine in ["potrace", "autotrace", "vtracer"] {
        let svg_path = svgs_root.join(engine).join(format!("{sl}-{}.svg", e.glyph));
        let xml = match std::fs::read_to_string(&svg_path) {
            Ok(x) => x,
            Err(err) => { eprintln!("MISSING {}: {err}", svg_path.display()); continue; }
        };
        let svg = parse_svg_outline(&xml).expect("parse svg");
        let stress = analyze_rings_with_grid(&svg.rings, svg.half_coord).expect("analyze svg");
        rows.push(row_from_stress(engine, &style_id, &e.glyph, &stress, svg.half_coord, svg.white_paths_skipped));
        let ovl = svg_overlay(&svg, tw, th, &tgray).expect("svg overlay");
        let png = encode_png_gray(tw, th, &ovl).expect("encode ovl");
        std::fs::write(out.join("ovl").join(format!("{engine}_{sl}-{}.ovl.png", e.glyph)), &png).unwrap();
    }
    rows
}

fn run_entries(
    entries: &[Entry], scales: &[(String, f64)], tiles_root: &Path, svgs_root: &Path,
    out: &Path, cfg: GlyphRunConfig, _rows: Vec<Row>,
) -> Vec<Row> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;
    let next = AtomicUsize::new(0);
    let collected: Mutex<Vec<Row>> = Mutex::new(Vec::new());
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= entries.len() { break; }
                let rs = run_one_entry(&entries[i], scales, tiles_root, svgs_root, out, &cfg);
                collected.lock().unwrap().extend(rs);
            });
        }
    });
    let mut rows = collected.into_inner().unwrap();
    rows.sort_by(|a, b| (&a.engine, &a.font, &a.glyph).cmp(&(&b.engine, &b.font, &b.glyph)));
    rows
}

fn main() {
    let mut selection: Option<PathBuf> = None;
    let mut tiles_root: Option<PathBuf> = None;
    let mut svgs_root: Option<PathBuf> = None;
    let mut declared: Option<PathBuf> = None;
    let mut out: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--selection" => selection = args.next().map(PathBuf::from),
            "--tiles-root" => tiles_root = args.next().map(PathBuf::from),
            "--svgs-root" => svgs_root = args.next().map(PathBuf::from),
            "--declared" => declared = args.next().map(PathBuf::from),
            "--out" => out = args.next().map(PathBuf::from),
            other => { eprintln!("unknown arg {other}"); std::process::exit(2); }
        }
    }
    let (selection, tiles_root, svgs_root, declared, out) =
        match (selection, tiles_root, svgs_root, declared, out) {
            (Some(a), Some(b), Some(c), Some(d), Some(e)) => (a, b, c, d, e),
            _ => { eprintln!("need --selection --tiles-root --svgs-root --declared --out"); std::process::exit(2); }
        };
    std::fs::create_dir_all(out.join("ovl")).expect("mkdir");
    let scales = parse_declared_scales(&declared);
    let sel = std::fs::read_to_string(&selection).expect("read selection.tsv");
    let mut entries = Vec::new();
    for line in sel.lines().skip(1) {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() < 5 { continue; }
        let tile_file = Path::new(f[4]).file_name().unwrap().to_string_lossy().to_string();
        entries.push(Entry { font: f[0].into(), style: f[1].into(), glyph: f[2].into(), tile_file });
    }
    let cfg = GlyphRunConfig {
        scale: ScaleSpec::UnitsPerPx(1.0), // replaced per style below
        rdp_eps_px: 0.25, fit_se: FitSeSpec::Value(0.25), max_refits: RefitSpec::Count(8),
    };
    let rows = run_entries(&entries, &scales, &tiles_root, &svgs_root, &out, cfg, Vec::new());
    // Per-glyph rows
    let mut tsv = String::from(
        "engine\tfont\tglyph\tnodes\tcubics\tlines\trings\tg1_breaks\tg2_breaks\tg1_per_node\tg2_per_node\tsev_mean_g2\tsev_max_g2\thalf_coord\twhite_paths_skipped\n");
    let emit = |tsv: &mut String, engine: &str, font: &str, glyph: &str, r: &Row| {
        let sev_mean = if r.g2 > 0 { r.sev_sum / r.g2 as f64 } else { 0.0 };
        tsv.push_str(&format!(
            "{engine}\t{font}\t{glyph}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{sev_mean}\t{}\t{}\t{}\n",
            r.nodes, r.cubics, r.lines, r.rings, r.g1, r.g2,
            r.g1 as f64 / r.nodes.max(1) as f64, r.g2 as f64 / r.nodes.max(1) as f64,
            r.sev_max, r.half_coord, r.white_skipped));
    };
    for r in &rows { emit(&mut tsv, &r.engine, &r.font, &r.glyph, r); }
    // Per-style aggregates
    tsv.push('\n');
    let mut styles: Vec<(String, String)> = rows.iter().map(|r| (r.engine.clone(), r.font.clone())).collect();
    styles.sort(); styles.dedup();
    for (eng, font) in styles {
        let rs: Vec<&Row> = rows.iter().filter(|r| r.engine == eng && r.font == font).collect();
        let agg = Row {
            engine: eng.clone(), font: font.clone(), glyph: "BOTH".into(),
            nodes: rs.iter().map(|r| r.nodes).sum(), cubics: rs.iter().map(|r| r.cubics).sum(),
            lines: rs.iter().map(|r| r.lines).sum(), rings: rs.iter().map(|r| r.rings).sum(),
            g1: rs.iter().map(|r| r.g1).sum(), g2: rs.iter().map(|r| r.g2).sum(),
            unavail: rs.iter().map(|r| r.unavail).sum(),
            sev_sum: rs.iter().map(|r| r.sev_sum).sum(),
            sev_max: rs.iter().map(|r| r.sev_max).fold(0.0, f64::max),
            half_coord: rs[0].half_coord, white_skipped: rs.iter().map(|r| r.white_skipped).sum(),
        };
        emit(&mut tsv, &agg.engine, &agg.font, &agg.glyph, &agg);
    }
    std::fs::write(out.join("race.tsv"), &tsv).unwrap();
    // Worst-5 per engine by (g2 desc, sev_sum desc): copy overlays with rank names
    let worst_dir = out.join("worst");
    std::fs::create_dir_all(&worst_dir).unwrap();
    for engine in ["kni", "potrace", "autotrace", "vtracer"] {
        let mut rs: Vec<&Row> = rows.iter().filter(|r| r.engine == engine).collect();
        rs.sort_by(|a, b| b.g2.cmp(&a.g2).then(b.sev_sum.partial_cmp(&a.sev_sum).unwrap()));
        for (rank, r) in rs.iter().take(5).enumerate() {
            let sl = slug_from_style(&r.font);
            let name = format!("{engine}_{sl}-{}.ovl.png", r.glyph);
            let src = out.join("ovl").join(&name);
            if src.exists() {
                std::fs::copy(&src, worst_dir.join(format!("rank{}_{name}", rank + 1))).unwrap();
            }
        }
    }
    eprintln!("rows: {}", rows.len());
}

fn slug_from_style(style_id: &str) -> String {
    style_id.replace(' ', "").replace('/', "-")
}
