use kni_core::capture::capture_gray;
use kni_core::capture_fit::fit_captured;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::Span;
fn main() {
    let (w, h) = (40usize, 40usize);
    let mut g = vec![255u8; w * h];
    for y in 0..h { for x in 0..w {
        let (fx, fy) = (x as f64 + 0.5, y as f64 + 0.5);
        let r = ((fx - 20.0).powi(2) + (fy - 20.0).powi(2)).sqrt();
        if r < 13.0 { g[y * w + x] = 0; }
    }}
    let c = capture_gray(w, h, &g, 0.25).unwrap();
    let p = FitPolicy { squared_error: 0.25, max_refits: 8 };
    let (fl, count, fb, dropped) = fit_captured(&c.rings, 1.0, &p);
    println!("rings {} spans_total {} fb {} dropped {}", fl.len(), count, fb, dropped);
    for r in &fl {
        println!("start {:?}", r.start);
        for s in &r.spans {
            match s { Span::Line { end } => println!("  L -> {:?}", end), Span::Cubic { control_one, control_two, end } => println!("  C c1 {:?} c2 {:?} -> {:?}", control_one, control_two, end) }
        }
    }
}
