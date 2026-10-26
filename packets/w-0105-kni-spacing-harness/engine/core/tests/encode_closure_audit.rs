//! Encode-boundary closure audit: the audit shares the closure invariant
//! with the encoder through `ValidatedClosedGeometry`, emits typed rows,
//! and never mutates or refuses.
use kni_core::outline_interface::{
    audit_glyph_closure, closure_audit_tsv, ClosureAuditStatus,
};
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

fn pt(x: f64, y: f64) -> Point {
    Point { x, y }
}

fn closed_glyph() -> DrawnGlyph {
    let o = pt(0.0, 0.0);
    DrawnGlyph {
        glyph_id: "A".into(),
        rings: vec![ReferenceRing {
            start: o,
            spans: vec![
                Span::Line { end: pt(10.0, 0.0) },
                Span::Line { end: pt(0.0, 10.0) },
                Span::Line { end: o },
            ],
        }],
    }
}

#[test]
fn closed_glyph_audits_closed() {
    let row = audit_glyph_closure(&closed_glyph());
    assert_eq!(row.status, ClosureAuditStatus::Closed);
    assert_eq!(row.rings, 1);
    assert_eq!(row.spans, 3);
}

#[test]
fn open_contour_audits_open_contour() {
    let mut g = closed_glyph();
    g.rings[0].spans.pop();
    assert_eq!(audit_glyph_closure(&g).status, ClosureAuditStatus::OpenContour);
}

#[test]
fn empty_glyph_audits_no_outline() {
    let g = DrawnGlyph { glyph_id: "space".into(), rings: vec![] };
    assert_eq!(audit_glyph_closure(&g).status, ClosureAuditStatus::NoOutline);
    let mut h = closed_glyph();
    h.rings[0].spans.clear();
    assert_eq!(audit_glyph_closure(&h).status, ClosureAuditStatus::NoOutline);
}

#[test]
fn nonfinite_coordinate_audits_non_finite() {
    let mut g = closed_glyph();
    g.rings[0].spans[0] = Span::Line { end: pt(f64::NAN, 0.0) };
    assert_eq!(audit_glyph_closure(&g).status, ClosureAuditStatus::NonFinite);
}

#[test]
fn tsv_carries_one_row_per_glyph_plus_the_summary() {
    let mut open = closed_glyph();
    open.glyph_id = "B".into();
    open.rings[0].spans.pop();
    let rows = vec![audit_glyph_closure(&closed_glyph()), audit_glyph_closure(&open)];
    let tsv = closure_audit_tsv(&rows);
    assert!(tsv.contains("# glyphs\t2\tclosed\t1\tnot_closed\t1\n"));
    assert!(tsv.contains("glyph\trings\tspans\tstatus\n"));
    assert!(tsv.contains("A\t1\t3\tclosed\n"));
    assert!(tsv.contains("B\t1\t2\topen_contour\n"));
}
