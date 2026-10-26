//! DRAFT precondition (not wired). Bounded-input convention: MAX_TOTAL_SEGMENTS = checked gray.len() = w*h.
//! Must run at the generated-route entry, BEFORE any call into lever_api::{flatten_ring, tagged_segments, area_error}.
//! Computes the exact number of chords those functions would emit, in f64 first (no `as usize` on an unchecked value),
//! and rejects non-finite or over-budget input with a typed error. Formula parity with lever_api.rs:121/229:
//!   Line  -> 1 chord;  Cubic -> n = ceil(|p0p1|+|p1p2|+|p2p3| in px) + 1 chords;  error_map adds 1 closing chord per ring.
use crate::lever_api::SourceMask;
use crate::reference_slice::{Point, ReferenceRing, Span};

#[derive(Clone, Debug, PartialEq)]
pub enum FlattenBudgetError {
    /// w*h overflowed usize or is zero (no budget can be declared)
    BadBudget,
    NonFinitePoint { ring: usize, span: Option<usize> },
    NonFiniteLength { ring: usize, span: usize },
    /// chords needed (f64, may be huge) exceed the declared budget
    OverBudget { ring: usize, span: usize, needed: f64, max_total: usize },
    CountOverflow,
}

/// MAX_TOTAL_SEGMENTS from the source dimensions. None on overflow or zero.
pub fn max_total_segments(w: usize, h: usize) -> Option<usize> { w.checked_mul(h).filter(|&n| n > 0) }

fn d(a: (f64, f64), b: (f64, f64)) -> f64 { ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt() }

/// Total chords flatten/tagged_segments/error_map would process (tagged_segments().len() + one closing chord per ring),
/// or a typed error. `max_total` is MAX_TOTAL_SEGMENTS.
pub fn check_flatten_budget(rings: &[ReferenceRing], mask: &SourceMask, max_total: usize) -> Result<usize, FlattenBudgetError> {
    if max_total == 0 { return Err(FlattenBudgetError::BadBudget); }
    let px = |p: Point, ring: usize, span: Option<usize>| -> Result<(f64, f64), FlattenBudgetError> {
        let q = mask.to_pixel(p);
        if q.0.is_finite() && q.1.is_finite() { Ok(q) } else { Err(FlattenBudgetError::NonFinitePoint { ring, span }) }
    };
    let mut total: usize = 0;
    // Exact chord counter for flatten/tagged_segments/error_map totals; checked_add preserves CountOverflow.
    #[allow(unused_mut)]
    let mut add = |n: usize, total: &mut usize| -> Result<(), FlattenBudgetError> {
        *total = total.checked_add(n).ok_or(FlattenBudgetError::CountOverflow)?; Ok(())
    };
    for (ri, r) in rings.iter().enumerate() {
        let mut cur = px(r.start, ri, None)?;
        for (si, s) in r.spans.iter().enumerate() {
            match s {
                Span::Line { end } => { cur = px(*end, ri, Some(si))?; add(1, &mut total)?; }
                Span::Cubic { control_one, control_two, end } => {
                    let (p1, p2, p3) = (px(*control_one, ri, Some(si))?, px(*control_two, ri, Some(si))?, px(*end, ri, Some(si))?);
                    let len = d(cur, p1) + d(p1, p2) + d(p2, p3);
                    if !len.is_finite() { return Err(FlattenBudgetError::NonFiniteLength { ring: ri, span: si }); }
                    let needed = len.ceil() + 1.0; // compared as f64 BEFORE the cast
                    if needed > max_total as f64 { return Err(FlattenBudgetError::OverBudget { ring: ri, span: si, needed, max_total }); }
                    add(needed as usize, &mut total)?;
                    cur = p3;
                }
            }
            if total > max_total { return Err(FlattenBudgetError::OverBudget { ring: ri, span: si, needed: total as f64, max_total }); }
        }
        add(1, &mut total)?; // closing chord of this ring (error_map implicit closure)
    }
    if total > max_total { return Err(FlattenBudgetError::OverBudget { ring: rings.len().saturating_sub(1), span: 0, needed: total as f64, max_total }); }
    Ok(total)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lever_api::{tagged_segments, NodeBudget};
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn mask(scale: f64) -> SourceMask { SourceMask { w: 12, h: 12, ink: vec![255; 144], scale, origin: (0., 12. * scale) } }
    fn mixed() -> Vec<ReferenceRing> { vec![ReferenceRing { start: p(0., 0.), spans: vec![
        Span::Line { end: p(40., 0.) },
        Span::Cubic { control_one: p(60., 0.), control_two: p(60., 40.), end: p(40., 40.) },
        Span::Line { end: p(0., 40.) }, Span::Line { end: p(0., 0.) }] },
        ReferenceRing { start: p(10., 10.), spans: vec![Span::Line { end: p(20., 10.) }, Span::Line { end: p(10., 20.) }, Span::Line { end: p(10., 10.) }] }] }
    #[test] fn parity_with_tagged_segments_plus_closing_chords() {
        let (r, m) = (mixed(), mask(10.));
        let got = check_flatten_budget(&r, &m, 1_000_000).unwrap();
        assert_eq!(got, tagged_segments(&r, &m).len() + r.len());
        let (r, m) = (mixed(), mask(0.5));
        assert_eq!(check_flatten_budget(&r, &m, 1_000_000).unwrap(), tagged_segments(&r, &m).len() + r.len());
    }
    #[test] fn tiny_scale_is_over_budget_before_any_cast_or_allocation() {
        let (r, m) = (mixed(), mask(1e-12));
        assert!(matches!(check_flatten_budget(&r, &m, 144), Err(FlattenBudgetError::OverBudget { .. })));
    }
    #[test] fn infinite_and_nan_are_typed() {
        let m = mask(1e-300); let r = vec![ReferenceRing { start: p(0., 0.), spans: vec![Span::Cubic { control_one: p(1e300, 0.), control_two: p(0., 1e300), end: p(1., 1.) }, Span::Line { end: p(0., 0.) }] }];
        assert!(matches!(check_flatten_budget(&r, &m, 144), Err(FlattenBudgetError::NonFinitePoint { .. }) | Err(FlattenBudgetError::NonFiniteLength { .. })));
        let r = vec![ReferenceRing { start: p(f64::NAN, 0.), spans: vec![Span::Line { end: p(0., 0.) }] }];
        assert!(matches!(check_flatten_budget(&r, &mask(1.), 144), Err(FlattenBudgetError::NonFinitePoint { ring: 0, span: None })));
    }
    #[test] fn budget_helper_checked() {
        assert_eq!(max_total_segments(12, 12), Some(144)); assert_eq!(max_total_segments(usize::MAX, 2), None); assert_eq!(max_total_segments(0, 5), None);
        let _ = NodeBudget { max_nodes: 0, max_nodes_per_ring: vec![] };
    }
    #[test] fn in_budget_normal_input_passes() { assert!(check_flatten_budget(&mixed(), &mask(10.), 144).is_ok()); }
}
