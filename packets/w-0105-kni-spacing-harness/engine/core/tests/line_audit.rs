//! Fake-line hunt: shipped Line spans audited against the source contour
//! they were fitted from. Synthetic oracles with exact expected deviations.
use kni_core::line_audit::{audit_line_spans, line_span_audit_tsv, LineSpanAudit};
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn pt(x: f64, y: f64) -> Point { Point { x, y } }

/// units -> absolute capture px: px = x/scale + origin_x, py = y/scale
fn from_px(p: Point, scale: f64, origin_x: f64) -> Point {
    pt((p.x - origin_x) * scale, p.y * scale)
}

fn one_span_ring(a: Point, b: Point) -> Vec<ReferenceRing> {
    vec![ReferenceRing { start: a, spans: vec![Span::Line { end: b }, Span::Line { end: a }] }]
}

#[test]
fn straight_source_arc_is_not_suspicious() {
    // Bottom edge straight (2 px steps), top edge straight at y=4: chord on
    // the bottom edge picks the zero-deviation arc.
    let ring: Vec<Point> = {
        let mut v: Vec<Point> = (0..=50).map(|i| pt(i as f64 * 2.0, 0.0)).collect();
        v.push(pt(100.0, 4.0));
        v.push(pt(0.0, 4.0));
        v
    };
    let (scale, ox) = (2.0, 10.0);
    let a = from_px(pt(0.0, 0.0), scale, ox);
    let b = from_px(pt(100.0, 0.0), scale, ox);
    let rings = one_span_ring(a, b); let rows = audit_line_spans(&rings, &[ring.clone()], ox, scale, 1.0);
    let r = &rows[0];
    assert!(r.anchored, "{r:?}");
    assert_eq!(r.samples, 49, "intermediate samples on the bottom edge: {r:?}");
    assert!(r.max_dev_px < 1e-9, "{r:?}");
    assert!(!r.suspicious, "{r:?}");
    assert!((r.chord_px - 100.0).abs() < 1e-9, "{r:?}");
}

#[test]
fn curved_source_arc_absorbed_as_line_is_suspicious() {
    // Quarter circle r=100 px sampled at 1 degree: exact max deviation of the
    // arc from the chord is r*(1 - sqrt(2)/2) at the 45-degree sample.
    let r = 100.0f64;
    let ring: Vec<Point> = (0..360)
        .map(|d| { let t = (d as f64).to_radians(); pt(r * t.cos(), r * t.sin()) })
        .collect();
    let (scale, ox) = (2.0, 10.0);
    let a = from_px(pt(r, 0.0), scale, ox);
    let b = from_px(pt(0.0, r), scale, ox);
    let rings = one_span_ring(a, b); let rows = audit_line_spans(&rings, &[ring.clone()], ox, scale, 1.0);
    let row = &rows[0];
    assert!(row.anchored, "{row:?}");
    let expected = r * (1.0 - std::f64::consts::SQRT_2 / 2.0);
    assert!((row.max_dev_px - expected).abs() < 1.0, "expected ~{expected}, got {row:?}");
    assert_eq!(row.samples, 89, "the quarter arc, not the three-quarter one: {row:?}");
    assert!(row.suspicious, "29 px of measurable curvature over rdp_eps=1: {row:?}");
    // A loose capture tolerance (the run's own declared bar) clears it.
    let rows2 = audit_line_spans(&rings, &[ring], ox, scale, 1000.0);
    assert!(!rows2[0].suspicious, "{rows2:?}");
}

#[test]
fn span_far_from_any_contour_is_unanchored_not_suspicious() {
    let ring = vec![pt(0.0, 0.0), pt(10.0, 0.0), pt(10.0, 10.0), pt(0.0, 10.0)];
    let (scale, ox) = (1.0, 0.0);
    // chord at x ~= 1000 px: no contour arc accepts the endpoints
    let rows = audit_line_spans(&one_span_ring(pt(1000.0, 0.0), pt(1000.0, 50.0)), &[ring], ox, scale, 0.25);
    assert!(!rows[0].anchored && !rows[0].suspicious, "{rows:?}");
    let tsv = line_span_audit_tsv("g", &rows[0]);
    assert!(tsv.ends_with("unanchored\n"), "{tsv}");
}

#[test]
fn zero_length_span_is_degenerate() {
    let ring = vec![pt(0.0, 0.0), pt(10.0, 0.0), pt(10.0, 10.0), pt(0.0, 10.0)];
    let rows = audit_line_spans(&one_span_ring(pt(5.0, 5.0), pt(5.0, 5.0)), &[ring], 0.0, 1.0, 0.25);
    assert!(!rows[0].anchored && rows[0].chord_px == 0.0, "{rows:?}");
    assert!(line_span_audit_tsv("g", &rows[0]).ends_with("degenerate\n"));
}

#[test]
fn cubic_spans_are_not_audited() {
    let ring = vec![pt(0.0, 0.0), pt(10.0, 0.0), pt(10.0, 10.0), pt(0.0, 10.0)];
    let rings = vec![ReferenceRing {
        start: pt(0.0, 0.0),
        spans: vec![Span::Cubic { control_one: pt(3.0, 3.0), control_two: pt(6.0, 3.0), end: pt(10.0, 0.0) }],
    }];
    assert!(audit_line_spans(&rings, &[ring], 0.0, 1.0, 0.25).is_empty());
}

#[test]
fn tsv_row_shape_is_stable() {
    let a = LineSpanAudit { ring: 1, span: 2, start: pt(1.0, 2.0), end: pt(3.0, 4.0),
        chord_px: 2.5, anchor_px: 0.5, arc_len_px: 3.0, max_dev_px: 1.25, samples: 7, anchored: true, suspicious: true };
    let row = line_span_audit_tsv("A", &a);
    let f: Vec<&str> = row.trim_end().split('\t').collect();
    assert_eq!(f.len(), 14, "{row}");
    assert_eq!(f[0], "A");
    assert_eq!(f[1], "1");
    assert_eq!(f[2], "2");
    assert_eq!(f[12], "1");
    assert_eq!(f[13], "anchored");
}
