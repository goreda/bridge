//! curve_stress_run: node-economy baseline corpus + curve-quality proof
//! sheets for one style directory or a fixtures root.
//!
//! Usage:
//!   cargo run -p kni-core --example curve_stress_run -- \
//!     (--style-dir DIR | --fixtures-root DIR) \
//!     (--scale UNITS_PER_PX | --scale-tile-height-1000) \
//!     --rdp-eps-px F \
//!     (--fit-squared-error F | --fit-se-derived) \
//!     (--max-refits N | --max-refits-derived) \
//!     --out DIR
//!
//! --fixtures-root may also come from the KNI_CURVE_STRESS_FIXTURES env var.
//! With --fixtures-root every immediate subdirectory is one style (style
//! label = directory name); each .png/.jpg/.jpeg inside is one glyph
//! (glyph label = file stem). No defaults: every measurement parameter is
//! explicit or derived by the named derivation, so a corpus always records
//! exactly how it was produced (the header carries the config note and this
//! command line).
//!
//! Output: <out>/<style>.tsv (corpus document, see curve_stress::corpus_document)
//! and <out>/<style>/<glyph>.fit.png / <glyph>.ovl.png proof sheets.
//!
//! Mona's declared scale lives in the pipeline's declared style data
//! (pipeline/src/declared_convention.rs); pass it via --scale when building
//! the Mona corpus from the kit collection.

use kni_core::curve_stress::*;
use std::path::PathBuf;

fn die(msg: &str) -> ! {
    eprintln!("curve_stress_run: {msg}");
    std::process::exit(2);
}

fn parse_f(v: Option<String>, name: &str) -> f64 {
    v.and_then(|s| s.parse().ok()).unwrap_or_else(|| die(&format!("bad {name}")))
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut style_dir: Option<PathBuf> = None;
    let mut fixtures_root: Option<PathBuf> = None;
    let mut scale: Option<ScaleSpec> = None;
    let mut rdp: Option<f64> = None;
    let mut fit_se: Option<FitSeSpec> = None;
    let mut max_refits: Option<RefitSpec> = None;
    let mut out: Option<PathBuf> = None;
    while let Some(a) = args.next() {
        match a.as_str() {
            "--style-dir" => style_dir = Some(PathBuf::from(args.next().unwrap_or_else(|| die("--style-dir missing")))),
            "--fixtures-root" => fixtures_root = Some(PathBuf::from(args.next().unwrap_or_else(|| die("--fixtures-root missing")))),
            "--scale" => scale = Some(ScaleSpec::UnitsPerPx(parse_f(args.next(), "--scale"))),
            "--scale-tile-height-1000" => scale = Some(ScaleSpec::TileHeight1000),
            "--rdp-eps-px" => rdp = Some(parse_f(args.next(), "--rdp-eps-px")),
            "--fit-squared-error" => fit_se = Some(FitSeSpec::Value(parse_f(args.next(), "--fit-squared-error"))),
            "--fit-se-derived" => fit_se = Some(FitSeSpec::DerivedSourceQuantization),
            "--max-refits" => {
                let v = args.next().and_then(|s| s.parse().ok()).unwrap_or_else(|| die("bad --max-refits"));
                max_refits = Some(RefitSpec::Count(v));
            }
            "--max-refits-derived" => max_refits = Some(RefitSpec::Derived),
            "--out" => out = Some(PathBuf::from(args.next().unwrap_or_else(|| die("--out missing")))),
            other => die(&format!("unknown argument {other}")),
        }
    }
    if fixtures_root.is_none() {
        if let Ok(env) = std::env::var(ENV_FIXTURES) {
            if !env.is_empty() {
                fixtures_root = Some(PathBuf::from(env));
            }
        }
    }
    if style_dir.is_some() == fixtures_root.is_some() {
        die("exactly one of --style-dir or --fixtures-root (or KNI_CURVE_STRESS_FIXTURES) is required");
    }
    let cfg = GlyphRunConfig {
        scale: scale.unwrap_or_else(|| die("scale is required (--scale or --scale-tile-height-1000)")),
        rdp_eps_px: rdp.unwrap_or_else(|| die("--rdp-eps-px is required")),
        fit_se: fit_se.unwrap_or_else(|| die("fit error is required (--fit-squared-error or --fit-se-derived)")),
        max_refits: max_refits.unwrap_or_else(|| die("max refits is required (--max-refits or --max-refits-derived)")),
    };
    let out = out.unwrap_or_else(|| die("--out is required"));
    let style_dirs: Vec<PathBuf> = match (style_dir, fixtures_root) {
        (Some(d), None) => vec![d],
        (None, Some(root)) => {
            let mut dirs: Vec<PathBuf> = std::fs::read_dir(&root)
                .unwrap_or_else(|e| die(&format!("cannot read fixtures root: {e}")))
                .filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| p.is_dir())
                .collect();
            dirs.sort();
            dirs
        }
        _ => unreachable!(),
    };
    let note = config_note(&cfg);
    let regen = format!("curve_stress_run {}", std::env::args().skip(1).collect::<Vec<_>>().join(" "));
    for dir in &style_dirs {
        let style = dir.file_name().and_then(|s| s.to_str()).unwrap_or_else(|| die("style dir has no usable name")).to_string();
        let mut tiles: Vec<PathBuf> = std::fs::read_dir(dir)
            .unwrap_or_else(|e| die(&format!("cannot read {}: {e}", dir.display())))
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| {
                p.extension().and_then(|e| e.to_str())
                    .map(|e| matches!(e.to_ascii_lowercase().as_str(), "png" | "jpg" | "jpeg"))
                    .unwrap_or(false)
            })
            .collect();
        tiles.sort();
        if tiles.is_empty() {
            eprintln!("curve_stress_run: {}: no tile images, skipped", dir.display());
            continue;
        }
        let proof_dir = out.join(&style);
        std::fs::create_dir_all(&proof_dir).unwrap_or_else(|e| die(&format!("cannot create {}: {e}", proof_dir.display())));
        // Glyph probes are independent: parallelize across the available
        // cores. Row order is restored by corpus_document's glyph sort, so
        // output stays byte-deterministic regardless of scheduling.
        let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
        let chunks = workers.min(tiles.len());
        let mut chunk_tiles: Vec<Vec<PathBuf>> = vec![Vec::new(); chunks];
        for (i, t) in tiles.iter().enumerate() {
            chunk_tiles[i % chunks].push(t.clone());
        }
        let done = std::sync::atomic::AtomicUsize::new(0);
        let total = tiles.len();
        let results: Vec<Vec<(String, Result<GlyphRun, String>)>> = std::thread::scope(|scope| {
            let mut handles = Vec::new();
            for chunk in &chunk_tiles {
                let style = &style;
                let proof_dir = &proof_dir;
                let done = &done;
                handles.push(scope.spawn(move || {
                    let mut out_rows = Vec::new();
                    for tile in chunk {
                        let glyph = tile.file_stem().and_then(|s| s.to_str()).unwrap().to_string();
                        let run = std::fs::read(tile)
                            .map_err(|e| format!("cannot read {}: {e}", tile.display()))
                            .and_then(|bytes| run_glyph(style, &glyph, &bytes, &cfg));
                        if let Ok(run) = &run {
                            let _ = std::fs::write(proof_dir.join(format!("{glyph}.fit.png")), &run.fit_png);
                            let _ = std::fs::write(proof_dir.join(format!("{glyph}.ovl.png")), &run.overlay_png);
                        }
                        let n = done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
                        if n % 25 == 0 || n == total {
                            eprintln!("curve_stress_run: {style}: {n}/{total}");
                        }
                        out_rows.push((glyph, run));
                    }
                    out_rows
                }));
            }
            handles.into_iter().map(|h| h.join().unwrap_or_else(|_| die("worker panicked"))).collect()
        });
        let mut rows = Vec::new();
        for chunk in results {
            for (glyph, run) in chunk {
                match run {
                    Ok(run) => rows.push(run.row),
                    Err(e) => eprintln!("curve_stress_run: {style}/{glyph}: {e}"),
                }
            }
        }
        if rows.is_empty() {
            eprintln!("curve_stress_run: {style}: no measurable glyphs, no corpus written");
            continue;
        }
        let doc = corpus_document(&style, &note, &regen, &rows).unwrap_or_else(|e| die(&e));
        let path = out.join(format!("{style}.tsv"));
        std::fs::write(&path, doc).unwrap_or_else(|e| die(&format!("cannot write {}: {e}", path.display())));
        eprintln!("curve_stress_run: {}: {} glyphs -> {}", style, rows.len(), path.display());
    }
}
