//! curve_stress_devmax: localize the symmetric-deviation ARGMAX of one
//! glyph's production fit. measure_glyph reports dev.max but not where it
//! happens; this probe answers "which stage hurts" by printing the worst
//! samples (direction, ring, image position, distance) and writing a crop
//! PNG around the worst one (source gray, flattened fitted outline burned
//! black, worst sample marked).
//!
//! Usage: curve_stress_devmax --tile <png|jpg> --units-per-px <f64> --out <prefix>

use kni_core::curve_stress::*;
use kni_core::reference_slice::{Point, Span};
use std::path::PathBuf;

fn span_end(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn sub(a: Point, b: Point) -> Point { Point { x: a.x - b.x, y: a.y - b.y } }
fn dist(a: Point, b: Point) -> f64 { let d = sub(a, b); (d.x * d.x + d.y * d.y).sqrt() }
fn dist_pt_seg(p: Point, a: Point, b: Point) -> f64 {
    let ab = sub(b, a);
    let len2 = ab.x * ab.x + ab.y * ab.y;
    if len2 == 0.0 { return dist(p, a); }
    let ap = sub(p, a);
    let t = ((ap.x * ab.x + ap.y * ab.y) / len2).clamp(0.0, 1.0);
    dist(p, Point { x: a.x + ab.x * t, y: a.y + ab.y * t })
}

struct Seg { ring: usize, a: Point, b: Point }
fn segments(polys: &[Vec<Point>]) -> Vec<Seg> {
    let mut out = Vec::new();
    for (ri, p) in polys.iter().enumerate() {
        if p.len() >= 2 {
            for i in 0..p.len() {
                out.push(Seg { ring: ri, a: p[i], b: p[(i + 1) % p.len()] });
            }
        }
    }
    out
}
fn nearest(p: Point, segs: &[Seg]) -> (f64, usize, usize) {
    let mut best = (f64::INFINITY, usize::MAX, usize::MAX);
    for (si, s) in segs.iter().enumerate() {
        let d = dist_pt_seg(p, s.a, s.b);
        if d < best.0 { best = (d, si, s.ring); }
    }
    best
}

fn main() {
    let mut tile: Option<PathBuf> = None;
    let mut scale: Option<f64> = None;
    let mut out: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--tile" => tile = args.next().map(PathBuf::from),
            "--units-per-px" => scale = args.next().and_then(|v| v.parse().ok()),
            "--out" => out = args.next().map(PathBuf::from),
            other => { eprintln!("unknown arg {other}"); std::process::exit(2); }
        }
    }
    let (tile, scale, out) = match (tile, scale, out) {
        (Some(t), Some(s), Some(o)) if s.is_finite() && s > 0.0 => (t, s, o),
        _ => { eprintln!("need --tile --units-per-px --out"); std::process::exit(2); }
    };
    let bytes = std::fs::read(&tile).expect("read tile");
    let glyph = tile.file_stem().unwrap().to_string_lossy().to_string();
    let src = kni_core::capture_dispatch::capture_source(&bytes, 0.25, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS)
        .expect("capture");
    let policy = kni_core::cubic_fit::FitPolicy { squared_error: 0.25, max_refits: 8 };
    let drawing = kni_core::generated_draw_frame::fit_from_source_frame(&src.contour, &src.gray, scale, &policy)
        .expect("fit");
    let stress = measure_glyph(&drawing.rings, &src.contour, scale).expect("measure");
    let dev = stress.deviation.expect("deviation");
    if std::env::var("DEVMAX_FAST").is_ok() {
        println!("dev_max_fu\t{}\tdev_mean_fu\t{}\tsamples\t{}", dev.max, dev.mean, dev.samples);
        println!("dev_max_kept_fu\t{}\tdev_mean_kept_fu\t{}\tsamples_kept\t{}", dev.max_kept, dev.mean_kept, dev.samples_kept);
        println!("dropped_rings\t{}\tdropped_area_px2\t{}", dev.dropped_rings, dev.dropped_area_px2);
        return;
    }
    let h = src.contour.height;
    let w = src.contour.width;

    // Same space as measure_glyph: font units, source = p*scale + (0, origin_y*scale)
    let flatten_tol = scale / 2.0;
    let fitted: Vec<Vec<Point>> = drawing.rings.iter().map(|r| flatten_ring(r, flatten_tol)).collect();
    let dy = src.contour.origin_y * scale;
    // same drawable-resolution exemption as measure_glyph
    let source: Vec<Vec<Point>> = src.contour.rings.iter()
        .filter(|r| !kni_core::capture::is_degenerate_ring(&r.points))
        .map(|r| {
            r.points.iter().map(|p| Point { x: p.x * scale, y: p.y * scale + dy }).collect()
        }).collect();
    let fs = segments(&fitted);
    let ss = segments(&source);

    // argmax samples both directions
    struct Hit { dir: &'static str, ring: usize, idx: usize, p: Point, d: f64, near_ring: usize }
    let mut hits: Vec<Hit> = Vec::new();
    for (ri, poly) in source.iter().enumerate() {
        for (pi, &p) in poly.iter().enumerate() {
            let (d, _, nr) = nearest(p, &fs);
            hits.push(Hit { dir: "src->fit", ring: ri, idx: pi, p, d, near_ring: nr });
        }
    }
    for (ri, poly) in fitted.iter().enumerate() {
        for (pi, &p) in poly.iter().enumerate() {
            let (d, _, nr) = nearest(p, &ss);
            hits.push(Hit { dir: "fit->src", ring: ri, idx: pi, p, d, near_ring: nr });
        }
    }
    hits.sort_by(|a, b| b.d.partial_cmp(&a.d).unwrap());

    println!("glyph\t{glyph}\tscale\t{scale}");
    println!("dev_max_fu\t{}\tdev_mean_fu\t{}\tsamples\t{}", dev.max, dev.mean, dev.samples);
    println!("dev_max_kept_fu\t{}\tdev_mean_kept_fu\t{}\tsamples_kept\t{}", dev.max_kept, dev.mean_kept, dev.samples_kept);
    println!("dropped_rings\t{}\tdropped_area_px2\t{}", dev.dropped_rings, dev.dropped_area_px2);
    println!("src_rings\t{}\tfit_rings\t{}\tdrawing_dropped\t{}", src.contour.rings.len(), drawing.rings.len(), drawing.dropped);
    // capture-space area of every source ring, so the area<0.5 drop rule's
    // victims are directly identifiable
    let mut n_tiny = 0usize;
    for (ri, r) in src.contour.rings.iter().enumerate() {
        let pts = &r.points;
        let mut a2 = 0.0f64;
        for i in 0..pts.len() {
            let u = pts[i]; let v = pts[(i + 1) % pts.len()];
            a2 += u.x * v.y - v.x * u.y;
        }
        let area = a2.abs() / 2.0;
        if area < 0.5 { n_tiny += 1; }
        if ri < 3 || area < 0.5 {
            println!("src_ring_area\t{ri}\tpoints\t{}\tarea_px2\t{area:.3}", pts.len());
        }
    }
    println!("tiny_rings_area_lt_0.5\t{n_tiny}");
    for (ri, r) in src.contour.rings.iter().enumerate() {
        println!("src_ring\t{ri}\tpoints\t{}", r.points.len());
    }
    for (ri, r) in drawing.rings.iter().enumerate() {
        println!("fit_ring\t{ri}\tspans\t{}", r.spans.len());
    }
    println!("-- worst 12 samples --");
    println!("dir\tring\tidx\td_fu\td_px\timg_x\timg_y\tnear_ring");
    let to_img = |p: Point| ((p.x / scale + src.contour.origin_x), (h as f64 - 1.0) - (p.y / scale - src.contour.origin_y));
    // careful: source points already include origin_y*scale translation; fitted_to_image handles fitted only.
    for hit in hits.iter().take(12) {
        let (ix, iy) = to_img(hit.p);
        println!("{}\t{}\t{}\t{:.3}\t{:.3}\t{:.1}\t{:.1}\t{}",
            hit.dir, hit.ring, hit.idx, hit.d, hit.d / scale, ix, iy, hit.near_ring);
    }

    // crop around the worst sample: 161x161 window, gray source, fitted
    // flattened outline burned to black, worst point marked with a cross.
    let worst = &hits[0];
    let (cx, cy) = to_img(worst.p);
    let rad = 80i64;
    let cw = (2 * rad + 1) as usize;
    let mut crop = vec![255u8; cw * cw];
    for wy in 0..cw {
        for wx in 0..cw {
            let ix = cx.round() as i64 + wx as i64 - rad;
            let iy = cy.round() as i64 + wy as i64 - rad;
            if ix >= 0 && ix < w as i64 && iy >= 0 && iy < h as i64 {
                crop[wy * cw + wx] = src.gray[iy as usize * w + ix as usize];
            }
        }
    }
    let burn = |crop: &mut Vec<u8>, p: Point, v: u8| {
        let (ix, iy) = to_img(p);
        let bx = (ix - cx).round() as i64 + rad;
        let by = (iy - cy).round() as i64 + rad;
        if bx >= 0 && bx < cw as i64 && by >= 0 && by < cw as i64 {
            crop[by as usize * cw + bx as usize] = v;
        }
    };
    for poly in &fitted { for &p in poly { burn(&mut crop, p, 0); } }
    // mark the worst sample with a small cross of value 160
    for d in -3i64..=3 {
        let (ix, iy) = to_img(worst.p);
        for (bx, by) in [(ix + d as f64, iy), (ix, iy + d as f64)] {
            let px = (bx - cx).round() as i64 + rad;
            let py = (by - cy).round() as i64 + rad;
            if px >= 0 && px < cw as i64 && py >= 0 && py < cw as i64 {
                crop[py as usize * cw + px as usize] = 160;
            }
        }
    }
    let png = encode_png_gray(cw, cw, &crop).expect("encode");
    let path = out.with_extension("devmax.crop.png");
    std::fs::write(&path, &png).expect("write crop");
    println!("crop\t{}", path.display());
    let _ = span_end;
}
