// INSTRUMENTATION ONLY (working copy, engine sources untouched): dump capture
// and fit decisions for ring 2 (stem+tail) of the canonical g-tail input.
use kni_core::capture::capture_png;
use kni_core::capture_fit::plausible;
use kni_core::cubic_fit::{adjacent_chord_tangents, fit_run, FitOutcome, FitPolicy};
use kni_core::reference_slice::Point;

fn dist_pt_seg(p: Point, a: Point, b: Point) -> f64 {
    let abx = b.x - a.x; let aby = b.y - a.y;
    let l2 = abx*abx + aby*aby;
    if l2 == 0.0 { return (p.x-a.x).hypot(p.y-a.y); }
    let mut t = ((p.x-a.x)*abx + (p.y-a.y)*aby) / l2;
    t = t.clamp(0.0, 1.0);
    (p.x-(a.x+t*abx)).hypot(p.y-(a.y+t*aby))
}
fn cubic_pt(q: &[Point;4], t: f64) -> Point {
    let mt = 1.0-t;
    let b = [mt*mt*mt, 3.*t*mt*mt, 3.*t*t*mt, t*t*t];
    let mut p = Point{x:0.,y:0.};
    for i in 0..4 { p.x += b[i]*q[i].x; p.y += b[i]*q[i].y; }
    p
}
// max excursion of cubic (dense 256) beyond the arc sample polyline (true-ish Hausdorff one-way)
fn excursion(q: &[Point;4], samples: &[Point]) -> f64 {
    let mut worst = 0.0f64;
    for k in 0..=256 {
        let p = cubic_pt(q, k as f64/256.0);
        let mut best = f64::INFINITY;
        for w in 0..samples.len()-1 {
            best = best.min(dist_pt_seg(p, samples[w], samples[w+1]));
        }
        worst = worst.max(best);
    }
    worst
}
// true distance from each interior sample to the dense cubic (what error() approximates at u[i])
fn sample_true_dist(q: &[Point;4], samples: &[Point]) -> f64 {
    let dense: Vec<Point> = (0..=256).map(|k| cubic_pt(q, k as f64/256.0)).collect();
    let mut worst = 0.0f64;
    for p in samples.iter().skip(1).take(samples.len().saturating_sub(2)) {
        let mut best = f64::INFINITY;
        for w in 0..dense.len()-1 { best = best.min(dist_pt_seg(*p, dense[w], dense[w+1])); }
        worst = worst.max(best);
    }
    worst
}

fn fit_log(pts: &[Point], policy: &FitPolicy, depth: usize, path: &str, spans_out: &mut Vec<(String, [Point;4], f64, f64)>) {
    if pts.len() == 2 { println!("{} [depth {}] LINE 2pt", path, depth); return; }
    if depth > 12 { println!("{} [depth {}] POLYLINE FALLBACK", path, depth); return; }
    let (lt, rt) = match adjacent_chord_tangents(pts) { Some(t)=>t, None=>{println!("{} degenerate", path); return;} };
    match fit_run(pts, lt, rt, policy) {
        FitOutcome::Fitted{controls, max_squared_error, ..} if plausible(pts, &controls) => {
            let exc = excursion(&controls, pts);
            let std_ = sample_true_dist(&controls, pts);
            println!("{} [depth {}] FITTED n={} mse={:.6} true_sample_dist={:.4} excursion={:.4} ctrl=({:.2},{:.2}) ({:.2},{:.2}) ({:.2},{:.2}) ({:.2},{:.2})",
                path, depth, pts.len(), max_squared_error, std_, exc,
                controls[0].x, controls[0].y, controls[1].x, controls[1].y,
                controls[2].x, controls[2].y, controls[3].x, controls[3].y);
            spans_out.push((path.to_string(), controls, max_squared_error, exc));
        }
        other => {
            let tag = match &other { FitOutcome::Fitted{..} => "REJECTED-plausibility", FitOutcome::SplitUnresolved{..} => "SPLIT-unresolved", FitOutcome::InvalidInput => "INVALID" };
            if let FitOutcome::Fitted{controls, max_squared_error, ..} = &other {
                println!("{} [depth {}] {} n={} mse={:.6} ctrl=({:.2},{:.2}) ({:.2},{:.2})", path, depth, tag, pts.len(), max_squared_error, controls[1].x, controls[1].y, controls[2].x, controls[2].y);
            } else {
                println!("{} [depth {}] {} n={}", path, depth, tag, pts.len());
            }
            let mid = pts.len()/2;
            fit_log(&pts[..=mid], policy, depth+1, &format!("{}L", path), spans_out);
            fit_log(&pts[mid..], policy, depth+1, &format!("{}R", path), spans_out);
        }
    }
}

fn main() {
    let png = std::fs::read(std::env::args().nth(1).unwrap()).unwrap();
    let mc = capture_png(&png, 0.5).unwrap();
    let min = mc.rings.iter().flat_map(|r| r.points.iter()).map(|p| p.y).fold(f64::INFINITY, f64::min);
    let max = mc.rings.iter().flat_map(|r| r.points.iter()).map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
    let scale = 700.0/(max-min);
    println!("scale={:.17} content_h_px={:.4}", scale, max-min);
    for (ri, r) in mc.rings.iter().enumerate() {
        println!("ring{}: n={} hole={} corners={:?}", ri, r.points.len(), r.hole, r.corners);
    }
    let r = &mc.rings[2];
    for (ri2,rr) in mc.rings.iter().enumerate() { for (i,p) in rr.points.iter().enumerate() { println!("ring{}.pt[{}]={:.4},{:.4}", ri2, i, p.x, p.y); } }
    // replicate fit_ring arc split (exact copy of engine logic)
    let mut pts: Vec<Point> = r.points.iter().map(|p| Point{x:p.x*scale, y:p.y*scale}).collect();
    let n = pts.len();
    let corners = r.corners.clone();
    let mut arcs: Vec<Vec<Point>> = vec![];
    if corners.is_empty() { let mut c = pts.clone(); c.push(pts[0]); arcs.push(c); }
    else {
        let k0 = corners[0];
        pts.rotate_left(k0);
        let cs: Vec<usize> = corners.iter().map(|&c| (c + n - k0) % n).collect();
        for w in 0..cs.len() {
            let a = cs[w]; let b = if w+1 < cs.len() { cs[w+1] } else { n };
            let mut seg: Vec<Point> = pts[a..=b.min(n-1)].to_vec();
            if b == n { seg.push(pts[0]); }
            arcs.push(seg);
        }
    }
    let mut m: Vec<Vec<Point>> = vec![];
    for seg in arcs.into_iter() {
        if let Some(last) = m.last_mut() {
            if last.len() < 3 { let mut p2 = last.clone(); p2.extend(seg[1..].iter().cloned()); *last = p2; continue; }
        }
        m.push(seg);
    }
    if m.len() > 1 && m.last().unwrap().len() < 3 {
        let last = m.pop().unwrap();
        let mut p2 = last; p2.extend(m[0][1..].iter().cloned()); m[0] = p2;
    }
    println!("== arcs (scaled font units) ==");
    for (ai, a) in m.iter().enumerate() {
        println!("arc{}: n={} first={:.2},{:.2} last={:.2},{:.2}", ai, a.len(), a[0].x, a[0].y, a[a.len()-1].x, a[a.len()-1].y);
        for (pi,p) in a.iter().enumerate() { println!("  arc{}.pt[{}]={:.4},{:.4}", ai, pi, p.x, p.y); }
    }
    let policy = FitPolicy{squared_error: 0.1, max_refits: 6};
    let mut spans_out = vec![];
    for (ai, a) in m.iter().enumerate() {
        println!("== fit arc{} ==", ai);
        fit_log(a, &policy, 0, &format!("a{}", ai), &mut spans_out);
    }
    println!("== accepted cubics: {} ==", spans_out.len());
}
