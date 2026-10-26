//! Diagnostic: dump fitted ring structure for emitted_geometry_refine fixtures.
use kni_core::capture::capture_gray;
use kni_core::capture_fit::{fit_captured, round_and_clean_ring};
use kni_core::cubic_fit::FitPolicy;
fn main() {
    for (idx, (w, h, f)) in [(40usize, 40usize, 0u8), (48, 36, 1), (48, 48, 2), (40, 40, 3)].into_iter().enumerate() {
        let mut g = vec![255u8; w * h];
        for y in 0..h { for x in 0..w {
            let (fx, fy) = (x as f64 + 0.5, y as f64 + 0.5);
            let (cx, cy) = (w as f64 / 2.0, h as f64 / 2.0);
            let r = ((fx - cx).powi(2) + (fy - cy).powi(2)).sqrt();
            let ink = match f {
                0 => r < 13.0,
                1 => ((fx - cx) / 17.0).powi(2) + ((fy - cy) / 11.0).powi(2) < 1.0,
                2 => r < 18.0 && r > 8.0,
                _ => (fx > 8.0 && fx < 16.0 && fy > 6.0 && fy < 34.0) || (fy > 26.0 && fy < 34.0 && fx > 8.0 && fx < 32.0),
            };
            if ink { g[y * w + x] = 0; }
        }}
        let c = capture_gray(w, h, &g, 0.25).unwrap();
        let p = FitPolicy { squared_error: 0.25, max_refits: 8 };
        let (mut fl, ..) = fit_captured(&c.rings, 1.0, &p);
        let dy = c.origin_y;
        for r in &mut fl { r.start.y += dy; }
        for r in &fl {
            let rr = round_and_clean_ring(r, 1.0);
            println!("real{} ring nodes={} spans={}", idx, rr.spans.len(), rr.spans.len());
        }
    }
}
