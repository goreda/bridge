//! w7_speck_census: per-ring area/extent census for one tile (W7 fixture selection).
//! Prints every ring: area px2, bbox span, degenerate flag. Usage: w7_speck_census <png>
use kni_core::curve_stress::{PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS};
fn main() {
    let tile = std::env::args().nth(1).expect("usage: w7_speck_census <png>");
    let bytes = std::fs::read(&tile).expect("read tile");
    let src = kni_core::capture_dispatch::capture_source(&bytes, 0.25, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS).expect("capture");
    let (mut speck_class, mut zero_area, mut subpixel, mut subpixel_holes) = (0usize, 0usize, 0usize, 0usize);
    for r in &src.contour.rings {
        let a = kni_core::capture::ring_area2(&r.points).abs() / 2.0;
        if a == 0.0 { zero_area += 1; } else if kni_core::capture::is_degenerate_ring(&r.points) { speck_class += 1; }
        let (mut x0, mut y0, mut x1, mut y1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for p in &r.points { x0 = x0.min(p.x); y0 = y0.min(p.y); x1 = x1.max(p.x); y1 = y1.max(p.y); }
        if (x1 - x0) < 1.0 || (y1 - y0) < 1.0 { subpixel += 1; if r.hole { subpixel_holes += 1; } }
    }
    println!("counters\tcaptured\t{}\tspeck_class\t{}\tzero_area\t{}\tsubpixel\t{}\tsubpixel_holes\t{}", src.contour.rings.len(), speck_class, zero_area, subpixel, subpixel_holes);
    let mut kept_speck = 0usize;
    for (i, r) in src.contour.rings.iter().enumerate() {
        let a = kni_core::capture::ring_area2(&r.points).abs() / 2.0;
        let (mut x0, mut y0, mut x1, mut y1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for p in &r.points { x0 = x0.min(p.x); y0 = y0.min(p.y); x1 = x1.max(p.x); y1 = y1.max(p.y); }
        let deg = kni_core::capture::is_degenerate_ring(&r.points);
        let subpixel = (x1 - x0) < 1.0 && (y1 - y0) < 1.0;
        if !deg && subpixel { kept_speck += 1; }
        if a < 4.0 { println!("ring\t{i}\tarea\t{a:.4}\tspan\t{:.3}x{:.3}\tdegenerate\t{deg}\tsubpixel\t{subpixel}\thole\t{}", x1 - x0, y1 - y0, r.hole); }
    }
    println!("total_rings\t{}\tkept_subpixel_specks\t{kept_speck}", src.contour.rings.len());
}
