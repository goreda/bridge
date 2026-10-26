use kni_core::capture::capture_png;
use kni_core::reference_slice::Point;
const W: usize = 3; const SWING: f64 = 2.0;
fn extrema(pts: &[Point]) -> Vec<(usize, char)> {
    let n = pts.len();
    if n < 2*W+3 { return vec![]; }
    let mut out = vec![];
    for i in W..n-W {
        for ax in 0..2 {
            let (pl, pr) = if ax==0 {(pts[i].x-pts[i-W].x, pts[i+W].x-pts[i].x)} else {(pts[i].y-pts[i-W].y, pts[i+W].y-pts[i].y)};
            if pl==0.0||pr==0.0||pl.signum()==pr.signum() {continue;}
            if pl.abs().min(pr.abs()) < SWING {continue;}
            out.push((i, if ax==0 {'x'} else {'y'}));
        }
    }
    out
}
fn main(){
    let inp = std::env::args().nth(1).unwrap();
    let scale: f64 = std::env::args().nth(2).unwrap().parse().unwrap();
    let png = std::fs::read(&inp).unwrap();
    let mc = capture_png(&png, 0.5).unwrap();
    for (ri, r) in mc.rings.iter().enumerate() {
        let pts: Vec<Point> = r.points.iter().map(|p| Point{x:p.x*scale, y:p.y*scale}).collect();
        let n = pts.len();
        let mut arcs: Vec<Vec<Point>> = vec![];
        if r.corners.is_empty() { let mut c = pts.clone(); c.push(pts[0]); arcs.push(c); }
        else {
            let k0 = r.corners[0];
            let mut p2 = pts.clone(); p2.rotate_left(k0);
            let cs: Vec<usize> = r.corners.iter().map(|&c| (c+n-k0)%n).collect();
            for w in 0..cs.len() {
                let a = cs[w]; let b = if w+1<cs.len() {cs[w+1]} else {n};
                let mut seg: Vec<Point> = p2[a..=b.min(n-1)].to_vec();
                if b==n { seg.push(p2[0]); }
                arcs.push(seg);
            }
        }
        for (ai, arc) in arcs.iter().enumerate() {
            let ex = extrema(arc);
            if !ex.is_empty() {
                println!("ring {} arc {} len {}: extrema {:?}", ri, ai, arc.len(), ex);
            }
        }
    }
}
