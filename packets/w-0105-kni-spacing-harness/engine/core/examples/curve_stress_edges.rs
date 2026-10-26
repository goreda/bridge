//! curve_stress_edges: for one glyph, find KNI's Line+corner chains (>=2
//! consecutive Line spans), check whether potrace/vtracer cover the same
//! edge with a single cubic, and measure the SOURCE contour along the edge
//! (sagitta, chord crossings, distance to each engine's geometry) so the
//! "is the source actually wavy there" call is data, not opinion.
//!
//! All geometry is compared in tile pixel space, y-down.
//! Cover-match endpoint tolerance is derived per glyph: fit dev_max in px
//! plus 1.0 px (0.5 px capture iso band + 0.5 px coordinate rounding).
//!
//! Usage: curve_stress_edges --style <id> --tile <png|jpg>
//!   --potrace-svg <svg> --vtracer-svg <svg> --units-per-px <f64> --out <tsv>

use kni_core::curve_stress::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn span_end(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn is_line(s: &Span) -> bool { matches!(s, Span::Line { .. }) }
fn d2(a: (f64, f64), b: (f64, f64)) -> f64 { ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt() }
fn dist_pt_seg(p: (f64, f64), a: (f64, f64), b: (f64, f64)) -> f64 {
    let ab = (b.0 - a.0, b.1 - a.1);
    let len2 = ab.0 * ab.0 + ab.1 * ab.1;
    if len2 == 0.0 { return d2(p, a); }
    let t = (((p.0 - a.0) * ab.0 + (p.1 - a.1) * ab.1) / len2).clamp(0.0, 1.0);
    d2(p, (a.0 + ab.0 * t, a.1 + ab.1 * t))
}
fn dist_to_poly(p: (f64, f64), poly: &[(f64, f64)]) -> f64 {
    if poly.len() < 2 { return f64::INFINITY; }
    (0..poly.len() - 1).map(|i| dist_pt_seg(p, poly[i], poly[i + 1])).fold(f64::INFINITY, f64::min)
}

/// One engine span flattened into tile px (y-down).
struct SpanPx {
    is_cubic: bool,
    flat: Vec<(f64, f64)>,
}

fn svg_spans_px(xml: &str, tile_w: usize, tile_h: usize) -> Vec<SpanPx> {
    let svg = parse_svg_outline(xml).expect("parse svg");
    let (sx, sy, ox, oy) = match svg.view_box {
        Some(vb) => (tile_w as f64 / vb[2], tile_h as f64 / vb[3], vb[0], vb[1]),
        None => (1.0, 1.0, 0.0, 0.0),
    };
    let to_px = |p: Point| -> (f64, f64) {
        let u = affine_apply(&svg.group_transform, p);
        ((u.x - ox) * sx, (u.y - oy) * sy)
    };
    let tol_user = 0.25 / sx.max(1e-9); // quarter output pixel
    let mut out = Vec::new();
    for ring in &svg.rings {
        for (si, s) in ring.spans.iter().enumerate() {
            let start_p = if si == 0 { ring.start } else { span_end(&ring.spans[si - 1]) };
            let one = ReferenceRing { start: start_p, spans: vec![s.clone()] };
            let flat_local = flatten_ring(&one, tol_user);
            out.push(SpanPx {
                is_cubic: !is_line(s),
                flat: flat_local.iter().map(|&p| to_px(p)).collect(),
            });
        }
    }
    out
}

struct CoverStats {
    spans_on_edge: usize,
    covered_frac: f64,
    best_region_max: f64,
    best_span_to_src: f64,
    best_is_cubic: bool,
    best_single_hugging: bool, // one span alone: region within tol AND span hugs source within tol
}

/// Edge coverage by one engine, placement-independent: which spans pass
/// within tol of the region's source points, what fraction of the region
/// they jointly cover, and whether a single span both covers the region
/// and hugs the source contour along its own whole length.
fn cover(spans: &[SpanPx], region: &[(f64, f64)], src_all: &[(f64, f64)], tol: f64) -> Option<CoverStats> {
    if region.is_empty() || spans.is_empty() { return None; }
    let dil = tol + 1.0;
    let (mut x0, mut y0, mut x1, mut y1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for &p in region { x0 = x0.min(p.0); y0 = y0.min(p.1); x1 = x1.max(p.0); y1 = y1.max(p.1); }
    let mut covered = vec![false; region.len()];
    let mut spans_on_edge = 0usize;
    let mut best: Option<(f64, f64, bool)> = None; // (region_max, span_to_src_max, is_cubic)
    for sp in spans {
        let (mut sx0, mut sy0, mut sx1, mut sy1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
        for &p in &sp.flat { sx0 = sx0.min(p.0); sy0 = sy0.min(p.1); sx1 = sx1.max(p.0); sy1 = sy1.max(p.1); }
        if sx1 < x0 - dil || sx0 > x1 + dil || sy1 < y0 - dil || sy0 > y1 + dil { continue; }
        let mut touches = false;
        let mut region_max = 0.0f64;
        for (k, &p) in region.iter().enumerate() {
            let d = dist_to_poly(p, &sp.flat);
            if d > region_max { region_max = d; }
            if d <= tol { covered[k] = true; touches = true; }
        }
        if touches { spans_on_edge += 1; }
        let span_to_src = sp.flat.iter().step_by(4).map(|&p| {
            src_all.iter().map(|&q| d2(p, q)).fold(f64::INFINITY, f64::min)
        }).fold(0.0f64, f64::max);
        if best.as_ref().map(|(br, _, _)| region_max < *br).unwrap_or(true) {
            best = Some((region_max, span_to_src, sp.is_cubic));
        }
    }
    let (br, bs, bc) = best?;
    let covered_frac = covered.iter().filter(|&&c| c).count() as f64 / region.len() as f64;
    Some(CoverStats {
        spans_on_edge, covered_frac,
        best_region_max: br, best_span_to_src: bs, best_is_cubic: bc,
        best_single_hugging: spans_on_edge >= 1 && br <= tol && bs <= tol,
    })
}

fn main() {
    let mut style = String::new();
    let mut tile: Option<std::path::PathBuf> = None;
    let mut potrace_svg: Option<std::path::PathBuf> = None;
    let mut vtracer_svg: Option<std::path::PathBuf> = None;
    let mut scale: Option<f64> = None;
    let mut out: Option<std::path::PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--style" => style = args.next().unwrap(),
            "--tile" => tile = args.next().map(Into::into),
            "--potrace-svg" => potrace_svg = args.next().map(Into::into),
            "--vtracer-svg" => vtracer_svg = args.next().map(Into::into),
            "--units-per-px" => scale = args.next().and_then(|v| v.parse().ok()),
            "--out" => out = args.next().map(Into::into),
            other => { eprintln!("unknown arg {other}"); std::process::exit(2); }
        }
    }
    let (tile, scale, out) = match (tile, scale, out) {
        (Some(t), Some(s), Some(o)) if s.is_finite() && s > 0.0 => (t, s, o),
        _ => { eprintln!("need --tile --units-per-px --out"); std::process::exit(2); }
    };
    let glyph = tile.file_stem().unwrap().to_string_lossy().to_string();
    let bytes = std::fs::read(&tile).expect("read tile");
    let src = kni_core::capture_dispatch::capture_source(&bytes, 0.25, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS).expect("capture");
    let policy = kni_core::cubic_fit::FitPolicy { squared_error: 0.25, max_refits: 8 };
    let drawing = kni_core::generated_draw_frame::fit_from_source_frame(&src.contour, &src.gray, scale, &policy).expect("fit");
    let stress = measure_glyph(&drawing.rings, &src.contour, scale).expect("measure");
    let dev_px = stress.deviation.map(|d| d.max / scale).unwrap_or(0.0);
    let tol_px = dev_px + 1.0; // fit dev_max + 0.5 px iso band + 0.5 px rounding

    let h = src.contour.height;
    let (ox, oy) = (src.contour.origin_x, src.contour.origin_y);
    let kni_px = |p: Point| -> (f64, f64) {
        let (x, y_up) = fitted_to_image(p, &src.contour, scale);
        (x, (h as f64 - 1.0) - y_up)
    };
    let mut src_pts: Vec<(f64, f64)> = Vec::new();
    for ring in &src.contour.rings {
        for p in &ring.points {
            src_pts.push((p.x + ox, -(p.y + oy)));
        }
    }

    let pot = potrace_svg.map(|p| svg_spans_px(&std::fs::read_to_string(p).expect("potrace svg"), src.contour.width, h));
    let vtr = vtracer_svg.map(|p| svg_spans_px(&std::fs::read_to_string(p).expect("vtracer svg"), src.contour.width, h));

    let mut jk = std::collections::HashMap::new();
    for j in &stress.joints { jk.insert((j.ring, j.node), j.kind); }

    let mut tsv = String::from(
        "style\tglyph\tring\tfirst_span\tspans\tlen_px\tcorners_inside\tpotrace_spans_on_edge\tpotrace_covered_frac\tpotrace_best_region_max\tpotrace_best_span_to_src\tpotrace_single\tvtracer_spans_on_edge\tvtracer_covered_frac\tvtracer_best_region_max\tvtracer_best_span_to_src\tvtracer_single\tsagitta_px\tchord_crossings\tcrossings_3px\tcrossings_6px\tnet_bulge_px\tsrc_to_kni_max_px\tverdict\n");
    let mut n_chains = 0usize;
    for (ri, ring) in drawing.rings.iter().enumerate() {
        let n = ring.spans.len();
        let mut i = 0usize;
        while i < n {
            if !is_line(&ring.spans[i]) { i += 1; continue; }
            let mut j = i;
            while j + 1 < n && is_line(&ring.spans[j + 1]) { j += 1; }
            let count = j - i + 1;
            if count >= 2 {
                n_chains += 1;
                let start_fu = if i == 0 { ring.start } else { span_end(&ring.spans[i - 1]) };
                let mut poly: Vec<(f64, f64)> = vec![kni_px(start_fu)];
                for s in &ring.spans[i..=j] { poly.push(kni_px(span_end(s))); }
                let corners_inside = (i..j).filter(|&k| jk.get(&(ri, k)) == Some(&JointKind::Corner)).count();
                let s0 = poly[0];
                let e0 = *poly.last().unwrap();
                let mut len_px = 0.0;
                for k in 0..poly.len() - 1 { len_px += d2(poly[k], poly[k + 1]); }
                let dil = tol_px + 3.0;
                let (mut x0, mut y0, mut x1, mut y1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
                for &p in &poly { x0 = x0.min(p.0); y0 = y0.min(p.1); x1 = x1.max(p.0); y1 = y1.max(p.1); }
                // Region = the source contour UNDER the chain (distance to
                // the chain polyline within tol), not a bbox: a bbox pulls
                // in neighbouring strokes (hatching, opposite stem side).
                let _ = (x0, y0, x1, y1, dil);
                let region: Vec<(f64, f64)> = src_pts.iter().copied()
                    .filter(|&p| dist_to_poly(p, &poly) <= tol_px)
                    .collect();
                let chord = (e0.0 - s0.0, e0.1 - s0.1);
                let clen = (chord.0 * chord.0 + chord.1 * chord.1).sqrt().max(1e-9);
                let signed = |p: (f64, f64)| (chord.0 * (p.1 - s0.1) - chord.1 * (p.0 - s0.0)) / clen;
                let sagitta = region.iter().map(|&p| signed(p).abs()).fold(0.0f64, f64::max);
                // Capture iso band half-width: capture_source localizes the
                // edge contour to 0.5 px on each side; sign flips inside
                // that band are capture noise, not contour motion.
                const ISO_PX: f64 = 0.5;
                let mut crossings = 0usize;
                let mut last_sign = 0i32;
                let mut signed_sum = 0.0f64;
                let mut support_n = 0usize;
                for &p in &region {
                    let sd = signed(p);
                    if sd.abs() > ISO_PX { signed_sum += sd; support_n += 1; }
                    let s = if sd > ISO_PX { 1 } else if sd < -ISO_PX { -1 } else { 0 };
                    if s != 0 {
                        if last_sign != 0 && s != last_sign { crossings += 1; }
                        last_sign = s;
                    }
                }
                let d_src_kni = region.iter().map(|&p| dist_to_poly(p, &poly)).fold(0.0f64, f64::max);
                // Sensitivity: same crossing count on tighter bands, to show
                // the oscillation count comes from the edge under the chain
                // and not from neighbouring strokes inside a fat tol region
                // (Marq Standard fit dev_max makes tol_px 8-17 px).
                let crossings_within = |band: f64| -> usize {
                    let mut c = 0usize; let mut last = 0i32;
                    for &p in &region {
                        if dist_to_poly(p, &poly) > band { continue; }
                        let sd = signed(p);
                        let sg = if sd > ISO_PX { 1 } else if sd < -ISO_PX { -1 } else { 0 };
                        if sg != 0 { if last != 0 && sg != last { c += 1; } last = sg; }
                    }
                    c
                };
                let crossings_3px = crossings_within(3.0);
                let crossings_6px = crossings_within(6.0);
                let pc = cover(pot.as_deref().unwrap_or(&[]), &region, &src_pts, tol_px);
                let vc = cover(vtr.as_deref().unwrap_or(&[]), &region, &src_pts, tol_px);
                let fmt = |c: &Option<CoverStats>| match c {
                    Some(c) => (format!("{}", c.spans_on_edge), format!("{}", c.covered_frac),
                                format!("{}", c.best_region_max), format!("{}", c.best_span_to_src),
                                if c.best_single_hugging && c.best_is_cubic { "single-cubic".to_string() }
                                else if c.best_single_hugging { "single-line".to_string() }
                                else { "multi".to_string() }),
                    None => ("n/a".into(), "n/a".into(), "n/a".into(), "n/a".into(), "n/a".into()),
                };
                let (pn, pf, pr, ps, pv) = fmt(&pc);
                let (vn, vf, vr, vs, vv) = fmt(&vc);
                // Chain-level verdict via the derived rule in
                // curve_stress::classify_chain (capture-resolution straight
                // band, one-inflection crossing bound; no tuned constants).
                // net_bulge below is evidence, not a rule input: |mean
                // signed distance| over the support - ~0 for oscillation
                // (B's "sag~0" on Marq comb teeth), >= half the peak for a
                // one-sided unimodal arc.
                // net bulge over the bump's own SUPPORT (|signed| > iso), so
                // flat stretches of the region cannot dilute it: for a
                // one-sided unimodal bump support-mean >= (peak+iso)/2, i.e.
                // still inside the triangle-wave bound classify_chain uses.
                let net_bulge = if support_n == 0 { 0.0 } else { (signed_sum / support_n as f64).abs() };
                let verdict = classify_chain(sagitta, crossings, ISO_PX).tag();
                tsv.push_str(&format!(
                    "{style}\t{glyph}\t{ri}\t{i}\t{count}\t{len_px}\t{corners_inside}\t{pn}\t{pf}\t{pr}\t{ps}\t{pv}\t{vn}\t{vf}\t{vr}\t{vs}\t{vv}\t{sagitta}\t{crossings}\t{crossings_3px}\t{crossings_6px}\t{net_bulge}\t{d_src_kni}\t{verdict}\n"));
            }
            i = j + 1;
        }
    }
    std::fs::write(&out, &tsv).expect("write tsv");
    eprintln!("{style} {glyph}: {n_chains} chains (tol_px={tol_px}) -> {}", out.display());
}
