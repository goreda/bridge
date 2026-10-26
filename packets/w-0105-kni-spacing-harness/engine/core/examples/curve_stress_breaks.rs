//! curve_stress_breaks: curvature-break ledger for one glyph tile. For
//! every joint whose kind is CurvatureBreak (and, with --all, every joint)
//! prints the glyph, ring, node, severity vs derived floor, and the FULL
//! control points of the two adjacent spans in font units, so a bad curve
//! can be quoted exactly (glyph/cp list). Fit parameters are the caller's
//! production manifest values, passed explicitly like curve_stress_probe.
//!
//! Usage: curve_stress_breaks --tile <png|jpg> --units-per-px <f64>
//!          [--rdp-eps-px F] [--fit-squared-error F] [--max-refits N] [--all]

use kni_core::curve_stress::*;
use kni_core::reference_slice::{Point, Span};
use std::path::PathBuf;

fn fmt_pt(p: Point) -> String { format!("({},{})", p.x, p.y) }

fn fmt_span(start: Point, s: &Span) -> String {
    match s {
        Span::Line { end } => format!("line {} -> {}", fmt_pt(start), fmt_pt(*end)),
        Span::Cubic { control_one, control_two, end } => format!(
            "cubic {} c1={} c2={} -> {}",
            fmt_pt(start), fmt_pt(*control_one), fmt_pt(*control_two), fmt_pt(*end)
        ),
    }
}

fn main() {
    let mut tile: Option<PathBuf> = None;
    let mut scale: Option<f64> = None;
    let mut rdp = 0.25f64;
    let mut se = 0.25f64;
    let mut refits = 8usize;
    let mut all = false;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--tile" => tile = args.next().map(PathBuf::from),
            "--units-per-px" => scale = args.next().and_then(|v| v.parse().ok()),
            "--rdp-eps-px" => rdp = args.next().and_then(|v| v.parse().ok()).unwrap_or(rdp),
            "--fit-squared-error" => se = args.next().and_then(|v| v.parse().ok()).unwrap_or(se),
            "--max-refits" => refits = args.next().and_then(|v| v.parse().ok()).unwrap_or(refits),
            "--all" => all = true,
            other => { eprintln!("unknown arg {other}"); std::process::exit(2); }
        }
    }
    let (tile, scale) = match (tile, scale) {
        (Some(t), Some(s)) if s.is_finite() && s > 0.0 => (t, s),
        _ => { eprintln!("need --tile --units-per-px"); std::process::exit(2); }
    };
    let bytes = std::fs::read(&tile).expect("read tile");
    let glyph = tile.file_stem().unwrap().to_string_lossy().to_string();

    let src = kni_core::capture_dispatch::capture_source(&bytes, rdp, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS)
        .expect("capture");
    let policy = kni_core::cubic_fit::FitPolicy { squared_error: se, max_refits: refits };
    let drawing = kni_core::generated_draw_frame::fit_from_source_frame(&src.contour, &src.gray, scale, &policy)
        .expect("fit");
    let stress = measure_glyph(&drawing.rings, &src.contour, scale).expect("measure");

    println!("glyph\t{glyph}\tscale\t{scale}\trdp_eps_px\t{rdp}\tfit_squared_error\t{se}\tmax_refits\t{refits}");
    println!("nodes\t{}\tcubics\t{}\tlines\t{}\trings\t{}\tcorners\t{}\tcurvature_breaks\t{}\tunavailable\t{}\tmax_break_severity\t{}",
        stress.nodes, stress.cubics, stress.lines, stress.rings, stress.corners,
        stress.curvature_breaks, stress.unavailable_joints, stress.max_break_severity);
    let dev = stress.deviation.as_ref().expect("measure_glyph deviation");
    println!("dev_max_fu\t{}\tdev_mean_fu\t{}\tdev_samples\t{}\tdev_max_kept_fu\t{}\tdev_mean_kept_fu\t{}\tdev_samples_kept\t{}\tdropped_specks\t{}\tdropped_area_px2\t{}",
        dev.max, dev.mean, dev.samples, dev.max_kept, dev.mean_kept, dev.samples_kept, dev.dropped_rings, dev.dropped_area_px2);
    println!("ring\tnode\tkind\tseverity\tfloor\tjoint_fu\tprev_span\tnext_span");
    for j in &stress.joints {
        if !all && j.kind != JointKind::CurvatureBreak { continue; }
        let ring = &drawing.rings[j.ring];
        let n = ring.spans.len();
        let prev = &ring.spans[j.node];
        let next = &ring.spans[(j.node + 1) % n];
        let prev_start = if j.node == 0 { ring.start } else { match &ring.spans[j.node - 1] {
            Span::Line { end } | Span::Cubic { end, .. } => *end,
        }};
        let joint = match prev { Span::Line { end } | Span::Cubic { end, .. } => *end };
        println!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            j.ring, j.node, j.kind.tag(), j.severity, j.floor, fmt_pt(joint),
            fmt_span(prev_start, prev), fmt_span(joint, next));
    }
}
