//! curve_stress_probe: one-glyph deep probe. Prints the full joint ledger
//! (kind, severity, floor, font-unit and image coordinates, adjacent span
//! tags) and writes a three-panel gray PNG: source | fitted fill | pixel
//! diff (diff legend: paper 255, both-ink 150, source-only 0 (black),
//! fit-only 90 (dark gray)).
//!
//! Usage: curve_stress_probe --tile <png|jpg> --units-per-px <f64> --out <prefix>
//! Fit parameters are the production manifest values, same as the corpus
//! runner: rdp 0.25 px, fixed squared error 0.25, max 8 refits.

use kni_core::curve_stress::*;
use kni_core::reference_slice::Span;
use std::path::PathBuf;

fn span_tag(s: &Span) -> &'static str {
    match s { Span::Line { .. } => "line", Span::Cubic { .. } => "cubic" }
}
fn span_end(s: &Span) -> kni_core::reference_slice::Point {
    match s { Span::Line { end } | Span::Cubic { end, .. } => *end }
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
    let (fill, _overlay) = render_proofs(&drawing.rings, &src.contour, &src.gray, scale).expect("render");

    let w = src.contour.width;
    let h = src.contour.height;
    let dev = stress.deviation.expect("measure_glyph deviation");

    // masks: source ink = gray < 128, fitted ink = fill < 128
    let mut inter = 0usize; let mut union = 0usize; let mut ref_only = 0usize; let mut fit_only = 0usize;
    let mut triple = vec![0u8; w * 3 * h];
    for row in 0..h {
        for x in 0..w {
            let r = src.gray[row * w + x] < 128;
            let f = fill[row * w + x] < 128;
            if r && f { inter += 1; }
            if r || f { union += 1; }
            if r && !f { ref_only += 1; }
            if f && !r { fit_only += 1; }
            triple[row * 3 * w + x] = src.gray[row * w + x];
            triple[row * 3 * w + w + x] = fill[row * w + x];
            triple[row * 3 * w + 2 * w + x] = match (r, f) {
                (true, true) => 150, (true, false) => 0, (false, true) => 90, (false, false) => 255,
            };
        }
    }
    let png = encode_png_gray(w * 3, h, &triple).expect("encode");
    let path = out.with_extension("triple.png");
    std::fs::write(&path, &png).expect("write triple");

    println!("glyph\t{glyph}");
    println!("scale\t{scale}");
    println!("nodes\t{}\tcubics\t{}\tlines\t{}\trings\t{}", stress.nodes, stress.cubics, stress.lines, stress.rings);
    println!("corners\t{}\tcurvature_breaks\t{}\tunavailable\t{}", stress.corners, stress.curvature_breaks, stress.unavailable_joints);
    println!("dev_max_fu\t{}\tdev_mean_fu\t{}\tdev_samples\t{}", dev.max, dev.mean, dev.samples);
    println!("iou\t{}\tref_only_px\t{}\tfit_only_px\t{}", inter as f64 / union.max(1) as f64, ref_only, fit_only);
    println!("triple\t{}", path.display());
    println!("ring\tnode\tkind\tseverity\tfloor\tfu_x\tfu_y\timg_x\timg_row\tprev_span\tnext_span");
    for j in &stress.joints {
        let ring = &drawing.rings[j.ring];
        let n = ring.spans.len();
        let p = span_end(&ring.spans[j.node]);
        let (ix, iy_up) = fitted_to_image(p, &src.contour, scale);
        let img_row = (h as f64 - 1.0 - iy_up).round() as i64;
        let prev_tag = span_tag(&ring.spans[j.node]);
        let next_tag = span_tag(&ring.spans[(j.node + 1) % n]);
        println!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            j.ring, j.node, j.kind.tag(), j.severity, j.floor, p.x, p.y,
            ix.round() as i64, img_row, prev_tag, next_tag);
    }
}
