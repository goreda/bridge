use kni_core::int_refine::try_apply;
use kni_core::lever_api::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn poly(v: &[(f64, f64)]) -> ReferenceRing {
    let spans = v[1..].iter().chain(std::iter::once(&v[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect();
    ReferenceRing { start: p(v[0].0, v[0].1), spans }
}
// mask: 64x64 px, 2 font units per px, origin top-left at font (0,128): font y = 128 - py*2
fn mask_from(f: impl Fn(f64, f64) -> bool) -> SourceMask {
    let (w, h, scale, origin) = (64usize, 64usize, 2.0, (0.0, 128.0));
    let mut ink = vec![255u8; w * h];
    let mut m = SourceMask { w, h, ink: vec![], scale, origin };
    for j in 0..h { for i in 0..w {
        let c = m.pixel_centre_to_font(i, j);
        if f(c.x, c.y) { ink[j * w + i] = 0; }
    } }
    m.ink = ink; m
}
fn tri_inside(a: (f64, f64), b: (f64, f64), c: (f64, f64)) -> impl Fn(f64, f64) -> bool {
    move |x, y| {
        let s = |p: (f64, f64), q: (f64, f64)| (q.0 - p.0) * (y - p.1) - (q.1 - p.1) * (x - p.0);
        let (d1, d2, d3) = (s(a, b), s(b, c), s(c, a));
        (d1 >= 0.0 && d2 >= 0.0 && d3 >= 0.0) || (d1 <= 0.0 && d2 <= 0.0 && d3 <= 0.0)
    }
}
fn budget(r: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(r), max_nodes_per_ring: vec![] } }

#[test]
fn convention_aligned_rect_has_zero_error() {
    // pixel (i,j) covers [i,i+1]x[j,j+1]; font x = 2*px, y = 128-2*py. Ink px 10..30 x, 10..30 y.
    let m = mask_from(|x, y| x > 20.0 && x < 60.0 && y > 68.0 && y < 108.0);
    let r = poly(&[(20.0, 108.0), (60.0, 108.0), (60.0, 68.0), (20.0, 68.0)]);
    assert!(area_error(&[r], &m) < 1e-9);
}

#[test]
fn improves_area_without_adding_nodes_and_within_one_unit() {
    let (a, b, c) = ((40.0, 44.0), (124.0, 36.0), (80.0, 120.0));
    let m = mask_from(tri_inside(a, b, c));
    let input = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
    let (out, rep) = try_apply(&input, &m, &budget(&input)).unwrap();
    assert!(rep.area_after < rep.area_before, "{} !< {}", rep.area_after, rep.area_before);
    assert!(rep.nodes_after <= rep.nodes_before);
    assert!(rep.max_node_displacement <= 1.0);
    assert_eq!(rep.input_hash, hash_rings(&input));
    assert_eq!(rep.output_hash, hash_rings(&out));
}

#[test]
fn deterministic_two_runs_same_hash() {
    let m = mask_from(tri_inside((40.0, 44.0), (124.0, 36.0), (80.0, 120.0)));
    let input = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
    let (_, r1) = try_apply(&input, &m, &budget(&input)).unwrap();
    let (_, r2) = try_apply(&input, &m, &budget(&input)).unwrap();
    assert_eq!(r1.output_hash, r2.output_hash);
}

#[test]
fn axis_aligned_rect_is_untouched() {
    let m = mask_from(|x, y| x > 20.0 && x < 60.0 && y > 68.0 && y < 108.0);
    let input = vec![poly(&[(20.0, 108.0), (60.0, 108.0), (60.0, 68.0), (20.0, 68.0)])];
    let (_, rep) = try_apply(&input, &m, &budget(&input)).unwrap();
    assert_eq!(rep.input_hash, rep.output_hash);
}

#[test]
fn budget_violation_is_error_not_clip() {
    let m = mask_from(|_, _| false);
    let input = vec![poly(&[(40.0, 44.0), (124.0, 36.0), (80.0, 120.0)])];
    let tight = NodeBudget { max_nodes: 2, max_nodes_per_ring: vec![] };
    assert!(try_apply(&input, &m, &tight).is_err());
}

#[test]
fn extremum_node_never_leaves_extremum() {
    // circle-like ring: extremum nodes with axis-aligned handles; all must survive
    let k = 33.0; // handle length, integer
    let (cx, cy, r) = (64.0, 64.0, 40.0);
    let cub = |c1: (f64, f64), c2: (f64, f64), e: (f64, f64)| Span::Cubic { control_one: p(c1.0, c1.1), control_two: p(c2.0, c2.1), end: p(e.0, e.1) };
    let ring = ReferenceRing { start: p(cx + r, cy), spans: vec![
        cub((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)),
        cub((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
        cub((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)),
        cub((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)),
    ]};
    let m = mask_from(|x, y| (x - 64.0).powi(2) + (y - 64.0).powi(2) <= 41.0 * 41.0);
    let input = vec![ring];
    let (out, rep) = try_apply(&input, &m, &budget(&input)).unwrap();
    assert!(rep.area_after <= rep.area_before);
    // extremum nodes unchanged
    for (a, b) in input[0].spans.iter().zip(&out[0].spans) {
        if let (Span::Cubic { end: e1, .. }, Span::Cubic { end: e2, .. }) = (a, b) {
            assert_eq!(e1, e2);
        }
    }
}

#[test]
fn per_span_error_sums_to_area_error_and_v2_marker() {
    assert!(LEVER_API_VERSION >= 2);
    let m = mask_from(tri_inside((40.0, 44.0), (124.0, 36.0), (80.0, 120.0)));
    let input = vec![poly(&[(40.0, 45.0), (124.0, 37.0), (81.0, 120.0)])];
    let per = area_error_per_span(&input, &m);
    let total: f64 = per.iter().flatten().sum();
    let ae = area_error(&input, &m);
    assert!((total - ae).abs() < 1e-6 * (1.0 + ae), "{} vs {}", total, ae);
    assert_eq!(per, area_error_per_span(&input, &m));
}
