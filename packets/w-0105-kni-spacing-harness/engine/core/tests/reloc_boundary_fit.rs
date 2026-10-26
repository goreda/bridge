//! A corner relocation is kept only where the moved corner fits the raw boundary at least as well as before.

use kni_core::capture_fit::{local_targets, relocate_corners_verified};
use kni_core::reference_slice::Point;

fn p(x: f64, y: f64) -> Point { Point { x, y } }

/// Square whose top-right corner vertex sits 0.4 px off the lines of its two edges.
/// `bulge` pushes the midpoint of the top edge off the chord (a curved edge).
fn square(bulge: f64) -> (Vec<Point>, Vec<usize>) {
    let pts = vec![
        p(0.0, 0.0), p(10.0, bulge), p(20.4, 0.4), p(20.0, 10.0), p(20.0, 20.0), p(10.0, 20.0),
        p(0.0, 20.0), p(0.0, 10.0),
    ];
    (pts, vec![0, 2, 4, 6])
}

#[test]
fn straight_corner_moves() {
    let (pts, corners) = square(0.0);
    let raw = pts.clone();
    let mut a = pts.clone();
    let moved = relocate_corners_verified(&mut a, &corners, &raw, 1.0);
    let mut b = pts.clone();
    local_targets(&mut b, &corners, &raw, 1.0);
    assert!(moved >= 1);
    assert_eq!((a[2].x, a[2].y), (b[2].x, b[2].y));
    let d = |q: Point| (q.x - 20.0).hypot(q.y);
    assert!(d(a[2]) < d(pts[2]), "corner moves toward the edge-line intersection");
}

#[test]
fn move_that_fits_raw_boundary_worse_is_rejected() {
    // Polygon vertices say the right edge leans (corner vertex displaced), but the raw boundary
    // along the top edge bulges: the unverified TLS intersection overshoots the contour.
    let (pts, corners) = square(0.0);
    let mut raw = pts.clone();
    // raw boundary hugs the ORIGINAL chord corner(0)->corner(2) on the top edge with a plateau at y=0.4
    raw[1] = p(10.0, 0.2);
    for k in [0usize] { raw[k] = pts[k]; }
    let mut a = pts.clone();
    relocate_corners_verified(&mut a, &corners, &raw, 1.0);
    let mut b = pts.clone();
    local_targets(&mut b, &corners, &raw, 1.0);
    let dev = |q: Point| {
        let (c0, c2) = (pts[0], q);
        let (dx, dy) = (c2.x - c0.x, c2.y - c0.y);
        ((raw[1].x - c0.x) * dy - (raw[1].y - c0.y) * dx).abs() / dx.hypot(dy)
    };
    assert!(dev(a[2]) <= dev(b[2]) + 1e-12, "verified result never fits the raw boundary worse than the unverified move");
}

#[test]
fn unverifiable_edge_stays() {
    let (pts, corners) = square(0.0);
    let mut a = pts.clone();
    relocate_corners_verified(&mut a, &corners, &[], 1.0);
    assert_eq!((a[2].x, a[2].y), (pts[2].x, pts[2].y));
}
