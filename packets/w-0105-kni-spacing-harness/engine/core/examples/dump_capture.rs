// Pre-fit capture ring dump (diagnostic): capture_png rings straight to a
// pixel-space SVG, y-down, bbox-relative (capture contract: origin at
// content bbox min, y-up -> flip to y-down for SVG).
use kni_core::capture::capture_png;
use std::fmt::Write;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let png = std::fs::read(&args[1]).unwrap();
    let mc = capture_png(&png, 0.5).unwrap();
    let mut mx = 0.0f64; let mut my = 0.0f64;
    for r in &mc.rings { for p in &r.points { mx = mx.max(p.x); my = my.max(p.y); } }
    let mut d = String::new();
    for r in &mc.rings {
        let mut first = true;
        for p in &r.points {
            let y = my - p.y; // y-up (bbox) -> y-down crop coords
            if first { let _ = write!(d, "M {:.2} {:.2} ", p.x, y); first = false; }
            else { let _ = write!(d, "L {:.2} {:.2} ", p.x, y); }
        }
        let _ = write!(d, "Z ");
    }
    std::fs::write(&args[2], format!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {:.0} {:.0}\"><path d=\"{}\"/></svg>", mx + 1.0, my + 1.0, d)).unwrap();
    println!("rings={} w={} h={} bbox={:.0}x{:.0}", mc.rings.len(), mc.width, mc.height, mx + 1.0, my + 1.0);
}
