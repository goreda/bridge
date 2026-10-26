//! SOLVER probe (analysis harness, not production): rasterized circle arcs on
//! the acquisition lattice, fitted through the public pipeline entry
//! (fit_captured_with_fallback_events) under the legacy fixed policy
//! (squared_error 0.25, refits 8) vs the derived source-quantization policy
//! ((K/2)^2 = 1.0 at K=2). Reports typed fallback reasons, final Line-run
//! length histogram (grinding regime), and fit_run-level solvability of
//! forced-axis vs tilted tangents. Prints TSV.
use kni_core::capture::CapturedRing;
use kni_core::capture_fit::{fit_captured_with_fallback_events, FallbackReason};
use kni_core::cubic_fit::{fit_run, FitOutcome, FitPolicy};
use kni_core::reference_slice::{Point, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn qz(v: f64, lat: f64) -> f64 { (v / lat).round() * lat }

/// Tracer-like ring: uniform arc-step samples of a circle quantized to the
/// acquisition lattice. `points` mimics the RDP output (spacing set by the
/// rdp sagitta), `raw` the denser traced chain.
fn circle_ring(cx: f64, cy: f64, r: f64, rdp_eps: f64, lat: f64, hole: bool) -> CapturedRing {
    // RDP keeps vertices whose sagitta ~ rdp_eps: step s = sqrt(8*r*eps).
    let s = (8.0 * r * rdp_eps).sqrt().max(1.0);
    let n = ((2.0 * std::f64::consts::PI * r / s).round() as usize).max(8);
    let points: Vec<Point> = (0..n)
        .map(|i| {
            let t = 2.0 * std::f64::consts::PI * (i as f64) / (n as f64);
            p(qz(cx + r * t.cos(), lat), qz(cy + r * t.sin(), lat))
        })
        .collect();
    let sraw = 0.5f64;
    let nraw = ((2.0 * std::f64::consts::PI * r / sraw).round() as usize).max(16);
    let raw: Vec<Point> = (0..nraw)
        .map(|i| {
            let t = 2.0 * std::f64::consts::PI * (i as f64) / (nraw as f64);
            p(qz(cx + r * t.cos(), lat), qz(cy + r * t.sin(), lat))
        })
        .collect();
    CapturedRing { points, corners: vec![], raw, hole }
}

/// Ring whose upper half is a circle arc between two corners; the lower half
/// is the chord back. Stands in for a rounded cap/bracket between corners.
fn cap_ring(cx: f64, cy: f64, r: f64, sweep_deg: f64, rdp_eps: f64, lat: f64) -> CapturedRing {
    let a0 = (90.0 - sweep_deg / 2.0).to_radians();
    let a1 = (90.0 + sweep_deg / 2.0).to_radians();
    let s = (8.0 * r * rdp_eps).sqrt().max(1.0);
    let n = ((r * (a1 - a0) / s).round() as usize).max(3);
    let mut points: Vec<Point> = (0..=n)
        .map(|i| {
            let t = a0 + (a1 - a0) * (i as f64) / (n as f64);
            p(qz(cx + r * t.cos(), lat), qz(cy + r * t.sin(), lat))
        })
        .collect();
    let corners = vec![0usize, points.len() - 1];
    // close the ring along the chord (1 intermediate point so raw/RDP differ)
    let e = *points.last().unwrap();
    let s0 = points[0];
    points.push(p(qz((e.x + s0.x) / 2.0, lat), qz((e.y + s0.y) / 2.0, lat)));
    let mut raw = points.clone();
    // densify raw on the arc
    let mut raw_dense: Vec<Point> = vec![];
    for w in raw.windows(2) {
        raw_dense.push(w[0]);
        raw_dense.push(p(qz((w[0].x + w[1].x) / 2.0, lat), qz((w[0].y + w[1].y) / 2.0, lat)));
    }
    raw_dense.push(*raw.last().unwrap());
    raw = raw_dense;
    CapturedRing { points, corners, raw, hole: false }
}

struct RingStats { fev: [usize; 3], spans: usize, cubics: usize, lines: usize, max_lrun_fu: f64, lrun_le5_share: f64, lrun_count: usize, max_radial: f64 }

fn analyze(ring: &kni_core::reference_slice::ReferenceRing, fev: &[kni_core::capture_fit::FallbackEvent], center: Point, r_fu: f64) -> RingStats {
    let mut c = [0usize; 3];
    for e in fev {
        match e.reason {
            FallbackReason::SplitUnresolved => c[0] += 1,
            FallbackReason::DepthLimit | FallbackReason::SubGridSpan => c[1] += 1,
            FallbackReason::DegenerateTangents | FallbackReason::AreaCollapseRestored => c[2] += 1,
        }
    }
    let mut cubics = 0usize;
    let mut lines = 0usize;
    // consecutive Line runs, length in fu along the polyline
    let mut runs: Vec<f64> = vec![];
    let mut cur = 0.0f64;
    let mut prev = ring.start;
    let mut max_radial = 0.0f64;
    let mut flush = |cur: &mut f64| { if *cur > 0.0 { runs.push(*cur); *cur = 0.0; } };
    for sp in &ring.spans {
        match sp {
            Span::Line { end } => { cur += (end.x - prev.x).hypot(end.y - prev.y); lines += 1; prev = *end; }
            Span::Cubic { control_one, control_two, end } => {
                flush(&mut cur);
                cubics += 1;
                for i in 0..=32 {
                    let t = i as f64 / 32.0;
                    let v = 1.0 - t;
                    let b = [v*v*v, 3.0*t*v*v, 3.0*t*t*v, t*t*t];
                    let x = b[0]*prev.x + b[1]*control_one.x + b[2]*control_two.x + b[3]*end.x;
                    let y = b[0]*prev.y + b[1]*control_one.y + b[2]*control_two.y + b[3]*end.y;
                    max_radial = max_radial.max(((x - center.x).hypot(y - center.y) - r_fu).abs());
                }
                prev = *end;
            }
        }
    }
    flush(&mut cur);
    let le5 = runs.iter().filter(|&&l| l <= 5.0).count();
    RingStats {
        fev: c, spans: ring.spans.len(), cubics, lines,
        max_lrun_fu: runs.iter().cloned().fold(0.0, f64::max),
        lrun_le5_share: if runs.is_empty() { 0.0 } else { le5 as f64 / runs.len() as f64 },
        lrun_count: runs.len(),
        max_radial,
    }
}

// ---- fit_run-level solvability probes ----

/// quarter arc samples (R fu, lattice fu), tangents tilted by `tilt_rad` from exact axis.
fn quarter(r: f64, lat: f64, tilt_rad: f64, policy: &FitPolicy) -> (f64, usize, &'static str) {
    let n = 16usize;
    let pts: Vec<Point> = (0..=n)
        .map(|i| {
            let t = std::f64::consts::FRAC_PI_2 * (i as f64) / (n as f64);
            p(qz(r * t.cos(), lat), qz(r * t.sin(), lat))
        })
        .collect();
    // exact axis tangents at ends: (0,1) at t=0 -> ( -sin0, cos0 ) = (0,1); at t=90: (-1,0)
    let rot = |x: f64, y: f64, a: f64| p(x * a.cos() - y * a.sin(), x * a.sin() + y * a.cos());
    let lt = rot(0.0, 1.0, tilt_rad);
    let rt = rot(1.0, 0.0, tilt_rad);
    let refits_used = 0usize;
    match fit_run(&pts, lt, rt, policy) {
        FitOutcome::Fitted { max_squared_error, .. } => (max_squared_error, refits_used, "Fitted"),
        FitOutcome::SplitUnresolved { .. } => (f64::NAN, 0, "SplitUnresolved"),
        FitOutcome::InvalidInput => (f64::NAN, 0, "InvalidInput"),
    }
}

// ---- parameterization A/B: local clone of cubic_fit with switchable initial u ----
mod ab {
    use super::p;
    use kni_core::reference_slice::Point;
    fn add(a: Point, b: Point) -> Point { p(a.x + b.x, a.y + b.y) }
    fn sub(a: Point, b: Point) -> Point { p(a.x - b.x, a.y - b.y) }
    fn sc(a: Point, k: f64) -> Point { p(a.x * k, a.y * k) }
    fn dot(a: Point, b: Point) -> f64 { a.x * b.x + a.y * b.y }
    fn basis(t: f64) -> [f64; 4] { let v = 1.0 - t; [v*v*v, 3.0*t*v*v, 3.0*t*t*v, t*t*t] }
    fn eval(q: &[Point; 4], t: f64) -> Point { let b = basis(t); (0..4).fold(p(0.0, 0.0), |acc, i| add(acc, sc(q[i], b[i]))) }
    fn solve(points: &[Point], u: &[f64], left: Point, right: Point) -> Option<[Point; 4]> {
        let p0 = points[0]; let p3 = *points.last()?;
        let (mut c00, mut c01, mut c11, mut x0, mut x1) = (0.0, 0.0, 0.0, 0.0, 0.0);
        for (pt, t) in points.iter().zip(u) {
            let b = basis(*t);
            let a0 = sc(left, b[1]); let a1 = sc(right, b[2]);
            let r = sub(*pt, add(sc(p0, b[0] + b[1]), sc(p3, b[2] + b[3])));
            c00 += dot(a0, a0); c01 += dot(a0, a1); c11 += dot(a1, a1);
            x0 += dot(a0, r); x1 += dot(a1, r);
        }
        let det = c00 * c11 - c01 * c01;
        if !det.is_finite() || det <= 0.0 { return None; }
        let a = (x0 * c11 - x1 * c01) / det;
        let b = (c00 * x1 - c01 * x0) / det;
        if !a.is_finite() || !b.is_finite() || a <= 0.0 || b <= 0.0 { return None; }
        Some([p0, add(p0, sc(left, a)), add(p3, sc(right, b)), p3])
    }
    fn maxerr(points: &[Point], u: &[f64], q: &[Point; 4]) -> f64 {
        let mut m: f64 = 0.0;
        for i in 1..points.len() - 1 {
            let d = sub(eval(q, u[i]), points[i]);
            m = m.max(dot(d, d));
        }
        m
    }
    fn deriv(q: &[Point; 4], t: f64) -> (Point, Point) {
        let v = 1.0 - t;
        let a = sc(sub(q[1], q[0]), 3.0); let b = sc(sub(q[2], q[1]), 3.0); let c = sc(sub(q[3], q[2]), 3.0);
        (add(add(sc(a, v * v), sc(b, 2.0 * v * t)), sc(c, t * t)), add(sc(sub(b, a), 2.0 * v), sc(sub(c, b), 2.0 * t)))
    }
    fn newton(q: &[Point; 4], pt: Point, t: f64) -> Option<f64> {
        let at = eval(q, t); let (d1, d2) = deriv(q, t); let r = sub(at, pt);
        let den = dot(d1, d1) + dot(r, d2);
        if !den.is_finite() || den == 0.0 { return None; }
        let n = t - dot(r, d1) / den;
        if !n.is_finite() || !(0.0..=1.0).contains(&n) { None } else { Some(n) }
    }
    /// Returns (initial max sq err, converged max sq err, refits used or None if unresolved)
    pub fn fit_ab(points: &[Point], left: Point, right: Point, tol: f64, budget: usize, centripetal: bool) -> (f64, f64, Option<usize>) {
        let mut u = vec![0.0f64];
        for i in 1..points.len() {
            let d = sub(points[i], points[i - 1]);
            let inc = d.x.hypot(d.y);
            let inc = if centripetal { inc.sqrt() } else { inc };
            u.push(u[i - 1] + inc);
        }
        let total = *u.last().unwrap();
        if total == 0.0 { return (f64::NAN, f64::NAN, None); }
        for t in u.iter_mut() { *t /= total; }
        let lu = |v: &Point| { let n = v.x.hypot(v.y); p(v.x / n, v.y / n) };
        let (left, right) = (lu(&left), lu(&right));
        let mut q = match solve(points, &u, left, right) { Some(q) => q, None => return (f64::NAN, f64::NAN, None) };
        let mut max = maxerr(points, &u, &q);
        let initial = max;
        for att in 0..=budget {
            if max <= tol { return (initial, max, Some(att)); }
            if att == budget { break; }
            let mut proposed = u.clone();
            let mut ok = true;
            for i in 1..points.len() - 1 {
                match newton(&q, points[i], u[i]) { Some(t) => proposed[i] = t, None => { ok = false; break; } }
            }
            if !ok || proposed.windows(2).any(|w| w[0] > w[1]) { break; }
            let Some(nq) = solve(points, &proposed, left, right) else { break; };
            u = proposed; q = nq; max = maxerr(points, &u, &q);
        }
        (initial, max, if max <= tol { Some(budget) } else { None })
    }
}

fn main() {
    let k = 2.0f64; // Lÿno declared scale (fu per px)
    let p_fixed = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let p_derived = FitPolicy { squared_error: (k / 2.0) * (k / 2.0), max_refits: 8 };
    println!("# A. rasterized circle rings through fit_captured (scale K=2, lattice 0.5px)");
    println!("scenario\tpolicy\tsplit_unresolved\tdepth_limit\tdegen_tangents\tspans\tcubics\tlines\tlruns\tmax_lrun_fu\tlrun_le5_share\tmax_radial_fu");
    for r in [8.0f64, 16.0, 32.0, 64.0, 128.0] {
        let ring = circle_ring(500.0, 500.0, r, 0.25, 0.5, false);
        for (name, pol) in [("fixed0.25", &p_fixed), ("derivedK2", &p_derived)] {
            let (out, _count, _fb, _drop, fev) = fit_captured_with_fallback_events(&[ring.clone()], k, pol);
            if let Some(rr) = out.first() {
                let st = analyze(rr, &fev, p(500.0 * k, 500.0 * k), r * k);
                println!("circle_r{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.2}\t{:.3}\t{:.3}",
                    r, name, st.fev[0], st.fev[1], st.fev[2], st.spans, st.cubics, st.lines, st.lrun_count, st.max_lrun_fu, st.lrun_le5_share, st.max_radial);
            } else {
                println!("circle_r{}\t{}\tNO_OUTPUT_RING", r, name);
            }
        }
    }
    println!("# B. cap arcs between corners (rounded cap / bracket stand-in)");
    for (r, sweep) in [(32.0f64, 90.0f64), (32.0, 180.0), (64.0, 180.0), (16.0, 120.0)] {
        let ring = cap_ring(500.0, 500.0, r, sweep, 0.25, 0.5);
        for (name, pol) in [("fixed0.25", &p_fixed), ("derivedK2", &p_derived)] {
            let (out, _c, _f, _d, fev) = fit_captured_with_fallback_events(&[ring.clone()], k, pol);
            if let Some(rr) = out.first() {
                let st = analyze(rr, &fev, p(500.0 * k, 500.0 * k), r * k);
                println!("cap_r{}_s{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.2}\t{:.3}\t{:.3}",
                    r, sweep, name, st.fev[0], st.fev[1], st.fev[2], st.spans, st.cubics, st.lines, st.lrun_count, st.max_lrun_fu, st.lrun_le5_share, st.max_radial);
            } else {
                println!("cap_r{}_s{}\t{}\tNO_OUTPUT_RING", r, sweep, name);
            }
        }
    }
    println!("# C. fit_run solvability: quarter arc, forced tangent tilt delta (off-extremum node)");
    println!("R_fu\ttol\ttilt_deg\toutcome\tmax_sq_err");
    for r_fu in [40.0f64, 80.0, 160.0] {
        for (tolname, tol) in [("0.25", 0.25f64), ("1.0", 1.0)] {
            for tilt in [0.0f64, 0.5, 1.0, 2.0, 5.0] {
                let pol = FitPolicy { squared_error: tol, max_refits: 8 };
                let (mse, _u, outc) = quarter(r_fu, 1.0, tilt.to_radians(), &pol);
                println!("{}\t{}\t{}\t{}\t{}", r_fu, tolname, tilt, outc, if mse.is_nan() { "-".into() } else { format!("{:.4}", mse) });
            }
        }
    }
    println!("# D. parameterization A/B: chord-length vs centripetal (clone of cubic_fit)");
    println!("shape\ttol\tscheme\tinit_mse\tfinal_mse\trefits");
    // high-curvature-variation arc: ellipse a=160, b=20 fu, quarter, 24 samples on 1fu lattice
    let ell: Vec<Point> = (0..=24)
        .map(|i| {
            let t = std::f64::consts::FRAC_PI_2 * (i as f64) / 24.0;
            p(qz(160.0 * t.cos(), 1.0), qz(20.0 * t.sin(), 1.0))
        })
        .collect();
    let lt = p(0.0, 1.0); let rt = p(1.0, 0.0);
    for (tolname, tol) in [("0.25", 0.25f64), ("1.0", 1.0)] {
        for (sname, centr) in [("chord", false), ("centripetal", true)] {
            let (i0, f0, rf) = ab::fit_ab(&ell, lt, rt, tol, 8, centr);
            println!("ellipse160x20\t{}\t{}\t{:.4}\t{:.4}\t{}", tolname, sname, i0, f0, rf.map(|x| x.to_string()).unwrap_or("UNRESOLVED".into()));
        }
    }
    // tight circle arc r=12fu (high curvature), half circle
    let tight: Vec<Point> = (0..=24)
        .map(|i| {
            let t = std::f64::consts::PI * (i as f64) / 24.0;
            p(qz(12.0 * t.cos(), 1.0), qz(12.0 * t.sin(), 1.0))
        })
        .collect();
    for (tolname, tol) in [("0.25", 0.25f64), ("1.0", 1.0)] {
        for (sname, centr) in [("chord", false), ("centripetal", true)] {
            let (i0, f0, rf) = ab::fit_ab(&tight, p(0.0, 1.0), p(0.0, 1.0), tol, 8, centr);
            println!("circleR12_half\t{}\t{}\t{:.4}\t{:.4}\t{}", tolname, sname, i0, f0, rf.map(|x| x.to_string()).unwrap_or("UNRESOLVED".into()));
        }
    }
}
