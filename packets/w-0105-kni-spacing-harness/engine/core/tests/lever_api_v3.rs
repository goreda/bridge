use kni_core::lever_api::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};
fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn poly(v: &[(f64, f64)]) -> ReferenceRing {
    let spans = v[1..].iter().chain(std::iter::once(&v[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect();
    ReferenceRing { start: p(v[0].0, v[0].1), spans }
}
fn mask(w: usize, h: usize, f: impl Fn(f64, f64) -> bool) -> SourceMask {
    let mut m = SourceMask { w, h, ink: vec![255; w * h], scale: 2.0, origin: (0.0, 2.0 * h as f64) };
    for j in 0..h { for i in 0..w { let c = m.pixel_centre_to_font(i, j); if f(c.x, c.y) { m.ink[j * w + i] = 0; } } }
    m
}
// Frozen v2 reference implementation (copied from the v2 source, uses only v1-era pieces + error_map).
fn v2_reference(rings: &[ReferenceRing], m: &SourceMask) -> Vec<Vec<f64>> {
    let e = error_map(rings, m);
    let mut segs: Vec<((f64, f64), (f64, f64), usize, usize)> = vec![];
    for (ri, r) in rings.iter().enumerate() {
        let mut cur = m.to_pixel(r.start);
        for (si, s) in r.spans.iter().enumerate() {
            match s {
                Span::Line { end } => { let n = m.to_pixel(*end); segs.push((cur, n, ri, si)); cur = n; }
                Span::Cubic { control_one, control_two, end } => {
                    let (p0, p1, p2, p3) = (cur, m.to_pixel(*control_one), m.to_pixel(*control_two), m.to_pixel(*end));
                    let d = |a: (f64, f64), b: (f64, f64)| ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
                    let n = (d(p0, p1) + d(p1, p2) + d(p2, p3)).ceil() as usize + 1;
                    let mut prev = p0;
                    for k in 1..=n {
                        let t = k as f64 / n as f64; let u = 1.0 - t;
                        let q = (u*u*u*p0.0 + 3.0*u*u*t*p1.0 + 3.0*u*t*t*p2.0 + t*t*t*p3.0, u*u*u*p0.1 + 3.0*u*u*t*p1.1 + 3.0*u*t*t*p2.1 + t*t*t*p3.1);
                        segs.push((prev, q, ri, si)); prev = q;
                    }
                    cur = p3;
                }
            }
        }
    }
    let mut out: Vec<Vec<f64>> = rings.iter().map(|r| vec![0.0; r.spans.len()]).collect();
    if segs.is_empty() { return out; }
    let k2 = m.scale * m.scale;
    for j in 0..m.h { for i in 0..m.w {
        let v = e[j * m.w + i]; if v <= 0.0 { continue; }
        let c = (i as f64 + 0.5, j as f64 + 0.5);
        let mut best = f64::INFINITY; let mut who = (0usize, 0usize);
        for &(a, b, ri, si) in &segs {
            let (dx, dy) = (b.0 - a.0, b.1 - a.1); let l2 = dx * dx + dy * dy;
            let t = if l2 == 0.0 { 0.0 } else { (((c.0 - a.0) * dx + (c.1 - a.1) * dy) / l2).clamp(0.0, 1.0) };
            let (px, py) = (a.0 + t * dx, a.1 + t * dy);
            let dd = (c.0 - px).powi(2) + (c.1 - py).powi(2);
            if dd < best { best = dd; who = (ri, si); }
        }
        out[who.0][who.1] += v * k2;
    } }
    out
}
fn circleish() -> ReferenceRing {
    let (cx, cy, r, k) = (64.0, 64.0, 40.0, 22.0);
    let cub = |a: (f64, f64), b: (f64, f64), e: (f64, f64)| Span::Cubic { control_one: p(a.0, a.1), control_two: p(b.0, b.1), end: p(e.0, e.1) };
    ReferenceRing { start: p(cx + r, cy), spans: vec![
        cub((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)), cub((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
        cub((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)), cub((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)) ] }
}
#[test]
fn v3_version_and_v2_outputs_bit_identical() {
    assert_eq!(LEVER_API_VERSION, 3);
    let m = mask(64, 64, |x, y| (x - 64.0).powi(2) + (y - 64.0).powi(2) <= 41.0 * 41.0);
    for rings in [vec![circleish()], vec![poly(&[(40.0, 44.0), (124.0, 36.0), (80.0, 120.0)])]] {
        let new = area_error_per_span(&rings, &m); let old = v2_reference(&rings, &m);
        assert_eq!(new.len(), old.len());
        for (a, b) in new.iter().zip(&old) { for (x, y) in a.iter().zip(b) { assert_eq!(x.to_bits(), y.to_bits()); } }
    }
}
#[test]
fn error_map_scaled_sum_is_area_error() {
    let m = mask(64, 64, |x, y| (x - 64.0).powi(2) + (y - 64.0).powi(2) <= 41.0 * 41.0);
    let r = vec![circleish()];
    let e = error_map(&r, &m);
    assert_eq!(e.len(), 64 * 64);
    let s: f64 = e.iter().sum::<f64>() * m.scale * m.scale;
    assert!((s - area_error(&r, &m)).abs() < 1e-9);
}
#[test]
fn tagged_segments_order_and_coverage() {
    let m = mask(64, 64, |_, _| false);
    let r = vec![circleish(), poly(&[(10.0, 10.0), (30.0, 10.0), (20.0, 30.0)])];
    let segs = tagged_segments(&r, &m);
    let keys: Vec<(usize, usize)> = segs.iter().map(|s| (s.ring, s.span)).collect();
    let mut sorted = keys.clone(); sorted.sort(); assert_eq!(keys, sorted, "order is (ring, span, sub)");
    for (ri, ring) in r.iter().enumerate() { for si in 0..ring.spans.len() { assert!(keys.contains(&(ri, si))); } }
    assert!(tagged_segments(&[], &m).is_empty());
    assert_eq!(nearest_segment((0.0, 0.0), &[]), None);
}
#[test]
fn tie_goes_to_lowest_index() {
    let a = TaggedSegment { a: (0.0, 0.0), b: (10.0, 0.0), ring: 0, span: 0 };
    let b = TaggedSegment { a: (0.0, 2.0), b: (10.0, 2.0), ring: 0, span: 1 };
    // point (5,1) is exactly 1.0 from both
    assert_eq!(nearest_segment((5.0, 1.0), &[a, b]), Some(0));
    assert_eq!(nearest_segment((5.0, 1.0), &[b, a]), Some(0)); // index, not span id, decides
    assert_eq!(nearest_segment((5.0, 1.5), &[a, b]), Some(1));
}

// ---- area_error_below: exact reject-fast contract ----
fn tri_inside(a: (f64, f64), b: (f64, f64), c: (f64, f64)) -> impl Fn(f64, f64) -> bool {
    move |x, y| {
        let s = |p: (f64, f64), q: (f64, f64)| (q.0 - p.0) * (y - p.1) - (q.1 - p.1) * (x - p.0);
        let (d1, d2, d3) = (s(a, b), s(b, c), s(c, a));
        (d1 >= 0.0 && d2 >= 0.0 && d3 >= 0.0) || (d1 <= 0.0 && d2 <= 0.0 && d3 <= 0.0)
    }
}
fn below_fixture() -> (Vec<ReferenceRing>, SourceMask) {
    let m = mask(64, 64, tri_inside((40.0, 44.0), (124.0, 36.0), (80.0, 120.0)));
    let input = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
    (input, m)
}

#[test]
fn area_error_below_matches_area_error_value_and_decision() {
    let (rings, m) = below_fixture();
    let e = area_error(&rings, &m);
    assert!(e.is_finite() && e > 0.0, "fixture error must be a positive finite value: {e}");
    // below the true value: exact same number back
    for l in [e + 1.0, e * 2.0, e + 1e-9, f64::MAX] {
        let got = area_error_below(&rings, &m, l);
        assert_eq!(got.map(|v| v.to_bits()), Some(e.to_bits()), "Some value must be bit-identical to area_error at limit {l}");
    }
    // at or above the true value: certain reject (None), matching e < limit == false
    for l in [e, e - 1e-9, e * 0.5, 0.0] {
        assert_eq!(area_error_below(&rings, &m, l), None, "limit {l} must be a certain reject (area {e})");
    }
    // NaN limit: no prefix can prove anything, full scan runs; caller's own
    // `e < limit` comparison still decides (false for NaN), as before
    let got = area_error_below(&rings, &m, f64::NAN);
    assert_eq!(got.map(|v| v.to_bits()), Some(e.to_bits()));
}

#[test]
fn area_error_below_reentrant_and_reused_scratch_agree() {
    let (rings, m) = below_fixture();
    let e = area_error(&rings, &m);
    // nested call inside a borrow of the thread-local scratch must take the
    // fallback path and still return the exact value
    let outer = area_error_below(&rings, &m, e * 2.0);
    let inner = area_error_below(&rings, &m, e * 2.0);
    assert_eq!(outer.map(|v| v.to_bits()), inner.map(|v| v.to_bits()));
}

/// Synthetic reject-heavy timing evidence (printed, not asserted): on a large
/// mask with a badly misplaced candidate, the reject-fast scan exits early
/// while returning the exact same decision. Wall-clock numbers go to stderr
/// for the delivery report; bit-identity of accepted values is asserted.
#[test]
fn area_error_below_timing_reject_heavy() {
    let m = mask(512, 512, tri_inside((200.0, 220.0), (900.0, 180.0), (500.0, 950.0)));
    // candidate far off the ink: huge error, rejected against any tight best
    let rings = vec![poly(&[(10.0, 12.0), (60.0, 8.0), (30.0, 60.0)])];
    let e = area_error(&rings, &m);
    assert!(e > 0.0);
    let limit = e * 0.5;
    let t0 = std::time::Instant::now();
    let mut acc = 0.0f64;
    for _ in 0..200 { acc += area_error(&rings, &m); }
    let full = t0.elapsed();
    let t1 = std::time::Instant::now();
    let mut n = 0usize;
    for _ in 0..200 { if area_error_below(&rings, &m, limit).is_none() { n += 1; } }
    let prescreen = t1.elapsed();
    assert_eq!(n, 200, "every iteration must be a certain reject");
    assert!(acc.is_finite());
    // accepted path stays bit-identical under the pre-screen
    let t2 = std::time::Instant::now();
    for _ in 0..50 { let _ = area_error_below(&rings, &m, e + 1.0); }
    let accept_path = t2.elapsed();
    assert_eq!(area_error_below(&rings, &m, e + 1.0).map(|v| v.to_bits()), Some(e.to_bits()));
    eprintln!("timing: full area_error x200 = {:?}, reject-fast x200 = {:?}, accept-path x50 = {:?}", full, prescreen, accept_path);
}
