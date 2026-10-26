// D2 diagnostic: for each fitted Cubic span on a source, report the arc's
// chord deviation, best single-breakpoint turn angle and two-line residual.
use kni_core::capture::capture_png;
use kni_core::reference_slice::Point;

fn dev_from_chord(pts: &[Point]) -> (f64, usize) {
    let a = pts[0]; let b = pts[pts.len()-1];
    let abx = b.x-a.x; let aby = b.y-a.y; let l = abx.hypot(aby);
    if l == 0.0 { return (0.0, 0); }
    let mut md = 0.0; let mut mi = 0;
    for (i,p) in pts[1..pts.len()-1].iter().enumerate() {
        let d = (abx*(p.y-a.y)-aby*(p.x-a.x)).abs()/l;
        if d > md { md = d; mi = i+1; }
    }
    (md, mi)
}

fn main() {
    let inp = std::env::args().nth(1).unwrap();
    let png = std::fs::read(&inp).unwrap();
    let mc = capture_png(&png, 0.5).unwrap();
    // replicate fit_ring's arc pipeline but inspect cubic choices: instead,
    // simpler: for each ring, for each arc between corners, run the same
    // recursive logic copy with reporting. We approximate: report per arc.
    let mut n_arcs = 0; let mut curved_like = 0; let mut two_line = 0;
    for r in &mc.rings {
        let n = r.points.len();
        let mut arcs: Vec<Vec<Point>> = vec![];
        if r.corners.is_empty() { let mut c = r.points.clone(); c.push(r.points[0]); arcs.push(c); }
        else {
            let k0 = r.corners[0];
            let mut pts = r.points.clone(); pts.rotate_left(k0);
            let cs: Vec<usize> = r.corners.iter().map(|&c| (c+n-k0)%n).collect();
            for w in 0..cs.len() {
                let a = cs[w]; let b = if w+1<cs.len() { cs[w+1] } else { n };
                let mut seg: Vec<Point> = pts[a..=b.min(n-1)].to_vec();
                if b == n { seg.push(pts[0]); }
                arcs.push(seg);
            }
        }
        for arc in arcs {
            if arc.len() < 3 { continue; }
            let (d, _mi) = dev_from_chord(&arc);
            if d <= 1.0 { continue; } // line-first would accept
            n_arcs += 1;
            if arc.len() < 5 { println!("arc len={:4} chorddev={:5.2} (short)", arc.len(), d); n_arcs += 1; curved_like += 1; continue; }
            // best breakpoint: minimize max(dev(left), dev(right))
            let mut best = f64::INFINITY; let mut bk = 2;
            for k in 2..arc.len()-2 {
                let dl = dev_from_chord(&arc[..=k]).0;
                let dr = dev_from_chord(&arc[k..]).0;
                let m = dl.max(dr);
                if m < best { best = m; bk = k; }
            }
            // turn angle at best breakpoint
            let a = arc[bk-1]; let b = arc[bk]; let c = arc[bk+1];
            let v1 = (b.x-a.x, b.y-a.y); let v2 = (c.x-b.x, c.y-b.y);
            let l1 = v1.0.hypot(v1.1); let l2 = v2.0.hypot(v2.1);
            let _cos = if l1>0.0 && l2>0.0 { ((v1.0*v2.0+v1.1*v2.1)/(l1*l2)).clamp(-1.0,1.0) } else { 1.0 };
            let bk = if bk>=arc.len()-1 {arc.len()-2} else {bk}; let a = arc[bk-1]; let b = arc[bk]; let c = arc[bk+1]; let v1=(b.x-a.x,b.y-a.y); let v2=(c.x-b.x,c.y-b.y); let l1=v1.0.hypot(v1.1); let l2=v2.0.hypot(v2.1); let cos = if l1>0.0&&l2>0.0 {((v1.0*v2.0+v1.1*v2.1)/(l1*l2)).clamp(-1.,1.)} else {1.}; let deg = cos.acos().to_degrees();
            if best <= 1.0 { two_line += 1; } else { curved_like += 1; }
            println!("arc len={:4} chorddev={:5.2} best2line={:5.2}@{} turn={:5.1}deg -> {}",
                arc.len(), d, best, bk, deg, if best<=1.0 {"TWO-LINE"} else {"CURVE-LIKE"});
        }
    }
    println!("SUMMARY: {} non-line arcs, {} two-line-decomposable, {} curve-like", n_arcs, two_line, curved_like);
}
