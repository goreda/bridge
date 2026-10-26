//! Source-raster coordinate contract, independent of output serialization.
use kni_core::capture::{capture_png, decode_png_gray, trace_field, trace_mask};
use kni_core::reference_slice::Point;

fn bounds(rings: &[Vec<Point>]) -> (f64, f64, f64, f64) {
    rings.iter().flatten().fold(
        (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY),
        |b, p| (b.0.min(p.x), b.1.min(p.y), b.2.max(p.x), b.3.max(p.y)),
    )
}

#[test]
fn a_single_sample_is_centered_in_its_raster_cell() {
    let rings = trace_mask(1, 1, &[true]);
    assert_eq!(rings.len(), 1);
    assert_eq!(bounds(&rings), (0.0, 0.0, 1.0, 1.0));
    let ring = &rings[0];
    assert_eq!(ring.len(), 4);
    let center = Point {
        x: ring.iter().map(|p| p.x).sum::<f64>() / ring.len() as f64,
        y: ring.iter().map(|p| p.y).sum::<f64>() / ring.len() as f64,
    };
    assert_eq!((center.x, center.y), (0.5, 0.5));
}

#[test]
fn a_full_rectangular_mask_uses_corner_origin_bounds_on_both_axes() {
    for (w, h) in [(2, 7), (9, 3)] {
        let rings = trace_mask(w, h, &vec![true; w * h]);
        assert_eq!(bounds(&rings), (0.0, 0.0, w as f64, h as f64));
    }
}

#[test]
fn interpolation_preserves_subpixel_position_in_the_center_lattice() {
    // The sample at (column 2, row 1) has strength 1; its right neighbor
    // has strength 1/3. At iso 1/2, the right edge is 3/4 cell from center.
    let rings = trace_field(4, 3, &|r, c| {
        match (r, c) { (1, 2) => 1.0, (1, 3) => 1.0 / 3.0, _ => 0.0 }
    }, 0.5);
    assert_eq!(bounds(&rings), (2.0, 1.0, 3.25, 2.0));
    assert!(rings[0].iter().any(|p| (p.x, p.y) == (3.25, 1.5)));
}

#[test]
fn normalization_retains_the_shared_raster_frame_in_the_origin() {
    let png = include_bytes!("fixtures/r_scan.png");
    let (w, h, gray) = decode_png_gray(png).unwrap();
    let field = trace_field(w, h, &|r, c| {
        if r >= 0 && c >= 0 && (r as usize) < h && (c as usize) < w {
            1.0 - gray[r as usize * w + c as usize] as f64 / 255.0
        } else { 0.0 }
    }, 0.5);
    let shared = bounds(&field);
    let captured = capture_png(png, 0.5).unwrap();
    assert_eq!((captured.origin_x, captured.origin_y), (shared.0, -shared.3));
    let restored: Vec<Vec<Point>> = captured.rings.iter().map(|r| r.raw.iter().map(|p| {
        Point { x: p.x + captured.origin_x, y: -(p.y + captured.origin_y) }
    }).collect()).collect();
    let actual = bounds(&restored);
    for (a, b) in [actual.0, actual.1, actual.2, actual.3].into_iter()
        .zip([shared.0, shared.1, shared.2, shared.3]) {
        assert!((a - b).abs() <= f64::EPSILON * w.max(h) as f64);
    }
}
