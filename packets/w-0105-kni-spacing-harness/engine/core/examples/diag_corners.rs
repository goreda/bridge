// P2 probe: per-corner arc interior-point counts on the simplified rings.
use kni_core::capture::capture_png;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let png = std::fs::read(&args[1]).unwrap();
    let mc = capture_png(&png, 0.5).unwrap();
    for (ri, r) in mc.rings.iter().enumerate() {
        let n = r.points.len();
        println!("ring{}: n={} corners={:?}", ri, n, r.corners);
        let cs = &r.corners;
        for w in 0..cs.len() {
            let a = cs[w];
            let b = if w + 1 < cs.len() { cs[w + 1] } else { cs[0] + n };
            let pa = r.points[a % n]; let pb = r.points[b % n];
            println!("  corner {} (idx {}) -> next: interior={} chord={:.1}px",
                w, a % n, b - a - 1, (pb.x - pa.x).hypot(pb.y - pa.y));
        }
    }
}
