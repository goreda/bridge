// LATTICE-1 prototype harness (example-only, no production wiring): style
// lattice detection + contour classification + circle-refusal census +
// line-fallback census and projected reduction, over a style's glyph tiles.
//
// Usage:
//   lattice_probe <glyph_dir> <scale> <out_prefix> [--squared-error E]
//                 [--max-refits N] [--rdp-eps R] [--max-glyphs N] [--skip-fit]
//
// Outputs:
//   <out_prefix>-lattice-status.tsv   typed lattice_status row
//   <out_prefix>-contours.tsv         per-contour features + class + circle gate
//   <out_prefix>-fallback.tsv         per-glyph line-fallback census + projection
//   stdout: summary rows (same content, human scan)

#[path = "../src/lattice.rs"]
mod lattice;

use kni_core::capture::{capture_gray, CapturedRing, DecodeLimits};
use kni_core::capture_dispatch::decode_source;
use kni_core::jpeg_source::Limits;
use kni_core::capture_fit::fit_captured_with_fallback_events;
use kni_core::cubic_fit::FitPolicy;
use kni_core::form::{circle_fit, recognize_circle_ring};
use kni_core::reference_slice::{Point, Span};
use std::collections::hash_map::DefaultHasher;
use std::fmt::Write as _;
use std::hash::{Hash, Hasher};

fn hash_bytes(b: &[u8]) -> u64 {
    let mut h = DefaultHasher::new();
    b.hash(&mut h);
    h.finish()
}

// Mirror of form.rs acceptance gates, in the same order, to report WHICH
// gate refuses a ring. Diagnostic mirror only - production logic unchanged.
fn circle_all_gates(pts: &[Point], corners: &[usize], t_circle: f64, rdp_eps: f64) -> String {
    // Every gate this ring fails, in gate order (first = production refusal).
    let mut fails: Vec<&'static str> = Vec::new();
    if !corners.is_empty() {
        fails.push("gate_corners");
        return fails.join(",");
    }
    let mut dense: Vec<Point> = Vec::new();
    for i in 0..pts.len() {
        let a = pts[i];
        let b = pts[(i + 1) % pts.len()];
        let l = (b.x - a.x).hypot(b.y - a.y);
        dense.push(a);
        if l > rdp_eps {
            let m = (l / rdp_eps).ceil() as usize;
            for j in 1..m {
                let t = j as f64 / m as f64;
                dense.push(Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) });
            }
        }
    }
    if dense.len() < 3 {
        fails.push("gate_degenerate");
        return fails.join(",");
    }
    let (c, r, _) = match circle_fit(pts) {
        Some(v) => v,
        None => {
            fails.push("gate_kasa");
            return fails.join(",");
        }
    };
    let mut resid = 0.0f64;
    for p in &dense {
        resid = resid.max(((p.x - c.x).hypot(p.y - c.y) - r).abs());
    }
    if resid > t_circle {
        fails.push("gate_residual");
    }
    let (mut mnx, mut mny, mut mxx, mut mxy) =
        (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for p in &dense {
        mnx = mnx.min(p.x);
        mxx = mxx.max(p.x);
        mny = mny.min(p.y);
        mxy = mxy.max(p.y);
    }
    if ((mxx - mnx) - 2.0 * r).abs() > t_circle || ((mxy - mny) - 2.0 * r).abs() > t_circle {
        fails.push("gate_bbox");
    }
    let limit = 1.5 * 2.0 * (2.0 * rdp_eps / r).sqrt();
    if limit > std::f64::consts::FRAC_PI_4 {
        fails.push("gate_abstain_small_radius");
    } else {
        let mut ang: Vec<f64> = dense.iter().map(|p| (p.y - c.y).atan2(p.x - c.x)).collect();
        ang.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let mut gap = 0.0f64;
        for i in 0..ang.len() {
            let d = if i + 1 < ang.len() {
                ang[i + 1] - ang[i]
            } else {
                ang[0] + std::f64::consts::TAU - ang[i]
            };
            gap = gap.max(d);
        }
        if gap > limit {
            fails.push("gate_angular_gap");
        }
    }
    if fails.is_empty() {
        "passes_gates".to_string()
    } else {
        fails.join(",")
    }
}

fn circle_refusal(pts: &[Point], corners: &[usize], t_circle: f64, rdp_eps: f64) -> &'static str {
    if !corners.is_empty() {
        return "gate_corners";
    }
    // dense resample at chord spacing <= rdp_eps (same as form::resample_closed)
    let mut dense: Vec<Point> = Vec::new();
    for i in 0..pts.len() {
        let a = pts[i];
        let b = pts[(i + 1) % pts.len()];
        let l = (b.x - a.x).hypot(b.y - a.y);
        dense.push(a);
        if l > rdp_eps {
            let m = (l / rdp_eps).ceil() as usize;
            for j in 1..m {
                let t = j as f64 / m as f64;
                dense.push(Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) });
            }
        }
    }
    if dense.len() < 3 {
        return "gate_degenerate";
    }
    let (c, r, _) = match circle_fit(pts) {
        Some(v) => v,
        None => return "gate_kasa",
    };
    let mut resid = 0.0f64;
    for p in &dense {
        resid = resid.max(((p.x - c.x).hypot(p.y - c.y) - r).abs());
    }
    if resid > t_circle {
        return "gate_residual";
    }
    let (mut mnx, mut mny, mut mxx, mut mxy) =
        (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for p in &dense {
        mnx = mnx.min(p.x);
        mxx = mxx.max(p.x);
        mny = mny.min(p.y);
        mxy = mxy.max(p.y);
    }
    if ((mxx - mnx) - 2.0 * r).abs() > t_circle || ((mxy - mny) - 2.0 * r).abs() > t_circle {
        return "gate_bbox";
    }
    let limit = 1.5 * 2.0 * (2.0 * rdp_eps / r).sqrt();
    if limit > std::f64::consts::FRAC_PI_4 {
        return "gate_abstain_small_radius";
    }
    let mut ang: Vec<f64> = dense.iter().map(|p| (p.y - c.y).atan2(p.x - c.x)).collect();
    ang.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mut gap = 0.0f64;
    for i in 0..ang.len() {
        let d = if i + 1 < ang.len() {
            ang[i + 1] - ang[i]
        } else {
            ang[0] + std::f64::consts::TAU - ang[i]
        };
        gap = gap.max(d);
    }
    if gap > limit {
        return "gate_angular_gap";
    }
    "passes_gates"
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: lattice_probe <glyph_dir> <scale> <out_prefix> [--squared-error E] [--max-refits N] [--rdp-eps R] [--max-glyphs N] [--skip-fit]");
        std::process::exit(2);
    }
    let glyph_dir = &args[1];
    let scale: f64 = args[2].parse().unwrap();
    let out_prefix = &args[3];
    let mut squared_error = 0.25;
    let mut max_refits = 8usize;
    let mut rdp_eps = 0.5f64;
    let mut max_glyphs = usize::MAX;
    let mut skip_fit = false;
    let mut i = 4;
    while i < args.len() {
        match args[i].as_str() {
            "--squared-error" => { squared_error = args[i + 1].parse().unwrap(); i += 2; }
            "--max-refits" => { max_refits = args[i + 1].parse().unwrap(); i += 2; }
            "--rdp-eps" => { rdp_eps = args[i + 1].parse().unwrap(); i += 2; }
            "--max-glyphs" => { max_glyphs = args[i + 1].parse().unwrap(); i += 2; }
            "--skip-fit" => { skip_fit = true; i += 1; }
            other => { eprintln!("unknown arg {other}"); std::process::exit(2); }
        }
    }
    let policy = FitPolicy { squared_error, max_refits };

    let mut entries: Vec<_> = std::fs::read_dir(glyph_dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.extension()
                .map(|x| {
                    let x = x.to_string_lossy().to_lowercase();
                    x == "png" || x == "jpg" || x == "jpeg"
                })
                .unwrap_or(false)
        })
        .collect();
    entries.sort();
    let total_tiles = entries.len();

    let mut seen = std::collections::HashSet::new();
    let mut glyphs: Vec<(String, Vec<CapturedRing>)> = Vec::new();
    let mut dup_skipped = 0usize;
    for path in entries {
        if glyphs.len() >= max_glyphs {
            break;
        }
        let bytes = std::fs::read(&path).unwrap();
        if !seen.insert(hash_bytes(&bytes)) {
            dup_skipped += 1;
            continue;
        }
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        let lim = Limits {
            max_input_bytes: 64 * 1024 * 1024,
            max_pixels: 64 * 1024 * 1024,
            max_working_bytes: 512 * 1024 * 1024,
        };
        let dlim = DecodeLimits {
            max_input_bytes: lim.max_input_bytes,
            max_pixels: lim.max_pixels,
            max_working_bytes: lim.max_working_bytes,
        };
        match decode_source(&bytes, &dlim, lim)
            .map_err(|e| format!("{e:?}"))
            .and_then(|d| capture_gray(d.width, d.height, &d.gray, rdp_eps))
        {
            Ok(mc) => glyphs.push((name, mc.rings)),
            Err(e) => eprintln!("capture failed {name}: {e}"),
        }
    }

    // stage 1+2
    let mut feats: Vec<lattice::RingFeatures> = Vec::new();
    for (g, rings) in &glyphs {
        for (idx, r) in rings.iter().enumerate() {
            feats.push(lattice::ring_features(g, idx, r));
        }
    }
    let status = lattice::detect_lattice(&feats);

    let mut status_tsv = String::from(
        "row_type\tstatus\tfailed_check\tdot_radius\tdot_radius_tol\tspacing\tbasis_angle_deg\tbasis_angle2_deg\tphase_u\tphase_v\tcoverage\tper_glyph_phase_agreement\tdot_count\tglyph_count\tcandidate_count\ttotal_tiles\tdup_tiles_skipped\n",
    );
    match &status {
        lattice::LatticeStatus::Detected(p) => {
            let _ = writeln!(
                status_tsv,
                "lattice_status\tdetected\t-\t{:.4}\t{:.4}\t{:.4}\t{:.3}\t{:.3}\t{:.4}\t{:.4}\t{:.4}\t{:.4}\t{}\t{}\t{}\t{}\t{}",
                p.dot_radius, p.dot_radius_tol, p.spacing,
                p.basis_angle.to_degrees(), p.basis_angle2.to_degrees(),
                p.phase.0, p.phase.1, p.coverage, p.per_glyph_phase_agreement,
                p.dot_count, p.glyph_count, p.candidate_count, total_tiles, dup_skipped
            );
        }
        lattice::LatticeStatus::NoLattice { failed_check } => {
            let _ = writeln!(
                status_tsv,
                "lattice_status\tno_lattice\t{}\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t{}\t-\t{}\t{}",
                failed_check, glyph_count(&glyphs), total_tiles, dup_skipped
            );
        }
    }
    std::fs::write(format!("{out_prefix}-lattice-status.tsv"), &status_tsv).unwrap();

    // classification + circle gates + fallback census
    let mut contours_tsv = String::from(
        "glyph\tring_index\thole\tclass\tradius_equiv\tarea\tperimeter\tcircularity\tbbox_w\tbbox_h\tn_points\tn_corners\tcenter_x\tcenter_y\tcircle_gate\tcircle_all_failed_gates\tcircle_accepted\tfallback_spans\temitted_line_spans\temitted_cubic_spans\n",
    );
    let mut fallback_tsv = String::from(
        "glyph\trings\tfallback_spans_total\tdot_spans\tstroke_spans\tambiguous_spans\n",
    );
    let t_circle = 1.0 * scale;
    let rdp_scaled = 0.5 * scale;
    let mut class_counts = [0usize; 3];
    let mut gate_counts: std::collections::BTreeMap<&str, usize> = Default::default();
    let mut circle_accepted_dots = 0usize;
    let mut total_fb = 0usize;
    let mut dot_fb = 0usize;
    let mut total_em_line = 0usize;
    let mut total_em_cubic = 0usize;
    let mut dot_em_line = 0usize;
    let mut dot_em_cubic = 0usize;

    for (g, rings) in &glyphs {
        let mut g_fb = [0usize; 4]; // total, dot, stroke, ambiguous
        for (idx, r) in rings.iter().enumerate() {
            let f = lattice::ring_features(g, idx, r);
            let class = match &status {
                lattice::LatticeStatus::Detected(p) => lattice::classify_contour(&f, p),
                lattice::LatticeStatus::NoLattice { .. } => lattice::ContourClass::Stroke,
            };
            class_counts[match class {
                lattice::ContourClass::LatticeDot => 0,
                lattice::ContourClass::Stroke => 1,
                lattice::ContourClass::Ambiguous => 2,
            }] += 1;
            let pts: Vec<Point> = r
                .points
                .iter()
                .map(|p| Point { x: p.x * scale, y: p.y * scale })
                .collect();
            let gate = circle_refusal(&pts, &r.corners, t_circle, rdp_scaled);
            let all_gates = circle_all_gates(&pts, &r.corners, t_circle, rdp_scaled);
            let accepted = recognize_circle_ring(&pts, &r.corners, r.hole, t_circle, rdp_scaled).is_some();
            if class == lattice::ContourClass::LatticeDot {
                *gate_counts.entry(gate).or_default() += 1;
                if accepted {
                    circle_accepted_dots += 1;
                }
            }
            let (fb, em_line, em_cubic) = if skip_fit {
                (0, 0, 0)
            } else {
                let (out, _, _, _, ev) = fit_captured_with_fallback_events(&[r.clone()], scale, &policy);
                let mut nl = 0usize;
                let mut nc = 0usize;
                for ring in &out {
                    for sp in &ring.spans {
                        match sp {
                            Span::Line { .. } => nl += 1,
                            Span::Cubic { .. } => nc += 1,
                        }
                    }
                }
                (ev.len(), nl, nc)
            };
            total_em_line += em_line;
            total_em_cubic += em_cubic;
            if class == lattice::ContourClass::LatticeDot {
                dot_em_line += em_line;
                dot_em_cubic += em_cubic;
            }
            total_fb += fb;
            g_fb[0] += fb;
            match class {
                lattice::ContourClass::LatticeDot => { dot_fb += fb; g_fb[1] += fb; }
                lattice::ContourClass::Stroke => { g_fb[2] += fb; }
                lattice::ContourClass::Ambiguous => { g_fb[3] += fb; }
            }
            let _ = writeln!(
                contours_tsv,
                "{}\t{}\t{}\t{}\t{:.4}\t{:.2}\t{:.2}\t{:.4}\t{:.2}\t{:.2}\t{}\t{}\t{:.3}\t{:.3}\t{}\t{}\t{}\t{}\t{}\t{}",
                g, f.ring_index, r.hole, class.as_str(), f.radius_equiv, f.area, f.perimeter, f.circularity,
                f.bbox_w, f.bbox_h, f.n_points, f.n_corners, f.center.x, f.center.y,
                gate, all_gates, accepted, fb, em_line, em_cubic
            );
        }
        let _ = writeln!(fallback_tsv, "{}\t{}\t{}\t{}\t{}\t{}", g, rings.len(), g_fb[0], g_fb[1], g_fb[2], g_fb[3]);
    }
    std::fs::write(format!("{out_prefix}-contours.tsv"), &contours_tsv).unwrap();
    std::fs::write(format!("{out_prefix}-fallback.tsv"), &fallback_tsv).unwrap();

    println!("tiles={} unique_glyphs={} dup_skipped={}", total_tiles, glyphs.len(), dup_skipped);
    match &status {
        lattice::LatticeStatus::Detected(p) => println!(
            "lattice_status=detected dot_radius={:.3} tol={:.3} spacing={:.3} basis=({:.2},{:.2})deg phase=({:.3},{:.3}) coverage={:.4} per_glyph_agree={:.4} dots={}",
            p.dot_radius, p.dot_radius_tol, p.spacing, p.basis_angle.to_degrees(),
            p.basis_angle2.to_degrees(), p.phase.0, p.phase.1, p.coverage,
            p.per_glyph_phase_agreement, p.dot_count),
        lattice::LatticeStatus::NoLattice { failed_check } =>
            println!("lattice_status=no_lattice failed_check={failed_check}"),
    }
    println!("class lattice_dot={} stroke={} ambiguous={}", class_counts[0], class_counts[1], class_counts[2]);
    println!("circle_accepted_dots={}", circle_accepted_dots);
    for (g, n) in &gate_counts {
        println!("dot_circle_gate {} {}", g, n);
    }
    if !skip_fit {
        println!("fallback_spans total={} lattice_dot={} stroke_or_amb={} projected_reduction={} ({:.1}%)",
            total_fb, dot_fb, total_fb - dot_fb, dot_fb,
            if total_fb > 0 { 100.0 * dot_fb as f64 / total_fb as f64 } else { 0.0 });
        println!("emitted_spans line={} cubic={} | dot line={} cubic={} | dot_nodes_if_circle={}",
            total_em_line, total_em_cubic, dot_em_line, dot_em_cubic, 4 * class_counts[0]);
    }
}

fn glyph_count(glyphs: &[(String, Vec<CapturedRing>)]) -> usize {
    glyphs.len()
}
