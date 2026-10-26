use kni_core::{boundary_bias, lever_api, reference_slice};
use boundary_bias::{measure, BiasError, BiasReport};
use lever_api::{hash_rings, SourceMask};
use reference_slice::{Point, ReferenceRing, Span};

fn mask() -> SourceMask {
    let mut ink = vec![255; 16];
    for y in 1..3 {
        for x in 1..3 {
            ink[y * 4 + x] = 0;
        }
    }
    SourceMask { w: 4, h: 4, ink, scale: 1.0, origin: (0.0, 0.0) }
}

fn square() -> ReferenceRing {
    let start = Point { x: 1.0, y: -1.0 };
    ReferenceRing {
        start,
        spans: vec![
            Span::Line { end: Point { x: 3.0, y: -1.0 } },
            Span::Line { end: Point { x: 3.0, y: -3.0 } },
            Span::Line { end: Point { x: 1.0, y: -3.0 } },
            Span::Line { end: start },
        ],
    }
}

fn assert_finite(report: &BiasReport) {
    assert!(report.mean_px.is_finite());
    assert!(report.median_px.is_finite());
    assert!(report.min_px.is_finite());
    assert!(report.max_px.is_finite());
    assert!(report.min_px <= report.mean_px);
    assert!(report.mean_px <= report.max_px);
    assert!(report.min_px <= report.median_px);
    assert!(report.median_px <= report.max_px);
    assert!(report.source_segments > 0);
    assert_eq!(report.scale, 1.0);
    for sample in &report.samples {
        assert!(sample.x_px.is_finite());
        assert!(sample.y_px.is_finite());
        assert!(sample.signed_offset_px.is_finite());
    }
}

#[test]
fn empty_outline_has_no_samples() {
    assert_eq!(measure(&[], &mask()).unwrap_err(), BiasError::NoOutlineSamples);
}

#[test]
fn ring_without_spans_has_no_samples() {
    let rings = vec![ReferenceRing { start: Point { x: 2.0, y: -2.0 }, spans: vec![] }];
    assert_eq!(measure(&rings, &mask()).unwrap_err(), BiasError::NoOutlineSamples);
}

#[test]
fn single_closed_ring_keeps_span_order_and_excludes_duplicate_endpoints() {
    let rings = vec![square()];
    let before = hash_rings(&rings);
    let m = mask();
    let ink_before = m.ink.clone();
    let report = measure(&rings, &m).unwrap();
    assert_eq!(report.samples.len(), 8);
    let expected = [
        (1.0, 1.0), (2.0, 1.0), (3.0, 1.0), (3.0, 2.0),
        (3.0, 3.0), (2.0, 3.0), (1.0, 3.0), (1.0, 2.0),
    ];
    for (i, sample) in report.samples.iter().enumerate() {
        assert_eq!(sample.ring, 0);
        assert_eq!(sample.span, i / 2);
        assert_eq!(sample.t, (i % 2) as f64 / 2.0);
        assert_eq!((sample.x_px, sample.y_px), expected[i]);
    }
    assert_finite(&report);
    assert_eq!(hash_rings(&rings), before);
    assert_eq!(m.ink, ink_before);
}

fn assert_zero_span(span: Span) {
    let point = Point { x: 2.0, y: -2.0 };
    let rings = vec![ReferenceRing { start: point, spans: vec![span] }];
    let before = hash_rings(&rings);
    let report = measure(&rings, &mask()).unwrap();
    assert_eq!(report.samples.len(), 1);
    let sample = &report.samples[0];
    assert_eq!((sample.ring, sample.span), (0, 0));
    assert_eq!(sample.t, 0.0);
    assert_eq!((sample.x_px, sample.y_px), (2.0, 2.0));
    assert_eq!(sample.signed_offset_px, -1.0);
    assert_eq!(report.mean_px, -1.0);
    assert_eq!(report.median_px, -1.0);
    assert_eq!(report.min_px, -1.0);
    assert_eq!(report.max_px, -1.0);
    assert_finite(&report);
    assert_eq!(hash_rings(&rings), before);
}

#[test]
fn zero_length_line_is_sampled_once() {
    assert_zero_span(Span::Line { end: Point { x: 2.0, y: -2.0 } });
}

#[test]
fn zero_length_cubic_is_sampled_once() {
    let point = Point { x: 2.0, y: -2.0 };
    assert_zero_span(Span::Cubic { control_one: point, control_two: point, end: point });
}

#[test]
fn all_ink_mask_has_a_boundary_against_the_white_exterior() {
    let m = SourceMask { w: 3, h: 3, ink: vec![0; 9], scale: 1.0, origin: (0.0, 0.0) };
    let point = Point { x: 1.5, y: -1.5 };
    let rings = vec![ReferenceRing { start: point, spans: vec![Span::Line { end: point }] }];
    let report = measure(&rings, &m).unwrap();
    assert_eq!(report.samples.len(), 1);
    assert_eq!(report.samples[0].signed_offset_px, -1.5);
    assert_eq!(report.mean_px, -1.5);
    assert_finite(&report);
    assert_eq!(m.ink, vec![0; 9]);
}

#[test]
fn all_blank_mask_is_rejected_before_outline_sampling() {
    let mut m = mask();
    m.ink.fill(255);
    assert_eq!(measure(&[square()], &m).unwrap_err(), BiasError::NoSourceBoundary);
    assert_eq!(measure(&[], &m).unwrap_err(), BiasError::NoSourceBoundary);
    assert_eq!(m.ink, vec![255; 16]);
}
