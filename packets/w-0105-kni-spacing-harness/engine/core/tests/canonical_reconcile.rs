//! CANON-FIX-1: the canonical arm wires the landed rounding reconcile
//! (quantize to the integer export grid + W2-2 constant-cubic cleanup) so
//! the canonical chain reaches an integer charstring on glyphs whose raw
//! fit emits non-integer coordinates. These tests pin the wiring contract:
//! refusal closed, every effect a typed row, nothing silently dropped or
//! clamped, non-finite geometry still refused by the downstream gate.

use kni_core::cff_container::{charstring, CffGlyph};
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
use kni_core::rounding_reconcile::{
    drop_constant_cubics, quantize_outline, ConstantCubicHold,
};

fn p(x: f64, y: f64) -> Point {
    Point { x, y }
}

fn cff(id: &str, advance: u16, outline: DrawnGlyph) -> CffGlyph {
    CffGlyph { name: id.to_string(), advance, outline }
}

/// Run the canonical arm's reconcile stage exactly as the harness wires it:
/// quantize, then constant-cubic cleanup, returning the reconciled outline
/// plus both typed reports.
fn reconcile(g: DrawnGlyph) -> (DrawnGlyph, kni_core::rounding_reconcile::QuantizeReport, kni_core::rounding_reconcile::ConstantCubicReport) {
    let mut g = g;
    let q = quantize_outline(&mut g);
    let id = g.glyph_id.clone();
    let mut cffs = vec![cff(&id, 1000, g)];
    let cc = drop_constant_cubics(&mut cffs);
    let g = cffs.into_iter().next().unwrap().outline;
    (g, q, cc)
}

fn rect(id: &str, x0: f64, y0: f64, x1: f64, y1: f64) -> DrawnGlyph {
    DrawnGlyph {
        glyph_id: id.to_string(),
        rings: vec![ReferenceRing {
            start: p(x0, y0),
            spans: vec![
                Span::Line { end: p(x1, y0) },
                Span::Line { end: p(x1, y1) },
                Span::Line { end: p(x0, y1) },
                Span::Line { end: p(x0, y0) },
            ],
        }],
    }
}

#[test]
fn reconcile_closes_the_integer_charstring_refusal() {
    // The W2-3 failure shape: fit output on the half grid refuses the
    // integer container (charstring_refused:UnrepresentableCoordinate).
    let raw = rect("percent_like", 0.5, 0.5, 220.5, 700.5);
    let refused = charstring(&cff("percent_like", 1000, raw.clone()));
    assert!(refused.is_err(), "raw fractional outline must still refuse pre-reconcile");

    let (reconciled, q, cc) = reconcile(raw);
    assert_eq!(q.coordinates, 10);
    assert_eq!(q.moved, 10);
    assert!((q.max_abs_delta - 0.5).abs() < 1e-12);
    assert_eq!(q.non_finite, 0);
    assert!(cc.dropped.is_empty() && cc.held.is_empty());

    let accepted = charstring(&cff("percent_like", 1000, reconciled)).expect("reconciled outline reaches an integer charstring");
    assert!(!accepted.is_empty());
}

#[test]
fn quantization_created_constant_cubic_is_dropped_with_a_typed_row() {
    // A sub-grid cubic: every point lands on (10, 10) after quantization.
    let g = DrawnGlyph {
        glyph_id: "dotlike".to_string(),
        rings: vec![ReferenceRing {
            start: p(10.2, 10.1),
            spans: vec![
                Span::Cubic { control_one: p(10.1, 10.2), control_two: p(10.3, 10.0), end: p(10.2, 10.1) },
                Span::Line { end: p(100.0, 10.0) },
                Span::Line { end: p(10.2, 10.1) },
            ],
        }],
    };
    let (reconciled, _q, cc) = reconcile(g);
    assert_eq!(cc.dropped.len(), 1);
    assert_eq!(cc.dropped[0].glyph_id, "dotlike");
    assert_eq!(cc.dropped[0].ring_index, 0);
    assert_eq!(cc.dropped[0].span_index, 0);
    assert_eq!(cc.dropped[0].point, [10.0, 10.0]);
    assert!(cc.held.is_empty());
    assert_eq!(reconciled.rings[0].spans.len(), 2, "only the constant cubic is removed");
    charstring(&cff("dotlike", 1000, reconciled)).expect("reconciled outline encodes");
}

#[test]
fn all_constant_ring_is_held_never_silently_dropped() {
    // Every span of the ring collapses: removal would empty the ring, so the
    // pass holds each span with a typed row and the ring survives whole.
    let g = DrawnGlyph {
        glyph_id: "pin".to_string(),
        rings: vec![ReferenceRing {
            start: p(10.1, 10.1),
            spans: vec![
                Span::Cubic { control_one: p(10.2, 10.2), control_two: p(10.0, 10.0), end: p(10.1, 10.1) },
            ],
        }],
    };
    let (reconciled, _q, cc) = reconcile(g);
    assert!(cc.dropped.is_empty());
    assert_eq!(cc.held.len(), 1);
    assert_eq!(cc.held[0].why, ConstantCubicHold::WouldEmptyRing);
    assert_eq!(reconciled.rings.len(), 1);
    assert_eq!(reconciled.rings[0].spans.len(), 1, "held ring keeps its span");
    charstring(&cff("pin", 1000, reconciled)).expect("held constant cubic still encodes as integer zero deltas");
}

#[test]
fn non_finite_coordinates_are_never_silently_repaired() {
    let mut g = rect("bad", 0.5, 0.5, 220.5, 700.5);
    g.rings[0].start = p(f64::NAN, 0.5);
    let (reconciled, q, _cc) = reconcile(g);
    assert_eq!(q.non_finite, 1, "the NaN is counted, not repaired");
    assert!(reconciled.rings[0].start.x.is_nan(), "the NaN is left in place");
    assert!(charstring(&cff("bad", 1000, reconciled)).is_err(), "the downstream gate still refuses it typed");
}

#[test]
fn quantize_outline_rounds_half_away_from_zero() {
    let g = DrawnGlyph {
        glyph_id: "ties".to_string(),
        rings: vec![ReferenceRing { start: p(20.5, -0.5), spans: vec![Span::Line { end: p(-20.5, 0.5) }] }],
    };
    let (reconciled, _q, _cc) = reconcile(g);
    assert_eq!(reconciled.rings[0].start.x, 21.0);
    assert_eq!(reconciled.rings[0].start.y, -1.0);
    match &reconciled.rings[0].spans[0] {
        Span::Line { end } => {
            assert_eq!(end.x, -21.0);
            assert_eq!(end.y, 1.0);
        }
        _ => panic!("line span preserved"),
    }
}
