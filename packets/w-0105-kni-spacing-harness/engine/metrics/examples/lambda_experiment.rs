//! Lambda > 0 kerning experiment harness (experiment-only, isolated).
//!
//! Work item: docs/kni/2026-10-17-lambda-dialogue-derived-work-items.md
//! item 1 ("LAMBDA>0 DENEY HARNESS'I"). This example sweeps the candidate
//! objective weight lambda over an EXPERIMENT-ONLY grid on the REAL
//! ordered-pair workload of one style's shipped run, replicating the
//! production pair-cascade evaluation chain (eval_one in
//! self_anchored_spacing.rs) input-for-input, and records per pair:
//! t* (residual), J, W, V, cap-saturation share, feasible-component count,
//! residual and the pair target. Per style x lambda it writes the residual
//! distribution summary (median, p90, max, below-epsilon count,
//! excluded-class counts). Before/after renders (kern off / kern on) are
//! written for the round->straight and diagonal->straight classes.
//!
//! Isolation contract: this file ADDS an example binary only. No
//! production file is edited, no production default changes (shipped
//! lambda stays 0.0; the sweep calls the same public solver with the
//! lambda value as an explicit argument, exactly like the shipped
//! cascade does with lambda = 0.0). The sweep is strictly serial
//! (jobs = 1, declared in the work item); the context solve itself is
//! bit-identical across worker counts
//! (oracle pair_cascade_explicit_pool_bit_identical_across_worker_counts).
//!
//! Provenance rules: every policy number is parsed from the run receipt
//! (run_config rows) or read from the solver's own ClassAudit snapshot -
//! no constants are invented here. The lambda grid is the work item's own
//! list. Renders-per-class and the summary percentile rules are DECLARED
//! CONVENTIONs documented in
//! docs/kni/2026-10-18-lambda-experiment-harness.md.
//!
//! Input contract (identical shape to metrics/examples/pair_solver_timing.rs):
//!   lambda_experiment <font.otf> <receipt.txt> <mapping.tsv> <out_dir>

use kni_core::cff_reader::CffReader;
use kni_core::flatten_budget::max_total_segments;
use kni_core::reference_slice::{DrawnGlyph, Span};
use kni_metrics::class_audit::ClassAudit;
use kni_metrics::outline_spacing::{
    profile_outline, OutlineInput, OutlineProfile, ScanPolicy, MERGE_GUARD_UNITS,
};
use kni_metrics::self_anchored_spacing::{
    solve_pair_t_l2, solve_spacing_with_class_audit, PairSolve, SideClass, SpacingPolicy,
};
use kni_metrics::signed_clearance as sc;
use std::collections::HashMap;
use std::fmt::Write as FmtWrite;
use std::io::Write as IoWrite;
use std::time::Instant;

/// EXPERIMENT GRID (provenance: work item 1 of
/// docs/kni/2026-10-17-lambda-dialogue-derived-work-items.md names exactly
/// these values: 0, 0.1, 0.3, 1, 3, 10). Not invented here.
const EXPERIMENT_LAMBDAS: [f64; 6] = [0.0, 0.1, 0.3, 1.0, 3.0, 10.0];

/// CONVENTION (declared, copied from metrics/examples/pair_solver_timing.rs):
/// flatten recursion ceiling, identical role to the production adapter's own
/// subdivision depth cap (its value is not observable from outside the
/// pipeline crate; the cap is a resource guard, not a quality parameter).
const MAX_FLATTEN_DEPTH: usize = 16;

/// DECLARED CONVENTION (docs/kni/2026-10-18-lambda-experiment-harness.md):
/// how many example pairs are rendered per render class.
const RENDER_PAIRS_PER_CLASS: usize = 2;

/// Render classes (work item 1 names the four experiment classes; renders
/// are required for round-straight and diagonal-straight).
const RENDER_CLASSES: [&str; 2] = ["round->straight", "diagonal->straight"];

fn die(msg: String) -> ! {
    eprintln!("LAMBDA-EXPERIMENT-SETUP-BLOCKER: {msg}");
    std::process::exit(2);
}

/// Production flatten (pipeline drawing_polys/flatten_into), replicated
/// verbatim from metrics/examples/pair_solver_timing.rs: adaptive midpoint
/// subdivision on the measured control-point chord distance, same
/// tolerance, same budget guard, same closing-point drop. Bit-identical
/// polylines for identical input rings.
fn flatten_into(p0: [f64; 2], c1: [f64; 2], c2: [f64; 2], p1: [f64; 2], tol: f64, depth: usize, out: &mut Vec<[f64; 2]>, budget: usize) -> Result<(), String> {
    if out.len() >= budget {
        return Err(format!("flatten budget refused: {budget} total points exceeded"));
    }
    let (dx, dy) = (p1[0] - p0[0], p1[1] - p0[1]);
    let len = (dx * dx + dy * dy).sqrt();
    let dist = |p: [f64; 2]| {
        if len == 0.0 {
            ((p[0] - p0[0]).powi(2) + (p[1] - p0[1]).powi(2)).sqrt()
        } else {
            ((p[0] - p0[0]) * dy - (p[1] - p0[1]) * dx).abs() / len
        }
    };
    if depth < MAX_FLATTEN_DEPTH && (dist(c1) > tol || dist(c2) > tol) {
        let m = |a: [f64; 2], b: [f64; 2]| [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0];
        let (p01, p12, p23) = (m(p0, c1), m(c1, c2), m(c2, p1));
        let (p012, p123) = (m(p01, p12), m(p12, p23));
        let mid = m(p012, p123);
        flatten_into(p0, p01, p012, mid, tol, depth + 1, out, budget)?;
        flatten_into(mid, p123, p23, p1, tol, depth + 1, out, budget)?;
    } else {
        out.push(p1);
    }
    Ok(())
}

fn drawing_polys(g: &DrawnGlyph, tol: f64, budget: usize) -> Result<Vec<Vec<[f64; 2]>>, String> {
    let mut rings = Vec::with_capacity(g.rings.len());
    for r in &g.rings {
        let mut poly = vec![[r.start.x, r.start.y]];
        let mut cur = r.start;
        for sp in &r.spans {
            match sp {
                Span::Line { end } => {
                    poly.push([end.x, end.y]);
                    cur = *end;
                }
                Span::Cubic { control_one, control_two, end } => {
                    flatten_into(
                        [cur.x, cur.y],
                        [control_one.x, control_one.y],
                        [control_two.x, control_two.y],
                        [end.x, end.y],
                        tol, 0, &mut poly, budget,
                    )?;
                    cur = *end;
                }
            }
        }
        if poly.len() > 1 && poly.last() == poly.first() {
            poly.pop();
        }
        rings.push(poly);
    }
    Ok(rings)
}

/// Verbatim copy of the production cell integrals
/// (self_anchored_spacing.rs `cell_integrals`, pub(crate), not reachable
/// from an example). Bit-identical by construction; the copy is declared in
/// docs/kni/2026-10-18-lambda-experiment-harness.md.
fn cell_integrals(len: f64, c0: f64, c1: f64, cap: f64) -> (f64, f64) {
    let lin = |len: f64, a: f64, b: f64|
        (len * (a + b) / 2.0, len * (a * a + a * b + b * b) / 3.0);
    if c0 <= cap && c1 <= cap { return lin(len, c0, c1); }
    if c0 >= cap && c1 >= cap { return (len * cap, len * cap * cap); }
    let f = (cap - c0) / (c1 - c0);
    let (lo_len, hi_len) = (len * f, len * (1.0 - f));
    if c0 < cap {
        let (a, b) = lin(lo_len, c0, cap);
        (a + hi_len * cap, b + hi_len * cap * cap)
    } else {
        let (a, b) = lin(hi_len, cap, c1);
        (a + lo_len * cap, b + lo_len * cap * cap)
    }
}

/// Verbatim copy of the production reduction (self_anchored_spacing.rs
/// `channel_stats`, pub(crate)). Returns (W, V) over `cells` shifted by t.
fn channel_stats_copy(cells: &[(f64, f64, f64)], t: f64, cap: f64) -> (f64, f64) {
    let (mut len, mut s1, mut s2) = (0.0, 0.0, 0.0);
    for &(l, c0, c1) in cells {
        let (a, b) = cell_integrals(l, c0 + t, c1 + t, cap);
        len += l; s1 += a; s2 += b;
    }
    if !(len > 0.0) { return (0.0, 0.0); }
    let w = s1 / len;
    (w, (s2 / len - w * w).max(0.0))
}

/// Cap-saturation share: share of total cell length whose clamped channel
/// sits at the cap. Per cell (len, c0, c1) at the measured placement
/// (t already folded into the cell coordinates): both endpoints >= cap ->
/// the full length; both <= cap -> zero; crossing -> the portion above cap
/// under the same linear-in-y model cell_integrals uses. Boundary equality
/// follows the production branch order (>= cap counts as saturated).
fn cap_saturation_share(cells: &[(f64, f64, f64)], cap: f64) -> f64 {
    let (mut len, mut sat) = (0.0, 0.0);
    for &(l, c0, c1) in cells {
        len += l;
        if c0 >= cap && c1 >= cap {
            sat += l;
        } else if c0 <= cap && c1 <= cap {
            // fully below the cap: no saturated portion
        } else if c1 > c0 {
            sat += l * (c1 - cap) / (c1 - c0);
        } else {
            sat += l * (c0 - cap) / (c0 - c1);
        }
    }
    if len > 0.0 { sat / len } else { 0.0 }
}

/// DECLARED CONVENTION percentile rules over ascending-sorted |residual|:
/// median = element at (n-1)/2; p90 = element at ceil(0.9n)-1; max = last.
fn median_sorted(s: &[f64]) -> f64 { s[(s.len() - 1) / 2] }
fn p90_sorted(s: &[f64]) -> f64 {
    s[((s.len() as f64 * 0.9).ceil() as usize).saturating_sub(1)]
}

/// One parsed receipt run_config value (key -> value).
fn receipt_run_config(receipt: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for line in receipt.lines() {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() >= 3 && f[0] == "run_config" {
            out.insert(f[1].to_string(), f[2].to_string());
        }
    }
    out
}

fn cfg_f64(cfg: &HashMap<String, String>, key: &str) -> f64 {
    cfg.get(key)
        .unwrap_or_else(|| die(format!("receipt run_config lacks required key {key}")))
        .parse()
        .unwrap_or_else(|_| die(format!("receipt run_config {key} is not numeric")))
}
fn cfg_u64(cfg: &HashMap<String, String>, key: &str) -> u64 {
    cfg.get(key)
        .unwrap_or_else(|| die(format!("receipt run_config lacks required key {key}")))
        .parse()
        .unwrap_or_else(|_| die(format!("receipt run_config {key} is not an integer")))
}

/// Style label from the receipt's own scale_context run_config row (the
/// cohort field, e.g. "Marq/Alternate"). The row carries its payload either
/// as further tab fields or embedded in field 2 with literal "\\t"
/// separators; both shapes are parsed. Typed "unknown" when absent, never
/// invented.
fn receipt_style(receipt: &str) -> String {
    for line in receipt.lines() {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() >= 3 && f[0] == "run_config" && f[1] == "scale_context" {
            if f.len() >= 4 {
                return f[3].to_string();
            }
            let toks: Vec<&str> = f[2].split("\\t").collect();
            if toks.len() >= 2 {
                return toks[1].to_string();
            }
        }
    }
    "unknown".to_string()
}

/// Parse "key=VALUE" numeric assignments out of a policy narrative line.
/// Returns None when the narrative does not carry the value (reported as
/// "not measured", never guessed).
fn parse_named_f64(text: &str, key: &str) -> Option<f64> {
    let mut start = 0;
    while let Some(pos) = text[start..].find(key) {
        let p = start + pos + key.len();
        if text[p..].starts_with('=') {
            let rest = &text[p + 1..];
            let end = rest.find(|c: char| !(c.is_ascii_digit() || c == '.' || c == '-' || c == '+' || c == 'e' || c == 'E')).unwrap_or(rest.len());
            if let Ok(v) = rest[..end].parse::<f64>() {
                return Some(v);
            }
        }
        start = p;
    }
    None
}

/// Everything the per-pair evaluation needs that does not change with the
/// pair or lambda (all receipt- or audit-derived; nothing invented).
struct SweepInputs<'a> {
    metrics: &'a HashMap<String, (f64, f64, f64)>, // glyph -> (lsb, rsb, advance)
    classes: &'a HashMap<String, (SideClass, SideClass)>, // glyph -> (left, right)
    targets: &'a HashMap<(SideClass, SideClass), f64>,    // facing class pair -> target
    w_target: f64,
    dcap: f64,
    pair_min_shared_rows: usize,
    eps: f64,
}

/// One measured pair row (per style x pair x lambda). Option fields are
/// empty in the TSV when the variant does not carry the value; no silent
/// defaults.
#[derive(Clone)]
struct PairRow {
    class: String,
    left: String,
    right: String,
    variant: &'static str,
    below_epsilon: bool,
    t_star: Option<f64>,
    j: Option<f64>,
    w: Option<f64>,
    v: Option<f64>,
    cap_sat_share: Option<f64>,
    feasible_components: Option<usize>,
    residual: Option<f64>,
    pair_target: Option<f64>,
}

/// Replicates the production eval_one gate chain
/// (self_anchored_spacing.rs pair cascade) for one ordered pair at one
/// lambda. Differences from production, all declared: the lambda value is
/// the sweep argument instead of the shipped 0.0; the J/W/V/cap-saturation
/// measurements fold the residual into the same cell model the cascade
/// re-checks (clearance_cells_constant at raw_base + residual); the
/// feasible-component count is reported from the same public
/// signed_clearance functions the solver calls internally.
fn eval_pair(l: &OutlineProfile, r: &OutlineProfile, inp: &SweepInputs, lambda: f64) -> PairRow {
    let base = |class: String, variant: &'static str| PairRow {
        class, left: l.glyph_id.clone(), right: r.glyph_id.clone(), variant,
        below_epsilon: false, t_star: None, j: None, w: None, v: None,
        cap_sat_share: None, feasible_components: None, residual: None,
        pair_target: None,
    };
    let (cl, cr) = match (inp.classes.get(&l.glyph_id), inp.classes.get(&r.glyph_id)) {
        (Some(a), Some(b)) => (a.1, b.0), // right side of left, left side of right
        _ => (SideClass::Empty, SideClass::Empty),
    };
    let class = format!("{cl}->{cr}");
    let pair_gap = *inp.targets.get(&(cl, cr)).unwrap_or(&inp.w_target);
    let (l_rsb, r_lsb) = match (inp.metrics.get(&l.glyph_id), inp.metrics.get(&r.glyph_id)) {
        (Some(a), Some(b)) => (a.1, b.0),
        _ => return base(class, "missing_sidebearings"),
    };
    let base_offset = l_rsb + r_lsb;
    let raw_base = l.bounds[2] - r.bounds[0] + base_offset;
    let cells = sc::clearance_cells_constant(l, r, raw_base);
    if cells.len() < inp.pair_min_shared_rows {
        return base(class, "gate_unmeasurable_shared_rows");
    }
    let min_base = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
    if !min_base.is_finite() {
        return base(class, "gate_unmeasurable_nonfinite");
    }
    // Frozen domain convention (production comment in eval_one):
    // [t_lo, t_hi] = [-min_base, dcap - min_base].
    let t_lo = -min_base;
    let t_hi = (inp.dcap - min_base).max(t_lo);
    let feasible_components = match sc::forbidden_residual_intervals(l, r, raw_base) {
        Ok(f) => sc::feasible_components(t_lo, t_hi, &f).ok().map(|c| c.len()),
        Err(_) => None,
    };
    let advance_l = inp.metrics[l.glyph_id.as_str()].2;
    let l_tr = inp.metrics[l.glyph_id.as_str()].0 - l.bounds[0];
    let r_tr = inp.metrics[r.glyph_id.as_str()].0 - r.bounds[0];
    let mut row = base(class, "solved");
    row.pair_target = if pair_gap.is_finite() && pair_gap >= 0.0 { Some(pair_gap) } else { None };
    row.feasible_components = feasible_components;
    match solve_pair_t_l2(l, r, raw_base, inp.dcap, pair_gap, lambda, t_lo, t_hi, advance_l, l_tr, r_tr) {
        PairSolve::Solved { residual, .. } => {
            row.residual = Some(residual);
            row.t_star = Some(residual);
            row.below_epsilon = residual.abs() < inp.eps;
            let cells_at = sc::clearance_cells_constant(l, r, raw_base + residual);
            let (w, v) = channel_stats_copy(&cells_at, 0.0, inp.dcap);
            row.w = Some(w);
            row.v = Some(v);
            row.j = Some((w - pair_gap) * (w - pair_gap) + lambda * v);
            row.cap_sat_share = Some(cap_saturation_share(&cells_at, inp.dcap));
        }
        PairSolve::NoFeasible => row.variant = "no_feasible",
        PairSolve::NoAcceptedCandidate => row.variant = "no_accepted_candidate",
        PairSolve::NotConverged(_) => row.variant = "not_converged",
        PairSolve::Unmeasurable => row.variant = "solve_unmeasurable",
    }
    row
}

fn fmt_opt(v: Option<f64>) -> String {
    v.map(|x| format!("{x:.6}")).unwrap_or_default()
}
fn fmt_opt_usize(v: Option<usize>) -> String {
    v.map(|x| x.to_string()).unwrap_or_default()
}

#[derive(Default, Clone, Copy)]
struct LambdaCounts {
    solved: u64,
    below_epsilon: u64,
    gate_shared_rows: u64,
    gate_nonfinite: u64,
    no_feasible: u64,
    no_accepted_candidate: u64,
    not_converged: u64,
    solve_unmeasurable: u64,
    missing_sidebearings: u64,
}

/// One SVG: rows = the lambda grid, columns = kern off (origin = advance_l)
/// and kern on (origin = advance_l + t*). Geometry is drawn from the same
/// CFF readback rings the profiles were built from, in the export frame
/// (x_translation = lsb - ink_xmin exactly as GlyphFrame::new composes it).
#[allow(clippy::too_many_arguments)]
fn render_pair_svg(
    path: &std::path::Path,
    style: &str,
    class: &str,
    left: &str,
    right: &str,
    per_lambda: &[(f64, PairRow)],
    polys_l: &[Vec<[f64; 2]>],
    polys_r: &[Vec<[f64; 2]>],
    l_tr: f64,
    r_tr: f64,
    advance_l: f64,
    cap_height: f64,
) -> std::io::Result<()> {
    // y extent shared by every row/column so rows align visually.
    let mut y_min = 0.0f64.min(cap_height);
    let mut y_max = 0.0f64.max(cap_height);
    for p in polys_l.iter().chain(polys_r.iter()).flatten() {
        y_min = y_min.min(p[1]);
        y_max = y_max.max(p[1]);
    }
    let pad = (y_max - y_min).max(1.0) * 0.05;
    y_min -= pad;
    y_max += pad;
    let scale = 180.0 / (y_max - y_min);
    let label_w = 250.0f64;
    // Column content width: identical across columns (only origin shifts).
    let mut x_min = f64::INFINITY;
    let mut x_max = f64::NEG_INFINITY;
    for row in per_lambda {
        let t = row.1.t_star.unwrap_or(0.0);
        for origin in [advance_l, advance_l + t] {
            for p in polys_l {
                for q in p {
                    x_min = x_min.min(q[0] + l_tr);
                    x_max = x_max.max(q[0] + l_tr);
                }
            }
            for p in polys_r {
                for q in p {
                    x_min = x_min.min(q[0] + r_tr + origin);
                    x_max = x_max.max(q[0] + r_tr + origin);
                }
            }
        }
    }
    let col_w = (x_max - x_min).max(1.0);
    let header_h = 16.0 / scale;
    let row_h = (y_max - y_min) + 24.0 / scale;
    let width = label_w / scale + 2.0 * col_w + 20.0 / scale;
    let height = header_h + per_lambda.len() as f64 * row_h + 8.0 / scale;
    let mut s = String::new();
    let _ = writeln!(s, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {:.3} {:.3}\" width=\"{:.0}\" height=\"{:.0}\" font-family=\"monospace\">",
        width, height, width * scale, height * scale);
    let _ = writeln!(s, "<rect x=\"0\" y=\"0\" width=\"{:.3}\" height=\"{:.3}\" fill=\"white\"/>", width, height);
    let px = |x: f64| x; // font units inside the viewBox; scale is applied by the viewBox size
    let fy = |y: f64| y_max - y; // flip y (SVG y grows downward)
    // Column headers, once, in the top strip.
    for (c, label) in ["kern off", "kern on"].iter().enumerate() {
        let hx = label_w / scale + c as f64 * (col_w + 10.0 / scale) + col_w / 2.0 - 30.0 / scale;
        let _ = writeln!(s, "<text x=\"{:.3}\" y=\"{:.3}\" font-size=\"{:.3}\" fill=\"black\">{}</text>",
            px(hx), px(11.0 / scale), 11.0 / scale, label);
    }
    for (i, (lambda, row)) in per_lambda.iter().enumerate() {
        let y0 = header_h + i as f64 * row_h;
        let t = row.t_star.unwrap_or(0.0);
        let _ = writeln!(s, "<text x=\"{:.3}\" y=\"{:.3}\" font-size=\"{:.3}\" fill=\"black\">lambda={} t*={} J={} W={} V={} sat={}</text>",
            px(2.0 / scale), y0 + 12.0 / scale, 11.0 / scale,
            lambda, fmt_opt(row.t_star), fmt_opt(row.j), fmt_opt(row.w), fmt_opt(row.v), fmt_opt(row.cap_sat_share));
        for (c, origin) in [advance_l, advance_l + t].iter().enumerate() {
            let x0 = label_w / scale + c as f64 * (col_w + 10.0 / scale) - x_min;
            let _ = writeln!(s, "<g transform=\"translate({:.3},{:.3})\">", px(x0), y0);
            // baseline and cap-height guides
            let _ = writeln!(s, "<line x1=\"{:.3}\" y1=\"{:.3}\" x2=\"{:.3}\" y2=\"{:.3}\" stroke=\"red\" stroke-width=\"{:.3}\"/>",
                px(x_min - 5.0 / scale), fy(0.0), px(x_min + col_w + 5.0 / scale), fy(0.0), 0.8 / scale);
            let _ = writeln!(s, "<line x1=\"{:.3}\" y1=\"{:.3}\" x2=\"{:.3}\" y2=\"{:.3}\" stroke=\"blue\" stroke-dasharray=\"{:.3},{:.3}\" stroke-width=\"{:.3}\"/>",
                px(x_min - 5.0 / scale), fy(cap_height), px(x_min + col_w + 5.0 / scale), fy(cap_height), 2.0 / scale, 2.0 / scale, 0.8 / scale);
            for p in polys_l {
                if p.len() < 2 { continue; }
                let mut d = format!("M {:.3} {:.3}", px(p[0][0] + l_tr), fy(p[0][1]));
                for q in &p[1..] {
                    let _ = write!(d, " L {:.3} {:.3}", px(q[0] + l_tr), fy(q[1]));
                }
                let _ = writeln!(s, "<path d=\"{d} Z\" fill=\"black\"/>");
            }
            for p in polys_r {
                if p.len() < 2 { continue; }
                let mut d = format!("M {:.3} {:.3}", px(p[0][0] + r_tr + origin), fy(p[0][1]));
                for q in &p[1..] {
                    let _ = write!(d, " L {:.3} {:.3}", px(q[0] + r_tr + origin), fy(q[1]));
                }
                let _ = writeln!(s, "<path d=\"{d} Z\" fill=\"black\"/>");
            }
            let _ = writeln!(s, "</g>");
        }
    }
    let _ = writeln!(s, "<text x=\"{:.3}\" y=\"{:.3}\" font-size=\"{:.3}\" fill=\"gray\">{} {} {}-&gt;{}</text>",
        px(2.0 / scale), height - 4.0 / scale, 11.0 / scale, style, class, left, right);
    let _ = writeln!(s, "</svg>");
    std::fs::write(path, s)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 5 {
        die("usage: lambda_experiment <font.otf> <receipt.txt> <mapping.tsv> <out_dir>".into());
    }
    let otf = std::fs::read(&args[1]).unwrap_or_else(|e| die(format!("{}: {e}", args[1])));
    let receipt = std::fs::read_to_string(&args[2]).unwrap_or_else(|e| die(format!("{}: {e}", args[2])));
    let mapping = std::fs::read_to_string(&args[3]).unwrap_or_else(|e| die(format!("{}: {e}", args[3])));
    let out_dir = std::path::PathBuf::from(&args[4]);
    std::fs::create_dir_all(out_dir.join("renders"))
        .unwrap_or_else(|e| die(format!("out_dir: {e}")));
    let font_sha = kni_learning::sha256::sha256_hex(&otf);
    let receipt_sha = kni_learning::sha256::sha256_hex(receipt.as_bytes());
    let mapping_sha = kni_learning::sha256::sha256_hex(mapping.as_bytes());
    let style = receipt_style(&receipt);

    // ---- receipt-derived configuration (no invented numbers) -------------
    let cfg = receipt_run_config(&receipt);
    let flatten_tolerance = cfg_f64(&cfg, "flatten_tolerance");
    let row_step = cfg_f64(&cfg, "scan_row_step");
    let max_rows = cfg_u64(&cfg, "scan_max_rows") as usize;
    let sample_resolution = cfg_f64(&cfg, "sample_resolution");
    let max_pair_evaluations = cfg_u64(&cfg, "max_pair_evaluations");
    let max_pairs = cfg_u64(&cfg, "max_pairs") as usize;
    let pair_min_shared_rows = cfg_u64(&cfg, "pair_min_shared_rows") as usize;
    let (canvas_w, canvas_h) = {
        let mut wh = None;
        for line in receipt.lines() {
            if line.starts_with("glyph\t") {
                let f: Vec<&str> = line.split('\t').collect();
                for i in 0..f.len() - 1 {
                    if f[i] == "source_px" {
                        let mut it = f[i + 1].split('x');
                        let w = it.next().and_then(|s| s.parse().ok());
                        let h = it.next().and_then(|s| s.parse().ok());
                        wh = match (w, h) {
                            (Some(w), Some(h)) => Some((w, h)),
                            _ => die(format!("unparseable source_px {}", f[i + 1])),
                        };
                    }
                }
                break;
            }
        }
        wh.unwrap_or_else(|| die("receipt carries no glyph source_px".into()))
    };
    let budget = max_total_segments(canvas_w, canvas_h)
        .unwrap_or_else(|| die("flatten budget unavailable for canvas".into()));

    // ---- mapping: gid -> glyph name (solver identity) --------------------
    let mut gid_name: HashMap<u16, String> = HashMap::new();
    {
        let mut lines = mapping.lines();
        let header = lines.next().unwrap_or("");
        if header != "codepoint\tname\tgid" {
            die(format!("mapping header must be codepoint<TAB>name<TAB>gid, got {header:?}"));
        }
        for line in lines {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() != 3 {
                continue;
            }
            let gid: u16 = f[2].parse().unwrap_or_else(|_| die(format!("mapping gid not an integer: {line}")));
            if gid_name.insert(gid, f[1].to_string()).is_some() {
                die(format!("duplicate gid {gid} in mapping"));
            }
        }
    }

    // ---- profiles from the OTF readback (real shipped outlines) ----------
    let t_profiles = Instant::now();
    let reader = CffReader::from_bytes(&otf, &font_sha).unwrap_or_else(|e| die(format!("CffReader: {e:?}")));
    let upm = reader.units_per_em();
    let glyph_count = reader.glyph_count();
    let mut profiles: Vec<OutlineProfile> = Vec::new();
    let mut polys_map: HashMap<String, Vec<Vec<[f64; 2]>>> = HashMap::new();
    let mut profile_failures = 0u64;
    for gid in 1..glyph_count as u16 {
        let name = match gid_name.get(&gid) {
            Some(n) => n.clone(),
            None => continue, // glyphs outside the manifest mapping are not solver population
        };
        let g = match reader.read_glyph(gid) {
            Ok(rg) => rg.drawn(name.clone()),
            Err(_) => {
                profile_failures += 1;
                continue;
            }
        };
        let polys = match drawing_polys(&g, flatten_tolerance, budget) {
            Ok(p) => p,
            Err(_) => {
                profile_failures += 1;
                continue;
            }
        };
        match profile_outline(
            &OutlineInput {
                glyph_id: name.clone(),
                source_pin: font_sha.clone(),
                upm,
                origin: [0.0, 0.0],
                flatten_tolerance,
                rings: polys.clone(),
            },
            ScanPolicy { row_step, max_rows, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) },
        ) {
            Ok(p) => {
                polys_map.insert(name, polys);
                profiles.push(p);
            }
            Err(_) => profile_failures += 1,
        }
    }
    let profile_build_s = t_profiles.elapsed().as_secs_f64();

    // ---- context solve with class audit (supplies per-pair production
    // inputs: lsb/rsb/advance, side classes, class-pair targets, dcap,
    // W_target). lambda: None -> shipped 0.0; bit-identical across worker
    // counts per the pair-cascade oracle; the lambda sweep itself is
    // strictly serial (jobs = 1, declared in the work item). --------------
    let policy = SpacingPolicy {
        sample_resolution,
        max_pair_evaluations,
        max_pairs,
        pair_min_shared_rows,
        lambda: None,
        dcap: None,
        class_channel_targets: false,
        contrast_floor: false,
        cadence_class_pass: false,
    };
    let t_solve = Instant::now();
    let (solution, audit): (_, ClassAudit) = match solve_spacing_with_class_audit(&profiles, None, &policy) {
        Ok(sa) => sa,
        Err(e) => die(format!("solve_spacing refused: {e:?}")),
    };
    let solve_spacing_s = t_solve.elapsed().as_secs_f64();
    let eps = sample_resolution / 2.0;
    let dcap = audit.dcap;
    let w_target = audit.w_target;

    let metrics: HashMap<String, (f64, f64, f64)> = solution
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.clone(), (g.lsb, g.rsb, g.advance)))
        .collect();
    let classes: HashMap<String, (SideClass, SideClass)> = audit
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.clone(), (g.left_class, g.right_class)))
        .collect();
    let mut targets: HashMap<(SideClass, SideClass), f64> = HashMap::new();
    for row in &audit.pair_targets {
        targets.insert((row.left_class, row.right_class), row.target);
    }
    let inked: Vec<&OutlineProfile> = profiles.iter().filter(|p| p.ink_area > 0.0).collect();
    let n = inked.len();
    let ordered_pairs = (n as u64) * (n.saturating_sub(1) as u64);
    let inp = SweepInputs {
        metrics: &metrics,
        classes: &classes,
        targets: &targets,
        w_target,
        dcap,
        pair_min_shared_rows,
        eps,
    };

    // ---- outputs ----------------------------------------------------------
    let pairs_path = out_dir.join("pairs.tsv");
    let mut pairs_out = std::io::BufWriter::new(
        std::fs::File::create(&pairs_path).unwrap_or_else(|e| die(format!("pairs.tsv: {e}"))),
    );
    writeln!(pairs_out, "style\tlambda\tclass\tleft\tright\tvariant\tbelow_epsilon\tt_star\tJ\tW\tV\tcap_sat_share\tfeasible_components\tresidual\tpair_target")
        .unwrap_or_else(|e| die(format!("pairs.tsv: {e}")));
    let mut summary_rows: Vec<String> = Vec::new();
    let mut lambda_walls: Vec<(f64, f64)> = Vec::new();
    // Render selection state: t* at lambda 0 and lambda 10 per pair in the
    // render classes (DECLARED CONVENTION ranking: |t*(10)-t*(0)| desc,
    // ties by (left, right) ascending).
    let mut t_at: [HashMap<(String, String, String), f64>; 2] = [HashMap::new(), HashMap::new()];
    let mut total_rows = 0u64;

    for lambda in EXPERIMENT_LAMBDAS {
        let t0 = Instant::now();
        let mut counts = LambdaCounts::default();
        let mut solved_abs_res: Vec<f64> = Vec::new();
        for l in &inked {
            for r in &inked {
                if l.glyph_id == r.glyph_id {
                    continue; // self pair, skipped by construction
                }
                let row = eval_pair(l, r, &inp, lambda);
                total_rows += 1;
                match row.variant {
                    "solved" => {
                        counts.solved += 1;
                        if row.below_epsilon {
                            counts.below_epsilon += 1;
                        }
                        solved_abs_res.push(row.residual.unwrap_or(0.0).abs());
                        if RENDER_CLASSES.contains(&row.class.as_str()) {
                            if lambda == EXPERIMENT_LAMBDAS[0] {
                                t_at[0].insert((row.class.clone(), row.left.clone(), row.right.clone()), row.t_star.unwrap_or(0.0));
                            }
                            if lambda == EXPERIMENT_LAMBDAS[EXPERIMENT_LAMBDAS.len() - 1] {
                                t_at[1].insert((row.class.clone(), row.left.clone(), row.right.clone()), row.t_star.unwrap_or(0.0));
                            }
                        }
                    }
                    "gate_unmeasurable_shared_rows" => counts.gate_shared_rows += 1,
                    "gate_unmeasurable_nonfinite" => counts.gate_nonfinite += 1,
                    "no_feasible" => counts.no_feasible += 1,
                    "no_accepted_candidate" => counts.no_accepted_candidate += 1,
                    "not_converged" => counts.not_converged += 1,
                    "solve_unmeasurable" => counts.solve_unmeasurable += 1,
                    _ => counts.missing_sidebearings += 1,
                }
                writeln!(
                    pairs_out,
                    "{style}\t{lambda}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
                    row.class, row.left, row.right, row.variant, row.below_epsilon as u8,
                    fmt_opt(row.t_star), fmt_opt(row.j), fmt_opt(row.w), fmt_opt(row.v),
                    fmt_opt(row.cap_sat_share), fmt_opt_usize(row.feasible_components),
                    fmt_opt(row.residual), fmt_opt(row.pair_target),
                )
                .unwrap_or_else(|e| die(format!("pairs.tsv: {e}")));
            }
        }
        let wall = t0.elapsed().as_secs_f64();
        lambda_walls.push((lambda, wall));
        solved_abs_res.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let (median, p90, max) = if solved_abs_res.is_empty() {
            (f64::NAN, f64::NAN, f64::NAN)
        } else {
            (median_sorted(&solved_abs_res), p90_sorted(&solved_abs_res), *solved_abs_res.last().unwrap_or(&f64::NAN))
        };
        summary_rows.push(format!(
            "{style}\t{lambda}\t{ordered_pairs}\t{}\t{}\t{median:.6}\t{p90:.6}\t{max:.6}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{wall:.3}",
            counts.solved, counts.below_epsilon, counts.gate_shared_rows, counts.gate_nonfinite,
            counts.no_feasible, counts.no_accepted_candidate, counts.not_converged,
            counts.solve_unmeasurable, counts.missing_sidebearings,
        ));
        println!("lambda={lambda}\twall_s={wall:.3}\tsolved={}\tbelow_epsilon={}", counts.solved, counts.below_epsilon);
    }
    drop(pairs_out);
    let mut summary_out = std::io::BufWriter::new(
        std::fs::File::create(out_dir.join("summary.tsv")).unwrap_or_else(|e| die(format!("summary.tsv: {e}"))),
    );
    writeln!(summary_out, "style\tlambda\tordered_pairs\tsolved\tbelow_epsilon\tmedian_abs_residual\tp90_abs_residual\tmax_abs_residual\tgate_shared_rows\tgate_nonfinite\tno_feasible\tno_accepted_candidate\tnot_converged\tsolve_unmeasurable\tmissing_sidebearings\twall_s")
        .unwrap_or_else(|e| die(format!("summary.tsv: {e}")));
    for row in &summary_rows {
        writeln!(summary_out, "{row}").unwrap_or_else(|e| die(format!("summary.tsv: {e}")));
    }
    drop(summary_out);

    // ---- renders (round->straight, diagonal->straight) -------------------
    let prof_by_id: HashMap<&str, &OutlineProfile> =
        profiles.iter().map(|p| (p.glyph_id.as_str(), p)).collect();
    let mut render_log: Vec<String> = Vec::new();
    for class in RENDER_CLASSES {
        let mut cands: Vec<(&(String, String, String), f64)> = t_at[0]
            .iter()
            .filter(|(k, _)| k.0 == class)
            .filter_map(|(k, t0)| t_at[1].get(k).map(|t10| (k, (t10 - t0).abs())))
            .collect();
        cands.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal)
            .then((&a.0 .1, &a.0 .2).cmp(&(&b.0 .1, &b.0 .2))));
        for (key, delta) in cands.into_iter().take(RENDER_PAIRS_PER_CLASS) {
            let (_, left, right) = key;
            let (pl, pr) = match (prof_by_id.get(left.as_str()), prof_by_id.get(right.as_str())) {
                (Some(a), Some(b)) => (*a, *b),
                _ => continue,
            };
            let per_lambda: Vec<(f64, PairRow)> = EXPERIMENT_LAMBDAS
                .iter()
                .map(|&lambda| (lambda, eval_pair(pl, pr, &inp, lambda)))
                .collect();
            let (polys_l, polys_r) = match (polys_map.get(left), polys_map.get(right)) {
                (Some(a), Some(b)) => (a, b),
                _ => continue,
            };
            let (l_tr, r_tr, advance_l) = match (metrics.get(left), metrics.get(right)) {
                (Some(a), Some(b)) => (a.0 - pl.bounds[0], b.0 - pr.bounds[0], a.2),
                _ => continue,
            };
            let svg_path = out_dir.join("renders").join(format!(
                "{}_{}_{}.svg",
                class.replace("->", "-"), left, right
            ));
            match render_pair_svg(&svg_path, &style, class, left, right, &per_lambda,
                                  polys_l, polys_r, l_tr, r_tr, advance_l, audit.cap_height) {
                Ok(()) => render_log.push(format!("{class}\t{left}\t{right}\tdelta_t={delta:.6}\t{}", svg_path.display())),
                Err(e) => render_log.push(format!("{class}\t{left}\t{right}\tRENDER-FAILED\t{e}")),
            }
        }
    }

    // ---- harness receipt ---------------------------------------------------
    let receipt_spacing = receipt.lines().find(|l| l.starts_with("spacing\t")).unwrap_or("");
    let receipt_w_target = parse_named_f64(receipt_spacing, "W_target");
    let receipt_dcap = parse_named_f64(receipt_spacing, "dcap");
    let mut rep = String::new();
    let _ = writeln!(rep, "lambda_experiment harness receipt (experiment-only; production default lambda=0 unchanged)");
    let _ = writeln!(rep, "style\t{style}");
    let _ = writeln!(rep, "font_sha256\t{font_sha}");
    let _ = writeln!(rep, "receipt_sha256\t{receipt_sha}");
    let _ = writeln!(rep, "mapping_sha256\t{mapping_sha}");
    let _ = writeln!(rep, "lambda_grid\t{:?}\tprovenance=docs/kni/2026-10-17-lambda-dialogue-derived-work-items.md item 1", EXPERIMENT_LAMBDAS);
    let _ = writeln!(rep, "jobs\t1\tdeclared: strictly serial lambda sweep; context solve bit-identical across worker counts (oracle pair_cascade_explicit_pool_bit_identical_across_worker_counts)");
    let _ = writeln!(rep, "config_echo\tflatten_tolerance={flatten_tolerance} scan_row_step={row_step} scan_max_rows={max_rows} sample_resolution={sample_resolution} max_pair_evaluations={max_pair_evaluations} max_pairs={max_pairs} pair_min_shared_rows={pair_min_shared_rows}");
    let _ = writeln!(rep, "audit\tupm={} dcap={dcap:.3} W_target={w_target:.3} lambda_shipped={:.3} cap_height={:.3}", audit.upm, audit.lambda, audit.cap_height);
    let _ = writeln!(rep, "profiles_built\t{}\tprofile_failures\t{profile_failures}\tinked_glyphs\t{n}\tordered_pairs\t{ordered_pairs}", profiles.len());
    let _ = writeln!(rep, "rows_written\t{total_rows}\taccounting_closed\t{}", total_rows == ordered_pairs * EXPERIMENT_LAMBDAS.len() as u64);
    let _ = writeln!(rep, "profile_build_s\t{profile_build_s:.3}\tcontext_solve_s\t{solve_spacing_s:.3}");
    for (lambda, wall) in &lambda_walls {
        let _ = writeln!(rep, "lambda_wall_s\tlambda={lambda}\t{wall:.3}");
    }
    match (receipt_dcap, receipt_w_target) {
        (Some(rd), Some(rw)) => {
            let _ = writeln!(rep, "receipt_validation\tdcap_receipt={rd:.3} delta={:.3}\tW_target_receipt={rw:.3} delta={:.3}\t(profiles here are the shipped CFF integer readback; the receipt profiled pre-rounding outlines)", dcap - rd, w_target - rw);
        }
        _ => {
            let _ = writeln!(rep, "receipt_validation\treceipt anchor values not parseable; not measured");
        }
    }
    let _ = writeln!(rep, "solution_pairs_emitted\t{}\texcluded_below_epsilon\t{}\texcluded_unmeasurable\t{}\texcluded_self\t{}", solution.pairs.len(), solution.excluded_below_epsilon, solution.excluded_unmeasurable, solution.excluded_self_pairs);
    for line in &render_log {
        let _ = writeln!(rep, "render\t{line}");
    }
    std::fs::write(out_dir.join("receipt.txt"), rep)
        .unwrap_or_else(|e| die(format!("receipt.txt: {e}")));
    println!("done\t{}\trows={total_rows}", out_dir.display());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect_profile(id: &str, x0: f64, x1: f64, y0: f64, y1: f64) -> OutlineProfile {
        let rings = vec![vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]];
        profile_outline(
            &OutlineInput {
                glyph_id: id.to_string(),
                source_pin: "test".to_string(),
                upm: 1000,
                origin: [0.0, 0.0],
                flatten_tolerance: 0.5,
                rings,
            },
            ScanPolicy { row_step: 10.0, max_rows: 1000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) },
        )
        .expect("rect profile")
    }

    #[test]
    fn cell_integrals_numeric_check() {
        // Below cap: pure linear segment integrals.
        let (s1, s2) = cell_integrals(2.0, 0.0, 4.0, 10.0);
        assert!((s1 - 4.0).abs() < 1e-12, "s1={s1}");
        assert!((s2 - 32.0 / 3.0).abs() < 1e-12, "s2={s2}");
        let (w, v) = channel_stats_copy(&[(2.0, 0.0, 4.0)], 0.0, 10.0);
        assert!((w - 2.0).abs() < 1e-12, "W={w}");
        assert!((v - 4.0 / 3.0).abs() < 1e-12, "V={v}");
    }

    #[test]
    fn cap_saturation_share_cases() {
        let cap = 10.0;
        // Fully saturated cell: share 1.
        assert_eq!(cap_saturation_share(&[(1.0, 12.0, 12.0)], cap), 1.0);
        // Fully below: share 0.
        assert_eq!(cap_saturation_share(&[(1.0, 5.0, 5.0)], cap), 0.0);
        // Crossing cell: linear gap 5 -> 15, cap 10 sits at half: share 0.5.
        assert_eq!(cap_saturation_share(&[(1.0, 5.0, 15.0)], cap), 0.5);
    }

    #[test]
    fn percentile_rules() {
        let s = [1.0, 2.0, 3.0, 4.0, 5.0];
        assert_eq!(median_sorted(&s), 3.0);
        assert_eq!(p90_sorted(&s), 5.0);
        let s2 = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0];
        assert_eq!(median_sorted(&s2), 5.0);
        assert_eq!(p90_sorted(&s2), 9.0);
    }

    #[test]
    fn sweep_matches_production_solve_and_closes_accounting() {
        let a = rect_profile("A", 0.0, 100.0, 0.0, 500.0);
        let b = rect_profile("B", 0.0, 100.0, 0.0, 500.0);
        let metrics: HashMap<String, (f64, f64, f64)> = [
            ("A".to_string(), (50.0, 50.0, 600.0)),
            ("B".to_string(), (50.0, 50.0, 600.0)),
        ]
        .into_iter()
        .collect();
        let classes: HashMap<String, (SideClass, SideClass)> = [
            ("A".to_string(), (SideClass::Straight, SideClass::Straight)),
            ("B".to_string(), (SideClass::Straight, SideClass::Straight)),
        ]
        .into_iter()
        .collect();
        let targets: HashMap<(SideClass, SideClass), f64> =
            [((SideClass::Straight, SideClass::Straight), 100.0)].into_iter().collect();
        let inp = SweepInputs {
            metrics: &metrics,
            classes: &classes,
            targets: &targets,
            w_target: 100.0,
            dcap: 400.0,
            pair_min_shared_rows: 1,
            eps: 5.0,
        };
        let inked = [&a, &b];
        let mut rows = 0u64;
        for l in inked {
            for r in inked {
                if l.glyph_id == r.glyph_id {
                    continue;
                }
                let row = eval_pair(l, r, &inp, 0.0);
                rows += 1;
                assert_eq!(row.variant, "solved");
                // Bit-identity: the lambda=0 arm equals the direct
                // production-pattern solve_pair_t_l2 call.
                let base_offset = 50.0 + 50.0;
                let raw_base = l.bounds[2] - r.bounds[0] + base_offset;
                let cells = sc::clearance_cells_constant(l, r, raw_base);
                let min_base = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
                let t_lo = -min_base;
                let t_hi = (400.0 - min_base).max(t_lo);
                let direct = solve_pair_t_l2(l, r, raw_base, 400.0, 100.0, 0.0, t_lo, t_hi,
                                             600.0, 50.0 - l.bounds[0], 50.0 - r.bounds[0]);
                match direct {
                    PairSolve::Solved { residual, .. } => {
                        assert_eq!(row.residual.map(f64::to_bits), Some(residual.to_bits()));
                    }
                    other => panic!("direct solve not solved: {other:?}"),
                }
            }
        }
        // Accounting closure: every ordered non-self pair produced exactly one row.
        assert_eq!(rows, 2 * 1);
    }
}
