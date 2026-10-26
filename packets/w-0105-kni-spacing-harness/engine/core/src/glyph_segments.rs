//! Typed segment list for shipped glyph rings.
//!
//! Takes rings whose coordinates are already integers and returns a flat,
//! deterministically ordered list of typed segments (line or arc). Every
//! value is carried over exactly from the ring: no float is re-derived,
//! nothing is fitted or rounded. The list is a pure read of its input and is
//! not wired into any production path.
//!
//! `segment_metrics` adds per-glyph counts (line, cubic, G1 joins, corner
//! joins) and total chord length for the receipt; it reuses the integer
//! tangent rule of `economy_eval`.

use crate::reference_slice::{Point, ReferenceRing, Span};

/// Integer point.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct IntPoint {
    pub x: i64,
    pub y: i64,
}

/// Direction class of a line segment, from integer deltas only.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum LineAxis {
    Horizontal,
    Vertical,
    Oblique,
    /// Start equals end.
    Degenerate,
}

/// Segment class with its exact integer control data.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SegmentClass {
    Line { axis: LineAxis },
    /// Cubic arc with its two control points.
    Arc { control_one: IntPoint, control_two: IntPoint },
}

/// One typed segment of a ring.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct GlyphSegment {
    /// Ring index in input order.
    pub ring: usize,
    /// Span index within the ring.
    pub span: usize,
    pub start: IntPoint,
    pub end: IntPoint,
    pub class: SegmentClass,
}

/// Why a ring set could not be turned into a segment list.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SegmentError {
    /// A coordinate is not an integer value (NaN, infinite, fractional or out of range).
    NonIntegerCoordinate { ring: usize, span: Option<usize> },
}

fn to_int(p: Point) -> Option<IntPoint> {
    fn c(v: f64) -> Option<i64> {
        // Exact integer only; 2^53 keeps the f64 -> i64 cast lossless.
        if v.is_finite() && v.fract() == 0.0 && v.abs() <= 9_007_199_254_740_992.0 {
            Some(v as i64)
        } else {
            None
        }
    }
    Some(IntPoint { x: c(p.x)?, y: c(p.y)? })
}

fn axis(a: IntPoint, b: IntPoint) -> LineAxis {
    match (a.x == b.x, a.y == b.y) {
        (true, true) => LineAxis::Degenerate,
        (false, true) => LineAxis::Horizontal,
        (true, false) => LineAxis::Vertical,
        _ => LineAxis::Oblique,
    }
}

/// Segments of all rings, ordered by (ring, span). A ring is closed: its
/// last span ends at the ring start by construction of the input, and each
/// segment starts where the previous one ended. Fails without partial
/// output when any coordinate is not an exact integer.
pub fn glyph_segments(rings: &[ReferenceRing]) -> Result<Vec<GlyphSegment>, SegmentError> {
    let mut out = Vec::new();
    for (ri, ring) in rings.iter().enumerate() {
        let mut cur = to_int(ring.start).ok_or(SegmentError::NonIntegerCoordinate { ring: ri, span: None })?;
        for (si, span) in ring.spans.iter().enumerate() {
            let bad = SegmentError::NonIntegerCoordinate { ring: ri, span: Some(si) };
            let seg = match span {
                Span::Line { end } => {
                    let e = to_int(*end).ok_or(bad)?;
                    GlyphSegment { ring: ri, span: si, start: cur, end: e, class: SegmentClass::Line { axis: axis(cur, e) } }
                }
                Span::Cubic { control_one, control_two, end } => {
                    let c1 = to_int(*control_one).ok_or(bad)?;
                    let c2 = to_int(*control_two).ok_or(bad)?;
                    let e = to_int(*end).ok_or(bad)?;
                    GlyphSegment { ring: ri, span: si, start: cur, end: e, class: SegmentClass::Arc { control_one: c1, control_two: c2 } }
                }
            };
            cur = seg.end;
            out.push(seg);
        }
    }
    Ok(out)
}

/// Join class at the vertex between two consecutive spans.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JoinClass {
    /// Integer in/out tangents are parallel and point the same way.
    G1,
    /// Anything else, including a degenerate tangent.
    Corner,
}

/// Per-glyph segment counts and chord length of the shipped rings.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SegmentMetrics {
    /// Line spans.
    pub line: usize,
    /// Cubic spans.
    pub cubic: usize,
    /// Joins classed G1.
    pub g1: usize,
    /// Joins classed corner.
    pub corner: usize,
    /// Sum of per-span chord lengths (straight start-to-end distance, not arc length).
    pub chord_len: f64,
}

/// Class of the join that starts span `k` of `ring`; `None` when the ring has
/// no such span. Uses the same exact integer tangent rule as `economy_eval`
/// (first non-zero in/out tangent, cross == 0 and dot > 0); a degenerate
/// tangent is a corner. A ring is closed: span 0 joins the last span.
pub fn join_class(ring: &ReferenceRing, k: usize) -> Option<JoinClass> {
    if k >= ring.spans.len() { return None; }
    Some(match crate::economy_eval::tangents(ring, k) {
        Some((a, b)) if crate::economy_eval::smooth(a, b) => JoinClass::G1,
        _ => JoinClass::Corner,
    })
}

/// Counts and chord length over all rings. A ring of n spans has n joins, so
/// `g1 + corner == line + cubic`. Rings with no spans contribute nothing.
/// Expects the documented closed-ring form (last span ends at the ring
/// start); this is not enforced.
pub fn segment_metrics(rings: &[ReferenceRing]) -> SegmentMetrics {
    let mut m = SegmentMetrics { line: 0, cubic: 0, g1: 0, corner: 0, chord_len: 0.0 };
    for ring in rings {
        let mut cur = ring.start;
        for (k, span) in ring.spans.iter().enumerate() {
            let end = match span {
                Span::Line { end } => { m.line += 1; *end }
                Span::Cubic { end, .. } => { m.cubic += 1; *end }
            };
            m.chord_len += (end.x - cur.x).hypot(end.y - cur.y);
            cur = end;
            match join_class(ring, k) {
                Some(JoinClass::G1) => m.g1 += 1,
                _ => m.corner += 1,
            }
        }
    }
    m
}

/// Receipt row for one glyph, or `None` when the drawing has no spans (no row,
/// so every emitted ratio is finite). Fields, tab separated, 18 in all:
/// `glyph_segments, subject, line, n, cubic, n, cubic_pct, f, g1, n, corner, n,
/// corner_per_node, f, chord_len, f, len_per_node, f`. Floats use `{:.6}`;
/// `chord_len` is the sum of span chords, not arc length. Rows end with LF.
pub fn receipt_row(subject: &str, rings: &[ReferenceRing]) -> Option<String> {
    let m = segment_metrics(rings);
    let nodes = m.line + m.cubic;
    if nodes == 0 { return None; }
    let n = nodes as f64;
    Some(format!(
        "glyph_segments\t{}\tline\t{}\tcubic\t{}\tcubic_pct\t{:.6}\tg1\t{}\tcorner\t{}\tcorner_per_node\t{:.6}\tchord_len\t{:.6}\tlen_per_node\t{:.6}\n",
        subject, m.line, m.cubic, 100.0 * m.cubic as f64 / n, m.g1, m.corner,
        m.corner as f64 / n, m.chord_len, m.chord_len / n))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(x: f64, y: f64) -> Point { Point { x, y } }

    fn square() -> ReferenceRing {
        ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![
                Span::Line { end: p(10.0, 0.0) },
                Span::Line { end: p(10.0, 10.0) },
                Span::Line { end: p(0.0, 10.0) },
                Span::Line { end: p(0.0, 0.0) },
            ],
        }
    }

    #[test]
    fn square_is_four_axis_lines_in_order() {
        let s = glyph_segments(&[square()]).unwrap();
        let axes: Vec<_> = s.iter().map(|g| g.class).collect();
        assert_eq!(
            axes,
            vec![
                SegmentClass::Line { axis: LineAxis::Horizontal },
                SegmentClass::Line { axis: LineAxis::Vertical },
                SegmentClass::Line { axis: LineAxis::Horizontal },
                SegmentClass::Line { axis: LineAxis::Vertical },
            ]
        );
        for (i, g) in s.iter().enumerate() {
            assert_eq!((g.ring, g.span), (0, i));
        }
        for w in s.windows(2) { assert_eq!(w[0].end, w[1].start); }
        assert_eq!(s[3].end, s[0].start);
    }

    #[test]
    fn mixed_ring_classes_arc_and_oblique() {
        let r = ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![
                Span::Cubic { control_one: p(0.0, 5.0), control_two: p(5.0, 10.0), end: p(10.0, 10.0) },
                Span::Line { end: p(0.0, 0.0) },
            ],
        };
        let s = glyph_segments(&[r]).unwrap();
        assert_eq!(s.len(), 2);
        assert_eq!(
            s[0].class,
            SegmentClass::Arc { control_one: IntPoint { x: 0, y: 5 }, control_two: IntPoint { x: 5, y: 10 } }
        );
        assert_eq!(s[0].start, IntPoint { x: 0, y: 0 });
        assert_eq!(s[1].start, IntPoint { x: 10, y: 10 });
        assert_eq!(s[1].class, SegmentClass::Line { axis: LineAxis::Oblique });
    }

    #[test]
    fn multiple_rings_keep_ring_then_span_order_and_are_deterministic() {
        let mut inner = square();
        inner.start = p(2.0, 2.0);
        inner.spans = vec![
            Span::Line { end: p(2.0, 8.0) },
            Span::Line { end: p(8.0, 8.0) },
            Span::Line { end: p(2.0, 2.0) },
        ];
        let rings = [square(), inner];
        let a = glyph_segments(&rings).unwrap();
        let b = glyph_segments(&rings).unwrap();
        assert_eq!(a, b);
        let keys: Vec<_> = a.iter().map(|g| (g.ring, g.span)).collect();
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted);
        assert_eq!(a.len(), 7);
        assert_eq!(a[4].ring, 1);
    }

    #[test]
    fn negative_coordinates_and_degenerate_line() {
        let r = ReferenceRing {
            start: p(-3.0, -4.0),
            spans: vec![Span::Line { end: p(-3.0, -4.0) }, Span::Line { end: p(-7.0, -4.0) }],
        };
        let s = glyph_segments(&[r]).unwrap();
        assert_eq!(s[0].class, SegmentClass::Line { axis: LineAxis::Degenerate });
        assert_eq!(s[1].class, SegmentClass::Line { axis: LineAxis::Horizontal });
        assert_eq!(s[1].end, IntPoint { x: -7, y: -4 });
    }

    #[test]
    fn fractional_or_nonfinite_coordinate_is_refused_whole() {
        let mut r = square();
        r.spans[1] = Span::Line { end: p(10.5, 10.0) };
        assert_eq!(
            glyph_segments(&[r]),
            Err(SegmentError::NonIntegerCoordinate { ring: 0, span: Some(1) })
        );
        let mut r2 = square();
        r2.start = p(f64::NAN, 0.0);
        assert_eq!(
            glyph_segments(&[r2]),
            Err(SegmentError::NonIntegerCoordinate { ring: 0, span: None })
        );
        let mut r3 = square();
        r3.spans[0] = Span::Cubic { control_one: p(1.0, 0.0), control_two: p(f64::INFINITY, 0.0), end: p(10.0, 0.0) };
        assert!(glyph_segments(&[r3]).is_err());
    }

    #[test]
    fn empty_input_gives_empty_list() {
        assert_eq!(glyph_segments(&[]).unwrap(), vec![]);
    }
    #[test]
    fn metrics_square_four_corners_no_g1() {
        let m = segment_metrics(&[square()]);
        assert_eq!((m.line, m.cubic, m.g1, m.corner), (4, 0, 0, 4));
        assert_eq!(m.chord_len, 40.0);
    }

    #[test]
    fn metrics_smooth_cubic_ring() {
        // Two half-discs: tangents match at both joins.
        let r = ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![
                Span::Cubic { control_one: p(0.0, 6.0), control_two: p(10.0, 6.0), end: p(10.0, 0.0) },
                Span::Cubic { control_one: p(10.0, -6.0), control_two: p(0.0, -6.0), end: p(0.0, 0.0) },
            ],
        };
        let m = segment_metrics(&[r.clone()]);
        assert_eq!((m.line, m.cubic, m.g1, m.corner), (0, 2, 2, 0));
        assert_eq!(join_class(&r, 1), Some(JoinClass::G1));
        // Smooth: line into a cubic that leaves along the same direction.
        let s = ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![
                Span::Line { end: p(4.0, 0.0) },
                Span::Cubic { control_one: p(6.0, 0.0), control_two: p(8.0, 2.0), end: p(8.0, 4.0) },
                Span::Line { end: p(0.0, 0.0) },
            ],
        };
        assert_eq!(join_class(&s, 1), Some(JoinClass::G1));
        assert_eq!(join_class(&s, 0), Some(JoinClass::Corner));
        let m = segment_metrics(&[s]);
        assert_eq!((m.line, m.cubic), (2, 1));
        assert_eq!(m.g1 + m.corner, 3);
    }

    #[test]
    fn metrics_zero_tangent_is_corner() {
        let r = ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![Span::Line { end: p(0.0, 0.0) }, Span::Line { end: p(5.0, 0.0) }, Span::Line { end: p(0.0, 0.0) }],
        };
        assert_eq!(join_class(&r, 1), Some(JoinClass::Corner));
        let m = segment_metrics(&[r]);
        assert_eq!(m.g1, 0);
        assert_eq!(m.corner, 3);
    }

    #[test]
    fn metrics_empty_and_chord_len() {
        let m = segment_metrics(&[]);
        assert_eq!((m.line, m.cubic, m.g1, m.corner, m.chord_len), (0, 0, 0, 0, 0.0));
        let empty_ring = ReferenceRing { start: p(1.0, 1.0), spans: vec![] };
        assert_eq!(segment_metrics(&[empty_ring.clone()]), m);
        assert_eq!(join_class(&empty_ring, 0), None);
        let tri = ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![Span::Line { end: p(3.0, 4.0) }, Span::Line { end: p(3.0, 0.0) }, Span::Line { end: p(0.0, 0.0) }],
        };
        assert_eq!(segment_metrics(&[tri]).chord_len, 12.0);
    }
    #[test]
    fn receipt_row_shape_and_empty() {
        assert_eq!(receipt_row("g", &[]), None);
        assert_eq!(receipt_row("g", &[ReferenceRing { start: p(0.0, 0.0), spans: vec![] }]), None);
        let row = receipt_row("A", &[square()]).unwrap();
        assert_eq!(
            row,
            "glyph_segments\tA\tline\t4\tcubic\t0\tcubic_pct\t0.000000\tg1\t0\tcorner\t4\tcorner_per_node\t1.000000\tchord_len\t40.000000\tlen_per_node\t10.000000\n"
        );
        assert_eq!(row.trim_end_matches('\n').split('\t').count(), 18);
        assert_eq!(row, receipt_row("A", &[square()]).unwrap());
    }

}
