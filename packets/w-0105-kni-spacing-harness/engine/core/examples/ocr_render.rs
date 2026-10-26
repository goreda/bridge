//! OCR font renderer core (W1, KNI-side integration plan 2026-10-20-1700):
//! rasterize each requested codepoint's outline from an OTF (CFF/Type2) into
//! an 8-bit grayscale tile, written as binary PGM (P5), one file per glyph.
//!
//! Usage: ocr_render OTF CODEPOINTS_FILE SIZE_PX OUT_DIR
//!
//!   OTF              font file; read once, capped, sha256-pinned before parse
//!   CODEPOINTS_FILE  ASCII text, one codepoint per line: `U+0041`, `0x41` or
//!                    bare hex `41`; `#` comment lines and blank lines allowed;
//!                    duplicates, surrogates and malformed rows are refusals
//!   SIZE_PX          square tile edge in pixels (4..=4096)
//!   OUT_DIR          output directory; created if missing
//!
//! Every failure is a typed refusal on stderr (`refusal\t<code>\t<detail>`,
//! exit 1); nothing falls back silently (contract v4 draft REFUSALS clause).
//! The run record on stdout carries the renderer determinism pin fields
//! (engine, version, hinting, AA mode, raster size; contract v4 draft
//! RENDERER DETERMINISM PIN clause). Each glyph is rendered twice and the run
//! refuses if the two rasters differ (render-twice self-check, same clause).
//!
//! TAHMIN marks (pending contract-v4 conformance ruling; W2 owns the
//! conformance test): the em window framing, the AA supersample factor, the
//! adaptive flatten tolerance/depth and the engine name/version string are
//! KNI-side choices, not OCR-pinned values.

use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_core::economy_eval::canon;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

// ---------- input caps (same pattern as examples/tile_to_pbm.rs) ----------
/// One open, take(cap + 1), typed refusal over cap. No metadata-length check,
/// never an unbounded read.
fn read_capped(path: &str, cap: u64, what: &str) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let f = std::fs::File::open(path).map_err(|e| format!("{what} open: {e}"))?;
    let mut buf = Vec::new();
    f.take(cap + 1).read_to_end(&mut buf).map_err(|e| format!("{what} read: {e}"))?;
    if buf.len() as u64 > cap { return Err(format!("{what} over {cap} bytes")); }
    Ok(buf)
}

const MAX_OTF_BYTES: u64 = 64 * 1024 * 1024;
const MAX_CODEPOINTS_BYTES: u64 = 1024 * 1024;
const MAX_CODEPOINTS: usize = 65536;
const MIN_SIZE_PX: u32 = 4;
const MAX_SIZE_PX: u32 = 4096;
/// Flatten/fill vector budgets, independent of raster resolution.
const MAX_EDGES: usize = 4_000_000;

// ---------- render pins (TAHMIN: KNI-side choice until contract ruling) ----
const ENGINE_NAME: &str = "kni-ocr_render";
const ENGINE_VERSION: &str = "0.1.0";
/// Anti-aliasing: SS x SS sub-sample grid per pixel, nonzero winding fill.
const SS: usize = 8;
const AA_MODE: &str = "supersample-8x8-nonzero";
/// Adaptive cubic flattening: chord flatness tolerance in canvas pixels and
/// the subdivision depth cap. Resolution-independent (scales with SIZE_PX).
const FLATTEN_TOL_PX: f64 = 0.05;
const FLATTEN_MAX_DEPTH: u32 = 16;
/// Font-space render window: [-0.25 em, +1.25 em] on both axes, so the em
/// square occupies the central 2/3 of the tile and descenders/accents keep
/// a fixed margin. Per (font, codepoint, size) the window is constant, so
/// tiles are byte-stable across runs and codepoint lists.
const WINDOW_LO_EM: f64 = -0.25;
const WINDOW_HI_EM: f64 = 1.25;

fn refusal(code: &str, detail: &str) -> String {
    format!("{code}\t{detail}")
}

fn ascii_arg(arg: &str, what: &str) -> Result<(), String> {
    if arg.is_empty() || !arg.is_ascii() {
        return Err(refusal("non_ascii_path", &format!("{what}: {arg:?}")));
    }
    Ok(())
}

// ---------- codepoints file ----------
fn parse_codepoints(text: &[u8]) -> Result<Vec<u32>, String> {
    if !text.is_ascii() {
        return Err(refusal("bad_codepoints", "file is not ASCII"));
    }
    let s = std::str::from_utf8(text).map_err(|_| refusal("bad_codepoints", "not utf8"))?;
    let mut out: Vec<u32> = Vec::new();
    for (lineno, raw) in s.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        let hex = line
            .strip_prefix("U+").or_else(|| line.strip_prefix("u+"))
            .or_else(|| line.strip_prefix("0x")).or_else(|| line.strip_prefix("0X"))
            .unwrap_or(line);
        if hex.is_empty() || hex.len() > 6 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(refusal("bad_codepoints", &format!("line {}: {line:?}", lineno + 1)));
        }
        let cp = u32::from_str_radix(hex, 16)
            .map_err(|_| refusal("bad_codepoints", &format!("line {}: {line:?}", lineno + 1)))?;
        if cp > 0x10FFFF || (0xD800..=0xDFFF).contains(&cp) {
            return Err(refusal("bad_codepoints", &format!("line {}: {line:?} not a scalar", lineno + 1)));
        }
        if out.contains(&cp) {
            return Err(refusal("bad_codepoints", &format!("line {}: duplicate U+{cp:04X}", lineno + 1)));
        }
        out.push(cp);
        if out.len() > MAX_CODEPOINTS {
            return Err(refusal("bad_codepoints", &format!("over {MAX_CODEPOINTS} rows")));
        }
    }
    if out.is_empty() {
        return Err(refusal("bad_codepoints", "no codepoints"));
    }
    Ok(out)
}

// ---------- outline -> canvas edges ----------
struct Canvas {
    ppu: f64, // canvas pixels per font unit
    x0: f64,  // font-space window minimum x
    y1: f64,  // font-space window maximum y (canvas row 0)
}

impl Canvas {
    fn to_px(&self, p: Point) -> Point {
        Point { x: (p.x - self.x0) * self.ppu, y: (self.y1 - p.y) * self.ppu }
    }
}

/// Distance from p to the chord a-b (segment-clamped), as in
/// economy_eval::dist_pt_seg.
fn dist_pt_seg(p: Point, a: Point, b: Point) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let l2 = dx * dx + dy * dy;
    let t = if l2 == 0.0 { 0.0 } else { (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0) };
    let (cx, cy) = (a.x + t * dx, a.y + t * dy);
    ((p.x - cx).powi(2) + (p.y - cy).powi(2)).sqrt()
}

/// Adaptive de Casteljau: emit `end` when the control polygon is within
/// FLATTEN_TOL_PX of the chord, else split at t=0.5. Deterministic.
fn flatten_cubic(
    p0: Point, c1: Point, c2: Point, p3: Point,
    depth: u32, out: &mut Vec<Point>,
) -> Result<(), String> {
    let flat = dist_pt_seg(c1, p0, p3) <= FLATTEN_TOL_PX && dist_pt_seg(c2, p0, p3) <= FLATTEN_TOL_PX;
    if flat || depth >= FLATTEN_MAX_DEPTH {
        out.push(p3);
        if out.len() > MAX_EDGES {
            return Err(refusal("geometry_budget", &format!("over {MAX_EDGES} flattened points")));
        }
        return Ok(());
    }
    let mid = |a: Point, b: Point| Point { x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5 };
    let q1 = mid(p0, c1);
    let q2 = mid(c1, c2);
    let q3 = mid(c2, p3);
    let r1 = mid(q1, q2);
    let r2 = mid(q2, q3);
    let s = mid(r1, r2);
    flatten_cubic(p0, q1, r1, s, depth + 1, out)?;
    flatten_cubic(s, r2, q3, p3, depth + 1, out)
}

/// One canonicalized ring to a closed canvas-space polygon. The closing
/// duplicate point is dropped; the fill closes the polygon with a modulo
/// edge, exactly like economy_eval::ProductionEvaluator::render_mask.
fn flatten_ring(ring: &ReferenceRing, cv: &Canvas) -> Result<Vec<Point>, String> {
    let canonical = canon(ring).map_err(|e| refusal("nonfinite_geometry", &format!("{e:?}")))?;
    let mut pts: Vec<Point> = Vec::new();
    pts.push(cv.to_px(canonical.start));
    let mut cur = canonical.start;
    for span in &canonical.spans {
        match *span {
            Span::Line { end } => {
                pts.push(cv.to_px(end));
                if pts.len() > MAX_EDGES {
                    return Err(refusal("geometry_budget", &format!("over {MAX_EDGES} flattened points")));
                }
            }
            Span::Cubic { control_one, control_two, end } => {
                flatten_cubic(cv.to_px(cur), cv.to_px(control_one), cv.to_px(control_two), cv.to_px(end), 0, &mut pts)?;
            }
        }
        cur = span_end(span);
    }
    if pts.len() > 1 && pts.last() == pts.first() { pts.pop(); }
    Ok(pts)
}

fn span_end(s: &Span) -> Point {
    match *s { Span::Line { end } | Span::Cubic { end, .. } => end }
}

// ---------- fill: nonzero winding on an SS x SS sub-pixel grid ----------
/// 8-bit gray tile, w*h row-major, 255 = full ink. Mirrors the nonzero
/// winding scanline semantics of ProductionEvaluator::render_mask at
/// sub-pixel resolution; coverage accumulates in integers and converts once
/// (round-half-up), so the output is platform-independent.
fn render_gray(edges: &[(Point, Point)], w: usize, h: usize) -> Vec<u8> {
    let mut acc = vec![0u32; w * h];
    let mut cov = vec![0u32; w];
    let mut xs: Vec<(f64, i32)> = Vec::new();
    for r in 0..h * SS {
        let yc = (r as f64 + 0.5) / SS as f64;
        xs.clear();
        for (a, b) in edges {
            if (a.y <= yc) != (b.y <= yc) {
                let x = a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x);
                xs.push((x, if b.y > a.y { 1 } else { -1 }));
            }
        }
        xs.sort_unstable_by(|p, q| p.0.partial_cmp(&q.0).unwrap_or(std::cmp::Ordering::Equal));
        cov.fill(0);
        let mut wind = 0i64;
        for k in 0..xs.len() {
            wind += xs[k].1 as i64;
            if wind != 0 && k + 1 < xs.len() {
                let (x0, x1) = (xs[k].0, xs[k + 1].0);
                if x1 <= x0 { continue; }
                // Sub-columns whose center lies strictly inside (x0, x1).
                let s0 = ((x0 * SS as f64) - 0.5).ceil().max(0.0) as usize;
                let s1 = (((x1 * SS as f64) - 0.5).ceil().max(0.0) as usize).min(w * SS);
                for s in s0..s1 { cov[s / SS] += 1; }
            }
        }
        let row = r / SS;
        for (col, &c) in cov.iter().enumerate() {
            acc[row * w + col] += c;
        }
    }
    let full = (SS * SS) as u32;
    acc.iter().map(|&c| ((c * 255 + full / 2) / full).min(255) as u8).collect()
}

fn pgm_bytes(gray: &[u8], w: usize, h: usize) -> Vec<u8> {
    let mut out = format!("P5\n{w} {h}\n255\n").into_bytes();
    out.extend_from_slice(gray);
    out
}

fn run() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 5 {
        return Err("usage: ocr_render OTF CODEPOINTS_FILE SIZE_PX OUT_DIR".into());
    }
    ascii_arg(&a[1], "otf path")?;
    ascii_arg(&a[2], "codepoints path")?;
    ascii_arg(&a[4], "out dir")?;

    let size_px: u32 = a[3].parse().map_err(|_| refusal("bad_size_px", &a[3]))?;
    if !(MIN_SIZE_PX..=MAX_SIZE_PX).contains(&size_px) {
        return Err(refusal("bad_size_px", &format!("{size_px} outside {MIN_SIZE_PX}..={MAX_SIZE_PX}")));
    }
    let (w, h) = (size_px as usize, size_px as usize);

    let otf = read_capped(&a[1], MAX_OTF_BYTES, "otf")?;
    let font_sha = sha256_hex(&otf);
    let reader = CffReader::from_bytes(&otf, &font_sha)
        .map_err(|e| refusal("font_read", &format!("{e:?}")))?;
    let upm = reader.units_per_em() as f64;

    let cps = parse_codepoints(&read_capped(&a[2], MAX_CODEPOINTS_BYTES, "codepoints")?)?;

    match std::fs::metadata(&a[4]) {
        Ok(m) if !m.is_dir() => return Err(refusal("out_dir", "exists and is not a directory")),
        Ok(_) => {}
        Err(_) => std::fs::create_dir_all(&a[4]).map_err(|e| refusal("out_dir", &format!("create: {e}")))?,
    }

    // Deterministic per-run window: identical (font, size) => identical
    // framing, independent of the requested codepoint set.
    let cv = Canvas {
        ppu: size_px as f64 / ((WINDOW_HI_EM - WINDOW_LO_EM) * upm),
        x0: WINDOW_LO_EM * upm,
        y1: WINDOW_HI_EM * upm,
    };

    println!("engine\t{ENGINE_NAME}\tversion\t{ENGINE_VERSION}\thinting\tnone\taa\t{AA_MODE}\tflatten\tadaptive-tol{FLATTEN_TOL_PX}px-depth{FLATTEN_MAX_DEPTH}\twindow\tem[{WINDOW_LO_EM},{WINDOW_HI_EM}]^2\tsize_px\t{size_px}\tfont_sha256\t{font_sha}\tupm\t{}", reader.units_per_em());
    println!("columns\tcodepoint\tgid\tadvance_width\trings\tspans\tedges\tw\th\tink_px\tpgm_sha256\tfile");

    let mut total_ink = 0u64;
    for &cp in &cps {
        let glyph = reader
            .read_codepoint(cp)
            .map_err(|e| refusal("font_read", &format!("U+{cp:04X}: {e:?}")))?
            .ok_or_else(|| refusal("missing_glyph", &format!("U+{cp:04X}")))?;
        let mut edges: Vec<(Point, Point)> = Vec::new();
        let mut span_count = 0usize;
        for ring in &glyph.rings {
            let pts = flatten_ring(ring, &cv)?;
            span_count += ring.spans.len();
            if pts.len() > 1 {
                for i in 0..pts.len() {
                    let (p, q) = (pts[i], pts[(i + 1) % pts.len()]);
                    if p != q { edges.push((p, q)); }
                }
            }
        }
        if edges.len() > MAX_EDGES {
            return Err(refusal("geometry_budget", &format!("U+{cp:04X}: over {MAX_EDGES} edges")));
        }
        // Render-twice self-check (contract v4 draft determinism pin).
        let gray_a = render_gray(&edges, w, h);
        let gray_b = render_gray(&edges, w, h);
        if gray_a != gray_b {
            return Err(refusal("render_nondeterminism", &format!("U+{cp:04X}")));
        }
        let ink_px = gray_a.iter().filter(|&&g| g > 0).count() as u64;
        let bytes = pgm_bytes(&gray_a, w, h);
        let pgm_sha = sha256_hex(&bytes);
        let file = format!("U+{cp:04X}.pgm");
        let path = format!("{}/{file}", a[4].trim_end_matches('/'));
        std::fs::write(&path, &bytes).map_err(|e| refusal("write", &format!("{path}: {e}")))?;
        total_ink += ink_px;
        println!(
            "glyph\tU+{cp:04X}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{file}",
            glyph.gid,
            glyph.width.map(|v| format!("{v}")).unwrap_or_else(|| "-".into()),
            glyph.rings.len(),
            span_count,
            edges.len(),
            w, h, ink_px, pgm_sha
        );
    }
    println!("summary\tglyphs\t{}\ttotal_ink_px\t{total_ink}", cps.len());
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("refusal\t{e}");
        std::process::exit(1);
    }
}
