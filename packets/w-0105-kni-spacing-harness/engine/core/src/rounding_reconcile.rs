//! Reconciled rounding ledger (diagnostic recovery path).
//!
//! When `generated_native::rounding_ledger` refuses, the run no longer dies
//! with the diagnostic: each affected glyph's advance is re-derived from the
//! quantized identity components of its own measurements,
//!   advance = quantized(lsb) + quantized(ink) + quantized(rsb),
//! and the run continues with a typed `rounding_reconciled` warning on the
//! receipt. The reconciled ledger is diagnostic only; it never gates ink,
//! hull or export, and it never invents values: a glyph whose own
//! measurements cannot be derived is excluded from the reconciled rows and
//! named on the warning.

use crate::cff_container::CffGlyph;
use crate::generated_native::{GeneratedError, RoundingLedger, EXPORT_RESOLUTION};
use crate::ink_bounds;
use crate::native_font::NativeFontInput;
use crate::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

/// CONVENTION: quantization is independent round-half-away-from-zero to the
/// fixed export grid (`EXPORT_RESOLUTION`, resolution 1), the same rounding
/// the core export path applies to every scalar; each quantized component
/// then carries at most RESOLUTION/2 of error, so the re-derived advance
/// stays inside the ledger's declared 4*(RESOLUTION/2) identity bound.
pub fn quantize(v: f64) -> f64 {
    (v / EXPORT_RESOLUTION).round() * EXPORT_RESOLUTION
}

/// Typed outcome of `quantize_outline`: how many coordinates the export-grid
/// rounding moved, the largest single move, and how many non-finite
/// coordinates were left untouched for the downstream integer gate to refuse.
/// Nothing is silently dropped or clamped.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct QuantizeReport {
    pub coordinates: usize,
    pub moved: usize,
    pub max_abs_delta: f64,
    pub non_finite: usize,
}

/// Quantize every coordinate of a drawn glyph to the fixed export grid
/// (`quantize`, round half away from zero, resolution `EXPORT_RESOLUTION`),
/// the same per-scalar rounding the production export path applies inside
/// `prepare_generated_with_placement`. Non-finite coordinates are not
/// invented or clamped: they are counted and left in place so the integer
/// charstring gate still refuses them as typed rows. Range checking stays
/// with that gate as well; this pass only rounds.
pub fn quantize_outline(g: &mut DrawnGlyph) -> QuantizeReport {
    let mut report = QuantizeReport::default();
    let mut step = |p: &mut Point| {
        for v in [&mut p.x, &mut p.y] {
            report.coordinates += 1;
            if !v.is_finite() {
                report.non_finite += 1;
                continue;
            }
            let q = quantize(*v);
            let d = (q - *v).abs();
            if d > 0.0 {
                report.moved += 1;
                if d > report.max_abs_delta {
                    report.max_abs_delta = d;
                }
            }
            *v = q;
        }
    };
    for ring in &mut g.rings {
        step(&mut ring.start);
        for span in &mut ring.spans {
            match span {
                Span::Line { end } => step(end),
                Span::Cubic { control_one, control_two, end } => {
                    step(control_one);
                    step(control_two);
                    step(end);
                }
            }
        }
    }
    report
}

/// Re-derived advance from the quantized identity components.
pub fn reconciled_advance(lsb: f64, ink_width: f64, rsb: f64) -> f64 {
    quantize(lsb) + quantize(ink_width) + quantize(rsb)
}

/// Why a glyph is absent from the reconciled rows. Nothing is invented for
/// an excluded glyph; it is named on the warning instead.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReconcileExclusion {
    MissingMetric,
    InkBounds,
}

/// Typed warning with a stable code; rendered as one receipt line.
#[derive(Clone, Debug)]
pub struct ReconcileWarning {
    pub cause: String,
    pub reconciled_rows: usize,
    pub excluded: Vec<(String, ReconcileExclusion)>,
}

impl ReconcileWarning {
    pub fn code(&self) -> &'static str {
        "rounding_reconciled"
    }

    pub fn receipt_line(&self) -> String {
        let excluded = if self.excluded.is_empty() {
            "-".to_string()
        } else {
            self.excluded
                .iter()
                .map(|(id, why)| format!("{id}:{why:?}"))
                .collect::<Vec<_>>()
                .join(",")
        };
        format!(
            "{}\tcause\t{}\treconciled_rows\t{}\texcluded\t{}\tconvention\tadvance=quantized(lsb)+quantized(ink)+quantized(rsb) from the glyph's own measurements; diagnostic recovery, never a gate\n",
            self.code(),
            self.cause,
            self.reconciled_rows,
            excluded
        )
    }
}

/// Per-glyph reconciled ledger row. Every field is derived from the glyph's
/// own input geometry, its exported outline and its requested metric row;
/// `Err(exclusion)` means no honest row exists and the glyph is excluded.
fn reconcile_row(
    g: &DrawnGlyph,
    exported: &CffGlyph,
    exported_lsb: i16,
    metric: Option<&(String, f64, f64, f64)>,
) -> Result<RoundingLedger, ReconcileExclusion> {
    let row = metric.ok_or(ReconcileExclusion::MissingMetric)?;
    let in_bounds = ink_bounds::analytic_ink_bounds(g).map_err(|_| ReconcileExclusion::InkBounds)?;
    let ex_analytic =
        ink_bounds::analytic_ink_bounds(&exported.outline).map_err(|_| ReconcileExclusion::InkBounds)?;
    let ex_int =
        ink_bounds::integer_outward_bounds(&exported.outline).map_err(|_| ReconcileExclusion::InkBounds)?;
    let in_ink_w = in_bounds.map_or(0.0, |b| b[2] - b[0]);
    let in_xmin = in_bounds.map_or(row.1, |b| b[0]);
    let ex_xmin = ex_analytic.map_or(exported_lsb as f64, |b| b[0]);
    let mut xs = Vec::new();
    for ring in &exported.outline.rings {
        xs.push(ring.start.x);
        for span in &ring.spans {
            match span {
                crate::reference_slice::Span::Line { end } => xs.push(end.x),
                crate::reference_slice::Span::Cubic { control_one, control_two, end } => {
                    xs.extend([control_one.x, control_two.x, end.x])
                }
            }
        }
    }
    let hull_width = if xs.is_empty() {
        0.0
    } else {
        xs.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - xs.iter().copied().fold(f64::INFINITY, f64::min)
    };
    let advance = reconciled_advance(row.1, in_ink_w, row.2);
    Ok(RoundingLedger {
        glyph_id: g.glyph_id.clone(),
        input_identity_residual: row.1 + in_ink_w + row.2 - row.3,
        identity_rounding_bound: 4.0 * (EXPORT_RESOLUTION / 2.0),
        lsb_error: exported_lsb as f64 - row.1,
        rsb_error: quantize(row.2) - row.2,
        advance_error: advance - row.3,
        exported_control_hull_width: hull_width,
        measured_ink_width: in_ink_w,
        requested_lsb: row.1,
        actual_ink_lsb: ex_xmin,
        lsb_quantization: ex_xmin - row.1,
        exported_hull_rsb: advance - exported_lsb as f64 - hull_width,
        exported_ink_bounds_analytic: ex_analytic,
        exported_ink_bounds_int_outward: ex_int,
        quantized_input_ink_xmin: in_xmin,
        x_translation: ex_xmin - in_xmin,
    })
}

/// Reconcile the rounding ledger after a `rounding_ledger` refusal. Rows are
/// derived per glyph from its own measurements; glyphs that cannot supply an
/// honest row are excluded and named on the returned warning.
pub fn reconcile(
    input: &[DrawnGlyph],
    metrics: &[(String, f64, f64, f64)],
    prepared: &NativeFontInput,
    cause: &GeneratedError,
) -> (Vec<RoundingLedger>, ReconcileWarning) {
    let mut rows = Vec::new();
    let mut excluded = Vec::new();
    for (g, (exported, lsb)) in input
        .iter()
        .zip(prepared.glyphs.iter().zip(&prepared.left_side_bearings))
    {
        match reconcile_row(g, exported, *lsb, metrics.iter().find(|r| r.0 == g.glyph_id)) {
            Ok(row) => rows.push(row),
            Err(why) => excluded.push((g.glyph_id.clone(), why)),
        }
    }
    let warning = ReconcileWarning {
        cause: format!("{cause:?}"),
        reconciled_rows: rows.len(),
        excluded,
    };
    (rows, warning)
}

// ---------------------------------------------------------------------------
// Post-quantization constant-cubic cleanup (W2-2).
//
// `prepare_generated` rounds every exported point to the integer export grid
// (`EXPORT_RESOLUTION`, ties away from zero). A cubic whose start, both
// controls and end were distinct in binary64 but land on the same grid point
// is a zero-length span created by the integer rounding itself. The fit-stage
// repair (`generated_draw`) only sees binary64-exact equality, so nothing
// downstream catches it and the writer encodes six zero deltas. This pass
// removes exactly those spans, carrying the predicate of
// docs/engine/constant-cubic-removal-proposal.md to the repository's own
// export boundary:
//
// - only an explicit cubic with P0 == P1 == P2 == P3 after quantization
//   (exact grid equality, no epsilon);
// - lines, retracted handles and endpoint-only coincidences are kept;
// - surviving geometry is never re-rounded, rebuilt or reordered;
// - a removal never empties a ring: when every span of a ring is a constant
//   cubic the ring is kept whole and each span is named as held, because a
//   contour must not silently cease to exist;
// - every drop and every hold is a typed ledger row, never a silent drop.
//
// The pass changes no downstream operands: a constant cubic leaves the
// current point unchanged (P3 == P0), so the spans after it encode the same
// relative deltas.

/// One removed constant cubic, named by its original pre-deletion indices so
/// removing the first of two adjacent spans cannot renumber the second.
#[derive(Clone, Debug, PartialEq)]
pub struct ConstantCubicDrop {
    pub glyph_id: String,
    /// Ring index before any deletion.
    pub ring_index: usize,
    /// Span index inside that ring before any deletion.
    pub span_index: usize,
    /// The shared quantized point of the removed span.
    pub point: [f64; 2],
}

/// Why a constant cubic was kept.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConstantCubicHold {
    /// Removing it would leave the ring without spans.
    WouldEmptyRing,
}

/// A constant cubic the pass refused to remove, with its original indices.
#[derive(Clone, Debug, PartialEq)]
pub struct ConstantCubicHeld {
    pub glyph_id: String,
    pub ring_index: usize,
    pub span_index: usize,
    pub why: ConstantCubicHold,
}

/// Typed outcome of `drop_constant_cubics`; rendered as receipt lines.
#[derive(Clone, Debug, Default)]
pub struct ConstantCubicReport {
    pub dropped: Vec<ConstantCubicDrop>,
    pub held: Vec<ConstantCubicHeld>,
}

impl ConstantCubicReport {
    #[allow(dead_code)] // registry code for receipt validators; the export callsite consumes receipt_lines()
    pub fn code(&self) -> &'static str {
        "constant_cubic_cleanup"
    }

    pub fn receipt_lines(&self) -> String {
        let mut out = String::new();
        for d in &self.dropped {
            out.push_str(&format!(
                "constant_cubic_dropped\tglyph\t{}\tring\t{}\tspan\t{}\tx\t{}\ty\t{}\tconvention\tP0==P1==P2==P3 after round-half-away-from-zero to the export grid; no epsilon\n",
                d.glyph_id, d.ring_index, d.span_index, d.point[0], d.point[1]
            ));
        }
        for h in &self.held {
            out.push_str(&format!(
                "constant_cubic_held\tglyph\t{}\tring\t{}\tspan\t{}\twhy\t{:?}\n",
                h.glyph_id, h.ring_index, h.span_index, h.why
            ));
        }
        out
    }
}

/// The shared quantized point when span `i` of `ring` is a constant cubic
/// after integer rounding, else `None`. Lines never match. A non-finite
/// coordinate quantizes to a non-finite value that equals nothing, so
/// non-finite geometry is never removed here (ink bounds refuses it first).
fn constant_cubic_point(ring: &ReferenceRing, i: usize) -> Option<[f64; 2]> {
    let (control_one, control_two, end) = match &ring.spans[i] {
        Span::Cubic { control_one, control_two, end } => (control_one, control_two, end),
        Span::Line { .. } => return None,
    };
    let start: &Point = if i == 0 {
        &ring.start
    } else {
        match &ring.spans[i - 1] {
            Span::Line { end } => end,
            Span::Cubic { end, .. } => end,
        }
    };
    let q = |p: &Point| [quantize(p.x), quantize(p.y)];
    let p0 = q(start);
    if p0 == q(control_one) && p0 == q(control_two) && p0 == q(end) {
        Some(p0)
    } else {
        None
    }
}

/// Remove every post-quantization constant cubic from the exported outlines.
/// Marks are computed against the original spans before any deletion, so the
/// ledger always names original indices. Returns the typed report.
pub fn drop_constant_cubics(glyphs: &mut [CffGlyph]) -> ConstantCubicReport {
    let mut report = ConstantCubicReport::default();
    for g in glyphs.iter_mut() {
        for (ring_index, ring) in g.outline.rings.iter_mut().enumerate() {
            let marks: Vec<Option<[f64; 2]>> =
                (0..ring.spans.len()).map(|i| constant_cubic_point(ring, i)).collect();
            let marked = marks.iter().flatten().count();
            if marked == 0 {
                continue;
            }
            if marked == ring.spans.len() {
                for (i, _) in marks.iter().enumerate().filter(|(_, m)| m.is_some()) {
                    report.held.push(ConstantCubicHeld {
                        glyph_id: g.name.clone(),
                        ring_index,
                        span_index: i,
                        why: ConstantCubicHold::WouldEmptyRing,
                    });
                }
                continue;
            }
            let old = std::mem::take(&mut ring.spans);
            let mut kept = Vec::with_capacity(old.len() - marked);
            for (i, span) in old.into_iter().enumerate() {
                match marks[i] {
                    Some(point) => report.dropped.push(ConstantCubicDrop {
                        glyph_id: g.name.clone(),
                        ring_index,
                        span_index: i,
                        point,
                    }),
                    None => kept.push(span),
                }
            }
            ring.spans = kept;
        }
    }
    report
}

// ---------------------------------------------------------------------------
// Post-quantization zero-length LINE cleanup.
//
// Companion of `drop_constant_cubics`: a line whose end quantizes to the
// grid point it starts from is a zero-length span created by integer
// rounding (the writer would encode it as `0 0 rlineto`). Same convention:
// exact grid equality after round-half-away-from-zero, no epsilon. Cubics are
// never touched here (a cubic with distinct controls is a real curve). A
// removal never empties a ring (held, typed row), surviving geometry is not
// re-rounded or reordered, and removing a span that leaves the current
// point unchanged cannot change any later relative delta.

/// One removed zero-length line, by original pre-deletion indices.
#[derive(Clone, Debug, PartialEq)]
pub struct ZeroLengthLineDrop {
    pub glyph_id: String,
    pub ring_index: usize,
    pub span_index: usize,
    pub point: [f64; 2],
}

/// A zero-length line kept because every span of its ring is one.
#[derive(Clone, Debug, PartialEq)]
pub struct ZeroLengthLineHeld {
    pub glyph_id: String,
    pub ring_index: usize,
    pub span_index: usize,
}

/// Typed outcome of `drop_zero_length_lines`.
#[derive(Clone, Debug, Default)]
pub struct ZeroLengthLineReport {
    pub dropped: Vec<ZeroLengthLineDrop>,
    pub held: Vec<ZeroLengthLineHeld>,
}

impl ZeroLengthLineReport {
    pub fn code(&self) -> &'static str {
        "zero_length_line_cleanup"
    }

    pub fn receipt_lines(&self) -> String {
        let mut out = String::new();
        for d in &self.dropped {
            out.push_str(&format!(
                "zero_length_line_dropped\tglyph\t{}\tring\t{}\tspan\t{}\tx\t{}\ty\t{}\tconvention\tend==start after round-half-away-from-zero to the export grid; no epsilon\n",
                d.glyph_id, d.ring_index, d.span_index, d.point[0], d.point[1]
            ));
        }
        for h in &self.held {
            out.push_str(&format!(
                "zero_length_line_held\tglyph\t{}\tring\t{}\tspan\t{}\twhy\tWouldEmptyRing\n",
                h.glyph_id, h.ring_index, h.span_index
            ));
        }
        out
    }
}

fn zero_length_line_point(ring: &ReferenceRing, i: usize) -> Option<[f64; 2]> {
    let end = match &ring.spans[i] {
        Span::Line { end } => end,
        Span::Cubic { .. } => return None,
    };
    let start: &Point = if i == 0 {
        &ring.start
    } else {
        match &ring.spans[i - 1] {
            Span::Line { end } => end,
            Span::Cubic { end, .. } => end,
        }
    };
    let q = |p: &Point| [quantize(p.x), quantize(p.y)];
    let p0 = q(start);
    if p0 == q(end) {
        Some(p0)
    } else {
        None
    }
}

/// Remove every post-quantization zero-length line. Run after
/// `drop_constant_cubics` (a removed constant cubic can expose no new
/// zero-length line, since it leaves the current point unchanged).
pub fn drop_zero_length_lines(glyphs: &mut [CffGlyph]) -> ZeroLengthLineReport {
    let mut report = ZeroLengthLineReport::default();
    for g in glyphs.iter_mut() {
        for (ring_index, ring) in g.outline.rings.iter_mut().enumerate() {
            let marks: Vec<Option<[f64; 2]>> =
                (0..ring.spans.len()).map(|i| zero_length_line_point(ring, i)).collect();
            let marked = marks.iter().flatten().count();
            if marked == 0 {
                continue;
            }
            if marked == ring.spans.len() {
                for (i, _) in marks.iter().enumerate().filter(|(_, m)| m.is_some()) {
                    report.held.push(ZeroLengthLineHeld {
                        glyph_id: g.name.clone(),
                        ring_index,
                        span_index: i,
                    });
                }
                continue;
            }
            let old = std::mem::take(&mut ring.spans);
            let mut kept = Vec::with_capacity(old.len() - marked);
            for (i, span) in old.into_iter().enumerate() {
                match marks[i] {
                    Some(point) => report.dropped.push(ZeroLengthLineDrop {
                        glyph_id: g.name.clone(),
                        ring_index,
                        span_index: i,
                        point,
                    }),
                    None => kept.push(span),
                }
            }
            ring.spans = kept;
        }
    }
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::reference_slice::{Point, ReferenceRing, Span};

    fn p(x: f64, y: f64) -> Point {
        Point { x, y }
    }

    /// Axis-aligned rectangle from (x0, y0) to (x1, y1), single closed ring.
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

    fn cff(id: &str, advance: u16, outline: DrawnGlyph) -> CffGlyph {
        CffGlyph { name: id.to_string(), advance, outline }
    }

    #[test]
    fn quantize_rounds_half_away_from_zero() {
        assert_eq!(quantize(20.49), 20.0);
        assert_eq!(quantize(20.5), 21.0);
        assert_eq!(quantize(-0.5), -1.0);
        assert_eq!(quantize(-20.49), -20.0);
        assert_eq!(quantize(0.0), 0.0);
    }

    #[test]
    fn reconciled_advance_sums_quantized_components() {
        // 20 + 100 + 30; unquantized sum would be 150.89.
        assert_eq!(reconciled_advance(20.49, 100.0, 30.4), 150.0);
        assert_eq!(reconciled_advance(-1.0, 0.0, 0.0), -1.0);
    }

    #[test]
    fn row_is_derived_from_the_glyphs_own_measurements() {
        // Ink 20..220 => width 200; requested lsb 20.49, rsb 30.4, advance 999.
        let g = rect("A", 20.0, 0.0, 220.0, 700.0);
        let e = cff("A", 999, rect("A", 20.0, 0.0, 220.0, 700.0));
        let metric = ("A".to_string(), 20.49, 30.4, 999.0);
        let row = reconcile_row(&g, &e, 20, Some(&metric)).expect("honest row");
        // advance = q(20.49) + q(200) + q(30.4) = 20 + 200 + 30 = 250.
        assert_eq!(row.advance_error, 250.0 - 999.0);
        assert_eq!(row.exported_hull_rsb, 250.0 - 20.0 - 200.0);
        assert_eq!(row.measured_ink_width, 200.0);
        assert_eq!(row.input_identity_residual, 20.49 + 200.0 + 30.4 - 999.0);
        assert_eq!(row.x_translation, 0.0);
        assert_eq!(row.actual_ink_lsb, 20.0);
        assert_eq!(row.lsb_quantization, 20.0 - 20.49);
        assert_eq!(row.exported_ink_bounds_int_outward, Some([20, 0, 220, 700]));
        assert_eq!(row.identity_rounding_bound, 2.0);
    }

    #[test]
    fn translated_export_measures_its_own_translation() {
        let g = rect("B", 0.0, 0.0, 200.0, 700.0);
        let e = cff("B", 250, rect("B", 20.0, 0.0, 220.0, 700.0));
        let metric = ("B".to_string(), 20.0, 30.0, 250.0);
        let row = reconcile_row(&g, &e, 20, Some(&metric)).expect("honest row");
        assert_eq!(row.x_translation, 20.0);
        assert_eq!(row.quantized_input_ink_xmin, 0.0);
        assert_eq!(row.actual_ink_lsb, 20.0);
    }

    #[test]
    fn empty_ink_glyph_reconciles_with_zero_ink() {
        let g = DrawnGlyph { glyph_id: "space".to_string(), rings: Vec::new() };
        let e = cff("space", 250, DrawnGlyph { glyph_id: "space".to_string(), rings: Vec::new() });
        let metric = ("space".to_string(), 0.0, 0.0, 250.0);
        let row = reconcile_row(&g, &e, 0, Some(&metric)).expect("honest row");
        assert_eq!(row.measured_ink_width, 0.0);
        assert_eq!(row.exported_ink_bounds_analytic, None);
        assert_eq!(row.advance_error, 0.0 - 250.0);
    }

    #[test]
    fn missing_metric_excludes_the_glyph() {
        let g = rect("C", 0.0, 0.0, 10.0, 10.0);
        let e = cff("C", 10, rect("C", 0.0, 0.0, 10.0, 10.0));
        assert_eq!(
            reconcile_row(&g, &e, 0, None).unwrap_err(),
            ReconcileExclusion::MissingMetric
        );
    }

    #[test]
    fn non_finite_geometry_excludes_the_glyph() {
        let g = rect("D", f64::NAN, 0.0, 10.0, 10.0);
        let e = cff("D", 10, rect("D", 0.0, 0.0, 10.0, 10.0));
        let metric = ("D".to_string(), 0.0, 0.0, 10.0);
        assert_eq!(
            reconcile_row(&g, &e, 0, Some(&metric)).unwrap_err(),
            ReconcileExclusion::InkBounds
        );
    }

    #[test]
    fn warning_code_is_stable_and_line_names_exclusions() {
        let w = ReconcileWarning {
            cause: "MissingMetric(\"C\")".to_string(),
            reconciled_rows: 2,
            excluded: vec![("C".to_string(), ReconcileExclusion::MissingMetric)],
        };
        assert_eq!(w.code(), "rounding_reconciled");
        let line = w.receipt_line();
        assert!(line.starts_with("rounding_reconciled\t"));
        assert!(line.contains("C:MissingMetric"));
        assert!(line.contains("reconciled_rows\t2"));
        assert!(line.ends_with('\n'));
    }
    // ------------------------------------------------------------------
    // W2-2: post-quantization constant-cubic cleanup.

    use crate::cff_container::{charstring, cff_one};

    /// End point of a span (the next span's start in this outline model).
    fn span_end(s: &Span) -> Point {
        match s {
            Span::Line { end } => *end,
            Span::Cubic { end, .. } => *end,
        }
    }

    /// Bit-exact span comparison (discriminant and every coordinate).
    fn span_bits(s: &Span) -> (u8, Vec<u64>) {
        match s {
            Span::Line { end } => (0, vec![end.x.to_bits(), end.y.to_bits()]),
            Span::Cubic { control_one, control_two, end } => (
                1,
                vec![
                    control_one.x.to_bits(),
                    control_one.y.to_bits(),
                    control_two.x.to_bits(),
                    control_two.y.to_bits(),
                    end.x.to_bits(),
                    end.y.to_bits(),
                ],
            ),
        }
    }

    /// Closed ring of `n` integer-coordinate line spans on a circle.
    /// Adjacent quantized points are always many units apart, so nothing in
    /// the ring collapses under rounding by accident.
    fn line_loop(n: usize, cx: f64, cy: f64, r: f64) -> ReferenceRing {
        assert!(n >= 3);
        let start = p((cx + r).round(), cy.round());
        let mut spans = Vec::new();
        for k in 1..n {
            let a = std::f64::consts::TAU * k as f64 / n as f64;
            spans.push(Span::Line { end: p((cx + r * a.cos()).round(), (cy + r * a.sin()).round()) });
        }
        spans.push(Span::Line { end: start });
        ReferenceRing { start, spans }
    }

    /// A cubic that is NOT constant in binary64 but whose four points all
    /// quantize to the integer grid point `q` (every offset < 0.5).
    fn const_cubic(q: Point) -> Span {
        Span::Cubic {
            control_one: p(q.x + 0.21, q.y - 0.17),
            control_two: p(q.x - 0.3, q.y + 0.28),
            end: p(q.x + 0.12, q.y + 0.05),
        }
    }

    /// Replace span `at` of `ring` with a constant cubic anchored on the
    /// quantized end of the previous span (the ring start for span 0).
    fn plant_constant(ring: &mut ReferenceRing, at: usize) {
        let prev = if at == 0 { ring.start } else { span_end(&ring.spans[at - 1]) };
        ring.spans[at] = const_cubic(prev);
    }

    /// Current state, measured: integer rounding CREATES zero-length spans.
    /// The cubic below is not constant in binary64, so the fit-stage repair
    /// (exact-equality, `generated_draw::degenerate_spans`) cannot see it;
    /// after quantization to the export grid it IS constant, and without
    /// this pass the writer ships it as six zero deltas + rrcurveto.
    #[test]
    fn integer_rounding_creates_constant_cubics_and_today_they_ship() {
        let sub_unit = Span::Cubic {
            control_one: p(200.21, 100.13),
            control_two: p(199.83, 100.34),
            end: p(200.12, 99.91),
        };
        let pre_quant = ReferenceRing {
            start: p(100.0, 100.0),
            spans: vec![
                Span::Line { end: p(200.0, 100.0) },
                sub_unit,
                Span::Line { end: p(200.0, 200.0) },
                Span::Line { end: p(100.0, 200.0) },
                Span::Line { end: p(100.0, 100.0) },
            ],
        };
        // Distinct in binary64: the exact-equality repair sees nothing.
        assert_eq!(crate::generated_draw::degenerate_spans(&[pre_quant.clone()]), 0);
        // ...but every point of the cubic quantizes to (200, 100).
        assert_eq!(quantize(200.21), 200.0);
        assert_eq!(quantize(199.83), 200.0);
        assert_eq!(quantize(200.12), 200.0);
        assert_eq!(quantize(99.91), 100.0);
        // The exported (already integer) outline therefore holds a constant
        // cubic; today the writer encodes it as six zero deltas + rrcurveto.
        let g = cff(
            "G",
            300,
            DrawnGlyph {
                glyph_id: "G".to_string(),
                rings: vec![ReferenceRing {
                    start: p(100.0, 100.0),
                    spans: vec![
                        Span::Line { end: p(200.0, 100.0) },
                        Span::Cubic { control_one: p(200.0, 100.0), control_two: p(200.0, 100.0), end: p(200.0, 100.0) },
                        Span::Line { end: p(200.0, 200.0) },
                        Span::Line { end: p(100.0, 200.0) },
                        Span::Line { end: p(100.0, 100.0) },
                    ],
                }],
            },
        );
        let zero_rrcurveto: [u8; 19] = [28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 8];
        assert!(
            charstring(&g).expect("encode").windows(19).any(|w| w == zero_rrcurveto),
            "current writer ships the constant cubic as six zero deltas"
        );
        // The pass removes exactly that span; the encoding then equals the
        // encoding of the glyph that never had it.
        let mut cleaned = vec![g.clone()];
        let report = drop_constant_cubics(&mut cleaned);
        assert_eq!(report.dropped.len(), 1);
        assert_eq!(report.dropped[0].point, [200.0, 100.0]);
        let never = cff(
            "G",
            300,
            DrawnGlyph {
                glyph_id: "G".to_string(),
                rings: vec![ReferenceRing {
                    start: p(100.0, 100.0),
                    spans: vec![
                        Span::Line { end: p(200.0, 100.0) },
                        Span::Line { end: p(200.0, 200.0) },
                        Span::Line { end: p(100.0, 200.0) },
                        Span::Line { end: p(100.0, 100.0) },
                    ],
                }],
            },
        );
        assert_eq!(charstring(&cleaned[0]).unwrap(), charstring(&never).unwrap());
    }

    /// The pinned W2 acceptance set (docs/engine/constant-cubic-removal-proposal.md):
    /// seven constant cubics in six glyphs at their original decoded
    /// contour/span indices. Distractor spans (retracted handles,
    /// endpoint-only coincidence) must survive.
    #[test]
    fn w2_acceptance_set_drops_exactly_the_seven_pinned_spans() {
        // seven / U+0037: contour 0, span 4; distractors at spans 1 and 2.
        let mut seven_ring = line_loop(6, 1000.0, 1000.0, 400.0);
        let e0 = span_end(&seven_ring.spans[0]);
        let e1 = span_end(&seven_ring.spans[1]);
        // retracted handles: c1 == P0, c2 == P3, a real curve -> keep.
        seven_ring.spans[1] = Span::Cubic { control_one: e0, control_two: e1, end: e1 };
        // endpoint-only coincidence: end == P0, controls elsewhere -> keep.
        seven_ring.spans[2] =
            Span::Cubic { control_one: p(e1.x + 50.0, e1.y), control_two: p(e1.x + 90.0, e1.y + 40.0), end: e0 };
        plant_constant(&mut seven_ring, 4);
        // uni00D1: contour 1, span 14.
        let mut d1_ring = line_loop(16, 2000.0, 1000.0, 400.0);
        plant_constant(&mut d1_ring, 14);
        // uni00D5: contour 2, span 1.
        let mut d5_ring = line_loop(3, 3000.0, 1000.0, 400.0);
        plant_constant(&mut d5_ring, 1);
        // uni02DC: contour 0, spans 18 and 19 (adjacent).
        let mut tilde_ring = line_loop(21, 4000.0, 1000.0, 400.0);
        plant_constant(&mut tilde_ring, 18);
        plant_constant(&mut tilde_ring, 19);
        // uni00A3: contour 0, span 31.
        let mut pound_ring = line_loop(33, 5000.0, 1000.0, 400.0);
        plant_constant(&mut pound_ring, 31);
        // uni2206: contour 0, span 6.
        let mut increment_ring = line_loop(8, 6000.0, 1000.0, 400.0);
        plant_constant(&mut increment_ring, 6);

        let glyphs = vec![
            cff("seven", 500, DrawnGlyph { glyph_id: "seven".to_string(), rings: vec![seven_ring] }),
            cff(
                "uni00D1",
                600,
                DrawnGlyph {
                    glyph_id: "uni00D1".to_string(),
                    rings: vec![line_loop(3, 1500.0, 3000.0, 300.0), d1_ring],
                },
            ),
            cff(
                "uni00D5",
                600,
                DrawnGlyph {
                    glyph_id: "uni00D5".to_string(),
                    rings: vec![line_loop(3, 2500.0, 3000.0, 300.0), line_loop(4, 2600.0, 3100.0, 200.0), d5_ring],
                },
            ),
            cff("uni02DC", 400, DrawnGlyph { glyph_id: "uni02DC".to_string(), rings: vec![tilde_ring] }),
            cff("uni00A3", 550, DrawnGlyph { glyph_id: "uni00A3".to_string(), rings: vec![pound_ring] }),
            cff("uni2206", 700, DrawnGlyph { glyph_id: "uni2206".to_string(), rings: vec![increment_ring] }),
        ];
        let before: Vec<CffGlyph> = glyphs.clone();
        let before_total: usize = glyphs.iter().flat_map(|g| g.outline.rings.iter()).map(|r| r.spans.len()).sum();
        assert_eq!(before_total, 6 + 19 + 10 + 21 + 33 + 8);

        let mut cleaned = glyphs;
        let report = drop_constant_cubics(&mut cleaned);

        // Exactly the seven pinned spans, original indices, in pass order.
        let got: Vec<(&str, usize, usize)> =
            report.dropped.iter().map(|d| (d.glyph_id.as_str(), d.ring_index, d.span_index)).collect();
        assert_eq!(
            got,
            vec![
                ("seven", 0, 4),
                ("uni00D1", 1, 14),
                ("uni00D5", 2, 1),
                ("uni02DC", 0, 18),
                ("uni02DC", 0, 19),
                ("uni00A3", 0, 31),
                ("uni2206", 0, 6),
            ]
        );
        assert!(report.held.is_empty());

        // Ring count unchanged; totals drop by exactly seven; every survivor
        // is bit-for-bit the original span in the original order.
        for (b, a) in before.iter().zip(cleaned.iter()) {
            assert_eq!(b.outline.rings.len(), a.outline.rings.len());
            assert_eq!(b.name, a.name);
            assert_eq!(b.advance, a.advance);
        }
        let after_total: usize = cleaned.iter().flat_map(|g| g.outline.rings.iter()).map(|r| r.spans.len()).sum();
        assert_eq!(after_total, before_total - 7);
        for (b, a) in before.iter().zip(cleaned.iter()) {
            for (ri, (rb, ra)) in b.outline.rings.iter().zip(a.outline.rings.iter()).enumerate() {
                assert_eq!(rb.start.x.to_bits(), ra.start.x.to_bits(), "ring starts are never rewritten");
                assert_eq!(rb.start.y.to_bits(), ra.start.y.to_bits());
                let dropped: std::collections::BTreeSet<usize> = report
                    .dropped
                    .iter()
                    .filter(|d| d.glyph_id == b.name && d.ring_index == ri)
                    .map(|d| d.span_index)
                    .collect();
                let survivors: Vec<&Span> =
                    rb.spans.iter().enumerate().filter(|(i, _)| !dropped.contains(i)).map(|(_, s)| s).collect();
                assert_eq!(survivors.len(), ra.spans.len());
                for (x, y) in survivors.iter().zip(ra.spans.iter()) {
                    assert_eq!(span_bits(x), span_bits(y), "surviving span rewritten");
                }
            }
        }

        // Before/after outline evidence for the seven spans (captured with
        // `cargo test -- --nocapture` into the delivery evidence file).
        for d in &report.dropped {
            let rb = &before.iter().find(|g| g.name == d.glyph_id).unwrap().outline.rings[d.ring_index];
            let ra = &cleaned.iter().find(|g| g.name == d.glyph_id).unwrap().outline.rings[d.ring_index];
            println!(
                "EVIDENCE\t{}\tring {}\tspan {}\tpoint ({}, {})\tspans {} -> {}",
                d.glyph_id, d.ring_index, d.span_index, d.point[0], d.point[1], rb.spans.len(), ra.spans.len()
            );
            println!("EVIDENCE\t{}\tremoved span {}: {:?}", d.glyph_id, d.span_index, rb.spans[d.span_index]);
        }
        println!("EVIDENCE\ttotal explicit spans: {} -> {}", before_total, after_total);
        print!("{}", report.receipt_lines());
    }

    /// Retracted handles and endpoint-only coincidences are real curves and
    /// stay; a zero-length LINE is outside this pass's predicate.
    #[test]
    fn non_constant_spans_survive() {
        let mut ring = line_loop(4, 1000.0, 1000.0, 400.0);
        let e0 = span_end(&ring.spans[0]);
        let e1 = span_end(&ring.spans[1]);
        ring.spans[1] = Span::Cubic { control_one: e0, control_two: e1, end: e1 }; // retracted handles
        ring.spans[2] = Span::Line { end: e1 }; // zero-length line (P0 == end)
        let mut glyphs = vec![cff("K", 500, DrawnGlyph { glyph_id: "K".to_string(), rings: vec![ring] })];
        let before = glyphs.clone();
        let report = drop_constant_cubics(&mut glyphs);
        assert!(report.dropped.is_empty() && report.held.is_empty());
        for (x, y) in before[0].outline.rings[0].spans.iter().zip(glyphs[0].outline.rings[0].spans.iter()) {
            assert_eq!(span_bits(x), span_bits(y));
        }
    }

    /// A removal never empties a ring: the contour is kept whole and every
    /// span of it is named as held; nothing is dropped.
    #[test]
    fn ring_that_would_empty_is_held_not_dropped() {
        let start = p(100.0, 100.0);
        let ring = ReferenceRing { start, spans: vec![const_cubic(start), const_cubic(start)] };
        let mut glyphs = vec![cff("S", 500, DrawnGlyph { glyph_id: "S".to_string(), rings: vec![ring] })];
        let report = drop_constant_cubics(&mut glyphs);
        assert!(report.dropped.is_empty());
        assert_eq!(report.held.len(), 2);
        assert!(report.held.iter().all(|h| h.why == ConstantCubicHold::WouldEmptyRing));
        assert_eq!(report.held[0].span_index, 0);
        assert_eq!(report.held[1].span_index, 1);
        assert_eq!(glyphs[0].outline.rings[0].spans.len(), 2, "held spans stay put");
    }

    /// The predicate is exact grid equality after round-half-away-from-zero:
    /// a control point 0.51 across the half-unit boundary lands in the next
    /// cell and the cubic survives.
    #[test]
    fn predicate_is_exact_grid_equality_at_cell_boundaries() {
        let mut ring = line_loop(4, 1000.0, 1000.0, 400.0);
        let p0 = span_end(&ring.spans[0]); // integer point (line_loop rounds)
        assert_eq!(p0.x.fract(), 0.0);
        ring.spans[1] = Span::Cubic { control_one: p(p0.x + 0.51, p0.y), control_two: p0, end: p0 };
        let mut glyphs = vec![cff("B", 500, DrawnGlyph { glyph_id: "B".to_string(), rings: vec![ring] })];
        let report = drop_constant_cubics(&mut glyphs);
        assert!(report.dropped.is_empty(), "0.51 across the half-unit boundary rounds to the next cell");
        assert!(report.held.is_empty());
    }

    /// Off-target bit-identity: a font without constant cubics encodes
    /// byte-identically across the pass; when one glyph is cleaned, every
    /// other glyph's charstring stays byte-identical.
    #[test]
    fn unaffected_glyphs_are_bit_identical() {
        let clean = vec![
            cff(".notdef", 500, rect(".notdef", 0.0, 0.0, 100.0, 700.0)),
            cff("A", 600, rect("A", 20.0, 0.0, 220.0, 700.0)),
            cff("B", 600, rect("B", 30.0, 0.0, 230.0, 700.0)),
        ];
        let before_bytes = cff_one("KNITest-Regular", &clean).expect("encode");
        let mut untouched = clean.clone();
        let report = drop_constant_cubics(&mut untouched);
        assert!(report.dropped.is_empty() && report.held.is_empty());
        assert_eq!(before_bytes, cff_one("KNITest-Regular", &untouched).unwrap());

        // Plant a constant cubic in glyph A only.
        let mut dirty = clean.clone();
        dirty[1].outline.rings[0].spans.insert(1, const_cubic(p(220.0, 0.0)));
        let raw0 = charstring(&dirty[0]).unwrap();
        let raw2 = charstring(&dirty[2]).unwrap();
        let report = drop_constant_cubics(&mut dirty);
        assert_eq!(report.dropped.len(), 1);
        assert_eq!(charstring(&dirty[0]).unwrap(), raw0, "glyph .notdef byte-identical");
        assert_eq!(charstring(&dirty[2]).unwrap(), raw2, "glyph B byte-identical");
        // A's cleaned charstring equals the glyph that never had the cubic.
        assert_eq!(charstring(&dirty[1]).unwrap(), charstring(&clean[1]).unwrap());
    }

    /// The ledger is typed and stable: stable code, one line per drop and
    /// per held span, original indices, the shared point, the convention.
    #[test]
    fn cleanup_ledger_lines_are_typed_and_stable() {
        let mut ring = line_loop(4, 1000.0, 1000.0, 400.0);
        plant_constant(&mut ring, 2);
        let single = ReferenceRing { start: p(5.0, 5.0), spans: vec![const_cubic(p(5.0, 5.0))] };
        let mut glyphs = vec![
            cff("G1", 500, DrawnGlyph { glyph_id: "G1".to_string(), rings: vec![ring] }),
            cff("G2", 500, DrawnGlyph { glyph_id: "G2".to_string(), rings: vec![single] }),
        ];
        let report = drop_constant_cubics(&mut glyphs);
        assert_eq!(report.code(), "constant_cubic_cleanup");
        let lines = report.receipt_lines();
        let drop_line = lines.lines().find(|l| l.starts_with("constant_cubic_dropped\t")).expect("drop line");
        assert!(drop_line.contains("glyph\tG1"));
        assert!(drop_line.contains("ring\t0"));
        assert!(drop_line.contains("span\t2"));
        assert!(drop_line.contains("convention\tP0==P1==P2==P3"));
        let held_line = lines.lines().find(|l| l.starts_with("constant_cubic_held\t")).expect("held line");
        assert!(held_line.contains("glyph\tG2"));
        assert!(held_line.contains("why\tWouldEmptyRing"));
        assert!(lines.ends_with('\n'));
    }

    /// Zero-length lines created by rounding are dropped with typed rows;
    /// distinct lines and cubics survive; indices are original.
    #[test]
    fn zero_length_lines_after_rounding_are_dropped() {
        let mut ring = line_loop(6, 1000.0, 1000.0, 400.0);
        let e1 = span_end(&ring.spans[1]);
        // sub-grid line: 0.4 away rounds onto the start point
        ring.spans[2] = Span::Line { end: p(e1.x + 0.4, e1.y - 0.4) };
        // exact zero-length line right after it
        ring.spans[3] = Span::Line { end: p(e1.x + 0.4, e1.y - 0.4) };
        let before = ring.spans.len();
        let mut glyphs = vec![cff("Z", 500, DrawnGlyph { glyph_id: "Z".to_string(), rings: vec![ring] })];
        let report = drop_zero_length_lines(&mut glyphs);
        assert_eq!(report.dropped.len(), 2);
        assert_eq!(report.dropped[0].span_index, 2);
        assert_eq!(report.dropped[1].span_index, 3);
        assert_eq!(glyphs[0].outline.rings[0].spans.len(), before - 2);
        assert!(report.receipt_lines().starts_with("zero_length_line_dropped\tglyph\tZ\tring\t0\tspan\t2"));
    }

    /// Cubics (even retracted) and non-zero lines are never touched; a
    /// ring made only of zero-length lines is held, not emptied; a clean
    /// font encodes byte-identically across the pass.
    #[test]
    fn zero_length_line_pass_is_narrow() {
        let start = p(100.0, 100.0);
        let ring = ReferenceRing { start, spans: vec![Span::Line { end: start }, Span::Line { end: p(100.2, 99.8) }] };
        let mut glyphs = vec![cff("H", 500, DrawnGlyph { glyph_id: "H".to_string(), rings: vec![ring] })];
        let report = drop_zero_length_lines(&mut glyphs);
        assert!(report.dropped.is_empty());
        assert_eq!(report.held.len(), 2);
        assert_eq!(glyphs[0].outline.rings[0].spans.len(), 2);

        let mut ring = line_loop(4, 1000.0, 1000.0, 400.0);
        plant_constant(&mut ring, 1);
        let mut cc = vec![cff("C", 500, DrawnGlyph { glyph_id: "C".to_string(), rings: vec![ring] })];
        let before = cc.clone();
        let r = drop_zero_length_lines(&mut cc);
        assert!(r.dropped.is_empty() && r.held.is_empty(), "constant cubics belong to the other pass");
        for (x, y) in before[0].outline.rings[0].spans.iter().zip(cc[0].outline.rings[0].spans.iter()) {
            assert_eq!(span_bits(x), span_bits(y));
        }

        let clean = vec![
            cff(".notdef", 500, rect(".notdef", 0.0, 0.0, 100.0, 700.0)),
            cff("A", 600, rect("A", 20.0, 0.0, 220.0, 700.0)),
        ];
        let b = cff_one("T-Regular", &clean).expect("encode");
        let mut again = clean.clone();
        assert!(drop_zero_length_lines(&mut again).dropped.is_empty());
        assert_eq!(b, cff_one("T-Regular", &again).unwrap());
    }

    /// The writer ships a zero-length line as `0 0 rlineto`; after the pass
    /// that operand pair is gone and the cleaned charstring equals the one
    /// of the outline that never had the span.
    #[test]
    fn cleaned_charstring_equals_never_had_it() {
        let clean = cff("A", 600, rect("A", 20.0, 0.0, 220.0, 700.0));
        let mut dirty = clean.clone();
        let e = span_end(&dirty.outline.rings[0].spans[0]);
        dirty.outline.rings[0].spans.insert(1, Span::Line { end: e });
        assert_ne!(charstring(&dirty).unwrap(), charstring(&clean).unwrap());
        let mut v = vec![dirty];
        assert_eq!(drop_zero_length_lines(&mut v).dropped.len(), 1);
        assert_eq!(charstring(&v[0]).unwrap(), charstring(&clean).unwrap());
    }

}
