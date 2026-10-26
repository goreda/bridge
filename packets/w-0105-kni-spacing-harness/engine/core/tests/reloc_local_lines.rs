//! Corner targets come from the local straight-run lines; a target farther than eps from the vertex stays.

use kni_core::capture_fit::local_targets;
use kni_core::reference_slice::Point;

fn p(x: f64, y: f64) -> Point { Point { x, y } }

/// 20x20 square sampled every 1 px; the top-right corner sample is displaced by (dx, dy) from the true
/// corner (20, 0). Polygon vertices are the corner and edge-midpoint samples.
fn square(dx: f64, dy: f64) -> (Vec<Point>, Vec<Point>, Vec<usize>) {
    let mut raw = Vec::new();
    for x in 0..20 { raw.push(p(x as f64, 0.0)); }
    for y in 0..20 { raw.push(p(20.0, y as f64)); }
    for x in 0..20 { raw.push(p(20.0 - x as f64, 20.0)); }
    for y in 0..20 { raw.push(p(0.0, 20.0 - y as f64)); }
    raw[20] = p(20.0 + dx, dy);
    let pts = vec![raw[0], raw[10], raw[20], raw[30], raw[40], raw[50], raw[60], raw[70]];
    (pts, raw, vec![0, 2, 4, 6])
}

#[test]
fn target_within_eps_moves() {
    let (pts, raw, corners) = square(0.4, 0.4);
    let mut a = pts.clone();
    local_targets(&mut a, &corners, &raw, 1.0);
    let d = (a[2].x - 20.0).hypot(a[2].y);
    assert!(d < 0.15 && d < 0.4f64.hypot(0.4), "corner moves onto the edge-line intersection, got ({}, {})", a[2].x, a[2].y);
}

#[test]
fn target_beyond_eps_stays() {
    let (pts, raw, corners) = square(1.2, 1.2);
    let mut a = pts.clone();
    local_targets(&mut a, &corners, &raw, 1.0);
    assert_eq!((a[2].x, a[2].y), (pts[2].x, pts[2].y));
}

#[test]
fn two_corner_ring_wraps() {
    let pts = vec![p(0.0, 0.0), p(5.0, 0.0), p(10.0, 0.0), p(5.0, 5.0)];
    let mut a = pts.clone();
    local_targets(&mut a, &[0, 2], &pts, 1.0);
    assert_eq!(a.len(), 4);
}
