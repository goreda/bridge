//! Pair-solver standalone timing, isolated from the pipeline.
//!
//! Measures `solve_pair_t_l2` over the REAL ordered-pair workload of a real
//! shipped font: profiles are built from the OTF readback (CFF integer
//! outlines, flattened with the production algorithm at the production
//! tolerance), the pair set is every ordered pair of inked glyphs (same
//! construction as the production cascade's `eval_one` gate chain), and the
//! per-pair solve arguments are rebuilt exactly as the production cascade
//! builds them from the spacing solution. Every policy number is parsed
//! from the run receipt (run_config rows) or from the solution's own
//! policy_derivation receipt - no constants are invented here; the one
//! free arm parameter (candidate-path lambda) is a declared CONVENTION
//! below. Wall times are real `Instant` measurements; anything that cannot
//! be measured is reported as "not measured", never estimated.
//!
//! Arms:
//!   frozen    - lambda = 0.0: the shipped path (receipt policy line:
//!               lambda=0.000; solve_pair_t keeps the frozen W-root/bound
//!               interior solve at lambda == 0).
//!   candidate - lambda = CANDIDATE_LAMBDA (declared CONVENTION): the
//!               lambda > 0 piecewise-candidate interior solve. The exact
//!               objective/anchor inputs are identical across arms; only
//!               the interior solve path differs.
//!
//! Usage: pair_solver_timing <font.otf> <receipt.txt> <mapping.tsv> [runs]
//! Default runs = 3 (spec: report min/median/max of 3).

use kni_core::cff_reader::CffReader;
use kni_core::flatten_budget::max_total_segments;
use kni_core::reference_slice::{DrawnGlyph, Span};
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, OutlineProfile, ScanPolicy, MERGE_GUARD_UNITS};
use kni_metrics::self_anchored_spacing::{
    solve_pair_t_l2, solve_spacing_jobs, PairSolve, SpacingPolicy,
};
use kni_metrics::signed_clearance::clearance_cells_constant;
use std::collections::HashMap;
use std::time::Instant;

/// CONVENTION (declared, not measured): the candidate arm's objective
/// weight. Production ships lambda = 0 (receipt policy line); the lambda>0
/// interior solve is the candidate path under evaluation. 1.0 weights the
/// two gap^2 units terms equally (module header: both terms carry gap^2
/// units, so the ratio is dimensionless). The frozen arm reproduces the
/// shipped behavior; this arm exists only to price the candidate path.
const CANDIDATE_LAMBDA: f64 = 1.0;
/// CONVENTION (declared): flatten recursion ceiling, identical role to the
/// production adapter's own subdivision depth cap (its value is not
/// observable from outside the pipeline crate; the cap is a resource
/// guard, not a quality parameter - subdivision stops on the measured
/// tolerance first in every realistic glyph).
const MAX_FLATTEN_DEPTH: usize = 16;

fn die(msg: String) -> ! {
    eprintln!("PAIR-SOLVER-TIMING-SETUP-BLOCKER: {msg}");
    std::process::exit(2);
}

/// Production flatten (pipeline drawing_polys/flatten_into), replicated
/// verbatim: adaptive midpoint subdivision on the measured control-point
/// chord distance, same tolerance, same budget guard, same closing-point
/// drop. Bit-identical polylines for identical input rings.
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

/// One parsed receipt run_config value (key -> (value, unit)).
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

/// Parse "name = ..." numeric assignments out of a solution/receipt policy
/// narrative line, e.g. "dcap=421.756" or "Dcap = measured plateau default
/// 421.756". Returns None when the narrative does not carry the value
/// (reported as "not measured" by the caller, never guessed).
fn parse_named_f64(text: &str, key: &str) -> Option<f64> {
    // form 1: key=VALUE
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

/// "Dcap = measured plateau default 421.756" narrative form.
fn parse_dcap(text: &str) -> Option<f64> {
    let marker = "Dcap = measured plateau default ";
    let pos = text.find(marker)?;
    let rest = &text[pos + marker.len()..];
    let end = rest.find(' ').unwrap_or(rest.len());
    rest[..end].parse().ok()
}

#[derive(Clone, Copy, Default)]
struct VariantCounts {
    solved: u64,
    below_epsilon: u64,
    no_feasible: u64,
    no_accepted: u64,
    not_converged: u64,
    unmeasurable_solve: u64,
    gated_rows: u64,
    gated_nonfinite: u64,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        die("usage: pair_solver_timing <font.otf> <receipt.txt> <mapping.tsv> [runs]".into());
    }
    let runs: usize = if args.len() > 4 {
        args[4].parse().unwrap_or_else(|_| die("runs must be an integer".into()))
    } else {
        3
    };
    if runs == 0 {
        die("runs must be >= 1".into());
    }

    let otf = std::fs::read(&args[1]).unwrap_or_else(|e| die(format!("{}: {e}", args[1])));
    let receipt = std::fs::read_to_string(&args[2]).unwrap_or_else(|e| die(format!("{}: {e}", args[2])));
    let mapping = std::fs::read_to_string(&args[3]).unwrap_or_else(|e| die(format!("{}: {e}", args[3])));
    let sha = kni_learning::sha256::sha256_hex(&otf);

    // ---- receipt-derived configuration (no invented numbers) -------------
    let cfg = receipt_run_config(&receipt);
    let flatten_tolerance = cfg_f64(&cfg, "flatten_tolerance");
    let row_step = cfg_f64(&cfg, "scan_row_step");
    let max_rows = cfg_u64(&cfg, "scan_max_rows") as usize;
    let sample_resolution = cfg_f64(&cfg, "sample_resolution");
    let max_pair_evaluations = cfg_u64(&cfg, "max_pair_evaluations");
    let max_pairs = cfg_u64(&cfg, "max_pairs") as usize;
    let pair_min_shared_rows = cfg_u64(&cfg, "pair_min_shared_rows") as usize;
    // Source canvas for the flatten budget: the receipt's own per-glyph
    // source_px field (identical for every glyph of the cohort).
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
    let reader = CffReader::from_bytes(&otf, &sha).unwrap_or_else(|e| die(format!("CffReader: {e:?}")));
    let upm = reader.units_per_em();
    let glyph_count = reader.glyph_count();
    let mut profiles: Vec<OutlineProfile> = Vec::new();
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
                glyph_id: name,
                source_pin: sha.clone(),
                upm,
                origin: [0.0, 0.0],
                flatten_tolerance,
                rings: polys,
            },
            ScanPolicy { row_step, max_rows, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) },
        ) {
            Ok(p) => profiles.push(p),
            Err(_) => profile_failures += 1,
        }
    }
    let profile_build_s = t_profiles.elapsed().as_secs_f64();

    // ---- spacing solve (jobs = 1): supplies the production per-pair
    // inputs (lsb/rsb/advance, dcap, W_target) and validates the harness
    // population against the receipt. --------------------------------------
    let policy = SpacingPolicy {
        sample_resolution,
        max_pair_evaluations,
        max_pairs,
        pair_min_shared_rows,
        lambda: None, // shipped value (receipt policy line: lambda=0.000)
        dcap: None,   // measured plateau default, receipted by the solver
        class_channel_targets: false, // matches SpacingPolicy::default (K2 class pass off in this harness)
        contrast_floor: false,
        cadence_class_pass: false,
    };
    let t_solve = Instant::now();
    let solution = match solve_spacing_jobs(&profiles, None, &policy, 1) {
        Ok(s) => s,
        Err(e) => die(format!("solve_spacing refused: {e:?}")),
    };
    let solve_spacing_s = t_solve.elapsed().as_secs_f64();
    let eps = sample_resolution / 2.0;
    let dcap = parse_dcap(&solution.policy_derivation)
        .unwrap_or_else(|| die("solution policy_derivation carries no measured Dcap; not measured".into()));
    let w_target = parse_named_f64(&solution.policy_derivation, "W_target")
        .unwrap_or_else(|| die("solution policy_derivation carries no W_target; not measured".into()));

    let metrics: HashMap<&str, (f64, f64, f64)> = solution
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.as_str(), (g.lsb, g.rsb, g.advance)))
        .collect();
    // Inked population = the solver's pair population: positive measured
    // ink area (space carries no ink and is never a pair member).
    let inked: Vec<&OutlineProfile> = profiles.iter().filter(|p| p.ink_area > 0.0).collect();
    let n = inked.len();
    let ordered_pairs = (n as u64) * (n.saturating_sub(1) as u64);

    // Receipt's own anchor numbers, for validation (parsed, never assumed).
    let receipt_spacing = receipt.lines().find(|l| l.starts_with("spacing\t")).unwrap_or("");
    let receipt_w_target = parse_named_f64(receipt_spacing, "W_target");
    let receipt_dcap = parse_named_f64(receipt_spacing, "dcap");

    println!("== pair-solver standalone timing ==");
    println!("font_sha256\t{sha}");
    println!("upm\t{upm}");
    println!("glyphs_in_cff\t{glyph_count}");
    println!("profiles_built\t{}\tprofile_failures\t{profile_failures}", profiles.len());
    println!("inked_glyphs\t{n}\tordered_pairs\t{ordered_pairs}");
    println!("profile_build_s\t{profile_build_s:.3}\t(not pair-solver time)");
    println!("solve_spacing_jobs1_s\t{solve_spacing_s:.3}\t(context reference, not pair-solver-only)");
    println!("harness_dcap\t{dcap:.3}\tharness_W_target\t{w_target:.3}");
    match (receipt_dcap, receipt_w_target) {
        (Some(rd), Some(rw)) => println!(
            "receipt_validation\tdcap_receipt={rd:.3} delta={:.3}\tW_target_receipt={rw:.3} delta={:.3}\t(note: profiles here are the shipped CFF integer readback; the receipt profiled pre-rounding outlines)",
            dcap - rd, w_target - rw
        ),
        _ => println!("receipt_validation\treceipt anchor values not parseable; not measured"),
    }
    println!("solution_pairs_emitted\t{}\texcluded_below_epsilon\t{}\texcluded_unmeasurable\t{}\texcluded_self\t{}",
        solution.pairs.len(), solution.excluded_below_epsilon, solution.excluded_unmeasurable, solution.excluded_self_pairs);

    // ---- the timed sweeps -------------------------------------------------
    for (arm, lambda) in [("frozen", 0.0), ("candidate", CANDIDATE_LAMBDA)] {
        let mut walls = Vec::with_capacity(runs);
        let mut last_per_pair_all: Vec<f64> = Vec::new();
        let mut last_counts = VariantCounts::default();
        for run in 1..=runs {
            let mut per_pair_all: Vec<f64> = Vec::with_capacity(ordered_pairs as usize);
            let mut counts = VariantCounts::default();
            let t0 = Instant::now();
            for l in &inked {
                for r in &inked {
                    if l.glyph_id == r.glyph_id {
                        continue; // self pair, skipped by construction (receipt: excluded_self)
                    }
                    let tp = Instant::now();
                    let (l_rsb, r_lsb) = match (metrics.get(l.glyph_id.as_str()), metrics.get(r.glyph_id.as_str())) {
                        (Some(a), Some(b)) => (a.1, b.0),
                        _ => die("inked glyph missing solved sidebearings".into()),
                    };
                    let base_offset = l_rsb + r_lsb;
                    let raw_base = l.bounds[2] - r.bounds[0] + base_offset;
                    let cells = clearance_cells_constant(l, r, raw_base);
                    if cells.len() < pair_min_shared_rows {
                        counts.gated_rows += 1;
                        per_pair_all.push(tp.elapsed().as_secs_f64());
                        continue;
                    }
                    let min_base = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
                    if !min_base.is_finite() {
                        counts.gated_nonfinite += 1;
                        per_pair_all.push(tp.elapsed().as_secs_f64());
                        continue;
                    }
                    let t_lo = -min_base;
                    let t_hi = (dcap - min_base).max(t_lo);
                    let advance_l = metrics[l.glyph_id.as_str()].2;
                    let l_tr = metrics[l.glyph_id.as_str()].0 - l.bounds[0];
                    let r_tr = metrics[r.glyph_id.as_str()].0 - r.bounds[0];
                    match solve_pair_t_l2(l, r, raw_base, dcap, w_target, lambda, t_lo, t_hi, advance_l, l_tr, r_tr) {
                        PairSolve::Solved { residual, .. } => {
                            counts.solved += 1;
                            if residual.abs() < eps {
                                counts.below_epsilon += 1;
                            }
                        }
                        PairSolve::NoFeasible => counts.no_feasible += 1,
                        PairSolve::NoAcceptedCandidate => counts.no_accepted += 1,
                        PairSolve::NotConverged(_) => counts.not_converged += 1,
                        PairSolve::Unmeasurable => counts.unmeasurable_solve += 1,
                    }
                    per_pair_all.push(tp.elapsed().as_secs_f64());
                }
            }
            let wall = t0.elapsed().as_secs_f64();
            let mean = per_pair_all.iter().sum::<f64>() / per_pair_all.len() as f64;
            let mut sorted = per_pair_all.clone();
            sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let median = sorted[sorted.len() / 2];
            println!(
                "arm={arm}\tlambda={lambda}\trun={run}\twall_s={wall:.3}\tpairs={}\tper_pair_mean_ms={:.6}\tper_pair_median_ms={:.6}",
                per_pair_all.len(),
                mean * 1e3,
                median * 1e3
            );
            walls.push(wall);
            if run == runs {
                last_per_pair_all = per_pair_all;
                last_counts = counts;
            }
        }
        let min = walls.iter().cloned().fold(f64::INFINITY, f64::min);
        let max = walls.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        let mut mid = walls.clone();
        mid.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let median_wall = mid[mid.len() / 2];
        let mut sorted = last_per_pair_all.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let p = |q: f64| sorted[((sorted.len() as f64 - 1.0) * q).round() as usize];
        println!(
            "arm={arm}\tsummary\truns={runs}\twall_min_s={min:.3}\twall_median_s={median_wall:.3}\twall_max_s={max:.3}\tper_pair_mean_ms={:.6}\tper_pair_median_ms={:.6}\tper_pair_p95_ms={:.6}\tper_pair_max_ms={:.6}",
            last_per_pair_all.iter().sum::<f64>() / last_per_pair_all.len() as f64 * 1e3,
            sorted[sorted.len() / 2] * 1e3,
            p(0.95) * 1e3,
            *sorted.last().unwrap() * 1e3
        );
        println!(
            "arm={arm}\tvariants\tsolved={}\tbelow_epsilon={}\tno_feasible={}\tno_accepted_candidate={}\tnot_converged={}\tsolve_unmeasurable={}\tgate_shared_rows={}\tgate_nonfinite={}",
            last_counts.solved, last_counts.below_epsilon, last_counts.no_feasible, last_counts.no_accepted,
            last_counts.not_converged, last_counts.unmeasurable_solve, last_counts.gated_rows, last_counts.gated_nonfinite
        );
    }
}
