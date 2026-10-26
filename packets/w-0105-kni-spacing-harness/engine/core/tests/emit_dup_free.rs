use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{Point, Span};

fn fit() -> Vec<kni_core::reference_slice::ReferenceRing> {
    let png = std::fs::read("tests/fixtures/00C9_scan.png").unwrap();
    let mc = capture_png(&png, 0.5).unwrap();
    fit_captured(&mc.rings, 1.71, &FitPolicy { squared_error: 0.1, max_refits: 6 }).0
}

/// Contract of the exact-coincidence cleaner on glyph 00C9 (scale 1.71,
/// squared_error 0.1): no zero-length Line, no fully degenerate Cubic, rings
/// closed, no signed zero in any coordinate.
#[test]
fn e_acute_has_no_zero_length_spans() {
    for r in &fit() {
        let mut cur = r.start;
        for s in &r.spans {
            let (end, zero) = match s {
                Span::Line { end } => (*end, *end == cur),
                Span::Cubic { control_one, control_two, end } =>
                    (*end, *end == cur && *control_one == cur && *control_two == cur),
            };
            assert!(!zero, "zero-length span at {cur:?}");
            for p in match s { Span::Line { end } => vec![*end], Span::Cubic { control_one, control_two, end } => vec![*control_one, *control_two, *end] } {
                assert!(!(p.x == 0.0 && p.x.is_sign_negative()) && !(p.y == 0.0 && p.y.is_sign_negative()), "-0.0");
            }
            cur = end;
        }
        assert_eq!(cur, r.start, "closure");
    }
}

/// Documents (does not assert away) the remaining coincident-handle points
/// on 00C9: retracted handles of real cubics, not zero-length spans.
/// 6 -> 0 with the PN-3 fallback rescue: the rescued fit resolves the arcs
/// whose cubics carried retracted handles (chord-line terminal accepts and
/// resolved cubics replace them).
#[test]
fn e_acute_retracted_handle_count_is_recorded() {
    let mut n = 0;
    for r in &fit() {
        let mut cur: Point = r.start;
        for s in &r.spans {
            if let Span::Cubic { control_one, control_two, end } = s {
                n += (*control_one == cur) as usize + (*control_two == *control_one) as usize + (*end == *control_two) as usize;
            }
            cur = match s { Span::Line { end } | Span::Cubic { end, .. } => *end };
        }
    }
    assert_eq!(n, 0, "retracted-handle coincidences on 00C9 changed");
}
